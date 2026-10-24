#' Ask a decision model typed questions
#'
#' Sends each input (a text, an image or both) with the questions to one
#' model and returns, for each input, the answer and a probability for each
#' allowed answer.
#'
#' @param decider A decider from `decider_typesafe()`, `decider_openai()`,
#'   `decider_foundry()`, `decider_openrouter()` or `decider_systemone()`;
#'   or a setup from `decision_setup()` or `read_setup()`. A setup gives the
#'   decider, the questions, the prepared references, the image settings and
#'   a calibrator. With a setup, give the inputs by name (`text = `,
#'   `image = `), and leave out `questions`, `references`, `max_size`,
#'   `upscale` and `crop`: they stop `decide()` with an error.
#' @param questions One question from `question_noul()`, `question_choice()`
#'   or `question_score()`, or a named list of questions. The names are the
#'   question names of the request, kept exactly. With two or more questions,
#'   the names, cleaned as the answer names are, are the prefixes of the
#'   output columns; two names that give the same prefix are refused. One
#'   question without a name is sent as `question`.
#' @param text A character vector with one text per input, or `NULL`.
#' @param image A character vector of file paths or URLs, a list of magick
#'   images, or a magick vector of several images (for example
#'   `magick::image_read(paths)`), with one image per input; or `NULL`. A
#'   file with several frames (GIF, TIFF, PDF) gives its first frame. With
#'   `text`, element i of `text` and element i of `image` make input i.
#' @param references Reference images for the answers, or `NULL`: a named
#'   list in which each name is an allowed answer of the question and each
#'   element holds the images of that answer (paths, URLs or magick images).
#'   This release takes references with one question only.
#' @param max_size The longest side of each image in pixels after the
#'   resize (one number of 1 or more), or `NULL` to keep the size. The
#'   default is `768`.
#' @param upscale `TRUE` enlarges an image that is smaller than `max_size`.
#'   `FALSE` (the default) never enlarges.
#' @param crop `"none"` (the default), `"center"`, a box
#'   `c(x, y, width, height)` in pixels, or a function that takes a magick
#'   image and returns a box. `max_size`, `upscale` and `crop` apply to the
#'   inputs and to the references.
#' @param max_active The largest number of requests in progress at the same
#'   time. The default is `10`.
#' @param rpm The largest number of requests per minute, or `NULL` (the
#'   default) for no limit. The requests then go out evenly, one each
#'   `60 / rpm` seconds.
#' @param path `NULL` (the default), or the path of a JSON file that keeps
#'   the finished answers, so that a long run that stops can continue
#'   without paying twice for an input (as `ellmer::batch_chat()` does). The
#'   folder must exist. The inputs that are not in the file go out in chunks
#'   of `4 * max_active`, and `decide()` adds the answers of each chunk to
#'   the file. A new call with the same `path` sends only the inputs that
#'   are not in the file and returns all rows, in the order of the inputs.
#'   Rows with an `.error` are not written, so a new call sends them again.
#'   With `path`, identical inputs are sent once.
#'
#'   The file holds a hash of the run and, for each finished input (keyed
#'   by a hash of the prepared text and image), its answers with their
#'   probabilities, `.model`, `.input_tokens`, `.cost` and `.seconds`. It
#'   holds no key and no input. The hash covers the provider, the server
#'   URL, the model, the request format, the image format, the questions
#'   (instructions, answers and descriptions), the prepared reference
#'   images and the image settings; a crop function enters through its
#'   body.
#'
#'   The keys and the hash of the run come from `rlang::hash()`, and both
#'   cover prepared JPEG bytes (of the inputs, and of the references).
#'   Another version of ImageMagick (the library under magick) can give
#'   other JPEG bytes for the same image, and another version of rlang can
#'   give other hashes. So a path file continues a run on the computer that
#'   wrote it, with the same versions of ImageMagick and rlang. Elsewhere,
#'   the hash of the run can differ, or the inputs are sent again.
#'
#'   With a setup that holds a calibrator, the file keeps the answers before
#'   calibration, and the hash does not cover the calibrator: `decide()`
#'   applies the calibrator after it reads the file. So a new call with a
#'   refitted calibrator, or with none, reuses the answers of the file.
#'
#'   A file that is not a path file of `decide()` (for example a setup file
#'   of `write_setup()`) stops the call before any request, also with
#'   `ignore_hash = TRUE`, so `decide()` never replaces it.
#' @param ignore_hash `FALSE` (the default) stops before any request when
#'   the hash in the `path` file differs from the hash of the run, that is,
#'   when the model, the questions, the references or the image settings
#'   changed. `TRUE` keeps the answers of the file with a warning and sends
#'   only the other inputs. The file gets the new hash when `decide()` adds
#'   answers to it; when the file holds every input, it does not change.
#'   Use `TRUE` only when you know that the change does not change the
#'   answers, for example the same model on a new server URL.
#' @return A tibble with one row per input, in the order of the inputs:
#'   * For one question: `.pred_class`, a factor whose levels are the
#'     allowed answers, kept exactly (for example `"not sure"`);
#'     `.pred_<answer>`, the probability of each allowed answer; and
#'     `.score` for a score question. The probability columns have
#'     syntactic names: the answer cleaned as
#'     `janitor::make_clean_names(case = "none")` cleans it (ASCII letters,
#'     digits and `_`; `X` before a leading digit). For example,
#'     `"not sure"` gives `.pred_not_sure`, `"late / lost"` gives
#'     `.pred_late_lost` and `"50%"` gives `.pred_X50_percent`. probably and
#'     yardstick read these columns.
#'   * For two or more questions: the same columns with the cleaned
#'     question name and `_` as a prefix, for example
#'     `quality_.pred_class`.
#'   * `.model`: the model that the provider reports, or the model of the
#'     decider when the response has none.
#'   * `.input_tokens`: the input tokens that the provider reports.
#'   * `.cost`: the cost that the provider reports, or `NA`.
#'   * `.seconds`: the time of the response.
#'   * `.error`: `NA`, or the reason why the answers of the row are `NA`.
#'
#'   The attribute `requests` of the tibble is the number of requests that
#'   this call sent (0 when a `path` file holds all the answers). A second
#'   try after HTTP 429 or 503 counts as a request.
#'
#'   With a setup that holds a calibrator, the calibrated probabilities of
#'   `probably::cal_apply()` replace the `.pred_<answer>` columns, and
#'   `.pred_class` is the answer with the highest calibrated probability
#'   (its levels stay the allowed answers). `.score` stays as the model gave
#'   it. The rows with an `.error` stay `NA`.
#' @details One request goes out per input, in parallel
#'   (`httr2::req_perform_parallel()`), with at most `max_active` requests
#'   at a time and at most `rpm` requests per minute. Set `rpm` to the rate
#'   limit of your account: with no `rpm`, the first requests go out at
#'   full speed, and a provider with a rate limit then refuses some of them
#'   with HTTP 429.
#'
#'   Each request waits at most 300 seconds (5 minutes) for its response
#'   (`httr2::req_timeout()`). A request that takes longer gets a row error,
#'   so a server that stops responding does not hold the call. With `path`,
#'   a new call sends that input again.
#'
#'   A request that gets HTTP 429 or 503 is sent one more time, as the
#'   default retry policy of httr2 does (two tries). `decide()` sends
#'   all such requests again together, after the longest wait that their
#'   `Retry-After` headers ask for (1 second without the header, at most 60
#'   seconds). A second failure stays as a row error. So a call never waits
#'   long for a server that keeps refusing.
#'
#'   An interrupt (Esc) keeps the rows that are done. After an interrupt
#'   while the requests are out, nothing is sent again, and each request
#'   that did not finish gets a row error. An interrupt during the wait
#'   before the second tries skips them; their rows get the error
#'   "Interrupted before a retry." With `path`, an interrupt also stops the
#'   chunks: the file keeps every finished answer, the inputs that were not
#'   sent get the row error of a request that did not finish, and a new
#'   call sends only the rest. Each write goes to a temporary file in the
#'   same folder first, which then replaces the file, so a crash during a
#'   write leaves the previous file whole. When the file cannot be replaced
#'   (for example, while a sync program holds it), `decide()` tries again
#'   twice, and warns at the end with the number of finished answers that
#'   the file does not hold.
#'
#'   No row is lost. A row has `NA` answers and a message in `.error` when
#'   the call fails (the message holds the error text of the provider word
#'   for word, the model name and the size of the request in bytes), when
#'   the response cannot be read, when an answer is not an allowed answer or
#'   is missing, when the probability of an allowed answer is missing, or
#'   when the score of a score question is not one number or its
#'   probabilities are all zero. With `path`, a new call sends such a row
#'   again. A row with an answered call keeps its `.input_tokens` and
#'   `.cost`. A `model`, `input_tokens` or `cost` field that is not one
#'   value gives the model of the decider or `NA`.
#'
#'   Because `.error` keeps the text of the provider word for word, it can
#'   hold a part of the key: OpenAI answers a wrong key with HTTP 401 and a
#'   text that shows the last four characters of the key. Do not share the
#'   `.error` texts of a call with a wrong key.
#'
#'   `decide()` reads the key and checks the input type of the model before
#'   any request. For a provider with a key (all deciders except
#'   `decider_systemone()`), it stops unless the key is one non-empty
#'   string; the message does not show the key. For a setup with a
#'   calibrator, it also checks before any request that probably and the
#'   packages of the calibrator (for example mgcv) are installed. It
#'   prepares each reference image once per call (a setup holds its
#'   references prepared) and each input image once. With
#'   `decider_systemone(image_format = "images")`, it writes the images with
#'   three color channels.
#'
#'   Each image goes out as a JPEG, which has no transparency. So each pixel
#'   keeps its color and loses its transparency, and transparent areas often
#'   become black (a transparent pixel usually holds black, as `"transparent"`
#'   does in magick).
#'
#'   SystemOne links reference images to the answers of choice and noul
#'   questions. A SystemOne score question has no place for them: they are
#'   sent, but not linked to a level. OpenAI puts them in the instructions
#'   of the question, and the image-list format names them in the state
#'   text.
#'
#'   `.cost` holds only a cost that the provider reports (OpenRouter does).
#'   When no row has a cost, `decide()` prints one message that says so.
#'
#'   `.seconds` is the total time of the response as
#'   `httr2::resp_timing()` gives it; for a request that was sent again, it
#'   is the time of the second try. It is `NA` when no response arrived.
#' @examples
#' \dontrun{
#' # These examples need an API key and make paid calls, so they are not run on CRAN.
#' refund <- question_noul("Does the message ask for a refund?")
#' decide(decider_typesafe("jev-1.13.0"), refund, text = c(
#'   "Please refund the second charge.",
#'   "Where is my parcel?"
#' ))
#'
#' # Images of the package: two references and two inputs
#' dir <- system.file("extdata", "textiles", package = "decisions")
#' refs <- subset(textiles, role == "reference" & reference_rank == 1)
#' inputs <- subset(textiles, role == "input")[1:2, ]
#' quality <- question_choice("Inspect `inspection_image` for a flaw.", c(
#'   nominal = "A regular pattern.", defective = "A flaw in the pattern."
#' ))
#' decide(
#'   decider_openai(), list(quality = quality),
#'   image = file.path(dir, inputs$file),
#'   references = list(
#'     nominal = file.path(dir, refs$file[refs$class == "nominal"]),
#'     defective = file.path(dir, refs$file[refs$class == "defective"])
#'   )
#' )
#'
#' # A setup holds the decider, the questions and the references
#' setup <- decision_setup(decider_typesafe("jev-1.13.0"), list(refund = refund))
#' decide(setup, text = "Please refund the second charge.")
#' }
#' @seealso The deciders ([decider_typesafe()] and the others), the questions ([question_noul()], [question_choice()] and [question_score()]), [decision_setup()] to save the choices, and `vignette("getting-started")`.
#' @export
decide <- function(decider, questions, text = NULL, image = NULL,
                   references = NULL, max_size = 768, upscale = FALSE,
                   crop = "none", max_active = 10, rpm = NULL, path = NULL,
                   ignore_hash = FALSE) {
  from_setup <- S7::S7_inherits(decider, setup_class)
  given <- c(
    questions = !missing(questions), references = !missing(references),
    max_size = !missing(max_size), upscale = !missing(upscale),
    crop = !missing(crop)
  )
  if (from_setup && any(given)) {
    cli::cli_abort(c(
      paste(
        "A setup holds the questions, the references and the image",
        "settings, so {.fn decide} takes no {.arg {names(given)[given]}}",
        "with a setup."
      ),
      i = "Give the inputs by name, for example {.code decide(setup, text = x)}."
    ))
  }
  if (!is.null(rpm) &&
      !(is.numeric(rpm) && length(rpm) == 1 && is.finite(rpm) && rpm > 0)) {
    cli::cli_abort("{.arg rpm} must be {.code NULL} or one number above 0.")
  }
  image <- as_images(image)
  n <- count_inputs(text, image)
  # One text gives one key in the path file, whatever its encoding mark or
  # class (for example glue)
  if (!is.null(text)) text <- enc2utf8(as.character(text))
  setup <- if (from_setup) {
    decider
  } else {
    decision_setup(decider, questions, references, max_size, upscale, crop)
  }
  decider <- setup@decider
  questions <- setup@questions
  references <- setup@references
  images <- !is.null(image) || !is.null(references)
  check_input_type(decider, text = !is.null(text), image = images)
  if (!is.null(setup@calibrator)) {
    reason <- "to apply the calibrator of a setup"
    rlang::check_installed("probably", reason = reason)
    rlang::check_installed(
      probably::required_pkgs(setup@calibrator), reason = reason
    )
  }
  key <- read_key(decider)

  if (!is.null(path)) {
    hash <- run_hash(setup)
    saved <- read_path(path, hash, ignore_hash)
  }

  base <- new_request(decider, key, images = images, rpm = rpm)
  build <- \(input) httr2::req_body_json(base, build_body(
    decider@format, decider@model, questions,
    text = input$text, image = input$image, references = references
  ))
  read <- \(responses, requests) purrr::map2(
    responses, requests, read_result, decider = decider, questions = questions
  )
  inputs <- purrr::map(seq_len(n), \(i) list(
    text = unname(text[i]),
    image = if (!is.null(image)) prepare_setup_image(setup, image[[i]])
  ))
  results <- if (is.null(path)) {
    requests <- purrr::map(inputs, build)
    responses <- perform_requests(requests, max_active)
    structure(
      read(responses, requests), requests = attr(responses, "requests")
    )
  } else {
    send_with_path(inputs, build, read, path, hash, saved, max_active)
  }

  sent <- attr(results, "requests")
  out <- as_output(results, questions)
  if (all(is.na(out$.cost)) && any(!is.na(out$.input_tokens))) {
    cli::cli_inform(paste(
      "{provider_name(decider)} does not report a cost.",
      "`.cost` is NA. `.input_tokens` has the input tokens."
    ))
  }
  if (!is.null(setup@calibrator)) {
    out <- apply_calibrator(out, setup@calibrator)
  }
  structure(out, requests = sent)
}

# Checks of the arguments ---------------------------------------------------

#' Turn the questions into a named list
#'
#' @param questions One question, or a named list of questions.
#' @return A named list of questions. One question without a name is named
#'   `question`.
#' @details An answer whose column name is `class` is refused, because its
#'   column `.pred_class` would clash with the column of the answer. With two
#'   or more questions, the cleaned question names are the column prefixes,
#'   so they must be unique.
#' @noRd
as_questions <- function(questions) {
  if (S7::S7_inherits(questions, question)) {
    questions <- list(question = questions)
  }
  given <- names(questions)
  if (!is.list(questions) || length(questions) == 0 || is.null(given) ||
      anyNA(given) || !all(nzchar(given)) || anyDuplicated(given) > 0) {
    cli::cli_abort(paste(
      "{.arg questions} must be one question or a named list of questions",
      "with unique names."
    ))
  }
  purrr::walk(questions, question_type)
  answers <- purrr::map(questions, \(x) clean_name(names(x@answers)))
  if (any(purrr::map_lgl(answers, \(x) "class" %in% x))) {
    cli::cli_abort(paste(
      "No answer can have the column name {.val class}:",
      "its column would be {.code .pred_class}."
    ))
  }
  prefixes <- clean_name(given)
  if (length(questions) > 1 && anyDuplicated(prefixes) > 0) {
    cli::cli_abort(paste(
      "The question names {.val {given}} give the column prefixes",
      "{.val {prefixes}}, which must be unique."
    ))
  }
  questions
}

#' Turn images into a list
#'
#' @param images `NULL`, a character vector of paths or URLs, a list, or a
#'   magick vector of one or more images.
#' @return `NULL`, or a list with one image per element. A magick vector
#'   becomes a list with one element for each of its images, in order.
#' @noRd
as_images <- function(images) {
  if (inherits(images, "magick-image")) {
    return(purrr::map(seq_along(images), \(i) images[i]))
  }
  if (is.null(images)) NULL else as.list(images)
}

#' Count the inputs
#'
#' @param text The `text` of `decide()`.
#' @param image The images of `decide()`, as a list, or `NULL`.
#' @return The number of inputs.
#' @noRd
count_inputs <- function(text, image) {
  if (is.null(text) && is.null(image)) {
    cli::cli_abort("Give {.arg text}, {.arg image} or both.")
  }
  if (!is.null(text) && (!is.character(text) || anyNA(text))) {
    cli::cli_abort("{.arg text} must be a character vector with no {.code NA}.")
  }
  if (!is.null(text) && !is.null(image) && length(text) != length(image)) {
    cli::cli_abort(paste(
      "{.arg text} and {.arg image} must have the same length:",
      "element i of each makes input i."
    ))
  }
  length(text %||% image)
}

#' Check the reference images and turn them into lists
#'
#' @param references The `references` of `decide()`: `NULL`, or a named list
#'   (or a named character vector) of images per answer.
#' @param questions The named list of questions.
#' @return `NULL`, or a named list in which each element is a list of
#'   images.
#' @noRd
as_references <- function(references, questions) {
  if (is.null(references)) {
    return(NULL)
  }
  if (length(questions) > 1) {
    cli::cli_abort("{.arg references} work with one question only.")
  }
  allowed <- names(questions[[1]]@answers)
  given <- names(references)
  if (!(is.list(references) || is.character(references)) || is.null(given) ||
      !all(given %in% allowed) || anyDuplicated(given) > 0) {
    cli::cli_abort(c(
      "Each name of {.arg references} must be an answer of the question.",
      i = "Answers: {.val {allowed}}. Names: {.val {given}}."
    ))
  }
  references <- purrr::map(as.list(references), as_images)
  if (any(lengths(references) == 0)) {
    cli::cli_abort(
      "Each element of {.arg references} needs at least one image."
    )
  }
  references
}

#' Read the key of a decider
#'
#' @param decider A decider.
#' @return The value of `decider@credentials()`: the key, or `NULL` for a
#'   SystemOne server with no key.
#' @details For a provider with a key variable (see `provider_key()`), it
#'   stops before any request unless the key is one non-empty string. The
#'   message never shows the value.
#' @noRd
read_key <- function(decider) {
  key <- decider@credentials()
  if (is.null(provider_key(decider@provider)) ||
      (rlang::is_string(key) && nzchar(key))) {
    return(key)
  }
  cli::cli_abort(c(
    "The key of {provider_name(decider)} must be one non-empty string.",
    i = "Check the {.arg credentials} function of the decider."
  ))
}

#' Stop when the model cannot read an input
#'
#' @param decider A decider.
#' @param text,image `TRUE` when the call sends text, or images (inputs or
#'   references).
#' @return `NULL`, invisibly. It stops with an error when the input type of
#'   the decider excludes text or images. A decider with input `NA` is not
#'   checked.
#' @noRd
check_input_type <- function(decider, text, image) {
  if (is.na(decider@input)) {
    return(invisible())
  }
  reads <- strsplit(decider@input, "+", fixed = TRUE)[[1]]
  refused <- setdiff(c("text", "image")[c(text, image)], reads)
  if (length(refused) > 0) {
    cli::cli_abort(c(
      paste(
        "Model {.val {decider@model}} reads only {decider@input},",
        "so {.fn decide} sends no {refused}."
      ),
      i = paste(
        "Set {.arg input} of the decider to override the table of",
        "input types."
      )
    ))
  }
  invisible()
}

# Requests and responses ----------------------------------------------------

#' Make the request that all inputs of a call share
#'
#' @param decider A decider.
#' @param key The key, or `NULL` for no authentication.
#' @param images `TRUE` when the requests carry images.
#' @param rpm The largest number of requests per minute, or `NULL`.
#' @return An httr2 request without a body.
#' @details HTTP errors do not count as errors (`req_error()`), so each one
#'   comes back as a response that `read_result()` turns into a row error.
#'   Each request waits at most 300 seconds (`req_timeout()`); a timeout
#'   comes back as an error, which `read_result()` also turns into a row
#'   error.
#'   The request has no `req_retry()`: in httr2 1.2.3,
#'   `req_perform_parallel()` ignores `max_tries`, so `perform_requests()`
#'   sends the second try. A throttle with a bucket of one token sends one
#'   request each `60 / rpm` seconds; a bucket of `rpm` tokens would start
#'   full and let about twice `rpm` requests go out in the first minute.
#' @noRd
new_request <- function(decider, key, images, rpm) {
  req <- httr2::request(decider_url(decider)) |>
    httr2::req_error(is_error = \(resp) FALSE) |>
    httr2::req_timeout(300)
  if (!is.null(key) && decider@provider == "foundry") {
    req <- httr2::req_headers_redacted(req, `api-key` = key)
  } else if (!is.null(key)) {
    req <- httr2::req_auth_bearer_token(req, key)
  }
  if (images && decider@provider == "typesafe") {
    req <- httr2::req_headers(req, `TypeSafe-Danger-Zone-Images` = "true")
  }
  if (!is.null(rpm)) {
    req <- httr2::req_throttle(req, capacity = 1, fill_time_s = 60 / rpm)
  }
  req
}

#' Send the requests, and send once more those that got HTTP 429 or 503
#'
#' @param requests A list of httr2 requests.
#' @param max_active The largest number of requests at the same time.
#' @return A list with one element per request, in order: a response, an
#'   error when no response arrived, or `NULL` when the request did not
#'   finish (after an interrupt). Its attribute `interrupted` is `TRUE`
#'   after an interrupt, so that `send_with_path()` sends no further chunk.
#'   Its attribute `requests` is the number of requests sent, second tries
#'   included.
#' @details This is the default retry policy of httr2 (two tries, HTTP 429
#'   and 503), with a bounded time: the second tries go out together
#'   after `retry_wait()`, and a second 429 or 503 is final.
#'
#'   An interrupt (Esc) never loses the answers of the first pass. After an
#'   interrupt in the first pass (httr2 then returns `NULL` for the requests
#'   that did not finish), nothing is sent again. An interrupt during the
#'   wait skips the second tries; their rows get the error "Interrupted
#'   before a retry."
#' @noRd
perform_requests <- function(requests, max_active) {
  send <- \(x) httr2::req_perform_parallel(
    x, on_error = "continue", max_active = max_active
  )
  # httr2 gives NULL for a request that did not finish: Esc was pressed
  mark <- \(x, sent) structure(
    x, interrupted = any(purrr::map_lgl(x, is.null)), requests = sent
  )
  responses <- send(requests)
  busy <- which(purrr::map_lgl(responses, \(x) {
    inherits(x, "httr2_response") && httr2::resp_status(x) %in% c(429, 503)
  }))
  if (length(busy) == 0 || any(purrr::map_lgl(responses, is.null))) {
    return(mark(responses, length(requests)))
  }
  waited <- tryCatch(
    {
      Sys.sleep(retry_wait(responses[busy]))
      TRUE
    },
    interrupt = \(cnd) FALSE
  )
  if (!waited) {
    responses[busy] <- list(simpleError("Interrupted before a retry."))
    return(structure(
      responses, interrupted = TRUE, requests = length(requests)
    ))
  }
  responses[busy] <- send(requests[busy])
  mark(responses, length(requests) + length(busy))
}

#' Find the wait before the second tries
#'
#' @param responses The responses with HTTP 429 or 503.
#' @return The longest wait in seconds that their `Retry-After` headers ask
#'   for (seconds or an HTTP date), between 0 and 60 seconds. A response
#'   without the header, or with a value that cannot be read (for example
#'   `"soon"`, or a date in a response without a `Date` header), counts as
#'   1 second.
#' @noRd
retry_wait <- function(responses) {
  waits <- purrr::map_dbl(responses, \(x) tryCatch(
    suppressWarnings(httr2::resp_retry_after(x)),
    error = \(e) NA_real_
  ))
  waits[is.na(waits)] <- 1
  min(max(waits, 0), 60)
}

#' Read the result of one request
#'
#' @param response An element of `perform_requests()`: a response, an
#'   error when no response arrived, or `NULL` when the request did not
#'   finish.
#' @param request The request that was sent.
#' @param decider A decider.
#' @param questions The named list of questions.
#' @return A list with `answers` (as in `parse_answers()`, or `NULL` for a
#'   row error), `model`, `input_tokens`, `cost`, `seconds` and `error`
#'   (`NA` or a message). `model` is one string, and `input_tokens`, `cost`
#'   and `seconds` are single numbers or `NA`.
#' @details A body that cannot be read (an unknown charset) or that has an
#'   unexpected shape (for example `"answers": "oops"`) gives a row error,
#'   so that one bad response never stops the call.
#' @noRd
read_result <- function(response, request, decider, questions) {
  if (!inherits(response, "httr2_response")) {
    reason <- if (is.null(response)) {
      "the request did not finish."
    } else {
      condition_text(response)
    }
    return(failed_result("No response", reason, decider, request))
  }
  seconds <- httr2::resp_timing(response)[["total"]] %||% NA_real_
  has_body <- httr2::resp_has_body(response)
  text <- tryCatch(
    if (has_body) httr2::resp_body_string(response) else "",
    error = identity
  )
  if (inherits(text, "error")) {
    problem <- paste("The response cannot be read:", condition_text(text))
    return(failed_result(problem, "", decider, request, seconds))
  }
  if (httr2::resp_is_error(response)) {
    problem <- paste("HTTP", httr2::resp_status(response))
    return(failed_result(problem, text, decider, request, seconds))
  }
  parsed <- tryCatch(
    {
      body <- jsonlite::parse_json(text)
      if (!is.list(body)) {
        cli::cli_abort("the body is not a JSON object.")
      }
      answers <- parse_answers(decider@format, body, questions)
      c(answers, list(
        model = body[["model"]],
        error = answer_error(answers$answers, questions)
      ))
    },
    error = identity
  )
  if (inherits(parsed, "error")) {
    problem <- paste("The response cannot be read:", condition_text(parsed))
    return(failed_result(problem, text, decider, request, seconds))
  }
  list(
    answers = if (is.na(parsed$error)) parsed$answers,
    model = if (rlang::is_string(parsed$model)) parsed$model else decider@model,
    input_tokens = parsed$input_tokens,
    cost = parsed$cost,
    seconds = seconds,
    error = parsed$error
  )
}

#' Write the message of a condition on one line
#'
#' @param cnd A condition.
#' @return Its message with no ANSI color codes, and with each run of line
#'   breaks (and the spaces around them) changed to one space. Messages of
#'   nested rlang and purrr conditions hold both.
#' @noRd
condition_text <- function(cnd) {
  text <- cli::ansi_strip(conditionMessage(cnd))
  gsub("[[:space:]]*[\r\n]+[[:space:]]*", " ", text)
}

#' Make the result of a failed call
#'
#' @param problem What went wrong, for example `"HTTP 500"`.
#' @param text The text of the provider or of the error, kept word for word.
#' @param decider A decider.
#' @param request The request that was sent.
#' @param seconds The time of the response, or `NA`.
#' @return A result as in `read_result()`, with no answers. The error names
#'   the model and the size of the request body in bytes (serialized as
#'   `httr2::req_body_json()` does).
#' @noRd
failed_result <- function(problem, text, decider, request, seconds = NA_real_) {
  json <- jsonlite::toJSON(
    httr2::req_get_body(request), auto_unbox = TRUE, digits = 22, null = "null"
  )
  error <- paste0(
    problem, " (model ", decider@model, ", request of ",
    nchar(json, type = "bytes"), " bytes)",
    if (nzchar(text)) paste0(": ", text) else "."
  )
  list(
    answers = NULL, model = decider@model, input_tokens = NA_real_,
    cost = NA_real_, seconds = seconds, error = error
  )
}

#' Check the answers of one response
#'
#' @param answers The `answers` of `parse_answers()`.
#' @param questions The named list of questions.
#' @return `NA` when every answer is allowed, or one text that names each
#'   problem: an answer that is not one text (for example an array), a
#'   missing answer, an answer that is not allowed, a missing probability
#'   of an allowed answer (any question type), or a score question whose
#'   score is not one number or whose probabilities are all zero.
#' @noRd
answer_error <- function(answers, questions) {
  problems <- purrr::imap_chr(questions, \(question, name) {
    answer <- answers[[name]][["answer"]]
    probabilities <- answers[[name]][["probabilities"]]
    score <- answers[[name]][["score"]]
    if (!is.character(answer) || length(answer) != 1) {
      paste0("The answer to question `", name, "` is not one text.")
    } else if (is.na(answer)) {
      paste0("No answer to question `", name, "`.")
    } else if (!answer %in% names(question@answers)) {
      paste0(
        "The answer \"", answer, "\" to question `", name,
        "` is not an allowed answer."
      )
    } else if (anyNA(probabilities)) {
      paste0("The probabilities of question `", name, "` are incomplete.")
    } else if (question_type(question) == "score" &&
               (length(score) != 1 || is.na(score) ||
                all(probabilities == 0))) {
      paste0(
        "The score of question `", name, "` is not one number, or its ",
        "probabilities are all zero."
      )
    } else {
      NA_character_
    }
  })
  problems <- problems[!is.na(problems)]
  if (length(problems) == 0) NA_character_ else paste(problems, collapse = " ")
}

# Output --------------------------------------------------------------------

#' Make the output tibble of `decide()`
#'
#' @param results The results of `read_result()`, in input order.
#' @param questions The named list of questions.
#' @return The tibble that `decide()` returns.
#' @noRd
as_output <- function(results, questions) {
  answers <- purrr::map(results, "answers")
  columns <- purrr::imap(questions, \(question, name) {
    columns <- answer_columns(question, purrr::map(answers, name))
    if (length(questions) > 1) {
      names(columns) <- paste0(clean_name(name), "_", names(columns))
    }
    columns
  })
  tibble::as_tibble(c(
    purrr::list_flatten(unname(columns)),
    list(
      .model = purrr::map_chr(results, "model"),
      .input_tokens = purrr::map_dbl(results, "input_tokens"),
      .cost = purrr::map_dbl(results, "cost"),
      .seconds = purrr::map_dbl(results, "seconds"),
      .error = purrr::map_chr(results, "error")
    )
  ))
}

#' Make the columns of one question
#'
#' @param question A question.
#' @param picked The answer of the question for each input, as in
#'   `parse_answers()`, or `NULL` for a row error.
#' @return A named list: `.pred_class` (a factor with the exact allowed
#'   answers as levels), `.pred_<answer>` for each allowed answer (the answer
#'   name cleaned by `clean_name()`), and `.score` for a score question.
#' @noRd
answer_columns <- function(question, picked) {
  allowed <- names(question@answers)
  answer <- purrr::map_chr(picked, \(x) x[["answer"]] %||% NA_character_)
  probabilities <- purrr::map(
    rlang::set_names(allowed, paste0(".pred_", clean_name(allowed))),
    \(level) purrr::map_dbl(
      picked, \(x) x[["probabilities"]][[level]] %||% NA_real_
    )
  )
  c(
    list(.pred_class = factor(answer, levels = allowed)),
    probabilities,
    if (question_type(question) == "score") {
      list(.score = purrr::map_dbl(picked, \(x) x[["score"]] %||% NA_real_))
    }
  )
}
