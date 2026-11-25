# Use the Gemini Decisions API

Makes a decider for a model of the Decisions API of Google Gemini
(`https://generativelanguage.googleapis.com`).

## Usage

``` r
decider_gemini(model = NULL, credentials = NULL, input = NULL)
```

## Arguments

- model:

  The model name. `NULL` (the default) uses `"gemini-decision-1"` and
  prints a message that names it.

- credentials:

  A function with no arguments that returns the key. `NULL` (the
  default) reads the environment variable `GEMINI_API_KEY` each time
  [`decide()`](https://fmegahed.github.io/decisions/dev/reference/decide.md)
  sends requests. You generally should not need this argument. Set
  `GEMINI_API_KEY` instead. The best place to set it is `.Renviron`.
  Open that file with `usethis::edit_r_environ()`. The usethis package
  is optional: you can also edit `.Renviron` by hand. Give a function
  for more control, for example to read the key from a secret store. The
  decider keeps the function, not the key.

- input:

  The input type that the model reads: `"text"`, `"image"` or
  `"text+image"`. `NULL` (the default) takes it from the internal table
  of input types; a model that is not in the table is not checked.
  [`decide()`](https://fmegahed.github.io/decisions/dev/reference/decide.md)
  stops before any request when an input does not fit.

## Value

A decider object for
[`decide()`](https://fmegahed.github.io/decisions/dev/reference/decide.md).
It holds no key.

## Details

You need a Gemini API key. Make one in [Google AI
Studio](https://aistudio.google.com). Then set the environment variable
`GEMINI_API_KEY`.

The Decisions API of Gemini is in beta (the requests go to
`/v1beta/decisions`), so Google can change it. The key goes in the
header `x-goog-api-key`. Gemini clamps the probability of a noul answer
to 0.01 to 0.99, and it reports no cost, so `.cost` is `NA` in the
output of
[`decide()`](https://fmegahed.github.io/decisions/dev/reference/decide.md).

Gemini questions take text only, so the reference images go in the input
of the request, before the image to inspect.
[`decide()`](https://fmegahed.github.io/decisions/dev/reference/decide.md)
checks the limits of Gemini before it sends a request: a question name
matches `[A-Za-z0-9_-]` and has 1 to 64 characters; a choice or a score
has 2 to 255 answers; an answer name has at most 128 characters and no
space at its start or end.

## See also

Other deciders:
[`decider_foundry()`](https://fmegahed.github.io/decisions/dev/reference/decider_foundry.md),
[`decider_openai()`](https://fmegahed.github.io/decisions/dev/reference/decider_openai.md),
[`decider_openrouter()`](https://fmegahed.github.io/decisions/dev/reference/decider_openrouter.md),
[`decider_systemone()`](https://fmegahed.github.io/decisions/dev/reference/decider_systemone.md),
[`decider_typesafe()`](https://fmegahed.github.io/decisions/dev/reference/decider_typesafe.md),
[`decider_venn()`](https://fmegahed.github.io/decisions/dev/reference/decider_venn.md)

## Examples

``` r
decider_gemini("gemini-decision-1")
#> <decider> Google Gemini
#> * Model: gemini-decision-1
#> * URL: https://generativelanguage.googleapis.com/v1beta/decisions
#> * Request format: gemini
#> * Input: text+image
```
