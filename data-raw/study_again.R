# Run the pipeline of vignette 5 (vignettes/study-again.Rmd) and save the
# results it shows (Task 12b, D156).
#
# Run from the package root:
#   Rscript data-raw/study_again.R sets
#   Rscript data-raw/study_again.R <step> <model>
#   Rscript data-raw/study_again.R save
# Steps, in this order: wording, grid, calibration, folds.
# Models: jev (TypeSafe, jev-1.14.0), openai (gpt-6-luna), clef (Clef-Flash
# on this computer, docker container clef-flash; free, not logged).
#
#   sets:        writes inst/extdata/study_sets.csv from the sets of the study
#                (no call).
#   wording:     jev and clef score the candidate descriptions of the study
#                loops, in their order, on the 96 design images of each
#                dataset (k = 2, max_size = 768), with the 0.02 keep rule.
#                jev: 13 x 96 = 1,248 calls. openai reads its own loop logs
#                (data-raw/study_again/loop/, no call). Pans have no loop.
#   grid:        the final wording with k in 1, 2, 4 and max_size in 512,
#                768, on the learning rows that are not references (92 per
#                dataset, 12 for pans): 6 x 380 = 2,280 calls per model.
#   calibration: the calibration rows with the chosen setup (pans: the
#                learning rows that are not references at the chosen k):
#                at most 202 calls per model. A logistic calibrator; the setup
#                files go to data-raw/study_again/setups/ (not in git: the
#                reference images make them large).
#   folds:       5-fold cross-validation, 10 repeats, of the grid answers of
#                the chosen setup (no call).
#   save:        inst/extdata/study_again.rds (numbers, texts and image names
#                only; no image, no setup, no key).
#
# No step scores a test row. score_rows() passes the role of each row to
# score_setup(), which refuses test rows; the one-time test (evaluate_once())
# is a later task.
#
# The code after each "# chunk: <name>" line is the code of the chunk with
# `script = TRUE` of that name in vignettes/study-again.Rmd, unchanged. The
# lines that this script adds: the folders, the inputs of each step (the loop
# logs and the results of the step before), the cap check, log_scores(), the
# error check, the Clef-Flash server and the saves.
#
# Every paid call appends one row to
# fine_tuned_jev/replication_materials/calls/<service>-calls.csv, once: a
# ledger next to each state file holds the rows that are logged. Each scoring
# run keeps its answers in a state file (`path` of score_setup()), so a run
# that stops continues without paying twice. The script reads the keys from
# the environment and never prints or saves a key.

readRenviron("C:/Users/megahefm/Dropbox/Miami/Code/claude/fine_tuned_jev/.Renviron")
pkgload::load_all(".", quiet = TRUE)
source("data-raw/log_call.R")

study_dir <- "C:/Users/megahefm/Dropbox/Miami/Code/claude/fine_tuned_jev"
# The images of the study: the same files as the data/ folder of
# fmegahed/qe_genai (checked byte for byte on 2026-10-23)
image_dir <- file.path(study_dir, "imgs")
work_dir <- "data-raw/study_again"
state_dir <- file.path(work_dir, "state")
setup_dir <- file.path(work_dir, "setups")
results_dir <- file.path(work_dir, "results")
loop_datasets <- c("extrusion", "microstructure", "pipe_staple", "textiles")
services <- c(jev = "typesafe", openai = "openai", clef = NA)
# Caps of Task 12b on the rows of this script in the call logs (D191)
caps <- c(typesafe = 4000, openai = 2700)
purpose_prefix <- "decisions-task12-study-"

# ---- Helpers (no call) ---------------------------------------------------------

#' Read the results of one step and model from results_dir
#' @param step,model_name The step and the model.
read_results <- function(step, model_name) {
  file <- file.path(results_dir, paste0(step, "_", model_name, ".rds"))
  if (!file.exists(file)) {
    stop("Run the step before first: ", basename(file), " is missing.")
  }
  readRDS(file)
}

#' Save the results of one step and model to results_dir
#' @param x A named list of tibbles.
save_step <- function(x, step, model_name) {
  dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)
  saveRDS(x, file.path(results_dir, paste0(step, "_", model_name, ".rds")))
}

#' Count the inputs that a state file does not hold yet
#' @param state A state file of score_setup().
#' @param n The number of inputs of the run.
open_inputs <- function(state, n) {
  done <- if (file.exists(state)) length(jsonlite::read_json(state)$done) else 0
  max(n - done, 0)
}

#' Stop when the planned calls would pass the cap of the service
#' @param model_name The model.
#' @param planned The calls that the step can still send.
check_cap <- function(model_name, planned) {
  service <- services[[model_name]]
  if (is.na(service)) {
    cat("Clef-Flash runs on this computer: no cap, no log.\n")
    return(invisible())
  }
  log <- readr::read_csv(
    file.path(calls_dir, paste0(service, "-calls.csv")),
    col_types = readr::cols(.default = "c")
  )
  used <- sum(stringr::str_starts(log$purpose, purpose_prefix), na.rm = TRUE)
  cat(
    service, "log rows:", nrow(log), "| rows of this script:", used,
    "| planned now:", planned, "| cap:", caps[[service]], "\n"
  )
  if (used + planned > caps[[service]]) {
    stop("The planned calls would pass the cap of ", service, ". Stop and report.")
  }
  invisible()
}

#' Log the paid calls of score_setup() results, each call once
#'
#' A ledger next to each state file (`<state>.logged.txt`) holds a key for
#' each logged row: the row number, `.seconds` and `.input_tokens` for an
#' answered row (the state file keeps them, so a rerun gives the same key),
#' and a key of this run for a failed row (a rerun sends it again).
#' @param results A list of one-row tibbles of score_setup().
#' @param states The state file of each result.
#' @param step,model_name,datasets The step, the model and the dataset of
#'   each result, for the purpose.
log_scores <- function(results, states, step, model_name, datasets) {
  service <- services[[model_name]]
  if (is.na(service)) return(invisible())
  run_id <- format(Sys.time(), "%Y%m%dT%H%M%OS3")
  purrr::pwalk(list(results, states, datasets), \(result, state, dataset) {
    out <- result$answers[[1]]
    rows <- seq_len(nrow(out))
    failed <- !is.na(out$.error) | is.na(out$.seconds)
    keys <- ifelse(
      failed, paste(rows, "failed", run_id),
      paste(rows, out$.seconds, out$.input_tokens)
    )
    ledger <- paste0(state, ".logged.txt")
    logged <- if (file.exists(ledger)) readLines(ledger) else character()
    new_calls <- !keys %in% logged
    if (any(new_calls)) {
      log_decide(
        service, out[new_calls, ],
        paste0(purpose_prefix, step, "-", model_name, "-", dataset),
        deciders[[model_name]]@model,
        paste0("study-", tools::file_path_sans_ext(basename(state)), "-", run_id)
      )
      cat(keys[new_calls], file = ledger, sep = "\n", append = TRUE)
    }
  })
  cat("Calls sent in this run:", sum(purrr::map_dbl(results, "calls")), "\n")
}

#' Stop when a scoring run has a row with an error
#' @param results A list of one-row tibbles of score_setup().
check_errors <- function(results) {
  errors <- sum(purrr::map_dbl(results, "errors"))
  if (errors > 0) {
    stop(
      errors, " rows failed. Their calls are logged. Run the same step ",
      "again: it sends only the failed rows."
    )
  }
}

#' Check that Clef-Flash answers; start the container when it does not
#' @return `TRUE` when this run started the container.
start_clef <- function() {
  health <- \() tryCatch(
    httr2::resp_status(httr2::req_perform(
      httr2::request("http://localhost:30000/health")
    )) == 200,
    error = \(e) FALSE
  )
  if (health()) return(FALSE)
  system2("docker", c("start", "clef-flash"))
  deadline <- Sys.time() + 15 * 60
  while (!health()) {
    if (Sys.time() > deadline) stop("No answer from Clef-Flash in time.")
    Sys.sleep(5)
  }
  TRUE
}

#' Read the loop logs of the study (jev, clef) or of gpt-6-luna (openai)
#' @param model_name The model.
#' @return A tibble: model, dataset, candidate, normal, defective, reason,
#'   auc and kept of the loop.
read_loops <- function(model_name) {
  files <- if (model_name == "openai") {
    file.path(work_dir, "loop", paste0(loop_datasets, "_loop_log.csv"))
  } else {
    file.path(
      study_dir, "results", "fair", "loop",
      paste0(model_name, "-", loop_datasets, "_loop_log.csv")
    )
  }
  missing <- files[!file.exists(files)]
  if (length(missing) > 0) stop("Loop logs missing: ", toString(missing))
  loops <- purrr::map2(files, loop_datasets, \(file, dataset) {
    readr::read_csv(file, col_types = readr::cols(
      candidate = "i", auc = "d", kept = "l", .default = "c"
    )) |>
      dplyr::mutate(model = model_name, dataset = dataset)
  }) |>
    purrr::list_rbind() |>
    dplyr::select(model, dataset, candidate, normal, defective, reason, auc, kept)
  expected <- list(
    jev = c(extrusion = 6, microstructure = 4, pipe_staple = 1, textiles = 2),
    clef = c(extrusion = 6, microstructure = 5, pipe_staple = 2, textiles = 5)
  )[[model_name]]
  counts <- table(loops$dataset)
  stopifnot(
    is.null(expected) || identical(as.integer(counts[names(expected)]), as.integer(expected)),
    all(dplyr::filter(loops, candidate == 1)$normal == generic[["normal"]]),
    all(dplyr::filter(loops, candidate == 1)$defective == generic[["defective"]])
  )
  loops
}

# ---- Case: sets (no call) --------------------------------------------------------

case_sets <- function() {
  sets_dir <- file.path(study_dir, "results", "fair", "sets")
  read_set <- \(name) readr::read_csv(file.path(sets_dir, name), show_col_types = FALSE)
  learning <- read_set("learning.csv")
  references <- read_set("references.csv")
  test <- readr::read_csv(
    file.path(study_dir, "results", "image_split_manifest.csv"),
    show_col_types = FALSE
  ) |>
    dplyr::filter(split == "test")
  study_sets <- dplyr::bind_rows(
    learning = dplyr::anti_join(learning, references, by = c("dataset", "image_path")),
    reference = references,
    calibration = read_set("calibration.csv"),
    test = dplyr::select(test, dataset, image_path, defect_type, actual_class),
    .id = "role"
  ) |>
    dplyr::transmute(
      dataset, image_path = stringr::str_remove(image_path, "^imgs/"),
      class = actual_class, defect_type, role, rank
    )
  design <- read_set("design.csv")
  design_again <- dplyr::filter(
    study_sets,
    dataset != "pan_images", role == "learning" | (role == "reference" & rank > 2)
  )
  stopifnot(
    nrow(dplyr::semi_join(references, learning, by = c("dataset", "image_path"))) == nrow(references),
    !anyDuplicated(study_sets$image_path),
    setequal(paste0("imgs/", design_again$image_path), design$image_path),
    all(study_sets$class %in% c("nominal", "defective")),
    all(file.exists(file.path(image_dir, study_sets$image_path)))
  )
  readr::write_csv(study_sets, file.path("inst", "extdata", "study_sets.csv"))
  print(table(study_sets$dataset, study_sets$role))
}

args <- commandArgs(trailingOnly = TRUE)
if (identical(args, "sets")) {
  case_sets()
  quit(save = "no")
}

# ---- Shared chunks ---------------------------------------------------------------

# chunk: sets
sets <- system.file("extdata", "study_sets.csv", package = "decisions") |>
  utils::read.csv() |>
  tibble::as_tibble() |>
  dplyr::mutate(
    truth = factor(
      dplyr::if_else(class == "nominal", "normal", "defective"),
      levels = c("normal", "defective")
    ),
    path = file.path(image_dir, image_path)
  )

by_dataset <- split(sets, sets$dataset)

table(sets$dataset, sets$role)

# chunk: question
quality_question <- function(descriptions) {
  list(quality = question_choice(
    "Inspect `inspection_image` for manufacturing defects. Select exactly one category.",
    descriptions
  ))
}

generic <- c(
  normal = "No visible manufacturing defects; the part appears conforming.",
  defective = "At least one visible manufacturing defect or anomaly."
)

# chunk: deciders
deciders <- list(
  jev = decider_typesafe("jev-1.14.0"),
  openai = decider_openai("gpt-6-luna"),
  clef = decider_systemone(
    "http://localhost:30000", "Cloudflare/clef-flash", image_format = "images"
  )
)

# chunk: setup-functions
make_setup <- function(model, dataset, descriptions, k, max_size,
                       calibrator = NULL) {
  references <- by_dataset[[dataset]] |>
    dplyr::filter(role == "reference", rank <= k) |>
    dplyr::arrange(rank)
  decision_setup(
    deciders[[model]], quality_question(descriptions),
    references = list(
      normal = references$path[references$truth == "normal"],
      defective = references$path[references$truth == "defective"]
    ),
    max_size = max_size, upscale = TRUE, calibrator = calibrator
  )
}

score_rows <- function(setup, rows, path) {
  score_setup(
    setup, image = rows$path, truth = rows$truth,
    role = dplyr::if_else(rows$role == "reference", "learning", rows$role),
    path = path
  )
}

state_file <- function(...) {
  file.path(state_dir, paste0(paste(..., sep = "_"), ".json"))
}

# chunk: keep-rule
keep_rule <- function(auc, gain = 0.02) {
  best <- purrr::accumulate(auc, \(best, x) {
    if (round(x - best, 10) >= gain) x else best
  })
  c(TRUE, diff(best) > 0)
}

# ---- Case: wording ---------------------------------------------------------------

case_wording <- function(model_name) {
  loops <- read_loops(model_name)
  if (model_name == "openai") {
    # No call: the loop of gpt-6-luna scored its candidates with the same
    # question, inputs, references and image settings (score_setup(), k = 2,
    # max_size = 768, upscale = TRUE).
    wording <- dplyr::select(loops, model, dataset, candidate, normal, defective, auc)
  } else {
    candidates <- dplyr::select(loops, model, dataset, candidate, normal, defective, reason)

    # chunk: wording-setups
    score_candidate <- function(model, dataset, candidate, normal, defective) {
      setup <- make_setup(
        model, dataset, c(normal = normal, defective = defective),
        k = 2, max_size = 768
      )
      design <- dplyr::filter(
        by_dataset[[dataset]],
        role == "learning" | (role == "reference" & rank > 2)
      )
      score_rows(setup, design, state_file("wording", model, dataset, candidate))
    }

    wording <- dplyr::filter(candidates, model == model_name)

    states <- purrr::pmap_chr(list("wording", wording$model, wording$dataset, wording$candidate), state_file)
    check_cap(model_name, sum(purrr::map_dbl(states, open_inputs, n = 96)))

    # chunk: wording-score
    wording <- wording |>
      dplyr::mutate(
        result = purrr::pmap(
          list(model, dataset, candidate, normal, defective), score_candidate
        ),
        auc = purrr::map_dbl(result, "estimate")
      )

    log_scores(wording$result, states, "wording", model_name, wording$dataset)
    check_errors(wording$result)
  }

  # chunk: wording-keep
  wording <- dplyr::mutate(wording, kept = keep_rule(auc), .by = dataset)

  final_wording <- wording |>
    dplyr::filter(kept) |>
    dplyr::slice_tail(n = 1, by = dataset) |>
    dplyr::select(model, dataset, normal, defective) |>
    dplyr::bind_rows(tibble::tibble(
      model = model_name, dataset = "pan_images",
      normal = generic[["normal"]], defective = generic[["defective"]]
    ))

  if (model_name == "openai") stopifnot(identical(wording$kept, loops$kept))
  wording$reason <- loops$reason
  print(dplyr::select(wording, dataset, candidate, auc, kept))
  save_step(list(wording = wording, final_wording = final_wording), "wording", model_name)
}

# ---- Case: grid ------------------------------------------------------------------

case_grid <- function(model_name) {
  final_wording <- read_results("wording", model_name)$final_wording

  # chunk: grid-setups
  score_grid <- function(model, dataset, normal, defective, k, max_size) {
    setup <- make_setup(
      model, dataset, c(normal = normal, defective = defective), k, max_size
    )
    learning <- dplyr::filter(by_dataset[[dataset]], role == "learning")
    score_rows(setup, learning, state_file("grid", model, dataset, k, max_size))
  }

  grid <- final_wording |>
    dplyr::cross_join(tibble::tibble(
      k = rep(c(1, 2, 4), each = 2), max_size = rep(c(512, 768), times = 3)
    ))

  states <- purrr::pmap_chr(list("grid", grid$model, grid$dataset, grid$k, grid$max_size), state_file)
  n_learning <- purrr::map_int(grid$dataset, \(d) sum(by_dataset[[d]]$role == "learning"))
  check_cap(model_name, sum(purrr::map2_dbl(states, n_learning, open_inputs)))

  # chunk: grid-score
  grid <- grid |>
    dplyr::mutate(result = purrr::pmap(
      list(model, dataset, normal, defective, k, max_size), score_grid
    ))

  log_scores(grid$result, states, "grid", model_name, grid$dataset)
  check_errors(grid$result)

  # chunk: grid-choose
  grid <- dplyr::bind_cols(
    dplyr::select(grid, -result),
    purrr::list_rbind(grid$result) |>
      dplyr::select(-metric) |>
      dplyr::rename(auc = estimate)
  )

  chosen <- grid |>
    dplyr::arrange(dataset, dplyr::desc(round(auc, 10)), k, max_size) |>
    dplyr::slice_head(n = 1, by = dataset)

  print(dplyr::select(grid, dataset, k, max_size, auc, n, calls, input_tokens, seconds, errors), n = 30)
  print(dplyr::select(chosen, dataset, k, max_size, auc))
  save_step(list(grid = grid, chosen = chosen), "grid", model_name)
}

# ---- Case: calibration -----------------------------------------------------------

case_calibration <- function(model_name) {
  chosen <- read_results("grid", model_name)$chosen
  dir.create(setup_dir, showWarnings = FALSE, recursive = TRUE)

  # chunk: calibration-setups
  calibration_rows <- function(dataset, k) {
    rows <- by_dataset[[dataset]]
    if (dataset == "pan_images") {
      dplyr::filter(rows, role == "learning" | (role == "reference" & rank > k))
    } else {
      dplyr::filter(rows, role == "calibration")
    }
  }

  score_calibration <- function(model, dataset, normal, defective, k, max_size) {
    setup <- make_setup(
      model, dataset, c(normal = normal, defective = defective), k, max_size
    )
    rows <- calibration_rows(dataset, k)
    score_rows(setup, rows, state_file("calibration", model, dataset, k, max_size))
  }

  calibration <- dplyr::select(chosen, model, dataset, normal, defective, k, max_size)

  states <- purrr::pmap_chr(list("calibration", calibration$model, calibration$dataset, calibration$k, calibration$max_size), state_file)
  n_rows <- purrr::map2_int(calibration$dataset, calibration$k, \(d, k) nrow(calibration_rows(d, k)))
  check_cap(model_name, sum(purrr::map2_dbl(states, n_rows, open_inputs)))

  # chunk: calibration-score
  calibration <- calibration |>
    dplyr::mutate(result = purrr::pmap(
      list(model, dataset, normal, defective, k, max_size), score_calibration
    ))

  log_scores(calibration$result, states, "calibration", model_name, calibration$dataset)
  check_errors(calibration$result)

  # chunk: calibration-fit
  fit_calibrator <- function(model, dataset, normal, defective, k, max_size,
                             result) {
    answers <- dplyr::mutate(
      result$answers[[1]], truth = calibration_rows(dataset, k)$truth
    )
    calibrator <- probably::cal_estimate_logistic(answers, truth, smooth = FALSE)
    setup <- make_setup(
      model, dataset, c(normal = normal, defective = defective), k, max_size,
      calibrator = calibrator
    )
    write_setup(setup, file.path(setup_dir, paste0(model, "_", dataset, ".json")))
    metrics <- yardstick::metric_set(
      yardstick::roc_auc, yardstick::brier_class, yardstick::mn_log_loss
    )
    calibrated <- probably::cal_apply(answers, calibrator)
    dplyr::bind_rows(
      before = metrics(answers, truth, .pred_defective, event_level = "second"),
      after = metrics(calibrated, truth, .pred_defective, event_level = "second"),
      .id = "probabilities"
    ) |>
      dplyr::mutate(model = model, dataset = dataset, n = nrow(answers), .before = 1)
  }

  calibration_summary <- calibration |>
    purrr::pmap(fit_calibrator) |>
    purrr::list_rbind()

  print(calibration_summary, n = 40)
  runs <- dplyr::bind_cols(
    dplyr::select(calibration, model, dataset, k, max_size),
    purrr::list_rbind(calibration$result)
  )
  save_step(list(runs = runs, summary = calibration_summary), "calibration", model_name)
}

# ---- Case: folds (no call) -------------------------------------------------------

case_folds <- function(model_name) {
  chosen <- read_results("grid", model_name)$chosen

  # chunk: folds
  fold_auc <- function(model, dataset, answers) {
    learning <- dplyr::filter(by_dataset[[dataset]], role == "learning")
    scored <- dplyr::mutate(answers, truth = learning$truth)
    set.seed(2026)
    rsample::vfold_cv(scored, v = 5, repeats = 10, strata = truth) |>
      dplyr::mutate(
        model = model, dataset = dataset,
        auc = purrr::map_dbl(splits, \(split) {
          held_out <- rsample::assessment(split)
          yardstick::roc_auc_vec(
            held_out$truth, held_out$.pred_defective, event_level = "second"
          )
        })
      ) |>
      dplyr::select(model, dataset, id, id2, auc)
  }

  folds <- chosen |>
    dplyr::select(model, dataset, answers) |>
    purrr::pmap(fold_auc) |>
    purrr::list_rbind()

  print(dplyr::summarise(
    folds, mean = mean(auc), sd = stats::sd(auc), min = min(auc), max = max(auc),
    .by = c(model, dataset)
  ))
  save_step(list(folds = folds), "folds", model_name)
}

# ---- Case: save (no call) --------------------------------------------------------

case_save <- function() {
  models <- names(deciders)
  done <- purrr::keep(models, \(m) file.exists(file.path(results_dir, paste0("folds_", m, ".rds"))))
  cat("Models with all steps:", toString(done), "\n")
  collect <- \(step, part) purrr::map(done, \(m) read_results(step, m)[[part]]) |> purrr::list_rbind()

  wording <- collect("wording", "wording") |>
    dplyr::select(model, dataset, candidate, normal, defective, reason, auc, kept)
  grid <- collect("grid", "grid") |>
    dplyr::select(model, dataset, k, max_size, auc, n, calls, input_tokens, cost, seconds, errors)
  chosen <- collect("grid", "chosen") |>
    dplyr::select(model, dataset, k, max_size, auc, normal, defective)
  calibration_runs <- collect("calibration", "runs") |>
    dplyr::select(model, dataset, k, max_size, auc = estimate, n, calls, input_tokens, cost, seconds, errors)
  calibration <- collect("calibration", "summary") |>
    dplyr::select(model, dataset, n, probabilities, metric = .metric, estimate = .estimate)
  folds <- collect("folds", "folds") |>
    dplyr::rename(repeat_id = id, fold = id2)

  # The scored images (one call each) of each step, with their input tokens,
  # reported cost and response times. `calls` of score_setup() counts only
  # the requests of the last run: a rerun that reads answers from its state
  # file counts 0 for them. So this table counts the scored images (`n`),
  # whose tokens and times the state files keep. The wording of gpt-6-luna
  # comes from the log of its loops (purpose
  # decisions-task12-openai-loop-<dataset>). No provider reports a cost, so
  # `cost` is NA.
  wording_calls <- collect("wording", "wording") |>
    dplyr::filter(model != "openai") |>
    dplyr::mutate(purrr::list_rbind(result) |> dplyr::select(images = n, input_tokens, cost, seconds)) |>
    dplyr::select(model, images, input_tokens, cost, seconds)
  if ("openai" %in% done) {
    loop_log <- readr::read_csv(
      file.path(calls_dir, "openai-calls.csv"), col_types = readr::cols(.default = "c")
    ) |>
      dplyr::filter(stringr::str_starts(purpose, "decisions-task12-openai-loop-"))
    stopifnot(all(loop_log$status == "200"))
    wording_calls <- dplyr::bind_rows(wording_calls, tibble::tibble(
      model = "openai", images = nrow(loop_log),
      input_tokens = sum(as.numeric(loop_log$input_tokens), na.rm = TRUE),
      cost = NA_real_, seconds = sum(as.numeric(loop_log$latency_ms), na.rm = TRUE) / 1000
    ))
  }
  calls <- dplyr::bind_rows(
    wording = wording_calls,
    grid = dplyr::select(grid, model, images = n, input_tokens, cost, seconds),
    calibration = dplyr::select(calibration_runs, model, images = n, input_tokens, cost, seconds),
    .id = "step"
  ) |>
    dplyr::summarise(
      images = sum(images), input_tokens = sum(input_tokens),
      cost = if (all(is.na(cost))) NA_real_ else sum(cost),
      seconds = sum(seconds), .by = c(model, step)
    )

  models_reported <- collect("grid", "grid") |>
    dplyr::mutate(reported = purrr::map(answers, \(x) unique(x$.model))) |>
    dplyr::summarise(reported = toString(unique(unlist(reported))), .by = model)

  saved <- list(
    wording = wording, grid = grid, chosen = chosen,
    calibration_runs = calibration_runs, calibration = calibration,
    folds = folds, calls = calls, models = models_reported,
    # The date of the calls
    run_date = as.Date("2026-10-23")
  )
  saveRDS(saved, file.path("inst", "extdata", "study_again.rds"))
  print(saved[c("chosen", "calls", "models")])
  cat("Size of study_again.rds:", file.size(file.path("inst", "extdata", "study_again.rds")), "bytes\n")
}

# ---- Run -------------------------------------------------------------------------

#' Run one step for one model
#'
#' A paid step stops before any call when the key is missing. A Clef-Flash
#' step starts the container when the server does not answer, and stops it
#' at the end only when this run started it.
#' @param step One of "wording", "grid", "calibration", "folds".
#' @param model_name One of "jev", "openai", "clef".
run_step <- function(step, model_name) {
  dir.create(state_dir, showWarnings = FALSE, recursive = TRUE)
  scoring <- step %in% c("wording", "grid", "calibration") &&
    !(step == "wording" && model_name == "openai")
  service <- services[[model_name]]
  if (scoring && is.na(service)) {
    if (start_clef()) on.exit(system2("docker", c("stop", "clef-flash")), add = TRUE)
  }
  if (scoring && !is.na(service)) {
    key <- c(typesafe = "TYPESAFE_API_KEY", openai = "OPENAI_API_KEY")[[service]]
    stopifnot(nzchar(Sys.getenv(key)))
  }
  switch(step,
    wording = case_wording(model_name),
    grid = case_grid(model_name),
    calibration = case_calibration(model_name),
    folds = case_folds(model_name)
  )
}

if (identical(args, "save")) {
  case_save()
} else {
  stopifnot(
    length(args) == 2, args[[1]] %in% c("wording", "grid", "calibration", "folds"),
    args[[2]] %in% names(deciders)
  )
  run_step(args[[1]], args[[2]])
}
