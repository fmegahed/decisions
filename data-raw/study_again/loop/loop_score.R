# Score one candidate of a description loop of gpt-6-luna (vignette 5).
# score.sh in the sandbox calls it:  Rscript loop_score.R <dataset> <N>
#
# It checks, then scores the 96 design images with score_setup() (96 paid
# calls), writes scores/N.csv, appends the log row to the sandbox log and to
# the mirror outside the sandbox, applies the keep rule, and prints the result.
# DECISIONS_LOOP_CHECK_ONLY=true: it runs the checks and builds the setup,
# prints "check only: no call", and writes nothing. It never prints a key.

here <- dirname(normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1]]),
  winslash = "/"
))
source(file.path(here, "loop_common.R"))
package_dir <- normalizePath(file.path(here, "..", "..", ".."), winslash = "/")
purpose <- "decisions-task12-openai-loop-"
instructions <- paste(
  "Inspect `inspection_image` for manufacturing defects.",
  "Select exactly one category."
)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: bash score.sh N")
dataset <- args[[1]]
check_dataset(dataset)
if (!grepl("^[1-9][0-9]{0,2}$", args[[2]])) {
  stop("N must be a whole number from 1 to 6, with no leading zero. Use: bash score.sh N")
}
n <- as.integer(args[[2]])
paths <- loop_paths(here, dataset)

check_only <- tolower(trimws(Sys.getenv("DECISIONS_LOOP_CHECK_ONLY")))
if (!check_only %in% c("", "true", "false")) {
  stop("DECISIONS_LOOP_CHECK_ONLY must be true or false.")
}
check_only <- check_only == "true"

# --- Checks (no call, no write) ------------------------------------------------

#' Stop unless candidate `n` may run now: n is at most 6, it is the next
#' number in the mirror, and its scores file does not exist.
#' @return The rows of the mirror.
check_slot <- function() {
  if (n < 1L) stop("The candidate number must be 1 or more.")
  if (n > max_candidates) {
    stop("Use at most ", max_candidates, " candidates, including the generic one.")
  }
  record <- read_record(paths$sandbox, paths$mirror)
  if (n != nrow(record) + 1L) {
    stop("The next candidate is number ", nrow(record) + 1L, ", not ", n, ".")
  }
  if (file.exists(file.path(paths$sandbox, "scores", paste0(n, ".csv")))) {
    stop("The scores file for candidate ", n, " exists. Each candidate is scored once.")
  }
  record
}

#' Read candidate `n`: one row, three non-empty texts. Candidate 1 must be
#' the generic description.
#' @return A list with `normal`, `defective` and `reason`.
read_candidate <- function() {
  file <- file.path(paths$sandbox, "candidates", paste0(n, ".csv"))
  if (!file.exists(file)) stop("The candidate file is missing: candidates/", n, ".csv")
  d <- suppressWarnings(readr::read_csv(
    file, show_col_types = FALSE, col_types = readr::cols(.default = "c")
  ))
  if (nrow(readr::problems(d)) > 0L) stop("The candidate file has parsing problems.")
  if (!setequal(names(d), c("normal", "defective", "reason"))) {
    stop("The candidate file needs the columns normal, defective and reason.")
  }
  if (nrow(d) != 1L) stop("The candidate file needs exactly one data row.")
  text <- as.list(d[1, c("normal", "defective", "reason")])
  empty <- purrr::map_lgl(text, \(x) is.na(x) || !nzchar(stringr::str_trim(x)))
  if (any(empty)) {
    stop("The candidate text '", names(text)[empty][[1]], "' is empty.")
  }
  generic <- generic_description()
  if (n == 1L && !(identical(text$normal, generic$normal) &&
                   identical(text$defective, generic$defective))) {
    stop("Candidate 1 must be the generic description.")
  }
  text
}

record <- check_slot()
check_score_sh(paths$sandbox, paths$md5)
text <- read_candidate()

# The design images: study paths from the map, truth from the study set.
study_path <- \(p) file.path(study_dir, p)
sets <- file.path(study_dir, "results", "fair", "sets")
design <- readr::read_csv(file.path(sets, "design.csv"), show_col_types = FALSE) |>
  dplyr::filter(.data$dataset == .env$dataset)
images <- readr::read_csv(paths$map, show_col_types = FALSE) |>
  dplyr::left_join(design, by = "image_path")
stopifnot(
  nrow(images) == 96L, !anyNA(images$actual_class),
  all(file.exists(study_path(images$image_path)))
)
references <- readr::read_csv(file.path(sets, "references.csv"), show_col_types = FALSE) |>
  dplyr::filter(.data$dataset == .env$dataset, .data$rank <= 2) |>
  dplyr::arrange(.data$rank)
reference_paths <- list(
  normal = study_path(references$image_path[references$actual_class == "nominal"]),
  defective = study_path(references$image_path[references$actual_class == "defective"])
)
stopifnot(lengths(reference_paths) == 2L, all(file.exists(unlist(reference_paths))))

# The code of the package is the scorer: the record names it, and a change in
# R/ between two candidates is refused.
git <- function(...) system2("git", c("-C", package_dir, ...), stdout = TRUE)
if (length(git("status", "--porcelain", "--", "R")) > 0L) {
  stop("R/ of the package has uncommitted changes. Commit them first: the scorer must match a commit.")
}
cat("Package code: git", git("rev-parse", "--short", "HEAD"), "\n")
pkgload::load_all(package_dir, quiet = TRUE)
setup <- decision_setup(
  decider_openai("gpt-6-luna"),
  list(quality = question_choice(
    instructions, c(normal = text$normal, defective = text$defective)
  )),
  references = reference_paths, max_size = 768, upscale = TRUE
)

if (check_only) {
  cat("Checks passed for candidate", n, "of", dataset, "\n")
  cat("check only: no call\n")
  quit(save = "no", status = 0)
}

# --- Score (96 paid calls) -----------------------------------------------------

readRenviron(file.path(study_dir, ".Renviron"))
if (!nzchar(Sys.getenv("OPENAI_API_KEY"))) stop("OPENAI_API_KEY is not set.")
source(file.path(here, "..", "..", "log_call.R"))

# The state file and the ledger carry a short hash of the two texts, so an
# edit of the candidate after a failed run starts a new state, not a stop.
if (!dir.exists(paths$state_dir)) stop("The state folder is missing: ", paths$state_dir)
stem <- file.path(paths$state_dir, paste0(
  dataset, "_", n, "_", substr(rlang::hash(c(text$normal, text$defective)), 1, 8)
))
state <- paste0(stem, ".json")
ledger <- paste0(stem, ".logged.txt")

truth <- dplyr::if_else(images$actual_class == "nominal", "normal", "defective")
result <- score_setup(
  setup, image = study_path(images$image_path), truth = truth,
  role = rep("learning", nrow(images)), path = state
)
out <- result$answers[[1]]

# The ledger (outside the sandbox) holds the key of each logged row. A row of
# the state file that is not in the ledger was paid but not logged (a stop
# after decide() saved it): it is logged now. A failed row has no stable key,
# so it gets one for this run.
run_id <- format(Sys.time(), "%Y%m%dT%H%M%OS3")
failed <- !is.na(out$.error) | is.na(out$.seconds)
keys <- ifelse(failed, paste(images$image, "failed", run_id),
               paste(images$image, out$.seconds, out$.input_tokens))
logged <- if (file.exists(ledger)) readLines(ledger) else character()
new_calls <- !keys %in% logged
if (any(new_calls)) {
  log_decide("openai", out[new_calls, ], paste0(purpose, dataset), "gpt-6-luna",
             paste0("loop-", dataset, "-c", n, "-", images$image[new_calls], "-", run_id))
  cat(keys[new_calls], file = ledger, sep = "\n", append = TRUE)
}

# A row with no error and no probability is saved: a retry would not send it.
if (any(is.na(out$.pred_defective) & is.na(out$.error))) {
  stop("A retry does not help: the answers are saved. Stop and report.")
}
if (result$errors > 0L) {
  stop(
    result$errors, " of ", nrow(images), " images failed. Nothing is logged for the candidate. ",
    "Run the same command once more: it sends only the failed images."
  )
}

scores <- tibble::tibble(
  image = images$image, class = images$actual_class,
  defect_type = images$defect_type, prob_defective = out$.pred_defective
)
by_type <- scores |>
  dplyr::summarise(mean = mean(.data$prob_defective), .by = "defect_type") |>
  dplyr::arrange(.data$defect_type)
type_text <- paste0(by_type$defect_type, "=", round(by_type$mean, 3), collapse = "; ")

# Check the slot again: another run of this slot can have finished first.
record <- check_slot()
log <- dplyr::bind_rows(record, tibble::tibble(
  candidate = n, time_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  normal = text$normal, defective = text$defective, auc = result$estimate,
  mean_score_by_type = type_text, reason = text$reason, kept = NA
))
rule <- apply_keep_rule(log)
log$kept <- rule$kept
# The mirror first, then the copy in the sandbox, then the scores file.
write_loop_log(log, paths$mirror)
write_loop_log(log, file.path(paths$sandbox, "loop_log.csv"))
readr::write_csv(scores, file.path(paths$sandbox, "scores", paste0(n, ".csv")))

cat("Candidate", n, "of", dataset, "\n")
cat("AUC:", round(result$estimate, 4), "\n")
cat("Mean probability of defective by defect type:", type_text, "\n")
cat("Kept:", rule$kept[[n]], "\n")
cat("Current best: candidate", rule$best, "with AUC", round(rule$best_auc, 4), "\n")
