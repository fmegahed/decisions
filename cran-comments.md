## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Test environments

* Local: Windows 11, R 4.6.1 (`devtools::check(args = "--as-cran", remote = TRUE, manual = TRUE)`)
* GitHub Actions on the pushed repository: TO FILL (fmm), after the push

## Notes

The package calls paid web APIs only when the user gives a key. Examples that
call them are in `\dontrun{}` and do not run. The tests use saved responses
and make no network call. The vignettes read saved results from
`inst/extdata` and need no key.
