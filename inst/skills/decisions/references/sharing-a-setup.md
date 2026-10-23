# Sharing a setup

A setup is one complete decision. `write_setup()` saves it as one JSON file. `read_setup()` reads it. R code, a Shiny app and an agent can share the file.

## Save and read

```r
write_setup(setup, "setup.json")
setup <- read_setup("setup.json")
```

- The file holds no key. `read_setup()` gives the decider its credentials from the environment variable of the provider. A `credentials` function overrides it.
- A crop function cannot be saved. Give `crop` as `"none"`, `"center"` or a box.
- `read_setup()` runs `unserialize()` on the calibrator. Read only setup files that you trust.

## The layout of the file

The file is one JSON object. Git shows changes to it as text.

- `version`: `1`.
- `decider`: provider, server URL, model, request format, image format and input type. No key.
- `questions`: an object keyed by question name. Each question has `type`, `instructions` and `answers`. The `answers` object maps each answer to its description.
- `references`: `null`, or the prepared images for each answer, in base64.
- `image_settings`: `max_size`, `upscale` and `crop`.
- `calibrator` and `calibrator_hash`: `null`, or the calibrator and the hash of what it was fitted for.

## Edit a description

An agent can edit the description text in `questions` and nothing else. Do not edit `references`, `calibrator` or `calibrator_hash` by hand.

- Edit a copy of the file. Keep the original.
- Keep the answer names and their order.
- Read the copy with `read_setup()` to check that it is valid.
- After an edit, a stored calibrator no longer fits. `read_setup()` drops it with a warning. This is the correct behavior.
- A `path` file of `decide()` made with the old wording does not match the new wording. Use a new `path`.

## Keys

Do not copy a key into a setup file, a log or a message. Do not read `.Renviron` or `.env`. Ask the person to set the environment variable.
