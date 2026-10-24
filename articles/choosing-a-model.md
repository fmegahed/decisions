# Choosing a model

``` r

library(decisions)
```

## Overview

Different providers host different decision models. The decisions
package gives them one interface. So you can run the same question with
each model and compare the results.

This vignette compares three models on one text task:

- Jev, from TypeSafe, with
  [`decider_typesafe()`](https://fmegahed.github.io/decisions/reference/decider_typesafe.md).
- Microsoft-Decision-1, through OpenRouter, with
  [`decider_openrouter()`](https://fmegahed.github.io/decisions/reference/decider_openrouter.md).
- The Decisions API of OpenAI, with
  [`decider_openai()`](https://fmegahed.github.io/decisions/reference/decider_openai.md).
  Its default model is `gpt-6-luna`.

The results below come from live calls. The package saved them in
`inst/extdata`, so this vignette builds without a key and without a
network. The code that made them is in `data-raw/vignette_results.R`.

## Credentials

Each provider has its own key.
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
reads the key from an environment variable when it sends the requests,
as ellmer does.

| Provider | Decider | Environment variable |
|----|----|----|
| TypeSafe | [`decider_typesafe()`](https://fmegahed.github.io/decisions/reference/decider_typesafe.md) | `TYPESAFE_API_KEY` |
| OpenRouter | [`decider_openrouter()`](https://fmegahed.github.io/decisions/reference/decider_openrouter.md) | `OPENROUTER_API_KEY` |
| OpenAI | [`decider_openai()`](https://fmegahed.github.io/decisions/reference/decider_openai.md) | `OPENAI_API_KEY` |

Set the variables in `~/.Renviron`, then restart R. A decider holds no
key. Each decider also takes a `credentials` function that returns the
key. The function replaces the environment variable.

## Data

The package has the dataset `ohio_injuries`. It has the narratives of
464 severe work injuries in Ohio. The source is the Severe Injury
Reports of the U.S. Occupational Safety and Health Administration
(OSHA). The column `collapsed_nature_title` has five injury types:
`amputation`, `fracture`, `crushing injury`, `thermal burn` and
`concussion`. See
[`?ohio_injuries`](https://fmegahed.github.io/decisions/reference/ohio_injuries.md)
for the details.

Source:

Occupational Safety and Health Administration. (n.d.). *Severe injury
reports* \[Data set\]. U.S. Department of Labor. Retrieved October 23,
2026, from <https://www.osha.gov/severe-injury-reports>

We used the filters Year: 2025 and State: Ohio.

For context: the NIOSH Center for Workers’ Compensation Studies reports
the claim counts and rates of the Ohio Bureau of Workers’ Compensation
(<https://www.cdc.gov/niosh/worker-comp/about/index.html>).

The five groups differ in size: 187 amputations and 242 fractures, but
only 14 crushing injuries, 15 thermal burns and 6 concussions. We take
all the reports of the three small groups and 20 reports of each large
group. The seed is fixed. This gives 75 narratives.

``` r

set.seed(2026)
injuries <- ohio_injuries |>
  dplyr::slice_sample(n = 20, by = collapsed_nature_title)

dplyr::count(injuries, collapsed_nature_title)
#> # A tibble: 5 × 2
#>   collapsed_nature_title     n
#>   <fct>                  <int>
#> 1 amputation                20
#> 2 fracture                  20
#> 3 crushing injury           14
#> 4 thermal burn              15
#> 5 concussion                 6
```

The truth is the column `collapsed_nature_title`, a factor. Its levels
are the five injury types, in the order above.

## Question

One choice question has the five injury types as its answers. The
descriptions are general. The model reads the narrative of each report.

``` r

nature <- question_choice(
  "Which injury does this report of a work injury describe? Choose the main injury.",
  c(
    amputation = "A body part is cut or torn off, in whole or in part.",
    fracture = "A bone is broken or cracked.",
    `crushing injury` = "A body part is squeezed hard between objects, and the tissue is damaged.",
    `thermal burn` = "Heat, flame, hot liquid or a hot surface burns the skin.",
    concussion = "A blow or a shake to the head hurts the brain."
  )
)
```

## Three models

[`purrr::map()`](https://purrr.tidyverse.org/reference/map.html) runs
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
once for each decider. One call of
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
uses one model. The list `deciders` is named, so the list of answers is
named too.

``` r

deciders <- list(
  jev = decider_typesafe(),
  microsoft = decider_openrouter("microsoft/microsoft-decision-1"),
  openai = decider_openai()
)

answers <- purrr::map(deciders, \(decider) decide(decider, nature, text = injuries$final_narrative))
```

Each element of `answers` is a tibble with 75 rows, in the order of the
narratives. We bind the three tibbles and add the truth.

``` r

results <- answers |>
  dplyr::bind_rows(.id = "model") |>
  dplyr::mutate(truth = rep(injuries$collapsed_nature_title, times = length(answers)))
```

The levels of `.pred_class` are the five answers, as in `truth`. A name
with a space gives a probability column with a clean name:
`crushing injury` gives `.pred_crushing_injury`.

``` r

grep("^\\.pred_", names(results), value = TRUE)
#> [1] ".pred_class"           ".pred_amputation"      ".pred_fracture"        ".pred_crushing_injury"
#> [5] ".pred_thermal_burn"    ".pred_concussion"
```

## Performance

yardstick reads the columns that
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
returns. `accuracy()` compares `truth` with `.pred_class`. `roc_auc()`
takes the five probability columns, in the order of the levels of
`truth`. With more than two classes, it computes the multiclass ROC AUC
of Hand and Till.

``` r

metrics <- yardstick::metric_set(yardstick::accuracy, yardstick::roc_auc)

results |>
  dplyr::group_by(model) |>
  metrics(
    truth,
    .pred_amputation, .pred_fracture, .pred_crushing_injury, .pred_thermal_burn, .pred_concussion,
    estimate = .pred_class
  ) |>
  dplyr::select(model, .metric, .estimate)
#> # A tibble: 6 × 3
#>   model     .metric  .estimate
#>   <chr>     <chr>        <dbl>
#> 1 jev       accuracy     0.96 
#> 2 microsoft accuracy     0.947
#> 3 openai    accuracy     0.987
#> 4 jev       roc_auc      1    
#> 5 microsoft roc_auc      1    
#> 6 openai    roc_auc      1
```

A row with an error has `NA` answers, and yardstick removes it. The
table shows how many rows each model answered.

``` r

results |>
  dplyr::group_by(model) |>
  dplyr::summarise(rows = dplyr::n(), errors = sum(!is.na(.error)))
#> # A tibble: 3 × 3
#>   model      rows errors
#>   <chr>     <int>  <int>
#> 1 jev          75      0
#> 2 microsoft    75      0
#> 3 openai       75      0
```

The confusion matrix of each model shows the counts. The rows are the
answers of the model, and the columns are the truth.

``` r

results |>
  split(results$model) |>
  purrr::map(\(x) yardstick::conf_mat(x, truth, .pred_class)$table)
#> $jev
#>                  Truth
#> Prediction        amputation fracture crushing injury thermal burn concussion
#>   amputation              19        0               0            0          0
#>   fracture                 0       20               0            0          1
#>   crushing injury          1        0              14            1          0
#>   thermal burn             0        0               0           14          0
#>   concussion               0        0               0            0          5
#> 
#> $microsoft
#>                  Truth
#> Prediction        amputation fracture crushing injury thermal burn concussion
#>   amputation              17        0               0            0          0
#>   fracture                 0       20               0            0          0
#>   crushing injury          3        0              14            1          0
#>   thermal burn             0        0               0           14          0
#>   concussion               0        0               0            0          6
#> 
#> $openai
#>                  Truth
#> Prediction        amputation fracture crushing injury thermal burn concussion
#>   amputation              20        0               0            0          0
#>   fracture                 0       20               0            0          1
#>   crushing injury          0        0              14            0          0
#>   thermal burn             0        0               0           15          0
#>   concussion               0        0               0            0          5
```

All three models do well on this task, and their scores differ by a few
reports. Seventy-five narratives and small groups give a rough
comparison only. The group `concussion` has 6 reports, so one report
changes its share by 17 points. Use more rows before you choose a model
for real work.

## Cost and time

Each provider reports different things. OpenRouter reports the cost of
each call. TypeSafe and OpenAI report none, so `.cost` is `NA` for them,
and
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
prints one message about it. All three report the input tokens.
`.seconds` is the time of one response. The requests run in parallel, so
these times do not add up to the time of the whole call.

``` r

results |>
  dplyr::group_by(model) |>
  dplyr::summarise(
    input_tokens = sum(.input_tokens, na.rm = TRUE),
    cost_usd = if (all(is.na(.cost))) NA_real_ else sum(.cost, na.rm = TRUE),
    median_seconds = median(.seconds, na.rm = TRUE)
  )
#> # A tibble: 3 × 4
#>   model     input_tokens  cost_usd median_seconds
#>   <chr>            <dbl>     <dbl>          <dbl>
#> 1 jev              36122 NA                0.0908
#> 2 microsoft        12885  0.000541         0.192 
#> 3 openai           18670 NA                0.156
```

The prices of the providers differ. To compare the cost, take the input
tokens and the price list of each provider.
