# Simulated textile images

Fifty simulated images of a woven textile, 250 x 250 pixels. Half of
them show a flaw in the pattern. Use them to test a decision model on an
image task. The files are in `inst/extdata/textiles/`.

## Usage

``` r
textiles
```

## Format

A tibble with 50 rows and 5 columns:

- file:

  Character. The name of the JPEG file in `inst/extdata/textiles/`. The
  name starts with the folder of the source (`nominal_`, `local_` or
  `global_`), because two source files have the same name.

- class:

  Factor. The truth, with the levels `nominal` and `defective`. Each
  level has 25 images.

- defect_type:

  Factor. `nominal` (no flaw), `local` (a flaw in one place) or `global`
  (a flaw that changes the whole pattern).

- role:

  Character. `reference` (4 images, to show the model what each answer
  looks like) or `input` (46 images, to decide on).

- reference_rank:

  Integer. `1` or `2` for the references, two for each class, and `NA`
  for the inputs.

## Source

Made with the R package spc4sts:

Bui, A. T., & Apley, D. W. (2021). spc4sts: Statistical process control
for stochastic textured surfaces in R. *Journal of Quality Technology,
53*(3), 219-242.
[doi:10.1080/00224065.2019.1707730](https://doi.org/10.1080/00224065.2019.1707730)

The CRAN page of spc4sts, which links its reference manual:
<https://CRAN.R-project.org/package=spc4sts>

The images are shared in the public repository
<https://github.com/fmegahed/qe_genai> (MIT licence). The 4 references
are the images of rank 1 and 2 of each class among the images that the
benchmark of that repository leaves open for training and design. The 46
inputs are 23 images of each class, drawn at random with a fixed seed
from the same open images; none is a reference. No image that the
benchmark keeps for testing is in the data. The script
`data-raw/textiles.R` builds the data.

## Examples

``` r
table(textiles$role, textiles$class)
#>            
#>             nominal defective
#>   input          23        23
#>   reference       2         2
paths <- file.path(
  system.file("extdata", "textiles", package = "decisions"), textiles$file
)
file.exists(paths[1])
#> [1] TRUE
```
