#' Register the S7 methods when the package loads
#'
#' @param libname,pkgname The library and the name of the package. Not used.
#' @return `NULL`, invisibly.
#' @noRd
.onLoad <- function(libname, pkgname) {
  S7::methods_register()
}
