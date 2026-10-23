test_that("question_choice keeps the named answers", {
  choices <- c(normal = "A clean part.", defective = "A visible defect.")
  q <- question_choice("Which?", choices)
  expect_equal(q@answers, choices)
  expect_equal(q@instructions, "Which?")
})

test_that("question_choice keeps names with spaces", {
  q <- question_choice("Which?", c("not sure" = "Unclear.", yes = "Yes."))
  expect_equal(names(q@answers), c("not sure", "yes"))
})

test_that("question_choice rejects bad choices", {
  expect_error(question_choice("Which?", c("a", "b")), "named")
  expect_error(question_choice("Which?", c(a = "x", a = "y")), "unique")
  expect_error(question_choice("Which?", c(a = "x")), "at least 2")
  expect_error(question_choice("", c(a = "x", b = "y")), "instructions")
})

test_that("answers whose column names would clash are refused", {
  # "not sure" and "not_sure" both give the column .pred_not_sure
  expect_error(
    question_choice("Which?", c(`not sure` = "a", not_sure = "b")),
    "not_sure"
  )
  expect_error(
    question_score("How bad?", c(`a-b` = "x", `a b` = "y", c = "z")),
    "a_b"
  )
  # "?" and "!" both give the column .pred_X, as janitor names them
  expect_error(
    question_choice("Which?", c(`?` = "a", `!` = "b")), ".pred_X"
  )
  expect_no_error(question_choice("Which?", c(`?` = "a", yes = "b")))
  # After transliteration, "cafe" with an accent and "cafe" clash
  expect_error(
    question_choice("Which?", rlang::set_names(c("a", "b"),
                                               c("caf\u00e9", "cafe"))),
    "cafe"
  )
})

test_that("clean_name() gives what janitor::make_clean_names() gives", {
  # Expected values from janitor 2.2.1: make_clean_names(case = "none").
  # The non-ASCII names are written with escapes, so this file stays ASCII.
  expected <- c(
    "not sure" = "not_sure",
    "late / lost" = "late_lost",
    "caf\u00e9" = "cafe",
    "\u00c6r\u00f8" = "AEro",
    "Stra\u00dfe" = "Strasse",
    "\u0434\u0430" = "da",
    "1st check" = "X1st_check",
    "a.b" = "a_b",
    "50%" = "X50_percent",
    "#1" = "number_1",
    "it's" = "its",
    ".5 mm" = "X5_mm",
    "_low" = "low",
    "high_" = "high",
    "A&B" = "A_B",
    "x--y" = "x_y",
    "Yes!" = "Yes",
    "no" = "no",
    "n/a" = "n_a",
    # Also checked with janitor 2.2.1 here: an empty result becomes "X"
    "?" = "X",
    "m\u00b2" = "m2"
  )
  expect_equal(clean_name(names(expected)), unname(expected))
})

test_that("answers in another script are accepted", {
  # The Cyrillic words for "yes" and "no", written with escapes
  answers <- rlang::set_names(
    c("Yes.", "No."), c("\u0434\u0430", "\u043d\u0435\u0442")
  )
  question <- question_choice("Which?", answers)
  expect_equal(names(question@answers), names(answers))
})

test_that("question_score keeps levels in order", {
  q <- question_score("How bad?", c(low = "Fine.", mid = "Some.", high = "Bad."))
  expect_equal(names(q@answers), c("low", "mid", "high"))
})

test_that("question_score needs at least 2 levels", {
  expect_error(question_score("How bad?", c(low = "x")), "at least 2")
})

test_that("question_noul has true and false answers", {
  expect_equal(
    question_noul("Is it wet?")@answers,
    c(true = NA_character_, false = NA_character_)
  )
  q <- question_noul("Is it wet?", true = "Wet.", false = "Dry.")
  expect_equal(q@answers, c(true = "Wet.", false = "Dry."))
  expect_equal(question_noul("Is it wet?", true = "Wet.")@answers[["true"]], "Wet.")
})

test_that("the classes share a parent", {
  expect_true(S7::S7_inherits(question_noul("Q?"), question))
  expect_true(S7::S7_inherits(question_score("Q?", c(a = "x", b = "y")), question))
})

test_that("questions print briefly", {
  expect_snapshot({
    question_noul("Is it wet?", true = "Wet.")
    question_choice("Which?", c(normal = "A clean part.", "not sure" = "Unclear."))
  })
})
