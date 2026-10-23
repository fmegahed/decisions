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
  # "?" gives an empty column name
  expect_error(question_choice("Which?", c(`?` = "a", yes = "b")), "column")
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
