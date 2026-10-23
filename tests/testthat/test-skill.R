skill_dir <- function() system.file("skills", "decisions", package = "decisions")

skill_files <- function() {
  list.files(skill_dir(), pattern = "[.]md$", recursive = TRUE, full.names = TRUE)
}

test_that("SKILL.md exists and its front matter names the skill and the functions", {
  skill <- file.path(skill_dir(), "SKILL.md")
  expect_true(file.exists(skill))
  lines <- readLines(skill, warn = FALSE)
  ends <- which(lines == "---")
  expect_identical(ends[1], 1L)
  front <- lines[seq(2, ends[2] - 1)]
  expect_true("name: decisions" %in% front)
  description <- paste(front[!startsWith(front, "name:")], collapse = " ")
  expect_match(description, "description:")
  for (fn in c("decide()", "score_setup()", "read_setup()")) {
    expect_match(description, fn, fixed = TRUE)
  }
  expect_lt(nchar(description), 700)
})

test_that("every file that SKILL.md links exists", {
  skill <- file.path(skill_dir(), "SKILL.md")
  text <- paste(readLines(skill, warn = FALSE), collapse = "\n")
  links <- regmatches(text, gregexpr("[]][(][^)#]+[)]", text))[[1]]
  links <- substr(links, 3, nchar(links) - 1)
  links <- links[!grepl("^https?://", links)]
  expect_gte(length(links), 4)
  expect_true(all(file.exists(file.path(skill_dir(), links))))
})

# External functions that the skill files may call. Keep this list short.
allowed_external <- c(
  "c", "list", "rep", "nrow", "unserialize",
  "probably::cal_estimate_isotonic"
)

# The calls in an R expression: a list of list(fun = "name", args = names).
calls_in <- function(x) {
  if (!is.call(x)) {
    return(list())
  }
  head <- x[[1]]
  here <- list()
  if (is.symbol(head) || (is.call(head) && identical(head[[1]], as.name("::")))) {
    fun <- paste(deparse(head), collapse = "")
    if (grepl("^[A-Za-z.][A-Za-z0-9_.:]*$", fun)) {
      arg_names <- names(x)[-1]
      here <- list(list(fun = fun, args = arg_names[!is.na(arg_names) & arg_names != ""]))
    }
  }
  c(here, unlist(lapply(as.list(x), calls_in), recursive = FALSE))
}

# Every call that a skill file shows: in fenced R code, and in a backticked
# `name()` or `name(arg = ...)` token that parses as a call.
skill_calls <- function(file) {
  lines <- readLines(file, warn = FALSE)
  fence <- cumsum(startsWith(lines, "```"))
  in_code <- fence %% 2 == 1 & !startsWith(lines, "```")
  code <- paste(lines[in_code], collapse = "\n")
  exprs <- if (nzchar(code)) as.list(parse(text = code, keep.source = FALSE)) else list()
  prose <- paste(lines[!in_code & !startsWith(lines, "```")], collapse = "\n")
  tokens <- regmatches(prose, gregexpr("`[^`]+[(][^`]*[)]`", prose))[[1]]
  tokens <- substr(tokens, 2, nchar(tokens) - 1)
  parsed <- lapply(tokens, function(token) tryCatch(parse(text = token)[[1]], error = function(e) NULL))
  unlist(lapply(c(exprs, parsed), calls_in), recursive = FALSE)
}

skill_problems <- function(dir) {
  exported <- getNamespaceExports("decisions")
  files <- list.files(dir, pattern = "[.]md$", recursive = TRUE, full.names = TRUE)
  unlist(lapply(files, function(file) {
    purrr::map_chr(skill_calls(file), function(call) {
      fun <- sub("^decisions::", "", call$fun)
      if (fun %in% exported) {
        unknown <- setdiff(call$args, names(formals(getExportedValue("decisions", fun))))
        if (length(unknown) == 0) NA_character_ else
          paste0(basename(file), ": ", fun, "() has no argument ", paste(unknown, collapse = ", "))
      } else if (call$fun %in% allowed_external) {
        NA_character_
      } else {
        paste0(basename(file), ": ", call$fun, "() is not exported or allowed")
      }
    })
  }))
}

test_that("the skill files call only exported functions, with real arguments", {
  dir <- skill_dir()
  expect_gte(length(skill_files()), 5)
  problems <- skill_problems(dir)
  expect_identical(unname(problems[!is.na(problems)]), character(0))
})

test_that("the drift check catches an invented function and a wrong argument", {
  copy <- withr::local_tempdir()
  file.copy(skill_dir(), copy, recursive = TRUE)
  file <- file.path(copy, "decisions", "SKILL.md")
  writeLines(c(readLines(file), "", "Use `tune_setup()` and `evaluate_once(role = x)`."), file)
  problems <- skill_problems(file.path(copy, "decisions"))
  expect_match(paste(problems, collapse = " "), "tune_setup() is not exported", fixed = TRUE)
  expect_match(paste(problems, collapse = " "), "evaluate_once() has no argument role", fixed = TRUE)
})
