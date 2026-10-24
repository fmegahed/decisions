#' Prepare an image for a provider
#'
#' Reads an image, turns it upright, crops it, resizes it, converts it to sRGB
#' and returns it as JPEG bytes (quality 90). All work happens in memory.
#' The function applies no size limits: the provider is the authority on them.
#'
#' @param image A file path, a URL or a magick image. A file or a magick
#'   image with several frames (GIF, TIFF, PDF) gives its first frame.
#' @param max_size The longest side in pixels after the resize, or `NULL` to
#'   keep the resolution. The aspect ratio stays the same.
#' @param upscale `TRUE` enlarges an image whose longest side is smaller than
#'   `max_size`. `FALSE` (default) never enlarges.
#' @param crop `"none"` (default), `"center"` (a centered square), a numeric
#'   box `c(x, y, width, height)` in pixels with the origin at the top left,
#'   or a function that takes the magick image and returns such a box. The
#'   crop happens before the resize.
#' @param rgb `TRUE` writes three color channels. A gray image is otherwise
#'   written with one channel, which some servers (SGLang with Clef-Flash)
#'   cannot read.
#' @return A raw vector with the bytes of a JPEG image. It is not base64
#'   encoded.
#' @keywords internal
#' @noRd
prepare_image <- function(image, max_size = 768, upscale = FALSE,
                          crop = "none", rgb = FALSE) {
  rlang::check_installed("magick", reason = "to read images")
  if (!inherits(image, "magick-image")) {
    if (!rlang::is_string(image)) {
      cli::cli_abort("{.arg image} must be a path, a URL or a magick image.")
    }
    if (!grepl("^https?://", image) && !file.exists(image)) {
      cli::cli_abort("Image file not found: {.path {image}}")
    }
    image <- magick::image_read(image)
  }
  image <- magick::image_orient(image[1])

  if (!identical(crop, "none")) {
    box <- crop_box(image, crop)
    image <- magick::image_crop(
      image, magick::geometry_area(box[3], box[4], box[1], box[2])
    )
  }

  if (!is.null(max_size)) {
    info <- magick::image_info(image)
    if (upscale || max(info$width, info$height) > max_size) {
      image <- magick::image_resize(image, magick::geometry_size_pixels(max_size, max_size))
    }
  }

  image <- magick::image_convert(image, colorspace = "sRGB")
  if (rgb) image <- magick::image_convert(image, type = "TrueColor")
  magick::image_write(image, format = "jpeg", quality = 90)
}

#' Find the crop box of an image
#'
#' @param image A magick image.
#' @param crop `"center"`, a numeric box `c(x, y, width, height)` or a function
#'   that takes `image` and returns a box.
#' @return A numeric vector `c(x, y, width, height)` inside the image.
#' @noRd
crop_box <- function(image, crop) {
  info <- magick::image_info(image)
  if (is.function(crop)) crop <- crop(image)
  if (identical(crop, "center")) {
    side <- min(info$width, info$height)
    crop <- c((info$width - side) %/% 2, (info$height - side) %/% 2, side, side)
  }
  if (!is.numeric(crop)) {
    cli::cli_abort(
      "{.arg crop} must be {.val none}, {.val center}, a box or a function."
    )
  }
  if (length(crop) != 4 || anyNA(crop)) {
    cli::cli_abort("A crop box must have four numbers: x, y, width and height.")
  }
  if (any(crop < 0)) {
    cli::cli_abort("A crop box must have non-negative numbers.")
  }
  if (crop[3] == 0 || crop[4] == 0 ||
      crop[1] + crop[3] > info$width || crop[2] + crop[4] > info$height) {
    cli::cli_abort(
      "The crop box must be inside the image ({info$width} x {info$height} pixels)."
    )
  }
  crop
}
