# Writing questions

Use this reference to build the questions and the setup of a decision.

## Choose the question type

- `question_noul()` asks for true or false. Its answers are `true` and `false`. Add `true = ` and `false = ` descriptions if they help.
- `question_choice()` asks for one of two or more named choices. Each name is an allowed answer. Each value is its description.
- `question_score()` asks for an ordered level. Give the levels from low to high.

An answer name can have spaces (for example `"not sure"`). Two names that give the same column name are refused.

## Choose the decider

- `decider_typesafe()`, `decider_openai()`, `decider_foundry()`, `decider_openrouter()` and `decider_systemone()` each name one provider.
- One `decide()` call uses one model.
- The key comes from an environment variable of the provider. A `credentials` function can give it instead. Do not write a key in code, in a log or in a file.
- Ask the person which decider and which model to use. Do not guess.

## Write the text

- Write the instructions as one clear question about what is visible or written in the input.
- Write each description in plain language. Say what makes an input belong to that answer.
- Do not write instructions about scores or labels in a description.
- Keep the same terms in all descriptions.

## Build a setup

```r
quality <- question_choice(
  "Inspect `inspection_image` for a defect.",
  c(nominal = "A clean surface.", defective = "A dark streak.")
)
setup <- decision_setup(
  decider_typesafe("jev-1.13.0"),
  list(quality = quality),
  references = list(nominal = "good.jpg", defective = "streak.jpg"),
  max_size = 768
)
```

- `references` takes one question only in this release. Each name is an allowed answer.
- `max_size`, `upscale` and `crop` set the image settings. They apply to the references and to the inputs.
- With a setup, call `decide()` with named inputs: `decide(setup, image = paths)`. Do not pass `questions`, `references` or image settings again.

## Read the output of decide()

`decide()` returns one row per input, in the order of the inputs.

- `.pred_class` is a factor. Its levels are the allowed answers.
- `.pred_<answer>` is the probability of each answer. The answer name is cleaned: `"not sure"` gives `.pred_not_sure`.
- `.score` is present for a score question.
- `.model`, `.input_tokens`, `.cost`, `.seconds` and `.error` follow.
- `.cost` is `NA` when the provider reports no cost.
- A row with a failed call has `NA` answers and the text of the provider in `.error`. Read it. Do not drop the row without a reason.

Use `path` to keep finished answers in a JSON file. A new call with the same `path` sends only the inputs that the file lacks. When the model, the questions, the references or the image settings change, `decide()` stops with a message that names the hash mismatch. Use a new `path`. Use `ignore_hash = TRUE` only when you know that the change does not change the answers.

Use `rpm` to limit the requests per minute.
