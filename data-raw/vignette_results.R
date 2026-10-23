# Run the live code of the vignettes and save the results they show.
#
# Run from the package root:
#   Rscript data-raw/vignette_results.R <case> [<case> ...]
# Cases: getting-started, open-models, grading.
# (The case "images" of vignette 2 comes with Task 11b.)
#
# The code of each case is the code of the chunks with `script = TRUE` in
# vignettes/<case>.Rmd, unchanged. The lines that this script adds are the
# calls of log_decide(), save_results(), report_errors() and wait_for_laya().
#
#   getting-started:   TypeSafe Jev, 23 calls.
#   open-models:       Laya on this computer (CPU), free, not logged.
#   grading:           TypeSafe Jev, 23 calls.
#
# Every paid call appends one row to
# fine_tuned_jev/replication_materials/calls/<service>-calls.csv.
# The keys come from the environment (readRenviron() below). This script
# never prints or saves a key: it saves tibbles of decide() only, never a
# decider or a setup object.

readRenviron("C:/Users/megahefm/Dropbox/Miami/Code/claude/fine_tuned_jev/.Renviron")
pkgload::load_all(".", quiet = TRUE)
source("data-raw/log_call.R")

root <- normalizePath(".")

# ---- Helpers -----------------------------------------------------------------

#' Save the results of a case to inst/extdata/<case>.rds
#' @param case The name of the case.
#' @param saved A named list of tibbles.
save_results <- function(case, saved) {
  dir.create(file.path(root, "inst", "extdata"), showWarnings = FALSE)
  saveRDS(saved, file.path(root, "inst", "extdata", paste0(case, ".rds")))
}

#' Print the number of rows with an error, for each tibble of a list
#' @param saved A named list of tibbles and of lists of tibbles.
report_errors <- function(saved) {
  tibbles <- purrr::list_flatten(purrr::map(saved, \(x) if (is.data.frame(x)) list(x) else x))
  tibbles <- purrr::keep(tibbles, \(x) is.data.frame(x) && ".error" %in% names(x))
  purrr::iwalk(tibbles, \(x, name) {
    cat(name, ":", sum(!is.na(x$.error)), "of", nrow(x), "rows with an error\n")
  })
}

#' Wait until Laya answers its health check
#' @param minutes The longest wait.
wait_for_laya <- function(minutes = 5) {
  deadline <- Sys.time() + minutes * 60
  repeat {
    up <- tryCatch(
      httr2::resp_status(httr2::req_perform(httr2::request("http://localhost:8000/health"))) == 200,
      error = \(e) FALSE
    )
    if (up) return(invisible(TRUE))
    if (Sys.time() > deadline) stop("No answer from Laya in time.")
    Sys.sleep(5)
  }
}

# ---- Cases -------------------------------------------------------------------

case_getting_started <- function() {
  stopifnot(nzchar(Sys.getenv("TYPESAFE_API_KEY")))

  # chunk: tickets
  tickets <- tibble::tibble(
    ticket = 1:10,
    text = c(
      "I was charged twice for order 4471. Please refund the extra charge today.",
      "My parcel has not arrived. The tracking page has said 'in transit' for two weeks.",
      "The app crashes each time I open the settings page. I cannot log in, and I have a meeting in ten minutes.",
      "Thank you for the quick delivery. The product works well.",
      "I want my money back. The blender broke after one day.",
      "How do I change the email address on my account?",
      "The invoice shows the wrong company name. Please send a new one when you can.",
      "The package arrived with a broken seal. Please send a replacement. There is no hurry.",
      "Your website shows an error when I pay by card. I must order before the sale ends tonight.",
      "Can you tell me which sizes the jacket comes in?"
    )
  )

  # chunk: decider
  jev <- decider_typesafe()
  jev

  # chunk: questions
  refund <- question_noul("Does the customer ask for a refund?")

  topic <- question_choice(
    "Which team should answer this ticket?",
    c(
      billing = "Charges, invoices and refunds.",
      shipping = "Parcels and delivery.",
      technical = "Errors, and how to use the product."
    )
  )

  urgency <- question_score(
    "How urgent is this ticket?",
    c(
      low = "The customer can wait several days.",
      medium = "The customer needs an answer today.",
      high = "The customer needs an answer now."
    )
  )

  purpose <- "decisions-task11-getting-started"

  # chunk: one-noul
  one_noul <- decide(jev, refund, text = tickets$text[1])
  one_noul

  log_decide("typesafe", one_noul, purpose, jev@model, "gs-one-noul")

  # chunk: one-choice
  one_choice <- decide(jev, topic, text = tickets$text[2])
  one_choice

  log_decide("typesafe", one_choice, purpose, jev@model, "gs-one-choice")

  # chunk: one-score
  one_score <- decide(jev, urgency, text = tickets$text[3])
  one_score

  log_decide("typesafe", one_score, purpose, jev@model, "gs-one-score")

  # chunk: many-noul
  many_noul <- decide(jev, refund, text = tickets$text)
  dplyr::bind_cols(tickets["ticket"], many_noul)

  log_decide("typesafe", many_noul, purpose, jev@model, "gs-many-noul")

  # chunk: many-two
  many_two <- decide(jev, list(topic = topic, urgency = urgency), text = tickets$text)
  names(many_two)

  log_decide("typesafe", many_two, purpose, jev@model, "gs-many-two")

  saved <- list(
    one_noul = one_noul, one_choice = one_choice, one_score = one_score,
    many_noul = many_noul, many_two = many_two
  )
  save_results("getting-started", saved)
  report_errors(saved)

  # chunk: many-two-table
  dplyr::bind_cols(
    tickets["ticket"],
    many_two[c("topic_.pred_class", "urgency_.pred_class", "urgency_.score")]
  )

}

case_open_models <- function() {
  wait_for_laya()

  # chunk: decider
  laya <- decider_systemone("http://localhost:8000", "english", input = "text")
  laya

  # chunk: tickets
  tickets <- tibble::tibble(
    ticket = 1:10,
    text = c(
      "I was charged twice for order 4471. Please refund the extra charge today.",
      "My parcel has not arrived. The tracking page has said 'in transit' for two weeks.",
      "The app crashes each time I open the settings page. I cannot log in, and I have a meeting in ten minutes.",
      "Thank you for the quick delivery. The product works well.",
      "I want my money back. The blender broke after one day.",
      "How do I change the email address on my account?",
      "The invoice shows the wrong company name. Please send a new one when you can.",
      "The package arrived with a broken seal. Please send a replacement. There is no hurry.",
      "Your website shows an error when I pay by card. I must order before the sale ends tonight.",
      "Can you tell me which sizes the jacket comes in?"
    )
  )

  refund <- question_noul("Does the customer ask for a refund?")

  topic <- question_choice(
    "Which team should answer this ticket?",
    c(
      billing = "Charges, invoices and refunds.",
      shipping = "Parcels and delivery.",
      technical = "Errors, and how to use the product."
    )
  )

  urgency <- question_score(
    "How urgent is this ticket?",
    c(
      low = "The customer can wait several days.",
      medium = "The customer needs an answer today.",
      high = "The customer needs an answer now."
    )
  )

  # chunk: decide
  answers <- decide(
    laya,
    list(refund = refund, topic = topic, urgency = urgency),
    text = tickets$text,
    max_active = 1
  )

  saved <- list(answers = answers)
  save_results("open-models", saved)
  report_errors(saved)

  # chunk: answers
  dplyr::bind_cols(
    tickets["ticket"],
    answers[c("refund_.pred_class", "topic_.pred_class", "urgency_.pred_class", ".seconds")]
  )

  # chunk: seconds
  dplyr::summarise(
    answers,
    rows = dplyr::n(),
    errors = sum(!is.na(.error)),
    input_tokens = sum(.input_tokens),
    median_seconds = median(.seconds),
    max_seconds = max(.seconds)
  )

}

case_grading <- function() {
  stopifnot(nzchar(Sys.getenv("TYPESAFE_API_KEY")))

  # chunk: rubric
  rubric <- list(
    keeps_row = question_noul("Does the text say that the failed input keeps its row in the output?"),
    na_answers = question_noul("Does the text say that the answers of the failed row are NA?"),
    error_text = question_noul("Does the text say that the reason of the failure is in the .error column?"),
    others_continue = question_noul("Does the text say that the other inputs of the batch still get their answers?"),
    stops_all = question_noul("Does the text say that decide() stops with an error, or returns nothing, when one call fails?"),
    drops_row = question_noul("Does the text say that decide() removes the failed input from the output?")
  )

  # chunk: rubric-text
  rubric_text <- tibble::tribble(
    ~question, ~kind, ~if_above, ~if_below,
    "keeps_row", "idea", "Covered: the failed input keeps its row.", "Missing: say what happens to the row of the failed input.",
    "na_answers", "idea", "Covered: the answers of the failed row are NA.", "Missing: say what the answers of the failed row are.",
    "error_text", "idea", "Covered: the reason is in the .error column.", "Missing: say where to find the reason of the failure.",
    "others_continue", "idea", "Covered: the other inputs still get their answers.", "Missing: say what happens to the other inputs.",
    "stops_all", "wrong", "Check again: one failed call does not stop decide().", NA_character_,
    "drops_row", "wrong", "Check again: decide() does not remove the row of a failed call.", NA_character_
  )

  # chunk: samples
  samples <- tibble::tribble(
    ~answer, ~keeps_row, ~na_answers, ~error_text, ~others_continue, ~stops_all, ~drops_row,
    "decide() keeps the row of the failed call. The answers in that row are NA, and the .error column holds the reason. The other inputs get their answers.", TRUE, TRUE, TRUE, TRUE, FALSE, FALSE,
    "The failed input still has a row, in the same place. Its answers are NA and .error says why.", TRUE, TRUE, TRUE, FALSE, FALSE, FALSE,
    "It stops and throws an error, so you get no result at all.", FALSE, FALSE, FALSE, FALSE, TRUE, FALSE,
    "The function removes the failed rows from the table, so the output is shorter than the input.", FALSE, FALSE, FALSE, FALSE, FALSE, TRUE,
    "The row of the failed call has NA values. Everything else works as before.", TRUE, TRUE, FALSE, TRUE, FALSE, FALSE,
    "It writes the error message into the .error column and goes on with the other inputs.", FALSE, FALSE, TRUE, TRUE, FALSE, FALSE,
    "I think it tries the call again and again until it works.", FALSE, FALSE, FALSE, FALSE, FALSE, FALSE,
    "One failed call stops the whole batch, and you lose the answers of the other inputs.", FALSE, FALSE, FALSE, FALSE, TRUE, FALSE,
    "The row stays in the output and its answer is NA. The reason for the failure is in .error. The call does not stop.", TRUE, TRUE, TRUE, TRUE, FALSE, FALSE,
    "The failed input gets NA answers, and the batch goes on.", FALSE, TRUE, FALSE, TRUE, FALSE, FALSE,
    "decide() skips the input that failed. It does not put that input in the output.", FALSE, FALSE, FALSE, FALSE, FALSE, TRUE,
    "The output has one row for each input, also for the inputs that fail. The failed rows hold the text of the error.", TRUE, FALSE, TRUE, FALSE, FALSE, FALSE,
    "Nothing happens. It just works.", FALSE, FALSE, FALSE, FALSE, FALSE, FALSE,
    "It gives a warning and drops that input. The other rows are fine.", FALSE, FALSE, FALSE, TRUE, FALSE, TRUE,
    "The reason for the failure is kept in the .error column, word for word from the provider. The answers of that row are NA.", TRUE, TRUE, TRUE, FALSE, FALSE, FALSE,
    "If one call fails, the other calls still go on and give their answers. The failed one has NA.", FALSE, TRUE, FALSE, TRUE, FALSE, FALSE,
    "The whole decide() call fails with the first HTTP error.", FALSE, FALSE, FALSE, FALSE, TRUE, FALSE,
    "Each input keeps its row, in order. A failed call has NA answers and a message in .error. The rest of the batch is not affected.", TRUE, TRUE, TRUE, TRUE, FALSE, FALSE,
    "decide() stops after the first failure, but it saves the finished answers to the path file.", FALSE, FALSE, FALSE, FALSE, TRUE, FALSE,
    "The failed row is marked with an error message. Then the model is asked again at once, up to ten times.", TRUE, FALSE, TRUE, FALSE, FALSE, FALSE
  )

  # chunk: setup-object
  setup <- decision_setup(decider_typesafe(), rubric)

  purpose <- "decisions-task11-grading"

  # chunk: score
  scored <- decide(setup, text = samples$answer)

  log_decide("typesafe", scored, purpose, setup@decider@model, "gr-samples")
  saved <- list(scored = scored)
  save_results("grading", saved)

  # chunk: probabilities
  dplyr::select(scored, dplyr::ends_with("_.pred_true"), .error)

  # chunk: thresholds
  thresholds <- purrr::map(names(rubric), \(question) {
    tibble::tibble(
      truth = factor(samples[[question]], levels = c(TRUE, FALSE)),
      probability = scored[[paste0(question, "_.pred_true")]]
    ) |>
      yardstick::roc_curve(truth, probability) |>
      dplyr::mutate(j = sensitivity + specificity - 1) |>
      dplyr::filter(dplyr::near(j, max(j)), is.finite(.threshold)) |>
      dplyr::summarise(threshold = median(.threshold), j = max(j))
  }) |>
    purrr::set_names(names(rubric)) |>
    dplyr::bind_rows(.id = "question")

  thresholds

  # chunk: feedback-rubric
  feedback_rubric <- rubric_text |>
    dplyr::left_join(thresholds[c("question", "threshold")], by = "question")

  feedback_rubric

  # chunk: give-feedback
  give_feedback <- function(scored, rubric) {
    if (!is.na(scored$.error)) {
      return("The check did not work. Try again.")
    }
    probability <- purrr::map_dbl(rubric$question, \(question) scored[[paste0(question, "_.pred_true")]])
    lines <- ifelse(probability >= rubric$threshold, rubric$if_above, rubric$if_below)
    lines[!is.na(lines)]
  }

  # chunk: new
  new_answers <- c(
    "The row of the failed call stays in the output. Its answers are NA, and .error has the reason.",
    "decide() stops with an error at the first failed call, and you get nothing back.",
    "It keeps going with the other inputs."
  )

  new_scored <- decide(setup, text = new_answers)

  purrr::map(seq_along(new_answers), \(i) give_feedback(new_scored[i, ], feedback_rubric))

  log_decide("typesafe", new_scored, purpose, setup@decider@model, "gr-new")
  saved <- list(
    scored = scored, thresholds = thresholds, feedback_rubric = feedback_rubric,
    new_answers = new_answers, new_scored = new_scored
  )
  save_results("grading", saved)
  report_errors(saved)
  # The file of write_setup() goes to a temporary folder first, then to inst/extdata
  old <- setwd(tempdir())

  # chunk: write-setup
  write_setup(setup, "rubric_setup.json")

  file.copy("rubric_setup.json", file.path(root, "inst", "extdata", "rubric_setup.json"), overwrite = TRUE)
  setwd(old)

}

# ---- Run ---------------------------------------------------------------------

cases <- commandArgs(trailingOnly = TRUE)
stopifnot(
  length(cases) > 0,
  all(cases %in% c("getting-started", "open-models", "grading"))
)
for (case in cases) {
  switch(case,
    `getting-started` = case_getting_started(),
    `open-models` = case_open_models(),
    grading = case_grading()
  )
}
