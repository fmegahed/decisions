# The R package decisions: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the R package `decisions` (14 exported functions, an agent skill, six vignettes) in a local folder, test it end to end with real calls, and hand it to fmm for the vignette 5 test.

**Architecture:** S7 objects describe a model (`decider_*()`), its questions (`question_*()`) and a complete setup (`decision_setup()`). `decide()` turns inputs into one httr2 request each through a small translator per request format, sends them in parallel, and returns one tibble row per input. Setups are JSON files. Calibration is done by probably, outside the package. The vignettes carry the use cases.

**Tech Stack:** R (>= 4.1), httr2, S7, rlang, cli, tibble, jsonlite, purrr; magick and probably in Suggests; testthat 3e with `httr2::local_mocked_responses()`; roxygen2; knitr vignettes.

**Spec:** `replication_materials/plans/2026-10-23-decisions-package-design.md` (revision 3, approved as D183). Every decision ID below refers to `replication_materials/project/decisions.md`.

## Global Constraints

- Package name `decisions`. Folder `C:/Users/megahefm/Dropbox/Miami/Code/claude/decisions` (a sibling of `fine_tuned_jev`, never inside it). `git init` on branch `main`, no remote. Never push it; fmm makes the GitHub repository (D158).
- No replication record in the package folder (D158). Records of M3 go to `fine_tuned_jev/replication_materials/` and are committed there by the record rule.
- Exactly 14 exported functions (D160, D165, D164): `decider_typesafe()`, `decider_openai()`, `decider_foundry()`, `decider_openrouter()`, `decider_systemone()`, `question_noul()`, `question_choice()`, `question_score()`, `decide()`, `decision_setup()`, `write_setup()`, `read_setup()`, `score_setup()`, `evaluate_once()`. S3/S7 methods (`print()`) are allowed in addition.
- Imports: httr2, S7, rlang, cli, tibble, jsonlite, purrr. Suggests: magick, probably, testthat (>= 3.0.0), withr, knitr, rmarkdown, rsample, yardstick, dplyr. No compiled code. Not livelink, not shiny (D151, D165).
- One model per `decide()` call (D168). No spending cap, no budget, no cache, no prices, no size-limit checks (D159, D161, D162).
- `.cost` holds only a cost that the provider reports; otherwise `NA` and one message: `"<Provider> does not report a cost. `.cost` is NA. `.input_tokens` has the input tokens."` (D162).
- Retries: `httr2::req_retry()` with its defaults (HTTP 429 and 503) (D170).
- Each request puts the shared parts first (instructions, then references) and the input last (D171).
- Keys: `TYPESAFE_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `AZURE_FOUNDRY_API_KEY` (endpoint default `AZURE_FOUNDRY_ENDPOINT`); a `credentials` function overrides them (D143). No key in a printed object, a setup file, a `path` file or an error message.
- magick only for images; when it is missing, call `rlang::check_installed("magick", reason = "to read images")` (D176). probably only for calibration, with `rlang::check_installed("probably", reason = "to apply the calibrator of a setup")`.
- Code: correct, efficient, easy to follow; one job per function; no abstraction with one use; native pipe; `pkg::fun()` calls; purrr for loops (D181). roxygen2 documentation for every function, exported or internal, with `@param` (values in backticks), `@return`, `@details` when needed, `@export` only for the 14, `@examples` that run without a key or sit in `\dontrun{}` (D182).
- No text says that Jev, or any model, was the first decision model (D163).
- The package is cleaner and more efficient than the study code (D184). The study code (`fine_tuned_jev/R/`) tells what the package must do, not how to write it: do not copy its structure. In particular: prepare each reference image once per `decide()` call and reuse its bytes for every input (the study prepared them again for each image); keep images in memory (`magick::image_write()` to a raw vector, `jsonlite::base64_enc()`), with no temporary files and no base64enc dependency; send requests in parallel (the study sent them one by one); keep no call log in the package.
- CRAN: tests and vignettes make no network call and need no key; vignettes read saved results from `inst/extdata` (D177). `R CMD check --as-cran` ends with 0 errors, 0 warnings and at most the "New submission" note.
- Paid calls: none before fmm approves a row in `fine_tuned_jev/replication_materials/calls/README.md`. Every paid call of the build appends one row to `calls/<service>-calls.csv` (columns `time_utc,call_id,purpose,model,request_id,status,latency_ms,input_tokens,output_tokens,cost_usd`). The logging lives in `data-raw/`, never in the package.
- Run R with `"/c/Program Files/R/R-4.6.1/bin/Rscript.exe"`. Write R code to files; do not pass code with backslashes or quotes through `Rscript -e`.
- Before each commit in `fine_tuned_jev`, run the counts-only secret scan (`scratchpad/secret_scan_staged.R`). In the package folder, run `git grep -c -E "sk-|Bearer [A-Za-z0-9]"` before each commit; it must print nothing.

## Review Focus

1. A batch where some calls fail, some answers fall outside the allowed answers, and some succeed: every input keeps its row, in input order, with `NA` answers and the provider text in `.error` for the failures. (Task 6)
2. Images that are gray, CMYK, PNG with alpha, or rotated by EXIF: they arrive upright, in sRGB, as JPEG, with three channels when `image_format = "images"` (the SGLang server of Clef-Flash fails on one-channel JPEGs). (Task 4)
3. A rerun with the same `path` after one description changed: `decide()` stops with a message that names the hash mismatch and `ignore_hash`; it never reuses answers made with the old wording. (Task 7)
4. Text with quotes, newlines, non-ASCII letters and 5,000 characters: the JSON body round-trips exactly, and a provider refusal reaches `.error` word for word, with the model name and the request size. (Tasks 5, 6)
5. Answer names with spaces or punctuation (for example `"not sure"`): the factor levels equal the allowed answers, and the probability columns get syntactic names (`.pred_not_sure`, D189), so `probably` (whose logistic method builds a formula) and `yardstick` select them with `dplyr::starts_with(".pred_")`. (Tasks 3, 6)

---

### Task 1: Package skeleton

**Files:**
- Create: `decisions/DESCRIPTION`, `decisions/NAMESPACE` (roxygen), `decisions/LICENSE`, `decisions/LICENSE.md`, `decisions/R/decisions-package.R`, `decisions/tests/testthat.R`, `decisions/.Rbuildignore`, `decisions/.gitignore`, `decisions/NEWS.md`, `decisions/README.md`

**Interfaces:**
- Produces: an installable, checkable empty package.

- [ ] **Step 1:** Make the folder and `git init -b main`. Write `DESCRIPTION`: `Package: decisions`, `Version: 0.0.0.9000`, `Title: Typed Decisions from Decision Models`, `Authors@R: c(person("Fadel M.", "Megahed", role = c("aut", "cre"), email = "fmegahed@miamioh.edu"), person("Ying-Ju", "Chen", role = "aut"))` (D185; fmm adds an email or ORCID if wanted), `License: MIT + file LICENSE`, `Depends: R (>= 4.1)`, the Imports and Suggests of the Global Constraints, `Config/testthat/edition: 3`, `Encoding: UTF-8`, `Roxygen: list(markdown = TRUE)`, `VignetteBuilder: knitr`.
- [ ] **Step 2:** `R/decisions-package.R` holds the package doc (`"_PACKAGE"`) and `@importFrom S7 new_class new_object` style imports only where used. `.Rbuildignore`: `^data-raw$`, `^\.git`, `^README\.Rmd$`.
- [ ] **Step 3:** Run `devtools::document()` then `devtools::check(args = "--as-cran", error_on = "warning")`. Expected: 0 errors, 0 warnings.
- [ ] **Step 4:** Commit: `git add -A && git commit -m "Package skeleton"`.

### Task 2: Real responses of each provider (gate: budget rows)

**Files:**
- Create: `decisions/data-raw/probe_providers.R`, `decisions/data-raw/log_call.R`, `decisions/tests/testthat/fixtures/<provider>-<type>.json`
- Modify: `fine_tuned_jev/replication_materials/calls/README.md` (only after approval)

**Interfaces:**
- Produces: saved, key-free JSON responses that Tasks 5 and 6 use as fixtures, and a short note `data-raw/formats.md` with the verified request and response fields of each format.

- [ ] **Step 1 (stop point):** Propose budget rows in the chat, one per service: `typesafe`, `openai`, and `openrouter` or `foundry` (ask fmm which of the two the account has). Proposed size: 40 calls and USD 1 each. Write the rows only after fmm approves them (D153).
- [ ] **Step 2:** Start the local servers: `docker start clef-flash` (SGLang, `http://localhost:30000/v1/systemone`), and Laya with `laya-serve` in a new conda environment (`pip install "laya[serve]"`), on its documented port.
- [ ] **Step 3:** `probe_providers.R` sends, with plain httr2, one request per provider for each question type (noul, choice with 2 and 3 options, score with 3 levels), on a short text, and one image request for Jev, OpenAI and Clef-Flash. It saves each response body to `fixtures/` after removing request IDs that could identify the account, and it appends each call to the call log with `log_call.R`.
- [ ] **Step 4:** Write `data-raw/formats.md`: for each provider, the endpoint, the auth header, the question fields, the answer fields, where usage and cost appear, and whether a cost is reported. Mark each fact that differs from design section 3.2.
- [ ] **Step 5:** Commit the package files. Commit the call logs and the README row in `fine_tuned_jev` (record rule).

### Task 3: Questions

**Files:**
- Create: `decisions/R/questions.R`, `decisions/tests/testthat/test-questions.R`

**Interfaces:**
- Produces: S7 classes `question_noul`, `question_choice`, `question_score`, each with `instructions` (string) and `answers` (named character vector: answer → description). `question_noul(instructions, true = NULL, false = NULL)`; `question_choice(instructions, choices)`; `question_score(instructions, levels)` (levels in order, low to high).

- [ ] **Step 1: Failing tests.**
  - `question_choice("Which?", c(normal = "A clean part.", defective = "A visible defect."))@answers` equals that vector.
  - `question_choice("Which?", c("a", "b"))` errors with a message that mentions "named".
  - `question_score("How bad?", c(low = "x"))` errors (a score needs at least 2 levels).
  - `question_noul("Is it wet?")@answers` equals `c(true = NA, false = NA)`; with `true = "Wet."` it holds that text.
  - `question_choice("Which?", c("not sure" = "Unclear.", yes = "Yes."))@answers` keeps the name `"not sure"`.
- [ ] **Step 2:** Run `devtools::test(filter = "questions")`. Expected: FAIL, functions not found.
- [ ] **Step 3:** Implement the three constructors with S7 validators; roxygen for each.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 4: Image preparation

**Files:**
- Create: `decisions/R/images.R`, `decisions/tests/testthat/test-images.R`

**Interfaces:**
- Produces (internal): `prepare_image(image, max_size = 768, upscale = FALSE, crop = "none", rgb = FALSE)` → raw vector of JPEG bytes. `image` is a path, a URL or a magick image. `max_size = NULL` keeps the resolution (D142). `crop` is `"none"`, `"center"`, a numeric box `c(x, y, width, height)`, or a function(magick image) → box.
- Behavior to keep from `fine_tuned_jev/R/industrial_defect_classifier.R::prepare_image()`: orient, crop, resize, sRGB, optional TrueColor, JPEG quality 90. Write it fresh and in memory (D184); drop its temporary file, its 280 to 1568 checks and its padding (D161).

- [ ] **Step 1: Failing tests** (images made in the test with `magick::image_blank()`; `skip_if_not_installed("magick")`):
  - A 2000 x 1000 image with `max_size = 768` gives 768 x 384.
  - A 400 x 300 image with `upscale = FALSE` stays 400 x 300; with `upscale = TRUE` it gives 768 x 576.
  - `max_size = NULL` keeps 2000 x 1000.
  - `crop = "center"` on 2000 x 1000 gives a square; `crop = c(10, 10, 100, 50)` gives 100 x 50 before resizing; a crop function that returns `c(0, 0, 50, 50)` gives 50 x 50.
  - A gray image with `rgb = TRUE` reads back with 3 channels; a CMYK image and a PNG with an alpha channel come back as sRGB JPEG; an image with EXIF orientation 6 comes back upright (width and height swapped).
  - A missing path errors with the path in the message.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement; call `rlang::check_installed("magick", reason = "to read images")` first.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 5: Request translators

**Files:**
- Create: `decisions/R/formats.R`, `decisions/tests/testthat/test-formats.R`

**Interfaces:**
- Consumes: the question classes (Task 3), `prepare_image()` (Task 4), the fixtures and `data-raw/formats.md` (Task 2).
- Produces (internal), for each format `"systemone"`, `"systemone_images"`, `"openai"`, `"openrouter"`:
  - `build_body(format, model, questions, text, image, references)` → a list for `httr2::req_body_json()`. `image` and `references` are already prepared JPEG bytes. `references` is a named list: answer name → list of JPEG bytes.
  - `parse_answers(format, body, questions)` → `list(answers = <named list, one element per question: list(answer = chr, probabilities = named num)>, input_tokens = num, cost = num or NA)`.

- [ ] **Step 1: Failing tests.**
  - SystemOne: the body has `model`, `state`, `assets` and `questions`; a noul question has `type = "noul"`, a choice has `type = "choice"` with `criteria`; with references, each criterion has `description` and `examples`; in the JSON text, `instructions` and the reference assets come before the inspected asset (D171).
  - SystemOne with images: `images` is a list of `data:image/jpeg;base64,` strings, the inspected image last, and `state` names each image.
  - OpenAI: `questions` is an array with `name`; noul maps to `type = "predicate"`; choice uses `choices` with `value` and `description`; score uses `levels` with `label` and `description`.
  - Each saved fixture of Task 2 parses: the answer is one of the allowed answers, the probabilities sum to 1 within 1e-6 for choice and score, and `input_tokens` is a positive number.
  - A text with quotes, a newline, "é" and 5,000 characters survives `jsonlite::toJSON()` and back unchanged.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement one small `build_*()` and `parse_*()` pair per format, dispatched by `switch()`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 6: Deciders and decide()

**Files:**
- Create: `decisions/R/deciders.R`, `decisions/R/decide.R`, `decisions/R/input-types.R`, `decisions/tests/testthat/test-deciders.R`, `decisions/tests/testthat/test-decide.R`

**Interfaces:**
- Consumes: Tasks 3 to 5.
- Produces:
  - S7 class `decider` with properties `provider`, `format`, `base_url`, `model`, `image_format`, `input`, `credentials` (a function). Constructors: `decider_typesafe(model = NULL, credentials = NULL, input = NULL)` (default model `"jev-latest"`, printed when not given), `decider_openai(model = NULL, credentials = NULL, input = NULL)` (default `"gpt-6-luna"`), `decider_foundry(endpoint = Sys.getenv("AZURE_FOUNDRY_ENDPOINT"), deployment, credentials = NULL, input = NULL)`, `decider_openrouter(model, credentials = NULL, input = NULL)`, `decider_systemone(base_url, model, image_format = c("assets", "images"), credentials = NULL, input = NULL)`.
  - Internal table `input_types` (tibble: `provider`, `model`, `input`, `checked`), one dated row per model of design section 3.1.
  - `decide(decider, questions, text = NULL, image = NULL, references = NULL, max_size = 768, upscale = FALSE, crop = "none", max_active = 10, rpm = NULL, path = NULL, ignore_hash = FALSE)` → tibble. `decider` can be a setup (Task 8 adds that branch). `questions` is one question or a named list of questions. `references` is a named list, answer name → paths, URLs or magick images; `decide()` prepares them once per call with `prepare_image()` and passes the bytes to `build_body()`.
  - Output columns: for a single question `.pred_class` (factor, levels = the allowed answers) and `.pred_<answer>` for each answer; for several questions `<question>_.pred_class` and `<question>_.pred_<answer>`; then `.model`, `.input_tokens`, `.cost`, `.seconds`, `.error`.

- [ ] **Step 1: Failing tests** (mocked with `httr2::local_mocked_responses()` and the fixtures):
  - `print(decider_typesafe(credentials = \() "sk-secret"))` output does not contain `"sk-secret"`.
  - `decider_typesafe()` with no key set errors at `decide()` time with a message naming `TYPESAFE_API_KEY`.
  - `decider_typesafe()` prints a message naming `"jev-latest"`; `decider_typesafe("jev-1.13.0")` prints none.
  - `decide()` with an image and a decider whose `input = "text"` errors before any request (the mock counts 0 calls); with `input = "text+image"` it sends the request.
  - Three text inputs where the mock returns success, HTTP 500 with body `"model overloaded"`, and an answer outside the allowed answers: 3 rows in input order; row 2 has `NA` answers and `.error` containing `"model overloaded"`, the model name and the request size; row 3 has `NA` answers and an `.error` that names the bad answer.
  - A TypeSafe response without a cost: `.cost` is `NA` and the message `"TypeSafe does not report a cost. ..."` appears once for the whole call.
  - The TypeSafe request carries `TypeSafe-Danger-Zone-Images: true` only when an image is sent.
  - With `skip_if_not_installed("probably")`: `probably::cal_estimate_logistic(out, truth = truth)` runs on the output of a single choice question with two answers.
  - A choice question with the answers `"not sure"` and `"yes"`: `.pred_class` has the levels `c("not sure", "yes")`, and the columns are named `.pred_not sure` and `.pred_yes`, so `dplyr::select(out, dplyr::starts_with(".pred_"))` returns three columns.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement. Requests: `httr2::request()` with the auth of each provider, `httr2::req_retry()` (defaults), `httr2::req_throttle()` when `rpm` is set, `httr2::req_error(is_error = \(resp) FALSE)`; send with `httr2::req_perform_parallel(reqs, on_error = "continue", max_active = max_active)`. Use the time of each response for `.seconds` (check `httr2::resp_timing()`; else time the batch and record `NA` per row, and say so in the roxygen `@details`).
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 7: The path file of decide()

**Files:**
- Modify: `decisions/R/decide.R`
- Create: `decisions/R/path.R`, `decisions/tests/testthat/test-path.R`

**Interfaces:**
- Produces (internal): `run_hash(decider, questions, references, settings)`, `read_path(path, hash, ignore_hash)`, `write_path(path, hash, done)`. The JSON file holds `version`, `hash` and `done` (a list keyed by the hash of each prepared input, with its parsed answers, tokens, cost and seconds). No key.

- [ ] **Step 1: Failing tests:**
  - 25 inputs with `max_active = 5`, where the mock fails input 12: the file holds 24 answers; a second run with the same `path` sends exactly 1 request.
  - A second run after one choice description changed stops with an error that mentions `ignore_hash`; with `ignore_hash = TRUE` it sends only the missing inputs.
  - The file text does not contain the key given by `credentials`.
  - Without `path`, no file appears in a `withr::local_tempdir()`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement chunks of `4 * max_active` inputs; write the file after each chunk.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 8: Setups

**Files:**
- Create: `decisions/R/setup.R`, `decisions/tests/testthat/test-setup.R`
- Modify: `decisions/R/decide.R` (accept a setup)

**Interfaces:**
- Produces: `decision_setup(decider, questions, references = NULL, max_size = 768, upscale = FALSE, crop = "none", calibrator = NULL)`; `write_setup(setup, path)`; `read_setup(path)`. The JSON holds the decider (no credentials), the questions, the prepared references (base64), the image settings, and, when present, the calibrator (`base64` of `serialize()`) with the hash of the questions and references at the time of the fit. A function `crop` cannot be saved: `write_setup()` errors and says so.
- `decide(setup, text, image, ...)` uses the setup's fields and, when a calibrator is present, adds the calibrated probabilities with `probably::cal_apply()`.

- [ ] **Step 1: Failing tests:**
  - `read_setup(write_setup(s, f))` gives back the same questions, model, image settings and reference bytes.
  - The file text contains no key.
  - With `skip_if_not_installed("probably")`: a setup with a calibrator, written, then edited so one description changes, gives a warning at `read_setup()` and a setup without a calibrator.
  - `write_setup()` with a function `crop` errors with a message that names `crop`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 9: score_setup() and evaluate_once()

**Files:**
- Create: `decisions/R/score.R`, `decisions/tests/testthat/test-score.R`

**Interfaces:**
- Produces: `score_setup(setup, text = NULL, image = NULL, truth, role = NULL, metric = "roc_auc", event = NULL, path = NULL)` → one-row tibble: `metric`, `estimate`, `n`, `calls`, `input_tokens`, `cost`, `seconds`, `errors`, `answers` (list column with the `decide()` output). `evaluate_once(setup, text = NULL, image = NULL, truth, path)` → the same row plus the output; it writes `path` and refuses a second run while `path` exists.
- ROC AUC: internal rank formula (Mann-Whitney) on the probability of `event`. `event` defaults to `"true"` for a noul question and to the second allowed answer for a question with two answers (for `c(normal = ..., defective = ...)` that is `"defective"`). For three or more answers, `event` is required, and `score_setup()` errors without it.

- [ ] **Step 1: Failing tests:**
  - With a mock that returns known probabilities 0.9, 0.8, 0.3, 0.2 for truths defective, defective, nominal, nominal: `estimate` is 1; with 0.2, 0.8, 0.3, 0.9 it is 0.5. The value equals `yardstick::roc_auc_vec()` when yardstick is installed.
  - `role` with any `"test"` value errors before any request, and the message says why.
  - `evaluate_once()` twice on the same `path`: the second call errors and sends 0 requests.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement on top of `decide()`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit.

### Task 10: Agent skill

**Files:**
- Create: `decisions/inst/skills/decisions/SKILL.md`, `references/writing-questions.md`, `references/tuning-descriptions.md`, `references/calibration-and-evaluation.md`, `references/sharing-a-setup.md`, `decisions/tests/testthat/test-skill.R`

**Interfaces:**
- Consumes: `score_setup()`, `evaluate_once()`, `write_setup()`, `read_setup()`.

- [ ] **Step 1: Failing test:** `SKILL.md` exists under `system.file("skills", "decisions", package = "decisions")`, its front matter has `name: decisions` and a `description` that names `decide()`, `score_setup()` and `read_setup()`, and every file that `SKILL.md` links exists.
- [ ] **Step 2:** Run the test. Expected: FAIL.
- [ ] **Step 3:** Write the skill in the style of the commons skill (`~/.claude/skills/commons/SKILL.md`). `tuning-descriptions.md` carries the rules of `fine_tuned_jev/scripts/fair_loop_instructions.md`: the 0.02 keep rule; base each change on the examples; one idea at a time; prefer a clear, general description over a long list of special cases; do not aim for an AUC of 1; only learning rows; no fixed length limit, and when a provider refuses a long text, read its error and shorten (D161). It states that the guards stop mistakes, not an agent that reads files with a shell (D155).
- [ ] **Step 4:** Run the test. Expected: PASS.
- [ ] **Step 5:** Pressure test (superpowers:writing-skills): give a fresh subagent the copied skill, a saved setup and 20 mocked learning rows, and ask it to improve the descriptions. Expected: it calls `score_setup()` only on learning rows, logs each attempt, applies the 0.02 rule, and never calls `evaluate_once()` before it is told to. Fix the skill text for each miss and rerun.
- [ ] **Step 6:** Commit.

### Task 11: Vignettes 1 to 4 and 6

**Files:**
- Create: `decisions/vignettes/{getting-started,images,choosing-a-model,open-models,grading}.Rmd`, `decisions/data-raw/vignette_results.R`, `decisions/inst/extdata/*.rds`

**Interfaces:**
- Consumes: the whole API. Each vignette has live code chunks (`eval = FALSE`, shown) and a hidden chunk that reads the saved result from `inst/extdata` (D177).

- [ ] **Step 1 (stop point):** Propose the budget rows for the vignette runs (expected: under 300 calls and USD 2 per hosted service). Write them after fmm approves.
- [ ] **Step 2:** `vignette_results.R` runs the live code of each vignette, logs each paid call, and saves the outputs, with no key, to `inst/extdata`.
- [ ] **Step 3:** Write the vignettes per design section 7: (1) the three question types on short texts, one input then many, and how to copy the agent skill to `.claude/skills` or `.agents/skills`; (2) images: the image arguments, the crop function hook, references per answer, on the simulated textiles; (3) Jev, Microsoft-Decision-1 and OpenAI on one text task with `purrr::map()` over `decide()`, yardstick for performance, dplyr for the reported cost and time; (4) Laya on a CPU, only the URL changes; (6) rubric checks with sample answers written for the vignette, questions about the package, a short Shiny use-mode app shown as code (not run) that reads a setup, names the provider that receives the answer, and takes a `credentials` function (D175), and the three credits of D150.
- [ ] **Step 4:** Build each vignette with no key set (`withr::local_envvar()`). Expected: each builds and shows the saved results.
- [ ] **Step 5:** Commit.

### Task 12: Vignette 5, the study again with the package (D156)

**Files:**
- Create: `decisions/vignettes/study-again.Rmd`, `decisions/data-raw/study_again.R`, `decisions/inst/extdata/study_again_*.rds`

**Interfaces:**
- Consumes: the whole API; the sets of the study in `fine_tuned_jev/results/fair/sets/` (`learning.csv`, `references.csv`, `calibration.csv`) and the test rows of `fine_tuned_jev/results/image_split_manifest.csv` (`split == "test"`); the images under `fine_tuned_jev/imgs/` (not shipped).

- [ ] **Step 1 (stop point):** Estimate the calls per model from the sets (learning rows minus references, times the grid size, plus calibration and test rows) and propose the budget rows (TypeSafe and OpenAI; Clef-Flash is local). Write them after fmm approves.
- [ ] **Step 2:** `study_again.R`, per dataset and per image model (Jev, OpenAI `gpt-6-luna`, Clef-Flash; Clef 27B only if it loads on the GPU):
  - a grid with `purrr::map()` over `score_setup()`: k in 1, 2, 4 (the reference ranks of `references.csv`) and `max_size` in 512 and 768, on the learning rows that are not references, with the description that the study froze for that model and dataset;
  - the wording, one change at a time: score the candidate descriptions of the study's eight loops, in their order, with the 0.02 keep rule;
  - calibration of the chosen setup with `probably::cal_estimate_logistic()` on the calibration rows, stored in the setup;
  - `evaluate_once()` on the test rows;
  - `rsample::vfold_cv()` over the learning rows, to show how much the ROC AUC moves.
  It logs each paid call and saves the results (numbers and image names only) to `inst/extdata`. No CLIP.
- [ ] **Step 3:** Write the vignette so that it stands on its own (D186): readers may not have seen our paper, which is still in progress. The vignette itself explains the question (can a decision model with a few reference images detect defects, with calibrated probabilities?), the five datasets and where they come from (cite the published CLIP study, Megahed et al., 2026, doi:10.1080/00224065.2026.2640171, for the datasets), the three kinds of rows (learning, calibration, test) and why the test rows are scored once, what the 0.02 keep rule protects against, and where the candidate descriptions come from (an agent wrote them while it looked at the learning images; link the public description-loops page of the replication record for the detail). It shows the live code, reads the saved results, and reports yardstick metrics by model and dataset, the reported cost and the time. It does not compare its numbers with the paper, and it does not need the paper to be read.
- [ ] **Step 4:** Check the licence of each dataset before the image names ship (AutoVI is CC BY-NC-SA 4.0). Record the result in `data-raw/formats.md`.
- [ ] **Step 5:** Commit.

### Task 13: Full check and hand-over

**Files:**
- Modify: `decisions/README.md`, `decisions/NEWS.md`
- Create: `decisions/_pkgdown.yml`

- [ ] **Step 1:** README: what the package does, install, a 10-line example, the six vignettes, the link to the Hugging Face Space (the Space itself is outside the package, D157), and how to copy the skill. No "first" claim.
- [ ] **Step 2:** webR example A: the calibration on saved probabilities runs in a fresh R session with no network (`withr::local_envvar(ALL_PROXY = "socks5://127.0.0.1:9")`). Put its code in the README. The webR check itself follows after fmm pushes the repository to GitHub and r-universe builds it.
- [ ] **Step 3:** Run `devtools::check(args = "--as-cran")` and `devtools::test()`. Expected: 0 errors, 0 warnings, at most the "New submission" note; every Review Focus item has a passing test.
- [ ] **Step 4:** Ask a fresh reviewer on the most capable model to read the whole package against the design and this plan, and to compare it with the study code for clarity and efficiency (D184): for each part, the package must be at least as clear and do no more work per input. Fix its findings.
- [ ] **Step 5:** Run the live code of vignette 5 once more from a clean session (with the saved results moved away), to prove that the workflow runs. Then hand the package folder to fmm for the vignette 5 test (D158).
- [ ] **Step 6:** In `fine_tuned_jev`: add a process row (stage `build`), and at the end of the milestone copy the ledger by the replication-materials procedure.

## Not in this plan

- The Hugging Face Space (D157). It is outside the package and comes after the package passes the test of fmm.
- webR example B, and pplx-decider (D179).
- The GitHub repository, r-universe and the CRAN submission: fmm does these.
