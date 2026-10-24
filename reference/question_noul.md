# Ask a question with true or false as the answer

A noul question has two answers, `true` and `false`. The model returns a
probability for each.

## Usage

``` r
question_noul(instructions, true = NULL, false = NULL)
```

## Arguments

- instructions:

  A string: the statement or question to decide.

- true, false:

  Optional strings that describe the answers `true` and `false`: each is
  one string, or `NULL` (the default) or `NA` for no description.

## Value

A `question_noul` object with the properties `instructions` and
`answers`.

## See also

[`question_choice()`](https://fmegahed.github.io/decisions/reference/question_choice.md)
for more than two answers,
[`question_score()`](https://fmegahed.github.io/decisions/reference/question_score.md)
for ordered levels, and
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
to ask the question.

Other questions:
[`question_choice()`](https://fmegahed.github.io/decisions/reference/question_choice.md),
[`question_score()`](https://fmegahed.github.io/decisions/reference/question_score.md)

## Examples

``` r
question_noul("Is the surface wet?")
#> <decisions::question_noul> Is the surface wet?
#> * true
#> * false
question_noul("Is the surface wet?", true = "Liquid is visible.")
#> <decisions::question_noul> Is the surface wet?
#> * true: Liquid is visible.
#> * false
```
