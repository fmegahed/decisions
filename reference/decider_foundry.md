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
  time [`decide()`](decide.md) sends requests.

- input:

  The input type that the model reads: `"text"`, `"image"` or
  `"text+image"`. `NULL` (the default) takes it from the internal table
  of input types; a model that is not in the table is not checked.
  [`decide()`](decide.md) stops before any request when an input does
  not fit.

## Value

A decider object for [`decide()`](decide.md). It holds no key.

## Details

The requests go to `<endpoint>/providers/microsoft/v1/systemone` with
the key in the `api-key` header. This release takes an API key only: a
Microsoft Entra ID token, which goes in an `Authorization` header, does
not work. This decider is not yet tested with a live call.
Microsoft-Decision-1 reads text only.

## Examples

``` r
decider_foundry("https://my-resource.services.ai.azure.com", "decision-1")
#> <decider> Microsoft Foundry
#> * Model: decision-1
#> * URL: https://my-resource.services.ai.azure.com/providers/microsoft/v1/systemone
#> * Request format: systemone
#> * Input: text
```
