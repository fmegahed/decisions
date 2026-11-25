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

#' Resize an image: the long side to `long` px, the short side at least 280 px
#'
#' @param img A magick image.
#' @param long The long side in pixels.
#' @return A magick image.
#' @noRd
locate_size <- function(img, long) {
  info <- magick::image_info(img)
  s <- max(long / max(info$width, info$height), 280 / min(info$width, info$height))
  magick::image_resize(img, sprintf("%dx%d!", round(info$width * s), round(info$height * s)))
}

#' A TypeSafe image asset of a magick image (sRGB JPEG, quality 92, as in
#' D307)
#' @noRd
locate_asset <- function(img) {
  img <- magick::image_convert(img, colorspace = "sRGB")
  image_asset(as.raw(magick::image_write(img, format = "jpeg", quality = 92)))
}

#' The reference crops in the state: their assets, keys and note
#'
#' @param references A list with `nominal` and `defective`, each a list of
#'   magick images.
#' @param defect The phrase of the defect.
#' @return A list with `state` (the note and a key for each example) and
#'   `assets`.
#' @noRd
locate_references <- function(references, defect) {
  examples <- c(
    purrr::imap(references$nominal, \(img, i) list(
      name = paste0("nominal_example_", i), key = paste0("reference_nominal_", i),
      img = img, note = "a part with no defect"
    )),
    purrr::imap(references$defective, \(img, i) list(
      name = paste0("defective_example_", i), key = paste0("reference_defective_", i),
      img = img, note = defect
    ))
  )
  note <- paste0(
    "Each question shows one part of the same inspection image. ",
    "Examples from other images: ",
    paste0("`", purrr::map_chr(examples, "name"), "` shows ", purrr::map_chr(examples, "note"), collapse = "; "),
    "."
  )
  list(
    state = c(
      list(note = note),
      rlang::set_names(purrr::map(examples, "key"), purrr::map_chr(examples, "name"))
    ),
    assets = rlang::set_names(
      purrr::map(examples, \(x) locate_asset(locate_size(x$img, 560))),
      purrr::map_chr(examples, "key")
    )
  )
}

#' The body of T1: a Choice over the 9 tiles and "none"
#'
#' @param model The model name.
#' @param image The magick image to inspect.
#' @param defect The phrase of the defect, with its article.
#' @param references See `locate_references()`.
#' @return A list for `httr2::req_body_json()`.
#' @noRd
locate_body_tiles <- function(model, image, defect, references) {
  info <- magick::image_info(image)
  tiles <- locate_tiles()
  keys <- paste0("tile_", tiles$tile)
  crops <- purrr::map(seq_len(nrow(tiles)), \(k) {
    g <- locate_crop(unlist(tiles[k, c("left", "top", "right", "bottom")]), width = info$width, height = info$height)
    locate_size(magick::image_crop(image, sprintf("%dx%d+%d+%d", g$w, g$h, g$x0, g$y0)), 560)
  })
  refs <- locate_references(references, defect)
  question <- list(
    type = "choice",
    instructions = paste0("Which picture shows ", defect, "? Compare it with the examples."),
    criteria = c(
      rlang::set_names(as.list(paste0("this picture: ", keys)), tiles$tile),
      list(none = paste0("None of the pictures shows ", defect, "."))
    )
  )
  list(
    model = model,
    questions = list(q001 = question),
    assets = c(rlang::set_names(purrr::map(crops, locate_asset), keys), refs$assets),
    state = refs$state
  )
}

#' The body of T2: a Box in two tiles, with two wordings
#'
#' @inheritParams locate_body_tiles
#' @param tiles Two rows of `locate_tiles()`: the most likely tile first.
#' @return A list with `body` and `crops` (the pixel crops, to map the boxes
#'   back to the image).
#' @noRd
locate_body_boxes <- function(model, image, tiles, defect, references) {
  info <- magick::image_info(image)
  crops <- purrr::map(seq_len(nrow(tiles)), \(k) locate_crop(
    unlist(tiles[k, c("left", "top", "right", "bottom")]), grow = 1.2,
    width = info$width, height = info$height
  ))
  keys <- paste0("crop_", seq_along(crops))
  wordings <- c("the defect", locate_wording(defect))
  questions <- unlist(purrr::map(keys, \(key) purrr::map(wordings, \(w) list(
    type = "box", instructions = paste0(w, " in this picture: ", key)
  ))), recursive = FALSE)
  names(questions) <- sprintf("q%03d", seq_along(questions))
  refs <- locate_references(references, defect)
  assets <- rlang::set_names(purrr::map(crops, \(g) locate_asset(locate_size(
    magick::image_crop(image, sprintf("%dx%d+%d+%d", g$w, g$h, g$x0, g$y0)), 1024
  ))), keys)
  list(
    body = list(model = model, questions = questions, assets = c(assets, refs$assets), state = refs$state),
    crops = crops
  )
}

#' Read the answer of T1
#'
#' @param answer The answer of the Choice (`answers$q001` of the response).
#' @return A list with `choice`, `tiles` (the probability of each tile, named
#'   `t1` to `t9`) and `none`.
#' @noRd
locate_read_tiles <- function(answer) {
  p <- answer$probabilities
  tiles <- paste0("t", 1:9)
  if (!is.list(p) || !all(c(tiles, "none") %in% names(p))) {
    cli::cli_abort("The tile answer has no probability for each tile and for {.val none}.")
  }
  list(choice = answer$choice, tiles = unlist(p[tiles]), none = p$none)
}

#' Read the answers of T2 and pick the box
#'
#' The answer is the box of the first tile, with the wording whose two boxes
#' (first and second tile) agree more (IoU); on a tie, the wording with the
#' higher mean confidence. As in D307, an answer with no box agrees with
#' nothing, and its box is `NA`.
#'
#' @param answers The answers of the response: `q001` and `q002` (first tile,
#'   generic and defect wording), `q003` and `q004` (second tile).
#' @param crops The crops of `locate_body_boxes()`.
#' @param width,height The size of the image in pixels.
#' @return A list with `box` (left, top, right, bottom as fractions of the
#'   image), `confidence` and `wording` (`"generic"` or `"defect"`).
#' @noRd
locate_read_boxes <- function(answers, crops, width, height) {
  item <- \(k) answers[[sprintf("q%03d", k)]]
  boxes <- purrr::map(1:4, \(k) locate_to_image(item(k)$box, crops[[(k + 1) %/% 2]], width, height))
  confidence <- purrr::map_dbl(1:4, \(k) item(k)$confidence %||% NA_real_)
  agree_of <- \(a, b) if (anyNA(c(a, b))) 0 else locate_iou(a, b)
  agree <- c(generic = agree_of(boxes[[1]], boxes[[3]]), defect = agree_of(boxes[[2]], boxes[[4]]))
  conf <- c(
    generic = mean(confidence[c(1, 3)], na.rm = TRUE),
    defect = mean(confidence[c(2, 4)], na.rm = TRUE)
  )
  defect <- agree[["defect"]] > agree[["generic"]] ||
    (agree[["defect"]] == agree[["generic"]] && isTRUE(conf[["defect"]] > conf[["generic"]]))
  k <- if (defect) 2 else 1
  list(box = boxes[[k]], confidence = confidence[[k]], wording = if (defect) "defect" else "generic")
}
