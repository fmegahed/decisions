# Use any SystemOne server

Makes a decider for a server that speaks SystemOne, for example
Clef-Flash on an SGLang server or Laya on `laya-serve`, often on the
computer of the user.

## Usage

``` r
decider_systemone(
  base_url,
  model,
  image_format = c("assets", "images"),
  credentials = NULL,
  input = NULL
)
```

## Arguments

- base_url:

  The server root, for example `"http://localhost:30000"`. Requests go
  to `<base_url>/v1/systemone`.

- model:

  The model name, for example `"Cloudflare/clef-flash"`, or a Laya
  checkpoint (`"english"`, `"multilingual"`, `"typed-decisions"`).
  Required.

- image_format:

  How the server takes images: `"assets"` (the SystemOne `assets`
  object) or `"images"` (an ordered list of images, as the SGLang server
  of Clef-Flash needs).

- credentials:

  A function with no arguments that returns a key. `NULL` (the default)
  sends no key, as a local server needs none. With a function, the key
  goes in an `Authorization: Bearer` header.

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

With `image_format = "images"`,
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
writes every image with three color channels, because the SGLang server
cannot read a JPEG with one channel.

## Examples

``` r
decider_systemone(
  "http://localhost:30000", "Cloudflare/clef-flash", image_format = "images"
)
#> <decider> The server at http://localhost:30000
#> * Model: Cloudflare/clef-flash
#> * URL: http://localhost:30000/v1/systemone
#> * Request format: systemone_images
#> * Input: text+image
decider_systemone("http://localhost:8000", "typed-decisions")
#> <decider> The server at http://localhost:8000
#> * Model: typed-decisions
#> * URL: http://localhost:8000/v1/systemone
#> * Request format: systemone
#> * Input: text
```
