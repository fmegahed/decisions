# Open models on your own computer

``` r

library(decisions)
```

## Overview

Laya is an open decision model from Convai Innovations (Apache 2.0
license). It runs on a CPU. You start a server on your computer, and the
decisions package talks to it. The texts stay on your computer. No key
is needed, and a call has no cost.

Laya speaks the SystemOne format, as Jev does. So only the decider
changes. The questions and the call of
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
stay the same.

Laya reads text only. It does not read images.

The results below come from a live run on a CPU. The package saved them
in `inst/extdata`, so this vignette builds without Laya and without a
network. The code that made them is in `data-raw/vignette_results.R`.

## Install

Laya needs Python. The commands below make an environment and install
the server. They do not run when this vignette builds.

``` sh
conda create -y -n laya python=3.11
conda activate laya
pip install "laya[serve]"
```

## Start

Set the device and the port, then start the server. The first start
downloads three checkpoints from Hugging Face (`english`, `multilingual`
and `typed-decisions`) and loads them. On our computer, the start took
about one minute.

``` sh
LAYA_DEVICE=cpu LAYA_PORT=8000 laya-serve
```

In PowerShell, set the variables first:

``` powershell
$env:LAYA_DEVICE = "cpu"
$env:LAYA_PORT = "8000"
laya-serve
```

The server is ready when the health check answers.

``` sh
curl http://localhost:8000/health
```

To stop the server, press Ctrl+C in its window.

## Decider

[`decider_systemone()`](https://fmegahed.github.io/decisions/reference/decider_systemone.md)
takes the URL of the server and the name of a checkpoint. Only the URL
and the model differ from the Jev decider of the other vignettes. The
decider sends no key, because it has no `credentials`. `input = "text"`
makes
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
stop if you give it an image.

``` r

laya <- decider_systemone("http://localhost:8000", "english", input = "text")
laya
#> <decider> The server at http://localhost:8000
#> * Model: english
#> * URL: http://localhost:8000/v1/systemone
#> * Request format: systemone
#> * Input: text
```

## Data and questions

This vignette stands alone, so it defines the tickets and the questions
again. They are the same as in the vignette “Getting started with text”.
We wrote the tickets for these vignettes.

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

## Decisions

One call of
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
asks the three questions about the ten tickets. We set `max_active = 1`,
so the server gets one request at a time. Then `.seconds` is the time
that the CPU needs for one request. With more active requests, the
requests wait for each other on a CPU.

``` r

answers <- decide(
  laya,
  list(refund = refund, topic = topic, urgency = urgency),
  text = tickets$text,
  max_active = 1
)
```

[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
prints one message, because Laya does not report a cost. The message
says that the server at `http://localhost:8000` reports no cost, that
`.cost` is `NA`, and that `.input_tokens` has the input tokens. The
model that the server reports is `laya-rl-agent`, whatever the
checkpoint.

``` r

dplyr::bind_cols(
  tickets["ticket"],
  answers[c("refund_.pred_class", "topic_.pred_class", "urgency_.pred_class", ".seconds")]
)
#> # A tibble: 10 × 5
#>    ticket refund_.pred_class topic_.pred_class urgency_.pred_class .seconds
#>     <int> <fct>              <fct>             <fct>                  <dbl>
#>  1      1 true               billing           medium                 0.461
#>  2      2 false              shipping          medium                 0.713
#>  3      3 false              technical         medium                 0.501
#>  4      4 false              shipping          medium                 0.478
#>  5      5 true               technical         medium                 0.448
#>  6      6 false              technical         medium                 0.418
#>  7      7 true               billing           medium                 0.465
#>  8      8 true               shipping          low                    0.485
#>  9      9 false              billing           medium                 0.477
#> 10     10 false              shipping          medium                 0.463
```

## Time

``` r

dplyr::summarise(
  answers,
  rows = dplyr::n(),
  errors = sum(!is.na(.error)),
  input_tokens = sum(.input_tokens),
  median_seconds = median(.seconds),
  max_seconds = max(.seconds)
)
#> # A tibble: 1 × 5
#>    rows errors input_tokens median_seconds max_seconds
#>   <int>  <int>        <dbl>          <dbl>       <dbl>
#> 1    10      0         1966          0.471       0.713
```

This small model on a CPU does not get every ticket right. The tables
show speed and format, not accuracy.

A request with three questions takes a fraction of a second on this CPU.
Your time depends on your computer.

## Privacy

[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
sends each text to the URL of the decider. With `http://localhost:8000`,
the text goes to your own computer and to no one else. Use a local
server when the texts are private.
