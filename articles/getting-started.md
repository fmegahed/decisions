# Getting started with text

``` r

library(decisions)
```

## Overview

A decision model reads an input and some typed questions. It returns a
probability for each allowed answer. The decisions package sends the
inputs to the model and gives you a tibble with one row per input.

This vignette uses short texts. It shows the three question types, one
input and then many inputs, and how to copy the agent skill of the
package.

The results below come from live calls. The package saved them in
`inst/extdata`, so this vignette builds without a key and without a
network. The code that made them is in `data-raw/vignette_results.R`.

## Data

The vignette uses ten support tickets. We wrote them for this vignette.

``` r

tickets <- tibble::tibble(
  ticket = 1:10,
  text = c(
    "I was charged twice for order 4471. Please refund the extra charge today.",
    "My parcel has not arrived. The tracking page has said 'in transit' for two weeks.",
    "The app crashes each time I open the settings page. I cannot log in, and I have a meeting in ten minutes.",
    "Thank you for the quick delivery. The product works well.",
    "I want my money back. The blender broke after one day.",
    "How do I change the email address on my account?",
    "The invoice shows the wrong company name. Please send a new one when you can.",
    "The package arrived with a broken seal. Please send a replacement. There is no hurry.",
    "Your website shows an error when I pay by card. I must order before the sale ends tonight.",
    "Can you tell me which sizes the jacket comes in?"
  )
)
```

## Decider

A decider names the provider and the model. Here we use Jev, a decision
model of TypeSafe. When you give no model, the function uses its default
model and prints its name, as ellmer does.

``` r

jev <- decider_typesafe()
#> Using model = "jev-latest".
jev
#> <decider> TypeSafe
#> * Model: jev-latest
#> * URL: https://api.typesafe.ai/v1/systemone
#> * Request format: systemone
#> * Input: text+image
```

The decider holds no key. [`decide()`](../reference/decide.md) reads the
key when it sends the requests. Put the key in the environment variable
`TYPESAFE_API_KEY`, for example in `~/.Renviron`. You can also give a
`credentials` function that returns the key:

``` r

jev <- decider_typesafe(credentials = \() Sys.getenv("MY_JEV_KEY"))
```

## Questions

A question has instructions and named answers. The package has three
types.

- [`question_noul()`](../reference/question_noul.md) has two answers,
  `true` and `false`.
- [`question_choice()`](../reference/question_choice.md) has two or more
  named choices. Each name is an allowed answer, and each value
  describes it.
- [`question_score()`](../reference/question_score.md) has ordered
  levels, from low to high.

``` r

refund <- question_noul("Does the customer ask for a refund?")

topic <- question_choice(
  "Which team should answer this ticket?",
  c(
    billing = "Charges, invoices and refunds.",
    shipping = "Parcels and delivery.",
    technical = "Errors, and how to use the product."
  )
)

urgency <- question_score(
  "How urgent is this ticket?",
  c(
    low = "The customer can wait several days.",
    medium = "The customer needs an answer today.",
    high = "The customer needs an answer now."
  )
)
```

## One input

[`decide()`](../reference/decide.md) takes the decider, the question and
a text. It returns a tibble with one row for the input.

``` r

one_noul <- decide(jev, refund, text = tickets$text[1])
one_noul
```

    #> # A tibble: 1 × 8
    #>   .pred_class .pred_true .pred_false .model     .input_tokens .cost .seconds .error
    #> * <fct>            <dbl>       <dbl> <chr>              <dbl> <dbl>    <dbl> <chr> 
    #> 1 true              0.99      0.0100 jev-1.14.0           299    NA    0.420 NA

TypeSafe does not report a cost. So [`decide()`](../reference/decide.md)
prints one message that says so, and `.cost` is `NA`. `.input_tokens`
has the input tokens.

The columns are:

- `.pred_class`: the answer with the highest probability. It is a
  factor. Its levels are the allowed answers, kept exactly as you wrote
  them.
- `.pred_true` and `.pred_false`: the probability of each allowed
  answer. There is one `.pred_` column for each answer. The column name
  is the answer with letters, digits and `_` only. For example, the
  answer `"not sure"` gives `.pred_not_sure`. The yardstick and probably
  packages read these columns.
- `.model`: the model that the provider reports.
- `.input_tokens`: the input tokens that the provider reports.
- `.cost`: the cost that the provider reports, or `NA`.
- `.seconds`: the time of the response.
- `.error`: `NA`, or the reason why the answers of the row are `NA`.

A choice question gives one `.pred_` column for each choice.

``` r

one_choice <- decide(jev, topic, text = tickets$text[2])
one_choice
```

    #> # A tibble: 1 × 9
    #>   .pred_class .pred_billing .pred_shipping .pred_technical .model     .input_tokens .cost .seconds
    #> * <fct>               <dbl>          <dbl>           <dbl> <chr>              <dbl> <dbl>    <dbl>
    #> 1 shipping                0              1               0 jev-1.14.0           363    NA    0.138
    #> # ℹ 1 more variable: .error <chr>

A score question gives one `.pred_` column for each level, and `.score`.
The score is the expected level: 0 is the lowest level.

``` r

one_score <- decide(jev, urgency, text = tickets$text[3])
one_score
```

    #> # A tibble: 1 × 10
    #>   .pred_class .pred_low .pred_medium .pred_high .score .model    .input_tokens .cost .seconds .error
    #> * <fct>           <dbl>        <dbl>      <dbl>  <dbl> <chr>             <dbl> <dbl>    <dbl> <chr> 
    #> 1 high                0            0          1      2 jev-1.14…           351    NA    0.135 NA

## Many inputs

Give a character vector to ask about many texts. The tibble has one row
for each text, in the same order. Every text keeps its row, also when a
call fails. A failed row has `NA` answers, and `.error` has the text of
the provider.

``` r

many_noul <- decide(jev, refund, text = tickets$text)
dplyr::bind_cols(tickets["ticket"], many_noul)
```

    #> # A tibble: 10 × 9
    #>    ticket .pred_class .pred_true .pred_false .model     .input_tokens .cost .seconds .error
    #>     <int> <fct>            <dbl>       <dbl> <chr>              <dbl> <dbl>    <dbl> <chr> 
    #>  1      1 true              0.99      0.0100 jev-1.14.0           299    NA    0.152 NA    
    #>  2      2 false             0.05      0.95   jev-1.14.0           299    NA    0.155 NA    
    #>  3      3 false             0.03      0.97   jev-1.14.0           305    NA    0.152 NA    
    #>  4      4 false             0.02      0.98   jev-1.14.0           292    NA    0.218 NA    
    #>  5      5 true              0.98      0.0200 jev-1.14.0           293    NA    0.196 NA    
    #>  6      6 false             0.01      0.99   jev-1.14.0           291    NA    0.141 NA    
    #>  7      7 false             0.04      0.96   jev-1.14.0           297    NA    0.168 NA    
    #>  8      8 false             0.03      0.97   jev-1.14.0           298    NA    0.169 NA    
    #>  9      9 false             0.03      0.97   jev-1.14.0           300    NA    0.153 NA    
    #> 10     10 false             0.01      0.99   jev-1.14.0           291    NA    0.142 NA

The requests go out in parallel. `.seconds` is the time of each
response.

## Two questions

Give a named list to ask more than one question about each text. The
names are the question names. The column names get the name of the
question and `_` as a prefix.

``` r

many_two <- decide(jev, list(topic = topic, urgency = urgency), text = tickets$text)
names(many_two)
```

    #>  [1] "topic_.pred_class"     "topic_.pred_billing"   "topic_.pred_shipping"  "topic_.pred_technical"
    #>  [5] "urgency_.pred_class"   "urgency_.pred_low"     "urgency_.pred_medium"  "urgency_.pred_high"   
    #>  [9] "urgency_.score"        ".model"                ".input_tokens"         ".cost"                
    #> [13] ".seconds"              ".error"

The request has all the questions, so each text costs one call, whatever
the number of questions.

``` r

dplyr::bind_cols(
  tickets["ticket"],
  many_two[c("topic_.pred_class", "urgency_.pred_class", "urgency_.score")]
)
#> # A tibble: 10 × 4
#>    ticket topic_.pred_class urgency_.pred_class urgency_.score
#>     <int> <fct>             <fct>                        <dbl>
#>  1      1 billing           medium                        1.07
#>  2      2 shipping          medium                        1.02
#>  3      3 technical         high                          2   
#>  4      4 shipping          low                           0   
#>  5      5 billing           medium                        1.18
#>  6      6 technical         low                           0.29
#>  7      7 billing           low                           0.23
#>  8      8 shipping          low                           0   
#>  9      9 technical         high                          1.88
#> 10     10 technical         low                           0.35
```

## Scores with known answers

The tickets have no known urgency. To check a score question, we need
data with a known ordered answer. The dataset `ohio_recalls` has food
recalls of firms in Ohio from the openFDA reports of the U.S. Food and
Drug Administration (FDA). The FDA puts each recall in one of three
classes, from low to high risk: Class III, Class II and Class I.

We take 30 recalls, 10 of each class. The text of a recall is its
product and its reason.

``` r

set.seed(2026)
recalls <- ohio_recalls |>
  dplyr::slice_sample(n = 10, by = classification) |>
  dplyr::mutate(
    text = paste0("Product: ", product_description, "\nReason: ", reason_for_recall)
  )
```

The levels of the question are the classes of the FDA, from low to high.
The descriptions are the definitions of 21 CFR 7.3(m) in plain words.

``` r

risk <- question_score(
  "How serious are the health consequences of using this recalled food?",
  c(
    `Class III` = "Using the food is not likely to cause adverse health consequences.",
    `Class II` = "Using the food may cause temporary or reversible health problems, or serious harm is remote.",
    `Class I` = "Using the food is likely to cause serious health problems or death."
  )
)
```

``` r

recall_out <- decide(jev, risk, text = recalls$text)
recall_out <- dplyr::bind_cols(recalls["classification"], recall_out)
```

The table counts the answers of the model against the class of the FDA.
Accuracy is the share of equal answers. The weighted kappa measures the
agreement of two ratings of ordered classes, beyond chance. The
quadratic weights count a miss of two classes more than a miss of one
class. A kappa of 1 is full agreement, and 0 is the agreement that
chance gives.

``` r

table(FDA = recall_out$classification, Jev = recall_out$.pred_class)
#>            Jev
#> FDA         Class III Class II Class I
#>   Class III         3        5       2
#>   Class II          0        7       3
#>   Class I           0        7       3
yardstick::accuracy(recall_out, classification, .pred_class)
#> # A tibble: 1 × 3
#>   .metric  .estimator .estimate
#>   <chr>    <chr>          <dbl>
#> 1 accuracy multiclass     0.433
yardstick::kap(recall_out, classification, .pred_class, weighting = "quadratic")
#> # A tibble: 1 × 3
#>   .metric .estimator .estimate
#>   <chr>   <chr>          <dbl>
#> 1 kap     multiclass     0.258
```

The column `.score` is the expected level of the question, as in the
ticket example. It is a number from 0, the lowest level (Class III), to
2, the highest level (Class I). It lies between two levels when the
model gives some probability to both. Here are two rows of each class.

``` r

recall_out |>
  dplyr::slice_head(n = 2, by = classification) |>
  dplyr::select(classification, .pred_class, .score)
#> # A tibble: 6 × 3
#>   classification .pred_class .score
#>   <ord>          <fct>        <dbl>
#> 1 Class II       Class I       1.57
#> 2 Class II       Class II      1.13
#> 3 Class I        Class II      1.32
#> 4 Class I        Class I       1.7 
#> 5 Class III      Class I       1.38
#> 6 Class III      Class II      1.29
```

The numbers are rough. The reason text alone does not always fix the
class, because the FDA also weighs the product and how far it went. A
sample of 30 recalls also gives wide error margins.

## Long runs

For a long run, give `path`, the path of a JSON file.
[`decide()`](../reference/decide.md) writes the finished answers to the
file. If the run stops, a new call with the same `path` sends only the
inputs that the file lacks.

``` r

decide(jev, refund, text = tickets$text, path = "refund-answers.json")
```

The file holds no key. If you change the model or a question,
[`decide()`](../reference/decide.md) stops and names the hash that does
not match.

## Agent skill

The package has a skill for coding agents. It explains how to write
questions, tune the descriptions of the answers, and run the one-time
test. Copy the folder of the skill into your project. Claude Code reads
`.claude/skills`. Other agents read `.agents/skills`.

``` r

skill <- system.file("skills", "decisions", package = "decisions")

# Claude Code
dir.create(".claude/skills", recursive = TRUE, showWarnings = FALSE)
file.copy(skill, ".claude/skills", recursive = TRUE)

# Other agents
dir.create(".agents/skills", recursive = TRUE, showWarnings = FALSE)
file.copy(skill, ".agents/skills", recursive = TRUE)
```
