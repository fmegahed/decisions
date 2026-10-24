# Copy the record of the package from the record of the project.
#
# Run from the package root, with the path of the project repository:
#   Rscript data-raw/record.R ../fine_tuned_jev
#
# The replication record of the whole project (the study, the paper and this
# package) is in fmegahed/decision-models-for-industrial-image-qc. This script
# copies the part about the package into replication_materials/, with the build
# scripts of the record in .replication/. The pkgdown workflow builds the copy
# into the website at /record/.
#
# The record of the project is the source. Do not edit the copy: change the
# record of the project, or the files in data-raw/record/, and run this script
# again. replication_materials/ and .replication/ are in .Rbuildignore, so the
# copy never changes the package.

args <- commandArgs(trailingOnly = TRUE)
project <- if (length(args) > 0) args[[1]] else "../fine_tuned_jev"
from <- file.path(project, "replication_materials")
stopifnot(file.exists("DESCRIPTION"), dir.exists(from))

# The decisions about the package: D39 first named it, and D136 starts the
# brainstorm of milestone M3. Add the ID of a later decision about the study or
# the paper to `not_package`.
earlier <- 39
first_package <- 136
not_package <- integer()
ruling_prefix <- "R-2026-10-23-decisions-package-"
m3_start <- "2026-10-23T00:52Z"
plans <- c(
  "2026-10-23-decisions-package-design.md",
  "2026-10-23-decisions-package-plan.md",
  "2026-10-23-decisions-package-ledger.md"
)
roles <- c(fmm = "Maintainer and author", yjc = "Author")

# ---- Helpers -----------------------------------------------------------------

read_text <- function(path) readLines(path, encoding = "UTF-8", warn = FALSE)

# LF line ends on every platform, as in the record of the project
write_text <- function(lines, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeLines(enc2utf8(lines), con, useBytes = TRUE)
}

# The cells of a table row; "\|" is a pipe inside a cell
cells <- function(line) {
  x <- stringr::str_split_1(line, "(?<!\\\\)\\|")
  stringr::str_trim(x[-c(1, length(x))])
}

as_row <- function(x) paste0("| ", paste(x, collapse = " | "), " |")

# Keep the text, the header and separator of each table, and the rows for
# which keep(heading, cells) is TRUE. `heading` is the last heading line above.
filter_rows <- function(lines, keep) {
  heading <- ""
  in_table <- FALSE
  kept <- logical(length(lines))
  for (i in seq_along(lines)) {
    line <- lines[[i]]
    if (stringr::str_starts(line, "#")) heading <- line
    is_row <- stringr::str_starts(line, "\\|")
    is_header <- is_row && !in_table
    is_rule <- stringr::str_detect(line, "^\\|[-:| ]+\\|$")
    in_table <- is_row
    kept[[i]] <- !is_row || is_header || is_rule || keep(heading, cells(line))
  }
  lines[kept]
}

package_decision <- function(id) {
  if (stringr::str_starts(id, ruling_prefix)) return(TRUE)
  n <- as.integer(stringr::str_match(id, "^D(\\d+)$")[, 2])
  !is.na(n) && (n == earlier || n >= first_package) && !n %in% not_package
}

# ---- Copy --------------------------------------------------------------------

to <- "replication_materials"
unlink(c(to, ".replication"), recursive = TRUE)

# Decisions, with their corrections and checks; the topics stay as they are
decision_tables <- c("## Decisions", "## Corrections", "## Checks")
read_text(file.path(from, "project", "decisions.md")) |>
  filter_rows(\(heading, x) !heading %in% decision_tables || package_decision(x[[1]])) |>
  write_text(file.path(to, "project", "decisions.md"))

# Process events of M3, without the events of the paper
read_text(file.path(from, "project", "process.md")) |>
  filter_rows(\(heading, x) x[[1]] >= m3_start && x[[2]] != "paper") |>
  write_text(file.path(to, "project", "process.md"))

# Roadmap: the people with their roles in the package, and milestone M3
roadmap <- read_text(file.path(from, "project", "roadmap.md")) |>
  filter_rows(\(heading, x) {
    switch(heading,
      "## People" = x[[1]] %in% names(roles),
      "## Milestones" = x[[1]] == "M3",
      "## Open items" = x[[3]] == "M3",
      TRUE
    )
  })
for (id in names(roles)) {
  i <- stringr::str_which(roadmap, paste0("^\\| ", id, " \\|"))
  x <- cells(roadmap[[i]])
  x[[3]] <- roles[[id]]
  roadmap[[i]] <- as_row(x)
}
write_text(roadmap, file.path(to, "project", "roadmap.md"))

# Budgets of the package work and the calls made under them
read_text(file.path(from, "calls", "README.md")) |>
  filter_rows(\(heading, x) stringr::str_detect(x[[3]], stringr::fixed("Package decisions (M3)"))) |>
  write_text(file.path(to, "calls", "README.md"))
for (log in list.files(file.path(from, "calls"), pattern = "-calls\\.csv$")) {
  lines <- read_text(file.path(from, "calls", log))
  purpose <- stringr::str_split_i(lines, ",", 3)
  write_text(lines[c(TRUE, stringr::str_starts(purpose[-1], "decisions-"))], file.path(to, "calls", log))
}

# Design, plan and build ledger of M3
dir.create(file.path(to, "plans"), recursive = TRUE)
invisible(file.copy(file.path(from, "plans", plans), file.path(to, "plans", plans)))

# The pages written for the package record
invisible(file.copy("data-raw/record/README.md", file.path(to, "README.md")))
invisible(file.copy("data-raw/record/contributions.md", file.path(to, "project", "contributions.md")))

# Build scripts of the record, from the same version of the skill
dir.create(".replication/lib", recursive = TRUE)
invisible(file.copy(file.path(project, ".replication", "build-site.mjs"), ".replication"))
invisible(file.copy(list.files(file.path(project, ".replication", "lib"), full.names = TRUE), ".replication/lib"))
invisible(file.copy("data-raw/record/site.config.json", ".replication"))

cat("Copied the record of the package into", to, "and .replication\n")
