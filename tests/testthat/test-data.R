test_that("textiles has the 4 references, the 46 inputs and one box reference", {
  expect_equal(nrow(textiles), 51)
  expect_equal(sum(textiles$role == "input"), 46)
  refs <- textiles$file[textiles$role == "reference"]
  expect_setequal(refs, c(
    "global_textile_0330.jpg", "local_textile_0471.jpg",
    "nominal_textile_0630.jpg", "nominal_textile_0731.jpg"
  ))
  box <- textiles[textiles$role == "box_reference", ]
  expect_equal(nrow(box), 1)
  expect_equal(box$file, "local_textile_0199.jpg")
  expect_equal(as.character(box$class), "defective")
  expect_equal(as.character(box$defect_type), "local")
  expect_true(all(file.exists(
    system.file("extdata", "textiles", textiles$file, package = "decisions")
  )))
})
