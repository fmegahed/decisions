# Changelog

## decisions 0.1.0

- Initial CRAN submission.

- Deciders:
  [`decider_typesafe()`](https://fmegahed.github.io/decisions/reference/decider_typesafe.md),
  [`decider_openai()`](https://fmegahed.github.io/decisions/reference/decider_openai.md),
  [`decider_foundry()`](https://fmegahed.github.io/decisions/reference/decider_foundry.md),
  [`decider_openrouter()`](https://fmegahed.github.io/decisions/reference/decider_openrouter.md)
  and
  [`decider_systemone()`](https://fmegahed.github.io/decisions/reference/decider_systemone.md).

- Questions:
  [`question_noul()`](https://fmegahed.github.io/decisions/reference/question_noul.md),
  [`question_choice()`](https://fmegahed.github.io/decisions/reference/question_choice.md)
  and
  [`question_score()`](https://fmegahed.github.io/decisions/reference/question_score.md).

- [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
  calls one model for many inputs. It returns a tibble in the tidymodels
  style, with one row for each input in input order. A failed call keeps
  its row, with `NA` answers and the reason in `.error`.

- Setups:
  [`decision_setup()`](https://fmegahed.github.io/decisions/reference/decision_setup.md),
  [`write_setup()`](https://fmegahed.github.io/decisions/reference/write_setup.md)
  and
  [`read_setup()`](https://fmegahed.github.io/decisions/reference/read_setup.md)
  keep the question, the descriptions, the references and the calibrator
  in one JSON file.

- Scoring:
  [`score_setup()`](https://fmegahed.github.io/decisions/reference/score_setup.md)
  scores a setup on labeled rows.
  [`evaluate_once()`](https://fmegahed.github.io/decisions/reference/evaluate_once.md)
  runs the one-time test.

- Six vignettes: getting started, images, choosing a model, open models,
  the industrial image inspection case study, and grading with a rubric.

- Four datasets: `ohio_injuries`, `ohio_recalls`, `textiles` and
  `rubric_answers`.

- An agent skill, in
  `system.file("skills", "decisions", package = "decisions")`.

- Requirements: R 4.3.0 or newer (for `@` on S7 objects), httr2 1.2.0 or
  newer, and rlang 1.3.0 or newer. rlang 1.3.0 changed the values of
  [`rlang::hash()`](https://rlang.r-lib.org/reference/hash.html), and
  the `path` files, the run hash and the calibrator hash of a setup use
  it. With an older rlang, a `path` file or a setup from a newer rlang
  does not match.
