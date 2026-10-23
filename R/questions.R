#' Check the instructions and answers of a question
#'
#' The shared validator of all questions. It stops with an error when a
#' check fails.
#'
#' @param self A question object.
#' @return `NULL`, invisibly, when valid.
#' @noRd
validate_question <- function(self) {
  answers <- self@answers
  nms <- names(answers)
  if (!rlang::is_string(self@instructions) || !nzchar(self@instructions)) {
    cli::cli_abort("{.arg instructions} must be one non-empty string.")
  }
  if (length(answers) < 2) {
    cli::cli_abort("There must be at least 2 answers, not {length(answers)}.")
  }
  if (is.null(nms) || anyNA(nms) || !all(nzchar(nms))) {
    cli::cli_abort("The answers must be named, with a non-empty name for each.")
  }
  if (anyDuplicated(nms) > 0) {
    cli::cli_abort("The names of the answers must be unique.")
  }
  columns <- clean_name(nms)
  if (!all(nzchar(columns))) {
    cli::cli_abort(
      "The answer {.val {nms[!nzchar(columns)]}} gives an empty column name."
    )
  }
  if (anyDuplicated(columns) > 0) {
    shared <- columns[duplicated(columns)][1]
    column <- paste0(".pred_", shared)
    cli::cli_abort(paste(
      "The answers {.val {nms[columns == shared]}} would share the column",
      "{.code {column}}."
    ))
  }
  invisible(NULL)
}

#' Make a syntactic column name from an answer or a question name
#'
#' Cleans a name as `janitor::make_clean_names(case = "none")` does (D190):
#' it writes the name in ASCII letters (an accented "cafe" gives `"cafe"`,
#' the Cyrillic word for "yes" gives `"da"`), replaces each run of characters
#' other than letters, digits, `_` and `.` with `_`, trims `_` at both ends,
#' and puts `X` before a leading digit. The case stays. For example,
#' `"not sure"` gives `"not_sure"` and `"1st check"` gives `"X1st_check"`.
#'
#' @param x A character vector.
#' @return A character vector of the same length. It is `""` for a name with
#'   no letter, digit, `_` or `.`, even after transliteration.
#' @noRd
clean_name <- function(x) {
  x <- stringi::stri_trans_general(x, "Any-Latin;Latin-ASCII")
  x <- gsub("[^A-Za-z0-9_.]+", "_", x, perl = TRUE)
  x <- gsub("^_+|_+$", "", x, perl = TRUE)
  sub("^([0-9])", "X\\1", x, perl = TRUE)
}

#' The parent class of all questions
#'
#' @param instructions A string that tells the model what to decide.
#' @param answers A named character vector: each name is an allowed answer and
#'   each value describes it (`NA` for no description).
#' @return A question object.
#' @noRd
question <- S7::new_class(
  "question",
  properties = list(
    instructions = S7::class_character,
    answers = S7::class_character
  ),
  validator = validate_question
)

#' Print a question
#'
#' @param x A question object.
#' @param ... Not used.
#' @return `x`, invisibly.
#' @noRd
print_question <- function(x, ...) {
  cat("<", class(x)[1], "> ", x@instructions, "
", sep = "")
  text <- ifelse(is.na(x@answers), "", paste0(": ", x@answers))
  cat(paste0("* ", names(x@answers), text), sep = "
")
  invisible(x)
}

S7::method(print, question) <- print_question

#' Ask a question with true or false as the answer
#'
#' A noul question has two answers, `true` and `false`. The model returns a
#' probability for each.
#'
#' @param instructions A string: the statement or question to decide.
#' @param true,false Optional strings that describe the answers `true` and
#'   `false`. `NULL` (the default) gives no description.
#' @return A `question_noul` object with the properties `instructions` and
#'   `answers`.
#' @examples
#' question_noul("Is the surface wet?")
#' question_noul("Is the surface wet?", true = "Liquid is visible.")
#' @export
question_noul <- S7::new_class(
  "question_noul",
  parent = question,
  constructor = function(instructions, true = NULL, false = NULL) {
    S7::new_object(question(
      instructions = instructions,
      answers = c(true = true %||% NA_character_, false = false %||% NA_character_)
    ))
  }
)

#' Ask a question with named choices
#'
#' @param instructions A string: the question to decide.
#' @param choices A named character vector with at least 2 unique names. Each
#'   name is an allowed answer (it can contain spaces, such as `"not sure"`).
#'   Each value describes the answer. In the output of `decide()`, the
#'   probability column of an answer has a syntactic name (`.pred_not_sure`
#'   for `"not sure"`), so two names that give the same column (`"not sure"`
#'   and `"not_sure"`) are refused.
#' @return A `question_choice` object with the properties `instructions` and
#'   `answers`.
#' @examples
#' question_choice(
#'   "Which describes the part?",
#'   c(normal = "A clean part.", defective = "A visible defect.")
#' )
#' @export
question_choice <- S7::new_class(
  "question_choice",
  parent = question,
  constructor = function(instructions, choices) {
    S7::new_object(question(instructions = instructions, answers = choices))
  }
)

#' Ask a question with ordered score levels
#'
#' @param instructions A string: what to score.
#' @param levels A named character vector with at least 2 unique names, in
#'   order from low to high. Each name is an allowed score and each value
#'   describes it. Two names that give the same probability column in the
#'   output of `decide()` are refused (see `question_choice()`).
#' @return A `question_score` object with the properties `instructions` and
#'   `answers`.
#' @examples
#' question_score(
#'   "How severe is the defect?",
#'   c(none = "No defect.", minor = "Small defect.", major = "Large defect.")
#' )
#' @export
question_score <- S7::new_class(
  "question_score",
  parent = question,
  constructor = function(instructions, levels) {
    S7::new_object(question(instructions = instructions, answers = levels))
  }
)
