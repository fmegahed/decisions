# locate(): where is the defect? Strategy T of the Box test of the study
# (D317): a Choice over 9 tiles with reference crops, then a Box in the two
# most likely tiles. The geometry below is the geometry of the code that
# passed the gate (box/R/{candidates,bank,regions}.R of the study, commit
# c21449e), in base R.

#' The 9 tiles of strategy T
#'
#' Tiles of half the image, with 50% overlap, in rows from the top left.
#'
#' @return A tibble with `tile` (`"t1"` to `"t9"`) and `left`, `top`,
#'   `right`, `bottom` as fractions of the image.
#' @noRd
locate_tiles <- function() {
  grid <- expand.grid(i = 0:2, j = 0:2)
  tibble::tibble(
    tile = paste0("t", grid$j * 3 + grid$i + 1),
    left = grid$i / 4, top = grid$j / 4,
    right = grid$i / 4 + 1 / 2, bottom = grid$j / 4 + 1 / 2
  )
}

#' The pixel crop around a box
#'
#' @param box A box as fractions of the image: left, top, right, bottom.
#' @param grow The factor that grows the box.
#' @param min_frac The smallest side of the crop, as a fraction of the short
#'   side of the image.
#' @param width,height The size of the image in pixels.
#' @return A list with `x0`, `y0` (the top left corner) and `w`, `h`, in
#'   pixels, inside the image. A crop is at most 5.5 times as long as wide:
#'   a thinner crop cannot have both sides in 280 to 1568 px.
#' @noRd
locate_crop <- function(box, grow = 1, min_frac = 0, width, height) {
  short <- min(width, height)
  cw <- max((box[[3]] - box[[1]]) * width * grow, min_frac * short, 16)
  ch <- max((box[[4]] - box[[2]]) * height * grow, min_frac * short, 16)
  cw <- max(cw, ch / 5.5)
  ch <- max(ch, cw / 5.5)
  cw <- min(round(cw), width)
  ch <- min(round(ch), height)
  cx <- (box[[1]] + box[[3]]) / 2 * width
  cy <- (box[[2]] + box[[4]]) / 2 * height
  list(
    x0 = round(min(max(cx - cw / 2, 0), width - cw)),
    y0 = round(min(max(cy - ch / 2, 0), height - ch)),
    w = cw, h = ch
  )
}

#' Map a Box answer on a crop to fractions of the image
#'
#' @param box The box of a Box answer: a list with `left`, `top`, `right`
#'   and `bottom` as fractions of the crop, or `NULL`.
#' @param crop A crop from `locate_crop()`.
#' @param width,height The size of the image in pixels.
#' @return Left, top, right and bottom as fractions of the image; `NA` for
#'   no box.
#' @noRd
locate_to_image <- function(box, crop, width, height) {
  if (is.null(box)) {
    return(rep(NA_real_, 4))
  }
  c(
    (crop$x0 + box$left * crop$w) / width, (crop$y0 + box$top * crop$h) / height,
    (crop$x0 + box$right * crop$w) / width, (crop$y0 + box$bottom * crop$h) / height
  )
}

#' The intersection over the union of two boxes
#'
#' @param a,b Boxes: left, top, right, bottom.
#' @return A number from 0 to 1; 0 when the union has no area.
#' @noRd
locate_iou <- function(a, b) {
  w <- max(0, min(a[[3]], b[[3]]) - max(a[[1]], b[[1]]))
  h <- max(0, min(a[[4]], b[[4]]) - max(a[[2]], b[[2]]))
  inter <- w * h
  union <- (a[[3]] - a[[1]]) * (a[[4]] - a[[2]]) +
    (b[[3]] - b[[1]]) * (b[[4]] - b[[2]]) - inter
  if (!is.finite(union) || union <= 0) {
    return(0)
  }
  inter / union
}

#' The second Box wording: the defect with its first article "the"
#'
#' @param defect One phrase, for example "a textile flaw (...)".
#' @return The phrase with a leading "a" or "an" changed to "the", or "the "
#'   before it when it has no article.
#' @noRd
locate_wording <- function(defect) {
  if (grepl("^the\\s", defect, ignore.case = TRUE)) {
    return(defect)
  }
  if (grepl("^an?\\s", defect, ignore.case = TRUE)) {
    return(sub("^an?\\s+", "the ", defect, ignore.case = TRUE))
  }
  paste("the", defect)
}
