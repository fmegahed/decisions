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

test_that("a server that keeps answering 503 gets one retry, then an error", {
  tries <- 0
  record_requests(\(req) {
    tries <<- tries + 1
    # A guard, so that unbounded retries fail the test and do not hang it
    if (tries > 10) stop("The server was hit more than 10 times.")
    httr2::response(503, headers = list(`Retry-After` = "0"),
                    body = charToRaw("busy"))
  })
  out <- decide(typesafe, list(refund = refund), text = "x")
  expect_equal(tries, 2)
  expect_match(out$.error, "HTTP 503", fixed = TRUE)
  expect_match(out$.error, "busy", fixed = TRUE)
  expect_true(is.na(out$.pred_class))
})

test_that("only the requests that got 429 or 503 are sent again", {
  tries <- c(a = 0, b = 0, c = 0)
  record_requests(\(req) {
    text <- state_text(req)
    tries[[text]] <<- tries[[text]] + 1
    if (text == "b" && tries[[text]] == 1) {
      return(httr2::response(429, headers = list(`Retry-After` = "0")))
    }
    fixture_response("typesafe-noul")
  })
  out <- suppressMessages(
    decide(typesafe, list(refund = refund), text = c("a", "b", "c"))
  )
  expect_equal(tries, c(a = 1, b = 2, c = 1))
  expect_true(all(is.na(out$.error)))
  expect_equal(as.character(out$.pred_class), c("true", "true", "true"))
})

test_that("the retry waits as Retry-After asks, at most 60 seconds", {
  wait_for <- \(...) retry_wait(list(httr2::response(429, headers = list(...))))
  expect_equal(wait_for(`Retry-After` = "7"), 7)
  expect_equal(wait_for(`Retry-After` = "3600"), 60)
  expect_equal(wait_for(`Retry-After` = "Wed, 21 Oct 2015 07:28:00 GMT"), 0)
  expect_equal(retry_wait(list(httr2::response(503))), 1)
  expect_equal(
    retry_wait(list(
      httr2::response(503, headers = list(`Retry-After` = "2")),
      httr2::response(503, headers = list(`Retry-After` = "5"))
    )),
    5
  )
})

test_that("an odd Retry-After keeps the 1 second default", {
  # A date needs the Date header of the response; here it is absent
  dated <- httr2::response(
    503, headers = list(`Retry-After` = "Wed, 21 Oct 2015 07:28:00 GMT")
  )
  dated$headers[["Date"]] <- NULL
  expect_equal(retry_wait(list(dated)), 1)
  soon <- httr2::response(503, headers = list(`Retry-After` = "soon"))
  expect_no_warning(expect_equal(retry_wait(list(soon)), 1))
})

test_that("an interrupt during the retry wait keeps the first answers", {
  tries <- c(a = 0, b = 0, c = 0)
  record_requests(\(req) {
    text <- state_text(req)
    tries[[text]] <<- tries[[text]] + 1
    if (text == "b") return(httr2::response(503))
    fixture_response("typesafe-noul")
  })
  # The user presses Esc while decide() waits before the retry
  local_mocked_bindings(retry_wait = function(responses) rlang::interrupt())
  out <- tryCatch(
    suppressMessages(
      decide(typesafe, list(refund = refund), text = c("a", "b", "c"))
    ),
    interrupt = \(cnd) NULL
  )
  expect_false(is.null(out))
  expect_equal(tries, c(a = 1, b = 1, c = 1))
  expect_equal(as.character(out$.pred_class), c("true", NA, "true"))
  expect_match(out$.error[2], "Interrupted before a retry", fixed = TRUE)
})

test_that("after an interrupt in the first pass, nothing is sent again", {
  # After Esc, req_perform_parallel() returns NULL for each request that did
  # not finish. (An interrupt raised inside a mocked response makes httr2
  # 1.2.3 loop, so the whole function is mocked here.)
  passes <- 0
  local_mocked_bindings(
    req_perform_parallel = function(reqs, ...) {
      passes <<- passes + 1
      list(httr2::response(503, headers = list(`Retry-After` = "0")), NULL,
           NULL)
    },
    .package = "httr2"
  )
  out <- decide(typesafe, list(refund = refund), text = c("a", "b", "c"))
  expect_equal(passes, 1)
  expect_match(out$.error[1], "HTTP 503", fixed = TRUE)
  expect_match(out$.error[2:3], "did not finish", fixed = TRUE)
})

test_that("a body in an unknown charset becomes a row error", {
  record_requests(\(req) {
    if (state_text(req) != "b") return(fixture_response("typesafe-noul"))
    httr2::response(
      200, headers = list(`Content-Type` = "application/json; charset=bogus"),
      body = charToRaw("{}")
    )
  })
  out <- suppressMessages(
    decide(typesafe, list(refund = refund), text = c("a", "b", "c"))
  )
  expect_equal(as.character(out$.pred_class), c("true", NA, "true"))
  expect_match(out$.error[2], "^The response cannot be read: ")
})

test_that("a condition message reaches .error without colours or newlines", {
  withr::local_options(cli.num_colors = 256)
  bad <- choice_body("team", "billing", c(billing = 0.5, technical = 0.5))
  bad$answers$team$probabilities$billing <- list(0.5, 0.5)
  record_requests(\(req) httr2::response_json(body = bad))
  out <- suppressMessages(decide(typesafe, list(team = team2), text = "x"))
  expect_match(out$.error, "^The response cannot be read: ")
  expect_false(grepl("\u001b", out$.error, fixed = TRUE))
  expect_false(grepl("\n", out$.error, fixed = TRUE))
})

test_that("rpm spaces the requests evenly", {
  log <- record_requests(\(req) fixture_response("typesafe-noul"))
  started <- Sys.time()
  out <- suppressMessages(
    decide(typesafe, list(refund = refund), text = c("a", "b", "c"), rpm = 120)
  )
  seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  expect_true(all(is.na(out$.error)))
  # One request at once, then one each 0.5 s: three requests take 1 s or more
  expect_gte(seconds, 0.9)
  realm <- log$requests[[1]]$policies$throttle_realm
  expect_equal(realm, "api.typesafe.ai")
  status <- httr2::throttle_status()
  expect_equal(status$capacity[status$realm == realm], 1)
})

test_that("path and ignore_hash are not implemented yet", {
  log <- record_requests(\(req) fixture_response("typesafe-noul"))
  expect_error(
    decide(typesafe, refund, text = "x", path = tempfile()),
    "not implemented"
  )
  expect_error(
    decide(typesafe, refund, text = "x", ignore_hash = TRUE),
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

test_that("malformed bodies become row errors and the other rows stay", {
  valid <- list(
    model = "jev-1.13.0",
    answers = list(
      refund = list(type = "noul", noul = 0.9),
      team = list(type = "choice", choice = "billing",
                  probabilities = list(billing = 0.8, technical = 0.2)),
      urgency = list(type = "score", score = 2,
                     probabilities = list(`0` = 0.1, `1` = 0.2, `2` = 0.7))
    ),
    usage = list(input_tokens = 20)
  )
  bodies <- list(valid1 = valid, valid2 = valid)
  bodies$answers_text <- valid
  bodies$answers_text$answers <- "oops"
  bodies$answer_text <- valid
  bodies$answer_text$answers <- list(refund = "yes", team = "yes",
                                     urgency = "yes")
  bodies$choice_array <- valid
  bodies$choice_array$answers$team$choice <- list("billing", "technical")
  bodies$noul_array <- valid
  bodies$noul_array$answers$refund$noul <- list(0.2, 0.8)
  bodies$score_array <- valid
  bodies$score_array$answers$urgency$score <- list(1, 2)
  bodies$model_array <- valid
  bodies$model_array$model <- list("a", "b")
  bodies$tokens_object <- valid
  bodies$tokens_object$usage <- list(input_tokens = list(a = 1, b = 2),
                                     cost = list(usd = 1))
  inputs <- c("valid1", "answers_text", "answer_text", "choice_array",
              "noul_array", "score_array", "model_array", "tokens_object",
              "valid2")
  record_requests(\(req) httr2::response_json(body = bodies[[state_text(req)]]))
  questions <- list(refund = refund, team = team2, urgency = urgency)
  out <- suppressMessages(decide(typesafe, questions, text = inputs))

  expect_equal(nrow(out), length(inputs))
  good <- inputs %in% c("valid1", "model_array", "tokens_object", "valid2")
  expect_equal(is.na(out$.error), good)
  expect_equal(as.character(out$team_.pred_class), ifelse(good, "billing", NA))
  expect_equal(out$urgency_.score, ifelse(good, 2, NA))
  # A malformed model or usage field becomes the decider model or NA
  expect_equal(out$.model[inputs == "model_array"], "jev-1.13.0")
  unread <- inputs %in% c("answers_text", "answer_text", "noul_array")
  expect_equal(
    out$.input_tokens, ifelse(unread | inputs == "tokens_object", NA, 20)
  )
  expect_true(all(is.na(out$.cost)))
  unreadable <- out$.error[unread]
  expect_match(unreadable, "^The response cannot be read: ")
  expect_match(unreadable, "jev-1.13.0", fixed = TRUE)
  expect_match(unreadable, "bytes): {", fixed = TRUE)
  expect_match(out$.error[inputs == "choice_array"], "team", fixed = TRUE)
  expect_match(out$.error[inputs == "score_array"], "urgency", fixed = TRUE)
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

sure <- question_choice("Is the part ready?", c(
  `not sure` = "The image does not show it.", yes = "The part is ready."
))

test_that("answer names give syntactic columns; the levels stay exact", {
  record_requests(\(req) httr2::response_json(
    body = choice_body("ready", "not sure", c(`not sure` = 0.6, yes = 0.4))
  ))
  out <- suppressMessages(decide(typesafe, list(ready = sure), text = "x"))
  expect_equal(levels(out$.pred_class), c("not sure", "yes"))
  expect_equal(as.character(out$.pred_class), "not sure")
  expect_equal(out$.pred_not_sure, 0.6)
  expect_equal(out$.pred_yes, 0.4)
  skip_if_not_installed("dplyr")
  predictions <- dplyr::select(out, dplyr::starts_with(".pred_"))
  expect_named(predictions, c(".pred_class", ".pred_not_sure", ".pred_yes"))
})

test_that("question names give clean prefixes; the request keeps them", {
  late <- question_choice("Where is the parcel?", c(
    `late / lost` = "It has not arrived.", delivered = "It arrived."
  ))
  log <- record_requests(\(req) httr2::response_json(body = list(
    model = "jev-1.13.0",
    answers = list(
      `parcel state` = list(type = "choice", choice = "late / lost",
                            probabilities = list(`late / lost` = 0.7,
                                                 delivered = 0.3)),
      refund = list(type = "noul", noul = 0.8)
    ),
    usage = list(input_tokens = 9)
  )))
  out <- suppressMessages(decide(
    typesafe, list(`parcel state` = late, refund = refund), text = "x"
  ))
  expect_named(
    httr2::req_get_body(log$requests[[1]])$questions,
    c("parcel state", "refund")
  )
  expect_equal(names(out)[1:6], c(
    "parcel_state_.pred_class", "parcel_state_.pred_late_lost",
    "parcel_state_.pred_delivered", "refund_.pred_class",
    "refund_.pred_true", "refund_.pred_false"
  ))
  expect_equal(
    levels(out$parcel_state_.pred_class), c("late / lost", "delivered")
  )
  expect_equal(out$parcel_state_.pred_late_lost, 0.7)
})

test_that("question names that clean to the same prefix are refused", {
  log <- record_requests(\(req) fixture_response("typesafe-noul"))
  expect_error(
    decide(typesafe, list(`a b` = refund, a_b = refund), text = "x"),
    "a_b"
  )
  expect_error(decide(typesafe, list(`?` = refund, b = refund), text = "x"))
  expect_length(log$requests, 0)
})

test_that("probably calibrates a two-answer choice with a spaced answer", {
  skip_if_not_installed("probably")
  p <- seq(0.05, 0.95, length.out = 40)
  record_requests(\(req) {
    i <- as.integer(state_text(req))
    choice <- if (p[i] >= 0.5) "yes" else "not sure"
    httr2::response_json(body = choice_body(
      "ready", choice, c(`not sure` = 1 - p[i], yes = p[i])
    ))
  })
  out <- suppressMessages(
    decide(typesafe, list(ready = sure), text = as.character(1:40))
  )
  out$truth <- factor(
    ifelse(p + rep(c(-0.3, 0.3), 20) > 0.5, "yes", "not sure"),
    levels = c("not sure", "yes")
  )
  # A control with plain names: "unsure" in place of "not sure"
  control <- out
  names(control)[names(control) == ".pred_not_sure"] <- ".pred_unsure"
  levels(control$.pred_class) <- c("unsure", "yes")
  levels(control$truth) <- c("unsure", "yes")
  same_as_control <- function(estimate) {
    calibrator <- estimate(out, truth = truth)
    expect_s3_class(calibrator, "cal_binary")
    spaced <- probably::cal_apply(out, calibrator)
    plain <- probably::cal_apply(control, estimate(control, truth = truth))
    expect_equal(spaced$.pred_yes, plain$.pred_yes)
    expect_equal(spaced$.pred_not_sure, plain$.pred_unsure)
    expect_equal(spaced$.pred_not_sure + spaced$.pred_yes, rep(1, 40))
  }
  same_as_control(probably::cal_estimate_isotonic)
  # The default logistic method fits a GAM with mgcv (in Suggests)
  skip_if_not_installed("mgcv")
  same_as_control(probably::cal_estimate_logistic)
})

test_that("answers in another script give transliterated columns", {
  # The Cyrillic words for "yes" and "no", written with escapes
  da_net <- c("\u0434\u0430", "\u043d\u0435\u0442")
  yes_no <- question_choice(
    "Is the part ready?", rlang::set_names(c("Yes.", "No."), da_net)
  )
  record_requests(\(req) httr2::response_json(body = choice_body(
    "ready", da_net[1], rlang::set_names(c(0.7, 0.3), da_net)
  )))
  out <- suppressMessages(decide(typesafe, list(ready = yes_no), text = "x"))
  expect_equal(names(out)[1:3], c(".pred_class", ".pred_da", ".pred_net"))
  expect_equal(levels(out$.pred_class), da_net)
  expect_equal(out$.pred_da, 0.7)
})

test_that("a question name that starts with a digit gets the prefix X", {
  record_requests(\(req) httr2::response_json(body = list(
    model = "jev-1.13.0",
    answers = list(
      `1st check` = list(type = "noul", noul = 0.8),
      refund = list(type = "noul", noul = 0.1)
    ),
    usage = list(input_tokens = 9)
  )))
  out <- suppressMessages(decide(
    typesafe, list(`1st check` = refund, refund = refund), text = "x"
  ))
  expect_equal(names(out)[1:3], c(
    "X1st_check_.pred_class", "X1st_check_.pred_true", "X1st_check_.pred_false"
  ))
  expect_equal(out$X1st_check_.pred_true, 0.8)
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

# Last in the file: before the fix, rpm = 0 made decide() wait forever.
test_that("rpm must be NULL or one number above 0", {
  log <- record_requests(\(req) fixture_response("typesafe-noul"))
  bad <- list(-1, "60", c(10, 20), NA, Inf, 0)
  purrr::walk(bad, \(rpm) {
    expect_error(
      decide(typesafe, list(refund = refund), text = "x", rpm = rpm), "rpm"
    )
  })
  expect_length(log$requests, 0)
})
