# Audit the transcript of one description loop of gpt-6-luna (vignette 5).
# Run from the package root, in Git Bash:
#   Rscript data-raw/study_again/loop/audit.R <dataset> <transcript.jsonl>
#
# It sources the audit code of the study (R/fair_runner.R and R/fair_loop.R in
# the study folder, read only) and runs audit_transcript(). Before that it
# checks that the loop is valid: score.sh is unchanged, the sandbox log equals
# the mirror, the candidates are 1, 2, 3 ... each once (at most 6), and the
# transcript has a scoring call for each logged candidate. It writes
# <dataset>_audit.csv in this folder and prints "blind" when no row is
# flagged. It makes no call and reads no key.

here <- dirname(normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1]]),
  winslash = "/"
))
source(file.path(here, "loop_common.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: Rscript audit.R <dataset> <transcript.jsonl>")
dataset <- args[[1]]
transcript <- args[[2]]
check_dataset(dataset)
if (!file.exists(transcript)) stop("The transcript does not exist: ", transcript)
paths <- loop_paths(here, dataset)
if (!dir.exists(paths$sandbox)) stop("The sandbox does not exist: ", paths$sandbox)

# The study functions live in their own environment, so that their names
# (for example loop_datasets) do not replace the names of this kit.
study <- new.env(parent = globalenv())
sys.source(file.path(study_dir, "R", "fair_runner.R"), envir = study)
sys.source(file.path(study_dir, "R", "fair_loop.R"), envir = study)

check_score_sh(paths$sandbox, paths$md5)
if (!file.exists(paths$mirror)) stop("No mirror of the loop log: ", paths$mirror)
log <- read_record(paths$sandbox, paths$mirror)
if (nrow(log) == 0L) stop("The loop log has no candidate.")
if (!identical(log$candidate, seq_len(nrow(log)))) {
  stop("The candidates in the loop log must be 1, 2, 3 and so on, each once. The loop is not valid.")
}
if (nrow(log) > max_candidates) {
  stop("The loop log has more than ", max_candidates, " candidates. The loop is not valid.")
}
called <- study$scoring_calls(transcript, paths$sandbox)
missing <- setdiff(log$candidate, called)
if (length(missing) > 0L) {
  stop("The transcript has no scoring call for candidate ", paste(missing, collapse = ", "), ".")
}

flagged <- study$audit_transcript(transcript, paths$sandbox)
audit <- if (nrow(flagged) == 0L) {
  tibble::tibble(time = NA_character_, tool = "none",
                 target = "No call outside the sandbox. The loop was blind.")
} else {
  flagged
}
audit |>
  dplyr::mutate(
    transcript = basename(transcript),
    transcript_md5 = unname(tools::md5sum(transcript))
  ) |>
  readr::write_csv(paths$audit)

rule <- apply_keep_rule(log)
cat("Audit file:", paths$audit, "\n")
cat("Candidates logged:", nrow(log), "| best: candidate", rule$best, "with AUC",
    round(rule$best_auc, 4), "\n")
if (nrow(flagged) == 0L) {
  cat("blind\n")
} else {
  cat("Flagged rows:", nrow(flagged), "(a person reviews them)\n")
  print(flagged, n = Inf, width = Inf)
}
