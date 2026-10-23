---
name: decisions
description: >-
  Use the decisions R package with decision models, which read a text or an image and typed questions and return a probability for each allowed answer. Use when a project calls decide(), score_setup(), evaluate_once(), read_setup(), write_setup(), decision_setup(), question_choice(), question_noul(), question_score(), or a decider such as decider_typesafe(). Covers writing questions, tuning answer descriptions on learning rows, calibration, the one-time test, and sharing a setup file. Do not use for other LLM packages.
---

# decisions

Read the relevant reference below before starting the corresponding task.

- [Writing questions](references/writing-questions.md) - choose a decider, write the instructions and the answer descriptions, and read the output of `decide()`.
- [Tuning descriptions](references/tuning-descriptions.md) - improve the descriptions of a saved setup with `score_setup()` on learning rows. Read it before you change any description.
- [Calibration and evaluation](references/calibration-and-evaluation.md) - fit a calibrator, and run the one-time test with `evaluate_once()`.
- [Sharing a setup](references/sharing-a-setup.md) - save, read and edit the JSON file of a setup.

## What the package does

A decision model reads an input (a text, an image or both) and one or more typed questions. It returns a probability for each allowed answer. The package calls the model, keeps the rows in order, and scores the probabilities.

- A question has instructions and named answers. Each answer has a description. Make a question with `question_noul()`, `question_choice()` or `question_score()`.
- A decider names the provider and the model: `decider_typesafe()`, `decider_openai()`, `decider_foundry()`, `decider_openrouter()` or `decider_systemone()`.
- `decide()` sends the inputs and returns one row per input.
- `decision_setup()` holds the decider, the questions, the reference images, the image settings and, if any, a calibrator. `write_setup()` and `read_setup()` save and read it as one JSON file.
- `score_setup()` returns the ROC AUC of a setup on labeled rows. `evaluate_once()` does the same for the test rows, one time only.

## Working principles

- Ask the person for a call budget before the first paid call. The package has no spending cap. Count the `calls` that `score_setup()` returns. Stop when the total reaches the budget. Then report.
- Use only learning rows to tune. Pass `role` to `score_setup()` on every call.
- Never call `evaluate_once()` until the person says that the descriptions are final.
- Never read, open or list test data or test labels. The package guards stop mistakes. They do not stop an agent that reads files with a shell. Keep to the files that the person names.
- Never print, log or write an API key. The package reads the key from an environment variable. Do not read `.Renviron` or `.env`.
- Keep a log of each attempt, so that a person can review the work.
- Read `.error` before you act on a low score. A row with an error has `NA` answers.
- Report what you did and what you did not check. Do not claim a result that the scores do not show.

## Typical order of work

1. Write the questions and build a setup (`references/writing-questions.md`).
2. Save the setup with `write_setup()`.
3. Score it on the learning rows and tune the descriptions (`references/tuning-descriptions.md`).
4. When the person says the descriptions are final, fit a calibrator if needed, then run the test one time (`references/calibration-and-evaluation.md`).
