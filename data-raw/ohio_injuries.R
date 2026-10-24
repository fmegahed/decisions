# Build the dataset `ohio_injuries` from the OSHA Severe Injury Reports.
#
# Source (APA 7): Occupational Safety and Health Administration. (n.d.).
#   Severe injury reports [Data set]. U.S. Department of Labor. Retrieved
#   October 23, 2026, from https://www.osha.gov/severe-injury-reports
#
# The raw file is not in the package repository (D206): it holds employer
# names and addresses, which the dataset drops. To rebuild the dataset:
# 1. Open https://www.osha.gov/severe-injury-reports in a browser (the site
#    refuses scripts), set the filters Year: 2025 and State: OHIO, and
#    download the data (678 records and 27 columns on 2026-10-23).
# 2. Save the file as data-raw/SIRDataDownload.csv (git-ignored).
# 3. Run from the package root: Rscript data-raw/ohio_injuries.R
# A later download can hold more records; the checks below then stop.
#
# read.csv() and readr misparse the file: 10 narratives hold an unescaped
# quote (inch marks) and 6 hold a line break. So this script reads the lines,
# joins each continuation line to its record, and splits on `","`.

raw_path <- "data-raw/SIRDataDownload.csv"
if (!file.exists(raw_path)) {
  stop("Download the raw OSHA file first (see the steps at the top of this script).")
}
lines <- readLines(raw_path, encoding = "UTF-8", warn = FALSE)
header <- strsplit(lines[[1]], ",", fixed = TRUE)[[1]]
lines <- lines[-1]
lines <- lines[nzchar(lines)]

# A record starts with a line that begins with the quoted report ID
starts <- grepl('^"[0-9]{10,11}","', lines)
stopifnot(starts[[1]])
records <- split(lines, cumsum(starts)) |>
  purrr::map_chr(\(x) paste(x, collapse = " ")) |>
  unname()

fields <- records |>
  sub(pattern = '^"', replacement = "") |>
  sub(pattern = '"$', replacement = "") |>
  strsplit('","', fixed = TRUE)
stopifnot(length(fields) == 678, all(lengths(fields) == length(header)))

raw <- tibble::as_tibble(
  stats::setNames(
    purrr::map(seq_along(header), \(i) trimws(purrr::map_chr(fields, i))),
    header
  )
)
stopifnot(all(!stringi::stri_detect_regex(unlist(raw), "[^\\x01-\\x7F]")))

nature_map <- c(
  "Amputations, avulsions, enucleations  unspecified" = "amputation",
  "Amputations involving bone loss" = "amputation",
  "Fractures" = "fracture",
  "Nonfatal 'crushing' injuries" = "crushing injury",
  "Thermal burns  degree unspecified" = "thermal burn",
  "Thermal burns  second degree" = "thermal burn",
  "Thermal burns  third degree or higher" = "thermal burn",
  "Concussions" = "concussion"
)

event_divisions <- c(
  "1" = "Violence and other injuries by persons or animals",
  "2" = "Transportation incidents",
  "3" = "Fires and explosions",
  "4" = "Falls, slips, trips",
  "5" = "Exposure to harmful substances or environments",
  "6" = "Contact with objects and equipment",
  "7" = "Overexertion and bodily reaction",
  "9" = "Nonclassifiable"
)

source_divisions <- c(
  "1" = "Chemicals and chemical products",
  "2" = "Containers, furniture and fixtures",
  "3" = "Machinery",
  "4" = "Parts and materials",
  "5" = "Persons, plants, animals, and minerals",
  "6" = "Structures and surfaces",
  "7" = "Tools, instruments, and equipment",
  "8" = "Vehicles",
  "9" = "Other sources"
)

#' Make a factor of the OIICS divisions that occur, in code order
#' @param code The OIICS code, as text.
#' @param divisions A named character vector: first digit to title.
division_factor <- function(code, divisions) {
  digit <- substr(code, 1, 1)
  stopifnot(all(digit %in% names(divisions)))
  present <- names(divisions)[names(divisions) %in% digit]
  factor(unname(divisions[digit]), levels = unname(divisions[present]))
}

ohio_injuries <- raw |>
  dplyr::filter(NatureTitle %in% names(nature_map)) |>
  dplyr::transmute(
    id = ID,
    event_date = as.Date(EventDate),
    city = city,
    state = state,
    final_narrative = FinalNarrative,
    original_nature_title = NatureTitle,
    collapsed_nature_title = factor(
      unname(nature_map[NatureTitle]),
      levels = c("amputation", "fracture", "crushing injury", "thermal burn", "concussion")
    ),
    original_event_title = EventTitle,
    collapsed_event_title = division_factor(Event, event_divisions),
    original_source_title = sourceTitle,
    collapsed_source_title = division_factor(Source, source_divisions)
  )

stopifnot(nrow(ohio_injuries) == 464)
print(table(ohio_injuries$collapsed_nature_title))
usethis::use_data(ohio_injuries, overwrite = TRUE, compress = "xz")
