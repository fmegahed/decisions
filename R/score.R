# The tuning hooks: score a setup on labeled learning rows (score_setup()),
# and score the test rows one time only (evaluate_once()).

#' Score a setup on labeled rows
#'
#' Runs `decide()` with a setup on inputs whose true answers you know, and
#' scores the probabilities with the area under the ROC curve. Use it to
#' compare candidate setups (descriptions, instructions, references) on the
#' learning rows. A person or an agent reads the `estimate` of each setup and
#' keeps the best.
#'
#' @param setup A setup from `decision_setup()` or `read_setup()` with one
#'   question.
#' @param text,image The inputs, as in `decide()`.
#' @param truth A factor or character vector with the true answer of each
#'   input. It has the length of the inputs, and its values are answers of
#'   the question.
#' @param role `NULL` (the default, no check), or a vector with one value per
#'   input: `"learning"`, `"calibration"` or `"test"`. `score_setup()` stops
#'   before any request when a value is `"test"`: score the test rows one
#'   time, with `evaluate_once()`.
#' @param metric The metric. This release has `"roc_auc"` only. For another
#'   metric, compute it from the `answers` column of the result with
#'   yardstick.
#' @param event The answer that counts as the event (the positive class) of
#'   the AUC. `NULL` (the default) gives `"true"` for a noul question and
#'   the second answer for a question with two answers (for
#'   `c(normal = ..., defective = ...)`, `"defective"`). With three or more
#'   answers, `event` is required.
#' @param path `NULL`, or a state file for `decide()` (see `path` in
#'   `decide()`). A new call with the same `path` sends only the inputs that
#'   the file does not hold.
#' @return A one-row tibble:
#'   * `metric` and `estimate`: the metric and its value. `estimate` is `NA`
#'     with a warning when fewer than one row of each class remains.
#'   * `n`: the number of rows in the AUC.
#'   * `calls`: the number of requests that this call sent (0 for inputs
#'     read from `path`).
#'   * `input_tokens`: the sum of the input tokens.
#'   * `cost`: the sum of the costs that the provider reports, or `NA` when
#'     an answered row has none.
#'   * `seconds`: the sum of the response times.
#'   * `errors`: the number of rows with an `.error`. They stay out of the
#'     AUC.
#'   * `answers`: a list column that holds the output of `decide()`.
#' @details The AUC uses the probabilities that `decide()` returns, so it is
#'   the AUC of the calibrated probabilities when the setup has a
#'   calibrator. It is the Mann-Whitney statistic of the probability of
#'   `event`, with average ranks for ties; it equals
#'   `yardstick::roc_auc_vec(truth, prob, event_level = "second")` when
#'   `event` is the second level of `truth`.
#'
#'   The function checks `setup`, `metric`, `event`, `truth` and `role`
#'   before it sends a request.
#' @examples
#' \dontrun{
#' quality <- question_choice("Is the part defective?", c(
#'   nominal = "A clean part.", defective = "A part with a defect."
#' ))
#' setup <- decision_setup(decider_typesafe("jev-1.13.0"), list(q = quality))
#' score_setup(
#'   setup, text = c("Clean surface.", "Dark streak."),
#'   truth = c("nominal", "defective"), role = c("learning", "learning")
#' )
#' }
#' @export
score_setup <- function(setup, text = NULL, image = NULL, truth, role = NULL,
                        metric = "roc_auc", event = NULL, path = NULL) {
  check_scorable(setup, metric)
  n <- count_inputs(text, as_images(image))
  event <- resolve_event(setup, event)
  truth <- check_truth(truth, setup, n)
  check_role(role, n)
  out <- decide(setup, text = text, image = image, path = path)
  score_row(out, truth, event)
}

#' Score the test rows one time
#'
#' Runs `decide()` with a setup on the test rows and scores them as
#' `score_setup()` does, but only once. It writes the result to `path`, and it
#' refuses to run again while `path` exists, so the test rows are not tuned
#' against.
#'
#' @inheritParams score_setup
#' @param path The path of the result file (an `.rds` file in a folder that
#'   exists). If it exists, `evaluate_once()` stops before any request.
#' @return The one-row tibble of `score_setup()` (with `event` at its
#'   default). It is also written to `path` with `saveRDS()` when no row has
#'   an error.
#' @details `decide()` keeps its state in `paste0(path, ".state.json")`. A
#'   run that stops continues from this file without paying twice, and each
#'   test row is scored once. When a row has an error, `evaluate_once()`
#'   returns the row, does not write `path`, and warns that a new call sends
#'   the failed rows again.
#' @examples
#' \dontrun{
#' evaluate_once(
#'   setup, text = test_texts, truth = test_truth, path = "test-result.rds"
#' )
#' }
#' @export
evaluate_once <- function(setup, text = NULL, image = NULL, truth, path) {
  if (!rlang::is_string(path)) {
    cli::cli_abort("{.arg path} must be one file path.")
  }
  if (file.exists(path)) {
    cli::cli_abort(c(
      "{.path {path}} exists: the test rows were already scored.",
      i = "Test rows are scored once. Read the result with {.fn readRDS}."
    ))
  }
  row <- score_setup(
    setup, text = text, image = image, truth = truth,
    path = paste0(path, ".state.json")
  )
  if (row$errors == 0) {
    saveRDS(row, path)
  } else {
    cli::cli_warn(c(
      "{row$errors} test row{?s} failed, so {.path {path}} was not written.",
      i = paste(
        "A new call sends the failed rows again and keeps the finished",
        "answers."
      )
    ))
  }
  row
}

#' Check the setup and the metric
#'
#' @param setup The `setup` of `score_setup()`.
#' @param metric The `metric` of `score_setup()`.
#' @return `NULL`, invisibly. It stops with an error when `setup` is not a
#'   setup with one question, or `metric` is not `"roc_auc"`.
#' @noRd
check_scorable <- function(setup, metric) {
  if (!S7::S7_inherits(setup, setup_class)) {
    cli::cli_abort(
      "{.arg setup} must come from {.fn decision_setup} or {.fn read_setup}."
    )
  }
  if (length(setup@questions) != 1) {
    cli::cli_abort(
      "{.fn score_setup} works with a setup of one question only."
    )
  }
  if (!identical(metric, "roc_auc")) {
    cli::cli_abort(c(
      "{.arg metric} must be {.val roc_auc} in this release.",
      i = "Compute other metrics from the {.field answers} column."
    ))
  }
  invisible()
}

#' Find the event of the AUC
#'
#' @param setup A setup with one question.
#' @param event The `event` of `score_setup()`.
#' @return The event: one answer of the question.
#' @noRd
resolve_event <- function(setup, event) {
  question <- setup@questions[[1]]
  answers <- names(question@answers)
  if (is.null(event)) {
    if (question_type(question) == "noul") {
      event <- "true"
    } else if (length(answers) == 2) {
      event <- answers[2]
    } else {
      cli::cli_abort(c(
        "{.arg event} is required for a question with {length(answers)} answers.",
        i = "Answers: {.val {answers}}."
      ))
    }
  }
  if (!rlang::is_string(event) || !event %in% answers) {
    cli::cli_abort(
      "{.arg event} must be one of the answers {.val {answers}}."
    )
  }
  event
}

#' Check the true answers
#'
#' @param truth The `truth` of `score_setup()`.
#' @param setup A setup with one question.
#' @param n The number of inputs.
#' @return `truth` as a character vector.
#' @noRd
check_truth <- function(truth, setup, n) {
  if (!(is.factor(truth) || is.character(truth)) || length(truth) != n) {
    cli::cli_abort(paste(
      "{.arg truth} must be a factor or character vector with the length of",
      "the inputs ({n})."
    ))
  }
  truth <- as.character(truth)
  answers <- names(setup@questions[[1]]@answers)
  bad <- unique(truth[!truth %in% answers])
  if (length(bad) > 0) {
    cli::cli_abort(c(
      "{.arg truth} holds values that are not answers: {.val {bad}}.",
      i = "Answers: {.val {answers}}."
    ))
  }
  truth
}

#' Check the roles
#'
#' @param role The `role` of `score_setup()`.
#' @param n The number of inputs.
#' @return `NULL`, invisibly. It stops with an error when `role` has the
#'   wrong length or values, or holds `"test"`.
#' @noRd
check_role <- function(role, n) {
  if (is.null(role)) {
    return(invisible())
  }
  if (length(role) != n ||
      !all(role %in% c("learning", "calibration", "test"))) {
    cli::cli_abort(paste(
      "{.arg role} must have one value per input: {.val learning},",
      "{.val calibration} or {.val test}."
    ))
  }
  if ("test" %in% role) {
    cli::cli_abort(c(
      "{.arg role} holds test rows. Test rows are scored once, with {.fn evaluate_once}.",
      i = "{.fn score_setup} refuses them, so the test rows stay unseen."
    ))
  }
  invisible()
}

#' Make the result row
#'
#' @param out The output of `decide()`.
#' @param truth The true answers, as a character vector.
#' @param event The answer that counts as the event.
#' @return The one-row tibble of `score_setup()`.
#' @noRd
score_row <- function(out, truth, event) {
  answered <- is.na(out$.error)
  prob <- out[[paste0(".pred_", clean_name(event))]]
  tibble::tibble(
    metric = "roc_auc",
    estimate = roc_auc(prob[answered], truth[answered] == event),
    n = sum(answered),
    calls = attr(out, "requests"),
    input_tokens = sum(out$.input_tokens, na.rm = TRUE),
    cost = if (anyNA(out$.cost[answered])) NA_real_ else sum(out$.cost[answered]),
    seconds = sum(out$.seconds, na.rm = TRUE),
    errors = sum(!answered),
    answers = list(out)
  )
}

#' Area under the ROC curve
#'
#' @param prob The probability of the event for each row.
#' @param event `TRUE` for a row of the event class.
#' @return The Mann-Whitney statistic: the share of event/non-event pairs in
#'   which the event row has the higher probability, with ties counted half.
#'   `NA`, with a warning, when a class has no row.
#' @noRd
roc_auc <- function(prob, event) {
  positives <- sum(event)
  negatives <- sum(!event)
  if (positives == 0 || negatives == 0) {
    cli::cli_warn(
      "Fewer than one row of each class remains, so the AUC is {.code NA}."
    )
    return(NA_real_)
  }
  ranks <- rank(prob)
  (sum(ranks[event]) - positives * (positives + 1) / 2) /
    (positives * negatives)
}
