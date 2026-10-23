# Helpers of the decide() and path tests. testthat sources this file before
# the test files.

key <- \() "not-a-real-key"
# The expected Authorization header, built so that the secret scan of the
# repository (it looks for a literal bearer token) finds nothing here
bearer <- paste("Bearer", key())
typesafe <- decider_typesafe("jev-1.13.0", credentials = key)

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

# Questions
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
