# Tuning descriptions

Use this reference to improve the descriptions of the answers of a saved setup. You change only the texts. You do not change the model, the reference images or the image settings, unless the person asks.

## Before you start

1. Ask the person for a call budget. Write it down. The package has no spending cap.
2. Ask the person for the files you may read: the setup file, the learning inputs and the learning labels. Read only those files.
3. Do not read, list or search test data or test labels. The package guards stop mistakes. For example, `score_setup()` refuses a `role` of `"test"`. The guards do not stop an agent that reads files with a shell. You must not do that.
4. Do not call `evaluate_once()`. The person tells you when the descriptions are final.

## Score a candidate

Read the setup with `read_setup()`. Score it on the learning rows only. Pass `role` with one value per row.

```r
setup <- read_setup("setup.json")
result <- score_setup(
  setup, image = learning$path, truth = learning$truth,
  role = rep("learning", nrow(learning)),
  path = "candidates/001-answers.json"
)
result$estimate
```

- `estimate` is the ROC AUC.
- `calls` is the number of requests that this call sent. Add it to your running total.
- `errors` is the number of rows with an error. Those rows stay out of the AUC.
- `cost` is the cost that the provider reports, or `NA`.
- `answers` holds the output of `decide()`. Look at the rows that are ranked wrongly.
- Use one `path` for each candidate. A `path` file holds answers for one wording only. A reused `path` with a changed description stops with a hash mismatch. This is the correct behavior.

## Rules

- Keep a candidate only when its AUC is at least 0.02 higher than the AUC of the current best. Candidate 1 is the first best.
- Base each change on what the learning examples and the scores show. Look at the inputs that are ranked wrongly. Compare them with the other class.
- Change one idea at a time. Then the log shows what helped.
- Prefer a clear, general description over a long list of special cases.
- Do not aim for an AUC of 1. A small learning set can mislead you.
- Use only learning rows. Pass `role` on every call. The `role` values are labels that you supply, so the guard is a self-check: it cannot know which rows are really test rows. Label each row with care.
- Write each description in plain language about what is visible or written. Do not write instructions about scores or labels.
- Score each candidate once. Do not edit a candidate after you score it. Write a new candidate.
- Stop when the budget is reached, when you have no further idea that you expect to help, or when the person says stop.

## Length

There is no fixed length limit. A long text can help. A provider can refuse a text that is too long. Then `score_setup()` returns rows with an error. Read the error in `.error` in the `answers` column. It holds the text of the provider, the model name and the size of the request. Shorten the descriptions. Then score again.

## Edit a candidate

Edit the descriptions in a copy of the setup file (see `sharing-a-setup.md`), or build the setup again with `decision_setup()`. Keep the best setup file unchanged. Write each candidate to its own file, for example `candidates/002.json`.

## Log each attempt

Write one row for each candidate to `candidates/log.csv`, so that a person can review the work:

- `candidate`: the number.
- `change`: one sentence. What you saw, and what the new text changes.
- `auc`: the `estimate`.
- `calls`: the `calls`.
- `cost`: the `cost`.
- `errors`: the `errors`.
- `kept`: `TRUE` when the candidate passed the 0.02 rule.

Keep a running total of `calls` against the budget.

## Final message

When you stop, report: the candidates that you tried, the AUC of each, the best candidate, the calls used against the budget, and any rows with errors. Say that you did not use test data. Then wait. Do not run `evaluate_once()` until the person says that the descriptions are final.
