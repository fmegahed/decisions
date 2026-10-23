key <- \() "not-a-real-key"

# Printing and keys -------------------------------------------------------

test_that("print() never shows the key", {
  deciders <- list(
    decider_typesafe("jev-1.13.0", credentials = key),
    decider_openai("gpt-6-luna", credentials = key),
    decider_foundry("https://example.services.ai.azure.com", "decision-1",
                    credentials = key),
    decider_openrouter("typesafe/jev-1.14", credentials = key),
    decider_systemone("http://localhost:30000", "Cloudflare/clef-flash",
                      image_format = "images", credentials = key)
  )
  purrr::walk(deciders, \(decider) {
    printed <- capture.output(print(decider))
    expect_false(any(grepl("not-a-real-key", printed, fixed = TRUE)))
    expect_true(any(grepl(decider@model, printed, fixed = TRUE)))
  })
})

test_that("a decider stores no key and reads the variable at request time", {
  withr::local_envvar(TYPESAFE_API_KEY = "not-a-real-key")
  decider <- decider_typesafe("jev-1.13.0")
  values <- S7::props(decider)
  values$credentials <- NULL
  expect_false(any(unlist(values) == "not-a-real-key", na.rm = TRUE))
  withr::local_envvar(TYPESAFE_API_KEY = "another-fake-key")
  expect_equal(decider@credentials(), "another-fake-key")
})

test_that("a missing key gives an error that names the variable", {
  withr::local_envvar(
    TYPESAFE_API_KEY = NA, OPENAI_API_KEY = NA, OPENROUTER_API_KEY = NA,
    AZURE_FOUNDRY_API_KEY = NA
  )
  expect_error(decider_typesafe("jev-1.13.0")@credentials(), "TYPESAFE_API_KEY")
  expect_error(decider_openai("gpt-6-luna")@credentials(), "OPENAI_API_KEY")
  expect_error(decider_openrouter("x/y")@credentials(), "OPENROUTER_API_KEY")
  expect_error(
    decider_foundry("https://example.services.ai.azure.com", "d")@credentials(),
    "AZURE_FOUNDRY_API_KEY"
  )
  local <- decider_systemone("http://localhost:8000", "english")
  expect_null(local@credentials())
})

test_that("credentials must be a function, not the key itself", {
  expect_error(
    decider_typesafe("jev-1.13.0", credentials = "not-a-real-key"),
    "function"
  )
})

# Models ------------------------------------------------------------------

test_that("the default model is named in a message", {
  expect_message(decider <- decider_typesafe(), "jev-latest")
  expect_equal(decider@model, "jev-latest")
  expect_no_message(decider_typesafe("jev-1.13.0"))
  expect_message(decider <- decider_openai(), "gpt-6-luna")
  expect_equal(decider@model, "gpt-6-luna")
  expect_no_message(decider_openai("gpt-6-luna"))
})

test_that("OpenRouter and SystemOne servers need a model", {
  expect_error(decider_openrouter(), "model")
  expect_error(decider_systemone("http://localhost:8000"), "model")
  expect_error(decider_openrouter(""), "model")
})

test_that("Foundry needs an endpoint and uses the deployment as the model", {
  withr::local_envvar(AZURE_FOUNDRY_ENDPOINT = NA)
  expect_error(decider_foundry(deployment = "d"), "AZURE_FOUNDRY_ENDPOINT")
  withr::local_envvar(
    AZURE_FOUNDRY_ENDPOINT = "https://example.services.ai.azure.com"
  )
  decider <- decider_foundry(deployment = "decision-1")
  expect_equal(decider@model, "decision-1")
  expect_equal(decider@base_url, "https://example.services.ai.azure.com")
  expect_equal(decider@format, "systemone")
})

test_that("each decider has its provider, format and server root", {
  expect_equal(
    decider_typesafe("jev-1.13.0")@base_url, "https://api.typesafe.ai"
  )
  expect_equal(decider_typesafe("jev-1.13.0")@format, "systemone")
  expect_equal(decider_openai("gpt-6-luna")@base_url, "https://api.openai.com")
  expect_equal(decider_openai("gpt-6-luna")@format, "openai")
  expect_equal(decider_openrouter("x/y")@base_url, "https://openrouter.ai")
  expect_equal(decider_openrouter("x/y")@format, "openrouter")
  assets <- decider_systemone("http://localhost:8000", "english")
  expect_equal(assets@format, "systemone")
  expect_equal(assets@image_format, "assets")
  images <- decider_systemone(
    "http://localhost:30000", "m", image_format = "images"
  )
  expect_equal(images@format, "systemone_images")
  expect_equal(images@image_format, "images")
  expect_error(decider_systemone("http://x", "m", image_format = "files"))
})

# Input types -------------------------------------------------------------

test_that("the input type comes from the table of input types", {
  expect_equal(decider_typesafe("jev-1.13.0")@input, "text+image")
  expect_equal(decider_typesafe("jev-latest")@input, "text+image")
  expect_equal(decider_openai("gpt-6-luna")@input, "text+image")
  expect_equal(decider_openrouter("typesafe/jev-1.14")@input, "text")
  expect_equal(
    decider_openrouter("microsoft/microsoft-decision-1")@input, "text"
  )
  expect_equal(
    decider_foundry("https://example.services.ai.azure.com", "any-name")@input,
    "text"
  )
  clef <- decider_systemone(
    "http://localhost:30000", "Cloudflare/clef-flash", image_format = "images"
  )
  expect_equal(clef@input, "text+image")
  laya <- decider_systemone("http://localhost:8000", "english")
  expect_equal(laya@input, "text")
})

test_that("a model that is not in the table is not checked", {
  expect_true(is.na(decider_systemone("http://localhost:1", "new-model")@input))
  expect_true(is.na(decider_typesafe("other-model")@input))
})

test_that("input overrides the table and must be a known type", {
  expect_equal(decider_typesafe("jev-1.13.0", input = "text")@input, "text")
  expect_equal(
    decider_openrouter("x/y", input = "text+image")@input, "text+image"
  )
  expect_error(decider_typesafe("jev-1.13.0", input = "video"), "input")
})

test_that("every row of the table of input types is dated", {
  expect_named(input_types, c("provider", "model", "input", "checked"))
  expect_true(all(input_types$input %in% c("text", "image", "text+image")))
  expect_true(all(input_types$checked == as.Date("2026-10-23")))
})
