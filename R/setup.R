# Setups: one complete decision (the decider, the questions, the reference
# images, the image settings and a calibrator) that R code, a Shiny app and
# an agent share as one JSON file (D147, D172, D173).

#' Check the calibrator of a setup
#'
#' The validator of `setup_class`. S7 runs it when a setup is made and when a
#' property is set.
#'
#' @param self A setup object.
#' @return `NULL` when the setup is valid, or one text that says what is
#'   wrong: a calibrator with two or more questions, or a calibrator that is
#'   not a probably classification calibrator (class `cal_binary` or
#'   `cal_multi`) that maps each answer of the question to its `.pred_`
#'   column.
#' @details probably maps the levels of the truth to the probability
#'   columns. A calibrator that maps an answer to the column of another
#'   answer would swap the probabilities, and a calibrator that reads columns
#'   that the output of `decide()` does not have would fail after the
#'   requests. The levels can be in any order.
#' @noRd
validate_setup <- function(self) {
  calibrator <- self@calibrator
  if (is.null(calibrator)) {
    return(NULL)
  }
  if (length(self@questions) > 1) {
    return("A calibrator works with one question only.")
  }
  answers <- names(self@questions[[1]]@answers)
  columns <- rlang::set_names(paste0(".pred_", clean_name(answers)), answers)
  fitted <- if (inherits(calibrator, c("cal_binary", "cal_multi"))) {
    purrr::map_chr(calibrator$levels, rlang::as_string)
  }
  if (length(fitted) != length(answers) ||
      !identical(fitted[answers], columns)) {
    return(paste0(
      "`calibrator` must be a probably calibrator of the columns ",
      paste0("`", columns, "`", collapse = ", "),
      ", with the answers as the levels of the truth."
    ))
  }
  NULL
}

#' The class of setups
#'
#' @param decider A decider.
#' @param questions A named list of questions, as from `as_questions()`.
#' @param references `NULL`, or the prepared reference images: a named list
#'   in which each name is an answer and each element is a list of raw
#'   vectors of JPEG bytes.
#' @param max_size,upscale,crop The image settings of `decide()`.
#' @param calibrator `NULL`, or a probably calibrator.
#' @return A setup object.
#' @noRd
setup_class <- S7::new_class(
  "decision_setup",
  properties = list(
    decider = decider_class,
    questions = S7::class_list,
    references = S7::new_union(NULL, S7::class_list),
    max_size = S7::new_union(NULL, S7::class_numeric),
    upscale = S7::class_logical,
    crop = S7::new_union(
      S7::class_character, S7::class_numeric, S7::class_function
    ),
    calibrator = S7::class_any
  ),
  validator = validate_setup
)

#' Print a setup
#'
#' Shows the model and its URL, the questions with their number of answers,
#' the number of reference images, the image settings and whether the setup
#' has a calibrator. It never calls or shows `credentials`, so no key
#' appears.
#'
#' @param x A setup.
#' @param ... Not used.
#' @return `x`, invisibly.
#' @noRd
print_setup <- function(x, ...) {
  questions <- purrr::imap_chr(x@questions, \(question, name) {
    paste0(name, " (", length(question@answers), " answers)")
  })
  crop <- if (is.function(x@crop)) "a function" else deparse(x@crop)
  cat(
    paste0("<", class(x)[1], ">"),
    paste0("* Model: ", x@decider@model),
    paste0("* URL: ", decider_url(x@decider)),
    paste0("* Questions: ", paste(questions, collapse = ", ")),
    paste0("* Reference images: ", sum(lengths(x@references))),
    paste0(
      "* Image settings: max_size = ", deparse(x@max_size),
      ", upscale = ", x@upscale, ", crop = ", crop
    ),
    paste0("* Calibrated: ", if (is.null(x@calibrator)) "no" else "yes"),
    sep = "\n"
  )
  invisible(x)
}

S7::method(print, setup_class) <- print_setup

#' Make a setup: one complete decision
#'
#' A setup holds one complete decision: the decider, the questions, the
#' reference images, the image settings and, if you want, a calibrator.
#' `decide()` takes a setup in place of `decider` and `questions`.
#' `write_setup()` saves it as one JSON file that R code, a Shiny app and an
#' agent can share, and `read_setup()` reads it.
#'
#' @param decider A decider from `decider_typesafe()`, `decider_openai()`,
#'   `decider_foundry()`, `decider_openrouter()` or `decider_systemone()`.
#' @param questions One question from `question_noul()`, `question_choice()`
#'   or `question_score()`, or a named list of questions, as in `decide()`.
#' @param references Reference images for the answers, or `NULL` (the
#'   default), as in `decide()`: a named list in which each name is an
#'   allowed answer of the question and each element holds the images of
#'   that answer (paths, URLs or magick images). This release takes
#'   references with one question only.
#' @param max_size,upscale,crop The image settings, as in `decide()`. They
#'   apply to the references now and to the inputs of `decide()`. A crop
#'   function works in R, but `write_setup()` cannot save it.
#' @param calibrator `NULL` (the default), or a probably calibrator, for
#'   example from `probably::cal_estimate_isotonic()`, fitted on the output
#'   of `decide()` for this question: its truth is a factor whose levels are
#'   the answers, and its estimates are the `.pred_` columns of the answers.
#'   A setup with a calibrator has one question. `decide()` applies the
#'   calibrator (see the value of `decide()`).
#' @return A setup: an S7 object of class `decision_setup` with the
#'   properties `decider`, `questions` (a named list), `references` (the
#'   prepared JPEG bytes, or `NULL`), `max_size`, `upscale`, `crop` and
#'   `calibrator`. It holds no key.
#' @details `decision_setup()` prepares each reference image once, with the
#'   image settings of the setup (and with three color channels for
#'   `decider_systemone(image_format = "images")`), and keeps its JPEG bytes.
#'   So `decide()`, the file of `write_setup()` and `read_setup()` use the
#'   same bytes, and a run with `path` has the same hash whether it starts
#'   from a setup or from its pieces.
#'
#'   A model that reads only text cannot take references: the setup stops
#'   with an error before it reads the images.
#' @examples
#' refund <- question_noul("Does the message ask for a refund?")
#' setup <- decision_setup(decider_typesafe("jev-1.13.0"), list(refund = refund))
#' setup
#' @export
decision_setup <- function(decider, questions, references = NULL,
                           max_size = 768, upscale = FALSE, crop = "none",
                           calibrator = NULL) {
  if (!S7::S7_inherits(decider, decider_class)) {
    cli::cli_abort(
      "{.arg decider} must come from a {.code decider_*()} function."
    )
  }
  questions <- as_questions(questions)
  references <- as_references(references, questions)
  # The settings and the calibrator are checked before the images are read
  setup <- setup_class(
    decider = decider, questions = questions, references = NULL,
    max_size = max_size, upscale = upscale, crop = crop,
    calibrator = calibrator
  )
  if (!is.null(references)) {
    check_input_type(decider, text = FALSE, image = TRUE)
    setup@references <- purrr::map(references, \(images) {
      purrr::map(images, \(image) prepare_setup_image(setup, image))
    })
  }
  setup
}

#' Prepare an image with the settings of a setup
#'
#' @param setup A setup.
#' @param image A file path, a URL or a magick image.
#' @return The JPEG bytes of `prepare_image()` with the image settings of the
#'   setup and, for `decider_systemone(image_format = "images")`, three color
#'   channels.
#' @noRd
prepare_setup_image <- function(setup, image) {
  prepare_image(
    image, max_size = setup@max_size, upscale = setup@upscale,
    crop = setup@crop, rgb = setup@decider@format == "systemone_images"
  )
}

#' Save a setup as one JSON file
#'
#' Writes a setup to one JSON file that R code, a Shiny app and an agent can
#' share. The file holds no key. An agent can edit the descriptions as text,
#' and git shows the changes.
#'
#' @param setup A setup from `decision_setup()` or `read_setup()`.
#' @param path The path of the JSON file, in a folder that exists. An
#'   existing file is replaced.
#' @return `path`, invisibly.
#' @details The file holds one JSON object, indented with two spaces:
#'   * `version`: `1`, the version of the layout.
#'   * `decider`: `provider`, `base_url`, `model`, `format`, `image_format`
#'     (`null` for OpenAI and OpenRouter) and `input` (`null` when the input
#'     type is not checked). It holds no key and no credentials function:
#'     `read_setup()` gives the decider its credentials.
#'   * `questions`: an object keyed by question name, in order. Each
#'     question has `type` (`"noul"`, `"choice"` or `"score"`),
#'     `instructions` and `answers`: an object keyed by answer, in order,
#'     whose values are the descriptions (`null` for none).
#'   * `references`: `null`, or an object keyed by answer whose values are
#'     arrays of the prepared JPEG images, each in base64 on one line.
#'   * `image_settings`: `max_size` (`null` to keep the size), `upscale` and
#'     `crop` (`"none"`, `"center"` or a box `[x, y, width, height]`).
#'   * `calibrator`: `null`, or the calibrator as base64 of `serialize()`.
#'   * `calibrator_hash`: `null`, or the hash of all that changes the
#'     answers of the model when the calibrator was stored: the decider
#'     (provider, server URL, model, request format and image format), the
#'     questions, the references and the image settings. It is the hash of
#'     a `path` file of `decide()` (see `read_setup()`).
#'
#'   A crop function cannot be saved: give `crop` as `"none"`, `"center"` or
#'   a box.
#'
#'   The file goes to a temporary file in the same folder first, which then
#'   replaces `path`, so a crash during the write leaves the previous file
#'   whole.
#' @examples
#' refund <- question_noul("Does the message ask for a refund?")
#' setup <- decision_setup(decider_typesafe("jev-1.13.0"), list(refund = refund))
#' path <- tempfile(fileext = ".json")
#' write_setup(setup, path)
#' read_setup(path)
#' @export
write_setup <- function(setup, path) {
  if (!S7::S7_inherits(setup, setup_class)) {
    cli::cli_abort(
      "{.arg setup} must come from {.fn decision_setup} or {.fn read_setup}."
    )
  }
  if (!rlang::is_string(path) || !dir.exists(dirname(path))) {
    cli::cli_abort("{.arg path} must be one file in a folder that exists.")
  }
  if (is.function(setup@crop)) {
    cli::cli_abort(c(
      "A setup file cannot hold a function {.arg crop}.",
      i = paste(
        "Give {.arg crop} as {.val none}, {.val center} or a box",
        "{.code c(x, y, width, height)}."
      )
    ))
  }
  decider <- setup@decider
  calibrator <- setup@calibrator
  stored <- !is.null(calibrator)
  json <- list(
    version = 1,
    decider = list(
      provider = decider@provider, base_url = decider@base_url,
      model = decider@model, format = decider@format,
      image_format = decider@image_format, input = decider@input
    ),
    questions = purrr::map(setup@questions, \(question) list(
      type = question_type(question),
      instructions = question@instructions,
      answers = as.list(question@answers)
    )),
    references = if (!is.null(setup@references)) {
      purrr::map(setup@references, \(images) purrr::map(images, base64))
    },
    image_settings = list(
      max_size = setup@max_size, upscale = setup@upscale, crop = setup@crop
    ),
    calibrator = if (stored) base64(serialize(calibrator, NULL)),
    calibrator_hash = if (stored) run_hash(setup)
  )
  if (!write_json_file(json, path, pretty = TRUE, null = "null")) {
    cli::cli_abort(
      "The setup could not be written: {.path {path}} could not be replaced."
    )
  }
  invisible(path)
}

#' Read a setup file
#'
#' Reads a JSON file of `write_setup()` and rebuilds the setup.
#'
#' @param path The path of a setup file.
#' @param credentials A function with no arguments that returns the key of
#'   the decider. `NULL` (the default) reads the environment variable of the
#'   provider each time `decide()` sends requests: `TYPESAFE_API_KEY`,
#'   `OPENAI_API_KEY`, `AZURE_FOUNDRY_API_KEY` or `OPENROUTER_API_KEY`. A
#'   `decider_systemone()` server then gets no key. A setup file holds no key
#'   and no credentials function.
#' @return A setup, as from `decision_setup()`. The reference images keep the
#'   bytes of the file: they are not prepared again.
#' @details `read_setup()` stops when `version` is not `1`, and checks the
#'   questions and the references as `decision_setup()` does.
#'
#'   When the decider (provider, server URL, model, request format or image
#'   format), the questions, the references or the image settings of the
#'   file no longer give its `calibrator_hash` (for example, because an agent
#'   edited a description or the model), the calibrator was fitted for other
#'   answers. `read_setup()` then drops it with a warning: fit a new
#'   calibrator on answers of the new setup.
#'
#'   `unserialize()` restores the calibrator, which is an R object. As with
#'   `readRDS()`, read only setup files that you trust.
#' @examples
#' refund <- question_noul("Does the message ask for a refund?")
#' setup <- decision_setup(decider_typesafe("jev-1.13.0"), list(refund = refund))
#' path <- tempfile(fileext = ".json")
#' write_setup(setup, path)
#' read_setup(path)
#' # A function can give the key, for example from another variable:
#' read_setup(path, credentials = \() Sys.getenv("MY_JEV_KEY"))
#' @export
read_setup <- function(path, credentials = NULL) {
  if (!rlang::is_string(path) || !file.exists(path)) {
    cli::cli_abort("{.arg path} must be one setup file that exists.")
  }
  json <- jsonlite::read_json(path, simplifyVector = TRUE)
  fields <- c("version", "decider", "questions", "image_settings")
  if (!is.list(json) || !all(fields %in% names(json))) {
    cli::cli_abort("{.path {path}} is not a setup file of {.fn write_setup}.")
  }
  version <- json[["version"]]
  if (!identical(version, 1L)) {
    cli::cli_abort(paste(
      "{.path {path}} is a setup file of version {.val {version}}.",
      "This version of decisions reads version 1."
    ))
  }
  decider <- json[["decider"]]
  decider <- new_decider(
    provider = decider[["provider"]], format = decider[["format"]],
    base_url = decider[["base_url"]], model = decider[["model"]],
    input = decider[["input"]], credentials = credentials,
    image_format = decider[["image_format"]] %||% NA_character_
  )
  questions <- as_questions(purrr::map(json[["questions"]], question_from_json))
  references <- json[["references"]]
  if (!is.null(references)) {
    references <- purrr::map(references, \(images) {
      purrr::map(images, jsonlite::base64_dec)
    })
    references <- as_references(references, questions)
  }
  settings <- purrr::map(json[["image_settings"]], \(x) {
    if (is.numeric(x)) as.double(x) else x
  })
  setup <- setup_class(
    decider = decider, questions = questions, references = references,
    max_size = settings[["max_size"]], upscale = settings[["upscale"]],
    crop = settings[["crop"]]
  )
  calibrator <- json[["calibrator"]]
  if (is.null(calibrator)) {
    return(setup)
  }
  if (!identical(json[["calibrator_hash"]], run_hash(setup))) {
    cli::cli_warn(c(
      paste(
        "The model, the questions, the references or the image settings in",
        "{.path {path}} changed after the calibrator was stored, so",
        "{.fn read_setup} dropped the calibrator."
      ),
      i = paste(
        "A calibrator fitted for the old setup does not apply to the new one.",
        "Refit it on answers of the new setup."
      )
    ))
    return(setup)
  }
  setup@calibrator <- unserialize(jsonlite::base64_dec(calibrator))
  setup
}

#' Rebuild a question from a setup file
#'
#' @param x One question of a setup file, as `jsonlite::read_json()` reads
#'   it: a list with `type`, `instructions` and `answers` (the descriptions
#'   keyed by answer, `NULL` for none).
#' @return A question of the type that the file gives.
#' @noRd
question_from_json <- function(x) {
  answers <- purrr::map_chr(x[["answers"]], \(description) {
    description %||% NA_character_
  })
  instructions <- x[["instructions"]]
  type <- x[["type"]]
  switch(type,
    noul = question_noul(
      instructions, true = answers[["true"]], false = answers[["false"]]
    ),
    choice = question_choice(instructions, answers),
    score = question_score(instructions, answers),
    cli::cli_abort("Unknown question type {.val {type}}.")
  )
}

#' Apply the calibrator of a setup to the output of `decide()`
#'
#' @param out The output tibble of `decide()` for one question.
#' @param calibrator A probably calibrator that fits the question (see
#'   `validate_setup()`).
#' @return `out`, in which each row without an `.error` has the calibrated
#'   probabilities of `probably::cal_apply()` in its `.pred_<answer>` columns
#'   and, in `.pred_class`, the answer with the highest calibrated
#'   probability. The rows with an `.error` stay as they are. The columns
#'   keep their order, and `.pred_class` keeps the answers as its levels, in
#'   order.
#' @details The rows with an `.error` are left out of `probably::cal_apply()`
#'   because its multinomial calibrator fails when all rows are `NA`.
#' @noRd
apply_calibrator <- function(out, calibrator) {
  answered <- is.na(out$.error)
  if (any(answered)) {
    calibrated <- probably::cal_apply(
      out[answered, ], calibrator, pred_class = ".pred_class"
    )
    out[answered, ] <- calibrated[names(out)]
  }
  out
}
