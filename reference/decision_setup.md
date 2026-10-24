# Make a setup: one complete decision

A setup holds one complete decision: the decider, the questions, the
reference images, the image settings and, if you want, a calibrator.
[`decide()`](decide.md) takes a setup in place of `decider` and
`questions`. [`write_setup()`](write_setup.md) saves it as one JSON file
that R code, a Shiny app and an agent can share, and
[`read_setup()`](read_setup.md) reads it.

## Usage

``` r
decision_setup(
  decider,
  questions,
  references = NULL,
  max_size = 768,
  upscale = FALSE,
  crop = "none",
  calibrator = NULL
)
```

## Arguments

- decider:

  A decider from [`decider_typesafe()`](decider_typesafe.md),
  [`decider_openai()`](decider_openai.md),
  [`decider_foundry()`](decider_foundry.md),
  [`decider_openrouter()`](decider_openrouter.md) or
  [`decider_systemone()`](decider_systemone.md).

- questions:

  One question from [`question_noul()`](question_noul.md),
  [`question_choice()`](question_choice.md) or
  [`question_score()`](question_score.md), or a named list of questions,
  as in [`decide()`](decide.md).

- references:

  Reference images for the answers, or `NULL` (the default), as in
  [`decide()`](decide.md): a named list in which each name is an allowed
  answer of the question and each element holds the images of that
  answer (paths, URLs or magick images). This release takes references
  with one question only.

- max_size, upscale, crop:

  The image settings, as in [`decide()`](decide.md): `max_size` is
  `NULL` or one number of 1 or more, and `upscale` is `TRUE` or `FALSE`.
  They apply to the references now and to the inputs of
  [`decide()`](decide.md). A crop function works in R, but
  [`write_setup()`](write_setup.md) cannot save it.

- calibrator:

  `NULL` (the default), or a probably calibrator, for example from
  [`probably::cal_estimate_isotonic()`](https://probably.tidymodels.org/reference/cal_estimate_isotonic.html),
  fitted on the output of [`decide()`](decide.md) for this question: its
  truth is a factor whose levels are the answers, and its estimates are
  the `.pred_` columns of the answers. A setup with a calibrator has one
  question. [`decide()`](decide.md) applies the calibrator (see the
  value of [`decide()`](decide.md)). To add a calibrator to a setup that
  exists, see Details.

## Value

A setup: an S7 object of class `decision_setup` with the properties
`decider`, `questions` (a named list), `references` (the prepared JPEG
bytes, or `NULL`), `max_size`, `upscale`, `crop` and `calibrator`. It
holds no key.

## Details

`decision_setup()` prepares each reference image once, with the image
settings of the setup (and with three color channels for
`decider_systemone(image_format = "images")`), and keeps its JPEG bytes.
So [`decide()`](decide.md), the file of
[`write_setup()`](write_setup.md) and [`read_setup()`](read_setup.md)
use the same bytes, and a run with `path` has the same hash whether it
starts from a setup or from its pieces.

A model that reads only text cannot take references, and bad image
settings are refused: the setup stops with an error before it reads the
images.

To add a calibrator to a setup that exists, set its property:
`setup@calibrator <- calibrator`. This works for a setup from
`decision_setup()` and for a setup from [`read_setup()`](read_setup.md),
whose references are prepared images that `decision_setup()` cannot take
again. The setup checks the calibrator, as `decision_setup()` does, and
its references, its settings and its run hash do not change. Then
[`write_setup()`](write_setup.md) stores the calibrator with that hash.

## Examples

``` r
refund <- question_noul("Does the message ask for a refund?")
setup <- decision_setup(decider_typesafe("jev-1.13.0"), list(refund = refund))
setup
#> <decisions::decision_setup>
#> * Model: jev-1.13.0
#> * URL: https://api.typesafe.ai/v1/systemone
#> * Questions: refund (2 answers)
#> * Reference images: 0
#> * Image settings: max_size = 768, upscale = FALSE, crop = "none"
#> * Calibrated: no
```
