# decisions (development version)

* `decider_gemini()` calls the Decisions API of Google Gemini
  (`gemini-decision-1`, beta). The reference images go in the input of the
  request, before the image to inspect. `decide()` checks the limits of
  Gemini (question names, 2 to 255 answers, answer names) before it sends a
  request.
* `decider_venn()` calls a local Venn server (venn-vdm, `venn-1`), for a
  text or one image. It needs no key. Venn reports no tokens and no cost, so
  `.input_tokens` and `.cost` are `NA`; its probabilities are not
  calibrated.

# decisions 0.1.1

* decisions installs again with S7 1.0.0. The decider of a setup is now a
  required property, so S7 makes no default for it from the name of its
  class. Nothing else changes for users.

# decisions 0.1.0

* Initial CRAN submission.

* Deciders: `decider_typesafe()`, `decider_openai()`, `decider_foundry()`, `decider_openrouter()` and `decider_systemone()`.
* Questions: `question_noul()`, `question_choice()` and `question_score()`.
* `decide()` calls one model for many inputs. It returns a tibble in the tidymodels style, with one row for each input in input order. A failed call keeps its row, with `NA` answers and the reason in `.error`.
* Setups: `decision_setup()`, `write_setup()` and `read_setup()` keep the question, the descriptions, the references and the calibrator in one JSON file.
* Scoring: `score_setup()` scores a setup on labeled rows. `evaluate_once()` runs the one-time test.
* Six vignettes: getting started, choosing a model, open models, grading with a rubric, images, and the industrial image inspection case study.
* Four datasets: `ohio_injuries`, `ohio_recalls`, `textiles` and `rubric_answers`.
* An agent skill, in `system.file("skills", "decisions", package = "decisions")`.
* Requirements: R 4.3.0 or newer (for `@` on S7 objects), httr2 1.2.0 or newer, and rlang 1.3.0 or newer. rlang 1.3.0 changed the values of `rlang::hash()`, and the `path` files, the run hash and the calibrator hash of a setup use it. With an older rlang, a `path` file or a setup from a newer rlang does not match.
