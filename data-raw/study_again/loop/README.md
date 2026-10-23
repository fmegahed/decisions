# Description loops of gpt-6-luna (vignette 5)

Decision D197: gpt-6-luna gets its own description loops. A fresh Claude Code
agent tunes two texts (normal, defective) on each of four datasets, in a blind
sandbox, one candidate at a time. The rules are the rules of the study loops.
Scoring uses the package: `decider_openai("gpt-6-luna")`, `question_choice()`,
`score_setup()`.

This folder holds the kit. Every command runs from the package root in Git
Bash. R is `"/c/Program Files/R/R-4.6.1/bin/Rscript.exe"`.

## Files

| File | Job |
|------|-----|
| `make_sandbox.R <dataset>` | Makes the sandbox, the image map and the md5 of `score.sh`. |
| `loop_score.R <dataset> <N>` | The scoring command. `score.sh` in the sandbox calls it. |
| `run_loop.sh [--dry-run] <dataset>` | Starts one agent with the flags of the study. |
| `audit.R <dataset> <transcript>` | Audits the transcript and writes `<dataset>_audit.csv`. |
| `loop_common.R` | Shared folders, loop log and keep rule. |

Datasets: `extrusion`, `microstructure`, `pipe_staple`, `textiles`. Pans have
no loop.

## Where the files are

- The sandbox is `C:/Users/megahefm/decisions-openai-loops/<dataset>`. It is
  outside Dropbox and outside both repositories. The agent works there.
- The sandbox has no label in a file name. The images are `img_001` and so
  on, in a shuffled order (seed 202610).
- Outside the sandbox, in this folder: `<dataset>_image_map.csv` (name to
  study path), `<dataset>_score_sh.md5`, `<dataset>_loop_log.csv` (the mirror
  of the loop log) and `<dataset>_audit.csv`.
- Outside the sandbox, in `C:/Users/megahefm/decisions-openai-loops/state`:
  one state file of `decide()` for each candidate. A failed run continues
  from it.

## Steps

1. Make the sandbox. The script refuses when the sandbox, the mirror or a
   state file of an earlier attempt exists.

   ```
   Rscript data-raw/study_again/loop/make_sandbox.R textiles
   ```

2. Rehearse with no paid call. This runs all checks and writes nothing.

   ```
   cd /c/Users/megahefm/decisions-openai-loops/textiles
   DECISIONS_LOOP_CHECK_ONLY=true bash score.sh 1
   ```

3. Print the agent command with a dry run. `claude` does not start.

   ```
   bash data-raw/study_again/loop/run_loop.sh --dry-run textiles
   ```

4. Run the loop. Do this only after fmm approves a budget row in
   `replication_materials/calls/README.md`. One loop makes at most 6 x 96
   calls. The script refuses when the mirror already has rows. It prints the
   path of the transcript.

   ```
   bash data-raw/study_again/loop/run_loop.sh textiles
   ```

5. Audit the transcript.

   ```
   Rscript data-raw/study_again/loop/audit.R textiles "<transcript path>"
   ```

   The script prints `blind` when no row is flagged. A person reviews each
   flagged row.

## What `score.sh N` does

1. It checks that N is the next number (rows of the mirror plus 1), that N is
   6 or less, that `candidates/N.csv` has one row with a non-empty `normal`,
   `defective` and `reason`, that the sandbox log equals the mirror, and that
   `score.sh` is unchanged.
2. It sets up `decider_openai("gpt-6-luna")` with one `question_choice()`
   named `quality`, the two candidate texts, the two reference images of each
   class, `max_size = 768` and `upscale = TRUE`.
3. It scores the 96 design images with `score_setup()` (`role = "learning"`).
   It logs each paid call with `log_decide()` (service `openai`, purpose
   `decisions-task12-openai-loop-<dataset>`).
4. It writes `scores/N.csv` and one row in the sandbox log and in the mirror.
5. The keep rule: a candidate replaces the current best only if its AUC is at
   least 0.02 higher. Candidate 1 is the first best. The script prints the AUC,
   the mean probability by defect type and the current best.

If an image fails, the script logs the calls, writes no log row and stops.
Run the same command once more. It sends only the failed images.

## Check only

`DECISIONS_LOOP_CHECK_ONLY=true` runs the checks and builds the setup. It
prints `check only: no call`. It makes no call, reads no key and writes no
file. `run_loop.sh` passes the variable to the agent.
