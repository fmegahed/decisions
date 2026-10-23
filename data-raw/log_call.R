# Append rows to the call log of a paid service in the study repository.
# This file never receives or writes an API key: it reads only responses and
# the output of decide().

calls_dir <- "C:/Users/megahefm/Dropbox/Miami/Code/claude/fine_tuned_jev/replication_materials/calls"

# Published input prices (USD per million input tokens). OpenRouter has no
# entry: the response reports the cost.
input_price_per_million <- c(typesafe = 0.042, openai = 0.10)

log_columns <- c(
  "time_utc", "call_id", "purpose", "model", "request_id", "status",
  "latency_ms", "input_tokens", "output_tokens", "cost_usd"
)

#' Estimate a cost when the provider reports none
#' @param service `"typesafe"`, `"openai"` or `"openrouter"`.
#' @param cost The reported cost, or `NA`.
#' @param input_tokens The input tokens, or `NA`.
#' @return The reported cost, or input tokens times the published input price.
estimate_cost <- function(service, cost, input_tokens) {
  price <- input_price_per_million[service]
  ifelse(is.na(cost) & !is.na(price), input_tokens * price / 1e6, cost)
}

#' Append rows to `<service>-calls.csv` with LF line endings
#' @param service `"typesafe"`, `"openai"` or `"openrouter"`.
#' @param rows A data frame with the columns `log_columns`.
#' @return `rows`, invisibly.
append_rows <- function(service, rows) {
  path <- file.path(calls_dir, paste0(service, "-calls.csv"))
  header <- !file.exists(path)
  # A binary connection keeps "\n" as is; a text connection on Windows
  # writes "\r\n".
  con <- file(path, open = "ab")
  on.exit(close(con))
  utils::write.table(
    rows[log_columns], con,
    sep = ",", row.names = FALSE, col.names = header, quote = FALSE,
    na = "", eol = "\n"
  )
  invisible(rows)
}

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
  row <- data.frame(
    time_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    call_id = call_id,
    purpose = purpose,
    model = model,
    request_id = httr2::resp_header(response, "x-request-id") %||% "",
    status = httr2::resp_status(response),
    latency_ms = round(latency_ms),
    input_tokens = input_tokens,
    output_tokens = usage$output_tokens %||% NA,
    cost_usd = estimate_cost(service, usage$cost %||% NA, input_tokens)
  )
  append_rows(service, row)
}

#' Append the calls of one decide() output to `<service>-calls.csv`
#'
#' One row per input. decide() keeps no request id and no output tokens, so
#' those cells stay empty. The status is 200 for a row with no error or with
#' an answer error, the HTTP status of a failed call, and empty when no
#' response arrived.
#' @param service `"typesafe"`, `"openai"` or `"openrouter"`.
#' @param out The output of decide().
#' @param purpose Text such as `"decisions-task6-check-noul"`.
#' @param model Model name that the requests used.
#' @param call_id A short label; the row number is appended.
#' @return The rows, invisibly.
log_decide <- function(service, out, purpose, model, call_id) {
  status <- ifelse(
    is.na(out$.error) | !grepl("^(HTTP|No response)", out$.error), "200",
    ifelse(grepl("^HTTP", out$.error), sub("^HTTP ([0-9]+).*", "\\1", out$.error), "")
  )
  rows <- data.frame(
    time_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    call_id = paste0(call_id, "-", seq_len(nrow(out))),
    purpose = purpose,
    model = model,
    request_id = "",
    status = status,
    latency_ms = round(out$.seconds * 1000),
    input_tokens = out$.input_tokens,
    output_tokens = NA,
    cost_usd = estimate_cost(service, out$.cost, out$.input_tokens)
  )
  append_rows(service, rows)
}

`%||%` <- function(x, y) if (is.null(x)) y else x
