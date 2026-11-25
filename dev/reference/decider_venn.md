# Use Venn on your computer

Makes a decider for a local Venn server (venn-vdm, a research preview by
Mark Russinovich, <https://markrussinovich.github.io/venn-vdm/>). Venn
answers noul, choice and score questions about a text, or about one
image, with a small decision head on the reader EmbeddingGemma 2. It
needs no key and makes no paid call.

## Usage

``` r
decider_venn(
  model = "venn-1",
  base_url = "http://127.0.0.1:8000",
  input = NULL
)
```

## Arguments

- model:

  The model name: `"venn-1"` (the default).

- base_url:

  The server root. The requests go to `<base_url>/api/alpha/decisions`.

- input:

  The input type that the model reads: `"text"`, `"image"` or
  `"text+image"`. `NULL` (the default) takes it from the internal table
  of input types; a model that is not in the table is not checked.
  [`decide()`](https://fmegahed.github.io/decisions/dev/reference/decide.md)
  stops before any request when an input does not fit.

## Value

A decider object for
[`decide()`](https://fmegahed.github.io/decisions/dev/reference/decide.md).

## Details

Venn needs Python 3.12. Install and start it from a clone of
<https://github.com/markrussinovich/venn-vdm>:

    python -m pip install torch --index-url https://download.pytorch.org/whl/cpu
    python -m pip install ".[embedding]"
    venn download-embedder
    venn serve --host 127.0.0.1 --port 8000

The server is ready when `http://127.0.0.1:8000/health` shows
`"reader":"ready"`.

Venn is a research preview with an alpha endpoint. Its server answers
one request at a time, on the CPU, so `max_active` of
[`decide()`](https://fmegahed.github.io/decisions/dev/reference/decide.md)
gives no speed-up. Its probabilities are not calibrated: give the setup
a calibrator (see
[`decision_setup()`](https://fmegahed.github.io/decisions/dev/reference/decision_setup.md)).
It reports no tokens and no cost, so `.input_tokens` and `.cost` are
`NA`.

Images are experimental in Venn:
[`decide()`](https://fmegahed.github.io/decisions/dev/reference/decide.md)
sends one image in each request with the header
`X-Venn-Experimental: media`. Without reference images, Venn was at
chance on the `textiles` data (AUC 0.48).
[`decide()`](https://fmegahed.github.io/decisions/dev/reference/decide.md)
stops before any request for an input with a text and an image (Venn
would ignore the text) and for reference images (not supported).

## See also

Other deciders:
[`decider_foundry()`](https://fmegahed.github.io/decisions/dev/reference/decider_foundry.md),
[`decider_gemini()`](https://fmegahed.github.io/decisions/dev/reference/decider_gemini.md),
[`decider_openai()`](https://fmegahed.github.io/decisions/dev/reference/decider_openai.md),
[`decider_openrouter()`](https://fmegahed.github.io/decisions/dev/reference/decider_openrouter.md),
[`decider_systemone()`](https://fmegahed.github.io/decisions/dev/reference/decider_systemone.md),
[`decider_typesafe()`](https://fmegahed.github.io/decisions/dev/reference/decider_typesafe.md)

## Examples

``` r
decider_venn()
#> <decider> Venn
#> * Model: venn-1
#> * URL: http://127.0.0.1:8000/api/alpha/decisions
#> * Request format: venn
#> * Input: text+image
```
