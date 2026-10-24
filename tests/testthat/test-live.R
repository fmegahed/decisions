# Live smoke tests: one tiny call per provider. They skip unless
# DECISIONS_LIVE_TESTS=true and the key of the provider is set (see
# helper-live.R). Each live call is paid. The Laya test is free but needs a
# running server.

live_text <- "I was charged twice. Please refund the extra charge."
live_question <- question_noul("Does the message ask for a refund?")

test_that("live: TypeSafe answers one noul question", {
  skip_if_not_live("TYPESAFE_API_KEY")
  out <- suppressMessages(
    decide(decider_typesafe(), live_question, text = live_text)
  )
  expect_noul_shape(out)
})

test_that("live: OpenAI answers one noul question", {
  skip_if_not_live("OPENAI_API_KEY")
  out <- suppressMessages(
    decide(decider_openai(), live_question, text = live_text)
  )
  expect_noul_shape(out)
})

test_that("live: OpenRouter answers one noul question", {
  skip_if_not_live("OPENROUTER_API_KEY")
  out <- suppressMessages(decide(
    decider_openrouter("microsoft/microsoft-decision-1"),
    live_question, text = live_text
  ))
  expect_noul_shape(out)
})

test_that("live: a local Laya server answers one noul question", {
  skip_if_no_laya()
  laya <- decider_systemone("http://localhost:8000", "english", input = "text")
  out <- suppressMessages(decide(laya, live_question, text = live_text))
  expect_noul_shape(out)
})
