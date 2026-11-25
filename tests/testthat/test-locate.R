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
