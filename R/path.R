# The path file of decide(): a JSON file that keeps the finished answers of a
# run, so that a run that stops can continue without paying twice (D169, as
# the state file of ellmer::batch_chat()).

#' Make the hash of the settings of a run
#'
#' @param decider A decider.
#' @param questions The named list of questions.
#' @param references The prepared reference images (a named list of lists of
#'   raw vectors), or `NULL`.
#' @param settings A list with the image settings `max_size`, `upscale` and
#'   `crop` of `decide()`.
#' @return One string: the `rlang::hash()` of the provider, the server root,
#'   the model, the request format, the image format, the questions (type,
#'   instructions, answers and descriptions), the prepared reference bytes
#'   and the image settings. The key and the `credentials` function are not
#'   part of it.
#' @details A crop function enters the hash through its deparsed body, so a
#'   change in a variable that the function reads is not seen. Numbers enter
#'   as doubles, so that `768L` and `768` give the same hash.
#' @noRd
run_hash <- function(decider, questions, references, settings) {
  if (is.function(settings$crop)) {
    settings$crop <- deparse(body(settings$crop))
  }
  rlang::hash(list(
    decider = c(decider@provider, decider@base_url, decider@model,
                decider@format, decider@image_format),
    questions = purrr::map(questions, \(x) {
      list(question_type(x), x@instructions, x@answers)
    }),
    references = references,
    settings = purrr::map(settings, \(x) if (is.numeric(x)) as.double(x) else x)
  ))
}

#' Read the finished answers of a path file
#'
#' @param path The path of the JSON file.
#' @param hash The hash of the run, from `run_hash()`.
#' @param ignore_hash `TRUE` to keep the answers of a file whose hash differs
#'   from `hash`.
#' @return A named list of results, as in `read_result()`, keyed by the hash
#'   of each prepared input; an empty list when the file does not exist.
#' @details It stops before any request when `path` is not one string, when
#'   its folder does not exist (the file could not be written after the first
#'   chunk), or when the hash of the file differs from `hash` and
#'   `ignore_hash` is `FALSE`. With `ignore_hash = TRUE`, a different hash
#'   gives a warning, as in `ellmer::batch_chat()`.
#' @noRd
read_path <- function(path, hash, ignore_hash) {
  if (!rlang::is_string(path) || !dir.exists(dirname(path))) {
    cli::cli_abort("{.arg path} must be one file in a folder that exists.")
  }
  if (!rlang::is_bool(ignore_hash)) {
    cli::cli_abort("{.arg ignore_hash} must be {.code TRUE} or {.code FALSE}.")
  }
  if (!file.exists(path)) {
    return(list())
  }
  state <- jsonlite::read_json(path)
  if (!identical(state$hash, hash)) {
    problem <- c(
      "The hash in {.path {path}} does not match the hash of this run.",
      i = paste(
        "The model, the questions, the references or the image settings",
        "changed since the file was written."
      )
    )
    if (!ignore_hash) {
      cli::cli_abort(c(problem, i = paste(
        "Use a new {.arg path}, or set {.code ignore_hash = TRUE} to keep",
        "the answers of the file."
      )))
    }
    cli::cli_warn(c(problem, i = paste(
      "{.code ignore_hash = TRUE}: {.fn decide} keeps the answers of the",
      "file and sends only the other inputs."
    )))
  }
  purrr::map(state$done, \(x) list(
    answers = x$answers,
    model = x$model,
    input_tokens = x$input_tokens %||% NA_real_,
    cost = x$cost %||% NA_real_,
    seconds = x$seconds %||% NA_real_,
    error = NA_character_
  ))
}

#' Write the finished answers to a path file
#'
#' @param path The path of the JSON file.
#' @param hash The hash of the run, from `run_hash()`.
#' @param done A named list of results with no error, keyed by the hash of
#'   each prepared input.
#' @return `NULL`, invisibly.
#' @details The file holds `version` (1), `hash` and `done`: for each input,
#'   its answers (with the probabilities as an object keyed by answer),
#'   `model`, `input_tokens`, `cost` and `seconds`. It holds no key and no
#'   input. Numbers have 17 significant digits, so each double reads back
#'   exactly; `NA` becomes `null`.
#'
#'   The function writes a temporary file in the same folder, then renames
#'   it to `path`, so that a crash during a write leaves the previous file
#'   whole. When the rename fails (for example, while a sync program holds
#'   the file), R gives a warning and the next write tries again with all
#'   the answers.
#' @noRd
write_path <- function(path, hash, done) {
  done <- purrr::map(done, \(x) list(
    answers = purrr::map(x$answers, \(answer) {
      purrr::modify_at(answer, "probabilities", as.list)
    }),
    model = x$model,
    input_tokens = x$input_tokens,
    cost = x$cost,
    seconds = x$seconds
  ))
  # An empty list must be written as {}, not []
  names(done) <- names(done) %||% character()
  temporary <- tempfile(tmpdir = dirname(path), fileext = ".json")
  jsonlite::write_json(
    list(version = 1, hash = hash, done = done), temporary,
    auto_unbox = TRUE, digits = I(17), na = "null"
  )
  if (!file.rename(temporary, path)) {
    unlink(temporary)
  }
  invisible()
}

#' Send the inputs that a path file does not hold, in chunks
#'
#' @param inputs A list with one prepared input per input of `decide()`:
#'   a list with `text` and `image` (raw JPEG bytes), each possibly `NULL`.
#' @param build A function that turns one prepared input into a request.
#' @param read A function that turns a list of responses and their requests
#'   into results, as `read_result()` does.
#' @param path The path of the JSON file.
#' @param hash The hash of the run, from `run_hash()`.
#' @param saved The results of the file, from `read_path()`.
#' @param max_active The largest number of requests at the same time.
#' @return A list of results, one per input, in input order.
#' @details Each input is keyed by the `rlang::hash()` of its prepared form,
#'   so identical inputs share one request and one entry. The inputs that
#'   are not in the file go out in chunks of `4 * max_active`; after each
#'   chunk, its finished results are added to the file. Results with an
#'   error are not written, so a new run sends them again. After an
#'   interrupt (Esc), no further chunk is sent, and each input that was not
#'   sent gets the row error of a request that did not finish.
#' @noRd
send_with_path <- function(inputs, build, read, path, hash, saved,
                           max_active) {
  keys <- purrr::map_chr(inputs, rlang::hash)
  todo <- setdiff(keys, names(saved))
  requests <- purrr::map(inputs[match(todo, keys)], build) |>
    rlang::set_names(todo)
  done <- saved
  results <- list()
  for (chunk in split(todo, ceiling(seq_along(todo) / (4 * max_active)))) {
    responses <- perform_requests(requests[chunk], max_active)
    results[chunk] <- read(responses, requests[chunk])
    done <- c(done, purrr::keep(results[chunk], \(x) is.na(x$error)))
    write_path(path, hash, done)
    if (isTRUE(attr(responses, "interrupted"))) break
  }
  unsent <- setdiff(todo, names(results))
  results[unsent] <- read(vector("list", length(unsent)), requests[unsent])
  unname(c(saved, results)[keys])
}
