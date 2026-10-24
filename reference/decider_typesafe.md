# Use Jev through the TypeSafe API

Makes a decider for a Jev model on the TypeSafe API
(`https://api.typesafe.ai`, SystemOne format).

## Usage

``` r
decider_typesafe(model = NULL, credentials = NULL, input = NULL)
```

## Arguments

- model:

  The model name, for example `"jev-1.13.0"`. `NULL` (the default) uses
  `"jev-latest"` and prints a message that names it.

- credentials:

  A function with no arguments that returns the key. `NULL` (the
  default) reads the environment variable `TYPESAFE_API_KEY` each time
  [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
  sends requests. You generally should not need this argument. Set
  `TYPESAFE_API_KEY` instead. The best place to set it is `.Renviron`.
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

You need a TypeSafe API key. Get one in the TypeSafe console
(<https://console.typesafe.ai/>), then set the environment variable
`TYPESAFE_API_KEY`. TypeSafe is at <https://typesafe.ai>.

Image input is experimental: TypeSafe reads images only with the header
`TypeSafe-Danger-Zone-Images: true`, which
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
sends whenever a request carries an image. TypeSafe does not report a
cost, so `.cost` is `NA` in the output of
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md).
On 2026-10-23, TypeSafe refused images under 280 pixels on the longest
side. So use `upscale = TRUE` for small images (see
[`vignette("images")`](https://fmegahed.github.io/decisions/articles/images.md)).

## See also

Other deciders:
[`decider_foundry()`](https://fmegahed.github.io/decisions/reference/decider_foundry.md),
[`decider_openai()`](https://fmegahed.github.io/decisions/reference/decider_openai.md),
[`decider_openrouter()`](https://fmegahed.github.io/decisions/reference/decider_openrouter.md),
[`decider_systemone()`](https://fmegahed.github.io/decisions/reference/decider_systemone.md)

## Examples

``` r
decider_typesafe("jev-1.13.0")
#> <decider> TypeSafe
#> * Model: jev-1.13.0
#> * URL: https://api.typesafe.ai/v1/systemone
#> * Request format: systemone
#> * Input: text+image
# A function can give the key, for example from another variable:
decider_typesafe("jev-1.13.0", credentials = \() Sys.getenv("MY_JEV_KEY"))
#> <decider> TypeSafe
#> * Model: jev-1.13.0
#> * URL: https://api.typesafe.ai/v1/systemone
#> * Request format: systemone
#> * Input: text+image
```
