# Append one row to the call log of a paid service in the study repository.
# This file never receives or writes an API key: it reads only the response.

calls_dir <- "C:/Users/megahefm/Dropbox/Miami/Code/claude/fine_tuned_jev/replication_materials/calls"

# Published input prices (USD per million input tokens). OpenRouter has no
# entry: the response reports the cost.
input_price_per_million <- c(typesafe = 0.042, openai = 0.10)

log_columns <- c(
  "time_utc", "call_id", "purpose", "model", "request_id", "status",
  "latency_ms", "input_tokens", "output_tokens", "cost_usd"
)

#' Append one paid call to `<service>-calls.csv`
#' @param service `"typesafe"`, `"openai"` or `"openrouter"`.
#' @param response An httr2 response.
#' @param purpose Text such as `"decisions-task2-noul"`.
#' @param model Model name that the request used.
#' @param call_id A short label of the call.
#' @param latency_ms Time of the call in milliseconds.
#' @return The row, invisibly. `cost_usd` is the reported cost, or an estimate
#'   (input tokens times the published input price) when none is reported.
log_call <- function(service, response, purpose, model, call_id, latency_ms) {
  body <- tryCatch(
    httr2::resp_body_json(response, simplifyVector = FALSE),
    error = function(e) list()
  )
  usage <- body$usage
  input_tokens <- usage$input_tokens %||% NA
  output_tokens <- usage$output_tokens %||% NA
  cost <- usage$cost %||% NA
  if (is.na(cost) && !is.na(input_tokens) && service %in% names(input_price_per_million)) {
    cost <- input_tokens * input_price_per_million[[service]] / 1e6
  }
  row <- data.frame(
    time_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    call_id = call_id,
    purpose = purpose,
    model = model,
    request_id = httr2::resp_header(response, "x-request-id") %||% "",
    status = httr2::resp_status(response),
    latency_ms = round(latency_ms),
    input_tokens = input_tokens,
    output_tokens = output_tokens,
    cost_usd = cost
  )[log_columns]
  path <- file.path(calls_dir, paste0(service, "-calls.csv"))
  utils::write.table(
    row, path,
    sep = ",", row.names = FALSE, col.names = !file.exists(path),
    append = file.exists(path), quote = FALSE, na = ""
  )
  invisible(row)
}

`%||%` <- function(x, y) if (is.null(x)) y else x
