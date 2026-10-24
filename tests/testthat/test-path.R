# The helpers (typesafe, record_requests(), state_text(), choice_body(), ...)
# and the questions (refund, team2, quality, urgency) are in
# helper-requests.R.

# The text "i" gets the probability i / 26 for billing, so that each input
# has its own answer
team_response <- function(req) {
  p <- as.integer(state_text(req)) / 26
  httr2::response_json(body = choice_body(
    "team", if (p >= 0.5) "billing" else "technical",
    c(billing = p, technical = 1 - p)
  ))
}

# The same answers, but the text "12" gets HTTP 500
fail_12 <- function(req) {
  if (state_text(req) == "12") {
    return(httr2::response(500, body = charToRaw("model overloaded")))
  }
  team_response(req)
}

# A path file in an empty temporary folder
local_path <- function(env = parent.frame()) {
  file.path(withr::local_tempdir(.local_envir = env), "run.json")
}

ask_team <- function(text, ...) {
  suppressMessages(decide(typesafe, list(team = team2), text = text, ...))
}

test_that("a new run with the same path sends only the failed input", {
  path <- local_path()
  texts <- as.character(1:25)
  write <- write_path
  written <- integer()
  local_mocked_bindings(write_path = function(path, hash, done) {
    written <<- c(written, length(done))
    write(path, hash, done)
  })
  log <- record_requests(fail_12)
  first <- ask_team(texts, max_active = 5, path = path)
  expect_length(log$requests, 25)
  expect_equal(which(!is.na(first$.error)), 12)
  # Chunks of 4 * max_active = 20 inputs; the file is written after each
  expect_equal(written, c(19, 24))
  expect_length(jsonlite::read_json(path)$done, 24)
  # The file was renamed into place: no temporary file is left
  expect_equal(list.files(dirname(path), all.files = TRUE, no.. = TRUE),
               "run.json")

  log <- record_requests(team_response)
  second <- ask_team(texts, max_active = 5, path = path)
  expect_length(log$requests, 1)
  expect_equal(state_text(log$requests[[1]]), "12")
  expect_length(jsonlite::read_json(path)$done, 25)
  expect_equal(second, ask_team(texts), ignore_attr = "requests")
})

test_that("a changed description stops the run; ignore_hash keeps the file", {
  path <- local_path()
  texts <- as.character(1:3)
  record_requests(\(req) {
    if (state_text(req) == "2") return(httr2::response(500))
    team_response(req)
  })
  ask_team(texts, path = path)

  changed <- question_choice(team2@instructions, c(
    billing = "Payments and charges only.",
    technical = "Bugs and problems using the product."
  ))
  ask_changed <- \(...) suppressMessages(
    decide(typesafe, list(team = changed), text = texts, path = path, ...)
  )
  log <- record_requests(team_response)
  error <- expect_error(ask_changed())
  expect_match(conditionMessage(error), "hash", fixed = TRUE)
  expect_match(conditionMessage(error), "ignore_hash = TRUE", fixed = TRUE)
  expect_length(log$requests, 0)

  expect_warning(out <- ask_changed(ignore_hash = TRUE), "hash")
  expect_length(log$requests, 1)
  expect_equal(state_text(log$requests[[1]]), "2")
  expect_true(all(is.na(out$.error)))
  # The file now carries the hash of the new run, as in ellmer::batch_chat()
  expect_no_warning(ask_changed())
  expect_length(log$requests, 1)
})

test_that("images, references and image settings enter the hashes", {
  local_mocked_bindings(prepare_image = function(image, max_size, upscale,
                                                 crop, rgb = FALSE) {
    charToRaw(image)
  })
  path <- local_path()
  log <- record_requests(\(req) fixture_response("typesafe-image"))
  ask <- \(image, references = list(normal = "n.jpg"),
           crop = \(img) c(0, 0, 10, 10), ...) suppressMessages(
    decide(typesafe, list(quality = quality), image = image,
           references = references, crop = crop, path = path, ...)
  )
  ask(c("a.jpg", "b.jpg"))
  # A crop function with the same body gives the same hash
  ask(c("a.jpg", "b.jpg", "c.jpg"), crop = function(img) c(0, 0, 10, 10))
  expect_length(log$requests, 3)
  expect_equal(
    rawToChar(jsonlite::base64_dec(
      httr2::req_get_body(log$requests[[3]])$assets$query$data_base64
    )),
    "c.jpg"
  )
  expect_error(ask("a.jpg", references = list(normal = "m.jpg")),
               "ignore_hash")
  expect_error(ask("a.jpg", max_size = 512), "ignore_hash")
  expect_error(ask("a.jpg", crop = \(img) c(0, 0, 20, 20)), "ignore_hash")
  expect_length(log$requests, 3)
})

test_that("the path file holds no key", {
  path <- local_path()
  record_requests(team_response)
  ask_team(c("1", "2"), path = path)
  text <- readChar(path, file.size(path), useBytes = TRUE)
  expect_false(grepl("not-a-real-key", text, fixed = TRUE))
  state <- jsonlite::read_json(path)
  expect_named(state, c("version", "hash", "done"))
  expect_equal(state$version, 1)
  expect_named(state$done[[1]],
               c("answers", "model", "input_tokens", "cost", "seconds"))
})

test_that("without path, decide() writes no file", {
  folder <- withr::local_tempdir()
  withr::local_dir(folder)
  record_requests(team_response)
  ask_team(c("1", "2"))
  expect_length(list.files(folder, all.files = TRUE, no.. = TRUE), 0)
})

test_that("a hard stop after the first chunk leaves a valid file", {
  path <- local_path()
  texts <- as.character(1:25)
  perform <- perform_requests
  calls <- 0
  local_mocked_bindings(perform_requests = function(requests, max_active) {
    calls <<- calls + 1
    if (calls == 2) stop("The power went out.")
    perform(requests, max_active)
  })
  log <- record_requests(team_response)
  expect_error(ask_team(texts, max_active = 5, path = path), "power")
  expect_length(log$requests, 20)
  expect_equal(list.files(dirname(path), all.files = TRUE, no.. = TRUE),
               "run.json")
  expect_length(jsonlite::read_json(path)$done, 20)

  out <- ask_team(texts, max_active = 5, path = path)
  expect_length(log$requests, 25)
  expect_equal(purrr::map_chr(log$requests[21:25], state_text),
               as.character(21:25))
  expect_true(all(is.na(out$.error)))
})

test_that("after an interrupt, decide() sends no further chunk", {
  # After Esc, req_perform_parallel() returns NULL for each request that did
  # not finish (here the last request of the first chunk)
  passes <- 0
  local_mocked_bindings(
    req_perform_parallel = function(reqs, ...) {
      passes <<- passes + 1
      c(purrr::map(reqs[-length(reqs)], team_response), list(NULL))
    },
    .package = "httr2"
  )
  path <- local_path()
  out <- ask_team(as.character(1:25), max_active = 5, path = path)
  expect_equal(passes, 1)
  expect_equal(nrow(out), 25)
  expect_true(all(is.na(out$.error[1:19])))
  expect_match(out$.error[20:25], "did not finish", fixed = TRUE)
  expect_length(jsonlite::read_json(path)$done, 19)
})

test_that("identical inputs share one request and one entry", {
  path <- local_path()
  log <- record_requests(team_response)
  out <- ask_team(c("3", "5", "3"), path = path)
  expect_length(log$requests, 2)
  expect_equal(out[3, ], out[1, ])
  expect_length(jsonlite::read_json(path)$done, 2)
})

test_that("rows of the file and new rows keep the input order", {
  path <- local_path()
  texts <- as.character(1:5)
  record_requests(team_response)
  expected <- ask_team(texts)
  ask_team(c("4", "2"), path = path)

  log <- record_requests(team_response)
  out <- ask_team(texts, path = path)
  expect_equal(purrr::map_chr(log$requests, state_text), c("1", "3", "5"))
  expect_equal(out, expected, ignore_attr = "requests")

  # All rows from the file: no request, and still one cost message
  messages <- capture_messages(
    decide(typesafe, list(team = team2), text = texts, path = path)
  )
  expect_length(log$requests, 3)
  expect_equal(sum(grepl("does not report a cost", messages, fixed = TRUE)), 1)
})

test_that("the file keeps probabilities, scores, tokens, cost and time exactly", {
  # Numbers with 17 significant digits; the noul probability of false and
  # the score are computed in R
  respond <- function(req) {
    i <- as.integer(state_text(req))
    p <- i / 7
    body <- list(
      model = "jev-1.13.0",
      answers = list(
        refund = list(type = "noul", noul = p),
        team = list(type = "choice", choice = "billing",
                    probabilities = list(billing = p, technical = 1 - p)),
        urgency = list(type = "score", probabilities = list(
          `0` = p / 3, `1` = 1 / 3, `2` = 1 - p / 3 - 1 / 3
        ))
      ),
      usage = list(input_tokens = 100 + i, cost = i / 3e5)
    )
    json <- jsonlite::toJSON(body, auto_unbox = TRUE, digits = I(17))
    httr2::response(
      200, headers = list(`Content-Type` = "application/json"),
      body = charToRaw(json), timing = c(total = i / 9)
    )
  }
  questions <- list(refund = refund, team = team2, urgency = urgency)
  texts <- as.character(1:6)
  path <- local_path()
  record_requests(respond)
  expected <- decide(typesafe, questions, text = texts)
  decide(typesafe, questions, text = texts, path = path)

  log <- record_requests(respond)
  out <- decide(typesafe, questions, text = texts, path = path)
  expect_length(log$requests, 0)
  expect_identical(out, expected, ignore_attr = "requests")
})

test_that("non-ASCII question and answer names come back from the file", {
  # The Cyrillic words for "yes" and "no", and an accented "ready"
  da_net <- c("\u0434\u0430", "\u043d\u0435\u0442")
  ready <- question_choice(
    "Is the part ready?", rlang::set_names(c("Yes.", "No."), da_net)
  )
  questions <- rlang::set_names(list(ready), "r\u00e9ady")
  respond <- \(req) httr2::response_json(body = list(
    model = "jev-1.13.0",
    answers = rlang::set_names(list(list(
      type = "choice", choice = da_net[2],
      probabilities = rlang::set_names(list(0.25, 0.75), da_net)
    )), names(questions)),
    usage = list(input_tokens = 7)
  ))
  texts <- c("caf\u00e9", "plain")
  path <- local_path()
  record_requests(respond)
  expected <- suppressMessages(decide(typesafe, questions, text = texts))
  suppressMessages(decide(typesafe, questions, text = texts, path = path))
  log <- record_requests(respond)
  out <- suppressMessages(decide(typesafe, questions, text = texts, path = path))
  expect_length(log$requests, 0)
  expect_identical(out, expected, ignore_attr = "requests")
})

test_that("the encoding mark and the class of a text do not change its key", {
  cafe <- "caf\u00e9"
  latin1 <- iconv(cafe, "UTF-8", "latin1")
  expect_equal(Encoding(latin1), "latin1")
  same <- \(req) httr2::response_json(body = choice_body(
    "team", "billing", c(billing = 0.9, technical = 0.1)
  ))
  path <- local_path()
  record_requests(same)
  ask_team(latin1, path = path)
  log <- record_requests(same)
  ask_team(cafe, path = path)
  ask_team(structure(cafe, class = c("glue", "character")), path = path)
  if (l10n_info()$`UTF-8`) {
    unknown <- cafe
    Encoding(unknown) <- "unknown"
    ask_team(unknown, path = path)
  }
  expect_length(log$requests, 0)
})

test_that("the encoding mark of question texts does not change the hash", {
  # "Is it ready?" in Spanish, with the answers "yes" and "no"
  listo <- function(encoding) {
    to <- \(x) iconv(x, "UTF-8", encoding)
    question_choice(
      to("\u00bfEst\u00e1 listo?"),
      rlang::set_names(
        to(c("S\u00ed, est\u00e1 listo.", "No.")), to(c("s\u00ed", "no")))
    )
  }
  expect_equal(Encoding(listo("latin1")@instructions), "latin1")
  respond <- \(req) httr2::response_json(body = choice_body(
    "ready", "s\u00ed", rlang::set_names(c(0.8, 0.2), c("s\u00ed", "no"))
  ))
  ask <- \(question) suppressMessages(
    decide(typesafe, list(ready = question), text = "x", path = path)
  )
  path <- local_path()
  record_requests(respond)
  first <- ask(listo("latin1"))
  expect_true(is.na(first$.error))
  log <- record_requests(respond)
  out <- ask(listo("UTF-8"))
  expect_length(log$requests, 0)
  expect_equal(out$.pred_si, first$.pred_si)
})

test_that("a locked path file is renamed again, up to three tries", {
  path <- local_path()
  tries <- 0
  from <- character()
  locked_twice <- function(temporary, to) {
    tries <<- tries + 1
    from <<- c(from, temporary)
    tries > 2 && file.rename(temporary, to)
  }
  expect_true(write_path(path, "first", list(), rename = locked_twice))
  expect_equal(tries, 3)
  expect_equal(jsonlite::read_json(path)$hash, "first")
  # A stray temporary file shows the name of its path file
  expect_match(basename(from), "^run[.]json-")
  # Three failures: the previous file stays whole, the temporary file goes
  expect_false(write_path(path, "second", list(), rename = \(...) FALSE))
  expect_equal(jsonlite::read_json(path)$hash, "first")
  expect_equal(list.files(dirname(path), all.files = TRUE, no.. = TRUE),
               "run.json")
})

test_that("answers that cannot be saved give one warning with their count", {
  path <- local_path()
  write <- write_path
  writes <- 0
  # The first write works; the file is locked during the second
  local_mocked_bindings(write_path = function(path, hash, done) {
    writes <<- writes + 1
    locked <- if (writes > 1) \(...) FALSE else file.rename
    write(path, hash, done, rename = locked)
  })
  record_requests(team_response)
  expect_warning(
    out <- ask_team(as.character(1:6), max_active = 1, path = path),
    "2 finished answers could not be saved"
  )
  expect_true(all(is.na(out$.error)))
  expect_length(jsonlite::read_json(path)$done, 4)
})

test_that("a file that is not a path file stops decide() and stays unchanged", {
  folder <- withr::local_tempdir()
  setup_file <- file.path(folder, "setup.json")
  write_setup(decision_setup(typesafe, list(team = team2)), setup_file)
  before <- tools::md5sum(setup_file)
  log <- record_requests(team_response)
  # ignore_hash = TRUE does not let decide() replace the file
  purrr::walk(c(FALSE, TRUE), \(ignore) {
    expect_error(
      ask_team("1", path = setup_file, ignore_hash = ignore),
      "is not a path file"
    )
  })
  expect_equal(tools::md5sum(setup_file), before)
  expect_no_warning(read_setup(setup_file))
  # A file that is not JSON, and a path file of another version
  notes <- file.path(folder, "notes.json")
  writeLines("not JSON", notes)
  expect_error(ask_team("1", path = notes), "is not a path file")
  other <- file.path(folder, "run.json")
  jsonlite::write_json(
    list(version = 2, hash = "abc", done = setNames(list(), character())),
    other, auto_unbox = TRUE
  )
  expect_error(
    ask_team("1", path = other, ignore_hash = TRUE), "is not a path file"
  )
  expect_length(log$requests, 0)
  expect_equal(sort(list.files(folder)), c("notes.json", "run.json", "setup.json"))
})

test_that("path must be one file in a folder that exists", {
  folder <- withr::local_tempdir()
  log <- record_requests(team_response)
  expect_error(
    ask_team("1", path = file.path(folder, "no-such-folder", "run.json")),
    "folder"
  )
  expect_error(ask_team("1", path = c("a.json", "b.json")), "path")
  expect_error(
    ask_team("1", path = file.path(folder, "run.json"), ignore_hash = NA),
    "ignore_hash"
  )
  expect_length(log$requests, 0)
})
