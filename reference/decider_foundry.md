# Use Microsoft-Decision-1 on Microsoft Foundry

Makes a decider for a deployment of Microsoft-Decision-1 on Microsoft
Foundry (SystemOne format).

## Usage

``` r
decider_foundry(
  endpoint = Sys.getenv("AZURE_FOUNDRY_ENDPOINT"),
  deployment,
  credentials = NULL,
  input = NULL
)
```

## Arguments

- endpoint:

  The endpoint of the Foundry resource, for example
  `"https://<resource>.services.ai.azure.com"`. The default reads the
  environment variable `AZURE_FOUNDRY_ENDPOINT`.

- deployment:

  The name of the deployment. It is the model name of the request.

- credentials:

  A function with no arguments that returns the key. `NULL` (the
  default) reads the environment variable `AZURE_FOUNDRY_API_KEY` each
  time
  [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
  sends requests. You generally should not need this argument. Set
  `AZURE_FOUNDRY_API_KEY` instead. The best place to set it is
  `.Renviron`. Open that file with `usethis::edit_r_environ()`. The
  usethis package is optional: you can also edit `.Renviron` by hand.
  Give a function for more control, for example to read the key from a
  secret store. The decider keeps the function, not the key.

- input:

  The input type that the model reads: `"text"`, `"image"` or
  `"text+image"`. `NULL` (the default) takes it from the internal table
  of input types; a model that is not in the table is not checked.
  [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
  stops before any request when an input does not fit.

## Value

A decider object for
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md).
It holds no key.

## Details

You need an Azure subscription and a Foundry resource with a deployment
of the model. Create them in [Microsoft Foundry](https://ai.azure.com).
Then set the environment variables `AZURE_FOUNDRY_ENDPOINT` (the
endpoint of the resource) and `AZURE_FOUNDRY_API_KEY` (a key of the
resource).

The requests go to `<endpoint>/providers/microsoft/v1/systemone` with
the key in the `api-key` header. This release takes an API key only: a
Microsoft Entra ID token, which goes in an `Authorization` header, does
not work. This decider is not yet tested with a live call.
Microsoft-Decision-1 reads text only.

## See also

Other deciders:
[`decider_openai()`](https://fmegahed.github.io/decisions/reference/decider_openai.md),
[`decider_openrouter()`](https://fmegahed.github.io/decisions/reference/decider_openrouter.md),
[`decider_systemone()`](https://fmegahed.github.io/decisions/reference/decider_systemone.md),
[`decider_typesafe()`](https://fmegahed.github.io/decisions/reference/decider_typesafe.md)

## Examples

``` r
decider_foundry("https://my-resource.services.ai.azure.com", "decision-1")
#> <decider> Microsoft Foundry
#> * Model: decision-1
#> * URL: https://my-resource.services.ai.azure.com/providers/microsoft/v1/systemone
#> * Request format: systemone
#> * Input: text
```
