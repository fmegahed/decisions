# Read a setup file

Reads a JSON file of
[`write_setup()`](https://fmegahed.github.io/decisions/reference/write_setup.md)
and rebuilds the setup.

## Usage

``` r
read_setup(path, credentials = NULL)
```

## Arguments

- path:

  The path of a setup file.

- credentials:

  A function with no arguments that returns the key of the decider.
  `NULL` (the default) reads the environment variable of the provider
  each time
  [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
  sends requests: `TYPESAFE_API_KEY`, `OPENAI_API_KEY`,
  `AZURE_FOUNDRY_API_KEY` or `OPENROUTER_API_KEY`. A
  [`decider_systemone()`](https://fmegahed.github.io/decisions/reference/decider_systemone.md)
  server then gets no key. A setup file holds no key and no credentials
  function.

## Value

A setup, as from
[`decision_setup()`](https://fmegahed.github.io/decisions/reference/decision_setup.md).
The reference images keep the bytes of the file: they are not prepared
again.

## Details

`read_setup()` stops when `version` is not `1`, and checks the questions
and the names of the references as
[`decision_setup()`](https://fmegahed.github.io/decisions/reference/decision_setup.md)
does. It does not check the input type of the model:
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
checks it before any request.

When the decider (provider, server URL, model, request format or image
format), the questions, the references or the image settings of the file
no longer give its `calibrator_hash` (for example, because an agent
edited a description or the model), the calibrator was fitted for other
answers. `read_setup()` then drops it with a warning: fit a new
calibrator on answers of the new setup.

[`unserialize()`](https://rdrr.io/r/base/serialize.html) restores the
calibrator, which is an R object. As with
[`readRDS()`](https://rdrr.io/r/base/readRDS.html), read only setup
files that you trust.

## See also

Other setups:
[`decision_setup()`](https://fmegahed.github.io/decisions/reference/decision_setup.md),
[`write_setup()`](https://fmegahed.github.io/decisions/reference/write_setup.md)

## Examples

``` r
refund <- question_noul("Does the message ask for a refund?")
setup <- decision_setup(decider_typesafe("jev-1.13.0"), list(refund = refund))
path <- tempfile(fileext = ".json")
write_setup(setup, path)
read_setup(path)
#> <decisions::decision_setup>
#> * Model: jev-1.13.0
#> * URL: https://api.typesafe.ai/v1/systemone
#> * Questions: refund (2 answers)
#> * Reference images: 0
#> * Image settings: max_size = 768, upscale = FALSE, crop = "none"
#> * Calibrated: no
# A function can give the key, for example from another variable:
read_setup(path, credentials = \() Sys.getenv("MY_JEV_KEY"))
#> <decisions::decision_setup>
#> * Model: jev-1.13.0
#> * URL: https://api.typesafe.ai/v1/systemone
#> * Questions: refund (2 answers)
#> * Reference images: 0
#> * Image settings: max_size = 768, upscale = FALSE, crop = "none"
#> * Calibrated: no
```
