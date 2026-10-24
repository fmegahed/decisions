# Sample answers for a rubric

Twenty sample answers to the question "What does [`decide()`](decide.md)
do when one call of a batch fails?", with a label for each question of
the rubric. We wrote the answers for the vignette "Grading short answers
with a rubric".

## Usage

``` r
rubric_answers
```

## Format

A tibble with 20 rows and 8 columns:

- answer_id:

  Integer. The number of the answer.

- answer:

  Character. The text of the answer.

- keeps_row:

  Logical. The answer says that the failed input keeps its row in the
  output.

- na_answers:

  Logical. The answer says that the answers of the failed row are `NA`.

- error_text:

  Logical. The answer says that the reason of the failure is in the
  `.error` column.

- others_continue:

  Logical. The answer says that the other inputs of the batch still get
  their answers.

- stops_all:

  Logical. The answer says that [`decide()`](decide.md) stops with an
  error, or returns nothing, when one call fails (a wrong claim).

- drops_row:

  Logical. The answer says that [`decide()`](decide.md) removes the
  failed input from the output (a wrong claim).

## Source

Written for this package. The labels are the labels of the author.

## Examples

``` r
rubric_answers[1:3, c("answer_id", "keeps_row", "stops_all")]
#> # A tibble: 3 × 3
#>   answer_id keeps_row stops_all
#>       <int> <lgl>     <lgl>    
#> 1         1 TRUE      FALSE    
#> 2         2 TRUE      FALSE    
#> 3         3 FALSE     TRUE     
```
