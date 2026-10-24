# Save a setup as one JSON file

Writes a setup to one JSON file that R code, a Shiny app and an agent
can share. The file holds no key. An agent can edit the descriptions as
text, and git shows the changes.

## Usage

``` r
write_setup(setup, path)
```

## Arguments

- setup:

  A setup from [`decision_setup()`](decision_setup.md) or
  [`read_setup()`](read_setup.md).

- path:

  The path of the JSON file, in a folder that exists. An existing file
  is replaced.

## Value

`path`, invisibly.

## Details

The file holds one JSON object, indented with two spaces:

- `version`: `1`, the version of the layout.

- `decider`: `provider`, `base_url`, `model`, `format`, `image_format`
  (`null` for OpenAI and OpenRouter) and `input` (`null` when the input
  type is not checked). It holds no key and no credentials function:
  [`read_setup()`](read_setup.md) gives the decider its credentials.

- `questions`: an object keyed by question name, in order. Each question
  has `type` (`"noul"`, `"choice"` or `"score"`), `instructions` and
  `answers`: an object keyed by answer, in order, whose values are the
  descriptions (`null` for none).

- `references`: `null`, or an object keyed by answer whose values are
  arrays of the prepared JPEG images, each in base64 on one line.

- `image_settings`: `max_size` (`null` to keep the size), `upscale` and
  `crop` (`"none"`, `"center"` or a box `[x, y, width, height]`).

- `calibrator`: `null`, or the calibrator as base64 of
  [`serialize()`](https://rdrr.io/r/base/serialize.html).

- `calibrator_hash`: `null`, or the hash of all that changes the answers
  of the model when the calibrator was stored: the decider (provider,
  server URL, model, request format and image format), the questions,
  the references and the image settings. It is the hash of a `path` file
  of [`decide()`](decide.md) (see [`read_setup()`](read_setup.md)).

A crop function cannot be saved: give `crop` as `"none"`, `"center"` or
a box.

The file goes to a temporary file in the same folder first, which then
replaces `path`, so a crash during the write leaves the previous file
whole.

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
```
