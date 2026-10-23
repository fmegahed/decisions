# Helpers --------------------------------------------------------------------

# Read a saved fixture as a list (no simplification)
fixture <- function(name) {
  jsonlite::read_json(test_path("fixtures", paste0(name, ".json")))
}

# Serialize a body as httr2::req_body_json() does, and read it back
on_the_wire <- function(body) {
  jsonlite::toJSON(body, auto_unbox = TRUE, digits = 22, null = "null")
}
round_trip <- function(body) jsonlite::parse_json(on_the_wire(body))

# Base64 on one line, written here apart from the package code
b64 <- function(bytes) gsub("\n", "", jsonlite::base64_enc(bytes), fixed = TRUE)

# Check that each string occurs in the serialized body, in the given order
# (the first occurrence of each counts). This is the D171 order on the wire.
expect_in_order <- function(body, ...) {
  json <- as.character(on_the_wire(body))
  at <- purrr::map_int(c(...), \(x) regexpr(x, json, fixed = TRUE)[[1]])
  expect_true(all(at > 0), label = "every part occurs in the JSON text")
  expect_equal(order(at), seq_along(at), label = "the order of the parts")
}

# Compare a built body with a saved request body
#
# D171 changes the order of the top-level fields, so only that order is
# ignored. The order inside each field must match.
expect_same_body <- function(body, expected, label) {
  top_sorted <- function(x) x[order(names(x))]
  expect_equal(
    top_sorted(round_trip(body)), top_sorted(expected), label = label
  )
}

text <- fixture("openai-noul-request")$input

# The three real JPEG images of the probes (280 x 280 px)
probe_assets <- fixture("typesafe-image-request")$assets
img <- list(
  normal = jsonlite::base64_dec(probe_assets$reference_normal$data_base64),
  defect = jsonlite::base64_dec(probe_assets$reference_defect$data_base64),
  query = jsonlite::base64_dec(probe_assets$query$data_base64)
)
references <- list(normal = list(img$normal), defective = list(img$defect))
several <- list(
  normal = list(as.raw(1:3), as.raw(4:6)),
  defective = list(as.raw(7:9))
)

# The questions of the probes (data-raw/probe_providers.R)
team <- c(
  billing = "Payments, charges and refunds.",
  technical = "Bugs and problems using the product.",
  shipping = "Delivery and tracking."
)
refund <- question_noul("Does the message ask for a refund?")
refund_described <- question_noul(
  "Does the message ask for a refund?",
  true = "The message asks for money back.",
  false = "The message does not ask for money back."
)
team2 <- question_choice("Which team should handle this message?", team[1:2])
team3 <- question_choice("Which team should handle this message?", team)
# SystemOne sends each level as "<name>: <description>"; OpenAI sends both.
urgency_systemone <- question_score("How urgent is this message?", c(
  Low = "no time pressure.",
  Medium = "the customer wants an answer soon.",
  High = "the customer threatens to leave or needs action today."
))
urgency_openai <- question_score("How urgent is this message?", c(
  low = "No time pressure.",
  medium = "The customer wants an answer soon.",
  high = "The customer threatens to leave or needs action today."
))
surface <- c(
  normal = "A clean surface with no streak.",
  defective = "A dark streak across the surface."
)
quality <- question_choice(paste(
  "Inspect `inspection_image` for a surface defect.",
  "Select exactly one category."
), surface)

# The question set of each probe case
probe_questions <- function(case, provider) {
  noul <- if (startsWith(provider, "openrouter")) refund_described else refund
  urgency <- if (provider == "openai") urgency_openai else urgency_systemone
  switch(case,
    noul = list(refund = noul),
    `noul-bare` = ,
    latest = list(refund = refund),
    choice2 = list(team = team2),
    choice3 = list(team = team3),
    score3 = list(urgency = urgency),
    combined = list(
      refund = noul, team2 = team2, team3 = team3, urgency = urgency
    ),
    image = list(quality = quality)
  )
}

provider_format <- c(
  typesafe = "systemone", laya = "systemone", clef = "systemone_images",
  `openrouter-jev` = "openrouter", `openrouter-microsoft` = "openrouter",
  openai = "openai"
)

# build_body(): the saved request bodies ----------------------------------

test_that("build_body() makes the saved text requests of each provider", {
  text_cases <- c("noul", "choice2", "choice3", "score3", "combined")
  cases <- list(
    list("typesafe", "jev-1.13.0", text_cases),
    list("typesafe", "jev-latest", "latest"),
    list("laya", NULL, text_cases),
    list("clef", "Cloudflare/clef-flash", text_cases),
    list("openrouter-jev", "typesafe/jev-1.14", c(text_cases, "noul-bare")),
    list("openrouter-microsoft", "microsoft/microsoft-decision-1", text_cases),
    list("openai", "gpt-6-luna", text_cases)
  )
  for (case in cases) {
    provider <- case[[1]]
    for (name in case[[3]]) {
      expected <- fixture(paste0(provider, "-", name, "-request"))
      # The probes named the state field `message`; the package names it
      # `text`, after the argument of decide(). The field name is free.
      if (is.list(expected$state)) {
        expected$state <- list(text = expected$state$message)
      }
      format <- provider_format[[provider]]
      questions <- probe_questions(name, provider)
      body <- build_body(format, case[[2]], questions, text)
      expect_same_body(body, expected, paste(provider, name))
    }
  }
})

test_that("build_body() makes the saved TypeSafe image request", {
  expected <- fixture("typesafe-image-request")
  # The package numbers the reference assets; the probe named them.
  names(expected$assets) <- c("reference_1", "reference_2", "query")
  criteria <- expected$questions$quality$criteria
  criteria$normal$examples <- list("reference_1")
  criteria$defective$examples <- list("reference_2")
  expected$questions$quality$criteria <- criteria
  body <- build_body(
    "systemone", "jev-1.13.0", list(quality = quality),
    image = img$query, references = references
  )
  expect_same_body(body, expected, "typesafe image")
})

test_that("build_body() makes the saved Clef-Flash image request", {
  expected <- fixture("clef-image-request")
  # The probe sent the inspected image first. D171 puts it last.
  expected$images <- expected$images[c(2, 3, 1)]
  expected$state <- paste(
    "Reference images of the answer `normal`: image 1.",
    "Reference images of the answer `defective`: image 2.",
    "Image 3 is `inspection_image`, the image to inspect.",
    sep = "\n"
  )
  body <- build_body(
    "systemone_images", "Cloudflare/clef-flash", list(quality = quality),
    image = img$query, references = references
  )
  expect_same_body(body, expected, "clef image")
})

test_that("build_body() makes the saved OpenAI image request", {
  expected <- fixture("openai-image-request")
  saved <- expected$questions[[1]]$instructions
  question <- question_choice(
    "Inspect the image for a surface defect. Select exactly one category.",
    surface
  )
  # The probe wrote its own sentences around the reference images; the
  # package labels each group with its answer. The images are the same.
  label <- \(answer) paste0("Reference images of the answer `", answer, "`:")
  expected$questions[[1]]$instructions <- list(
    list(type = "input_text", text = question@instructions),
    list(type = "input_text", text = label("normal")),
    saved[[2]],
    list(type = "input_text", text = label("defective")),
    saved[[4]]
  )
  body <- build_body(
    "openai", "gpt-6-luna", list(quality = question),
    image = img$query, references = references
  )
  expect_same_body(body, expected, "openai image")
})

# build_body(): SystemOne -------------------------------------------------

test_that("a SystemOne body has model, state, assets and questions", {
  body <- build_body(
    "systemone", "jev-1.13.0", list(refund = refund, quality = quality),
    text = "A part.", image = img$query, references = references
  )
  expect_setequal(names(body), c("model", "state", "assets", "questions"))
  expect_equal(
    body$questions$refund,
    list(type = "noul", instructions = refund@instructions)
  )
  expect_equal(body$questions$quality$type, "choice")
  expect_equal(
    body$questions$quality$criteria$normal,
    list(description = surface[["normal"]], examples = list("reference_1"))
  )
  expect_equal(body$state, list(text = "A part.", inspection_image = "query"))
})

test_that("SystemOne puts instructions and references before the input", {
  body <- build_body(
    "systemone", "jev-1.13.0", list(quality = quality),
    text = "Inspect this.", image = img$query, references = references
  )
  expect_in_order(
    body, quality@instructions, b64(img$normal), b64(img$defect),
    b64(img$query), "Inspect this."
  )
})

test_that("SystemOne numbers several references per answer", {
  body <- build_body(
    "systemone", "m", list(quality = quality),
    image = as.raw(10:12), references = several
  )
  expect_equal(
    names(body$assets),
    c("reference_1", "reference_2", "reference_3", "query")
  )
  criteria <- body$questions$quality$criteria
  expect_equal(criteria$normal$examples, list("reference_1", "reference_2"))
  expect_equal(criteria$defective$examples, list("reference_3"))
  expect_equal(body$assets$reference_3$data_base64, b64(as.raw(7:9)))
})

test_that("SystemOne fills a missing description with the answer name", {
  q <- question_choice("Which?", c(yes = NA, "not sure" = "Unclear."))
  body <- build_body("systemone", "m", list(q = q), text = "x")
  expect_equal(
    body$questions$q$criteria,
    list(yes = "yes", "not sure" = "Unclear.")
  )
  s <- question_score("How bad?", c(low = NA, high = "Very bad."))
  body <- build_body("systemone", "m", list(s = s), text = "x")
  expect_equal(body$questions$s$criteria, list("low", "high: Very bad."))
})

test_that("a described noul question gets criteria", {
  q <- question_noul("Is it wet?", true = "Liquid is visible.")
  body <- build_body("systemone", "m", list(wet = q), text = "x")
  expect_equal(
    body$questions$wet$criteria,
    list(true = "Liquid is visible.", false = "false")
  )
})

test_that("a body without a model or an image leaves those fields out", {
  questions <- list(refund = refund)
  body <- build_body("systemone", NULL, questions, text = "x")
  expect_named(body, c("questions", "state"))
  body <- build_body("systemone_images", NULL, questions, text = "x")
  expect_named(body, c("questions", "state"))
})

test_that("base64 data has no line breaks and decodes to the same bytes", {
  bytes <- as.raw(rep(0:255, 4))
  expect_match(jsonlite::base64_enc(bytes), "\n", fixed = TRUE)
  questions <- list(refund = refund)
  body <- build_body("systemone", "m", questions, image = bytes)
  data <- body$assets$query$data_base64
  expect_no_match(data, "\n", fixed = TRUE)
  expect_identical(jsonlite::base64_dec(data), bytes)
  body <- build_body("systemone_images", "m", questions, image = bytes)
  expect_no_match(body$images[[1]], "\n", fixed = TRUE)
})

# build_body(): SystemOne with an image list ------------------------------

test_that("the image list holds data URLs with the inspected image last", {
  body <- build_body(
    "systemone_images", "m", list(quality = quality),
    text = "Line one.", image = as.raw(10:12), references = several
  )
  expect_false("assets" %in% names(body))
  expect_length(body$images, 4)
  expect_match(unlist(body$images), "^data:image/jpeg;base64,")
  expect_equal(
    body$images[[4]],
    paste0("data:image/jpeg;base64,", b64(as.raw(10:12)))
  )
  expect_equal(body$state, paste(
    "Reference images of the answer `normal`: image 1, image 2.",
    "Reference images of the answer `defective`: image 3.",
    "Image 4 is `inspection_image`, the image to inspect.",
    "Line one.",
    sep = "\n"
  ))
  expect_equal(body$questions$quality$criteria, as.list(surface))
})

test_that("the image list puts instructions and references before the input", {
  body <- build_body(
    "systemone_images", "m", list(quality = quality),
    text = "Line one.", image = img$query, references = references
  )
  expect_in_order(
    body, quality@instructions, b64(img$normal), b64(img$defect),
    b64(img$query), "Image 3 is `inspection_image`", "Line one."
  )
})

test_that("the image list names a single image without references", {
  body <- build_body(
    "systemone_images", "m", list(quality = quality), image = as.raw(1:3)
  )
  expect_equal(
    body$state,
    "Image 1 is `inspection_image`, the image to inspect."
  )
  expect_length(body$images, 1)
})

# build_body(): OpenAI ----------------------------------------------------

test_that("OpenAI questions are an array with names and their own types", {
  questions <- list(refund = refund, team = team2, urgency = urgency_openai)
  body <- build_body("openai", "gpt-6-luna", questions, text = "x")
  expect_null(names(body$questions))
  expect_equal(
    purrr::map_chr(body$questions, "name"),
    c("refund", "team", "urgency")
  )
  expect_equal(
    purrr::map_chr(body$questions, "type"),
    c("predicate", "choice", "score")
  )
  expect_equal(
    body$questions[[2]]$choices[[1]],
    list(value = "billing", description = team[["billing"]])
  )
  expect_equal(
    body$questions[[3]]$levels[[3]],
    list(label = "high", description = urgency_openai@answers[["high"]])
  )
})

test_that("OpenAI puts the text and the image in the input", {
  body <- build_body(
    "openai", "m", list(quality = quality),
    text = "A part.", image = as.raw(1:3)
  )
  expect_equal(body$input, list(list(role = "user", content = list(
    list(type = "input_text", text = "A part."),
    list(type = "input_text", text = "Image to inspect:"),
    list(
      type = "input_image",
      image_url = paste0("data:image/jpeg;base64,", b64(as.raw(1:3)))
    )
  ))))
})

test_that("OpenAI adds noul descriptions to the instructions", {
  body <- build_body("openai", "m", list(refund = refund_described), text = "x")
  expect_equal(body$questions[[1]]$instructions, paste(
    refund_described@instructions,
    "true: The message asks for money back.",
    "false: The message does not ask for money back.",
    sep = "\n"
  ))
})

test_that("OpenAI puts references in the instructions, before the input", {
  body <- build_body(
    "openai", "m", list(quality = quality),
    image = img$query, references = references
  )
  expect_in_order(
    body, quality@instructions, b64(img$normal), b64(img$defect),
    "Image to inspect:", b64(img$query)
  )
})

# build_body(): every format ----------------------------------------------

test_that("a long text with quotes, a newline and an accent round-trips", {
  e_acute <- intToUtf8(233)
  long <- paste0("She said \"stop\".\nCaf", e_acute, " ", strrep("x", 5000))
  long <- substr(long, 1, 5000)
  expect_equal(nchar(long), 5000)
  expect_true(grepl(e_acute, long, fixed = TRUE))
  read_text <- list(
    systemone = \(b) b$state$text,
    openrouter = \(b) b$state$text,
    systemone_images = \(b) b$state,
    openai = \(b) b$input
  )
  for (format in names(read_text)) {
    body <- build_body(format, "m", list(refund = refund), text = long)
    sent <- read_text[[format]](round_trip(body))
    expect_identical(sent, long, label = format)
  }
})

test_that("an unknown format or question type errors", {
  questions <- list(refund = refund)
  expect_error(build_body("bogus", "m", questions, text = "x"), "bogus")
  expect_error(parse_answers("bogus", list(), questions), "bogus")
  expect_error(
    build_body("systemone", "m", list(q = "Is it?"), text = "x"),
    "question_noul"
  )
})

# parse_answers(): every saved response -----------------------------------

test_that("every saved response of a successful call parses", {
  saved <- sub("\\.json$", "", list.files(test_path("fixtures"), "\\.json$"))
  saved <- saved[!grepl("-request$|-error$|^laya-(health|batch)$", saved)]
  providers <- paste(names(provider_format), collapse = "|")
  pattern <- paste0("^(", providers, ")-(.+)$")
  for (name in saved) {
    provider <- sub(pattern, "\\1", name)
    questions <- probe_questions(sub(pattern, "\\2", name), provider)
    body <- fixture(name)
    parsed <- parse_answers(provider_format[[provider]], body, questions)
    expect_gt(parsed$input_tokens, 0, label = name)
    cost <- as.numeric(body$usage$cost %||% NA)
    expect_identical(parsed$cost, cost, label = name)
    for (q in names(questions)) {
      answer <- parsed$answers[[q]]
      allowed <- names(questions[[q]]@answers)
      expect_true(answer$answer %in% allowed, label = paste(name, q))
      expect_named(answer$probabilities, allowed)
      if (!S7::S7_inherits(questions[[q]], question_noul)) {
        # Laya rounds each probability to 4 digits (data-raw/formats.md).
        tolerance <- if (provider == "laya") 5e-5 * length(allowed) else 1e-6
        total <- sum(answer$probabilities)
        expect_lt(abs(total - 1), tolerance, label = paste(name, q))
      }
    }
  }
  # The 35 saved responses of successful calls (Task 2): none is skipped.
  expect_length(saved, 35)
})

test_that("each result of the Laya batch parses", {
  for (result in fixture("laya-batch")$results) {
    parsed <- parse_answers("systemone", result, list(team = team3))
    expect_true(parsed$answers$team$answer %in% names(team))
    expect_gt(parsed$input_tokens, 0)
  }
})

# parse_answers(): values -------------------------------------------------

test_that("a noul answer gives the probability of true and false", {
  questions <- list(refund = refund)
  parsed <- parse_answers("systemone", fixture("typesafe-noul"), questions)
  expect_equal(parsed$answers$refund, list(
    answer = "true", probabilities = c(true = 0.99, false = 0.01)
  ))
  expect_equal(parsed$input_tokens, 313)
  expect_identical(parsed$cost, NA_real_)
  parsed <- parse_answers("openai", fixture("openai-noul"), questions)
  expect_equal(parsed$answers$refund$probabilities, c(true = 1, false = 0))
})

test_that("a noul answer is true from a probability of 0.5", {
  answer <- function(p) {
    body <- list(
      answers = list(q = list(type = "noul", noul = p)),
      usage = list(input_tokens = 1)
    )
    parse_answers("systemone", body, list(q = refund))$answers$q$answer
  }
  expect_equal(answer(0.5), "true")
  expect_equal(answer(0.49), "false")
})

test_that("choice probabilities are matched by name, not position", {
  # Microsoft-Decision-1 lists billing, shipping, technical.
  body <- fixture("openrouter-microsoft-choice3")
  parsed <- parse_answers("openrouter", body, list(team = team3))
  p <- body$answers$team$probabilities
  expect_equal(
    parsed$answers$team$probabilities,
    c(billing = p$billing, technical = p$technical, shipping = p$shipping)
  )
  expect_equal(parsed$answers$team$answer, "billing")
  expect_equal(parsed$cost, 0.00000357)
})

test_that("OpenAI probabilities are matched by name, not position", {
  # Both arrays are reversed and lack one answer; the answers are reversed.
  urgency <- list(
    type = "score", name = "urgency", score = 1.4,
    probabilities = list(
      list(value = 2, label = "high", probability = 0.7),
      list(value = 0, label = "low", probability = 0.3)
    )
  )
  team <- list(
    type = "choice", name = "team", choice = "shipping",
    probabilities = list(
      list(value = "shipping", probability = 0.6),
      list(value = "technical", probability = 0.4)
    )
  )
  body <- list(answers = list(urgency, team), usage = list(input_tokens = 10))
  questions <- list(team = team3, urgency = urgency_openai)
  parsed <- parse_answers("openai", body, questions)
  expect_equal(parsed$answers$team, list(
    answer = "shipping",
    probabilities = c(billing = NA, technical = 0.4, shipping = 0.6)
  ))
  expect_equal(parsed$answers$urgency, list(
    answer = "high",
    probabilities = c(low = 0.3, medium = NA, high = 0.7),
    score = 1.4
  ))
})

test_that("the saved OpenAI combined response gives the expected values", {
  questions <- probe_questions("combined", "openai")
  parsed <- parse_answers("openai", fixture("openai-combined"), questions)
  expect_equal(
    parsed$answers$team3$probabilities,
    c(billing = 1, technical = 0, shipping = 0)
  )
  expect_equal(parsed$answers$urgency, list(
    answer = "high",
    probabilities = c(low = 0, medium = 0, high = 1),
    score = 2
  ))
})

test_that("a score answer keeps the reported score", {
  body <- fixture("clef-score3")
  questions <- list(urgency = urgency_systemone)
  urgency <- parse_answers("systemone_images", body, questions)$answers$urgency
  expect_equal(urgency$score, body$answers$urgency$score)
  expect_equal(urgency$answer, "High")
  expect_equal(
    unname(urgency$probabilities),
    unlist(body$answers$urgency$probabilities, use.names = FALSE)
  )
})

test_that("a score answer without a score gets the weighted mean level", {
  answer <- list(
    type = "score", probabilities = list("0" = 0.2, "1" = 0.3, "2" = 0.5)
  )
  body <- list(
    answers = list(urgency = answer), usage = list(input_tokens = 10)
  )
  questions <- list(urgency = urgency_systemone)
  urgency <- parse_answers("systemone", body, questions)$answers$urgency
  expect_equal(urgency$score, 1.3)
  expect_equal(urgency$answer, "High")
})

test_that("a missing probability is NA and an unknown choice passes through", {
  answer <- list(
    type = "choice", choice = "refunds",
    probabilities = list(billing = 0.7, technical = 0.3)
  )
  body <- list(answers = list(team = answer), usage = list(input_tokens = 10))
  parsed <- parse_answers("systemone", body, list(team = team3))
  team_answer <- parsed$answers$team
  expect_equal(team_answer$answer, "refunds")
  expect_equal(
    team_answer$probabilities,
    c(billing = 0.7, technical = 0.3, shipping = NA)
  )
})

test_that("a question without an answer gives NA", {
  body <- list(answers = list(), usage = list(input_tokens = 10))
  questions <- list(refund = refund, team = team2)
  parsed <- parse_answers("systemone", body, questions)
  expect_equal(parsed$answers$refund$answer, NA_character_)
  expect_equal(
    parsed$answers$team$probabilities,
    c(billing = NA_real_, technical = NA_real_)
  )
})
