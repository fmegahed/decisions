# Probe each decision-model provider once per case and save real responses
# as test fixtures. Run from the package root:
#   Rscript data-raw/probe_providers.R <provider> [<provider> ...]
# Providers: typesafe, openai, openrouter, clef, laya.
# Each paid call is one call: there is no retry loop. A failed request stops
# the run, so a person can read the error and fix the request.
# Keys come from Sys.getenv() only. No key goes to a file, a log or the console.

readRenviron("C:/Users/megahefm/Dropbox/Miami/Code/claude/fine_tuned_jev/.Renviron")
source("data-raw/log_call.R")

fixture_dir <- "tests/testthat/fixtures"
# Set with a second argument, e.g. `typesafe image,bad-type`, to rerun some cases.
only_cases <- NULL

# ---- Shared inputs ---------------------------------------------------------

text <- paste(
  "I was charged twice for order 4471 and nobody has answered my three",
  "emails. Please refund the extra charge today, or I will cancel my account."
)

base64_file <- function(file) {
  # jsonlite::base64_enc() wraps its output in lines; a provider rejects them
  gsub("\n", "", jsonlite::base64_enc(readBin(file, "raw", file.size(file))), fixed = TRUE)
}
image_data_url <- function(file) paste0("data:image/jpeg;base64,", base64_file(file))
image_file <- function(name) file.path("data-raw", paste0("test-image-", name, ".jpg"))

# ---- Saving and sending ----------------------------------------------------

to_json <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA)

#' Remove the response id and the account user id from a raw JSON body
drop_ids <- function(raw) {
  raw |>
    sub(pattern = '"id"[[:space:]]*:[[:space:]]*"[^"]*"[[:space:]]*,?', replacement = "") |>
    sub(pattern = ',?[[:space:]]*"user_id"[[:space:]]*:[[:space:]]*"[^"]*"', replacement = "")
}

#' Send one request, save request and response, and log paid calls
#' @param prefix Fixture prefix, for example `"typesafe"`.
#' @param case Case name, for example `"noul"`.
#' @param service Call-log service, or `NULL` for a free local call.
#' @param ok Whether a failure is expected (`FALSE` saves it as `-error`).
send <- function(prefix, case, url, body, key = NULL, headers = list(),
                 service = NULL, expect_error = FALSE, method = "POST") {
  if (!is.null(only_cases) && !(case %in% only_cases)) return(invisible(NULL))
  req <- httr2::request(url) |>
    httr2::req_headers(!!!headers) |>
    httr2::req_error(is_error = \(resp) FALSE)
  if (!is.null(key)) req <- httr2::req_auth_bearer_token(req, key)
  if (method == "POST") req <- httr2::req_body_json(req, body, auto_unbox = TRUE, digits = NA)
  started <- Sys.time()
  resp <- httr2::req_perform(req)
  latency_ms <- as.numeric(difftime(Sys.time(), started, units = "secs")) * 1000
  status <- httr2::resp_status(resp)
  raw <- httr2::resp_body_string(resp)
  cat(sprintf("%s %s: HTTP %s, %.0f ms\n", prefix, case, status, latency_ms))
  if (!is.null(service)) {
    log_call(service, resp, paste0("decisions-task2-", case),
             body$model %||% "", paste0(prefix, "-", case), latency_ms)
  }
  failed <- httr2::resp_is_error(resp)
  if (failed != expect_error) {
    cat(substr(raw, 1, 600), "\n")
    stop(prefix, " ", case, ": unexpected HTTP status ", status, call. = FALSE)
  }
  name <- if (expect_error) paste0(prefix, "-error") else paste0(prefix, "-", case)
  if (method == "POST") writeLines(to_json(body), file.path(fixture_dir, paste0(name, "-request.json")))
  writeLines(jsonlite::prettify(drop_ids(raw)), file.path(fixture_dir, paste0(name, ".json")))
  invisible(resp)
}

# ---- Question sets ---------------------------------------------------------
# The SystemOne format and OpenRouter use a map keyed by question name.
# The OpenAI format uses an array.

team <- c(billing = "Payments, charges and refunds.",
          technical = "Bugs and problems using the product.",
          shipping = "Delivery and tracking.")
urgency <- c("Low: no time pressure.",
             "Medium: the customer wants an answer soon.",
             "High: the customer threatens to leave or needs action today.")

systemone_questions <- function(openrouter = FALSE) {
  noul <- list(type = "noul", instructions = "Does the message ask for a refund?")
  if (openrouter) {
    noul$criteria <- list(`true` = "The message asks for money back.",
                          `false` = "The message does not ask for money back.")
  }
  list(
    noul = list(refund = noul),
    choice2 = list(team = list(
      type = "choice", instructions = "Which team should handle this message?",
      criteria = as.list(team[1:2]))),
    choice3 = list(team = list(
      type = "choice", instructions = "Which team should handle this message?",
      criteria = as.list(team))),
    score3 = list(urgency = list(
      type = "score", instructions = "How urgent is this message?",
      criteria = as.list(urgency)))
  )
}

openai_questions <- function() {
  choices <- function(x) unname(Map(\(v, d) list(value = v, description = d), names(x), x))
  list(
    noul = list(list(type = "predicate", name = "refund",
                     instructions = "Does the message ask for a refund?")),
    choice2 = list(list(type = "choice", name = "team",
                        instructions = "Which team should handle this message?",
                        choices = choices(team[1:2]))),
    choice3 = list(list(type = "choice", name = "team",
                        instructions = "Which team should handle this message?",
                        choices = choices(team))),
    score3 = list(list(type = "score", name = "urgency",
                       instructions = "How urgent is this message?",
                       levels = list(
                         list(label = "low", description = "No time pressure."),
                         list(label = "medium", description = "The customer wants an answer soon."),
                         list(label = "high", description = "The customer threatens to leave or needs action today."))))
  )
}

# One call per single question, then one call with all four questions.
# `combined` renames the clashing `team` question so that each name is unique.
combined_systemone <- function(q) {
  c(q$noul, list(team2 = q$choice2$team, team3 = q$choice3$team), q$score3)
}
combined_openai <- function(q) {
  q$choice2[[1]]$name <- "team2"
  q$choice3[[1]]$name <- "team3"
  c(q$noul, q$choice2, q$choice3, q$score3)
}

# ---- One function per provider ---------------------------------------------

probe_typesafe <- function(model = "jev-1.13.0") {
  key <- Sys.getenv("TYPESAFE_API_KEY")
  url <- "https://api.typesafe.ai/v1/systemone"
  post <- function(case, body, ...) {
    send("typesafe", case, url, body, key, service = "typesafe", ...)
  }
  q <- systemone_questions()
  for (case in names(q)) {
    post(case, list(model = model, state = list(message = text), questions = q[[case]]))
  }
  post("combined", list(model = model, state = list(message = text),
                        questions = combined_systemone(q)))
  post("latest", list(model = "jev-latest", state = list(message = text),
                      questions = q$noul))
  bad <- list(refund = list(type = "bogus", instructions = "Does the message ask for a refund?"))
  post("bad-type", list(model = model, state = list(message = text), questions = bad),
       expect_error = TRUE)
  # Image: assets form, one reference image per answer.
  asset <- \(name) list(type = "image", format = "jpg",
                        data_base64 = base64_file(image_file(name)))
  body <- list(
    model = model,
    state = list(inspection_image = "query"),
    assets = list(reference_normal = asset("reference-normal"),
                  reference_defect = asset("reference-defect"),
                  query = asset("streak")),
    questions = list(quality = list(
      type = "choice",
      instructions = "Inspect `inspection_image` for a surface defect. Select exactly one category.",
      criteria = list(
        normal = list(description = "A clean surface with no streak.", examples = list("reference_normal")),
        defective = list(description = "A dark streak across the surface.", examples = list("reference_defect")))))
  )
  post("image", body, headers = list("TypeSafe-Danger-Zone-Images" = "true"))
}

probe_openai <- function(model = "gpt-6-luna") {
  key <- Sys.getenv("OPENAI_API_KEY")
  url <- "https://api.openai.com/v1/decisions"
  post <- function(case, body, ...) {
    send("openai", case, url, body, key, service = "openai", ...)
  }
  q <- openai_questions()
  for (case in names(q)) {
    post(case, list(model = model, input = text, questions = q[[case]]))
  }
  post("combined", list(model = model, input = text, questions = combined_openai(q)))
  bad <- list(list(type = "bogus", name = "refund", instructions = "Does the message ask for a refund?"))
  post("bad-type", list(model = model, input = text, questions = bad), expect_error = TRUE)
  # Image: the references sit in the question instructions, the input comes last.
  part_text <- \(x) list(type = "input_text", text = x)
  part_image <- \(name) list(type = "input_image", image_url = image_data_url(image_file(name)))
  question <- list(type = "choice", name = "quality",
    instructions = list(
      part_text("Inspect the image for a surface defect. A clean surface looks like this:"),
      part_image("reference-normal"),
      part_text("A surface with a dark streak looks like this:"),
      part_image("reference-defect"),
      part_text("Select exactly one category for the image of the input.")),
    choices = list(
      list(value = "normal", description = "A clean surface with no streak."),
      list(value = "defective", description = "A dark streak across the surface.")))
  body <- list(model = model,
    input = list(list(role = "user", content = list(part_text("Image to inspect:"), part_image("streak")))),
    questions = list(question))
  post("image", body)
}

probe_openrouter <- function() {
  key <- Sys.getenv("OPENROUTER_API_KEY")
  url <- "https://openrouter.ai/api/alpha/decisions"
  q <- systemone_questions(openrouter = TRUE)
  models <- c("openrouter-jev" = "typesafe/jev-1.14",
              "openrouter-microsoft" = "microsoft/microsoft-decision-1")
  for (prefix in names(models)) {
    post <- function(case, body, ...) {
      send(prefix, case, url, body, key, service = "openrouter", ...)
    }
    model <- models[[prefix]]
    for (case in names(q)) {
      post(case, list(model = model, state = list(message = text), questions = q[[case]]))
    }
    post("combined", list(model = model, state = list(message = text),
                          questions = combined_systemone(q)))
    if (prefix == "openrouter-jev") {
      # Is `criteria` required for noul? (Its docs say so; SystemOne needs none.)
      post("noul-bare", list(model = model, state = list(message = text),
                             questions = systemone_questions()$noul))
      bad <- list(refund = list(type = "bogus", instructions = "Does the message ask for a refund?"))
      post("bad-type", list(model = model, state = list(message = text), questions = bad),
           expect_error = TRUE)
    }
  }
}

# Local servers: free, no call log.
probe_systemone_local <- function(prefix, base_url, model = NULL, state = text) {
  q <- systemone_questions()
  with_model <- \(body) if (is.null(model)) body else c(list(model = model), body)
  for (case in names(q)) {
    send(prefix, case, base_url, with_model(list(state = state, questions = q[[case]])))
  }
  send(prefix, "combined", base_url,
       with_model(list(state = state, questions = combined_systemone(q))))
  bad <- list(refund = list(type = "bogus", instructions = "Does the message ask for a refund?"))
  send(prefix, "bad-type", base_url, with_model(list(state = state, questions = bad)),
       expect_error = TRUE)
}

probe_clef <- function() {
  url <- "http://localhost:30000/v1/systemone"
  model <- "Cloudflare/clef-flash"
  probe_systemone_local("clef", url, model)
  # Image: ordered `images` list; the state text says which image is which.
  body <- list(
    model = model,
    state = paste("Image 1 is `inspection_image`, the image to inspect.",
                  "Reference images of the normal category: image 2.",
                  "Reference images of the defective category: image 3."),
    images = list(image_data_url(image_file("streak")),
                  image_data_url(image_file("reference-normal")),
                  image_data_url(image_file("reference-defect"))),
    questions = list(quality = list(
      type = "choice",
      instructions = "Inspect `inspection_image` for a surface defect. Select exactly one category.",
      criteria = list(normal = "A clean surface with no streak.",
                      defective = "A dark streak across the surface.")))
  )
  send("clef", "image", url, body, headers = list())
}

probe_laya <- function(base = "http://localhost:8000") {
  probe_systemone_local("laya", paste0(base, "/v1/systemone"), state = list(message = text))
  q <- systemone_questions()
  batch <- list(states = list(list(message = text),
                              list(message = "The app crashes every time I open the settings page.")),
                questions = q$choice3)
  send("laya", "batch", paste0(base, "/v1/systemone/batch"), batch)
  # `GET /models` of the Laya guide gives 404 on laya-serve (only a playground has it);
  # `GET /health` lists the loaded checkpoints.
  send("laya", "health", paste0(base, "/health"), NULL, method = "GET")
}

# ---- Run -------------------------------------------------------------------

if (!interactive() && sys.nframe() == 0) {
  what <- commandArgs(trailingOnly = TRUE)
  if (length(what) > 1 && !what[2] %in% c("typesafe", "openai", "openrouter", "clef", "laya")) {
    only_cases <- strsplit(what[2], ",")[[1]]
    what <- what[1]
  }
  for (provider in what) {
    switch(provider,
      typesafe = probe_typesafe(), openai = probe_openai(),
      openrouter = probe_openrouter(), clef = probe_clef(), laya = probe_laya(),
      stop("Unknown provider: ", provider))
  }
}
