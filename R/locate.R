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
    purrr::imap(unname(references$nominal), \(img, i) list(
      name = paste0("nominal_example_", i), key = paste0("reference_nominal_", i),
      img = img, note = "a part with no defect"
    )),
    purrr::imap(unname(references$defective), \(img, i) list(
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
  number <- \(x) is.numeric(x) && length(x) == 1 && is.finite(x)
  if (!is.list(p) || !all(c(tiles, "none") %in% names(p)) ||
      !all(purrr::map_lgl(p[c(tiles, "none")], number))) {
    cli::cli_abort(
      "The tile answer has no probability (one number) for each tile and for {.val none}."
    )
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

#' Locate a defect in images (experimental)
#'
#' `locate()` asks TypeSafe where the defect is in each image: a Choice over
#' 9 tiles of the image with reference crops, then a Box in the two most
#' likely tiles. These are the steps that passed the Box test of the study.
#' On the 46 textile inputs of the package, one run of `locate()` pointed to
#' 14 of the 14 local defects and put a box on 1 of the 23 nominal images
#' (`vignette("images")`, section "Defect location").
#'
#' Box is experimental. Only Jev 1.14 and later have it, and TypeSafe can
#' change it between releases. Check the boxes on images with a known defect
#' before you use them.
#'
#' @section Steps:
#' 1. One request for each image: a Choice "Which picture shows `defect`?
#'    Compare it with the examples." over 9 tiles of half the image, with
#'    50% overlap, and the answer "none". The tiles and the references are
#'    sent at 560 pixels. The references go in the state, with a note that names
#'    each of them.
#' 2. If the answer is not "none", one more request: a Box in each of the
#'    two most likely tiles (grown by 1.2, sent at 1024 pixels), with two
#'    wordings: "the defect", and `defect` with its first article changed to
#'    "the". The answer is the box in the most likely tile, with the wording
#'    whose two boxes agree more; on a tie, the wording with the higher mean
#'    confidence.
#'
#' Each image is enlarged so that its short side is at least 280 pixels, the
#' smallest size that TypeSafe takes.
#'
#' @param decider A decider from [decider_typesafe()] with Jev 1.14 or later,
#'   for example `decider_typesafe("jev-1.14.0")` or `"jev-latest"`.
#' @param image The images: paths, URLs or magick images, as in [decide()].
#' @param defect One phrase for the defect, with its article, for example
#'   `"a textile flaw (a small patch where the weave is replaced by noise)"`.
#' @param references A list with `nominal` and `defective`. Each is a list of
#'   images (paths, URLs or magick images): parts with no defect, and parts
#'   with the defect, at about the scale of a tile (half the side of an
#'   inspected image). `locate()` does not crop them.
#' @inheritParams decide
#' @return A tibble with one row for each image, in the input order:
#'   \describe{
#'     \item{.pred_defect}{1 minus the probability of "none" in step 1.}
#'     \item{.box_left, .box_top, .box_right, .box_bottom}{The box as
#'       fractions of the width and the height of the image, with the origin
#'       at the top left. `NA` when step 1 says "none".}
#'     \item{.box_confidence}{The confidence of the Box answer.}
#'     \item{.wording}{The wording of the box: `"generic"` ("the defect") or
#'       `"defect"` (the phrase of `defect`).}
#'     \item{.input_tokens}{The input tokens of the requests of the image.}
#'     \item{.cost}{`NA`: TypeSafe does not report a cost.}
#'     \item{.seconds}{The time of the requests of the image.}
#'     \item{.error}{`NA`, or why the row has no answer.}
#'   }
#'   The attribute `requests` is the number of requests sent: one or two for
#'   each image.
#' @examples
#' \dontrun{
#' dir <- system.file("extdata", "textiles", package = "decisions")
#' read <- \(f) magick::image_read(file.path(dir, f))
#' references <- list(
#'   nominal = list(
#'     magick::image_crop(read("nominal_textile_0630.jpg"), "125x125+62+62"),
#'     magick::image_crop(read("nominal_textile_0731.jpg"), "125x125+62+62")
#'   ),
#'   defective = list(
#'     magick::image_crop(read("local_textile_0199.jpg"), "125x125+56+68")
#'   )
#' )
#' locate(
#'   decider_typesafe("jev-1.14.0"),
#'   image = file.path(dir, "local_textile_0319.jpg"),
#'   defect = paste(
#'     "a textile flaw (a small patch where the regular diagonal weave is",
#'     "replaced by fine speckled noise)"
#'   ),
#'   references = references
#' )
#' }
#' @export
locate <- function(decider, image, defect, references, max_active = 10,
                   rpm = NULL) {
  check_locate_decider(decider)
  if (!rlang::is_string(defect) || !nzchar(defect)) {
    cli::cli_abort("{.arg defect} must be one phrase, for example {.val a dent}.")
  }
  check_locate_references(references)
  check_rpm(rpm)
  rlang::check_installed("magick", reason = "to cut the images into tiles")
  # The images are read when their requests are built, so that no decoded
  # image stays in memory for the whole call
  images <- as_images(image)
  if (length(images) == 0) {
    cli::cli_abort("{.arg image} must give one image or more.")
  }
  refs <- purrr::map(references[c("nominal", "defective")], \(x) purrr::map(x, locate_image))
  key <- read_key(decider)
  base <- new_request(decider, key, images = TRUE, rpm = rpm)
  send <- function(bodies) {
    if (length(bodies) == 0) {
      return(structure(list(), requests = 0))
    }
    requests <- purrr::map(bodies, \(b) httr2::req_body_json(base, b))
    responses <- perform_requests(requests, max_active)
    structure(
      purrr::map2(responses, requests, locate_response, decider = decider),
      requests = attr(responses, "requests"),
      interrupted = isTRUE(attr(responses, "interrupted"))
    )
  }

  # Step 1: the tiles
  sizes <- list()
  t1 <- send(purrr::imap(images, \(x, i) {
    img <- locate_image(x)
    sizes[[i]] <<- magick::image_info(img)[c("width", "height")]
    locate_body_tiles(decider@model, img, defect, refs)
  }))
  rows <- purrr::map(t1, locate_row_tiles)

  # Step 2: the boxes, for the images whose answer is not "none". After an
  # interrupt (Esc), no step-2 request goes out.
  ask <- which(purrr::map_lgl(rows, \(r) is.na(r$.error) && !r$none))
  if (isTRUE(attr(t1, "interrupted"))) {
    for (i in ask) rows[[i]]$.error <- "Step 2 was not sent: the call was interrupted."
    ask <- integer()
  }
  t2_bodies <- purrr::map(ask, \(i) locate_body_boxes(
    decider@model, locate_image(images[[i]]), locate_tiles()[rows[[i]]$top, ], defect, refs
  ))
  t2 <- send(purrr::map(t2_bodies, "body"))
  for (j in seq_along(ask)) {
    i <- ask[[j]]
    rows[[i]] <- locate_row_boxes(rows[[i]], t2[[j]], t2_bodies[[j]]$crops, sizes[[i]]$width, sizes[[i]]$height)
  }

  out <- tibble::tibble(
    .pred_defect = purrr::map_dbl(rows, ".pred_defect"),
    .box_left = purrr::map_dbl(rows, \(r) r$box[[1]]),
    .box_top = purrr::map_dbl(rows, \(r) r$box[[2]]),
    .box_right = purrr::map_dbl(rows, \(r) r$box[[3]]),
    .box_bottom = purrr::map_dbl(rows, \(r) r$box[[4]]),
    .box_confidence = purrr::map_dbl(rows, ".box_confidence"),
    .wording = purrr::map_chr(rows, ".wording"),
    .input_tokens = purrr::map_dbl(rows, ".input_tokens"),
    .cost = NA_real_,
    .seconds = purrr::map_dbl(rows, ".seconds"),
    .error = purrr::map_chr(rows, ".error")
  )
  structure(out, requests = attr(t1, "requests") + attr(t2, "requests"))
}

#' Check that a decider can run locate(): TypeSafe, Jev 1.14 or later
#' @noRd
check_locate_decider <- function(decider) {
  if (!S7::S7_inherits(decider, decider_class) || !identical(decider@provider, "typesafe")) {
    cli::cli_abort(c(
      "{.fn locate} needs a TypeSafe decider from {.fn decider_typesafe}.",
      i = "Only Jev 1.14 and later answer Box questions."
    ))
  }
  version <- regmatches(decider@model, regexec("^jev-([0-9]+)[.]([0-9]+)", decider@model))[[1]]
  if (length(version) == 3 &&
      numeric_version(paste(version[[2]], version[[3]], sep = ".")) < "1.14") {
    cli::cli_abort(c(
      "{.fn locate} needs Jev 1.14 or later: {.val {decider@model}} has no Box question.",
      i = "Use {.code decider_typesafe(\"jev-1.14.0\")} or {.val jev-latest}."
    ))
  }
  invisible(decider)
}

#' Check the references of locate()
#' @noRd
check_locate_references <- function(references) {
  parts <- c("nominal", "defective")
  ok <- is.list(references) && all(parts %in% names(references)) &&
    all(purrr::map_lgl(references[parts], \(x) is.list(x) && length(x) > 0))
  if (!ok) {
    cli::cli_abort(c(
      "{.arg references} must be a list with {.field nominal} and {.field defective}.",
      i = "Each is a list of one image or more: a path, a URL or a magick image."
    ))
  }
  invisible(references)
}

#' Read one image for locate(): a path, a URL or a magick image
#' @noRd
locate_image <- function(x) {
  if (!inherits(x, "magick-image")) {
    if (!rlang::is_string(x)) {
      cli::cli_abort("Each image must be a path, a URL or a magick image.")
    }
    if (!grepl("^https?://", x) && !file.exists(x)) {
      cli::cli_abort("Image file not found: {.path {x}}")
    }
    x <- magick::image_read(x)
  }
  magick::image_orient(x[1])
}

#' Read one response of locate()
#'
#' @return A list with `answers`, `input_tokens`, `seconds` and `error`
#'   (`NA` when the response has answers).
#' @noRd
locate_response <- function(response, request, decider) {
  if (!inherits(response, "httr2_response")) {
    reason <- if (is.null(response)) "the request did not finish." else condition_text(response)
    return(failed_result("No response", reason, decider, request))
  }
  seconds <- httr2::resp_timing(response)[["total"]] %||% NA_real_
  text <- if (httr2::resp_has_body(response)) {
    tryCatch(httr2::resp_body_string(response), error = \(e) "")
  } else {
    ""
  }
  if (httr2::resp_is_error(response)) {
    return(failed_result(paste("HTTP", httr2::resp_status(response)), text, decider, request, seconds))
  }
  body <- tryCatch(jsonlite::parse_json(text), error = identity)
  if (inherits(body, "error") || !is.list(body) || !is.list(body$answers)) {
    return(failed_result("The response cannot be read", text, decider, request, seconds))
  }
  usage <- body$usage
  tokens <- if (is.list(usage) && is.numeric(usage$input_tokens) && length(usage$input_tokens) == 1) {
    as.numeric(usage$input_tokens)
  } else {
    NA_real_
  }
  list(answers = body$answers, input_tokens = tokens, seconds = seconds, error = NA_character_)
}

#' The row of an image after step 1
#' @noRd
locate_row_tiles <- function(result) {
  row <- list(
    .pred_defect = NA_real_, box = rep(NA_real_, 4), .box_confidence = NA_real_,
    .wording = NA_character_, .input_tokens = result$input_tokens,
    .seconds = result$seconds, .error = result$error, none = TRUE, top = NULL
  )
  if (!is.na(row$.error)) {
    return(row)
  }
  read <- tryCatch(
    {
      read <- locate_read_tiles(result$answers$q001)
      list(pred = 1 - read$none, none = identical(read$choice, "none"), top = order(-read$tiles)[1:2])
    },
    error = identity
  )
  if (inherits(read, "error")) {
    row$.error <- paste("Step 1:", condition_text(read))
    return(row)
  }
  row$.pred_defect <- read$pred
  row$none <- read$none
  row$top <- read$top
  row
}

#' The row of an image after step 2
#' @noRd
locate_row_boxes <- function(row, result, crops, width, height) {
  add <- \(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
  row$.input_tokens <- add(c(row$.input_tokens, result$input_tokens))
  row$.seconds <- add(c(row$.seconds, result$seconds))
  if (!is.na(result$error)) {
    row$.error <- result$error
    return(row)
  }
  read <- tryCatch(locate_read_boxes(result$answers, crops, width, height), error = identity)
  if (inherits(read, "error")) {
    row$.error <- paste("Step 2:", condition_text(read))
  } else if (anyNA(read$box)) {
    row$.error <- "Step 2: the Box answer in the most likely tile has no box."
  } else {
    row$box <- read$box
    row$.box_confidence <- read$confidence
    row$.wording <- read$wording
  }
  row
}
