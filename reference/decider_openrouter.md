# Use a decision model through OpenRouter

Makes a decider for a decision model on OpenRouter
(`https://openrouter.ai`, alpha decisions endpoint), for example Jev or
Microsoft-Decision-1.

## Usage

``` r
decider_openrouter(model, credentials = NULL, input = NULL)
```

## Arguments

- model:

  The OpenRouter model id, for example `"typesafe/jev-1.14"` or
  `"microsoft/microsoft-decision-1"`. Required.

- credentials:

  A function with no arguments that returns the key. `NULL` (the
  default) reads the environment variable `OPENROUTER_API_KEY` each time
  [`decide()`](decide.md) sends requests.

- input:

  The input type that the model reads: `"text"`, `"image"` or
  `"text+image"`. `NULL` (the default) takes it from the internal table
  of input types; a model that is not in the table is not checked.
  [`decide()`](decide.md) stops before any request when an input does
  not fit.

## Value

A decider object for [`decide()`](decide.md). It holds no key.

## Details

OpenRouter documents no image field for decisions, so the table of input
types gives every OpenRouter model the input type `"text"`. OpenRouter
reports the cost of each call, and `.cost` holds it.

## Examples

``` r
decider_openrouter("typesafe/jev-1.14")
#> <decider> OpenRouter
#> * Model: typesafe/jev-1.14
#> * URL: https://openrouter.ai/api/alpha/decisions
#> * Request format: openrouter
#> * Input: text
```
