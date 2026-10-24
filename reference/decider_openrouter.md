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
  [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
  sends requests. You generally should not need this argument. Set
  `OPENROUTER_API_KEY` instead. The best place to set it is `.Renviron`.
  Open that file with `usethis::edit_r_environ()`. The usethis package
  is optional: you can also edit `.Renviron` by hand. Give a function
  for more control, for example to read the key from a secret store. The
  decider keeps the function, not the key.

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

Sign up at <https://openrouter.ai>, then create a key on the [keys
page](https://openrouter.ai/keys). Set the environment variable
`OPENROUTER_API_KEY`.

OpenRouter documents no image field for decisions, so the table of input
types gives every OpenRouter model the input type `"text"`. OpenRouter
reports the cost of each call, and `.cost` holds it.

## See also

Other deciders:
[`decider_foundry()`](https://fmegahed.github.io/decisions/reference/decider_foundry.md),
[`decider_openai()`](https://fmegahed.github.io/decisions/reference/decider_openai.md),
[`decider_systemone()`](https://fmegahed.github.io/decisions/reference/decider_systemone.md),
[`decider_typesafe()`](https://fmegahed.github.io/decisions/reference/decider_typesafe.md)

## Examples

``` r
decider_openrouter("typesafe/jev-1.14")
#> <decider> OpenRouter
#> * Model: typesafe/jev-1.14
#> * URL: https://openrouter.ai/api/alpha/decisions
#> * Request format: openrouter
#> * Input: text
```
