# Calibration and evaluation

Use this reference after the person says that the descriptions are final.

## Calibration

A calibrator corrects the probabilities of a model. Fit it on calibration rows, not on learning rows or test rows.

1. Run `decide()` with the setup on the calibration rows.
2. Fit a calibrator with probably, for example `probably::cal_estimate_isotonic()`. Its truth is a factor whose levels are the answers. Its estimates are the `.pred_` columns.
3. Build a new setup with `decision_setup()` and `calibrator = `. A setup with a calibrator has one question.
4. Save it with `write_setup()`.

`decide()` applies the calibrator after it reads the answers. The `path` file keeps the answers before calibration, so a refitted calibrator reuses them.

A setup file stores a hash with the calibrator. When the model, the questions, the references or the image settings change, `read_setup()` drops the calibrator with a warning. Fit a new one on answers of the new setup.

## The one-time test

`evaluate_once()` scores the test rows one time.

- Call it only when the person says that the descriptions and the calibrator are final.
- Pass `path` as the result file (an `.rds` file in a folder that exists). It refuses to run again while this file exists.
- Pass `role` as `"test"` for the test rows if you use `role`.
- It returns the one-row tibble of `score_setup()`.
- When a test row has an error, `estimate` is `NA` and the result file is not written. A new call with the same `path` sends only the failed rows again. Tell the person. Do not change the descriptions.
- Do not tune on the result. Report it as it is.

Never call `evaluate_once()` to look at test performance during tuning. Use `score_setup()` on learning rows for that.

## Report

Report the estimate, `n`, `calls`, `cost` and `errors`. Report the budget used. Say which rows were learning, calibration and test. Say which model and which setup file you used.
