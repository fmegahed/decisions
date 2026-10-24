## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Test environments

* Local: Windows 11, R 4.6.1 (`devtools::check(args = "--as-cran", remote = TRUE, manual = TRUE)`)
* GitHub Actions (R CMD check, all Status: OK):
  * macOS (aarch64), R 4.6.1
  * Windows (x86_64), R 4.6.1
  * Ubuntu 24.04 (x86_64), R-devel (2026-10-23 r90760), R 4.6.1 and R 4.5.3
* win-builder: TO FILL (fmm). Paste the result of `devtools::check_win_devel()` and `devtools::check_win_release()`.
* R-hub: TO FILL (fmm). Paste the platforms and results of `rhub::rhub_check()`.

## Notes

The package calls paid web APIs only when the user gives a key. Examples that
call them are in `\dontrun{}` and do not run, because they need an API key and
a paid call. The tests use saved responses and make no network call. The
vignettes read saved results from `inst/extdata` and need no key.

Possibly misspelled words in DESCRIPTION: Apley, Bui. These are the names of
the authors of the reference (Bui and Apley, 2021), spelled correctly.

Three URLs answer HTTP 403 to automated clients and open in a browser:
<https://www.osha.gov/severe-injury-reports>, <https://platform.openai.com> and
<https://console.typesafe.ai/>. The URLs are valid.

The vignette `industrial-image-inspection` names the license of the AutoVI
images (CC BY-NC-SA 4.0). The package holds no AutoVI image. The file
`inst/extdata/study_sets.csv` holds only relative file names and labels.

No published paper describes the decision-model method of the package, so the
Description has no method reference. It cites only the source of the textile
images.
