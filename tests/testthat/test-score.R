# The helpers (typesafe, record_requests(), choice_body(), ...) are in
# helper-requests.R.

part <- question_choice("Is the part defective?", c(
  nominal = "A clean part.", defective = "A part with a defect."
))
part_setup <- decision_setup(typesafe, list(part = part))

# The text is the probability of "defective"; the text "bad" gets HTTP 500
part_response <- function(req) {
  text <- state_text(req)
  if (text == "bad") {
    return(httr2::response(500, body = charToRaw("model overloaded")))
  }
  p <- as.numeric(text)
  httr2::response_json(body = choice_body(
    "part", if (p >= 0.5) "defective" else "nominal",
    c(nominal = 1 - p, defective = p)
  ))
}

truth4 <- c("defective", "defective", "nominal", "nominal")
texts4 <- c("0.9", "0.8", "0.3", "0.2")

score4 <- function(texts, truth = truth4, setup = part_setup, ...) {
  suppressMessages(score_setup(setup, text = texts, truth = truth, ...))
}

local_file <- function(name, env = parent.frame()) {
  file.path(withr::local_tempdir(.local_envir = env), name)
}

test_that("the AUC is 1 for a perfect ranking and 0.5 for a mixed one", {
  record_requests(part_response)
  one <- score4(texts4)
  expect_equal(one$metric, "roc_auc")
  expect_equal(one$estimate, 1)
  expect_equal(one$n, 4L)
  expect_equal(one$calls, 4L)
  expect_equal(one$errors, 0L)
  expect_equal(one$input_tokens, 40)
  expect_true(is.na(one$cost))
  expect_equal(nrow(one$answers[[1]]), 4)
  half <- score4(c("0.9", "0.2", "0.8", "0.3"))
  expect_equal(half$estimate, 0.5)
})

test_that("the AUC equals yardstick", {
  skip_if_not_installed("yardstick")
  record_requests(part_response)
  p <- c(0.9, 0.35, 0.35, 0.6, 0.1, 0.35, 0.8, 0.2)
  truth <- c("defective", "defective", "nominal", "nominal", "nominal",
             "defective", "nominal", "defective")
  out <- score4(as.character(p), truth)
  expected <- yardstick::roc_auc_vec(
    factor(truth, levels = c("nominal", "defective")), p,
    event_level = "second"
  )
  expect_equal(out$estimate, expected)
})

test_that("tied probabilities count half", {
  record_requests(part_response)
  expect_equal(score4(rep("0.5", 4))$estimate, 0.5)
})

test_that("event defaults to true for a noul question", {
  setup <- decision_setup(typesafe, list(refund = refund))
  record_requests(function(req) {
    httr2::response_json(body = list(
      model = "jev-1.13.0",
      answers = list(refund = list(
        type = "noul", noul = as.numeric(state_text(req))
      )),
      usage = list(input_tokens = 10)
    ))
  })
  truth <- c("true", "true", "false", "false")
  expect_equal(score4(texts4, truth, setup = setup)$estimate, 1)
  other <- score4(texts4, truth, setup = setup, event = "false")
  expect_equal(other$estimate, 1)
  flipped <- score4(texts4, rev(truth), setup = setup)
  expect_equal(flipped$estimate, 0)
})

test_that("event and truth are checked before any request", {
  log <- record_requests(part_response)
  expect_error(score4(texts4, event = "other"), "event")
  expect_error(score4(texts4, truth = c("defective", "x", "y", "nominal")),
               "\"x\".*\"y\"")
  expect_error(score4(texts4, truth = truth4[1:3]), "length")
  expect_error(score4(texts4, metric = "accuracy"), "roc_auc")
  three <- decision_setup(typesafe, list(team = question_choice("Team?", c(
    a = "A.", b = "B.", c = "C."
  ))))
  expect_error(score4(texts4, c("a", "b", "c", "a"), setup = three), "event")
  two <- decision_setup(typesafe, list(a = refund, b = team2))
  expect_error(score4(texts4, truth4, setup = two), "one question")
  expect_length(log$requests, 0)
})

test_that("rows with an error are left out and counted", {
  record_requests(part_response)
  out <- score4(c("0.9", "0.8", "bad", "0.2"))
  expect_equal(out$errors, 1L)
  expect_equal(out$n, 3L)
  expect_equal(out$calls, 4L)
  expect_equal(out$estimate, 1)
})

test_that("fewer than one row of each class gives NA and a warning", {
  record_requests(part_response)
  expect_warning(
    out <- score4(c("bad", "0.3", "0.2", "0.1"), truth4[c(1, 3, 3, 3)]),
    "each class"
  )
  expect_true(is.na(out$estimate))
  expect_warning(score4(texts4, rep("nominal", 4)), "each class")
})

test_that("calls counts the requests that went out", {
  log <- record_requests(part_response)
  path <- local_file("run.json")
  first <- score4(texts4, path = path)
  expect_equal(first$calls, 4L)
  second <- score4(texts4, path = path)
  expect_equal(second$calls, 0L)
  expect_equal(second$estimate, 1)
  expect_length(log$requests, 4)
})

test_that("role refuses test rows before any request", {
  log <- record_requests(part_response)
  expect_error(
    score4(texts4, role = c("learning", "test", "learning", "calibration")),
    "evaluate_once"
  )
  expect_error(score4(texts4, role = c("learning", "x", "x", "x")), "role")
  expect_error(score4(texts4, role = "learning"), "role")
  expect_length(log$requests, 0)
  ok <- score4(
    texts4, role = c("learning", "learning", "calibration", "learning")
  )
  expect_equal(ok$estimate, 1)
})

test_that("a calibrated setup is scored on the calibrated probabilities", {
  skip_if_not_installed("probably")
  skip_if_not_installed("mgcv")
  p <- seq(0.05, 0.95, length.out = 40)
  fit <- tibble::tibble(
    .pred_class = factor(
      ifelse(p >= 0.5, "defective", "nominal"),
      levels = c("nominal", "defective")
    ),
    .pred_nominal = 1 - p, .pred_defective = p,
    truth = factor(
      ifelse(p + rep(c(-0.3, 0.3), 20) > 0.5, "defective", "nominal"),
      levels = c("nominal", "defective")
    )
  )
  setup <- decision_setup(
    typesafe, list(part = part),
    calibrator = probably::cal_estimate_isotonic(fit, truth = truth)
  )
  record_requests(part_response)
  out <- score4(texts4, setup = setup)
  direct <- suppressMessages(decide(setup, text = texts4))
  expect_equal(out$answers[[1]]$.pred_defective, direct$.pred_defective)
})

test_that("evaluate_once scores once and refuses a second run", {
  log <- record_requests(part_response)
  path <- local_file("test.rds")
  run <- \() suppressMessages(
    evaluate_once(part_setup, text = texts4, truth = truth4, path = path)
  )
  first <- run()
  expect_equal(first$estimate, 1)
  expect_true(file.exists(path))
  expect_equal(readRDS(path)$estimate, 1)
  expect_length(log$requests, 4)
  expect_error(run(), "test.rds.*already")
  expect_length(log$requests, 4)
})

test_that("evaluate_once keeps a stopped run and sends only the failed row", {
  texts <- c("0.9", "bad", "0.3", "0.2")
  log <- record_requests(part_response)
  path <- local_file("test.rds")
  run <- \() suppressMessages(
    evaluate_once(part_setup, text = texts, truth = truth4, path = path)
  )
  expect_warning(first <- run(), "again")
  expect_equal(first$errors, 1L)
  expect_false(file.exists(path))
  expect_true(file.exists(paste0(path, ".state.json")))
  expect_length(log$requests, 4)
  log$requests <- list()
  texts[2] <- "0.8"
  second <- run()
  expect_length(log$requests, 1)
  expect_equal(second$calls, 1L)
  expect_equal(second$errors, 0L)
  expect_equal(second$estimate, 1)
  expect_true(file.exists(path))
})

test_that("an answered row with a missing event probability is left out", {
  record_requests(function(req) {
    if (state_text(req) != "na") return(part_response(req))
    httr2::response_json(body = choice_body(
      "part", "nominal", c(nominal = 0.9)
    ))
  })
  out <- score4(c("0.9", "0.8", "na", "0.2"))
  expect_equal(out$estimate, 1)
  expect_equal(out$n, 3L)
  expect_equal(out$errors, 1L)
})

test_that("calls counts the second tries after HTTP 429", {
  seen <- new.env()
  seen$first <- TRUE
  log <- record_requests(function(req) {
    if (state_text(req) == "0.9" && seen$first) {
      seen$first <- FALSE
      return(httr2::response(429, headers = list(`Retry-After` = "0")))
    }
    part_response(req)
  })
  expect_equal(score4(texts4)$calls, 5L)
  expect_length(log$requests, 5)
  seen$first <- TRUE
  path <- local_file("run.json")
  expect_equal(score4(texts4, path = path)$calls, 5L)
})

test_that("cost sums every reported cost, error rows included", {
  record_requests(function(req) {
    resp <- part_response(req)
    if (httr2::resp_status(resp) != 200) {
      body <- choice_body("part", "maybe", c(nominal = 0.5, defective = 0.5))
    } else {
      body <- httr2::resp_body_json(resp)
    }
    body$usage$cost <- 0.01
    httr2::response_json(body = body)
  })
  out <- score4(c("0.9", "0.8", "bad", "0.2"))
  expect_equal(out$errors, 1L)
  expect_equal(out$cost, 0.04)
})

test_that("cost is NA when a row used tokens and has no cost", {
  record_requests(part_response)
  expect_true(is.na(score4(texts4)$cost))
  record_requests(function(req) httr2::response(500, body = charToRaw("x")))
  expect_equal(suppressWarnings(score4(texts4))$cost, 0)
})

test_that("evaluate_once takes event", {
  three <- decision_setup(typesafe, list(team = question_choice("Team?", c(
    a = "A.", b = "B.", c = "C."
  ))))
  record_requests(function(req) {
    p <- as.numeric(state_text(req))
    httr2::response_json(body = choice_body(
      "team", "a", c(a = p, b = (1 - p) / 2, c = (1 - p) / 2)
    ))
  })
  path <- local_file("test.rds")
  args <- list(three, text = c("0.9", "0.2"), truth = c("a", "b"), path = path)
  expect_error(do.call(evaluate_once, args), "event")
  out <- suppressMessages(do.call(evaluate_once, c(args, event = "a")))
  expect_equal(out$estimate, 1)
})

test_that("evaluate_once gives no estimate while a row fails", {
  texts <- c("0.9", "bad", "0.3", "0.2")
  record_requests(part_response)
  path <- local_file("test.rds")
  run <- \() suppressMessages(
    evaluate_once(part_setup, text = texts, truth = truth4, path = path)
  )
  expect_warning(first <- run(), "again")
  expect_true(is.na(first$estimate))
  expect_equal(first$errors, 1L)
  expect_false(file.exists(path))
  texts[2] <- "0.8"
  second <- run()
  expect_equal(second$estimate, 1)
  expect_true(file.exists(path))
})
