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
  [`decide()`](decide.md) are refused (see
  [`question_choice()`](question_choice.md)).

## Value

A `question_score` object with the properties `instructions` and
`answers`.

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
