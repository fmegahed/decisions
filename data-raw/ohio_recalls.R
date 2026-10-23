# Build the dataset `ohio_recalls` from the openFDA food enforcement reports.
#
# Run from the package root: Rscript data-raw/ohio_recalls.R
# Step 1 downloads the records (needs the network, no key) and writes the flat
# fields to data-raw/openfda_food_enforcement_oh.csv. Step 2 builds the
# dataset from that file only. A rebuild needs no network: the script
# downloads only when the CSV is missing.
#
# Source: https://api.fda.gov/food/enforcement.json?search=state:"OH"
# (recalling firm in Ohio, all years). 1,227 records on 2026-10-23.

csv_path <- "data-raw/openfda_food_enforcement_oh.csv"

# ---- Step 1: download --------------------------------------------------------

if (!file.exists(csv_path)) {
  page <- function(skip) {
    httr2::request("https://api.fda.gov/food/enforcement.json") |>
      httr2::req_url_query(search = 'state:"OH"', limit = 1000, skip = skip) |>
      httr2::req_retry(max_tries = 3) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
  }
  results <- purrr::map(c(0, 1000), page) |>
    purrr::map(\(x) x$results) |>
    purrr::list_flatten()

  # Keep the flat fields: drop the nested `openfda` field
  flat <- results |>
    purrr::map(\(x) x[names(x) != "openfda"]) |>
    purrr::map(\(x) purrr::map(x, \(v) if (is.null(v)) NA_character_ else as.character(v)))
  raw <- dplyr::bind_rows(flat)
  stopifnot(nrow(raw) == 1227)
  utils::write.csv(raw, csv_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
}

# ---- Step 2: build -----------------------------------------------------------

raw <- utils::read.csv(csv_path, colClasses = "character", encoding = "UTF-8", na.strings = "")

#' Turn text into ASCII and trim the whitespace
#' @param x A character vector.
to_ascii <- function(x) {
  trimws(stringi::stri_trans_general(x, "Any-Latin;Latin-ASCII"))
}

ohio_recalls <- raw |>
  dplyr::mutate(
    reason_for_recall = trimws(reason_for_recall),
    classification = factor(classification, levels = c("Class III", "Class II", "Class I"), ordered = TRUE)
  ) |>
  # One recall event lists many products with the same reason: keep the first
  dplyr::distinct(event_id, reason_for_recall, classification, .keep_all = TRUE) |>
  dplyr::transmute(
    recall_number,
    event_id,
    recall_initiation_date = as.Date(recall_initiation_date, format = "%Y%m%d"),
    city = to_ascii(city),
    state,
    product_description = to_ascii(product_description),
    reason_for_recall = to_ascii(reason_for_recall),
    classification
  ) |>
  tibble::as_tibble()

stopifnot(
  !anyNA(ohio_recalls),
  all(!stringi::stri_detect_regex(unlist(ohio_recalls[purrr::map_lgl(ohio_recalls, is.character)]), "[^\x01-\x7F]")),
  !any(purrr::map_lgl(ohio_recalls, \(x) !is.null(names(x))))
)
print(nrow(ohio_recalls))
print(table(ohio_recalls$classification))
usethis::use_data(ohio_recalls, overwrite = TRUE, compress = "xz")
