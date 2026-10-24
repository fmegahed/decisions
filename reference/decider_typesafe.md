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

  A function with no arguments that returns the key, for example to read
  it from a secret store. `NULL` (the default) reads the environment
  variable `TYPESAFE_API_KEY` each time [`decide()`](decide.md) sends
  requests.

- input:

  The input type that the model reads: `"text"`, `"image"` or
  `"text+image"`. `NULL` (the default) takes it from the internal table
  of input types; a model that is not in the table is not checked.
  [`decide()`](decide.md) stops before any request when an input does
  not fit.

## Value

A decider object for [`decide()`](decide.md). It holds no key.

## Details

Image input is experimental: TypeSafe reads images only with the header
`TypeSafe-Danger-Zone-Images: true`, which [`decide()`](decide.md) sends
whenever a request carries an image. TypeSafe does not report a cost, so
`.cost` is `NA` in the output of [`decide()`](decide.md). On 2026-10-23,
TypeSafe refused images under 280 pixels on the longest side. So use
`upscale = TRUE` for small images (see
[`vignette("images")`](../articles/images.md)).

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
