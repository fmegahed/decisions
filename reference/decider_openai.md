# Use the OpenAI Decisions API

Makes a decider for a model of the OpenAI Decisions API
(`https://api.openai.com`).

## Usage

``` r
decider_openai(model = NULL, credentials = NULL, input = NULL)
```

## Arguments

- model:

  The model name. `NULL` (the default) uses `"gpt-6-luna"` and prints a
  message that names it.

- credentials:

  A function with no arguments that returns the key. `NULL` (the
  default) reads the environment variable `OPENAI_API_KEY` each time
  [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
  sends requests.

- input:

  The input type that the model reads: `"text"`, `"image"` or
  `"text+image"`. `NULL` (the default) takes it from the internal table
  of input types; a model that is not in the table is not checked.
  [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
  stops before any request when an input does not fit.

## Value

A decider object for
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md).
It holds no key.

## Details

OpenAI does not report a cost, so `.cost` is `NA` in the output of
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md).

## Examples

``` r
decider_openai("gpt-6-luna")
#> <decider> OpenAI
#> * Model: gpt-6-luna
#> * URL: https://api.openai.com/v1/decisions
#> * Request format: openai
#> * Input: text+image
```
