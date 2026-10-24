# Score the test rows one time

Runs [`decide()`](decide.md) with a setup on the test rows and scores
them as [`score_setup()`](score_setup.md) does, but only once. It writes
the result to `path`, and it refuses to run again while `path` exists,
so the test rows are not tuned against.

## Usage

``` r
evaluate_once(setup, text = NULL, image = NULL, truth, event = NULL, path)
```

## Arguments

- setup:

  A setup from [`decision_setup()`](decision_setup.md) or
  [`read_setup()`](read_setup.md) with one question.

- text, image:

  The inputs, as in [`decide()`](decide.md).

- truth:

  A factor or character vector with the true answer of each input. It
  has the length of the inputs, and its values are answers of the
  question.

- event:

  The answer that counts as the event (the positive class) of the AUC.
  `NULL` (the default) gives `"true"` for a noul question and the second
  answer for a question with two answers (for
  `c(normal = ..., defective = ...)`, `"defective"`). With three or more
  answers, `event` is required.

- path:

  The path of the result file (an `.rds` file in a folder that exists).
  If it exists, `evaluate_once()` stops before any request.

## Value

The one-row tibble of [`score_setup()`](score_setup.md). It is also
written to `path` with
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html) when no row has an
error. While a row has an error, `estimate` is `NA`: the estimate
appears only in the complete result.

## Details

[`decide()`](decide.md) keeps its state in
`paste0(path, ".state.json")`. A run that stops continues from this file
without paying twice, and each test row is scored once. When a row has
an error, `evaluate_once()` returns the row with `estimate = NA`, does
not write `path`, and warns with the failed rows that a new call sends
only them again. So the test rows give one estimate only, and you cannot
tune on them by repeated calls.

A test row can fail at each call, for example with an image that the
provider refuses. Then the estimate cannot appear until that row has an
answer or leaves the test rows. Read the reason in the `.error` column
of `answers`. If a new call cannot fix the row, remove it from the test
rows, call `evaluate_once()` again with the same `path`, and report the
removed row with the result. The state file keeps the other answers, so
they are not sent again.

## Examples

``` r
if (FALSE) { # \dontrun{
evaluate_once(
  setup, text = test_texts, truth = test_truth, path = "test-result.rds"
)
} # }
```
