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

test_that("the skill files name only functions that the package exports", {
  exported <- getNamespaceExports("decisions")
  own <- "^(decide|decider_|question_|decision_|write_setup|read_setup|score_setup|evaluate_once)"
  files <- skill_files()
  expect_gte(length(files), 5)
  for (file in files) {
    text <- paste(readLines(file, warn = FALSE), collapse = "\n")
    called <- regmatches(text, gregexpr("[a-z][a-z0-9_]*(?=[(])", text, perl = TRUE))[[1]]
    called <- unique(called[grepl(own, called)])
    prefixed <- regmatches(text, gregexpr("decisions::[A-Za-z_][A-Za-z0-9_.]*", text))[[1]]
    prefixed <- unique(sub("^decisions::", "", prefixed))
    named <- c(called, prefixed)
    expect_true(
      all(named %in% exported),
      info = paste(basename(file), ":", paste(setdiff(named, exported), collapse = ", "))
    )
  }
})
