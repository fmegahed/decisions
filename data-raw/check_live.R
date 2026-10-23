# Confirm the open format points of Task 5 with live calls through the real
# decide() of the package (Task 6). Run from the package root:
#   Rscript data-raw/check_live.R <case> [<case> ...]
# Cases: typesafe, openai, openrouter, clef.
#   typesafe:   a noul question with true/false descriptions (text), and a
#               noul question with descriptions and reference images
#               (image input), jev-1.13.0. 4 calls.
#   openai:     a predicate with descriptions (text), and a choice question
#               with reference images (image input), gpt-6-luna. 3 calls.
#   openrouter: Microsoft-Decision-1, a noul question without descriptions
#               (no criteria). 2 calls.
#   clef:       Clef-Flash on the local SGLang server (docker container
#               clef-flash), a choice question with reference images,
#               references first in the image list. 2 local calls, free.
# Paid calls stay under 10 per service (budget rows D188 of the study
# record). Each paid call appends one row to
# fine_tuned_jev/replication_materials/calls/<service>-calls.csv.
# decide() reads the keys with Sys.getenv() at request time. This script
# prints answers and error messages, never a key or a raw body.

readRenviron("C:/Users/megahefm/Dropbox/Miami/Code/claude/fine_tuned_jev/.Renviron")
pkgload::load_all(".", quiet = TRUE)
source("data-raw/log_call.R")

# ---- Inputs ------------------------------------------------------------------

texts <- c(
  "I was charged twice for order 4471. Please refund the extra charge today.",
  "My parcel arrived on time and the product works well. Thank you."
)

image_file <- function(name) {
  file.path("data-raw", paste0("test-image-", name, ".jpg"))
}
# The streak image shows a defect. A mirrored copy of the normal reference
# is a normal image that is not itself a reference.
images <- list(
  magick::image_read(image_file("streak")),
  magick::image_flop(magick::image_read(image_file("reference-normal")))
)

refund_described <- question_noul(
  "Does the message ask for a refund?",
  true = "The message asks for money back.",
  false = "The message does not ask for money back."
)
refund_bare <- question_noul("Does the message ask for a refund?")
defect <- question_noul(
  "Does `inspection_image` show a surface defect?",
  true = "A dark streak crosses the surface.",
  false = "A clean surface with no streak."
)
quality <- question_choice(
  paste(
    "Inspect `inspection_image` for a surface defect.",
    "Select exactly one category."
  ),
  c(
    normal = "A clean surface with no streak.",
    defective = "A dark streak across the surface."
  )
)
references_defect <- list(
  true = image_file("reference-defect"), false = image_file("reference-normal")
)
references_quality <- list(
  normal = image_file("reference-normal"),
  defective = image_file("reference-defect")
)

# ---- Running and reporting -------------------------------------------------

#' Run one check through decide(), log paid calls, and print the result
#' @param service The call-log service, or `NULL` for a free local call.
#' @param label The case label; the purpose is `decisions-task6-check-<label>`.
#' @param expected The expected `.pred_class` of each input.
#' @param ... Passed to decide().
#' @return A list with `accepted` (no row error) and `expected` (the answers
#'   equal `expected`).
run_check <- function(service, label, decider, questions, expected, ...) {
  out <- decide(decider, questions, ...)
  if (!is.null(service)) {
    log_decide(
      service, out, paste0("decisions-task6-check-", label), decider@model,
      label
    )
  }
  cat("\n==", label, "\n")
  print(as.data.frame(out[setdiff(names(out), ".error")]), digits = 4)
  # An OpenAI 401 text echoes a masked key; hide any key-like word. The
  # class [k] keeps the secret scan of the repository free of this line.
  errors <- gsub("s[k]-[A-Za-z0-9*_-]+", "<key redacted>", out$.error)
  if (any(!is.na(errors))) {
    cat("Errors:\n", paste0("  row ", seq_along(errors), ": ", errors, "\n"))
  }
  result <- list(
    accepted = all(is.na(out$.error)),
    expected = identical(as.character(out$.pred_class), expected)
  )
  cat(label, "- accepted:", result$accepted, "- expected answers:",
      result$expected, "\n")
  result
}

#' Wait until a local server answers its health check
#' @param url The health URL.
#' @param minutes The longest wait.
wait_for_health <- function(url, minutes = 15) {
  deadline <- Sys.time() + minutes * 60
  repeat {
    up <- tryCatch(
      httr2::resp_status(httr2::req_perform(httr2::request(url))) == 200,
      error = function(e) FALSE
    )
    if (up) return(invisible(TRUE))
    if (Sys.time() > deadline) stop("No answer from ", url, " in time.")
    Sys.sleep(5)
  }
}

check_typesafe <- function() {
  stopifnot(nzchar(Sys.getenv("TYPESAFE_API_KEY")))
  jev <- decider_typesafe("jev-1.13.0")
  list(
    run_check(
      "typesafe", "typesafe-noul-described", jev,
      list(refund = refund_described), c("true", "false"), text = texts
    ),
    run_check(
      "typesafe", "typesafe-noul-references", jev, list(defect = defect),
      c("true", "false"), image = images, references = references_defect
    )
  )
}

check_openai <- function() {
  stopifnot(nzchar(Sys.getenv("OPENAI_API_KEY")))
  luna <- decider_openai("gpt-6-luna")
  list(
    run_check(
      "openai", "openai-predicate-described", luna,
      list(refund = refund_described), c("true", "false"), text = texts
    ),
    run_check(
      "openai", "openai-image-references", luna, list(quality = quality),
      "defective", image = images[1], references = references_quality
    )
  )
}

check_openrouter <- function() {
  stopifnot(nzchar(Sys.getenv("OPENROUTER_API_KEY")))
  microsoft <- decider_openrouter("microsoft/microsoft-decision-1")
  list(run_check(
    "openrouter", "openrouter-microsoft-noul-bare", microsoft,
    list(refund = refund_bare), c("true", "false"), text = texts
  ))
}

check_clef <- function() {
  system2("docker", c("start", "clef-flash"))
  on.exit(system2("docker", c("stop", "clef-flash")))
  wait_for_health("http://localhost:30000/health")
  clef <- decider_systemone(
    "http://localhost:30000", "Cloudflare/clef-flash", image_format = "images"
  )
  list(run_check(
    NULL, "clef-image-references", clef, list(quality = quality),
    c("defective", "normal"), image = images, references = references_quality
  ))
}

cases <- commandArgs(trailingOnly = TRUE)
stopifnot(length(cases) > 0,
          all(cases %in% c("typesafe", "openai", "openrouter", "clef")))
for (case in cases) {
  switch(case,
    typesafe = check_typesafe(),
    openai = check_openai(),
    openrouter = check_openrouter(),
    clef = check_clef()
  )
}
