skip_if_not_installed("magick")

# Size of the JPEG bytes that prepare_image() returns.
jpeg_size <- function(bytes) {
  info <- magick::image_info(magick::image_read(bytes))
  c(width = info$width, height = info$height)
}

blank <- function(width, height, ...) magick::image_blank(width, height, ...)

test_that("a large image is resized to max_size and keeps its aspect ratio", {
  out <- prepare_image(blank(2000, 1000), max_size = 768)
  expect_type(out, "raw")
  expect_equal(unname(jpeg_size(out)), c(768, 384))
  expect_equal(magick::image_info(magick::image_read(out))$format, "JPEG")
})

test_that("upscale controls whether a small image is enlarged", {
  expect_equal(unname(jpeg_size(prepare_image(blank(400, 300)))), c(400, 300))
  expect_equal(
    unname(jpeg_size(prepare_image(blank(400, 300), upscale = TRUE))),
    c(768, 576)
  )
})

test_that("max_size = NULL keeps the resolution", {
  out <- prepare_image(blank(2000, 1000), max_size = NULL, upscale = TRUE)
  expect_equal(unname(jpeg_size(out)), c(2000, 1000))
})

test_that("crop accepts center, a box and a function", {
  img <- blank(2000, 1000)
  expect_equal(
    unname(jpeg_size(prepare_image(img, max_size = NULL, crop = "center"))),
    c(1000, 1000)
  )
  expect_equal(
    unname(jpeg_size(prepare_image(img, max_size = NULL, crop = c(10, 10, 100, 50)))),
    c(100, 50)
  )
  expect_equal(
    unname(jpeg_size(prepare_image(img, crop = function(x) c(0, 0, 50, 50)))),
    c(50, 50)
  )
})

test_that("crop happens before resize", {
  out <- prepare_image(blank(2000, 1000), max_size = 100, crop = c(0, 0, 400, 200))
  expect_equal(unname(jpeg_size(out)), c(100, 50))
})

test_that("a bad crop box stops with a clear message", {
  img <- blank(200, 100)
  expect_error(prepare_image(img, crop = c(0, 0, 50)), "four numbers")
  expect_error(prepare_image(img, crop = c(-1, 0, 50, 50)), "non-negative")
  expect_error(prepare_image(img, crop = c(150, 0, 100, 50)), "inside the image")
  expect_error(prepare_image(img, crop = "middle"), "crop")
})

test_that("rgb = TRUE writes three channels for a gray image", {
  gray <- magick::image_convert(blank(300, 300, color = "gray50"), type = "Grayscale")
  one <- magick::image_info(magick::image_read(prepare_image(gray)))
  three <- magick::image_info(magick::image_read(prepare_image(gray, rgb = TRUE)))
  expect_equal(one$colorspace, "Gray")
  expect_equal(three$colorspace, "sRGB")
  # One-channel JPEG bytes are smaller than three-channel ones.
  expect_gt(length(prepare_image(gray, rgb = TRUE)), length(prepare_image(gray)))
})

test_that("a CMYK image comes back as sRGB JPEG", {
  cmyk <- magick::image_convert(blank(300, 300, color = "red"), colorspace = "cmyk")
  info <- magick::image_info(magick::image_read(prepare_image(cmyk)))
  expect_equal(info$format, "JPEG")
  expect_equal(info$colorspace, "sRGB")
})

test_that("a PNG with an alpha channel comes back as sRGB JPEG", {
  path <- withr::local_tempfile(fileext = ".png")
  magick::image_write(blank(300, 300, color = "#ff000080"), path, format = "png")
  info <- magick::image_info(magick::image_read(prepare_image(path)))
  expect_equal(info$format, "JPEG")
  expect_equal(info$colorspace, "sRGB")
  expect_false(info$matte)
})

test_that("EXIF orientation 6 comes back upright", {
  # magick cannot write EXIF, so splice an APP1 segment (orientation = 6,
  # big-endian TIFF) right after the SOI marker of a plain 40 x 20 JPEG.
  jpg <- magick::image_write(blank(40, 20, color = "red"), format = "jpeg")
  exif <- as.raw(c(
    0xff, 0xe1, 0x00, 0x22, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00,
    0x4d, 0x4d, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08,
    0x00, 0x01, 0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01,
    0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
  ))
  path <- withr::local_tempfile(fileext = ".jpg")
  writeBin(c(jpg[1:2], exif, jpg[-(1:2)]), path)
  expect_equal(unname(jpeg_size(magick::image_read(path) |> magick::image_write(format = "jpeg"))), c(40, 20))
  expect_equal(unname(jpeg_size(prepare_image(path, max_size = NULL))), c(20, 40))
})

test_that("a missing path stops and names the path", {
  expect_error(prepare_image("no/such/image.jpg"), "no/such/image.jpg", fixed = TRUE)
})
