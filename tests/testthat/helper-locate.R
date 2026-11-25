# Shared by the tests of locate() and by probe_locate() in
# data-raw/probe_providers.R, so that the fixtures and the tests use the same
# inputs.

#' One textile input, the references of D307 and the defect phrase of D307
locate_inputs <- function() {
  dir <- system.file("extdata", "textiles", package = "decisions")
  read <- \(f) magick::image_read(file.path(dir, f))
  crop <- \(img, x0, y0, side) magick::image_crop(img, sprintf("%dx%d+%d+%d", side, side, x0, y0))
  list(
    image = read("local_textile_0319.jpg"),
    references = list(
      nominal = list(
        crop(read("nominal_textile_0630.jpg"), 62, 62, 125),
        crop(read("nominal_textile_0731.jpg"), 62, 62, 125)
      ),
      defective = list(crop(read("local_textile_0199.jpg"), 56, 68, 125))
    ),
    defect = paste(
      "a textile flaw (a small patch where the regular diagonal weave is",
      "replaced by fine speckled noise)"
    )
  )
}

#' A body with each image replaced by "<jpeg WIDTHxHEIGHT>"
#'
#' JPEG bytes can change with the version of ImageMagick, so the fixtures
#' keep the size of each image, not its bytes.
locate_strip_bytes <- function(body) {
  body$assets <- lapply(body$assets, \(a) {
    info <- magick::image_info(magick::image_read(jsonlite::base64_dec(a$data_base64)))
    a$data_base64 <- sprintf("<jpeg %dx%d>", info$width, info$height)
    a
  })
  body
}
