# Shared by make_sandbox.R, loop_score.R and audit.R: the folders, the loop
# log, the keep rule and the generic description. It makes no call and needs
# no key. Needs readr, dplyr, stringr, purrr and tibble.

study_dir <- "C:/Users/megahefm/Dropbox/Miami/Code/claude/fine_tuned_jev"
sandbox_root <- "C:/Users/megahefm/decisions-openai-loops"
loop_datasets <- c("extrusion", "microstructure", "pipe_staple", "textiles")
max_candidates <- 6L
keep_gain <- 0.02
loop_columns <- c(
  "candidate", "time_utc", "normal", "defective", "auc",
  "mean_score_by_type", "reason", "kept"
)

#' Stop unless the dataset has a loop
#' @param dataset One string.
#' @return `dataset`, invisibly.
check_dataset <- function(dataset) {
  if (identical(dataset, "pan_images")) stop("Pans have no loop.")
  if (!dataset %in% loop_datasets) {
    stop("DATASET must be one of: ", paste(loop_datasets, collapse = ", "), ".")
  }
  invisible(dataset)
}

#' The files of one loop
#' @param loop_dir The folder of the kit (it holds the maps and the mirrors).
#' @param dataset One of `loop_datasets`.
#' @return A list of paths. Only `sandbox` and `state_dir` lie outside the kit
#'   folder; the sandbox holds no map, mirror, md5 or state file.
loop_paths <- function(loop_dir, dataset) {
  list(
    sandbox = file.path(sandbox_root, dataset),
    state_dir = file.path(sandbox_root, "state"),
    map = file.path(loop_dir, paste0(dataset, "_image_map.csv")),
    mirror = file.path(loop_dir, paste0(dataset, "_loop_log.csv")),
    md5 = file.path(loop_dir, paste0(dataset, "_score_sh.md5")),
    audit = file.path(loop_dir, paste0(dataset, "_audit.csv"))
  )
}

#' The generic description of the study
#' @return A list with `normal` and `defective`.
generic_description <- function() {
  list(
    normal = "No visible manufacturing defects; the part appears conforming.",
    defective = "At least one visible manufacturing defect or anomaly."
  )
}

#' Keep rule: candidate 1 is the first best; a later candidate replaces the
#' best only if its AUC is at least 0.02 higher than the best.
#' @param log A loop log with `candidate` and `auc`, in order.
#' @return A list: `kept` (logical per row), `best` (candidate number),
#'   `best_auc`.
apply_keep_rule <- function(log, gain = keep_gain) {
  kept <- logical(nrow(log))
  best <- NA_integer_
  best_auc <- NA_real_
  for (i in seq_len(nrow(log))) {
    if (i == 1L || round(log$auc[[i]] - best_auc, 10) >= gain) {
      kept[[i]] <- TRUE
      best <- as.integer(log$candidate[[i]])
      best_auc <- log$auc[[i]]
    }
  }
  list(kept = kept, best = best, best_auc = best_auc)
}

#' An empty loop log
empty_loop_log <- function() {
  tibble::tibble(
    candidate = integer(), time_utc = character(), normal = character(),
    defective = character(), auc = double(), mean_score_by_type = character(),
    reason = character(), kept = logical()
  )
}

#' Read a loop log
#' @param path A CSV file with the `loop_columns`.
read_loop_log <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(
    candidate = "i", time_utc = "c", normal = "c", defective = "c",
    auc = "d", mean_score_by_type = "c", reason = "c", kept = "l"
  ))
}

#' Write a loop log
write_loop_log <- function(log, path) {
  readr::write_csv(dplyr::select(log, dplyr::all_of(loop_columns)), path)
}

#' The record of the loop: the mirror outside the sandbox
#' @param sandbox,mirror The sandbox folder and the mirror file.
#' @return The mirror rows. Stops when the sandbox log differs from the mirror,
#'   or when there is no mirror and the sandbox log has rows.
read_record <- function(sandbox, mirror) {
  copy_file <- file.path(sandbox, "loop_log.csv")
  if (!file.exists(copy_file)) stop("The loop log is missing from the sandbox.")
  copy <- read_loop_log(copy_file)
  if (!file.exists(mirror)) {
    if (nrow(copy) > 0L) {
      stop("The sandbox log has rows but there is no mirror. The loop is not valid.")
    }
    return(empty_loop_log())
  }
  record <- read_loop_log(mirror)
  if (!isTRUE(all.equal(record, copy, check.attributes = FALSE))) {
    stop("The loop log in the sandbox differs from the mirror. The loop is not valid.")
  }
  record
}

#' Stop unless score.sh is the file that make_sandbox.R wrote
check_score_sh <- function(sandbox, md5_file) {
  if (!file.exists(md5_file)) stop("No md5 record of score.sh: ", md5_file)
  now <- unname(tools::md5sum(file.path(sandbox, "score.sh")))
  if (!identical(now, readLines(md5_file, warn = FALSE)[[1]])) {
    stop("score.sh changed after the sandbox was made. The loop is not valid.")
  }
  invisible(TRUE)
}
