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
#' Gives the name that `janitor::make_clean_names(case = "none")` gives
#' (janitor 2.2.1, D190), without janitor. The steps, in janitor's order:
#' 1. Remove quotes (`'` and `"`); `%` becomes `_percent_` and `#` becomes
#'    `_number_`.
#' 2. Write the name in ASCII letters with the transliterators of janitor
#'    (an accented "cafe" gives `"cafe"`, the Cyrillic word for "yes" gives
#'    `"da"`, a superscript 2 gives `"2"`).
#' 3. Change each run of other characters (`.` too) to one `_`, and trim
#'    `_` at both ends.
#' 4. Put `X` before a leading digit, and give `"X"` for an empty name.
#'
#' The case stays. For example, `"not sure"` gives `"not_sure"`, `"50%"`
#' gives `"X50_percent"` and `"1st check"` gives `"X1st_check"`. janitor adds
#' `_2`, `_3`, ... to duplicates; the package refuses them instead.
#'
#' @param x A character vector.
#' @return A character vector of the same length, with no empty name.
#' @noRd
clean_name <- function(x) {
  x <- gsub("['\"]", "", enc2utf8(x))
  x <- gsub("%", "_percent_", x, fixed = TRUE)
  x <- gsub("#", "_number_", x, fixed = TRUE)
  x <- stringi::stri_trans_general(
    x, "Any-Latin;Greek-Latin;Any-NFKD;Any-NFC;Latin-ASCII"
  )
  x <- gsub("^_+|_+$", "", gsub("[^A-Za-z0-9]+", "_", x, perl = TRUE))
  x <- sub("^([0-9])", "X\\1", x, perl = TRUE)
  x[!nzchar(x)] <- "X"
  x
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
  cat("<", class(x)[1], "> ", x@instructions, "\n", sep = "")
  text <- ifelse(is.na(x@answers), "", paste0(": ", x@answers))
  cat(paste0("* ", names(x@answers), text), sep = "\n")
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
#'   `false`: each is one string, or `NULL` (the default) or `NA` for no
#'   description.
#' @return A `question_noul` object with the properties `instructions` and
#'   `answers`.
#' @examples
#' question_noul("Is the surface wet?")
#' question_noul("Is the surface wet?", true = "Liquid is visible.")
#' @family questions
#' @seealso [question_choice()] for more than two answers, [question_score()] for ordered levels, and [decide()] to ask the question.
#' @export
question_noul <- S7::new_class(
  "question_noul",
  parent = question,
  constructor = function(instructions, true = NULL, false = NULL) {
    one_text <- \(x) {
      is.null(x) || (length(x) == 1 && (is.character(x) || is.na(x)))
    }
    if (!one_text(true) || !one_text(false)) {
      cli::cli_abort(
        "{.arg true} and {.arg false} must each be {.code NULL} or one string."
      )
    }
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
#' @family questions
#' @seealso [question_noul()] for true or false, [question_score()] for ordered levels, and [decide()] to ask the question.
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
#' @family questions
#' @seealso [question_noul()] for true or false, [question_choice()] for unordered choices, and [decide()] to ask the question.
#' @export
question_score <- S7::new_class(
  "question_score",
  parent = question,
  constructor = function(instructions, levels) {
    S7::new_object(question(instructions = instructions, answers = levels))
  }
)
