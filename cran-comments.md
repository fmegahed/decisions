This is an update of decisions 0.1.0. It fixes the installation ERROR on the
CRAN check page (7 platforms since S7 1.0.0: "object 'decider' not found").
The decider of a setup is now a required S7 property, so S7 no longer makes
a default for it from the name of its class.

## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

* Local: Windows 11, R 4.6.1: `R CMD check --as-cran` with S7 1.0.0 (Status: OK)
  and with S7 0.2.2 (0 errors | 0 warnings | 0 notes).
* GitHub Actions (R CMD check, all pass): macOS R-release; Windows R-release;
  Ubuntu R-devel, R-release and R-oldrel-1.
* R-hub (https://github.com/fmegahed/decisions/actions/runs/45480137384):
  Linux, Windows, macOS and macOS arm64 (R-devel), and the nosuggests
  container: all pass.
* win-builder: R-devel (2026-11-17 r90926 ucrt): Status OK. R-release
  (4.6.2 ucrt): 1 NOTE, a timeout for one URL. R-oldrelease (4.5.3 ucrt):
  1 NOTE, HTTP 403 for two URLs. See Notes.

## Notes

On win-builder R-release, <https://isa401-review.vercel.app> (vignette
`grading`) did not answer within 60 seconds. The URL is valid: it answered
HTTP 200 in under one second on 2026-11-25, and the R-devel check on
win-builder found no problem with it.

Three URLs answer HTTP 403 to automated clients and open in a browser:
<https://www.osha.gov/severe-injury-reports>, <https://platform.openai.com> and
<https://console.typesafe.ai/>. On win-builder R-oldrelease, the first and the
last gave the NOTE. The URLs are valid: both answered HTTP 200 to a browser on
2026-11-25.

The package calls paid web APIs only when the user gives a key. Examples that
call them are in `\dontrun{}` and do not run, because they need an API key and
a paid call. The tests use saved responses and make no network call. The
vignettes read saved results from `inst/extdata` and need no key.

The vignette `industrial-image-inspection` names the license of the AutoVI
images (CC BY-NC-SA 4.0). The package holds no AutoVI image. The file
`inst/extdata/study_sets.csv` holds only relative file names and labels.

No published paper describes the decision-model method of the package, so the
Description has no method reference. It cites only the source of the textile
images.
