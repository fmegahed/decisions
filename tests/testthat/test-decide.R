# Helpers --------------------------------------------------------------------

key <- \() "not-a-real-key"
# The expected Authorization header, built so that the secret scan of the
# repository (it looks for a literal bearer token) finds nothing here
bearer <- paste("Bearer", key())
typesafe <-decider_typesafe("jev-1.13.0", credentials = key)

# A saved provider body as an httr2 response, byte for byte
fixture_response <- function(name, status = 200L, timing = NULL) {
  path <- test_path("fixtures", paste0(name, ".json"))
  httr2::response(
    status_code = status,
    headers = list(`Content-Type` = "application/json"),
    body = readBin(path, "raw", file.size(path)),
    timing = timing
  )
}

fixture <- function(name) {
  jsonlite::read_json(test_path("fixtures", paste0(name, ".json")))
}

# Mock every request with `respond(req)` and record the requests. The
# returned environment holds them in `requests`, so a test can count them.
record_requests <- function(respond, env = parent.frame()) {
  log <- new.env()
  log$requests <- list()
  httr2::local_mocked_responses(function(req) {
    log$requests <- c(log$requests, list(req))
    respond(req)
  }, env = env)
  log
}

# The text of a SystemOne request
state_text <- function(req) httr2::req_get_body(req)$state$text

# The size of a request body, serialized as httr2::req_body_json() does
body_bytes <- function(req) {
  json <- jsonlite::toJSON(
    httr2::req_get_body(req), auto_unbox = TRUE, digits = 22, null = "null"
  )
  nchar(json, type = "bytes")
}

# A SystemOne body with one choice answer
choice_body <- function(name, choice, probabilities, tokens = 10) {
  answers <- list()
  answers[[name]] <- list(
    type = "choice", choice = choice, probabilities = as.list(probabilities)
  )
  list(model = "jev-1.13.0", answers = answers,
       usage = list(input_tokens = tokens))
}

# A SystemOne body with one score answer (probabilities keyed by level index)
score_body <- function(probabilities) {
  names(probabilities) <- as.character(seq_along(probabilities) - 1)
  list(
    model = "jev-1.13.0",
    answers = list(urgency = list(
      type = "score", probabilities = as.list(probabilities)
    )),
    usage = list(input_tokens = 10)
  )
}

# The real probe JPEG (280 x 280 px) as a magick image
probe_image <- function() {
  data <- fixture("typesafe-image-request")$assets$query$data_base64
  magick::image_read(jsonlite::base64_dec(data))
}

refund <- question_noul("Does the message ask for a refund?")
team2 <- question_choice("Which team should handle this message?", c(
  billing = "Payments, charges and refunds.",
  technical = "Bugs and problems using the product."
))
quality <- question_choice("Inspect `inspection_image` for a defect.", c(
  normal = "A clean surface.", defective = "A dark streak."
))
urgency <- question_score("How urgent is this message?", c(
  Low = "no time pressure.", Medium = "an answer soon.", High = "action today."
))

# Requests ----------------------------------------------------------------

test_that("each decider sends its URL and its authentication", {
  respond <- \(req) {
    if (grepl("openai", req$url)) fixture_response("openai-noul")
    else fixture_response("typesafe-noul")
  }
  cases <- list(
    list(typesafe, "https://api.typesafe.ai/v1/systemone"),
    list(decider_openai("gpt-6-luna", credentials = key),
         "https://api.openai.com/v1/decisions"),
    list(decider_openrouter("typesafe/jev-1.14", credentials = key),
         "https://openrouter.ai/api/alpha/decisions"),
    list(decider_systemone("http://localhost:8000/", "english",
                           credentials = key),
         "http://localhost:8000/v1/systemone")
  )
  purrr::walk(cases, \(case) {
    log <- record_requests(respond)
    suppressMessages(decide(case[[1]], list(refund = refund), text = "x"))
    req <- log$requests[[1]]
    expect_equal(req$url, case[[2]])
    expect_equal(
      httr2::req_get_headers(req, "reveal")$Authorization,
      bearer
    )
  })
})

test_that("Foundry sends the key in the api-key header", {
  log <- record_requests(\(req) fixture_response("typesafe-noul"))
  foundry <- decider_foundry(
    "https://example.services.ai.azure.com", "decision-1", credentials = key
  )
  suppressMessages(decide(foundry, list(refund = refund), text = "x"))
  req <- log$requests[[1]]
  expect_equal(
    req$url,
    "https://example.services.ai.azure.com/providers/microsoft/v1/systemone"
  )
  headers <- httr2::req_get_headers(req, "reveal")
  expect_equal(headers$`api-key`, "not-a-real-key")
  expect_null(headers$Authorization)
})

test_that("a local SystemOne server without credentials gets no key", {
  log <- record_requests(\(req) fixture_response("typesafe-noul"))
  local <- decider_systemone("http://localhost:8000", "english")
  suppressMessages(decide(local, list(refund = refund), text = "x"))
  expect_null(httr2::req_get_headers(log$requests[[1]], "reveal")$Authorization)
})

test_that("the key is read at request time, and a missing key stops decide()", {
  withr::local_envvar(TYPESAFE_API_KEY = NA)
  log <- record_requests(\(req) fixture_response("typesafe-noul"))
  decider <- decider_typesafe("jev-1.13.0")
  expect_error(decide(decider, refund, text = "x"), "TYPESAFE_API_KEY")
  expect_length(log$requests, 0)
  withr::local_envvar(TYPESAFE_API_KEY = "not-a-real-key")
  suppressMessages(decide(decider, list(refund = refund), text = "x"))
  expect_equal(
    httr2::req_get_headers(log$requests[[1]], "reveal")$Authorization,
    bearer
  )
})

test_that("the body is the body of build_body(), one request per input", {
  log <- record_requests(\(req) fixture_response("typesafe-noul"))
  suppressMessages(decide(typesafe, list(refund = refund), text = c("a", "b")))
  expect_length(log$requests, 2)
  bodies <- purrr::map(log$requests, httr2::req_get_body)
  expect_equal(
    bodies[[2]],
    build_body("systemone", "jev-1.13.0", list(refund = refund), "b")
  )
  expect_equal(purrr::map_chr(log$requests, state_text), c("a", "b"))
})

test_that("a single question without a name is sent as `question`", {
  log <- record_requests(\(req) httr2::response_json(body = list(
    model = "jev-1.13.0",
    answers = list(question = list(type = "noul", noul = 0.2)),
    usage = list(input_tokens = 5)
  )))
  out <- suppressMessages(decide(typesafe, refund, text = "x"))
  expect_named(httr2::req_get_body(log$requests[[1]])$questions, "question")
  expect_equal(as.character(out$.pred_class), "false")
  expect_equal(out$.pred_true, 0.2)
})

test_that("TypeSafe gets the image header only when an image is sent", {
  skip_if_not_installed("magick")
  log <- record_requests(\(req) fixture_response("typesafe-image"))
  suppressMessages(decide(typesafe, list(quality = quality), text = "x"))
  suppressMessages(
    decide(typesafe, list(quality = quality), image = list(probe_image()))
  )
  headers <- purrr::map(log$requests, httr2::req_get_headers)
  expect_null(headers[[1]]$`TypeSafe-Danger-Zone-Images`)
  expect_equal(headers[[2]]$`TypeSafe-Danger-Zone-Images`, "true")
})

test_that("a 503 is tried again", {
  tries <- 0
  record_requests(\(req) {
    tries <<- tries + 1
    if (tries == 1) {
      return(httr2::response(503, headers = list(`Retry-After` = "0")))
    }
    fixture_response("typesafe-noul")
  })
  out <- suppressMessages(decide(typesafe, list(refund = refund), text = "x"))
  expect_equal(tries, 2)
  expect_true(is.na(out$.error))
})

test_that("rpm throttles the requests without changing the answers", {
  record_requests(\(req) fixture_response("typesafe-noul"))
  out <- suppressMessages(
    decide(typesafe, list(refund = refund), text = c("a", "b"), rpm = 600)
  )
  expect_equal(nrow(out), 2)
  expect_true(all(is.na(out$.error)))
})

test_that("path is not implemented yet", {
  log <- record_requests(\(req) fixture_response("typesafe-noul"))
  expect_error(
    decide(typesafe, refund, text = "x", path = tempfile()),
    "not implemented"
  )
  expect_length(log$requests, 0)
})

# Input types and images ----------------------------------------------------

test_that("an image to a text-only model stops before any request", {
  log <- record_requests(\(req) fixture_response("typesafe-image"))
  text_only <- decider_typesafe("jev-1.13.0", credentials = key, input = "text")
  expect_error(
    decide(text_only, list(quality = quality), image = "no-such-file.jpg"),
    "image"
  )
  expect_error(
    decide(text_only, list(quality = quality), text = "x",
           references = list(normal = "no-such-file.jpg")),
    "image"
  )
  expect_length(log$requests, 0)
  skip_if_not_installed("magick")
  both <- decider_typesafe(
    "jev-1.13.0", credentials = key, input = "text+image"
  )
  out <- suppressMessages(
    decide(both, list(quality = quality), image = list(probe_image()))
  )
  expect_length(log$requests, 1)
  expect_equal(as.character(out$.pred_class), "defective")
})

test_that("a text to an image-only model stops before any request", {
  log <- record_requests(\(req) fixture_response("typesafe-noul"))
  image_only <- decider_typesafe(
    "jev-1.13.0", credentials = key, input = "image"
  )
  expect_error(decide(image_only, list(refund = refund), text = "x"), "text")
  expect_length(log$requests, 0)
})

test_that("references are prepared once per call, inputs once each", {
  prepared <- character()
  three_channels <- logical()
  local_mocked_bindings(prepare_image = function(image, max_size, upscale,
                                                 crop, rgb = FALSE) {
    prepared <<- c(prepared, image)
    three_channels <<- c(three_channels, rgb)
    charToRaw(image)
  })
  log <- record_requests(\(req) fixture_response("typesafe-image"))
  references <- list(normal = c("n1.jpg", "n2.jpg"), defective = "d1.jpg")
  suppressMessages(decide(
    typesafe, list(quality = quality), image = c("a.jpg", "b.jpg", "c.jpg"),
    references = references
  ))
  expect_equal(sort(prepared), sort(c("n1.jpg", "n2.jpg", "d1.jpg",
                                      "a.jpg", "b.jpg", "c.jpg")))
  expect_false(any(three_channels))
  body <- httr2::req_get_body(log$requests[[3]])
  expect_named(
    body$assets, c("reference_1", "reference_2", "reference_3", "query")
  )
  expect_equal(
    rawToChar(jsonlite::base64_dec(body$assets$query$data_base64)), "c.jpg"
  )
  expect_equal(
    rawToChar(jsonlite::base64_dec(body$assets$reference_3$data_base64)),
    "d1.jpg"
  )
})

test_that("the image-list format gets three-channel images", {
  three_channels <- logical()
  local_mocked_bindings(prepare_image = function(image, max_size, upscale,
                                                 crop, rgb = FALSE) {
    three_channels <<- c(three_channels, rgb)
    charToRaw(image)
  })
  record_requests(\(req) fixture_response("clef-image"))
  clef <- decider_systemone(
    "http://localhost:30000", "Cloudflare/clef-flash", image_format = "images"
  )
  suppressMessages(decide(clef, list(quality = quality), image = "a.jpg",
                          references = list(normal = "n.jpg")))
  expect_equal(three_channels, c(TRUE, TRUE))
})

test_that("references need one question and names among its answers", {
  log <- record_requests(\(req) fixture_response("typesafe-image"))
  expect_error(
    decide(typesafe, list(quality = quality, team = team2), image = "a.jpg",
           references = list(normal = "n.jpg")),
    "one question"
  )
  expect_error(
    decide(typesafe, list(quality = quality), image = "a.jpg",
           references = list(broken = "n.jpg")),
    "broken"
  )
  expect_error(
    decide(typesafe, list(quality = quality), image = "a.jpg",
           references = list(normal = character())),
    "image"
  )
  expect_length(log$requests, 0)
})

test_that("inputs and questions are checked before any request", {
  log <- record_requests(\(req) fixture_response("typesafe-noul"))
  expect_error(decide(typesafe, list(refund = refund)), "text")
  expect_error(
    decide(typesafe, list(refund = refund), text = c("a", "b"),
           image = "a.jpg"),
    "same length"
  )
  expect_error(decide(typesafe, list(refund = refund), text = NA), "text")
  expect_error(decide(typesafe, list(refund, refund), text = "x"), "named")
  expect_error(decide(typesafe, list(a = "not a question"), text = "x"))
  expect_error(decide("typesafe", list(refund = refund), text = "x"), "decider")
  odd <- question_choice("Pick one.", c(class = "A class.", other = "Other."))
  expect_error(decide(typesafe, list(odd = odd), text = "x"), "class")
  expect_length(log$requests, 0)
})

# Output --------------------------------------------------------------------

test_that("a batch keeps every row in input order, with the errors", {
  bad <- fixture("typesafe-choice2")
  bad$answers$team$choice <- "sales"
  log <- record_requests(\(req) switch(state_text(req),
    first = fixture_response("typesafe-choice2"),
    second = httr2::response(500, body = charToRaw("model overloaded")),
    third = httr2::response_json(body = bad)
  ))
  out <- suppressMessages(decide(
    typesafe, list(team = team2), text = c("first", "second", "third")
  ))
  expect_equal(nrow(out), 3)
  expect_equal(as.character(out$.pred_class), c("billing", NA, NA))
  expect_equal(out$.pred_billing, c(1, NA, NA))
  expect_equal(out$.pred_technical, c(0, NA, NA))
  expect_true(is.na(out$.error[1]))
  second <- purrr::detect(log$requests, \(req) state_text(req) == "second")
  expect_match(out$.error[2], "model overloaded", fixed = TRUE)
  expect_match(out$.error[2], "jev-1.13.0", fixed = TRUE)
  expect_match(out$.error[2], paste(body_bytes(second), "bytes"), fixed = TRUE)
  expect_match(out$.error[3], "sales", fixed = TRUE)
  # The third call was answered and paid: its tokens stay
  expect_equal(out$.input_tokens, c(358, NA, 358))
})

test_that("a provider error reaches .error word for word", {
  record_requests(\(req) fixture_response("openai-error", status = 400L))
  openai <- decider_openai("gpt-6-luna", credentials = key)
  out <- decide(openai, list(refund = refund), text = "x")
  message <- fixture("openai-error")$error$message
  expect_match(out$.error, message, fixed = TRUE)
  expect_match(out$.error, "HTTP 400", fixed = TRUE)
  expect_true(is.na(out$.pred_class))
})

test_that("a response that is not JSON becomes a row error", {
  record_requests(\(req) httr2::response(200, body = charToRaw("<html>")))
  out <- decide(typesafe, list(refund = refund), text = "x")
  expect_match(out$.error, "<html>", fixed = TRUE)
  expect_true(is.na(out$.pred_class))
})

test_that("a response without an answer becomes a row error", {
  record_requests(\(req) httr2::response_json(body = list(
    model = "jev-1.13.0", answers = list(), usage = list(input_tokens = 5)
  )))
  out <- suppressMessages(decide(typesafe, list(refund = refund), text = "x"))
  expect_match(out$.error, "refund", fixed = TRUE)
  expect_true(is.na(out$.pred_true))
})

test_that("a score with zero or missing probabilities becomes a row error", {
  record_requests(\(req) switch(state_text(req),
    zero = httr2::response_json(body = score_body(c(0, 0, 0))),
    missing = httr2::response_json(body = score_body(c(0.2, 0.8))),
    good = httr2::response_json(body = score_body(c(0.2, 0.3, 0.5)))
  ))
  out <- suppressMessages(decide(
    typesafe, list(urgency = urgency), text = c("zero", "missing", "good")
  ))
  expect_match(out$.error[1], "urgency", fixed = TRUE)
  expect_match(out$.error[2], "urgency", fixed = TRUE)
  expect_true(is.na(out$.error[3]))
  expect_equal(as.character(out$.pred_class), c(NA, NA, "High"))
  expect_equal(out$.score, c(NA, NA, 1.3))
})

test_that("one question gives .pred_ columns; a score adds .score", {
  record_requests(\(req) fixture_response("typesafe-score3"))
  out <- suppressMessages(decide(typesafe, list(urgency = urgency), text = "x"))
  expect_named(out, c(
    ".pred_class", ".pred_Low", ".pred_Medium", ".pred_High", ".score",
    ".model", ".input_tokens", ".cost", ".seconds", ".error"
  ))
  expect_equal(levels(out$.pred_class), c("Low", "Medium", "High"))
  expect_equal(out$.score, 2)
  expect_equal(out$.model, "jev-1.13.0")
})

test_that("several questions give prefixed columns", {
  team3 <- question_choice("Which team should handle this message?", c(
    billing = "Payments.", technical = "Bugs.", shipping = "Delivery."
  ))
  questions <- list(refund = refund, team2 = team2, team3 = team3,
                    urgency = urgency)
  record_requests(\(req) fixture_response("typesafe-combined"))
  out <- suppressMessages(decide(typesafe, questions, text = "x"))
  expect_named(out, c(
    "refund_.pred_class", "refund_.pred_true", "refund_.pred_false",
    "team2_.pred_class", "team2_.pred_billing", "team2_.pred_technical",
    "team3_.pred_class", "team3_.pred_billing", "team3_.pred_technical",
    "team3_.pred_shipping",
    "urgency_.pred_class", "urgency_.pred_Low", "urgency_.pred_Medium",
    "urgency_.pred_High", "urgency_.score",
    ".model", ".input_tokens", ".cost", ".seconds", ".error"
  ))
  expect_equal(levels(out$refund_.pred_class), c("true", "false"))
  expect_equal(as.character(out$refund_.pred_class), "true")
  expect_equal(out$refund_.pred_true, 0.99)
  expect_equal(as.character(out$team3_.pred_class), "billing")
  expect_equal(out$urgency_.score, 2)
  expect_equal(out$.input_tokens, 509)
})

test_that("answer names with spaces keep their exact names", {
  sure <- question_choice("Is the part ready?", c(
    `not sure` = "The image does not show it.", yes = "The part is ready."
  ))
  record_requests(\(req) httr2::response_json(
    body = choice_body("ready", "not sure", c(`not sure` = 0.6, yes = 0.4))
  ))
  out <- suppressMessages(decide(typesafe, list(ready = sure), text = "x"))
  expect_equal(levels(out$.pred_class), c("not sure", "yes"))
  expect_equal(as.character(out$.pred_class), "not sure")
  expect_equal(out$`.pred_not sure`, 0.6)
  expect_equal(out$.pred_yes, 0.4)
  skip_if_not_installed("dplyr")
  predictions <- dplyr::select(out, dplyr::starts_with(".pred_"))
  expect_named(predictions, c(".pred_class", ".pred_not sure", ".pred_yes"))
})

test_that("probably calibrates the output of a two-answer choice question", {
  skip_if_not_installed("probably")
  p <- seq(0.05, 0.95, length.out = 40)
  record_requests(\(req) {
    i <- as.integer(state_text(req))
    choice <- if (p[i] >= 0.5) "defective" else "normal"
    httr2::response_json(body = choice_body(
      "quality", choice, c(normal = 1 - p[i], defective = p[i])
    ))
  })
  out <- suppressMessages(
    decide(typesafe, list(quality = quality), text = as.character(1:40))
  )
  out$truth <- factor(
    ifelse(p + rep(c(-0.3, 0.3), 20) > 0.5, "defective", "normal"),
    levels = c("normal", "defective")
  )
  # A logistic regression needs no package beyond probably
  calibrator <- probably::cal_estimate_logistic(
    out, truth = truth, smooth = FALSE
  )
  expect_s3_class(calibrator, "cal_binary")
  # The default (smooth) method fits a GAM with mgcv, which R CMD check
  # hides because the package does not declare it
  skip_if_not_installed("mgcv")
  calibrator <- probably::cal_estimate_logistic(out, truth = truth)
  expect_s3_class(calibrator, "cal_binary")
})

test_that(".seconds holds the time of each response", {
  record_requests(
    \(req) fixture_response("typesafe-noul", timing = c(total = 1.25))
  )
  out <- suppressMessages(decide(typesafe, list(refund = refund), text = "x"))
  expect_equal(out$.seconds, 1.25)
})

# Cost ----------------------------------------------------------------------

test_that("TypeSafe reports no cost: .cost is NA and one message per call", {
  record_requests(\(req) fixture_response("typesafe-noul"))
  messages <- capture_messages(
    out <- decide(typesafe, list(refund = refund), text = c("a", "b", "c"))
  )
  expect_true(all(is.na(out$.cost)))
  expect_equal(out$.input_tokens, c(313, 313, 313))
  cost <- grepl("TypeSafe does not report a cost", messages, fixed = TRUE)
  expect_equal(sum(cost), 1)
  expect_match(messages[cost], "`.cost` is NA", fixed = TRUE)
})

test_that("each provider is named in the cost message", {
  record_requests(\(req) {
    if (grepl("openai", req$url)) fixture_response("openai-noul")
    else fixture_response("typesafe-noul")
  })
  cases <- list(
    list(decider_openai("gpt-6-luna", credentials = key), "OpenAI"),
    list(decider_foundry("https://example.services.ai.azure.com", "d",
                         credentials = key), "Microsoft Foundry"),
    list(decider_systemone("http://localhost:8000", "english"),
         "The server at http://localhost:8000")
  )
  purrr::walk(cases, \(case) {
    expect_message(
      decide(case[[1]], list(refund = refund), text = "x"),
      paste(case[[2]], "does not report a cost"), fixed = TRUE
    )
  })
})

test_that("OpenRouter reports a cost: .cost holds it and no message", {
  record_requests(\(req) fixture_response("openrouter-jev-noul"))
  openrouter <- decider_openrouter("typesafe/jev-1.14", credentials = key)
  expect_no_message(
    out <- decide(openrouter, list(refund = refund), text = "x")
  )
  expect_equal(out$.cost, 0.00001449)
  expect_equal(out$.model, "typesafe/jev-1.14-20261014")
})

test_that("no cost message when every call failed", {
  record_requests(\(req) fixture_response("typesafe-error", status = 400L))
  expect_no_message(out <- decide(typesafe, list(refund = refund), text = "x"))
  expect_match(out$.error, "Invalid request.", fixed = TRUE)
  expect_equal(out$.model, "jev-1.13.0")
})
