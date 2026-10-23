# Build the dataset `textiles`: 50 simulated textile images.
#
# Run from the package root: Rscript data-raw/textiles.R
# The images come from the study folder (read only). The sets are in
# results/fair/sets/ of the study. References: the rows of references.csv for
# textiles with rank 1 and 2 (two per class). Inputs: 23 rows per class of
# design.csv for textiles, drawn with a fixed seed; none is a reference.
# The test rows of the study (results/image_split_manifest.csv, split "test")
# are never used. The script checks that.

study <- "C:/Users/megahefm/Dropbox/Miami/Code/claude/fine_tuned_jev"
sets <- file.path(study, "results", "fair", "sets")

read_set <- function(name) {
  rows <- utils::read.csv(file.path(sets, name), stringsAsFactors = FALSE)
  tibble::as_tibble(rows[rows$dataset == "textiles", ])
}

references <- read_set("references.csv") |>
  dplyr::filter(rank %in% 1:2)
design <- read_set("design.csv")

set.seed(2026)
inputs <- design |>
  dplyr::filter(!image_path %in% references$image_path) |>
  dplyr::slice_sample(n = 23, by = actual_class)

manifest <- utils::read.csv(file.path(study, "results", "image_split_manifest.csv"))
test_paths <- manifest$image_path[manifest$split == "test"]

chosen <- dplyr::bind_rows(
  dplyr::mutate(references, role = "reference", reference_rank = as.integer(rank)),
  dplyr::mutate(inputs, role = "input", reference_rank = NA_integer_)
)
stopifnot(
  nrow(chosen) == 50, !anyDuplicated(chosen$image_path),
  !any(chosen$image_path %in% test_paths),
  all(table(chosen$actual_class) == 25)
)

textiles <- chosen |>
  dplyr::transmute(
    # Two study files share a name in different folders: the folder joins the name
    file = paste0(defect_type, "_", basename(image_path)),
    class = factor(actual_class, levels = c("nominal", "defective")),
    defect_type = factor(defect_type, levels = c("nominal", "local", "global")),
    role, reference_rank,
    from = image_path
  ) |>
  dplyr::arrange(role, class, file)

dir.create("inst/extdata/textiles", recursive = TRUE, showWarnings = FALSE)
stopifnot(all(file.copy(
  file.path(study, textiles$from), file.path("inst/extdata/textiles", textiles$file),
  overwrite = TRUE
)))
textiles <- dplyr::select(textiles, !from)

print(table(textiles$role, textiles$class))
print(table(textiles$role, textiles$defect_type))
usethis::use_data(textiles, overwrite = TRUE, compress = "xz")
