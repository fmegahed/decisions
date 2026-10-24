# decisions 0.0.0.9000

This is the development version.

* Deciders: `decider_typesafe()`, `decider_openai()`, `decider_foundry()`, `decider_openrouter()` and `decider_systemone()`.
* Questions: `question_noul()`, `question_choice()` and `question_score()`.
* `decide()` calls one model for many inputs. It returns a tibble in the tidymodels style, with one row for each input in input order. A failed call keeps its row, with `NA` answers and the reason in `.error`.
* Setups: `decision_setup()`, `write_setup()` and `read_setup()` keep the question, the descriptions, the references and the calibrator in one JSON file.
* Scoring: `score_setup()` scores a setup on labeled rows. `evaluate_once()` runs the one-time test.
* Six vignettes: getting started, images, choosing a model, open models, the study again, and grading with a rubric.
* Four datasets: `ohio_injuries`, `ohio_recalls`, `textiles` and `rubric_answers`.
* An agent skill, in `system.file("skills", "decisions", package = "decisions")`.
