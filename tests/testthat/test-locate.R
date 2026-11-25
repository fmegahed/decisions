# The geometry helpers of locate() (strategy T of D317; the code that passed
# the gate is box/R/{candidates,bank,regions}.R of the study, commit c21449e)

test_that("locate_tiles() gives 9 tiles of half the image with 50% overlap", {
  tiles <- locate_tiles()
  expect_equal(tiles$tile, paste0("t", 1:9))
  expect_equal(unlist(tiles[1, c("left", "top", "right", "bottom")]),
               c(left = 0, top = 0, right = 0.5, bottom = 0.5))
  expect_equal(unlist(tiles[2, c("left", "top", "right", "bottom")]),
               c(left = 0.25, top = 0, right = 0.75, bottom = 0.5))
  expect_equal(unlist(tiles[5, c("left", "top", "right", "bottom")]),
               c(left = 0.25, top = 0.25, right = 0.75, bottom = 0.75))
  expect_equal(unlist(tiles[9, c("left", "top", "right", "bottom")]),
               c(left = 0.5, top = 0.5, right = 1, bottom = 1))
})

test_that("locate_crop() grows a box, keeps it square enough and inside the image", {
  expect_equal(
    locate_crop(c(0.25, 0.25, 0.75, 0.75), grow = 1.2, width = 250, height = 250),
    list(x0 = 50, y0 = 50, w = 150, h = 150)
  )
  # Near the corner: moved inside the image
  expect_equal(
    locate_crop(c(0.9, 0.9, 1, 1), grow = 3, width = 250, height = 250),
    list(x0 = 175, y0 = 175, w = 75, h = 75)
  )
  # A thin box: at most 5.5 times as long as wide, before the rounding to
  # whole pixels (here 200 / 36)
  thin <- locate_crop(c(0.1, 0.1, 0.9, 0.12), width = 250, height = 250)
  expect_equal(c(thin$w, thin$h), c(200, 36))
  expect_lte(thin$w / (thin$h + 0.5), 5.5)
})

test_that("locate_to_image() maps a box of a crop to fractions of the image", {
  crop <- list(x0 = 50, y0 = 50, w = 150, h = 150)
  box <- list(left = 0.2, top = 0.4, right = 0.6, bottom = 0.8)
  expect_equal(locate_to_image(box, crop, 250, 250), c(0.32, 0.44, 0.56, 0.68))
  expect_equal(locate_to_image(NULL, crop, 250, 250), rep(NA_real_, 4))
})

test_that("locate_iou() is the intersection over the union", {
  expect_equal(locate_iou(c(0, 0, 1, 1), c(0, 0, 1, 1)), 1)
  expect_equal(locate_iou(c(0, 0, 1, 1), c(2, 2, 3, 3)), 0)
  expect_equal(locate_iou(c(0, 0, 1, 1), c(0.5, 0, 1.5, 1)), 1 / 3)
  expect_equal(locate_iou(c(0, 0, 0, 0), c(0, 0, 0, 0)), 0)
})

test_that("locate_wording() changes the first article to 'the'", {
  expect_equal(
    locate_wording("a textile flaw (a small patch of noise)"),
    "the textile flaw (a small patch of noise)"
  )
  expect_equal(locate_wording("an open seam"), "the open seam")
  expect_equal(locate_wording("scratches on the lens"), "the scratches on the lens")
  expect_equal(locate_wording("the dent"), "the dent")
})

# The bodies of T1 and T2 -------------------------------------------------

skip_if_no_magick <- function() testthat::skip_if_not_installed("magick")

# locate_inputs() is in helper-locate.R

test_that("locate_size() enlarges to the long side, at least 280 px on the short side", {
  skip_if_no_magick()
  img <- magick::image_blank(125, 125)
  expect_equal(unlist(magick::image_info(locate_size(img, 560))[c("width", "height")]), c(width = 560, height = 560))
  wide <- magick::image_blank(200, 36)
  info <- magick::image_info(locate_size(wide, 1024))
  expect_gte(min(info$width, info$height), 280)
})

test_that("the T1 body asks a Choice over 9 tiles and none, with the reference crops in the state", {
  skip_if_no_magick()
  x <- locate_inputs()
  body <- locate_body_tiles("jev-1.14.0", x$image, x$defect, x$references)
  expect_named(body, c("model", "questions", "assets", "state"))
  q <- body$questions$q001
  expect_equal(q$type, "choice")
  expect_equal(q$instructions, paste0("Which picture shows ", x$defect, "? Compare it with the examples."))
  expect_named(q$criteria, c(paste0("t", 1:9), "none"))
  expect_equal(q$criteria$t1, "this picture: tile_t1")
  expect_equal(q$criteria$none, paste0("None of the pictures shows ", x$defect, "."))
  expect_setequal(names(body$assets), c(paste0("tile_t", 1:9), "reference_nominal_1", "reference_nominal_2", "reference_defective_1"))
  expect_equal(body$state$nominal_example_1, "reference_nominal_1")
  expect_equal(body$state$defective_example_1, "reference_defective_1")
  expect_match(body$state$note, "^Each question shows one part of the same inspection image. Examples from other images:")
  expect_match(body$state$note, paste0("`defective_example_1` shows ", x$defect), fixed = TRUE)
  expect_equal(body$assets$tile_t1$type, "image")
  expect_false(grepl("\n", body$assets$tile_t1$data_base64, fixed = TRUE))
})

test_that("the T2 body asks a Box in two tiles with two wordings, one crop per tile", {
  skip_if_no_magick()
  x <- locate_inputs()
  tiles <- locate_tiles()
  t2 <- locate_body_boxes("jev-1.14.0", x$image, tiles[c(5, 2), ], x$defect, x$references)
  body <- t2$body
  expect_equal(names(body$questions), sprintf("q%03d", 1:4))
  expect_equal(purrr::map_chr(body$questions, "type"), rep("box", 4), ignore_attr = TRUE)
  expect_equal(
    purrr::map_chr(body$questions, "instructions"),
    c("the defect in this picture: crop_1", paste0(locate_wording(x$defect), " in this picture: crop_1"),
      "the defect in this picture: crop_2", paste0(locate_wording(x$defect), " in this picture: crop_2")),
    ignore_attr = TRUE
  )
  expect_setequal(names(body$assets), c("crop_1", "crop_2", "reference_nominal_1", "reference_nominal_2", "reference_defective_1"))
  expect_equal(t2$crops[[1]], locate_crop(unlist(tiles[5, c("left", "top", "right", "bottom")]), grow = 1.2, width = 250, height = 250))
})

test_that("the T1 and T2 bodies equal the saved requests of probe_locate()", {
  skip_if_no_magick()
  x <- locate_inputs()
  saved <- \(f) jsonlite::read_json(test_path("fixtures", f))
  t1 <- locate_body_tiles("jev-1.14.0", x$image, x$defect, x$references)
  expect_equal(locate_strip_bytes(t1), saved("locate-t1-request.json"))
  # T1 chose t2, then t1 (fixture locate-t1.json)
  t2 <- locate_body_boxes("jev-1.14.0", x$image, locate_tiles()[c(2, 1), ], x$defect, x$references)
  expect_equal(locate_strip_bytes(t2$body), saved("locate-t2-request.json"))
})

test_that("a CMYK image goes as an sRGB JPEG", {
  skip_if_no_magick()
  # A color image: ImageMagick writes gray content as a gray JPEG in any case
  cmyk <- magick::image_convert(magick::image_blank(64, 64, "#C41230"), colorspace = "cmyk")
  asset <- locate_asset(cmyk)
  img <- magick::image_read(jsonlite::base64_dec(asset$data_base64))
  expect_equal(magick::image_info(img)$colorspace, "sRGB")
})

# The readers ---------------------------------------------------------------

saved_answers <- \(f) jsonlite::read_json(test_path("fixtures", f))$answers

test_that("locate_read_tiles() reads the tile probabilities and P(none)", {
  read <- locate_read_tiles(saved_answers("locate-t1.json")$q001)
  expect_equal(read$choice, "t2")
  expect_equal(read$tiles, c(t1 = 0.21, t2 = 0.29, t3 = 0.03, t4 = 0.14, t5 = 0.17,
                             t6 = 0.05, t7 = 0.02, t8 = 0.01, t9 = 0.01))
  expect_equal(read$none, 0.07)
  expect_error(locate_read_tiles(list(choice = "t1")), "no probability")
})

# The crops of T2 for tiles t2 and t1 of a 250 x 250 image:
# (50, 0, 150 x 150) and (0, 0, 150 x 150)
t2_crops <- function() {
  purrr::map(c(2, 1), \(k) locate_crop(
    unlist(locate_tiles()[k, c("left", "top", "right", "bottom")]),
    grow = 1.2, width = 250, height = 250
  ))
}

test_that("locate_read_boxes() gives the box of the first tile with the wording that agrees more", {
  crops <- t2_crops()
  expect_equal(crops[[1]], list(x0 = 50, y0 = 0, w = 150, h = 150))
  # q001 maps to (50 + 0.26 * 150) / 250 = 0.356, ...; IoU of the generic
  # boxes (q001, q003) 0.576, of the defect boxes (q002, q004) 0.422
  read <- locate_read_boxes(saved_answers("locate-t2.json"), crops, 250, 250)
  expect_equal(read$box, c(0.356, 0.354, 0.398, 0.444))
  expect_equal(read$confidence, 0.84)
  expect_equal(read$wording, "generic")
})

test_that("a Box answer with no box agrees with nothing (as in D307)", {
  answers <- saved_answers("locate-t2.json")
  answers$q003$box <- NULL
  read <- locate_read_boxes(answers, t2_crops(), 250, 250)
  expect_equal(read$wording, "defect")
  expect_equal(read$box, c(0.356, 0.354, 0.404, 0.438))
  expect_equal(read$confidence, 0.88)
  # No box in the first tile with the picked wording: NA box
  answers$q001$box <- NULL
  answers$q002$box <- NULL
  read <- locate_read_boxes(answers, t2_crops(), 250, 250)
  expect_equal(read$box, rep(NA_real_, 4))
})

# locate() ------------------------------------------------------------------

jev14 <- decider_typesafe("jev-1.14.0", credentials = key)

# A T1 or T2 body of the fixtures with changed answers
t1_body <- function(none = 0.07, drop = NULL) {
  body <- fixture("locate-t1")
  if (none > 0.5) {
    body$answers$q001$choice <- "none"
    body$answers$q001$probabilities <- c(as.list(rep(0.01, 9)) |> rlang::set_names(paste0("t", 1:9)), list(none = 0.91))
  }
  body$answers$q001$probabilities[drop] <- NULL
  body
}
as_response <- \(body) httr2::response_json(body = body)
is_t1 <- \(req) identical(httr2::req_get_body(req)$questions$q001$type, "choice")

test_that("locate() gives one row with the score, the box and the cost columns", {
  skip_if_no_magick()
  x <- locate_inputs()
  log <- record_requests(\(req) fixture_response(if (is_t1(req)) "locate-t1" else "locate-t2"))
  out <- locate(jev14, x$image, x$defect, x$references)
  expect_named(out, c(".pred_defect", ".box_left", ".box_top", ".box_right", ".box_bottom",
                      ".box_confidence", ".wording", ".input_tokens", ".cost", ".seconds", ".error"))
  expect_equal(out$.pred_defect, 0.93)
  expect_equal(unlist(out[1, c(".box_left", ".box_top", ".box_right", ".box_bottom")]),
               c(.box_left = 0.356, .box_top = 0.354, .box_right = 0.398, .box_bottom = 0.444))
  expect_equal(out$.box_confidence, 0.84)
  expect_equal(out$.wording, "generic")
  expect_equal(out$.input_tokens, 10259 + 13857)
  expect_identical(out$.cost, NA_real_)
  expect_identical(out$.error, NA_character_)
  expect_equal(attr(out, "requests"), 2)
  expect_length(log$requests, 2)
  expect_equal(httr2::req_get_headers(log$requests[[1]])[["TypeSafe-Danger-Zone-Images"]], "true")
})

test_that("three images, the middle one 'none': input order, no T2 for 'none', NA boxes", {
  skip_if_no_magick()
  x <- locate_inputs()
  dir <- system.file("extdata", "textiles", package = "decisions")
  images <- purrr::map(c("local_textile_0319.jpg", "nominal_textile_0630.jpg", "local_textile_0471.jpg"),
                       \(f) magick::image_read(file.path(dir, f)))
  tile_of <- \(img) locate_body_tiles("jev-1.14.0", img, x$defect, x$references)$assets$tile_t1$data_base64
  crop_of <- \(img) locate_body_boxes("jev-1.14.0", img, locate_tiles()[c(2, 1), ], x$defect,
                                      x$references)$body$assets$crop_1$data_base64
  # The third image gets four equal boxes: (0.1, 0.1, 0.2, 0.2) of each crop
  same <- list(type = "box", box = list(top = 0.1, bottom = 0.2, left = 0.1, right = 0.2), confidence = 0.5)
  third <- fixture("locate-t2")
  third$answers <- list(q001 = same, q002 = same, q003 = same, q004 = same)
  none_tile <- tile_of(images[[2]])
  third_crop <- crop_of(images[[3]])
  log <- record_requests(\(req) {
    body <- httr2::req_get_body(req)
    if (is_t1(req)) {
      as_response(t1_body(none = if (identical(body$assets$tile_t1$data_base64, none_tile)) 0.91 else 0.07))
    } else if (identical(body$assets$crop_1$data_base64, third_crop)) {
      as_response(third)
    } else {
      fixture_response("locate-t2")
    }
  })
  out <- locate(jev14, images, x$defect, x$references)
  expect_equal(nrow(out), 3)
  expect_equal(out$.pred_defect, c(0.93, 0.09, 0.93))
  expect_equal(out$.box_left, c(0.356, NA, 0.26))
  expect_equal(out$.box_bottom, c(0.444, NA, 0.12))
  expect_equal(out$.wording, c("generic", NA, "generic"))
  expect_equal(out$.input_tokens, c(10259 + 13857, 10259, 10259 + 13857))
  expect_identical(out$.error, rep(NA_character_, 3))
  # 3 T1 requests and 2 T2 requests: none for the middle image
  expect_length(log$requests, 5)
  expect_equal(sum(!purrr::map_lgl(log$requests, is_t1)), 2)
  expect_equal(attr(out, "requests"), 5)
})

test_that("a T1 answer with no probability for a tile gives a row error and no T2", {
  skip_if_no_magick()
  x <- locate_inputs()
  log <- record_requests(\(req) as_response(t1_body(drop = "t5")))
  out <- locate(jev14, x$image, x$defect, x$references)
  expect_match(out$.error, "no probability")
  expect_identical(out$.pred_defect, NA_real_)
  expect_length(log$requests, 1)
})

test_that("a T2 answer with no box in the first tile gives a row error", {
  skip_if_no_magick()
  x <- locate_inputs()
  empty <- fixture("locate-t2")
  for (q in names(empty$answers)) empty$answers[[q]]$box <- NULL
  log <- record_requests(\(req) if (is_t1(req)) fixture_response("locate-t1") else as_response(empty))
  out <- locate(jev14, x$image, x$defect, x$references)
  expect_match(out$.error, "no box")
  expect_equal(out$.pred_defect, 0.93)
  expect_identical(out$.box_left, NA_real_)
})

test_that("an HTTP error gives a row error", {
  skip_if_no_magick()
  x <- locate_inputs()
  log <- record_requests(\(req) httr2::response(status_code = 500L))
  out <- locate(jev14, x$image, x$defect, x$references)
  expect_match(out$.error, "HTTP 500")
  expect_length(log$requests, 1)
})

test_that("locate() stops with no request for another provider or a Jev before 1.14", {
  x <- list(image = "x.jpg", defect = "a dent", references = list(nominal = list("a.jpg"), defective = list("b.jpg")))
  log <- record_requests(\(req) stop("no request expected"))
  expect_error(locate(decider_openai("gpt-6-luna", credentials = key), x$image, x$defect, x$references), "TypeSafe")
  expect_error(locate(decider_typesafe("jev-1.13.0", credentials = key), x$image, x$defect, x$references), "1.14", fixed = TRUE)
  expect_error(locate(jev14, x$image, c("a dent", "a scratch"), x$references), "defect")
  expect_error(locate(jev14, x$image, x$defect, list(nominal = list("a.jpg"))), "defective")
  expect_error(locate(jev14, x$image, x$defect, x$references, rpm = 0), "rpm")
  expect_length(log$requests, 0)
})

test_that("jev-latest and later Jev versions pass the check of the model", {
  expect_silent(check_locate_decider(decider_typesafe("jev-latest", credentials = key)))
  expect_silent(check_locate_decider(jev14))
  expect_silent(check_locate_decider(decider_typesafe("jev-2.0.0", credentials = key)))
  expect_error(check_locate_decider(decider_typesafe("jev-1.9.3", credentials = key)), "1.14", fixed = TRUE)
})

# Fixes of the final review -----------------------------------------------

test_that("named reference lists give the keys and the note of the design (final review, Important 1)", {
  skip_if_no_magick()
  x <- locate_inputs()
  plain <- locate_strip_bytes(locate_body_tiles("jev-1.14.0", x$image, x$defect, x$references))
  # Named with local paths, as sapply() names them
  named <- list(
    nominal = rlang::set_names(x$references$nominal, c("C:/a/nominal_1.jpg", "C:/b/nominal_2.jpg")),
    defective = list(first = x$references$defective[[1]])
  )
  body <- locate_body_tiles("jev-1.14.0", x$image, x$defect, named)
  expect_false(grepl("C:/", body$state$note, fixed = TRUE))
  expect_equal(locate_strip_bytes(body), plain)
  # Partly named
  partly <- list(nominal = list(a = x$references$nominal[[1]], x$references$nominal[[2]]),
                 defective = x$references$defective)
  expect_equal(locate_strip_bytes(locate_body_tiles("jev-1.14.0", x$image, x$defect, partly)), plain)
})

# A step-1 response from the fixture text, with one change
t1_text <- function(from, to) {
  path <- test_path("fixtures", "locate-t1.json")
  text <- readChar(path, file.size(path))
  stopifnot(grepl(from, text, fixed = TRUE))
  httr2::response(
    status_code = 200L, headers = list(`Content-Type` = "application/json"),
    body = charToRaw(sub(from, to, text, fixed = TRUE))
  )
}

test_that("a step-1 answer with a null or non-numeric probability gives a row error (final review, Important 2)", {
  skip_if_no_magick()
  x <- locate_inputs()
  cases <- list(
    c('"none": 0.07', '"none": null'),
    c('"t2": 0.29', '"t2": null'),
    c('"t5": 0.17', '"t5": "0.17"')
  )
  for (case in cases) {
    log <- record_requests(\(req) if (is_t1(req)) t1_text(case[1], case[2]) else fixture_response("locate-t2"))
    out <- locate(jev14, x$image, x$defect, x$references)
    expect_match(out$.error, "no probability", label = case[2])
    expect_identical(out$.pred_defect, NA_real_, label = case[2])
    expect_length(log$requests, 1)
  }
  # A usage that is not an object: no stop, the answer is kept
  odd <- fixture("locate-t1")
  odd$usage <- "x"
  log <- record_requests(\(req) if (is_t1(req)) as_response(odd) else fixture_response("locate-t2"))
  out <- locate(jev14, x$image, x$defect, x$references)
  expect_identical(out$.error, NA_character_)
  expect_equal(out$.pred_defect, 0.93)
  expect_equal(out$.input_tokens, 13857)
})

test_that("locate() reads each image when it builds a request, and keeps no decoded image (final review, Important 3)", {
  skip_if_no_magick()
  x <- locate_inputs()
  dir <- system.file("extdata", "textiles", package = "decisions")
  paths <- file.path(dir, c("local_textile_0319.jpg", "nominal_textile_0630.jpg"))
  reads <- character()
  read_image <- locate_image
  local_mocked_bindings(locate_image = function(x) {
    if (is.character(x)) reads <<- c(reads, basename(x))
    read_image(x)
  })
  log <- record_requests(\(req) {
    if (!is_t1(req)) return(fixture_response("locate-t2"))
    none <- identical(httr2::req_get_body(req)$assets$tile_t1$data_base64,
                      locate_body_tiles("jev-1.14.0", magick::image_read(paths[2]), x$defect, x$references)$assets$tile_t1$data_base64)
    as_response(t1_body(none = if (none) 0.91 else 0.07))
  })
  out <- locate(jev14, paths, x$defect, x$references)
  # Step 1 reads both images; step 2 reads the first one again
  expect_equal(reads, c("local_textile_0319.jpg", "nominal_textile_0630.jpg", "local_textile_0319.jpg"))
  expect_equal(out$.box_left, c(0.356, NA))
})

test_that("an interrupt in step 1 sends no step-2 request (final review, Esc)", {
  skip_if_no_magick()
  x <- locate_inputs()
  sends <- 0
  local_mocked_bindings(perform_requests = function(requests, max_active) {
    sends <<- sends + 1
    # The first request answered, the others did not finish (Esc)
    structure(
      c(list(fixture_response("locate-t1")), rep(list(NULL), length(requests) - 1)),
      interrupted = TRUE, requests = length(requests)
    )
  })
  out <- locate(jev14, list(x$image, x$image, x$image), x$defect, x$references)
  expect_equal(sends, 1)
  expect_equal(out$.pred_defect, c(0.93, NA, NA))
  expect_match(out$.error[1], "interrupted")
  expect_match(out$.error[2], "No response")
  expect_identical(out$.box_left, rep(NA_real_, 3))
})

# Two more test cases (recommended by the final review) ---------------------

# A white image of 400 x 240 pixels with a black mark of 20 x 20 pixels at
# x 300 to 319, y 40 to 59: fractions (0.75, 0.1667, 0.8, 0.25)
marked_image <- function() {
  magick::image_blank(400, 240, "white") |>
    magick::image_composite(magick::image_blank(20, 20, "black"), offset = "+300+40")
}
mark <- c(300, 40, 320, 60) / c(400, 240, 400, 240)

# The dark part of an image asset, as fractions of the asset
dark_box <- function(asset) {
  img <- magick::image_read(jsonlite::base64_dec(asset$data_base64))
  a <- as.integer(magick::image_data(img, channels = "gray"))[, , 1]
  dark <- which(a < 128, arr.ind = TRUE)
  if (nrow(dark) == 0) return(NULL)
  info <- magick::image_info(img)
  list(left = (min(dark[, 2]) - 1) / info$width, top = (min(dark[, 1]) - 1) / info$height,
       right = max(dark[, 2]) / info$width, bottom = max(dark[, 1]) / info$height)
}

test_that("a mark in a non-square image is in the right tile of T1, and maps back to its place", {
  skip_if_no_magick()
  x <- locate_inputs()
  body <- locate_body_tiles("jev-1.14.0", marked_image(), x$defect, x$references)
  found <- purrr::map(body$assets[paste0("tile_t", 1:9)], dark_box)
  # Only tile t3 (right half, top half) holds the mark
  expect_equal(names(purrr::compact(found)), "tile_t3")
  t3 <- locate_crop(c(0.5, 0, 1, 0.5), width = 400, height = 240)
  expect_equal(t3, list(x0 = 200, y0 = 0, w = 200, h = 120))
  expect_equal(locate_to_image(found$tile_t3, t3, 400, 240), mark, tolerance = 0.01)
})

test_that("a mark in the Box crop of a non-square image maps back to its place (T2)", {
  skip_if_no_magick()
  x <- locate_inputs()
  t2 <- locate_body_boxes("jev-1.14.0", marked_image(), locate_tiles()[c(3, 2), ], x$defect, x$references)
  # Tile t3 grown by 1.2: 240 x 144 pixels, moved inside the image
  expect_equal(t2$crops[[1]], list(x0 = 160, y0 = 0, w = 240, h = 144))
  found <- dark_box(t2$body$assets$crop_1)
  expect_equal(locate_to_image(found, t2$crops[[1]], 400, 240), mark, tolerance = 0.01)
})

# Deferred minors of the final review ---------------------------------------

test_that("references take a vector of paths or a magick vector, as decide() does", {
  skip_if_no_magick()
  x <- locate_inputs()
  dir <- system.file("extdata", "textiles", package = "decisions")
  paths <- file.path(dir, c("nominal_textile_0630.jpg", "nominal_textile_0731.jpg"))
  log <- record_requests(\(req) fixture_response(if (is_t1(req)) "locate-t1" else "locate-t2"))
  out <- locate(jev14, x$image, x$defect,
                list(nominal = paths, defective = x$references$defective[[1]]))
  expect_identical(out$.error, NA_character_)
  body <- httr2::req_get_body(log$requests[[1]])
  expect_true(all(c("reference_nominal_1", "reference_nominal_2", "reference_defective_1") %in% names(body$assets)))
  out <- locate(jev14, x$image, x$defect,
                list(nominal = magick::image_read(paths), defective = list(x$references$defective[[1]])))
  expect_identical(out$.error, NA_character_)
})

test_that("an image with a page offset gives the tiles of the image", {
  skip_if_no_magick()
  x <- locate_inputs()
  offset <- magick::image_crop(magick::image_scale(x$image, "550x550!"), "400x400+150+150", repage = FALSE)
  body <- locate_body_tiles("jev-1.14.0", locate_image(offset), x$defect, x$references)
  sizes <- purrr::map_chr(locate_strip_bytes(body)$assets[paste0("tile_t", 1:9)], "data_base64")
  expect_equal(unname(sizes), rep("<jpeg 560x560>", 9))
})

test_that("a long and narrow image or reference stops before any request", {
  skip_if_no_magick()
  x <- locate_inputs()
  log <- record_requests(\(req) fixture_response("locate-t1"))
  long <- magick::image_blank(3000, 250, "white")
  expect_error(locate(jev14, long, x$defect, x$references), "long and narrow")
  thin <- list(nominal = x$references$nominal, defective = list(magick::image_blank(40, 400, "white")))
  expect_error(locate(jev14, x$image, x$defect, thin), "long and narrow")
  expect_length(log$requests, 0)
})

test_that("a missing key stops locate() before any image is read", {
  withr::local_envvar(TYPESAFE_API_KEY = NA)
  log <- record_requests(\(req) stop("no request expected"))
  refs <- list(nominal = list("missing-a.jpg"), defective = list("missing-b.jpg"))
  expect_error(locate(decider_typesafe("jev-1.14.0"), "missing-c.jpg", "a dent", refs), "TYPESAFE_API_KEY")
  expect_length(log$requests, 0)
})

test_that("a row error names its step, also for an HTTP error in step 2", {
  skip_if_no_magick()
  x <- locate_inputs()
  log <- record_requests(\(req) if (is_t1(req)) fixture_response("locate-t1") else httr2::response(status_code = 500L))
  out <- locate(jev14, x$image, x$defect, x$references)
  expect_match(out$.error, "^Step 2: HTTP 500")
  expect_equal(out$.pred_defect, 0.93)
  expect_identical(out$.box_left, NA_real_)
  expect_equal(out$.input_tokens, 10259)
  log <- record_requests(\(req) httr2::response(status_code = 500L))
  out <- locate(jev14, x$image, x$defect, x$references)
  expect_match(out$.error, "^Step 1: HTTP 500")
})

test_that("locate() prepares the references once for all images and both steps", {
  skip_if_no_magick()
  x <- locate_inputs()
  calls <- 0
  prepare <- locate_references
  local_mocked_bindings(locate_references = function(...) {
    calls <<- calls + 1
    prepare(...)
  })
  log <- record_requests(\(req) fixture_response(if (is_t1(req)) "locate-t1" else "locate-t2"))
  out <- locate(jev14, list(x$image, x$image, x$image), x$defect, x$references)
  expect_length(log$requests, 6)
  expect_equal(calls, 1)
})

test_that("locate_wording() keeps a phrase that starts with another determiner, and trims spaces", {
  expect_equal(locate_wording("another flaw"), "another flaw")
  expect_equal(locate_wording("one scratch"), "one scratch")
  expect_equal(locate_wording("  a dent"), "the dent")
  expect_equal(locate_wording("A  dent"), "the dent")
})

test_that("the model check of locate() ignores case", {
  expect_error(check_locate_decider(decider_typesafe("JEV-1.13.0", credentials = key)), "1.14", fixed = TRUE)
})

test_that("with no box in the first tile for the picked wording, the box of the other wording is used", {
  answers <- saved_answers("locate-t2.json")
  # Both agreements are 0; the defect wording has the higher confidence, but
  # its first-tile answer (q002) has no box
  answers$q002$box <- NULL
  answers$q003$box <- NULL
  read <- locate_read_boxes(answers, t2_crops(), 250, 250)
  expect_equal(read$box, c(0.356, 0.354, 0.398, 0.444))
  expect_equal(read$wording, "generic")
  expect_equal(read$confidence, 0.84)
})
