#' The input types of the known models
#'
#' One dated row per model of the design (section 3.1). `decide()` uses the
#' table to stop before any request when a model cannot read an input.
#'
#' @format A tibble with the columns:
#'   * `provider`: the provider id of the decider (`"typesafe"`, `"openai"`,
#'     `"openrouter"`, `"foundry"` or `"systemone"`).
#'   * `model`: a regular expression that the model name must match.
#'   * `input`: `"text"`, `"image"` or `"text+image"`.
#'   * `checked`: the date of the check against the provider.
#' @details The facts change (D161): check them again before a release.
#'   TypeSafe reads images only with the header
#'   `TypeSafe-Danger-Zone-Images: true` (experimental). OpenRouter documents
#'   no image field, so every OpenRouter model reads text only. Foundry hosts
#'   Microsoft-Decision-1, which reads text only, under any deployment name.
#'   Laya runs three checkpoints (`english`, `multilingual`,
#'   `typed-decisions`) and reads text only.
#' @noRd
input_types <- tibble::tribble(
  ~provider,    ~model,                    ~input,       ~checked,
  "typesafe",   "^jev-",                   "text+image", as.Date("2026-10-23"),
  "openai",     "^gpt-6-luna$",            "text+image", as.Date("2026-10-23"),
  "openrouter", ".",                       "text",       as.Date("2026-10-23"),
  "foundry",    ".",                       "text",       as.Date("2026-10-23"),
  "systemone",  "^Cloudflare/clef-flash$", "text+image", as.Date("2026-10-23"),
  "systemone",  "^(english|multilingual|typed-decisions)$", "text",
  as.Date("2026-10-23")
)

#' Look up the input type of a model
#'
#' @param provider The provider id of the decider.
#' @param model The model name.
#' @return The `input` of the first row of `input_types` that matches, or
#'   `NA` when no row matches (the input is then not checked).
#' @noRd
lookup_input <- function(provider, model) {
  rows <- input_types[input_types$provider == provider, ]
  hit <- purrr::detect_index(rows$model, \(pattern) grepl(pattern, model))
  if (hit == 0) NA_character_ else rows$input[[hit]]
}
