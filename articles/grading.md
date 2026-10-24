# Grading short answers with a rubric

``` r

library(decisions)
```

## Overview

A rubric lists the ideas that a good answer has. A decision model can
check each idea with a true-or-false question. You can also list the
wrong claims that students often make, and check them in the same way.

This vignette checks short answers to one question about this package:

> What does
> [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
> do when one call of a batch fails?

A good answer has four ideas:

- The failed input keeps its row in the output.
- The answers of that row are `NA`.
- The reason of the failure is in the `.error` column.
- The other inputs of the batch still get their answers.

Two wrong claims are common:

- [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
  stops with an error, or returns nothing, when one call fails.
- [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
  removes the row of the failed input.

We make one
[`question_noul()`](https://fmegahed.github.io/decisions/reference/question_noul.md)
for each idea and for each wrong claim. All six questions go into one
call of
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md),
so a student answer costs one call.

The results below come from live calls. The package saved them in the
package folder `extdata`, so this vignette builds without a key and
without a network. The code that made them is in `vignette_results.R` in
the folder `data-raw` of the [GitHub
repository](https://github.com/fmegahed/decisions).

## Rubric

The instructions of each question refer to the text, which is the answer
of the student.

``` r

rubric <- list(
  keeps_row = question_noul("Does the text say that the failed input keeps its row in the output?"),
  na_answers = question_noul("Does the text say that the answers of the failed row are NA?"),
  error_text = question_noul("Does the text say that the reason of the failure is in the .error column?"),
  others_continue = question_noul("Does the text say that the other inputs of the batch still get their answers?"),
  stops_all = question_noul("Does the text say that decide() stops with an error, or returns nothing, when one call fails?"),
  drops_row = question_noul("Does the text say that decide() removes the failed input from the output?")
)
```

The student sees only words of the rubric. For each question, we write
what the student sees when the probability is above the threshold of the
question (`if_above`), and when it is below (`if_below`). `NA` means
that the student sees nothing.

``` r

rubric_text <- tibble::tribble(
  ~question, ~kind, ~if_above, ~if_below,
  "keeps_row", "idea", "Covered: the failed input keeps its row.", "Missing: say what happens to the row of the failed input.",
  "na_answers", "idea", "Covered: the answers of the failed row are NA.", "Missing: say what the answers of the failed row are.",
  "error_text", "idea", "Covered: the reason is in the .error column.", "Missing: say where to find the reason of the failure.",
  "others_continue", "idea", "Covered: the other inputs still get their answers.", "Missing: say what happens to the other inputs.",
  "stops_all", "wrong", "Check again: one failed call does not stop decide().", NA_character_,
  "drops_row", "wrong", "Check again: decide() does not remove the row of a failed call.", NA_character_
)
```

## Sample answers

We wrote 20 sample answers for this vignette. The package has them as
the dataset `rubric_answers`, with the labels. Some answers are good,
some have wrong claims, and some are vague. For each answer, we also
wrote a label for each question: `TRUE` if the answer says it, `FALSE`
if not.

``` r

samples <- rubric_answers
samples[1:3, ]
#> # A tibble: 3 × 8
#>   answer_id answer               keeps_row na_answers error_text others_continue stops_all drops_row
#>       <int> <chr>                <lgl>     <lgl>      <lgl>      <lgl>           <lgl>     <lgl>    
#> 1         1 decide() keeps the … TRUE      TRUE       TRUE       TRUE            FALSE     FALSE    
#> 2         2 The failed input st… TRUE      TRUE       TRUE       FALSE           FALSE     FALSE    
#> 3         3 It stops and throws… FALSE     FALSE      FALSE      FALSE           TRUE      FALSE
```

## Setup

[`decision_setup()`](https://fmegahed.github.io/decisions/reference/decision_setup.md)
holds the decider and the six questions. We use Jev. It reads the key
from `TYPESAFE_API_KEY`. The saved results below come from the model
`jev-1.14.0`, which the default `"jev-latest"` named on 2026-10-23. In
real grading, give the model a fixed version (for example
`decider_typesafe("jev-1.14.0")`), so that the answers do not change
when the default model changes.

``` r

setup <- decision_setup(decider_typesafe(), rubric)
#> Using model = "jev-latest".
```

[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
takes the setup in place of the decider and the questions. The answers
are the only input.

``` r

scored <- decide(setup, text = samples$answer)
```

Each question gives its own columns. The column `keeps_row_.pred_true`
is the probability that the answer says it.

``` r

dplyr::select(scored, dplyr::ends_with("_.pred_true"), .error)
#> # A tibble: 20 × 7
#>    keeps_row_.pred_true na_answers_.pred_true error_text_.pred_true others_continue_.pred_true
#>                   <dbl>                 <dbl>                 <dbl>                      <dbl>
#>  1                 0.93                  0.99                  0.98                       0.97
#>  2                 0.96                  0.98                  0.94                       0.18
#>  3                 0.03                  0.04                  0.05                       0.05
#>  4                 0.03                  0.06                  0.04                       0.13
#>  5                 0.56                  0.8                   0.09                       0.76
#>  6                 0.7                   0.09                  0.45                       0.69
#>  7                 0.04                  0.03                  0.03                       0.06
#>  8                 0.06                  0.06                  0.03                       0.03
#>  9                 0.97                  0.95                  0.96                       0.28
#> 10                 0.54                  0.97                  0.04                       0.71
#> 11                 0.02                  0.07                  0.03                       0.44
#> 12                 0.97                  0.05                  0.33                       0.55
#> 13                 0.06                  0.04                  0.03                       0.1 
#> 14                 0.1                   0.07                  0.04                       0.81
#> 15                 0.5                   0.98                  0.98                       0.12
#> 16                 0.65                  0.83                  0.03                       0.95
#> 17                 0.05                  0.06                  0.09                       0.06
#> 18                 0.92                  0.98                  0.88                       0.91
#> 19                 0.15                  0.07                  0.04                       0.19
#> 20                 0.57                  0.07                  0.19                       0.16
#> # ℹ 3 more variables: stops_all_.pred_true <dbl>, drops_row_.pred_true <dbl>, .error <chr>
```

## Thresholds

A probability is not a grade. For each question, we choose a threshold:
the answer counts as “says it” when the probability is at or above the
threshold. For each question,
[`yardstick::roc_curve()`](https://yardstick.tidymodels.org/reference/roc_curve.html)
gives the sensitivity and the specificity at each threshold. We take the
thresholds that maximize `sensitivity + specificity - 1`, and then the
median of them.

``` r

thresholds <- purrr::map(names(rubric), \(question) {
  tibble::tibble(
    truth = factor(samples[[question]], levels = c(TRUE, FALSE)),
    probability = scored[[paste0(question, "_.pred_true")]]
  ) |>
    yardstick::roc_curve(truth, probability) |>
    dplyr::mutate(j = sensitivity + specificity - 1) |>
    dplyr::filter(dplyr::near(j, max(j)), is.finite(.threshold)) |>
    dplyr::summarise(threshold = median(.threshold), j = max(j))
}) |>
  purrr::set_names(names(rubric)) |>
  dplyr::bind_rows(.id = "question")

thresholds
#> # A tibble: 6 × 3
#>   question        threshold     j
#>   <chr>               <dbl> <dbl>
#> 1 keeps_row            0.5  0.75 
#> 2 na_answers           0.8  1    
#> 3 error_text           0.19 1    
#> 4 others_continue      0.69 0.875
#> 5 stops_all            0.32 1    
#> 6 drops_row            0.36 1
```

Twenty answers are few, and we set the thresholds on the same answers
that we use to check them. So the thresholds are rough. Use more labeled
answers for a real course, and keep some of them to check the
thresholds.

We join the thresholds to the text of the rubric.

``` r

feedback_rubric <- rubric_text |>
  dplyr::left_join(thresholds[c("question", "threshold")], by = "question")

feedback_rubric
#> # A tibble: 6 × 5
#>   question        kind  if_above                                                  if_below threshold
#>   <chr>           <chr> <chr>                                                     <chr>        <dbl>
#> 1 keeps_row       idea  Covered: the failed input keeps its row.                  Missing…      0.5 
#> 2 na_answers      idea  Covered: the answers of the failed row are NA.            Missing…      0.8 
#> 3 error_text      idea  Covered: the reason is in the .error column.              Missing…      0.19
#> 4 others_continue idea  Covered: the other inputs still get their answers.        Missing…      0.69
#> 5 stops_all       wrong Check again: one failed call does not stop decide().      NA            0.32
#> 6 drops_row       wrong Check again: decide() does not remove the row of a faile… NA            0.36
```

## Feedback

`give_feedback()` takes the output of
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
for one answer and the rubric. It returns the lines that the student
sees. It never shows a probability. When the call failed, it says so and
shows no provider text.

``` r

give_feedback <- function(scored, rubric) {
  if (!is.na(scored$.error)) {
    return("The check did not work. Try again.")
  }
  probability <- purrr::map_dbl(rubric$question, \(question) scored[[paste0(question, "_.pred_true")]])
  lines <- ifelse(probability >= rubric$threshold, rubric$if_above, rubric$if_below)
  lines[!is.na(lines)]
}
```

Here are three new answers.

``` r

new_answers <- c(
  "The row of the failed call stays in the output. Its answers are NA, and .error has the reason.",
  "decide() stops with an error at the first failed call, and you get nothing back.",
  "It keeps going with the other inputs."
)

new_scored <- decide(setup, text = new_answers)

purrr::map(seq_along(new_answers), \(i) give_feedback(new_scored[i, ], feedback_rubric))
```

    #> [[1]]
    #> [1] "Covered: the failed input keeps its row."      
    #> [2] "Covered: the answers of the failed row are NA."
    #> [3] "Covered: the reason is in the .error column."  
    #> [4] "Missing: say what happens to the other inputs."
    #> 
    #> [[2]]
    #> [1] "Missing: say what happens to the row of the failed input."
    #> [2] "Missing: say what the answers of the failed row are."     
    #> [3] "Missing: say where to find the reason of the failure."    
    #> [4] "Missing: say what happens to the other inputs."           
    #> [5] "Check again: one failed call does not stop decide()."     
    #> 
    #> [[3]]
    #> [1] "Missing: say what happens to the row of the failed input."
    #> [2] "Missing: say what the answers of the failed row are."     
    #> [3] "Missing: say where to find the reason of the failure."    
    #> [4] "Missing: say what happens to the other inputs."

## Setup file

[`write_setup()`](https://fmegahed.github.io/decisions/reference/write_setup.md)
saves the decider and the questions as one JSON file. The file holds no
key.

``` r

write_setup(setup, "rubric_setup.json")
```

The thresholds and the text of the rubric are not part of the setup.
Save them as well.

``` r

saveRDS(feedback_rubric, "rubric.rds")
```

## Shiny app

The app below lets a student type an answer and press a button. It shows
the rubric text. It uses shiny, which the package does not need. Save
`give_feedback()` in the file `R/feedback.R` of the app folder. Shiny
reads that folder by itself. Put `rubric_setup.json` and `rubric.rds` in
the app folder too. The app needs R 4.3 or newer, because it uses `@` on
S7 objects, and the purrr package, because `give_feedback()` uses it.

[`read_setup()`](https://fmegahed.github.io/decisions/reference/read_setup.md)
takes a `credentials` function. The function runs when
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
sends the requests. So the host of the app gives the key. On Posit
Connect, for example, you set the variable `TYPESAFE_API_KEY` in the
settings of the content. The key is a secret of the host. It is never a
field of the app and never in the file.

``` r

library(shiny)
library(decisions)

rubric <- readRDS("rubric.rds")

ui <- fluidPage(
  titlePanel("Check your answer"),
  p("What does decide() do when one call of a batch fails?"),
  textAreaInput("answer", "Your answer", width = "100%", rows = 6),
  actionButton("check", "Check"),
  textOutput("provider"),
  uiOutput("feedback")
)

server <- function(input, output, session) {
  # Replace the function with the key source of your host
  setup <- read_setup("rubric_setup.json", credentials = \() Sys.getenv("TYPESAFE_API_KEY"))

  output$provider <- renderText(
    paste0("Your answer goes to ", setup@decider@provider, " (", setup@decider@base_url, ").")
  )

  output$feedback <- renderUI({
    req(nzchar(input$answer))
    scored <- decide(setup, text = input$answer)
    tags$ul(lapply(give_feedback(scored, rubric), tags$li))
  }) |>
    bindEvent(input$check)
}

shinyApp(ui, server)
```

## Privacy

The answer of the student goes to the provider that the decider names.
With Jev, that is TypeSafe. The app shows the provider, so the student
knows. Read the terms of the provider before you send student work to
it. To keep the answers on your computer, use a local model. Set the
setup to
[`decider_systemone()`](https://fmegahed.github.io/decisions/reference/decider_systemone.md)
with a Laya server, as the vignette “Open models on your own computer”
shows. Then the answers never leave the computer.

## Credits

- Jeffrey Biles of PhysicsGraph had the idea to check an explanation
  while the student types it
  (<https://x.com/JeffreyBiles/status/2107211222320021722>).
- The course ISA 401 of Fadel Megahed at Miami University gave the use
  case.
- The exam-review game of the course
  (<https://isa401-review.vercel.app>,
  <https://github.com/fmegahed/isa401/tree/main/games/exam-review>) is
  an example of such a tool.
