#' decisions: Typed Decisions from Decision Models
#'
#' Calls decision models. A decision model reads an input and a typed
#' question. It returns a probability for each allowed answer.
#'
#' @section Start here:
#' 1. Make a decider: [decider_typesafe()], [decider_openai()],
#'    [decider_foundry()], [decider_openrouter()] or [decider_systemone()].
#'    Each help page says how to get a key and where to put it.
#' 2. Make a question: [question_noul()], [question_choice()] or
#'    [question_score()].
#' 3. Call [decide()].
#'
#' `vignette("getting-started")` shows these steps with saved results.
#'
#' @section Output:
#' [decide()] returns a tibble with one row for each input, a `.pred_class`
#' column and one `.pred_` column for each allowed answer. A failed call keeps
#' its row, with `NA` answers and the reason in `.error`.
#'
#' @section Links:
#' * Source and bug reports: <https://github.com/fmegahed/decisions>
#' * Website: <https://fmegahed.github.io/decisions/>
#'
#' @keywords internal
"_PACKAGE"

#' @importFrom rlang %||%
NULL
