# Run the live code of the vignettes and save the results they show.
#
# Run from the package root:
#   Rscript data-raw/vignette_results.R <case> [<case> ...]
# Cases: getting-started, getting-started-recalls, images, choosing-a-model, open-models, grading.
#
# The code of each case is the code of the chunks with `script = TRUE` in
# vignettes/<case>.Rmd, unchanged. The lines that this script adds are the
# calls of log_decide(), save_results(), report_errors() and wait_for_laya().
#
#   getting-started:   TypeSafe Jev, 23 calls.
#   getting-started-recalls: TypeSafe Jev, 30 calls (score question on ohio_recalls).
#   images:            TypeSafe Jev and OpenAI, 46 calls each; Clef-Flash on this
#                      computer (docker container clef-flash), 3 x 46 calls, free,
#                      not logged.
#   choosing-a-model:  TypeSafe, OpenRouter and OpenAI, 75 calls each.
#   open-models:       Laya on this computer (CPU), free, not logged.
#   grading:           TypeSafe Jev, 23 calls.
#
# Every paid call appends one row to
# fine_tuned_jev/replication_materials/calls/<service>-calls.csv.
# The keys come from the environment (readRenviron() below). This script
# never prints or saves a key: it saves tibbles of decide() only, never a
# decider or a setup object.

readRenviron("C:/Users/megahefm/Dropbox/Miami/Code/claude/fine_tuned_jev/.Renviron")
pkgload::load_all(".", quiet = TRUE)
source("data-raw/log_call.R")

root <- normalizePath(".")

# ---- Helpers -----------------------------------------------------------------

#' Save the results of a case to inst/extdata/<case>.rds
#' @param case The name of the case.
#' @param saved A named list of tibbles.
save_results <- function(case, saved) {
  dir.create(file.path(root, "inst", "extdata"), showWarnings = FALSE)
  saveRDS(saved, file.path(root, "inst", "extdata", paste0(case, ".rds")))
}

#' Print the number of rows with an error, for each tibble of a list
#' @param saved A named list of tibbles and of lists of tibbles.
report_errors <- function(saved) {
  tibbles <- purrr::list_flatten(purrr::map(saved, \(x) if (is.data.frame(x)) list(x) else x))
  tibbles <- purrr::keep(tibbles, \(x) is.data.frame(x) && ".error" %in% names(x))
  purrr::iwalk(tibbles, \(x, name) {
    cat(name, ":", sum(!is.na(x$.error)), "of", nrow(x), "rows with an error\n")
  })
}

#' Wait until Laya answers its health check
#' @param minutes The longest wait.
wait_for_laya <- function(minutes = 5) {
  deadline <- Sys.time() + minutes * 60
  repeat {
    up <- tryCatch(
      httr2::resp_status(httr2::req_perform(httr2::request("http://localhost:8000/health"))) == 200,
      error = \(e) FALSE
    )
    if (up) return(invisible(TRUE))
    if (Sys.time() > deadline) stop("No answer from Laya in time.")
    Sys.sleep(5)
  }
}

#' Wait until the Clef-Flash server answers its health check
#' @param minutes The longest wait.
wait_for_clef <- function(minutes = 15) {
  deadline <- Sys.time() + minutes * 60
  repeat {
    up <- tryCatch(
      httr2::resp_status(httr2::req_perform(httr2::request("http://localhost:30000/health"))) == 200,
      error = \(e) FALSE
    )
    if (up) return(invisible(TRUE))
    if (Sys.time() > deadline) stop("No answer from Clef-Flash in time.")
    Sys.sleep(5)
  }
}

# ---- Cases -------------------------------------------------------------------

case_getting_started <- function() {
  stopifnot(nzchar(Sys.getenv("TYPESAFE_API_KEY")))

  # chunk: tickets
  tickets <- tibble::tibble(
    ticket = 1:10,
    text = c(
      "I was charged twice for order 4471. Please refund the extra charge today.",
      "My parcel has not arrived. The tracking page has said 'in transit' for two weeks.",
      "The app crashes each time I open the settings page. I cannot log in, and I have a meeting in ten minutes.",
      "Thank you for the quick delivery. The product works well.",
      "I want my money back. The blender broke after one day.",
      "How do I change the email address on my account?",
      "The invoice shows the wrong company name. Please send a new one when you can.",
      "The package arrived with a broken seal. Please send a replacement. There is no hurry.",
      "Your website shows an error when I pay by card. I must order before the sale ends tonight.",
      "Can you tell me which sizes the jacket comes in?"
    )
  )

  # chunk: decider
  jev <- decider_typesafe()
  jev

  # chunk: questions
  refund <- question_noul("Does the customer ask for a refund?")

  topic <- question_choice(
    "Which team should answer this ticket?",
    c(
      billing = "Charges, invoices and refunds.",
      shipping = "Parcels and delivery.",
      technical = "Errors, and how to use the product."
    )
  )

  urgency <- question_score(
    "How urgent is this ticket?",
    c(
      low = "The customer can wait several days.",
      medium = "The customer needs an answer today.",
      high = "The customer needs an answer now."
    )
  )

  purpose <- "decisions-task11-getting-started"

  # chunk: one-noul
  one_noul <- decide(jev, refund, text = tickets$text[1])
  one_noul

  log_decide("typesafe", one_noul, purpose, jev@model, "gs-one-noul")

  # chunk: one-choice
  one_choice <- decide(jev, topic, text = tickets$text[2])
  one_choice

  log_decide("typesafe", one_choice, purpose, jev@model, "gs-one-choice")

  # chunk: one-score
  one_score <- decide(jev, urgency, text = tickets$text[3])
  one_score

  log_decide("typesafe", one_score, purpose, jev@model, "gs-one-score")

  # chunk: many-noul
  many_noul <- decide(jev, refund, text = tickets$text)
  dplyr::bind_cols(tickets["ticket"], many_noul)

  log_decide("typesafe", many_noul, purpose, jev@model, "gs-many-noul")

  # chunk: many-two
  many_two <- decide(jev, list(topic = topic, urgency = urgency), text = tickets$text)
  names(many_two)

  log_decide("typesafe", many_two, purpose, jev@model, "gs-many-two")

  saved <- list(
    one_noul = one_noul, one_choice = one_choice, one_score = one_score,
    many_noul = many_noul, many_two = many_two
  )
  save_results("getting-started", saved)
  report_errors(saved)

  # chunk: many-two-table
  dplyr::bind_cols(
    tickets["ticket"],
    many_two[c("topic_.pred_class", "urgency_.pred_class", "urgency_.score")]
  )

}

case_getting_started_recalls <- function() {
  stopifnot(nzchar(Sys.getenv("TYPESAFE_API_KEY")))

  # chunk: decider
  jev <- decider_typesafe()
  jev

  # chunk: recalls
  set.seed(2026)
  recalls <- ohio_recalls |>
    dplyr::slice_sample(n = 10, by = classification) |>
    dplyr::mutate(
      text = paste0("Product: ", product_description, "\nReason: ", reason_for_recall)
    )

  # chunk: recall-question
  risk <- question_score(
    "How serious are the health consequences of using this recalled food?",
    c(
      `Class III` = "Using the food is not likely to cause adverse health consequences.",
      `Class II` = "Using the food may cause temporary or reversible health problems, or serious harm is remote.",
      `Class I` = "Using the food is likely to cause serious health problems or death."
    )
  )

  # chunk: recall-decide
  recall_out <- decide(jev, risk, text = recalls$text)
  recall_out <- dplyr::bind_cols(recalls["classification"], recall_out)

  log_decide(
    "typesafe", recall_out, "decisions-task11c-getting-started-recalls",
    jev@model, "gs-recalls"
  )

  saved <- list(recall_out = recall_out)
  save_results("getting-started-recalls", saved)
  report_errors(saved)

  # chunk: recall-metrics
  print(table(FDA = recall_out$classification, Jev = recall_out$.pred_class))
  print(yardstick::accuracy(recall_out, classification, .pred_class))
  print(yardstick::kap(recall_out, classification, .pred_class, weighting = "quadratic"))

  # chunk: recall-score
  recall_out |>
    dplyr::slice_head(n = 2, by = classification) |>
    dplyr::select(classification, .pred_class, .score) |>
    print()
}

case_images <- function() {
  stopifnot(nzchar(Sys.getenv("TYPESAFE_API_KEY")), nzchar(Sys.getenv("OPENAI_API_KEY")))
  system2("docker", c("start", "clef-flash"))
  on.exit(system2("docker", c("stop", "clef-flash")))
  wait_for_clef()

  # chunk: data
  textile_dir <- system.file("extdata", "textiles", package = "decisions")

  textiles <- textiles |>
    dplyr::mutate(path = file.path(textile_dir, file))

  dplyr::count(textiles, role, class)

  # chunk: montage
  reference_files <- textiles |>
    dplyr::filter(role == "reference") |>
    dplyr::arrange(class, reference_rank)

  reference_files$path |>
    magick::image_read() |>
    magick::image_montage(tile = "2x2", geometry = "250x250+4+4")

  # chunk: references
  references <- split(reference_files$path, reference_files$class)

  inputs <- dplyr::filter(textiles, role == "input")

  # chunk: question
  weave <- question_choice(
    "Does the woven pattern in `inspection_image` have a flaw?",
    c(
      nominal = "The weave is regular. The pattern repeats with no break.",
      defective = "The weave has a flaw. A part of the pattern is broken, or the whole pattern is distorted."
    )
  )

  # chunk: trim
  trim_border <- function(image) {
    info <- magick::image_info(image)
    c(12, 12, info$width - 24, info$height - 24)
  }

  # chunk: decide
  deciders <- list(jev = decider_typesafe(), openai = decider_openai())

  answers <- purrr::map(deciders, \(decider) {
    decide(
      decider, weave,
      image = inputs$path, references = references,
      max_size = 768, upscale = TRUE
    )
  })

  services <- c(jev = "typesafe", openai = "openai")
  purrr::iwalk(services, \(service, name) {
    log_decide(service, answers[[name]], "decisions-task11b-images", deciders[[name]]@model, paste0("im-", name))
  })

  # chunk: clef
  clef <- decider_systemone(
    "http://localhost:30000", "Cloudflare/clef-flash",
    image_format = "images"
  )

  settings <- list(
    `max_size 768` = list(max_size = 768),
    `max_size 512` = list(max_size = 512),
    `crop trim` = list(max_size = 768, crop = trim_border)
  )

  clef_answers <- purrr::map(settings, \(setting) {
    rlang::exec(
      decide, clef, weave,
      image = inputs$path, references = references, upscale = TRUE,
      !!!setting
    )
  })

  saved <- list(inputs = inputs[c("file", "class")], answers = answers, clef_answers = clef_answers)
  save_results("images", saved)
  report_errors(saved)

  # chunk: results
  all_answers <- c(answers, clef_answers)

  results <- all_answers |>
    dplyr::bind_rows(.id = "model") |>
    dplyr::mutate(
      model = factor(model, levels = names(all_answers)),
      truth = rep(inputs$class, times = length(all_answers))
    )

  # chunk: performance
  results |>
    dplyr::group_by(model) |>
    dplyr::summarise(
      roc_auc = yardstick::roc_auc_vec(truth, .pred_defective, event_level = "second"),
      errors = sum(!is.na(.error)),
      input_tokens = sum(.input_tokens, na.rm = TRUE),
      cost_usd = if (all(is.na(.cost))) NA_real_ else sum(.cost, na.rm = TRUE),
      median_seconds = median(.seconds, na.rm = TRUE)
    )

}

case_choosing_a_model <- function() {
  stopifnot(nzchar(Sys.getenv("TYPESAFE_API_KEY")), nzchar(Sys.getenv("OPENROUTER_API_KEY")), nzchar(Sys.getenv("OPENAI_API_KEY")))

  # chunk: injuries
  set.seed(2026)
  injuries <- ohio_injuries |>
    dplyr::slice_sample(n = 20, by = collapsed_nature_title)

  dplyr::count(injuries, collapsed_nature_title)

  # chunk: question
  nature <- question_choice(
    "Which injury does this report of a work injury describe? Choose the main injury.",
    c(
      amputation = "A body part is cut or torn off, in whole or in part.",
      fracture = "A bone is broken or cracked.",
      `crushing injury` = "A body part is squeezed hard between objects, and the tissue is damaged.",
      `thermal burn` = "Heat, flame, hot liquid or a hot surface burns the skin.",
      concussion = "A blow or a shake to the head hurts the brain."
    )
  )

  # chunk: decide
  deciders <- list(
    jev = decider_typesafe(),
    microsoft = decider_openrouter("microsoft/microsoft-decision-1"),
    openai = decider_openai()
  )

  answers <- purrr::map(deciders, \(decider) decide(decider, nature, text = injuries$final_narrative))

  services <- c(jev = "typesafe", microsoft = "openrouter", openai = "openai")
  purrr::iwalk(services, \(service, name) {
    log_decide(service, answers[[name]], "decisions-task11-choosing-a-model", deciders[[name]]@model, paste0("cm-", name))
  })
  saved <- list(injuries = injuries, answers = answers)
  save_results("choosing-a-model", saved)
  report_errors(saved)

  # chunk: results
  results <- answers |>
    dplyr::bind_rows(.id = "model") |>
    dplyr::mutate(truth = rep(injuries$collapsed_nature_title, times = length(answers)))

  # chunk: columns
  grep("^\\.pred_", names(results), value = TRUE)

  # chunk: performance
  metrics <- yardstick::metric_set(yardstick::accuracy, yardstick::roc_auc)

  results |>
    dplyr::group_by(model) |>
    metrics(
      truth,
      .pred_amputation, .pred_fracture, .pred_crushing_injury, .pred_thermal_burn, .pred_concussion,
      estimate = .pred_class
    ) |>
    dplyr::select(model, .metric, .estimate)

  # chunk: errors
  results |>
    dplyr::group_by(model) |>
    dplyr::summarise(rows = dplyr::n(), errors = sum(!is.na(.error)))

  # chunk: confusion
  results |>
    split(results$model) |>
    purrr::map(\(x) yardstick::conf_mat(x, truth, .pred_class)$table)

  # chunk: cost
  results |>
    dplyr::group_by(model) |>
    dplyr::summarise(
      input_tokens = sum(.input_tokens, na.rm = TRUE),
      cost_usd = if (all(is.na(.cost))) NA_real_ else sum(.cost, na.rm = TRUE),
      median_seconds = median(.seconds, na.rm = TRUE)
    )

}

case_open_models <- function() {
  wait_for_laya()

  # chunk: decider
  laya <- decider_systemone("http://localhost:8000", "english", input = "text")
  laya

  # chunk: tickets
  tickets <- tibble::tibble(
    ticket = 1:10,
    text = c(
      "I was charged twice for order 4471. Please refund the extra charge today.",
      "My parcel has not arrived. The tracking page has said 'in transit' for two weeks.",
      "The app crashes each time I open the settings page. I cannot log in, and I have a meeting in ten minutes.",
      "Thank you for the quick delivery. The product works well.",
      "I want my money back. The blender broke after one day.",
      "How do I change the email address on my account?",
      "The invoice shows the wrong company name. Please send a new one when you can.",
      "The package arrived with a broken seal. Please send a replacement. There is no hurry.",
      "Your website shows an error when I pay by card. I must order before the sale ends tonight.",
      "Can you tell me which sizes the jacket comes in?"
    )
  )

  refund <- question_noul("Does the customer ask for a refund?")

  topic <- question_choice(
    "Which team should answer this ticket?",
    c(
      billing = "Charges, invoices and refunds.",
      shipping = "Parcels and delivery.",
      technical = "Errors, and how to use the product."
    )
  )

  urgency <- question_score(
    "How urgent is this ticket?",
    c(
      low = "The customer can wait several days.",
      medium = "The customer needs an answer today.",
      high = "The customer needs an answer now."
    )
  )

  # chunk: decide
  answers <- decide(
    laya,
    list(refund = refund, topic = topic, urgency = urgency),
    text = tickets$text,
    max_active = 1
  )

  saved <- list(answers = answers)
  save_results("open-models", saved)
  report_errors(saved)

  # chunk: answers
  dplyr::bind_cols(
    tickets["ticket"],
    answers[c("refund_.pred_class", "topic_.pred_class", "urgency_.pred_class", ".seconds")]
  )

  # chunk: seconds
  dplyr::summarise(
    answers,
    rows = dplyr::n(),
    errors = sum(!is.na(.error)),
    input_tokens = sum(.input_tokens),
    median_seconds = median(.seconds),
    max_seconds = max(.seconds)
  )

}

case_grading <- function() {
  stopifnot(nzchar(Sys.getenv("TYPESAFE_API_KEY")))

  # chunk: rubric
  rubric <- list(
    keeps_row = question_noul("Does the text say that the failed input keeps its row in the output?"),
    na_answers = question_noul("Does the text say that the answers of the failed row are NA?"),
    error_text = question_noul("Does the text say that the reason of the failure is in the .error column?"),
    others_continue = question_noul("Does the text say that the other inputs of the batch still get their answers?"),
    stops_all = question_noul("Does the text say that decide() stops with an error, or returns nothing, when one call fails?"),
    drops_row = question_noul("Does the text say that decide() removes the failed input from the output?")
  )

  # chunk: rubric-text
  rubric_text <- tibble::tribble(
    ~question, ~kind, ~if_above, ~if_below,
    "keeps_row", "idea", "Covered: the failed input keeps its row.", "Missing: say what happens to the row of the failed input.",
    "na_answers", "idea", "Covered: the answers of the failed row are NA.", "Missing: say what the answers of the failed row are.",
    "error_text", "idea", "Covered: the reason is in the .error column.", "Missing: say where to find the reason of the failure.",
    "others_continue", "idea", "Covered: the other inputs still get their answers.", "Missing: say what happens to the other inputs.",
    "stops_all", "wrong", "Check again: one failed call does not stop decide().", NA_character_,
    "drops_row", "wrong", "Check again: decide() does not remove the row of a failed call.", NA_character_
  )

  # chunk: samples
  samples <- rubric_answers
  samples[1:3, ]

  # chunk: setup-object
  setup <- decision_setup(decider_typesafe(), rubric)

  purpose <- "decisions-task11-grading"

  # chunk: score
  scored <- decide(setup, text = samples$answer)

  log_decide("typesafe", scored, purpose, setup@decider@model, "gr-samples")

  # chunk: probabilities
  dplyr::select(scored, dplyr::ends_with("_.pred_true"), .error)

  # chunk: thresholds
  thresholds <- purrr::map(names(rubric), \(question) {
    tibble::tibble(
      truth = factor(samples[[question]], levels = c(TRUE, FALSE)),
      probability = scored[[paste0(question, "_.pred_true")]]
    ) |>
      yardstick::roc_curve(truth, probability) |>
      dplyr::mutate(j = sensitivity + specificity - 1) |>
      dplyr::filter(dplyr::near(j, max(j)), is.finite(.threshold)) |>
      dplyr::summarise(threshold = median(.threshold), j = max(j))
  }) |>
    purrr::set_names(names(rubric)) |>
    dplyr::bind_rows(.id = "question")

  thresholds

  # chunk: feedback-rubric
  feedback_rubric <- rubric_text |>
    dplyr::left_join(thresholds[c("question", "threshold")], by = "question")

  feedback_rubric

  # chunk: give-feedback
  give_feedback <- function(scored, rubric) {
    if (!is.na(scored$.error)) {
      return("The check did not work. Try again.")
    }
    probability <- purrr::map_dbl(rubric$question, \(question) scored[[paste0(question, "_.pred_true")]])
    lines <- ifelse(probability >= rubric$threshold, rubric$if_above, rubric$if_below)
    lines[!is.na(lines)]
  }

  # chunk: new
  new_answers <- c(
    "The row of the failed call stays in the output. Its answers are NA, and .error has the reason.",
    "decide() stops with an error at the first failed call, and you get nothing back.",
    "It keeps going with the other inputs."
  )

  new_scored <- decide(setup, text = new_answers)

  purrr::map(seq_along(new_answers), \(i) give_feedback(new_scored[i, ], feedback_rubric))

  log_decide("typesafe", new_scored, purpose, setup@decider@model, "gr-new")
  saved <- list(
    scored = scored, thresholds = thresholds, feedback_rubric = feedback_rubric,
    new_answers = new_answers, new_scored = new_scored
  )
  save_results("grading", saved)
  report_errors(saved)
  # The file of write_setup() goes to a temporary folder first, then to inst/extdata
  withr::with_dir(tempdir(), {

  # chunk: write-setup
  write_setup(setup, "rubric_setup.json")

  })
  file.copy(file.path(tempdir(), "rubric_setup.json"), file.path(root, "inst", "extdata", "rubric_setup.json"), overwrite = TRUE)

}

# ---- Run ---------------------------------------------------------------------

cases <- commandArgs(trailingOnly = TRUE)
stopifnot(
  length(cases) > 0,
  all(cases %in% c("getting-started", "getting-started-recalls", "images", "choosing-a-model", "open-models", "grading"))
)
for (case in cases) {
  switch(case,
    `getting-started` = case_getting_started(),
    `getting-started-recalls` = case_getting_started_recalls(),
    images = case_images(),
    `choosing-a-model` = case_choosing_a_model(),
    `open-models` = case_open_models(),
    grading = case_grading()
  )
}
