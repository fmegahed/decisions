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
  health <- tryCatch(
    httr2::resp_body_json(httr2::req_perform(
      httr2::request("http://localhost:8000/health")
    )),
    error = \(e) NULL
  )
  # Venn uses the same port; its health answer has a `reader` field.
  if (is.null(health) || !is.null(health$reader)) {
    testthat::skip("No Laya server answers at http://localhost:8000/health.")
  }
  invisible()
}

#' Check the shape of the result of one live noul question
#'
#' @param out The tibble that `decide()` returned for one text and one noul
#'   question.
#' @return Nothing. It runs expectations.
expect_noul_shape <- function(out, tokens = TRUE) {
  testthat::expect_equal(nrow(out), 1)
  testthat::expect_s3_class(out$.pred_class, "factor")
  testthat::expect_setequal(levels(out$.pred_class), c("true", "false"))
  probabilities <- c(out$.pred_true, out$.pred_false)
  testthat::expect_true(all(probabilities >= 0 & probabilities <= 1))
  testthat::expect_equal(sum(probabilities), 1, tolerance = 0.05)
  testthat::expect_true(is.na(out$.error))
  # Venn reports no tokens: NA, not a measured 0.
  if (tokens) {
    testthat::expect_gt(out$.input_tokens, 0)
  } else {
    testthat::expect_true(is.na(out$.input_tokens))
  }
}

#' Skip unless a local Venn server answers
#'
#' Needs `DECISIONS_LIVE_LOCAL=true` and a Venn answer (with its `reader`
#' field) from `http://127.0.0.1:8000/health`. Laya uses the same port, so
#' an answer with no `reader` field skips. The test never starts a server.
skip_if_no_venn <- function() {
  testthat::skip_on_cran()
  if (!identical(Sys.getenv("DECISIONS_LIVE_LOCAL"), "true")) {
    testthat::skip("Local tests are off. Set DECISIONS_LIVE_LOCAL=true to run them.")
  }
  health <- tryCatch(
    httr2::resp_body_json(httr2::req_perform(
      httr2::request("http://127.0.0.1:8000/health")
    )),
    error = \(e) list()
  )
  if (!identical(health$reader, "ready")) {
    testthat::skip("No Venn server is ready at http://127.0.0.1:8000/health.")
  }
  invisible()
}
