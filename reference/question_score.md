# Ask a question with ordered score levels

Ask a question with ordered score levels

## Usage

``` r
question_score(instructions, levels)
```

## Arguments

- instructions:

  A string: what to score.

- levels:

  A named character vector with at least 2 unique names, in order from
  low to high. Each name is an allowed score and each value describes
  it. Two names that give the same probability column in the output of
  [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
  are refused (see
  [`question_choice()`](https://fmegahed.github.io/decisions/reference/question_choice.md)).

## Value

A `question_score` object with the properties `instructions` and
`answers`.

## See also

[`question_noul()`](https://fmegahed.github.io/decisions/reference/question_noul.md)
for true or false,
[`question_choice()`](https://fmegahed.github.io/decisions/reference/question_choice.md)
for unordered choices, and
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
to ask the question.

Other questions:
[`question_choice()`](https://fmegahed.github.io/decisions/reference/question_choice.md),
[`question_noul()`](https://fmegahed.github.io/decisions/reference/question_noul.md)

## Examples

``` r
question_score(
  "How severe is the defect?",
  c(none = "No defect.", minor = "Small defect.", major = "Large defect.")
)
#> <decisions::question_score> How severe is the defect?
#> * none: No defect.
#> * minor: Small defect.
#> * major: Large defect.
```
