# Score a setup on labeled rows

Runs [`decide()`](decide.md) with a setup on inputs whose true answers
you know, and scores the probabilities with the area under the ROC
curve. Use it to compare candidate setups (descriptions, instructions,
references) on the learning rows. A person or an agent reads the
`estimate` of each setup and keeps the best.

## Usage

``` r
score_setup(
  setup,
  text = NULL,
  image = NULL,
  truth,
  role = NULL,
  metric = "roc_auc",
  event = NULL,
  path = NULL
)
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

- role:

  `NULL` (the default, no check), or a vector with one value per input:
  `"learning"`, `"calibration"` or `"test"`. `score_setup()` stops
  before any request when a value is `"test"`: score the test rows one
  time, with [`evaluate_once()`](evaluate_once.md).

- metric:

  The metric. This release has `"roc_auc"` only. For another metric,
  compute it from the `answers` column of the result with yardstick.

- event:

  The answer that counts as the event (the positive class) of the AUC.
  `NULL` (the default) gives `"true"` for a noul question and the second
  answer for a question with two answers (for
  `c(normal = ..., defective = ...)`, `"defective"`). With three or more
  answers, `event` is required.

- path:

  `NULL`, or a state file for [`decide()`](decide.md) (see `path` in
  [`decide()`](decide.md)). A new call with the same `path` sends only
  the inputs that the file does not hold.

## Value

A one-row tibble:

- `metric` and `estimate`: the metric and its value. `estimate` is `NA`
  with a warning when fewer than one row of each class remains.

- `n`: the number of rows in the AUC.

- `calls`: the number of requests that this call sent (0 for inputs read
  from `path`).

- `input_tokens`: the sum of the input tokens.

- `cost`: the sum of every cost that the provider reports (rows with an
  error included: the provider billed them), or `NA` when a row that
  used input tokens has no reported cost. It is 0 when no row reports a
  cost or input tokens.

- `seconds`: the sum of the response times.

- `errors`: the number of rows with an `.error` (for example a failed
  call, or an answer with a missing probability). They stay out of the
  AUC.

- `answers`: a list column that holds the output of
  [`decide()`](decide.md).

`input_tokens`, `cost` and `seconds` count every row, also the rows that
come from the `path` file. So a new call with the same `path` can report
tokens and a cost with `calls = 0`.

## Details

The AUC uses the probabilities that [`decide()`](decide.md) returns, so
it is the AUC of the calibrated probabilities when the setup has a
calibrator. It is the Mann-Whitney statistic of the probability of
`event`, with average ranks for ties; it equals
`yardstick::roc_auc_vec(truth, prob, event_level = "second")` when
`event` is the second level of `truth`.

The function checks `setup`, `metric`, `event`, `truth` and `role`
before it sends a request.

## Examples

``` r
if (FALSE) { # \dontrun{
quality <- question_choice("Is the part defective?", c(
  nominal = "A clean part.", defective = "A part with a defect."
))
setup <- decision_setup(decider_typesafe("jev-1.13.0"), list(q = quality))
score_setup(
  setup, text = c("Clean surface.", "Dark streak."),
  truth = c("nominal", "defective"), role = c("learning", "learning")
)
} # }
```
