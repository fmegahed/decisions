# The study again, with the package

``` r

library(decisions)
```

## Overview

Can a decision model find defects in images of manufactured parts when
it sees only a few reference images? And are its probabilities
calibrated, so that a probability of 0.8 means that about 8 of 10 such
parts are defective?

This vignette examines these questions with the package, on five
datasets of industrial images. It repeats the steps of a study of
decision models on these images (the original study; its record is
public at
<https://fmegahed.github.io/decision-models-for-industrial-image-qc/>).
It tunes the descriptions of the answers, chooses the number of
reference images and the image size, fits a calibrator, and saves each
setup for one final test. It uses three models:

- Jev, from TypeSafe, with
  [`decider_typesafe()`](https://fmegahed.github.io/decisions/reference/decider_typesafe.md).
  The version is pinned to `jev-1.14.0`, so a later version of Jev does
  not change the results.
- gpt-6-luna, on the Decisions API of OpenAI, with
  [`decider_openai()`](https://fmegahed.github.io/decisions/reference/decider_openai.md).
- Clef-Flash, from Cloudflare, on a local SGLang server, with
  [`decider_systemone()`](https://fmegahed.github.io/decisions/reference/decider_systemone.md).

The results below come from live calls on 2026-10-23 and 2026-10-24. The
package saved them in `inst/extdata/study_again.rds`, so this vignette
builds without a key, a network or the images. The script
`data-raw/study_again.R` in the source of the package made them. Its
code is the code of this vignette.

## Data

The five datasets come from a published study of image inspection with
CLIP (Megahed et al., 2026). Each image is `nominal` (a good part) or
`defective`.

| Dataset | Images | Nominal | Defective |
|----|----|----|----|
| `extrusion` | Frames of the extrusion profile of a 3D printer | `normal` | `over`, `under` (too much or too little material) |
| `microstructure` | Simulated microstructure images (EBSD) | `Uniform` | `Band`, `Bimodal`, `SingleCrystal`, each at a `low`, `medium` or `high` level |
| `pan_images` | Surfaces of metallic pans | `nominal` | `defective` |
| `pipe_staple` | A pipe staple on a car production line | `good` | `missing` (the staple is missing) |
| `textiles` | Simulated textured surfaces | `nominal` | `local` (a small flaw), `global` (a change of the whole texture) |

The authors of Megahed et al. (2026) recorded the extrusion images and
simulated the microstructure images. The pan images come from Megahed
and Camelio (2012). The authors simulated the textile images with the R
package spc4sts (Bui & Apley, 2021). The pipe staple images come from
the Automotive Visual Inspection Dataset (AutoVI) of Renault (Carvalho
et al., 2024).

### Licences

The images are in the public repository
[fmegahed/qe_genai](https://github.com/fmegahed/qe_genai), folder
`data/`, under the MIT licence. The pipe staple images keep the licence
of AutoVI, CC BY-NC-SA 4.0: give credit, use them for non-commercial
work only, and share changed images under the same licence. The table
`study_sets.csv` of the package holds only the image names and the
labels. The package holds no image of these datasets, except the 50
textile images of
[`vignette("images")`](https://fmegahed.github.io/decisions/articles/images.md).
Here they are learning or reference images, not test images.

### Images

Download the repository (about 360 MB):

``` bash
git clone https://github.com/fmegahed/qe_genai.git
```

Then tell R where the images are, and where the state files, the setups
and the test results go:

``` r

image_dir <- "qe_genai/data"
state_dir <- "state"
setup_dir <- "setups"
test_dir <- "test"
```

``` r

dir.create(state_dir)
dir.create(setup_dir)
dir.create(test_dir)
```

## Rows

The table `study_sets.csv` gives each image one role. The image paths
are relative to the folder `data/` of fmegahed/qe_genai.

``` r

sets <- system.file("extdata", "study_sets.csv", package = "decisions") |>
  utils::read.csv() |>
  tibble::as_tibble() |>
  dplyr::mutate(
    truth = factor(
      dplyr::if_else(class == "nominal", "normal", "defective"),
      levels = c("normal", "defective")
    ),
    path = file.path(image_dir, image_path)
  )

by_dataset <- split(sets, sets$dataset)

table(sets$dataset, sets$role)
#>                 
#>                  calibration learning reference test
#>   extrusion               50       92         8  200
#>   microstructure          50       92         8  450
#>   pan_images               0       12         8   78
#>   pipe_staple             34       92         8  100
#>   textiles                50       92         8  200
```

The roles:

- `learning`: labeled images to tune on. The tuning steps choose the
  descriptions and the image settings on these images.
- `reference`: four images per class, with a `rank` from 1 to 4. A setup
  with `k` references per class uses the ranks 1 to `k`. The references
  come from the learning images. No step scores the references that its
  setup uses.
- `calibration`: labeled images to fit the calibrator on. The pans have
  too few images for this role. For the pans, the calibrator uses the
  learning images and the references that the chosen setup does not use.
- `test`: the images for the final estimate. They are scored one time
  only.

Each step of the tuning looks at the scores and keeps the better choice.
A choice that looks better on the images that it was chosen on is, on
average, less good on new images. So the estimate of a tuned setup on
its own learning images is too high. The test images give an honest
estimate only if no choice used them. So the test images are scored one
time, at the end, after all choices are fixed.
[`score_setup()`](https://fmegahed.github.io/decisions/reference/score_setup.md)
refuses rows with the role `test`, and
[`evaluate_once()`](https://fmegahed.github.io/decisions/reference/evaluate_once.md)
scores them one time (see “Test”).

The original study drew the rows once, with fixed seeds.

## Question

Each dataset gets the same choice question, with two answers. The
instructions name `inspection_image`: that is the name of the input
image in each request. The descriptions of the answers change during the
tuning. The first candidate of each dataset is a generic description.

``` r

quality_question <- function(descriptions) {
  list(quality = question_choice(
    "Inspect `inspection_image` for manufacturing defects. Select exactly one category.",
    descriptions
  ))
}

generic <- c(
  normal = "No visible manufacturing defects; the part appears conforming.",
  defective = "At least one visible manufacturing defect or anomaly."
)
```

## Models

``` r

deciders <- list(
  jev = decider_typesafe("jev-1.14.0"),
  openai = decider_openai("gpt-6-luna"),
  clef = decider_systemone(
    "http://localhost:30000", "Cloudflare/clef-flash", image_format = "images"
  )
)
```

[`decider_typesafe()`](https://fmegahed.github.io/decisions/reference/decider_typesafe.md)
reads the key from the environment variable `TYPESAFE_API_KEY`, and
[`decider_openai()`](https://fmegahed.github.io/decisions/reference/decider_openai.md)
from `OPENAI_API_KEY` (for example, in `~/.Renviron`). Clef-Flash runs
on your computer, on a GPU, and needs no key. The shell command below
starts its server with Docker
([`vignette("images")`](https://fmegahed.github.io/decisions/articles/images.md)
has the details). It is not run here.

``` bash
docker run --gpus all --shm-size 8g --ipc=host -p 30000:30000 \
  lmsysorg/sglang:dev-clef \
  sglang serve --model-path Cloudflare/clef-flash --host 0.0.0.0 --port 30000
```

The code below runs one model at a time. `model_name` is `"jev"`,
`"openai"` or `"clef"`.

``` r

model_name <- "jev"
```

## Setups

A setup holds one complete decision: the decider, the question with its
descriptions, the reference images and the image settings.
`make_setup()` makes the setup of one model and dataset with `k`
references per class. `upscale = TRUE` enlarges each image to `max_size`
pixels on its longest side: TypeSafe refuses images under 280 pixels,
and some images of these datasets are smaller.

`score_rows()` scores a setup on labeled rows with
[`score_setup()`](https://fmegahed.github.io/decisions/reference/score_setup.md).
It gives
[`score_setup()`](https://fmegahed.github.io/decisions/reference/score_setup.md)
the role of each row, so a test row stops the call before any request. A
reference row counts as a learning row. Each run keeps its answers in a
state file (`path`): a run that stops continues and does not pay twice.
`score_rows()` also keeps the image paths with the result, so a later
step can check that its rows are in the same order as the saved answers.

``` r

make_setup <- function(model, dataset, descriptions, k, max_size) {
  references <- by_dataset[[dataset]] |>
    dplyr::filter(role == "reference", rank <= k) |>
    dplyr::arrange(rank)
  decision_setup(
    deciders[[model]], quality_question(descriptions),
    references = list(
      normal = references$path[references$truth == "normal"],
      defective = references$path[references$truth == "defective"]
    ),
    max_size = max_size, upscale = TRUE
  )
}

score_rows <- function(setup, rows, path) {
  score_setup(
    setup, image = rows$path, truth = rows$truth,
    role = dplyr::if_else(rows$role == "reference", "learning", rows$role),
    path = path
  ) |>
    dplyr::mutate(image_path = list(rows$image_path))
}

state_file <- function(...) {
  file.path(state_dir, paste0(paste(..., sep = "_"), ".json"))
}
```

## Wording

### Candidates

The candidate descriptions come from description loops. In each loop, an
agent (Claude Code) looked at 96 labeled images of one dataset (the
learning images and the references of rank 3 and 4), in a sandbox folder
that it could not leave. The image names gave no label. It wrote one
candidate at a time: a new text for `normal` and for `defective`, from
the images that the best candidate so far scored badly. A script scored
each candidate, with two references per class, and gave the agent the
ROC AUC. A loop had at most 6 candidates, and candidate 1 was the
generic description.

The loops for Jev and Clef-Flash ran in the original study. gpt-6-luna
got its own loops, with the same rules, scored with
[`score_setup()`](https://fmegahed.github.io/decisions/reference/score_setup.md)
of this package. The pans have no loop: they keep the generic
description. The page [description
loops](https://fmegahed.github.io/decision-models-for-industrial-image-qc/pages/description_loops.html)
of the study record shows each candidate of the study loops with the
reason for the change.

The saved results hold the candidates of all loops:

``` r

saved <- readRDS(system.file("extdata", "study_again.rds", package = "decisions"))
candidates <- dplyr::select(
  saved$wording, model, dataset, candidate, normal, defective, reason
)
```

### Keep rule

Two wordings can get a different AUC by chance alone: 96 images give a
rough AUC. If each higher AUC replaced the best wording, the loop would
follow this noise, and it would keep the wording that fits these 96
images by luck. The keep rule protects against this. A candidate
replaces the current best only if its AUC is at least 0.02 higher.
Candidate 1 is the first best.

``` r

keep_rule <- function(auc, gain = 0.02) {
  best <- purrr::accumulate(auc, \(best, x) {
    if (round(x - best, 10) >= gain) x else best
  })
  c(TRUE, diff(best) > 0)
}
```

[`round()`](https://rdrr.io/r/base/Round.html) removes the small errors
of floating-point numbers, so a gain of exactly 0.02 counts.

### Scores

The wording step scores the candidates of each loop in their order, on
the same 96 images, with two references per class and `max_size = 768`.
For Jev and Clef-Flash, these are new calls with the package. For
gpt-6-luna, its loop already scored its candidates in this way, so its
AUCs come from its loop logs, with no new call.

``` r

score_candidate <- function(model, dataset, candidate, normal, defective) {
  setup <- make_setup(
    model, dataset, c(normal = normal, defective = defective),
    k = 2, max_size = 768
  )
  design <- dplyr::filter(
    by_dataset[[dataset]],
    role == "learning" | (role == "reference" & rank > 2)
  )
  score_rows(setup, design, state_file("wording", model, dataset, candidate))
}

wording <- dplyr::filter(candidates, model == model_name)
```

``` r

wording <- wording |>
  dplyr::mutate(
    result = purrr::pmap(
      list(model, dataset, candidate, normal, defective), score_candidate
    ),
    auc = purrr::map_dbl(result, "estimate")
  )
```

The keep rule then gives the final wording of each dataset. The pans get
the generic description.

``` r

wording <- dplyr::mutate(wording, kept = keep_rule(auc), .by = dataset)

final_wording <- wording |>
  dplyr::filter(kept) |>
  dplyr::slice_tail(n = 1, by = dataset) |>
  dplyr::select(model, dataset, normal, defective) |>
  dplyr::bind_rows(tibble::tibble(
    model = model_name, dataset = "pan_images",
    normal = generic[["normal"]], defective = generic[["defective"]]
  ))
```

The table gives, for each model and dataset, the number of candidates,
the AUC of the generic description (candidate 1), the final candidate
and its AUC.

| model  | dataset        | candidates | generic_auc | final | final_auc |
|:-------|:---------------|-----------:|------------:|------:|----------:|
| jev    | extrusion      |          6 |       0.666 |     2 |     0.695 |
| jev    | microstructure |          4 |       0.804 |     2 |     0.918 |
| jev    | pipe_staple    |          1 |       0.934 |     1 |     0.934 |
| jev    | textiles       |          2 |       0.674 |     2 |     0.996 |
| openai | extrusion      |          6 |       0.613 |     5 |     0.770 |
| openai | microstructure |          5 |       0.931 |     1 |     0.931 |
| openai | pipe_staple    |          2 |       0.828 |     2 |     0.999 |
| openai | textiles       |          6 |       0.743 |     5 |     0.966 |
| clef   | extrusion      |          6 |       0.797 |     2 |     0.820 |
| clef   | microstructure |          5 |       0.901 |     4 |     0.953 |
| clef   | pipe_staple    |          2 |       0.661 |     2 |     1.000 |
| clef   | textiles       |          5 |       0.780 |     2 |     0.959 |

The loops raised the AUC of the generic description on most datasets.
The largest gains: Clef-Flash on the pipe staples (0.66 to 1.00), Jev on
the textiles (0.67 to 1.00), and gpt-6-luna on the textiles (0.74 to
0.97). For Jev on the pipe staples, the study loop stopped after the
generic description. For gpt-6-luna on the microstructures, no candidate
beat the generic description (0.93).

The keep rule worked as intended. For Clef-Flash on the textiles,
candidate 2 scored 0.959 and candidate 4 scored 0.977. The gain of 0.018
is less than 0.02, so candidate 2 stayed the final wording.

These AUCs are on the images that the loops chose on, so they are too
high (see “Rows”). The calibration and test images give fresher
estimates.

The final descriptions of the textiles. Each model has its own loop, so
each model has its own wording:

| model | normal | defective |
|:---|:---|:---|
| jev | Grey fabric with a soft, smooth texture of long diagonal streaks that blend gently into each other; no spots, marks or areas that differ from the rest. | Grey fabric with a visible anomaly: either a small local spot or mark, or a texture that is grainier, more speckled and noisier across the whole image, with short choppy strokes instead of long smooth diagonal streaks. |
| openai | Gray fabric with a smooth, soft texture of long diagonal streaks running from lower left to upper right; clear darker and lighter bands and patches stand out, and the pattern looks the same across the whole image. | Gray fabric where the texture is changed: either the whole image is covered by a fine, even, static-like grain with weak contrast, so the long diagonal streaks and dark bands are faint or washed out, or a tiny, sharp cluster of black and white pixels (often near an edge or corner) breaks the soft streak pattern. |
| clef | Gray fabric with a uniform texture of smooth, soft diagonal streaks running evenly across the whole image; no spots or marks. | Gray fabric where the texture differs from smooth even diagonal streaks: the whole surface looks rougher, coarser, mottled or clumpy, or there is a small spot, speck or foreign mark. |

## Grid

The grid tries 6 setups for each model and dataset: `k` = 1, 2 or 4
references per class, and `max_size` = 512 or 768 pixels. Each setup
uses the final wording. It scores the learning images that are not
references: 92 per dataset, and 12 for the pans. The setup with the
highest AUC is the chosen setup. A tie goes to the smaller `k`, then to
the smaller size.

``` r

score_grid <- function(model, dataset, normal, defective, k, max_size) {
  setup <- make_setup(
    model, dataset, c(normal = normal, defective = defective), k, max_size
  )
  learning <- dplyr::filter(by_dataset[[dataset]], role == "learning")
  score_rows(setup, learning, state_file("grid", model, dataset, k, max_size))
}

grid <- final_wording |>
  dplyr::cross_join(tibble::tibble(
    k = rep(c(1, 2, 4), each = 2), max_size = rep(c(512, 768), times = 3)
  ))
```

``` r

grid <- grid |>
  dplyr::mutate(result = purrr::pmap(
    list(model, dataset, normal, defective, k, max_size), score_grid
  ))
```

``` r

grid <- dplyr::bind_cols(
  dplyr::select(grid, -result),
  purrr::list_rbind(grid$result) |>
    dplyr::select(-metric) |>
    dplyr::rename(auc = estimate)
)

chosen <- grid |>
  dplyr::arrange(dataset, dplyr::desc(round(auc, 10)), k, max_size) |>
  dplyr::slice_head(n = 1, by = dataset)
```

The AUC of each setup:

| model  | dataset        | k 1, 512 | k 1, 768 | k 2, 512 | k 2, 768 | k 4, 512 | k 4, 768 |
|:-------|:---------------|---------:|---------:|---------:|---------:|---------:|---------:|
| jev    | extrusion      |    0.771 |    0.689 |    0.750 |    0.682 |    0.764 |    0.729 |
| jev    | microstructure |    0.927 |    0.912 |    0.934 |    0.902 |    0.937 |    0.894 |
| jev    | pipe_staple    |    0.936 |    0.923 |    0.981 |    0.931 |    1.000 |    0.998 |
| jev    | textiles       |    0.985 |    0.981 |    0.996 |    0.992 |    0.992 |    0.999 |
| jev    | pan_images     |    1.000 |    1.000 |    1.000 |    1.000 |    1.000 |    1.000 |
| openai | extrusion      |    0.744 |    0.747 |    0.795 |    0.763 |    0.812 |    0.760 |
| openai | microstructure |    0.831 |    0.960 |    0.951 |    0.927 |    0.954 |    0.943 |
| openai | pipe_staple    |    1.000 |    1.000 |    0.997 |    0.999 |    1.000 |    1.000 |
| openai | textiles       |    0.940 |    0.942 |    0.934 |    0.963 |    0.931 |    0.977 |
| openai | pan_images     |    1.000 |    1.000 |    1.000 |    1.000 |    1.000 |    1.000 |
| clef   | extrusion      |    0.779 |    0.774 |    0.815 |    0.811 |    0.829 |    0.824 |
| clef   | microstructure |    0.964 |    0.960 |    0.942 |    0.950 |    0.963 |    0.956 |
| clef   | pipe_staple    |    0.977 |    1.000 |    0.941 |    1.000 |    0.908 |    0.964 |
| clef   | textiles       |    0.919 |    0.968 |    0.948 |    0.958 |    0.882 |    0.927 |
| clef   | pan_images     |    0.944 |    1.000 |    0.861 |    1.000 |    1.000 |    1.000 |

The chosen setups:

| model  | dataset        |   k | max_size |   auc |
|:-------|:---------------|----:|---------:|------:|
| jev    | extrusion      |   1 |      512 | 0.771 |
| jev    | microstructure |   4 |      512 | 0.937 |
| jev    | pan_images     |   1 |      512 | 1.000 |
| jev    | pipe_staple    |   4 |      512 | 1.000 |
| jev    | textiles       |   4 |      768 | 0.999 |
| openai | extrusion      |   4 |      512 | 0.812 |
| openai | microstructure |   1 |      768 | 0.960 |
| openai | pan_images     |   1 |      512 | 1.000 |
| openai | pipe_staple    |   1 |      512 | 1.000 |
| openai | textiles       |   4 |      768 | 0.977 |
| clef   | extrusion      |   4 |      512 | 0.829 |
| clef   | microstructure |   1 |      512 | 0.964 |
| clef   | pan_images     |   1 |      768 | 1.000 |
| clef   | pipe_staple    |   1 |      768 | 1.000 |
| clef   | textiles       |   1 |      768 | 0.968 |

No setting is the best for all models and datasets. On the extrusion
images, the chosen setups use `k` = 1 (Jev), 4 (gpt-6-luna) and 4
(Clef-Flash). On the microstructures, they use `k` = 4, 1 and 1. Images
of 512 pixels need about 49 % of the input tokens of images of 768
pixels, and they were often as good. 22 of the 90 setups reach an AUC of
1, all on the pans and pipe staples. The tie rule then picks the setup
with the fewest references. On the 12 learning images of the pans, an
AUC of 1 says little.

These AUCs are on the images that the grid chose on, so they are too
high (see “Rows”). The calibration and test images give fresher
estimates.

## Calibration

A calibrator corrects the probabilities of a model, so that they agree
with the rates of defects. This vignette uses Platt scaling: a logistic
regression of the truth on the logit of the probability of `defective`.
It is fitted on the calibration images, with the chosen setup.

``` r

calibration_rows <- function(dataset, k) {
  rows <- by_dataset[[dataset]]
  if (dataset == "pan_images") {
    dplyr::filter(rows, role == "learning" | (role == "reference" & rank > k))
  } else {
    dplyr::filter(rows, role == "calibration")
  }
}

score_calibration <- function(model, dataset, normal, defective, k, max_size) {
  setup <- make_setup(
    model, dataset, c(normal = normal, defective = defective), k, max_size
  )
  rows <- calibration_rows(dataset, k)
  score_rows(setup, rows, state_file("calibration", model, dataset, k, max_size))
}

calibration <- dplyr::select(chosen, model, dataset, normal, defective, k, max_size)
```

``` r

calibration <- calibration |>
  dplyr::mutate(result = purrr::pmap(
    list(model, dataset, normal, defective, k, max_size), score_calibration
  ))
```

Platt scaling does not fit the labels 0 and 1. With N+ defective and N-
normal calibration images, its target is (N+ + 1) / (N+ + 2) for a
defective image and 1 / (N- + 2) for a normal image. These targets keep
the fit finite when a model ranks the few calibration images almost
perfectly. A fit on the labels 0 and 1 then has no finite solution: its
slope grows without limit, and the calibrated probabilities become 0
or 1. The logistic calibrator of probably
([`probably::cal_estimate_logistic()`](https://probably.tidymodels.org/reference/cal_estimate_logistic.html)
with `smooth = FALSE`) fits the labels 0 and 1, so it saturates on so
few, almost perfectly ranked calibration images. On the calibration
images of this vignette, its [`glm()`](https://rdrr.io/r/stats/glm.html)
warns for 8 of the 15 setups, and its calibrated probabilities come
within 1e-12 of 0 or 1 for 9 setups. The calibrators of probably fit
well with more calibration images. The targets are not 0 or 1, so the
fit uses `family = quasibinomial`.
[`clip()`](https://rdrr.io/r/graphics/clip.html) keeps each probability
between 0.005 and 0.995, the clamp of the original study, so that its
logit stays between about -5.3 and 5.3.

``` r

clip <- function(prob) pmin(pmax(prob, 0.005), 0.995)

platt_fit <- function(prob, truth) {
  n_defective <- sum(truth == "defective")
  n_normal <- sum(truth == "normal")
  target <- dplyr::if_else(
    truth == "defective", (n_defective + 1) / (n_defective + 2), 1 / (n_normal + 2)
  )
  stats::glm(target ~ stats::qlogis(clip(prob)), family = stats::quasibinomial())
}

platt_apply <- function(prob, intercept, slope) {
  stats::plogis(intercept + slope * stats::qlogis(clip(prob)))
}
```

`platt_row()` fits the Platt scaling of one setup and keeps its two
coefficients and the class counts.

``` r

platt_row <- function(model, dataset, k, result, ...) {
  truth <- calibration_rows(dataset, k)$truth
  fit <- platt_fit(result$answers[[1]]$.pred_defective, truth)
  tibble::tibble(
    model = model, dataset = dataset,
    n_normal = sum(truth == "normal"), n_defective = sum(truth == "defective"),
    intercept = stats::coef(fit)[[1]], slope = stats::coef(fit)[[2]]
  )
}

platt <- calibration |>
  purrr::pmap(platt_row) |>
  purrr::list_rbind()
```

The setups keep no calibrator.
[`write_setup()`](https://fmegahed.github.io/decisions/reference/write_setup.md)
saves each setup as one JSON file, and the Platt fits stay in the saved
results. So
[`evaluate_once()`](https://fmegahed.github.io/decisions/reference/evaluate_once.md)
scores the raw probabilities, and `platt_apply()` maps them to
calibrated ones. (A setup can hold a probably calibrator when there are
enough calibration images for it. Set it with
`setup@calibrator <- calibrator`; this works also for a setup from
[`read_setup()`](https://fmegahed.github.io/decisions/reference/read_setup.md).)

``` r

calibration |>
  dplyr::select(model, dataset, normal, defective, k, max_size) |>
  purrr::pwalk(\(model, dataset, normal, defective, k, max_size) {
    setup <- make_setup(
      model, dataset, c(normal = normal, defective = defective), k, max_size
    )
    write_setup(setup, file.path(setup_dir, paste0(model, "_", dataset, ".json")))
  })
```

The Platt fits, with the smallest fitted value and the distance of the
largest fitted value from 1, on the calibration images:

| model | dataset | n_normal | n_defective | intercept | slope | min_fitted | 1 - max_fitted |
|:---|:---|---:|---:|---:|---:|:---|:---|
| jev | extrusion | 25 | 25 | -0.435 | 0.550 | 0.284 | 0.186 |
| jev | microstructure | 25 | 25 | 1.294 | 1.438 | 0.0813 | 0.000136 |
| jev | pan_images | 9 | 9 | -0.349 | 0.888 | 0.107 | 0.0427 |
| jev | pipe_staple | 17 | 17 | -1.188 | 2.315 | 0.0105 | 0.0114 |
| jev | textiles | 25 | 25 | -3.124 | 2.759 | 0.00891 | 7.1e-05 |
| openai | extrusion | 25 | 25 | -1.863 | 0.533 | 0.1 | 0.277 |
| openai | microstructure | 25 | 25 | 4.235 | 1.462 | 0.0292 | 1.75e-05 |
| openai | pan_images | 9 | 9 | -0.403 | 0.678 | 0.0456 | 0.0397 |
| openai | pipe_staple | 17 | 17 | -0.998 | 1.634 | 0.0186 | 0.00917 |
| openai | textiles | 25 | 25 | -1.618 | 2.951 | 0.035 | 6.53e-06 |
| clef | extrusion | 25 | 25 | 3.758 | 4.175 | 0.0271 | 0.0456 |
| clef | microstructure | 25 | 25 | 5.282 | 2.811 | 0.114 | 0.000176 |
| clef | pan_images | 9 | 9 | 0.596 | 0.944 | 0.115 | 0.0538 |
| clef | pipe_staple | 17 | 17 | -3.484 | 5.166 | 0.000308 | 0.0118 |
| clef | textiles | 25 | 25 | 7.770 | 6.926 | 0.00974 | 2.34e-06 |

All 15 fits converged, and [`glm()`](https://rdrr.io/r/stats/glm.html)
gave no warning. No fitted value reaches 0 or 1: the fitted values lie
between 3.1e-04 and 1 - 2.3e-06. No fitted value lies within 1e-6 of 0
or 1. The clamp limits the logit, so it also limits the calibrated
probability of any raw probability. But a steep fit multiplies the logit
by its slope (up to 6.9, for Clef-Flash on the textiles). So at the
clamp limits, 2 fits (Clef-Flash on the pipe staples and Clef-Flash on
the textiles) give a calibrated probability within 1e-12 of 0 or 1.

The calibrated metrics:

``` r

calibration_metrics <- function(model, dataset, k, result, intercept, slope,
                                ...) {
  answers <- dplyr::mutate(
    result$answers[[1]], truth = calibration_rows(dataset, k)$truth
  )
  calibrated <- dplyr::mutate(
    answers, .pred_defective = platt_apply(.pred_defective, intercept, slope)
  )
  metrics <- yardstick::metric_set(
    yardstick::roc_auc, yardstick::brier_class, yardstick::mn_log_loss
  )
  dplyr::bind_rows(
    before = metrics(answers, truth, .pred_defective, event_level = "second"),
    after = metrics(calibrated, truth, .pred_defective, event_level = "second"),
    .id = "probabilities"
  ) |>
    dplyr::mutate(model = model, dataset = dataset, n = nrow(answers), .before = 1)
}

calibration_summary <- calibration |>
  dplyr::left_join(platt, by = c("model", "dataset")) |>
  purrr::pmap(calibration_metrics) |>
  purrr::list_rbind()
```

The table gives the AUC of the chosen setup on the calibration images,
and the Brier score and the log loss before and after Platt scaling. A
lower Brier score and a lower log loss are better. Platt scaling is
strictly increasing between the clamp limits (its slope is positive in
all 15 fits), so it keeps the order of the images there. Raw
probabilities below 0.005, or above 0.995, become equal. On the
calibration images, the AUC after Platt scaling is the same as before
for all 15 setups. The AUC of the test comes from the raw probabilities.

| model | dataset | n | auc | brier_before | brier_after | log_loss_before | log_loss_after |
|:---|:---|---:|---:|---:|---:|---:|---:|
| jev | extrusion | 50 | 0.607 | 0.270 | 0.239 | 0.747 | 0.670 |
| jev | microstructure | 50 | 0.973 | 0.091 | 0.064 | 0.298 | 0.227 |
| jev | pan_images | 18 | 1.000 | 0.030 | 0.034 | 0.147 | 0.163 |
| jev | pipe_staple | 34 | 1.000 | 0.071 | 0.012 | 0.287 | 0.083 |
| jev | textiles | 50 | 0.991 | 0.163 | 0.033 | 0.467 | 0.138 |
| openai | extrusion | 50 | 0.765 | 0.357 | 0.193 | 3.840 | 0.569 |
| openai | microstructure | 50 | 0.986 | 0.229 | 0.052 | 0.673 | 0.186 |
| openai | pan_images | 18 | 1.000 | 0.012 | 0.024 | 0.078 | 0.137 |
| openai | pipe_staple | 34 | 0.978 | 0.113 | 0.081 | 0.374 | 0.266 |
| openai | textiles | 50 | 0.942 | 0.170 | 0.101 | 0.505 | 0.326 |
| clef | extrusion | 50 | 0.849 | 0.256 | 0.161 | 0.702 | 0.496 |
| clef | microstructure | 50 | 0.957 | 0.217 | 0.078 | 0.633 | 0.271 |
| clef | pan_images | 18 | 1.000 | 0.035 | 0.027 | 0.150 | 0.142 |
| clef | pipe_staple | 34 | 1.000 | 0.167 | 0.018 | 0.508 | 0.103 |
| clef | textiles | 50 | 0.996 | 0.212 | 0.036 | 0.598 | 0.147 |

Platt scaling is fitted and measured on the same images, so the numbers
“after” are too good. The test images give the honest numbers.

The calibration images are new to the chosen setup (not for the pans:
their calibration rows include the grid images), so their AUC is a first
check of the choices. On most datasets, the AUC stays close to the AUC
of the grid. On the extrusion images, the AUC of Jev falls from 0.77
(grid) to 0.61. This agrees with the effect that “Rows” describes: the
choices fit the learning images better than new images. Chance plays a
part too, because 50 images give a rough AUC.

Before calibration, the probabilities of the models are often too
extreme. For gpt-6-luna on the extrusion images, the log loss is 3.84:
the model gave probabilities near 0 or 1 to images of the other class.
Platt scaling moves such probabilities toward the rates of defects, and
the log loss falls to 0.57.

For Jev on the pans, Jev on the pipe staples, gpt-6-luna on the pans,
Clef-Flash on the pans, and Clef-Flash on the pipe staples, the chosen
setup separates the two classes of the calibration images fully (AUC 1).
Their Platt fits stay finite, so their Brier score and log loss “after”
stay above 0. The targets of Platt pull the probabilities a little away
from 0 and 1. Where the raw probabilities are already good, this can
make the numbers “after” worse: the Brier score or the log loss goes up
for Jev on the pans and gpt-6-luna on the pans.

## Folds

How much does an AUC move from one sample of images to another?
Cross-validation splits the learning images of the chosen setup into 5
folds, 10 times
([`rsample::vfold_cv()`](https://rsample.tidymodels.org/reference/vfold_cv.html),
with the classes in the same ratio in each fold). Each fold gives the
AUC of its fifth of the images. No model is fitted, and no call is sent:
the folds use the saved probabilities of the grid.

``` r

fold_auc <- function(model, dataset, answers) {
  learning <- dplyr::filter(by_dataset[[dataset]], role == "learning")
  scored <- dplyr::mutate(answers, truth = learning$truth)
  set.seed(2026)
  rsample::vfold_cv(scored, v = 5, repeats = 10, strata = truth) |>
    dplyr::mutate(
      model = model, dataset = dataset,
      auc = purrr::map_dbl(splits, \(split) {
        held_out <- rsample::assessment(split)
        yardstick::roc_auc_vec(
          held_out$truth, held_out$.pred_defective, event_level = "second"
        )
      })
    ) |>
    dplyr::select(model, dataset, id, id2, auc)
}

folds <- chosen |>
  dplyr::select(model, dataset, answers) |>
  purrr::pmap(fold_auc) |>
  purrr::list_rbind()
```

| model  | dataset        | folds |  mean |    sd |   min |   max | grid_auc |
|:-------|:---------------|------:|------:|------:|------:|------:|---------:|
| jev    | extrusion      |    50 | 0.771 | 0.088 | 0.586 | 0.951 |    0.771 |
| jev    | microstructure |    50 | 0.938 | 0.050 | 0.784 | 1.000 |    0.937 |
| jev    | pan_images     |    50 | 1.000 | 0.000 | 1.000 | 1.000 |    1.000 |
| jev    | pipe_staple    |    50 | 0.999 | 0.003 | 0.988 | 1.000 |    1.000 |
| jev    | textiles       |    50 | 0.999 | 0.003 | 0.988 | 1.000 |    0.999 |
| openai | extrusion      |    50 | 0.811 | 0.095 | 0.543 | 0.981 |    0.812 |
| openai | microstructure |    50 | 0.960 | 0.033 | 0.858 | 1.000 |    0.960 |
| openai | pan_images     |    50 | 1.000 | 0.000 | 1.000 | 1.000 |    1.000 |
| openai | pipe_staple    |    50 | 1.000 | 0.000 | 1.000 | 1.000 |    1.000 |
| openai | textiles       |    50 | 0.976 | 0.033 | 0.833 | 1.000 |    0.977 |
| clef   | extrusion      |    50 | 0.834 | 0.084 | 0.636 | 1.000 |    0.829 |
| clef   | microstructure |    50 | 0.964 | 0.033 | 0.864 | 1.000 |    0.964 |
| clef   | pan_images     |    50 | 1.000 | 0.000 | 1.000 | 1.000 |    1.000 |
| clef   | pipe_staple    |    50 | 1.000 | 0.000 | 1.000 | 1.000 |    1.000 |
| clef   | textiles       |    50 | 0.968 | 0.032 | 0.840 | 1.000 |    0.968 |

The mean of the fold AUCs is close to the AUC of the grid, as it should
be: the folds split the same images. The spread is the useful part. On
the extrusion images, the AUC of about 18 images has a standard
deviation of about 0.09, and it goes from 0.54 to 1.00 over the three
models. On the microstructures and the textiles, the standard deviation
is 0.05 or less. The standard deviation of an AUC falls about as 1 /
sqrt(n). So for the 92 learning images of the extrusion, it is about
0.09 / sqrt(5), that is about 0.04: a difference of a few hundredths
between two setups can come from chance. The pans give an AUC of 1 in
100 % of the folds, and the pipe staples in 97 %, so their folds show
almost no spread.

## Test

The test images give the final estimate of each chosen setup. No step
above used them: the descriptions, the image settings and the Platt fits
were fixed before the test. Before the run, the script
`data-raw/study_again.R` checks that no learning, reference or
calibration image has the path or the bytes (md5) of a test image. This
check also shows that two extrusion test images are the same file, byte
for byte; both stay in the test set. The numbers below come from one run
on the test images, on 2026-10-24.

[`evaluate_once()`](https://fmegahed.github.io/decisions/reference/evaluate_once.md)
reads the saved setup, which holds no calibrator, and scores the test
images one time. So its AUC is the AUC of the raw probabilities. It
writes the result to `path` and refuses to run again while that file
exists. `score_test()` reads the result file when it exists, so a second
run of this code sends no request and gives the same numbers.

``` r

test_file <- function(model, dataset) {
  file.path(test_dir, paste0(model, "_", dataset, ".rds"))
}

score_test <- function(model, dataset) {
  path <- test_file(model, dataset)
  if (file.exists(path)) {
    # The test rows were scored: read the result. No request goes out.
    return(dplyr::mutate(readRDS(path), calls = 0))
  }
  setup <- read_setup(file.path(setup_dir, paste0(model, "_", dataset, ".json")))
  test <- dplyr::filter(by_dataset[[dataset]], role == "test")
  evaluate_once(
    setup, image = test$path, truth = test$truth, event = "defective",
    path = path
  )
}
```

``` r

test <- chosen |>
  dplyr::select(model, dataset) |>
  dplyr::mutate(result = purrr::map2(model, dataset, score_test))
```

The Platt fit of each setup then gives the calibrated probabilities of
the test images. `test_metrics()` computes with yardstick the AUC, the
accuracy, the sensitivity (the share of defective images that the setup
finds) and the specificity (the share of normal images that it passes)
at a probability of 0.5, the Brier score and the log loss. It computes
them before Platt scaling (`raw`) and after it (`calibrated`).

``` r

at_half <- function(prob) {
  factor(
    dplyr::if_else(prob >= 0.5, "defective", "normal"),
    levels = c("normal", "defective")
  )
}

test_metrics <- function(model, dataset, result, intercept, slope, ...) {
  truth <- dplyr::filter(by_dataset[[dataset]], role == "test")$truth
  metrics <- yardstick::metric_set(
    yardstick::roc_auc, yardstick::accuracy, yardstick::sensitivity,
    yardstick::specificity, yardstick::brier_class, yardstick::mn_log_loss
  )
  score <- function(prob) {
    scored <- tibble::tibble(truth = truth, prob = prob, predicted = at_half(prob))
    metrics(scored, truth, prob, estimate = predicted, event_level = "second")
  }
  raw <- result$answers[[1]]$.pred_defective
  dplyr::bind_rows(
    raw = score(raw),
    calibrated = score(platt_apply(raw, intercept, slope)),
    .id = "probabilities"
  ) |>
    dplyr::mutate(model = model, dataset = dataset, n = length(truth), .before = 1)
}

test_summary <- test |>
  dplyr::left_join(platt, by = c("model", "dataset")) |>
  purrr::pmap(test_metrics) |>
  purrr::list_rbind()
```

The table gives, for each model and dataset, the number of test images,
the AUC and the accuracy (`raw_accuracy`) of the raw probabilities, and
the accuracy, sensitivity, specificity, Brier score and log loss after
Platt scaling.

| model | dataset | n | auc | raw_accuracy | accuracy | sensitivity | specificity | brier | log_loss |
|:---|:---|---:|---:|---:|---:|---:|---:|---:|---:|
| jev | extrusion | 200 | 0.755 | 0.560 | 0.685 | 0.720 | 0.650 | 0.215 | 0.621 |
| jev | microstructure | 450 | 0.934 | 0.840 | 0.884 | 0.791 | 0.978 | 0.091 | 0.297 |
| jev | pan_images | 78 | 1.000 | 0.987 | 0.885 | 0.769 | 1.000 | 0.075 | 0.287 |
| jev | pipe_staple | 100 | 0.997 | 0.910 | 0.960 | 1.000 | 0.920 | 0.035 | 0.133 |
| jev | textiles | 200 | 1.000 | 0.620 | 0.990 | 0.980 | 1.000 | 0.027 | 0.130 |
| openai | extrusion | 200 | 0.733 | 0.570 | 0.680 | 0.580 | 0.780 | 0.212 | 0.611 |
| openai | microstructure | 450 | 0.968 | 0.698 | 0.918 | 0.853 | 0.982 | 0.064 | 0.224 |
| openai | pan_images | 78 | 0.997 | 0.808 | 0.654 | 0.308 | 1.000 | 0.163 | 0.465 |
| openai | pipe_staple | 100 | 0.995 | 0.950 | 0.950 | 0.900 | 1.000 | 0.046 | 0.186 |
| openai | textiles | 200 | 0.958 | 0.805 | 0.875 | 0.760 | 0.990 | 0.093 | 0.306 |
| clef | extrusion | 200 | 0.842 | 0.500 | 0.745 | 0.680 | 0.810 | 0.164 | 0.499 |
| clef | microstructure | 450 | 0.966 | 0.682 | 0.880 | 0.760 | 1.000 | 0.087 | 0.289 |
| clef | pan_images | 78 | 1.000 | 0.821 | 0.859 | 0.718 | 1.000 | 0.094 | 0.318 |
| clef | pipe_staple | 100 | 0.999 | 0.610 | 0.970 | 0.980 | 0.960 | 0.023 | 0.112 |
| clef | textiles | 200 | 0.983 | 0.540 | 0.945 | 0.890 | 1.000 | 0.056 | 0.212 |

The same threshold metrics, the Brier score and the log loss of the raw
probabilities, before Platt scaling:

| model  | dataset        | accuracy | sensitivity | specificity | brier | log_loss |
|:-------|:---------------|---------:|------------:|------------:|------:|---------:|
| jev    | extrusion      |    0.560 |       0.950 |        0.17 | 0.241 |    0.675 |
| jev    | microstructure |    0.840 |       0.680 |        1.00 | 0.113 |    0.359 |
| jev    | pan_images     |    0.987 |       0.974 |        1.00 | 0.053 |    0.236 |
| jev    | pipe_staple    |    0.910 |       1.000 |        0.82 | 0.084 |    0.309 |
| jev    | textiles       |    0.620 |       1.000 |        0.24 | 0.165 |    0.469 |
| openai | extrusion      |    0.570 |       0.990 |        0.15 | 0.345 |    2.292 |
| openai | microstructure |    0.698 |       0.396 |        1.00 | 0.221 |    0.847 |
| openai | pan_images     |    0.808 |       0.615 |        1.00 | 0.118 |    0.356 |
| openai | pipe_staple    |    0.950 |       0.960 |        0.94 | 0.078 |    0.293 |
| openai | textiles       |    0.805 |       0.960 |        0.65 | 0.152 |    0.470 |
| clef   | extrusion      |    0.500 |       0.000 |        1.00 | 0.258 |    0.708 |
| clef   | microstructure |    0.682 |       0.364 |        1.00 | 0.228 |    0.664 |
| clef   | pan_images     |    0.821 |       0.641 |        1.00 | 0.134 |    0.406 |
| clef   | pipe_staple    |    0.610 |       1.000 |        0.22 | 0.173 |    0.520 |
| clef   | textiles       |    0.540 |       0.080 |        1.00 | 0.244 |    0.670 |

The AUC measures the ranking: it is the chance that a defective image
gets a higher probability than a normal image. On the pans and the pipe
staples, the AUC of each model is 0.995 or more. On the microstructures
and the textiles, it lies between 0.934 and 1.000. The extrusion images
are the hardest for all three models: their AUC lies between 0.733 and
0.842.

A good ranking does not give good decisions at a probability of 0.5. The
raw probabilities of a model can fall mostly on one side of 0.5. For
example, on the extrusion images, Clef-Flash gives no test image a raw
probability of 0.5 or more (the highest is 0.495), although its AUC
there is 0.842. So with the raw probabilities it calls every image
normal, and its accuracy is 0.500. After Platt scaling, its accuracy is
0.745.

Platt scaling moves the probabilities toward the rates of defects of the
calibration images. On most setups, this helps. The accuracy at 0.5 is
higher after Platt scaling for 12 of the 15 setups, and the same for
gpt-6-luna on the pipe staples. The Brier score and the log loss are
both lower for 13 setups.

Platt scaling hurts Jev on the pans and gpt-6-luna on the pans. Their
accuracy falls (Jev 0.987 to 0.885 and gpt-6-luna 0.808 to 0.654), their
Brier score rises (Jev 0.053 to 0.075 and gpt-6-luna 0.118 to 0.163),
and their log loss rises (Jev 0.236 to 0.287 and gpt-6-luna 0.356 to
0.465). The Platt fits of the pans come from only 18 images, and the
grid chose the setup on most of these images (see “Calibration”), so
these fits are rough.

The test sets are small. For the 78 pan images, one image on the wrong
side changes the accuracy by 1.3 percentage points, and for the 100 pipe
staple images by 1.0 points.

### Cost and time of the test

Each test run sends one request per distinct image. The two extrusion
test images that are the same file share one request
([`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
sends identical inputs once), so `images` is 1,027 per model, for 1,028
test images. `seconds` is the sum of the response times, and `minutes`
is the time of the whole run (10 requests at a time).

| model  | images | input_tokens | cost |   seconds | log_rows | minutes |
|:-------|-------:|-------------:|-----:|----------:|---------:|--------:|
| jev    |  1,027 |    7,437,499 |   NA | 1,022.282 |    1,027 |     2.2 |
| openai |  1,027 |    2,606,155 |   NA |   866.213 |    1,027 |     2.1 |
| clef   |  1,027 |    1,706,215 |   NA | 2,066.687 |       NA |     4.0 |

`log_rows` is the number of paid calls that the script
`data-raw/study_again.R` logged, one row per call. Clef-Flash runs on
this computer and costs nothing per call, so it has no log. Each model
scored its test images in 2.1 to 4.0 minutes.

## Cost and time

The tables below give the tuning steps (wording, grid and calibration);
the test has its own table in “Test”. TypeSafe, OpenAI and the
Clef-Flash server report no cost, so `.cost` is `NA`, and the reported
cost below is `NA` too. All three report the input tokens. `images` is
the number of scored images: one call each. `seconds` is the sum of the
response times. The requests run in parallel (10 at a time), so a run
takes less time than this sum.

| model | images | input_tokens | reported_cost | seconds | tokens_per_image | seconds_per_image |
|:---|---:|---:|---:|---:|---:|---:|
| jev | 3,730 | 27,544,904 | NA | 3,444.394 | 7,384.693 | 0.923 |
| clef | 4,210 | 11,765,934 | NA | 13,996.386 | 2,794.759 | 3.325 |
| openai | 4,306 | 12,046,952 | NA | 4,554.550 | 2,797.713 | 1.058 |

The images by step:

| model  | step        | images | input_tokens | cost |   seconds |
|:-------|:------------|-------:|-------------:|-----:|----------:|
| jev    | wording     |  1,248 |   10,354,944 |   NA | 1,118.131 |
| clef   | wording     |  1,728 |    5,432,160 |   NA | 6,531.470 |
| openai | wording     |  1,824 |    5,667,168 |   NA | 1,771.646 |
| jev    | grid        |  2,280 |   15,707,648 |   NA | 2,124.139 |
| openai | grid        |  2,280 |    5,838,144 |   NA | 2,536.228 |
| clef   | grid        |  2,280 |    5,958,136 |   NA | 7,016.431 |
| jev    | calibration |    202 |    1,482,312 |   NA |   202.124 |
| openai | calibration |    202 |      541,640 |   NA |   246.677 |
| clef   | calibration |    202 |      375,638 |   NA |   448.485 |

The wording images of gpt-6-luna are the calls of its loops. No tuning
step scored a test image.

Jev used about 2.6 times the input tokens of the other two models for
the same images. The two hosted models answered in about 0.9 (Jev) and
1.1 (gpt-6-luna) seconds per image. Clef-Flash ran on one GPU (NVIDIA
RTX 5000 Ada, 32 GB), and it took about 3.3 seconds per image, but it
costs nothing per call. Once, during the wording step, the Clef-Flash
server stopped answering. A restart of the server and a new run with the
same state files continued the step: the finished answers came from the
state files, and only the open images were sent again.

## Image size

The setup here differs slightly from the paper of the original study.
This vignette enlarges each image to 512 or 768 pixels on its longest
side (`upscale = TRUE`; the large pan images are made smaller). The
paper used 1,568 pixels, with padding.

## References

Bui, A. T., & Apley, D. W. (2021). spc4sts: Statistical process control
for stochastic textured surfaces in R. *Journal of Quality Technology,
53*(3), 219-242. <https://doi.org/10.1080/00224065.2019.1707730>

Carvalho, P., Lafou, M., Durupt, A., Leblanc, A., & Grandvalet, Y.
(2024). *The Automotive Visual Inspection Dataset (AutoVI): A genuine
industrial production dataset for unsupervised anomaly detection*
``` math
Data set
```
. Zenodo. <https://doi.org/10.5281/zenodo.10459003>

Megahed, F. M., & Camelio, J. A. (2012). Real-time fault detection in
manufacturing environments using face recognition techniques. *Journal
of Intelligent Manufacturing, 23*(3), 393-408.
<https://doi.org/10.1007/s10845-010-0378-3>

Megahed, F. M., Chen, Y.-J., Colosimo, B. M., Grasso, M., Jones-Farmer,
L. A., Knoth, S., Sun, H., & Zwetsloot, I. M. (2026). Adapting OpenAI’s
CLIP model for few-shot image inspection in manufacturing quality
control: An expository case study with multiple application examples.
*Journal of Quality Technology, 58*(4), 415-441.
<https://doi.org/10.1080/00224065.2026.2640171>
