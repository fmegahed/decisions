# The helpers (key, typesafe, record_requests(), state_text(),
# choice_body(), probe_image(), ...) and the questions (refund, team2,
# quality, urgency) are in helper-requests.R.

# A setup file in an empty temporary folder
local_file <- function(env = parent.frame()) {
  file.path(withr::local_tempdir(.local_envir = env), "setup.json")
}

# A stand-in for prepare_image() that needs no magick: the bytes name the
# image and the channel setting
fake_prepare <- function(image, max_size, upscale, crop, rgb = FALSE) {
  charToRaw(paste(image, rgb))
}

# The text "i" gets the probability i / 26 for billing; the text "13" gets
# HTTP 500
team_answer <- function(req) {
  text <- state_text(req)
  if (text == "13") {
    return(httr2::response(500, body = charToRaw("model overloaded")))
  }
  p <- as.integer(text) / 26
  httr2::response_json(body = choice_body(
    "team", if (p >= 0.5) "billing" else "technical",
    c(billing = p, technical = 1 - p)
  ))
}

# An isotonic calibrator of team2, fitted on synthetic answers of the shape
# of decide(); `levels` sets the order of the levels of the truth
team_calibrator <- function(levels = c("billing", "technical")) {
  p <- seq(0.05, 0.95, length.out = 40)
  answers <- tibble::tibble(
    .pred_class = factor(
      ifelse(p >= 0.5, "billing", "technical"),
      levels = c("billing", "technical")
    ),
    .pred_billing = p,
    .pred_technical = 1 - p,
    truth = factor(
      ifelse(p + rep(c(-0.3, 0.3), 20) > 0.5, "billing", "technical"),
      levels = levels
    )
  )
  probably::cal_estimate_isotonic(answers, truth = truth)
}

ask <- function(setup, text, ...) {
  suppressMessages(decide(setup, text = text, ...))
}

# Setups and files ----------------------------------------------------------

test_that("a setup file gives back the questions, model, settings and references", {
  local_mocked_bindings(prepare_image = fake_prepare)
  clef <- decider_systemone(
    "http://localhost:30000", "Cloudflare/clef-flash", image_format = "images"
  )
  setup <- decision_setup(
    clef, list(quality = quality),
    references = list(normal = c("n1.jpg", "n2.jpg"), defective = "d1.jpg"),
    max_size = 512, upscale = TRUE, crop = c(0, 0, 10, 10)
  )
  # Prepared once, with three channels for the image-list format
  expect_identical(setup@references$normal[[2]], charToRaw("n2.jpg TRUE"))

  back <- read_setup(write_setup(setup, local_file()))
  expect_equal(back@questions, setup@questions)
  expect_identical(back@references, setup@references)
  without_key <- \(decider) S7::props(decider)[c(
    "provider", "format", "base_url", "model", "image_format", "input"
  )]
  expect_identical(without_key(back@decider), without_key(clef))
  expect_null(back@decider@credentials())
  expect_identical(back@max_size, 512)
  expect_true(back@upscale)
  expect_identical(back@crop, c(0, 0, 10, 10))
  expect_null(back@calibrator)
})

test_that("questions keep their type, order, texts and missing descriptions", {
  # A French question with a quote, a newline and an answer without a
  # description
  odd <- question_choice("Caf\u00e9 ou th\u00e9 ?", c(
    `not sure` = "Neither, \"quoted\"\non two lines.", oui = NA
  ))
  setup <- decision_setup(
    typesafe, list(refund = refund, urgency = urgency, odd = odd),
    max_size = NULL, crop = "center"
  )
  back <- read_setup(write_setup(setup, local_file()))
  expect_equal(back@questions, setup@questions)
  expect_named(back@questions, c("refund", "urgency", "odd"))
  expect_s3_class(back@questions$urgency, "decisions::question_score")
  expect_named(back@questions$urgency@answers, c("Low", "Medium", "High"))
  expect_identical(back@questions$refund@answers,
                   c(true = NA_character_, false = NA_character_))
  expect_identical(back@questions$odd@instructions, "Caf\u00e9 ou th\u00e9 ?")
  expect_null(back@max_size)
  expect_identical(back@crop, "center")
  expect_false(back@upscale)
  expect_null(back@references)
})

test_that("a magick reference keeps its exact bytes through the file", {
  skip_if_not_installed("magick")
  setup <- decision_setup(
    typesafe, list(quality = quality),
    references = list(defective = list(probe_image())), max_size = 128
  )
  expect_identical(
    setup@references$defective[[1]],
    prepare_image(probe_image(), max_size = 128)
  )
  back <- read_setup(write_setup(setup, local_file()))
  expect_identical(back@references, setup@references)
})

test_that("a setup file holds no key; read_setup() gives the credentials", {
  path <- local_file()
  setup <- decision_setup(
    decider_typesafe("jev-1.13.0", credentials = \() "not-a-real-key"),
    list(refund = refund)
  )
  expect_identical(write_setup(setup, path), path)
  text <- readChar(path, file.size(path), useBytes = TRUE)
  expect_false(grepl("not-a-real-key", text, fixed = TRUE))
  expect_false(grepl("credentials", text, fixed = TRUE))

  withr::local_envvar(TYPESAFE_API_KEY = "not-a-real-key-from-env")
  expect_identical(read_setup(path)@decider@credentials(),
                   "not-a-real-key-from-env")
  back <- read_setup(path, credentials = \() "not-a-real-key-from-fn")
  expect_identical(back@decider@credentials(), "not-a-real-key-from-fn")
  expect_error(read_setup(path, credentials = "not-a-real-key"), "function")
})

test_that("write_setup() refuses a crop function and names crop", {
  path <- local_file()
  setup <- decision_setup(
    typesafe, list(refund = refund), crop = \(img) c(0, 0, 10, 10)
  )
  expect_error(write_setup(setup, path), "crop")
  expect_false(file.exists(path))
})

test_that("a setup file of another version, or another file, is refused", {
  path <- local_file()
  write_setup(decision_setup(typesafe, list(refund = refund)), path)
  json <- jsonlite::read_json(path)
  json$version <- 2
  jsonlite::write_json(json, path, auto_unbox = TRUE, null = "null")
  expect_error(read_setup(path), "version")

  jsonlite::write_json(
    list(version = 1, hash = "abc", done = setNames(list(), character())),
    path, auto_unbox = TRUE
  )
  expect_error(read_setup(path), "setup")
})

test_that("a setup checks its pieces when it is made", {
  expect_error(decision_setup("typesafe", list(refund = refund)), "decider")
  expect_error(
    decision_setup(typesafe, list(quality = quality, team = team2),
                   references = list(normal = "n.jpg")),
    "one question"
  )
  text_only <- decider_typesafe("jev-1.13.0", credentials = key,
                                input = "text")
  expect_error(
    decision_setup(text_only, list(quality = quality),
                   references = list(normal = "no-such-file.jpg")),
    "image"
  )
  expect_error(
    decision_setup(typesafe, list(quality = quality, team = team2),
                   calibrator = list()),
    "one question"
  )
  expect_error(
    decision_setup(typesafe, list(team = team2), calibrator = "a calibrator"),
    "calibrator"
  )
})

test_that("a setup prints its pieces and no key", {
  local_mocked_bindings(prepare_image = fake_prepare)
  setup <- decision_setup(
    typesafe, list(quality = quality),
    references = list(normal = c("n1.jpg", "n2.jpg"), defective = "d1.jpg")
  )
  expect_snapshot(print(setup))
  expect_snapshot(print(decision_setup(
    typesafe, list(refund = refund, urgency = urgency), max_size = NULL,
    crop = \(img) c(0, 0, 10, 10)
  )))
  text <- paste(utils::capture.output(print(setup)), collapse = "\n")
  expect_false(grepl("not-a-real-key", text, fixed = TRUE))
})

# decide() with a setup -----------------------------------------------------

test_that("decide(setup) sends what decide() sends with the same pieces", {
  skip_if_not_installed("magick")
  log <- record_requests(\(req) fixture_response("typesafe-image"))
  references <- list(defective = list(probe_image()))
  run <- file.path(withr::local_tempdir(), "run.json")
  direct <- suppressMessages(decide(
    typesafe, list(quality = quality), text = "x", image = list(probe_image()),
    references = references, max_size = 128, crop = "center", path = run
  ))
  setup <- decision_setup(typesafe, list(quality = quality),
                          references = references, max_size = 128,
                          crop = "center")
  from_setup <- suppressMessages(
    decide(setup, text = "x", image = list(probe_image()))
  )
  expect_length(log$requests, 2)
  expect_identical(httr2::req_get_body(log$requests[[2]]),
                   httr2::req_get_body(log$requests[[1]]))
  expect_equal(from_setup, direct)

  # The setup from the file has the same run hash and input keys: the path
  # file of the direct call answers it without a request
  back <- read_setup(write_setup(setup, local_file()), credentials = key)
  again <- suppressMessages(
    decide(back, text = "x", image = list(probe_image()), path = run)
  )
  expect_length(log$requests, 2)
  expect_equal(again, direct)
})

test_that("arguments that a setup holds are refused with a setup", {
  setup <- decision_setup(typesafe, list(refund = refund))
  log <- record_requests(\(req) fixture_response("typesafe-noul"))
  expect_error(decide(setup, refund, text = "x"), "questions")
  # A text given by position lands in `questions`
  expect_error(decide(setup, "x"), "by name")
  expect_error(
    decide(setup, text = "x", references = list(true = "a.jpg")),
    "references"
  )
  expect_error(decide(setup, text = "x", max_size = 512), "max_size")
  expect_error(decide(setup, text = "x", upscale = TRUE), "upscale")
  expect_error(decide(setup, text = "x", crop = "center"), "crop")
  expect_length(log$requests, 0)
  out <- suppressMessages(decide(setup, text = "x"))
  expect_length(log$requests, 1)
  expect_named(out, c(".pred_class", ".pred_true", ".pred_false", ".model",
                      ".input_tokens", ".cost", ".seconds", ".error"))
})

# Calibrators ---------------------------------------------------------------

test_that("decide() applies the calibrator of a setup to the answered rows", {
  skip_if_not_installed("probably")
  calibrator <- team_calibrator()
  path <- local_file()
  write_setup(
    decision_setup(typesafe, list(team = team2), calibrator = calibrator),
    path
  )
  setup <- read_setup(path, credentials = key)
  expect_false(is.null(setup@calibrator))
  record_requests(team_answer)
  texts <- as.character(1:25)
  raw <- ask(decision_setup(typesafe, list(team = team2)), texts)
  out <- ask(setup, texts)

  answered <- is.na(raw$.error)
  expect_equal(which(!answered), 13)
  expected <- probably::cal_apply(
    raw[answered, ], calibrator, pred_class = ".pred_class"
  )
  expect_equal(out[answered, ], expected[names(raw)])
  # The calibration changes the probabilities; the failed row stays as is
  expect_false(isTRUE(all.equal(out$.pred_billing, raw$.pred_billing)))
  expect_equal(out[!answered, ], raw[!answered, ])
  expect_named(out, names(raw))
  expect_identical(levels(out$.pred_class), c("billing", "technical"))

  # A truth with the levels in another order: the class keeps the levels of
  # the answers
  reversed <- decision_setup(
    typesafe, list(team = team2),
    calibrator = team_calibrator(c("technical", "billing"))
  )
  expect_identical(levels(ask(reversed, texts)$.pred_class),
                   c("billing", "technical"))
})

test_that("a calibrator must fit the answers of the question", {
  skip_if_not_installed("probably")
  expect_error(
    decision_setup(typesafe, list(quality = quality),
                   calibrator = team_calibrator()),
    ".pred_normal"
  )
})

test_that("the path file keeps the answers before calibration", {
  skip_if_not_installed("probably")
  calibrator <- team_calibrator()
  plain <- decision_setup(typesafe, list(team = team2))
  calibrated <- decision_setup(typesafe, list(team = team2),
                               calibrator = calibrator)
  run <- file.path(withr::local_tempdir(), "run.json")
  log <- record_requests(team_answer)
  texts <- as.character(1:5)
  out <- ask(calibrated, texts, path = run)
  expect_length(log$requests, 5)
  # The same path without the calibrator: no hash error and no request
  raw <- ask(plain, texts, path = run)
  expect_length(log$requests, 5)
  # The file holds the answers of the model, as a call without path gives
  expect_equal(raw, ask(plain, texts))
  expect_equal(
    out, probably::cal_apply(raw, calibrator, pred_class = ".pred_class")[
      names(raw)
    ]
  )
})

test_that("an edited description drops the calibrator with a warning", {
  skip_if_not_installed("probably")
  path <- local_file()
  write_setup(
    decision_setup(typesafe, list(team = team2),
                   calibrator = team_calibrator()),
    path
  )
  expect_no_warning(kept <- read_setup(path))
  expect_false(is.null(kept@calibrator))

  text <- readLines(path, encoding = "UTF-8")
  edited <- sub("Payments, charges and refunds.", "Payments and charges only.",
                text, fixed = TRUE)
  expect_false(identical(edited, text))
  writeLines(edited, path, useBytes = TRUE)
  warning <- expect_warning(back <- read_setup(path), "calibrator")
  expect_match(conditionMessage(warning), "refit", ignore.case = TRUE)
  expect_null(back@calibrator)
  expect_identical(back@questions$team@answers[["billing"]],
                   "Payments and charges only.")
})

# Write a calibrated setup of team2, check that the unchanged file keeps the
# calibrator, then change one line of the file from `from` to `to`
write_and_edit <- function(path, from, to) {
  write_setup(
    decision_setup(typesafe, list(team = team2),
                   calibrator = team_calibrator()),
    path
  )
  expect_no_warning(kept <- read_setup(path))
  expect_false(is.null(kept@calibrator))
  text <- readLines(path, encoding = "UTF-8")
  edited <- sub(from, to, text, fixed = TRUE)
  expect_false(identical(edited, text))
  writeLines(edited, path, useBytes = TRUE)
}

test_that("an edited model drops the calibrator with a warning", {
  skip_if_not_installed("probably")
  path <- local_file()
  write_and_edit(path, '"model": "jev-1.13.0"', '"model": "jev-1.14.0"')
  warning <- expect_warning(back <- read_setup(path), "calibrator")
  expect_match(conditionMessage(warning), "model")
  expect_null(back@calibrator)
  expect_identical(back@decider@model, "jev-1.14.0")
})

test_that("an edited image size drops the calibrator with a warning", {
  skip_if_not_installed("probably")
  path <- local_file()
  write_and_edit(path, '"max_size": 768', '"max_size": 512')
  warning <- expect_warning(back <- read_setup(path), "calibrator")
  expect_match(conditionMessage(warning), "image settings")
  expect_null(back@calibrator)
  expect_identical(back@max_size, 512)
})
