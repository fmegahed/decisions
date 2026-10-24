# Ask a question with named choices

Ask a question with named choices

## Usage

``` r
question_choice(instructions, choices)
```

## Arguments

- instructions:

  A string: the question to decide.

- choices:

  A named character vector with at least 2 unique names. Each name is an
  allowed answer (it can contain spaces, such as `"not sure"`). Each
  value describes the answer. In the output of [`decide()`](decide.md),
  the probability column of an answer has a syntactic name
  (`.pred_not_sure` for `"not sure"`), so two names that give the same
  column (`"not sure"` and `"not_sure"`) are refused.

## Value

A `question_choice` object with the properties `instructions` and
`answers`.

## Examples

``` r
question_choice(
  "Which describes the part?",
  c(normal = "A clean part.", defective = "A visible defect.")
)
#> <decisions::question_choice> Which describes the part?
#> * normal: A clean part.
#> * defective: A visible defect.
```
