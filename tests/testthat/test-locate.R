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
