# Request translators: one per request format. Each turns the questions and
# one input into a request body, and a response body into answers. The
# verified fields of each provider are in data-raw/formats.md.

#' Build the request body of one input
#'
#' Translates the questions and one input (a text, an image or both) into the
#' body of a request in one request format.
#'
#' @param format The request format: `"systemone"` (TypeSafe, `laya-serve`
#'   and Foundry), `"systemone_images"` (the SGLang server of Clef-Flash),
#'   `"openai"` or `"openrouter"`.
#' @param model The model name, or `NULL` to leave the field out (a
#'   `laya-serve` server then picks its own checkpoint).
#' @param questions A named list of questions, made with `question_noul()`,
#'   `question_choice()` or `question_score()`. The names are the question
#'   names of the request.
#' @param text The text of the input: one string, or `NULL`.
#' @param image The image of the input: a raw vector of JPEG bytes from
#'   `prepare_image()`, or `NULL`.
#' @param references Reference images, or `NULL`: a named list in which each
#'   name is an answer and each element is a list of raw vectors of JPEG
#'   bytes.
#' @return A list for `httr2::req_body_json()`.
#' @details Each body puts the parts that all inputs share first (the
#'   questions with their instructions, then the reference images) and the
#'   input last, so that the prompt caching of a provider can work (D171).
#'
#'   OpenRouter takes the SystemOne body (verified on 2026-10-23), so the
#'   formats `"systemone"` and `"openrouter"` share one translator.
#'
#'   Reference images attach to every question that has an answer of the
#'   same name. SystemOne links them to the `criteria` of choice and noul
#'   questions as `examples`; its score `criteria` is an array of texts with
#'   no place for examples. The image-list format names them in the state
#'   text. OpenAI puts them in the `instructions` of the question.
#' @noRd
build_body <- function(format, model, questions, text = NULL, image = NULL,
                       references = NULL) {
  build <- switch(format,
    systemone = ,
    openrouter = build_systemone,
    systemone_images = build_systemone_images,
    openai = build_openai,
    cli::cli_abort("Unknown request format {.val {format}}.")
  )
  build(model, questions, text, image, references)
}

#' Read the answers of a response body
#'
#' @param format The request format, as in `build_body()`.
#' @param body The response body as a list, as from `httr2::resp_body_json()`
#'   (no simplification).
#' @param questions The named list of questions of the request.
#' @return A list with:
#'   * `answers`: a named list with one element per question, in the order of
#'     `questions`. Each element is a list with `answer` (the answer of the
#'     provider, or `NA`), `probabilities` (a named numeric vector in the
#'     order of the allowed answers; `NA` for an answer the provider left
#'     out), and, for a score question, `score`.
#'   * `input_tokens`: the input tokens that the provider reports, or `NA`
#'     when `usage.input_tokens` is not one number.
#'   * `cost`: the cost that the provider reports (`usage.cost` of
#'     OpenRouter), or `NA` when it reports none or not one number.
#' @details The function does not check that an answer is allowed:
#'   `decide()` does. Probabilities are matched by answer name, never by
#'   position, because a provider can list them in another order. A noul
#'   answer is `"true"` when the probability of true is 0.5 or more. A score
#'   answer is the level with the highest probability; `score` is the score
#'   that the provider reports, or else the mean level index (0 for the
#'   lowest level) weighted by the probabilities.
#' @noRd
parse_answers <- function(format, body, questions) {
  parse <- switch(format,
    systemone = ,
    systemone_images = ,
    openrouter = parse_systemone,
    openai = parse_openai,
    cli::cli_abort("Unknown request format {.val {format}}.")
  )
  usage <- if (is.list(body[["usage"]])) body[["usage"]] else list()
  list(
    answers = parse(body, questions),
    input_tokens = as_number(usage[["input_tokens"]]),
    cost = as_number(usage[["cost"]])
  )
}

# SystemOne ---------------------------------------------------------------

#' Build a SystemOne body
#'
#' The state is an object with the field `text` and, for an image, the field
#' `inspection_image`, which holds the asset id of the image. Assets are
#' keyed by id: `reference_1`, `reference_2`, ... and `query` for the
#' inspected image, which comes last.
#'
#' @inheritParams build_body
#' @return A list with `model`, `questions`, `assets` and `state`. Empty
#'   fields are left out.
#' @noRd
build_systemone <- function(model, questions, text, image, references) {
  ids <- reference_positions(references) |>
    purrr::map(\(at) paste0("reference_", at))
  assets <- c(
    unlist(references, recursive = FALSE, use.names = FALSE) |>
      purrr::map(image_asset) |>
      rlang::set_names(unlist(ids, use.names = FALSE)),
    if (!is.null(image)) list(query = image_asset(image))
  )
  state <- list(text = text, inspection_image = if (!is.null(image)) "query")
  purrr::compact(list(
    model = model,
    questions = purrr::map(questions, systemone_question, examples = ids),
    assets = assets,
    state = purrr::compact(state)
  ))
}

#' Build a SystemOne body with an ordered image list
#'
#' The SGLang server of Clef-Flash ignores `assets`. It takes an `images` list
#' of data URLs: the reference images first, the inspected image last. The
#' state is one text: a legend that says which image is which, then the text
#' of the input.
#'
#' @inheritParams build_body
#' @return A list with `model`, `questions`, `images` and `state`. Empty
#'   fields are left out.
#' @noRd
build_systemone_images <- function(model, questions, text, image, references) {
  images <- c(
    unlist(references, recursive = FALSE, use.names = FALSE),
    if (!is.null(image)) list(image)
  )
  legend <- c(
    purrr::imap_chr(reference_positions(references), \(at, answer) paste0(
      "Reference images of the answer `", answer, "`: ",
      paste("image", at, collapse = ", "), "."
    )),
    if (!is.null(image)) {
      paste(
        "Image", length(images), "is `inspection_image`, the image to inspect."
      )
    }
  )
  purrr::compact(list(
    model = model,
    questions = purrr::map(questions, systemone_question),
    images = purrr::map(images, data_url),
    state = paste(c(legend, text), collapse = "\n")
  ))
}

#' Translate one question into the SystemOne form
#'
#' @param question A question object.
#' @param examples A named list: answer name to the asset ids of its
#'   reference images, or `NULL`.
#' @return A list with `type`, `instructions` and, when needed, `criteria`:
#'   * noul: `criteria` (`true`, `false`) only when an answer has a
#'     description or reference images. TypeSafe needs none.
#'   * choice: `criteria` maps each answer to its description, or to
#'     `list(description, examples)` when it has reference images.
#'   * score: `criteria` is an array of level texts, lowest first, each
#'     `"<name>: <description>"`, so that the model sees the level names.
#'   A missing description becomes the answer name.
#' @noRd
systemone_question <- function(question, examples = NULL) {
  type <- question_type(question)
  answers <- question@answers
  out <- list(type = type, instructions = question@instructions)
  if (type == "score") {
    levels <- paste0(names(answers), ": ", answers)
    levels[is.na(answers)] <- names(answers)[is.na(answers)]
    out$criteria <- as.list(levels)
    return(out)
  }
  linked <- names(answers) %in% names(examples)
  if (type == "noul" && all(is.na(answers)) && !any(linked)) {
    return(out)
  }
  out$criteria <- purrr::imap(described(answers), \(description, answer) {
    ids <- examples[[answer]]
    if (length(ids) == 0) {
      return(description)
    }
    list(description = description, examples = as.list(ids))
  })
  out
}

#' Read the answers of a SystemOne response
#'
#' SystemOne, the image-list format and OpenRouter answer alike: `answers` is
#' an object keyed by question name; a noul answer has `noul` (the
#' probability of true); a choice answer has `choice` and `probabilities`
#' keyed by answer; a score answer has `score` and `probabilities` keyed by
#' level index (`"0"` for the lowest level).
#'
#' @inheritParams parse_answers
#' @return The `answers` element of `parse_answers()`.
#' @noRd
parse_systemone <- function(body, questions) {
  purrr::imap(questions, \(question, name) {
    answer <- body[["answers"]][[name]]
    probabilities <- answer[["probabilities"]]
    levels <- names(question@answers)
    switch(question_type(question),
      noul = noul_answer(answer[["noul"]]),
      choice = choice_answer(answer[["choice"]], probabilities, levels),
      score = score_answer(answer[["score"]], probabilities, levels,
                           keys = as.character(seq_along(levels) - 1L))
    )
  })
}

# OpenAI ------------------------------------------------------------------

#' Build an OpenAI Decisions body
#'
#' The input is the text alone, or, with an image, one user message with the
#' text, a label that names `inspection_image` ("the image to inspect:") and the image.
#'
#' @inheritParams build_body
#' @return A list with `model`, `questions` (an array) and `input`.
#' @noRd
build_openai <- function(model, questions, text, image, references) {
  input <- text
  if (!is.null(image)) {
    content <- c(
      if (!is.null(text)) list(input_text(text)),
      list(input_text("`inspection_image`, the image to inspect:"), input_image(image))
    )
    input <- list(list(role = "user", content = content))
  }
  questions <- purrr::imap(questions, openai_question, references = references)
  list(model = model, questions = unname(questions), input = input)
}

#' Translate one question into the OpenAI form
#'
#' A noul question becomes a `predicate`, a choice lists `choices` with
#' `value` and `description`, and a score lists `levels` with `label` and
#' `description`, lowest first. A missing description becomes the answer
#' name.
#'
#' @param question A question object.
#' @param name The name of the question.
#' @param references The reference images of `build_body()`, or `NULL`.
#' @return A list for the `questions` array.
#' @noRd
openai_question <- function(question, name, references = NULL) {
  type <- question_type(question)
  answers <- described(question@answers)
  out <- list(
    type = if (type == "noul") "predicate" else type,
    name = name,
    instructions = openai_instructions(question, references)
  )
  if (type == "choice") {
    out$choices <- unname(purrr::imap(answers, \(description, value) {
      list(value = value, description = description)
    }))
  }
  if (type == "score") {
    out$levels <- unname(purrr::imap(answers, \(description, label) {
      list(label = label, description = description)
    }))
  }
  out
}

#' Write the instructions of an OpenAI question
#'
#' A predicate has no field for the descriptions of `true` and `false`, so
#' they follow the instructions, one line each. With reference images for
#' the answers of the question, the instructions become an array: the text,
#' then for each answer a label and its images.
#'
#' @param question A question object.
#' @param references The reference images of `build_body()`, or `NULL`.
#' @return One string, or a list of `input_text` and `input_image` parts.
#' @noRd
openai_instructions <- function(question, references) {
  text <- question@instructions
  given <- question@answers[!is.na(question@answers)]
  if (S7::S7_inherits(question, question_noul) && length(given) > 0) {
    text <- paste(c(text, paste0(names(given), ": ", given)), collapse = "\n")
  }
  shown <- references[intersect(names(question@answers), names(references))]
  if (length(shown) == 0) {
    return(text)
  }
  parts <- purrr::imap(shown, \(images, answer) c(
    list(input_text(paste0("Reference images of the answer `", answer, "`:"))),
    purrr::map(images, input_image)
  ))
  c(list(input_text(text)), unlist(unname(parts), recursive = FALSE))
}

#' Read the answers of an OpenAI Decisions response
#'
#' `answers` is an array; each answer has `name`. A predicate answer has
#' `probability` (of true); choice and score answers have `probabilities`,
#' an array of `{value, probability}` (choice) or `{value, label,
#' probability}` (score, matched by `label`).
#'
#' @inheritParams parse_answers
#' @return The `answers` element of `parse_answers()`.
#' @noRd
parse_openai <- function(body, questions) {
  answers <- body[["answers"]] %||% list()
  names(answers) <- purrr::map_chr(answers, "name", .default = NA_character_)
  purrr::imap(questions, \(question, name) {
    answer <- answers[[name]]
    entries <- answer[["probabilities"]]
    levels <- names(question@answers)
    switch(question_type(question),
      noul = noul_answer(answer[["probability"]]),
      choice = choice_answer(
        answer[["choice"]], keyed_by(entries, "value"), levels
      ),
      score = score_answer(
        answer[["score"]], keyed_by(entries, "label"), levels
      )
    )
  })
}

#' Turn an OpenAI probability array into a named list
#'
#' @param entries A list of objects, each with `probability` and `key`.
#' @param key The field that names each probability: `"value"` or `"label"`.
#' @return A list of probabilities, named by `key`.
#' @noRd
keyed_by <- function(entries, key) {
  rlang::set_names(
    purrr::map(entries, "probability"),
    purrr::map_chr(entries, key, .default = NA_character_)
  )
}

# Answers -----------------------------------------------------------------

#' Make the answer of a noul question
#'
#' @param probability The probability of true, or `NULL` when it is missing.
#' @return A list with `answer` (`"true"` when the probability is 0.5 or more)
#'   and `probabilities` (`c(true = p, false = 1 - p)`).
#' @noRd
noul_answer <- function(probability) {
  p <- as.numeric(probability %||% NA_real_)
  list(
    answer = if (is.na(p)) NA_character_ else if (p >= 0.5) "true" else "false",
    probabilities = c(true = p, false = 1 - p)
  )
}

#' Make the answer of a choice question
#'
#' @param choice The answer of the provider, or `NULL`.
#' @param probabilities A list of probabilities named by answer.
#' @param levels The allowed answers, in order.
#' @return A list with `answer` and `probabilities`.
#' @noRd
choice_answer <- function(choice, probabilities, levels) {
  list(
    answer = choice %||% NA_character_,
    probabilities = pick_probabilities(probabilities, levels)
  )
}

#' Make the answer of a score question
#'
#' @param score The score that the provider reports, or `NULL`.
#' @param probabilities A list of probabilities named by `keys`.
#' @param levels The allowed levels, lowest first.
#' @param keys The name of each level in `probabilities`: the level names
#'   (OpenAI), or the level indices `"0"`, `"1"`, ... (SystemOne).
#' @return A list with `answer` (the most probable level), `probabilities`
#'   and `score`.
#' @noRd
score_answer <- function(score, probabilities, levels, keys = levels) {
  p <- pick_probabilities(probabilities, levels, keys)
  list(
    answer = if (all(is.na(p))) NA_character_ else levels[which.max(p)],
    probabilities = p,
    score = as.numeric(score %||% (sum(p * (seq_along(p) - 1)) / sum(p)))
  )
}

#' Pick the probability of each allowed answer by name
#'
#' @param probabilities A list of probabilities named by `keys`, or `NULL`.
#' @param levels The allowed answers, in order.
#' @param keys The name of each answer in `probabilities`.
#' @return A numeric vector named by `levels`, with `NA` for an answer that
#'   has no probability.
#' @noRd
pick_probabilities <- function(probabilities, levels, keys = levels) {
  p <- purrr::map_dbl(keys, \(key) {
    as.numeric(probabilities[[key]] %||% NA_real_)
  })
  rlang::set_names(p, levels)
}

# Small parts -------------------------------------------------------------

#' Read one number of a response
#'
#' @param x A value of a parsed JSON body, or `NULL`.
#' @return `x` as a double when it is one number, else `NA`.
#' @noRd
as_number <- function(x) {
  if (is.numeric(x) && length(x) == 1) as.numeric(x) else NA_real_
}

#' Find the type of a question
#'
#' @param question A question object.
#' @return `"noul"`, `"choice"` or `"score"`.
#' @noRd
question_type <- function(question) {
  if (S7::S7_inherits(question, question_noul)) return("noul")
  if (S7::S7_inherits(question, question_choice)) return("choice")
  if (S7::S7_inherits(question, question_score)) return("score")
  cli::cli_abort(paste(
    "Each question must come from {.fn question_noul},",
    "{.fn question_choice} or {.fn question_score}."
  ))
}

#' Fill missing descriptions with the answer names
#'
#' @param answers The named character vector of a question's answers.
#' @return `answers`, with each `NA` replaced by its name.
#' @noRd
described <- function(answers) {
  ifelse(is.na(answers), names(answers), answers)
}

#' Number the reference images
#'
#' @param references The reference images of `build_body()`, or `NULL`.
#' @return A named list: answer name to the positions of its images when all
#'   images are in one list, in order (1, 2, ...).
#' @noRd
reference_positions <- function(references) {
  n <- lengths(references)
  purrr::map2(cumsum(n) - n, n, \(before, count) before + seq_len(count))
}

#' Encode bytes as base64 on one line
#'
#' `jsonlite::base64_enc()` breaks its output into lines, and TypeSafe
#' rejects such a string (data-raw/formats.md).
#'
#' @param bytes A raw vector.
#' @return One string with no line breaks.
#' @noRd
base64 <- function(bytes) {
  gsub("\n", "", jsonlite::base64_enc(bytes), fixed = TRUE)
}

#' Make a JPEG data URL
#'
#' @param bytes A raw vector of JPEG bytes.
#' @return A string `"data:image/jpeg;base64,..."`.
#' @noRd
data_url <- function(bytes) {
  paste0("data:image/jpeg;base64,", base64(bytes))
}

#' Make a SystemOne image asset
#'
#' @param bytes A raw vector of JPEG bytes.
#' @return A list with `type`, `format` and `data_base64`.
#' @noRd
image_asset <- function(bytes) {
  list(type = "image", format = "jpg", data_base64 = base64(bytes))
}

#' Make an OpenAI text part
#'
#' @param text One string.
#' @return A list with `type = "input_text"` and `text`.
#' @noRd
input_text <- function(text) {
  list(type = "input_text", text = text)
}

#' Make an OpenAI image part
#'
#' @param bytes A raw vector of JPEG bytes.
#' @return A list with `type = "input_image"` and a data URL in `image_url`.
#' @noRd
input_image <- function(bytes) {
  list(type = "input_image", image_url = data_url(bytes))
}
