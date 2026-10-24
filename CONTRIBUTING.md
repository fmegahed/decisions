# Contributing

Notes for fmm and future contributors.

## Tests without a key

The tests make no network call and need no key.

- Each test mocks the provider with `httr2::local_mocked_responses()`. The
  helper `record_requests()` in `tests/testthat/helper-requests.R` does this
  and keeps the requests, so a test can count and read them.
- The mocked answers are saved provider responses in
  `tests/testthat/fixtures/`. `fixture_response("<name>")` turns one file into
  an httr2 response. Do not edit a saved response by hand. Make it again from
  a real call.
- Tests use the fake key `"not-a-real-key"`. Never use a string that starts
  with `sk-`.

## Live tests

`tests/testthat/test-live.R` makes one tiny real call for each provider.
These calls cost money. A live test runs only when:

- `DECISIONS_LIVE_TESTS=true`, and
- the key variable of the provider is set (`TYPESAFE_API_KEY`,
  `OPENAI_API_KEY` or `OPENROUTER_API_KEY`).

Otherwise it skips and says why. To run them:

```r
Sys.setenv(DECISIONS_LIVE_TESTS = "true")
devtools::test(filter = "live")
```

The Laya test is free. It needs `DECISIONS_LIVE_LOCAL=true` and a Laya server
that answers `http://localhost:8000/health`. The test does not start a server.

The workflow `.github/workflows/live-api.yaml` runs the live tests by hand
only. It reads the three keys from repository secrets.

## Saved results of the vignettes

The vignettes make no call. They read saved results from `inst/extdata/`.

- `data-raw/vignette_results.R` runs the live code of vignettes 1 to 4 and
  the grading vignette, and saves the results.
- `data-raw/study_again.R` runs the pipeline of the vignette "study-again" in
  steps and saves the results.
- Each paid call appends one row to a call log through `data-raw/log_call.R`.
  A budget row must exist before you make a paid call.

## Keys

No key is ever written to a file. Scripts read keys with `Sys.getenv()`. Do
not print a key, put it in a setup file, or commit `.Renviron` or `.env`.
Before each commit, run `git grep -c -E "sk-|Bearer [A-Za-z0-9]"`. It must
print nothing.
