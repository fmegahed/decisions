# Ask a decision model typed questions

Sends each input (a text, an image or both) with the questions to one
model and returns, for each input, the answer and a probability for each
allowed answer.

## Usage

``` r
decide(
  decider,
  questions,
  text = NULL,
  image = NULL,
  references = NULL,
  max_size = 768,
  upscale = FALSE,
  crop = "none",
  max_active = 10,
  rpm = NULL,
  path = NULL,
  ignore_hash = FALSE
)
```

## Arguments

- decider:

  A decider from
  [`decider_typesafe()`](https://fmegahed.github.io/decisions/reference/decider_typesafe.md),
  [`decider_openai()`](https://fmegahed.github.io/decisions/reference/decider_openai.md),
  [`decider_foundry()`](https://fmegahed.github.io/decisions/reference/decider_foundry.md),
  [`decider_openrouter()`](https://fmegahed.github.io/decisions/reference/decider_openrouter.md)
  or
  [`decider_systemone()`](https://fmegahed.github.io/decisions/reference/decider_systemone.md);
  or a setup from
  [`decision_setup()`](https://fmegahed.github.io/decisions/reference/decision_setup.md)
  or
  [`read_setup()`](https://fmegahed.github.io/decisions/reference/read_setup.md).
  A setup gives the decider, the questions, the prepared references, the
  image settings and a calibrator. With a setup, give the inputs by name
  (`text = `, `image = `), and leave out `questions`, `references`,
  `max_size`, `upscale` and `crop`: they stop `decide()` with an error.

- questions:

  One question from
  [`question_noul()`](https://fmegahed.github.io/decisions/reference/question_noul.md),
  [`question_choice()`](https://fmegahed.github.io/decisions/reference/question_choice.md)
  or
  [`question_score()`](https://fmegahed.github.io/decisions/reference/question_score.md),
  or a named list of questions. The names are the question names of the
  request, kept exactly. With two or more questions, the names, cleaned
  as the answer names are, are the prefixes of the output columns; two
  names that give the same prefix are refused. One question without a
  name is sent as `question`.

- text:

  A character vector with one text per input, or `NULL`.

- image:

  A character vector of file paths or URLs, a list of magick images, or
  a magick vector of several images (for example
  `magick::image_read(paths)`), with one image per input; or `NULL`. A
  file with several frames (GIF, TIFF, PDF) gives its first frame. With
  `text`, element i of `text` and element i of `image` make input i.

- references:

  Reference images for the answers, or `NULL`: a named list in which
  each name is an allowed answer of the question and each element holds
  the images of that answer (paths, URLs or magick images). This release
  takes references with one question only.

- max_size:

  The longest side of each image in pixels after the resize (one number
  of 1 or more), or `NULL` to keep the size. The default is `768`.

- upscale:

  `TRUE` enlarges an image that is smaller than `max_size`. `FALSE` (the
  default) never enlarges.

- crop:

  `"none"` (the default), `"center"`, a box `c(x, y, width, height)` in
  pixels, or a function that takes a magick image and returns a box.
  `max_size`, `upscale` and `crop` apply to the inputs and to the
  references.

- max_active:

  The largest number of requests in progress at the same time. The
  default is `10`.

- rpm:

  The largest number of requests per minute, or `NULL` (the default) for
  no limit. The requests then go out evenly, one each `60 / rpm`
  seconds.

- path:

  `NULL` (the default), or the path of a JSON file that keeps the
  finished answers, so that a long run that stops can continue without
  paying twice for an input (as `ellmer::batch_chat()` does). The folder
  must exist. The inputs that are not in the file go out in chunks of
  `4 * max_active`, and `decide()` adds the answers of each chunk to the
  file. A new call with the same `path` sends only the inputs that are
  not in the file and returns all rows, in the order of the inputs. Rows
  with an `.error` are not written, so a new call sends them again. With
  `path`, identical inputs are sent once.

  The file holds a hash of the run and, for each finished input (keyed
  by a hash of the prepared text and image), its answers with their
  probabilities, `.model`, `.input_tokens`, `.cost` and `.seconds`. It
  holds no key and no input. The hash covers the provider, the server
  URL, the model, the request format, the image format, the questions
  (instructions, answers and descriptions), the prepared reference
  images and the image settings; a crop function enters through its
  body.

  The keys and the hash of the run come from
  [`rlang::hash()`](https://rlang.r-lib.org/reference/hash.html), and
  both cover prepared JPEG bytes (of the inputs, and of the references).
  Another version of ImageMagick (the library under magick) can give
  other JPEG bytes for the same image, and another version of rlang can
  give other hashes. So a path file continues a run on the computer that
  wrote it, with the same versions of ImageMagick and rlang. Elsewhere,
  the hash of the run can differ, or the inputs are sent again.

  With a setup that holds a calibrator, the file keeps the answers
  before calibration, and the hash does not cover the calibrator:
  `decide()` applies the calibrator after it reads the file. So a new
  call with a refitted calibrator, or with none, reuses the answers of
  the file.

  A file that is not a path file of `decide()` (for example a setup file
  of
  [`write_setup()`](https://fmegahed.github.io/decisions/reference/write_setup.md))
  stops the call before any request, also with `ignore_hash = TRUE`, so
  `decide()` never replaces it.

- ignore_hash:

  `FALSE` (the default) stops before any request when the hash in the
  `path` file differs from the hash of the run, that is, when the model,
  the questions, the references or the image settings changed. `TRUE`
  keeps the answers of the file with a warning and sends only the other
  inputs. The file gets the new hash when `decide()` adds answers to it;
  when the file holds every input, it does not change. Use `TRUE` only
  when you know that the change does not change the answers, for example
  the same model on a new server URL.

## Value

A tibble with one row per input, in the order of the inputs:

- For one question: `.pred_class`, a factor whose levels are the allowed
  answers, kept exactly (for example `"not sure"`); `.pred_<answer>`,
  the probability of each allowed answer; and `.score` for a score
  question. The probability columns have syntactic names: the answer
  cleaned as `janitor::make_clean_names(case = "none")` cleans it (ASCII
  letters, digits and `_`; `X` before a leading digit). For example,
  `"not sure"` gives `.pred_not_sure`, `"late / lost"` gives
  `.pred_late_lost` and `"50%"` gives `.pred_X50_percent`. probably and
  yardstick read these columns.

- For two or more questions: the same columns with the cleaned question
  name and `_` as a prefix, for example `quality_.pred_class`.

- `.model`: the model that the provider reports, or the model of the
  decider when the response has none.

- `.input_tokens`: the input tokens that the provider reports.

- `.cost`: the cost that the provider reports, or `NA`.

- `.seconds`: the time of the response.

- `.error`: `NA`, or the reason why the answers of the row are `NA`.

The attribute `requests` of the tibble is the number of requests that
this call sent (0 when a `path` file holds all the answers). A second
try after HTTP 429 or 503 counts as a request.

With a setup that holds a calibrator, the calibrated probabilities of
[`probably::cal_apply()`](https://probably.tidymodels.org/reference/cal_apply.html)
replace the `.pred_<answer>` columns, and `.pred_class` is the answer
with the highest calibrated probability (its levels stay the allowed
answers). `.score` stays as the model gave it. The rows with an `.error`
stay `NA`.

## Details

One request goes out per input, in parallel
([`httr2::req_perform_parallel()`](https://httr2.r-lib.org/reference/req_perform_parallel.html)),
with at most `max_active` requests at a time and at most `rpm` requests
per minute. Set `rpm` to the rate limit of your account: with no `rpm`,
the first requests go out at full speed, and a provider with a rate
limit then refuses some of them with HTTP 429.

Each request waits at most 300 seconds (5 minutes) for its response
([`httr2::req_timeout()`](https://httr2.r-lib.org/reference/req_timeout.html)).
A request that takes longer gets a row error, so a server that stops
responding does not hold the call. With `path`, a new call sends that
input again.

A request that gets HTTP 429 or 503 is sent one more time, as the
default retry policy of httr2 does (two tries). `decide()` sends all
such requests again together, after the longest wait that their
`Retry-After` headers ask for (1 second without the header, at most 60
seconds). A second failure stays as a row error. So a call never waits
long for a server that keeps refusing.

An interrupt (Esc) keeps the rows that are done. After an interrupt
while the requests are out, nothing is sent again, and each request that
did not finish gets a row error. An interrupt during the wait before the
second tries skips them; their rows get the error "Interrupted before a
retry." With `path`, an interrupt also stops the chunks: the file keeps
every finished answer, the inputs that were not sent get the row error
of a request that did not finish, and a new call sends only the rest.
Each write goes to a temporary file in the same folder first, which then
replaces the file, so a crash during a write leaves the previous file
whole. When the file cannot be replaced (for example, while a sync
program holds it), `decide()` tries again twice, and warns at the end
with the number of finished answers that the file does not hold.

No row is lost. A row has `NA` answers and a message in `.error` when
the call fails (the message holds the error text of the provider word
for word, the model name and the size of the request in bytes), when the
response cannot be read, when an answer is not an allowed answer or is
missing, when the probability of an allowed answer is missing, or when
the score of a score question is not one number or its probabilities are
all zero. With `path`, a new call sends such a row again. A row with an
answered call keeps its `.input_tokens` and `.cost`. A `model`,
`input_tokens` or `cost` field that is not one value gives the model of
the decider or `NA`.

Because `.error` keeps the text of the provider word for word, it can
hold a part of the key: OpenAI answers a wrong key with HTTP 401 and a
text that shows the last four characters of the key. Do not share the
`.error` texts of a call with a wrong key.

`decide()` reads the key and checks the input type of the model before
any request. For a provider with a key (all deciders except
[`decider_systemone()`](https://fmegahed.github.io/decisions/reference/decider_systemone.md)),
it stops unless the key is one non-empty string; the message does not
show the key. For a setup with a calibrator, it also checks before any
request that probably and the packages of the calibrator (for example
mgcv) are installed. It prepares each reference image once per call (a
setup holds its references prepared) and each input image once. With
`decider_systemone(image_format = "images")`, it writes the images with
three color channels.

Each image goes out as a JPEG, which has no transparency. So each pixel
keeps its color and loses its transparency, and transparent areas often
become black (a transparent pixel usually holds black, as
`"transparent"` does in magick).

SystemOne links reference images to the answers of choice and noul
questions. A SystemOne score question has no place for them: they are
sent, but not linked to a level. OpenAI puts them in the instructions of
the question, and the image-list format names them in the state text.

`.cost` holds only a cost that the provider reports (OpenRouter does).
When no row has a cost, `decide()` prints one message that says so.

`.seconds` is the total time of the response as
[`httr2::resp_timing()`](https://httr2.r-lib.org/reference/resp_timing.html)
gives it; for a request that was sent again, it is the time of the
second try. It is `NA` when no response arrived.

## See also

The deciders
([`decider_typesafe()`](https://fmegahed.github.io/decisions/reference/decider_typesafe.md)
and the others), the questions
([`question_noul()`](https://fmegahed.github.io/decisions/reference/question_noul.md),
[`question_choice()`](https://fmegahed.github.io/decisions/reference/question_choice.md)
and
[`question_score()`](https://fmegahed.github.io/decisions/reference/question_score.md)),
[`decision_setup()`](https://fmegahed.github.io/decisions/reference/decision_setup.md)
to save the choices, and
[`vignette("getting-started")`](https://fmegahed.github.io/decisions/articles/getting-started.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# These examples need an API key and make paid calls, so they are not run on CRAN.
refund <- question_noul("Does the message ask for a refund?")
decide(decider_typesafe("jev-1.13.0"), refund, text = c(
  "Please refund the second charge.",
  "Where is my parcel?"
))

# Images of the package: two references and two inputs
dir <- system.file("extdata", "textiles", package = "decisions")
refs <- subset(textiles, role == "reference" & reference_rank == 1)
inputs <- subset(textiles, role == "input")[1:2, ]
quality <- question_choice("Inspect `inspection_image` for a flaw.", c(
  nominal = "A regular pattern.", defective = "A flaw in the pattern."
))
decide(
  decider_openai(), list(quality = quality),
  image = file.path(dir, inputs$file),
  references = list(
    nominal = file.path(dir, refs$file[refs$class == "nominal"]),
    defective = file.path(dir, refs$file[refs$class == "defective"])
  )
)

# A setup holds the decider, the questions and the references
setup <- decision_setup(decider_typesafe("jev-1.13.0"), list(refund = refund))
decide(setup, text = "Please refund the second charge.")
} # }
```
