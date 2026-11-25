# Paid calls

Claude Code makes no paid call before a row exists for it in this table. The Service of a row is the name of its call log, `<service>-calls.csv`: `typesafe` is the TypeSafe JEV API (D111), `openai` is the OpenAI Decisions API, `openrouter` is OpenRouter (D188), and `gemini` is the Decisions API of Gemini (D301).

| Date | Service | Purpose | Max calls | Max cost (USD) | Approved by |
|---|---|---|---|---|---|
| 2026-10-23 | typesafe | Package decisions (M3), Task 2: real responses of each question type (noul, choice, score) and of an image request, for the tests of the package (D188) | 400 | 9.5 | fmm |
| 2026-10-23 | openai | Package decisions (M3), Task 2: the same with the OpenAI Decisions API (gpt-6-luna) (D188) | 400 | 9.5 | fmm |
| 2026-10-23 | openrouter | Package decisions (M3), Task 2: the same with Jev and Microsoft-Decision-1 through OpenRouter (D188) | 400 | 9.5 | fmm |
| 2026-10-23 | typesafe | Package decisions (M3), Task 11: saved results of vignettes 1 to 4 and 6 (D191) | 300 | 1 | fmm |
| 2026-10-23 | openai | Package decisions (M3), Task 11: the same with the OpenAI Decisions API (D191) | 300 | 1 | fmm |
| 2026-10-23 | openrouter | Package decisions (M3), Task 11: Jev and Microsoft-Decision-1 through OpenRouter for vignette 3 (D191) | 150 | 0.5 | fmm |
| 2026-10-23 | typesafe | Package decisions (M3), Task 12: vignette 5 repeats the study with Jev (grid, rescoring of the loop wordings, calibration, one test) (D191) | 8000 | 5 | fmm |
| 2026-10-23 | openai | Package decisions (M3), Task 12: the same with gpt-6-luna (D191) | 8000 | 10 | fmm |
| 2026-11-24 | gemini | Package decisions: tests of the Decisions API of Gemini (gemini-decision-1): the request format, images and references, real responses for the tests of the package, and the runs of the vignettes, as for gpt-6-luna (D301, D302) | 30000 | 15 | fmm |
| 2026-11-24 | typesafe | locate() in decisions (D321): the run of the vignette section on the 46 textile inputs, and the fixture calls of the tests | 150 | 0.05 | fmm |

## Call logs

Each service has one log: `<service>-calls.csv`. The columns are:

`time_utc,call_id,purpose,model,request_id,status,latency_ms,input_tokens,output_tokens,cost_usd`

## Paid calls before the record

The record started after the experiments (D7). The paid calls before it were approved in the chat, not in this table. There is no per-call log for them (open item O2).

- Service: TypeSafe JEV API (`jev-1.13.0`). Calls made: 4,554, on 2026-10-20.
- Approvals in the chat: batch 1 with 600 calls (D4), a cap of 1,000 calls (D10), a cap of 5,000 calls (D16), and a cap of 7,000 calls (D26).
- Estimated cost: about USD 0.52 (12.3 million input tokens at USD 0.042 per million). The estimate multiplies the calls of each batch by the input tokens measured for that kind of request. These calls count against the USD 5 budget above, so about USD 4.48 remains.
- Clef-Flash (D34) and CLIP ran on a local GPU. They had no API cost.

## Paid calls after the budget row

- 2026-10-20, about 18:40 UTC: 100 JEV calls, made by mistake. A test of a new guard in `scripts/optimize_jev.R` was meant to stop before any call, but Rscript reloaded the key from `.Renviron`. The run used the default microstructure settings, so it repeated the baseline (BA 0.54, AUC 0.789, against 0.55 and 0.803). Estimated cost: about USD 0.011. There is no per-call log (open item O2).
- Totals: 4,654 JEV calls, about USD 0.53. Left under the budget row: 2,346 calls and about USD 4.47.

## Calls of the fair comparison

Budget row of 2026-10-21 (D84). Each call has a row in `typesafe-calls.csv`. The cost is an estimate: input tokens times USD 0.042 per million.

| Step | Purpose prefix | Calls | Failed | Input tokens | Estimated cost (USD) |
|---|---|---|---|---|---|

- Left under the budget row: 41,566 calls and about USD 19.27.
- Clef-Flash and CLIP ran on a local GPU. They had no API cost.

## Calls of the Gemini Decisions API (D301)

Budget row of 2026-11-24 (D301): USD 15 and 30,000 calls, model `gemini-decision-1`. The cost is an estimate: input tokens times USD 0.10 per million. Gemini reports none.

| Step | Purpose prefix | Calls | Failed | Input tokens | Estimated cost (USD) |
|---|---|---|---|---|---|

- The fixture calls of part 1 hold one row added by hand: the logger failed on the first call (`usage$input_tokens` matched `input_tokens_by_modality`), and the call was made again.
- Venn calls are local and free; they are not logged.
- The failed calls of part 3 are one extrusion test image (`extrusion_images/over/frame351.jpg`) that the safety filter of Gemini refused each time (HTTP 400, `prohibited_content`): the test, two sends of the failed row, one debug call, and the test of the rerun. The case study keeps it as a row with an error.
- Total of the budget row of D301 on 2026-11-24: 10,661 calls, about USD 7.05 of USD 15.

## Rule

Do not put a key, a token or an authorization header in any file in this folder.
