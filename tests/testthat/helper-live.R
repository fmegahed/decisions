# Helpers of the live tests (tests/testthat/test-live.R). testthat sources
# this file before the test files.

#' Skip a live test unless it is allowed to run
#'
#' A live test makes a real, paid call. It runs only when the variable
#' `DECISIONS_LIVE_TESTS` is `"true"` and the key variable of the provider is
#' set. It never runs on CRAN. Otherwise `testthat::skip()` says why.
#'
#' @param key_var The name of the key variable of the provider, for example
#'   `"TYPESAFE_API_KEY"`.
#' @return Nothing. It skips the test or returns invisibly.
skip_if_not_live <- function(key_var) {
  testthat::skip_on_cran()
  if (!identical(Sys.getenv("DECISIONS_LIVE_TESTS"), "true")) {
    testthat::skip("Live tests are off. Set DECISIONS_LIVE_TESTS=true to run them.")
  }
  if (!nzchar(Sys.getenv(key_var))) {
    testthat::skip(paste0("The environment variable ", key_var, " is not set."))
  }
  invisible()
}

#' Skip a test unless a local Laya server is allowed and reachable
#'
#' Needs `DECISIONS_LIVE_LOCAL=true` and an answer from
#' `http://localhost:8000/health`. The test never starts a server.
#'
#' @return Nothing. It skips the test or returns invisibly.
skip_if_no_laya <- function() {
  testthat::skip_on_cran()
  if (!identical(Sys.getenv("DECISIONS_LIVE_LOCAL"), "true")) {
    testthat::skip("Local tests are off. Set DECISIONS_LIVE_LOCAL=true to run them.")
  }
  up <- tryCatch(
    httr2::resp_status(httr2::req_perform(
      httr2::request("http://localhost:8000/health")
    )) == 200,
    error = \(e) FALSE
  )
  if (!up) testthat::skip("No Laya server answers at http://localhost:8000/health.")
  invisible()
}

#' Check the shape of the result of one live noul question
#'
#' @param out The tibble that `decide()` returned for one text and one noul
#'   question.
#' @return Nothing. It runs expectations.
expect_noul_shape <- function(out) {
  testthat::expect_equal(nrow(out), 1)
  testthat::expect_s3_class(out$.pred_class, "factor")
  testthat::expect_setequal(levels(out$.pred_class), c("true", "false"))
  probabilities <- c(out$.pred_true, out$.pred_false)
  testthat::expect_true(all(probabilities >= 0 & probabilities <= 1))
  testthat::expect_equal(sum(probabilities), 1, tolerance = 0.05)
  testthat::expect_true(is.na(out$.error))
  testthat::expect_gt(out$.input_tokens, 0)
}
