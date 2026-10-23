#' Ask a decision model typed questions
#'
#' Sends each input (a text, an image or both) with the questions to one
#' model and returns, for each input, the answer and a probability for each
#' allowed answer.
#'
#' @param decider A decider from `decider_typesafe()`, `decider_openai()`,
#'   `decider_foundry()`, `decider_openrouter()` or `decider_systemone()`.
#' @param questions One question from `question_noul()`, `question_choice()`
#'   or `question_score()`, or a named list of questions. The names are the
#'   question names of the request and, with two or more questions, the
#'   prefixes of the output columns. One question without a name is sent as
#'   `question`.
#' @param text A character vector with one text per input, or `NULL`.
#' @param image A character vector of file paths or URLs, or a list of
#'   magick images, with one image per input; or `NULL`. With `text`,
#'   element i of `text` and element i of `image` make input i.
#' @param references Reference images for the answers, or `NULL`: a named
#'   list in which each name is an allowed answer of the question and each
#'   element holds the images of that answer (paths, URLs or magick images).
#'   This release takes references with one question only.
#' @param max_size The longest side of each image in pixels after the
#'   resize, or `NULL` to keep the size. The default is `768`.
#' @param upscale `TRUE` enlarges an image that is smaller than `max_size`.
#'   `FALSE` (the default) never enlarges.
#' @param crop `"none"` (the default), `"center"`, a box
#'   `c(x, y, width, height)` in pixels, or a function that takes a magick
#'   image and returns a box. `max_size`, `upscale` and `crop` apply to the
#'   inputs and to the references.
#' @param max_active The largest number of requests in progress at the same
#'   time. The default is `10`.
#' @param rpm The largest number of requests per minute, or `NULL` (the
#'   default) for no limit.
#' @param path Not implemented yet: it must be `NULL`.
#' @param ignore_hash Not used yet.
#' @return A tibble with one row per input, in the order of the inputs:
#'   * For one question: `.pred_class`, a factor whose levels are the
#'     allowed answers; `.pred_<answer>`, the probability of each allowed
#'     answer, with the answer name kept exactly (for example
#'     `` `.pred_not sure` ``); and `.score` for a score question.
#'   * For two or more questions: the same columns with the question name
#'     and `_` as a prefix, for example `quality_.pred_class`.
#'   * `.model`: the model that the provider reports, or the model of the
#'     decider when the response has none.
#'   * `.input_tokens`: the input tokens that the provider reports.
#'   * `.cost`: the cost that the provider reports, or `NA`.
#'   * `.seconds`: the time of the response.
#'   * `.error`: `NA`, or the reason why the answers of the row are `NA`.
#' @details One request goes out per input, in parallel
#'   (`httr2::req_perform_parallel()`), with at most `max_active` requests
#'   at a time and at most `rpm` requests per minute. A request that gets
#'   HTTP 429 or 503 is tried again (`httr2::req_retry()`).
#'
#'   No row is lost. A row has `NA` answers and a message in `.error` when
#'   the call fails (the message holds the error text of the provider word
#'   for word, the model name and the size of the request in bytes), when an
#'   answer is not an allowed answer or is missing, or when the
#'   probabilities of a score question are all zero or incomplete. A row
#'   with an answered call keeps its `.input_tokens` and `.cost`.
#'
#'   `decide()` reads the key and checks the input type of the model before
#'   any request. It prepares each reference image once per call and each
#'   input image once. With `decider_systemone(image_format = "images")`, it
#'   writes the images with three color channels.
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
#'   `httr2::resp_timing()` gives it; for a request that was tried again, it
#'   is the time of the last try. It is `NA` when no response arrived.
#' @examples
#' \dontrun{
#' refund <- question_noul("Does the message ask for a refund?")
#' decide(decider_typesafe("jev-1.13.0"), refund, text = c(
#'   "Please refund the second charge.",
#'   "Where is my parcel?"
#' ))
#'
#' quality <- question_choice("Inspect `inspection_image` for a defect.", c(
#'   normal = "A clean surface.", defective = "A dark streak."
#' ))
#' decide(
#'   decider_openai(), list(quality = quality),
#'   image = c("part-1.jpg", "part-2.jpg"),
#'   references = list(normal = "good.jpg", defective = "streak.jpg")
#' )
#' }
#' @export
decide <- function(decider, questions, text = NULL, image = NULL,
                   references = NULL, max_size = 768, upscale = FALSE,
                   crop = "none", max_active = 10, rpm = NULL, path = NULL,
                   ignore_hash = FALSE) {
  if (!is.null(path)) {
    cli::cli_abort("{.arg path} is not implemented yet.")
  }
  if (!S7::S7_inherits(decider, decider_class)) {
    cli::cli_abort(
      "{.arg decider} must come from a {.code decider_*()} function."
    )
  }
  questions <- as_questions(questions)
  image <- as_images(image)
  n <- count_inputs(text, image)
  references <- as_references(references, questions)
  images <- !is.null(image) || !is.null(references)
  check_input_type(decider, text = !is.null(text), image = images)
  key <- decider@credentials()

  prepare <- \(x) prepare_image(
    x, max_size = max_size, upscale = upscale, crop = crop,
    rgb = decider@format == "systemone_images"
  )
  if (!is.null(references)) {
    references <- purrr::map(references, \(x) purrr::map(x, prepare))
  }
  base <- new_request(decider, key, images = images, rpm = rpm)
  requests <- purrr::map(seq_len(n), \(i) {
    body <- build_body(
      decider@format, decider@model, questions,
      text = unname(text[i]),
      image = if (!is.null(image)) prepare(image[[i]]),
      references = references
    )
    httr2::req_body_json(base, body)
  })
  responses <- httr2::req_perform_parallel(
    requests, on_error = "continue", max_active = max_active
  )
  results <- purrr::map2(
    responses, requests, read_result, decider = decider, questions = questions
  )

  out <- as_output(results, questions)
  if (all(is.na(out$.cost)) && any(!is.na(out$.input_tokens))) {
    cli::cli_inform(paste(
      "{provider_name(decider)} does not report a cost.",
      "`.cost` is NA. `.input_tokens` has the input tokens."
    ))
  }
  out
}

# Checks of the arguments ---------------------------------------------------

#' Turn the questions into a named list
#'
#' @param questions One question, or a named list of questions.
#' @return A named list of questions. One question without a name is named
#'   `question`.
#' @details An answer named `class` is refused, because its column
#'   `.pred_class` would clash with the column of the answer.
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
  if (any(purrr::map_lgl(questions, \(x) "class" %in% names(x@answers)))) {
    cli::cli_abort(paste(
      "No answer can be named {.val class}:",
      "its column would be {.code .pred_class}."
    ))
  }
  questions
}

#' Turn images into a list
#'
#' @param images `NULL`, a character vector of paths or URLs, a list, or one
#'   magick image.
#' @return `NULL`, or a list with one image per element. One magick image
#'   becomes a list of one image.
#' @noRd
as_images <- function(images) {
  if (inherits(images, "magick-image")) {
    return(list(images))
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
#' @details The retry policy is the httr2 default (two tries, HTTP 429 and
#'   503, D170); `max_tries = 2` is given only to avoid the message of httr2.
#'   The request keeps the httr2 error policy, because a request whose HTTP
#'   errors count as successes is never tried again. `decide()` turns the
#'   errors into rows.
#' @noRd
new_request <- function(decider, key, images, rpm) {
  req <- httr2::request(decider_url(decider)) |>
    httr2::req_retry(max_tries = 2)
  if (!is.null(key) && decider@provider == "foundry") {
    req <- httr2::req_headers_redacted(req, `api-key` = key)
  } else if (!is.null(key)) {
    req <- httr2::req_auth_bearer_token(req, key)
  }
  if (images && decider@provider == "typesafe") {
    req <- httr2::req_headers(req, `TypeSafe-Danger-Zone-Images` = "true")
  }
  if (!is.null(rpm)) {
    req <- httr2::req_throttle(req, capacity = rpm, fill_time_s = 60)
  }
  req
}

#' Read the result of one request
#'
#' @param response An element of `httr2::req_perform_parallel()`: a
#'   response, an error (with the response for an HTTP error), or `NULL`
#'   when the request did not finish.
#' @param request The request that was sent.
#' @param decider A decider.
#' @param questions The named list of questions.
#' @return A list with `answers` (as in `parse_answers()`, or `NULL` for a
#'   row error), `model`, `input_tokens`, `cost`, `seconds` and `error`
#'   (`NA` or a message).
#' @noRd
read_result <- function(response, request, decider, questions) {
  # An HTTP error carries its response; a failed connection has none
  resp <- if (inherits(response, "httr2_response")) {
    response
  } else {
    response[["resp"]]
  }
  if (is.null(resp)) {
    reason <- if (is.null(response)) {
      "the request did not finish."
    } else {
      conditionMessage(response)
    }
    return(failed_result("No response", reason, decider, request))
  }
  seconds <- httr2::resp_timing(resp)[["total"]] %||% NA_real_
  text <- if (httr2::resp_has_body(resp)) httr2::resp_body_string(resp) else ""
  if (httr2::resp_is_error(resp)) {
    problem <- paste("HTTP", httr2::resp_status(resp))
    return(failed_result(problem, text, decider, request, seconds))
  }
  body <- tryCatch(jsonlite::parse_json(text), error = \(e) NULL)
  if (!is.list(body)) {
    problem <- "The response is not a JSON object"
    return(failed_result(problem, text, decider, request, seconds))
  }
  parsed <- parse_answers(decider@format, body, questions)
  error <- answer_error(parsed$answers, questions)
  list(
    answers = if (is.na(error)) parsed$answers,
    model = as.character(body[["model"]] %||% decider@model),
    input_tokens = parsed$input_tokens,
    cost = parsed$cost,
    seconds = seconds,
    error = error
  )
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
#'   problem: a missing answer, an answer that is not allowed, or a score
#'   question whose probabilities contain `NA` or are all zero.
#' @noRd
answer_error <- function(answers, questions) {
  problems <- purrr::imap_chr(questions, \(question, name) {
    answer <- answers[[name]][["answer"]]
    probabilities <- answers[[name]][["probabilities"]]
    if (is.na(answer)) {
      paste0("No answer to question `", name, "`.")
    } else if (!answer %in% names(question@answers)) {
      paste0(
        "The answer \"", answer, "\" to question `", name,
        "` is not an allowed answer."
      )
    } else if (question_type(question) == "score" &&
               (anyNA(probabilities) || all(probabilities == 0))) {
      paste0(
        "The probabilities of the score question `", name,
        "` contain NA or are all zero."
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
      names(columns) <- paste0(name, "_", names(columns))
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
#' @return A named list: `.pred_class` (a factor with the allowed answers as
#'   levels), `.pred_<answer>` for each allowed answer, and `.score` for a
#'   score question.
#' @noRd
answer_columns <- function(question, picked) {
  allowed <- names(question@answers)
  answer <- purrr::map_chr(picked, \(x) x[["answer"]] %||% NA_character_)
  probabilities <- purrr::map(
    rlang::set_names(allowed, paste0(".pred_", allowed)),
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
