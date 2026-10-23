# Verified formats of the decision-model providers

Date of the probes: 2026-10-23. Script: `data-raw/probe_providers.R`. Saved
bodies: `tests/testthat/fixtures/<provider>-<case>.json` (response) and
`<provider>-<case>-request.json` (request). Facts change: check them again
before a release (D161).

Test input: one support message (a double charge). Cases: `noul`, `choice2`
(2 options), `choice3` (3 options), `score3` (3 levels), `combined` (all four
questions in one request), `image`, and one `error`. Test images are 280 x 280
px, made in R (`data-raw/make_test_images.R`).

"Differs from design" marks a fact that differs from section 3.2 of the design,
or that the design does not state.

## Facts for all providers

- Every request puts `questions` in the same request as the input. Every
  response gives one answer per question.
- Differs from design: `jsonlite::base64_enc()` wraps its output in lines with
  `\n`. TypeSafe answered HTTP 400 `Invalid image request.` for such a string.
  Remove the line breaks: `gsub("\n", "", x, fixed = TRUE)`. This matters for
  the code that D184 asks for (`jsonlite::base64_enc()` in memory).
- Differs from design: TypeSafe refuses an image under 280 px on a side
  (HTTP 400 `Invalid image dimensions.` for 128 x 128). The study code says
  280 to 1568 px (`max_size`). The package does not check size limits (D161),
  so the provider text must reach `.error` word for word.
- No provider sent an `x-request-id` header that the logger could read, except
  OpenAI (`req_...` value in the log).
- Choice probabilities: the order of the options can differ from the request
  (Microsoft-Decision-1 lists `billing`, `shipping`, `technical`). Match by
  name, never by position.

## 1. TypeSafe Jev (SystemOne format)

| Item | Fact |
|---|---|
| Endpoint | `POST https://api.typesafe.ai/v1/systemone` |
| Auth | `Authorization: Bearer <key>` |
| Image header | `TypeSafe-Danger-Zone-Images: true` (needed with images) |
| Model | `jev-1.13.0` (reported as `jev-1.13.0`). `jev-latest` is reported as `jev-1.14.0`. |
| Body | `model`, `state`, `assets` (images only), `questions` |
| `state` | An object (text fields), for example `{"message": "..."}`. For an image: `{"inspection_image": "<asset id>"}`. |
| Asset | `{"type": "image", "format": "jpg", "data_base64": "..."}`, keyed by an id |
| Question: noul | `{"type": "noul", "instructions": "..."}`. No `criteria` needed. |
| Question: choice | `{"type": "choice", "instructions": "...", "criteria": {"<option>": "<description>"}}` |
| Choice with references | `criteria` entry is `{"description": "...", "examples": ["<asset id>"]}` |
| Question: score | `{"type": "score", "instructions": "...", "criteria": ["<level 0>", "<level 1>", ...]}` (array, lowest first) |
| Answer: noul | `{"type": "noul", "noul": 0.99}` (probability of yes) |
| Answer: choice | `{"type": "choice", "choice": "billing", "confidence": 1.0, "probabilities": {"billing": 1.0, "technical": 0.0}}` |
| Answer: score | `{"type": "score", "score": 2.0, "confidence": 1.0, "legend": {"0": "<level text>", ...}, "probabilities": {"0": 0.0, "1": 0.0, "2": 1.0}}`. Keys are level indices, not labels. |
| Response top level | `model`, `answers` (an object keyed by question name), `usage` |
| Usage | `usage.input_tokens`, `usage.output_tokens` |
| Cost reported | No. `cost_usd` in the log is an estimate: input tokens x USD 0.042 per million. |
| Error | HTTP 400, `{"detail": {"error_type": "api_usage_error", "message": "Invalid request."}}` (invalid question type `bogus`). Image errors have the same shape (`Invalid image request.`, `Invalid image dimensions.`). |
| Fixtures | `typesafe-{noul,choice2,choice3,score3,combined,latest,image,error}` |

Differs from design: none for the request. The design says "`noul` (yes or
no)"; the answer field is `noul`, a probability, not a label.

## 2. OpenAI Decisions API

| Item | Fact |
|---|---|
| Endpoint | `POST https://api.openai.com/v1/decisions` |
| Auth | `Authorization: Bearer <key>` |
| Model | `gpt-6-luna` (reported as `gpt-6-luna`; the guide says it is the only one) |
| Body | `model`, `input`, `questions` (an array) |
| `input` | A string, or `[{"role": "user", "content": [{"type": "input_text", "text": "..."}, {"type": "input_image", "image_url": "data:image/jpeg;base64,..."}]}]` |
| Question: predicate | `{"type": "predicate", "name": "...", "instructions": "..."}` |
| Question: choice | `{"type": "choice", "name": "...", "instructions": "...", "choices": [{"value": "...", "description": "..."}]}` |
| Question: score | `{"type": "score", "name": "...", "instructions": "...", "levels": [{"label": "...", "description": "..."}]}` (2 to 10 levels, lowest first) |
| References | There is no `examples` field. `instructions` can be an array of `input_text` and `input_image` parts. The probe puts the reference images there and the image to inspect in `input` (shared parts first, input last). It worked. |
| Answer: predicate | `{"type": "predicate", "name": "refund", "probability": 1.0}` |
| Answer: choice | `{"type": "choice", "name": "team", "choice": "billing", "probabilities": [{"value": "billing", "probability": 1.0}, ...], "confidence": 1.0}` (an array, not an object) |
| Answer: score | `{"type": "score", "name": "urgency", "score": 2.0, "probabilities": [{"value": 0, "label": "low", "probability": 0.0}, ...], "confidence": 1.0}` |
| Response top level | `model`, `answers` (an **array**, each with `name`), `usage`. The guide also lists a `refusal` answer type per question (not seen). |
| Usage | `usage.input_tokens`, `usage.input_tokens_details.{cached_tokens, cache_write_tokens}`, `usage.output_tokens` (always 0), `usage.output_tokens_details.reasoning_tokens`, `usage.total_tokens` |
| Cost reported | No. `cost_usd` in the log is an estimate: input tokens x USD 0.10 per million (uncached). |
| Error | HTTP 400, `{"error": {"message": "Invalid value: 'bogus'. Supported values are: 'predicate', 'choice', and 'score'.", "type": "invalid_request_error", "param": "questions[0].type", "code": "invalid_value"}}` |
| Fixtures | `openai-{noul,choice2,choice3,score3,combined,image,error}` |

Differs from design: the design says the answer array and `usage.input_tokens`
only. New facts: probabilities are arrays of `{value, probability}` (not
named lists); the noul answer type is `predicate`; there are no `examples` for
references, they go inside the `instructions` array.

## 3. OpenRouter decisions (alpha)

| Item | Fact |
|---|---|
| Endpoint | `POST https://openrouter.ai/api/alpha/decisions` |
| Auth | `Authorization: Bearer <key>` |
| Model IDs | Jev: `typesafe/jev-1.14` (also `typesafe/jev-1.13`, and the alias `~typesafe/jev-latest`). Microsoft-Decision-1: `microsoft/microsoft-decision-1`. OpenAI: `openai/gpt-6-luna-decisions` (not probed). Found in `GET https://openrouter.ai/api/v1/models?output_modalities=all`. The default model list (no `output_modalities=all`) does not show them. |
| Reported model | `typesafe/jev-1.14-20261014`, `microsoft/microsoft-decision-1-20261009` (a dated version) |
| Body | `model`, `state`, `questions` (an object keyed by name). Optional: `provider`, `session_id`, `trace`, `user` |
| `state` | A string, or an object, for example `{"message": "..."}` |
| Question: noul | `{"type": "noul", "instructions": "...", "criteria": {"true": "...", "false": "..."}}`. The docs say `criteria` is required. Jev accepted a noul question without `criteria` (HTTP 200, `openrouter-jev-noul-bare`). Microsoft-Decision-1 was probed only with `criteria`. |
| Question: choice | `{"type": "choice", "instructions": "...", "criteria": {"<option>": "<description>"}}` |
| Question: score | `{"type": "score", "instructions": "...", "criteria": ["<level 0>", ...]}` |
| Question: box | `{"type": "box", "instructions": "..."}` (Jev 1.14 only; not probed) |
| Answers | The same fields as TypeSafe: `noul`; `choice`, `confidence`, `probabilities` (object); `score`, `confidence`, `legend`, `probabilities` (object keyed by level index). Microsoft-Decision-1 gives full-precision floats, Jev rounds. |
| Response top level | `model`, `answers` (object), `usage`, `provider` (`TypeSafe` or `Azure`). The response also has an `id`; it is removed from the fixtures. |
| Usage | `usage.input_tokens`, `usage.output_tokens`, `usage.cost` |
| Cost reported | **Yes**: `usage.cost` in USD. The log copies it (`cost_usd` is not an estimate for OpenRouter). Jev: input tokens x 4.2e-8; the reported cost matches the model list price. |
| Error | HTTP 400, `{"error": {"message": "<a JSON text from the validator>", "code": 400}}`, plus an account `user_id` (removed from the fixture). The `message` holds a JSON array as text (`invalid_union`, `Invalid discriminator value. Expected 'noul' | 'choice' | 'score' | 'box'`). The docs list 400, 401, 402, 403, 404, 413, 429, 500, 502, 503, 524 and 529. |
| Fixtures | `openrouter-jev-{noul,noul-bare,choice2,choice3,score3,combined,error}`, `openrouter-microsoft-{noul,choice2,choice3,score3,combined}` |

Differs from design: the design says "`questions` map (secondary sources)".
Verified. New facts: `usage.cost` is reported (the design's `.cost` rule fits);
`criteria` for noul; model IDs and the dated model names; `provider` field.
Jev through OpenRouter charges 345 input tokens for the noul question with
`criteria` and 313 without it.

## 4. Clef-Flash (SGLang, local, free)

| Item | Fact |
|---|---|
| Endpoint | `POST http://localhost:30000/v1/systemone` (no auth) |
| Model | `Cloudflare/clef-flash` (reported as the same) |
| Body | `model`, `state`, `images` (optional), `questions` |
| `state` | A plain string. With images: a string that says which image is which. (An object was not probed on Clef-Flash.) |
| Images | `images`: a list of `data:image/jpeg;base64,...` strings (3 channels). Order matters. `assets` is ignored. |
| Questions and answers | As TypeSafe (criteria maps, score `criteria` array). Floats have full precision. |
| Usage | `usage.input_tokens`, `usage.output_tokens` (0). No cost. |
| Cost reported | No. Local calls are not logged. |
| Error | HTTP 422 (FastAPI): `{"detail": [{"type": "union_tag_invalid", "loc": ["body", "questions", "refund"], "msg": "Input tag 'bogus' found using 'type' does not match any of the expected tags: 'noul', 'choice', 'score'", "ctx": {...}}]}` |
| Fixtures | `clef-{noul,choice2,choice3,score3,combined,image,error}` |

Differs from design: none.

## 5. Laya (`laya-serve`, local, CPU, free)

| Item | Fact |
|---|---|
| Install | `conda create -y -n laya python=3.11`; `pip install "laya[serve]"` (worked) |
| Start | `laya-serve` with environment variables `LAYA_DEVICE=cpu`, `LAYA_PORT=8000` (default host `0.0.0.0`, port 8000). It downloads three checkpoints from Hugging Face at the first start and loads them (`english`, `multilingual`, `typed-decisions`). Start took about 1 minute. |
| Endpoints | `POST /v1/systemone`, `POST /v1/systemone/batch` (`states`, up to 64, plus one `questions`), `GET /health` |
| `GET /models` | **404** on `laya-serve` (the guide lists it only for a playground server). Use `GET /health`: `{"status": "ok", "loaded": [...], "revisions": {...}, "device": "cpu", ...}` |
| Body | `state` (object with text fields, for example `{"message": "..."}`), `questions`. `model` is optional (pins a checkpoint). No `images`. |
| Questions | As TypeSafe: noul has `instructions`; choice has a `criteria` object; score has a `criteria` array |
| Answers | As TypeSafe, with extra fields: `answer_confidence`, `action.act_probability`, `x_jev_confidence`. Values are rounded to 4 digits. |
| Response top level | `model` (`laya-rl-agent`), `answers`, `usage`, `routing` (checkpoint, language detection). A batch gives `results` (same order as `states`, each as a single response) and `total_usage`. |
| Usage | `usage.input_tokens`, `output_tokens` (0), `state_tokens`, `state_tokens_dropped`, `truncated`, `truncated_questions` |
| Cost reported | No. |
| Error | HTTP 422: `{"detail": "question 'refund': unknown type 'bogus'; use one of ['choice', 'noul', 'score']"}` (a string, not a list) |
| Fixtures | `laya-{noul,choice2,choice3,score3,combined,batch,health,error}` |

Differs from design: `laya-serve` has no `GET /models`. The `usage` object has
more fields. The `model` field in the response is `laya-rl-agent`, not a
checkpoint name.

## Estimated and reported costs in the call logs

- `typesafe-calls.csv`: every `decisions-task2-*` row has an **estimated**
  cost (input tokens x USD 0.042 per million). TypeSafe reports none.
- `openai-calls.csv`: every row has an **estimated** cost (input tokens x
  USD 0.10 per million, uncached). OpenAI reports none.
- `openrouter-calls.csv`: every row has the cost that OpenRouter **reported**
  (`usage.cost`). Failed calls (HTTP 400) have no tokens and no cost.
- Failed calls and their purposes: the TypeSafe `bad-type` row (the expected
  error) and two `image` rows with HTTP 400 (128 px image with line breaks in
  the base64, then 128 px). The bodies of the two image errors were not saved.
- Local calls (Clef-Flash, Laya) are not logged.
