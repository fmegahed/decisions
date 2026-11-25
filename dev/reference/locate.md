# Locate a defect in images (experimental)

`locate()` asks TypeSafe where the defect is in each image: a Choice
over 9 tiles of the image with reference crops, then a Box in the two
most likely tiles. These are the steps that passed the Box test of the
study. On the 46 textile inputs of the package, one run of `locate()`
pointed to 14 of the 14 local defects and put a box on 1 of the 23
nominal images
([`vignette("images")`](https://fmegahed.github.io/decisions/dev/articles/images.md),
section "Defect location").

## Usage

``` r
locate(decider, image, defect, references, max_active = 10, rpm = NULL)
```

## Arguments

- decider:

  A decider from
  [`decider_typesafe()`](https://fmegahed.github.io/decisions/dev/reference/decider_typesafe.md)
  with Jev 1.14 or later, for example `decider_typesafe("jev-1.14.0")`
  or `"jev-latest"`.

- image:

  The images: paths, URLs or magick images, as in
  [`decide()`](https://fmegahed.github.io/decisions/dev/reference/decide.md).

- defect:

  One phrase for the defect, with its article, for example
  `"a textile flaw (a small patch where the weave is replaced by noise)"`.

- references:

  A list with `nominal` and `defective`. Each holds one or more images,
  as `image` does (paths, URLs or magick images): parts with no defect,
  and parts with the defect, at about the scale of a tile (half the side
  of an inspected image). `locate()` does not crop them.

- max_active:

  The largest number of requests in progress at the same time. The
  default is `10`.

- rpm:

  The largest number of requests per minute, or `NULL` (the default) for
  no limit. The requests then go out evenly, one each `60 / rpm`
  seconds.

## Value

A tibble with one row for each image, in the input order:

- .pred_defect:

  1 minus the probability of "none" in step 1.

- .box_left, .box_top, .box_right, .box_bottom:

  The box as fractions of the width and the height of the image, with
  the origin at the top left. `NA` when step 1 says "none", and for a
  row with an error.

- .box_confidence:

  The confidence that TypeSafe gives for the box, from 0 to 1. In the
  run of
  [`vignette("images")`](https://fmegahed.github.io/decisions/dev/articles/images.md),
  the two boxes that were not on a local flaw had 0.03 and 0.06, and the
  14 boxes on a local flaw had 0.64 to 0.92.

- .wording:

  The wording of the box: `"generic"` ("the defect") or `"defect"` (the
  phrase of `defect`).

- .input_tokens:

  The input tokens of the requests of the image.

- .cost:

  `NA`: TypeSafe does not report a cost.

- .seconds:

  The time of the requests of the image.

- .error:

  `NA`, or why the row has no answer. The text starts with the step:
  "Step 1" or "Step 2". After an error in step 2, the row keeps
  `.pred_defect` of step 1.

The attribute `requests` is the number of requests sent: one or two for
each image.

## Details

Box is experimental. Only Jev 1.14 and later have it, and TypeSafe can
change it between releases. Check the boxes on images with a known
defect before you use them.

## Steps

1.  One request for each image: a Choice "Which picture shows `defect`?
    Compare it with the examples." over 9 tiles of half the image, with
    50% overlap, and the answer "none". The tiles and the references are
    sent at 560 pixels. The references go in the state, with a note that
    names each of them.

2.  If the answer is not "none", one more request: a Box in each of the
    two most likely tiles (grown by 1.2, sent at 1024 pixels), with two
    wordings: "the defect", and `defect` with its first article changed
    to "the". The answer is the box in the most likely tile, with the
    wording whose two boxes agree more; on a tie, the wording with the
    higher mean confidence.

Each image is enlarged so that its short side is at least 280 pixels,
the smallest size that TypeSafe takes. TypeSafe takes sides of 280 to
1568 pixels, so the long side of an inspected image can be at most 9
times its short side, and that of a reference 5.6 times. `locate()`
stops before any request for a longer image.

## Examples

``` r
if (FALSE) { # \dontrun{
dir <- system.file("extdata", "textiles", package = "decisions")
read <- \(f) magick::image_read(file.path(dir, f))
references <- list(
  nominal = list(
    magick::image_crop(read("nominal_textile_0630.jpg"), "125x125+62+62"),
    magick::image_crop(read("nominal_textile_0731.jpg"), "125x125+62+62")
  ),
  defective = list(
    magick::image_crop(read("local_textile_0199.jpg"), "125x125+56+68")
  )
)
locate(
  decider_typesafe("jev-1.14.0"),
  image = file.path(dir, "local_textile_0319.jpg"),
  defect = paste(
    "a textile flaw (a small patch where the regular diagonal weave is",
    "replaced by fine speckled noise)"
  ),
  references = references
)
} # }
```
