# Small, license-free test images (made here, no outside source).
# A gray background with fine noise; the defect is a dark streak.
set.seed(1)
make_image <- function(angle = NULL) {
  img <- magick::image_blank(280, 280, color = "gray60") |>
    magick::image_noise("gaussian") |>
    magick::image_convert(type = "Grayscale")
  if (!is.null(angle)) {
    streak <- magick::image_blank(240, 8, color = "gray10") |>
      magick::image_background("none") |>
      magick::image_rotate(angle)
    img <- magick::image_composite(img, streak, gravity = "center")
  }
  magick::image_convert(img, colorspace = "sRGB", type = "TrueColor")
}
out <- "data-raw"
write_jpeg <- function(img, name) {
  magick::image_write(img, file.path(out, name), format = "jpeg", quality = 85)
}
write_jpeg(make_image(35), "test-image-streak.jpg")
write_jpeg(make_image(-30), "test-image-reference-defect.jpg")
write_jpeg(make_image(), "test-image-reference-normal.jpg")
print(file.size(list.files(out, "jpg$", full.names = TRUE)))
print(magick::image_info(magick::image_read(file.path(out, "test-image-streak.jpg"))))
