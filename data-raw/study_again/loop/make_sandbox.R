# Make the blind sandbox of one description loop of gpt-6-luna (vignette 5).
# Run from the package root, in Git Bash:
#   Rscript data-raw/study_again/loop/make_sandbox.R <dataset>
# The sandbox is C:/Users/megahefm/decisions-openai-loops/<dataset>. The map
# of the image names, the md5 of score.sh and (later) the mirror of the loop
# log go to this folder, outside the sandbox. The script makes no call and
# reads no key. It reads the study folder and changes nothing in it.

here <- dirname(normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1]]),
  winslash = "/"
))
source(file.path(here, "loop_common.R"))
rscript <- "C:/Program Files/R/R-4.6.1/bin/Rscript.exe"
package_dir <- normalizePath(file.path(here, "..", "..", ".."), winslash = "/")
seed <- 202610

dataset <- commandArgs(trailingOnly = TRUE)
if (length(dataset) != 1L) stop("Usage: Rscript make_sandbox.R <dataset>")
check_dataset(dataset)
paths <- loop_paths(here, dataset)

if (dir.exists(paths$sandbox)) stop("The sandbox folder already exists: ", paths$sandbox)
if (file.exists(paths$mirror)) {
  stop("A loop log mirror from an earlier attempt exists: ", paths$mirror)
}
old_state <- list.files(paths$state_dir, pattern = paste0("^", dataset, "_"))
if (length(old_state) > 0L) {
  stop("State files from an earlier attempt exist in ", paths$state_dir)
}

sets <- file.path(study_dir, "results", "fair", "sets")
design <- readr::read_csv(file.path(sets, "design.csv"), show_col_types = FALSE) |>
  dplyr::filter(.data$dataset == .env$dataset)
stopifnot(nrow(design) == 96L)
references <- readr::read_csv(file.path(sets, "references.csv"), show_col_types = FALSE) |>
  dplyr::filter(.data$dataset == .env$dataset, .data$rank <= 2) |>
  dplyr::mutate(
    name = paste0(dplyr::if_else(.data$actual_class == "nominal", "normal", "defective"),
                  "_", .data$rank)
  )
stopifnot(nrow(references) == 4L, !anyDuplicated(references$name))

purrr::walk(c("images", "references", "candidates", "scores"), \(d) {
  dir.create(file.path(paths$sandbox, d), recursive = TRUE)
})
dir.create(paths$state_dir, showWarnings = FALSE)

# A fixed seed shuffles the images, so the number does not show the class.
design <- withr::with_seed(seed, dplyr::slice_sample(design, prop = 1)) |>
  dplyr::mutate(image = sprintf("img_%03d.%s", dplyr::row_number(),
                                tools::file_ext(.data$image_path)))
stopifnot(all(file.copy(file.path(study_dir, design$image_path),
                        file.path(paths$sandbox, "images", design$image))))
design |>
  dplyr::transmute(image, class = .data$actual_class, defect_type = .data$defect_type) |>
  readr::write_csv(file.path(paths$sandbox, "labels.csv"))
design |>
  dplyr::select("image", "image_path") |>
  readr::write_csv(paths$map)

stopifnot(all(file.copy(
  file.path(study_dir, references$image_path),
  file.path(paths$sandbox, "references",
            paste0(references$name, ".", tools::file_ext(references$image_path)))
)))

generic <- generic_description()
tibble::tibble(normal = generic$normal, defective = generic$defective) |>
  readr::write_csv(file.path(paths$sandbox, "generic_description.csv"))
tibble::tibble(normal = generic$normal, defective = generic$defective,
               reason = "Start: the generic description.") |>
  readr::write_csv(file.path(paths$sandbox, "candidates", "1.csv"))
write_loop_log(empty_loop_log(), file.path(paths$sandbox, "loop_log.csv"))

# score.sh: one command. The md5 goes outside the sandbox.
readr::write_lines(c(
  "#!/usr/bin/env bash",
  "# Scores one candidate on the design images. Usage: bash score.sh N",
  paste0("\"", rscript, "\" \"", package_dir, "/data-raw/study_again/loop/loop_score.R\" ",
         dataset, " \"$1\"")
), file.path(paths$sandbox, "score.sh"))
writeLines(unname(tools::md5sum(file.path(paths$sandbox, "score.sh"))), paths$md5)

# LOOP.md: the study template. Only the first sentence of the top comment
# changes; its command line stays word for word, and run_loop.sh uses the
# same flags.
defect_types <- design |>
  dplyr::filter(.data$actual_class == "defective") |>
  dplyr::pull(.data$defect_type) |>
  unique() |>
  sort() |>
  paste(collapse = ", ")
template <- readLines(file.path(study_dir, "scripts", "fair_loop_instructions.md"),
                      warn = FALSE, encoding = "UTF-8")
close_comment <- which(template == "-->")[[1]]
command_line <- stringr::str_subset(template[seq_len(close_comment)], "^claude -p ")
stopifnot(length(command_line) == 1L)
comment <- c(
  "<!--",
  paste("Note for the reader: data-raw/study_again/loop/run_loop.sh starts the agent",
        "of this loop in this folder, as a fresh and isolated Claude Code process,",
        "with this command:"),
  command_line,
  "-->"
)
c(comment, template[-seq_len(close_comment)]) |>
  stringr::str_replace_all(stringr::fixed("{{dataset}}"), dataset) |>
  stringr::str_replace_all(stringr::fixed("{{defect_types}}"), defect_types) |>
  stringr::str_replace_all(stringr::fixed("{{model}}"), "gpt-6-luna (the OpenAI Decisions API)") |>
  stringr::str_replace_all(stringr::fixed("{{score_command}}"), "bash score.sh N") |>
  readr::write_lines(file.path(paths$sandbox, "LOOP.md"))
stopifnot(!any(grepl("{{", readLines(file.path(paths$sandbox, "LOOP.md")), fixed = TRUE)))

cat("Sandbox:", paths$sandbox, "\n")
cat("Image map:", paths$map, "\n")
cat("Defect types:", defect_types, "\n")
