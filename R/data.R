#' Severe injury reports from Ohio, 2025
#'
#' Narratives of 464 severe work injuries in Ohio, with the injury type that
#' OSHA recorded. Use it to test a decision model on a text task with five
#' groups of different size.
#'
#' @format A tibble with 464 rows and 11 columns:
#' \describe{
#'   \item{id}{Character. The report ID of OSHA.}
#'   \item{event_date}{Date. The date of the event.}
#'   \item{city}{Character. The city of the event.}
#'   \item{state}{Character. The state, always `"OHIO"`.}
#'   \item{final_narrative}{Character. The narrative that OSHA published,
#'     with the whitespace trimmed and each line break changed to a space.}
#'   \item{original_nature_title}{Character. The nature of the injury, as
#'     OSHA titles it.}
#'   \item{collapsed_nature_title}{Factor. The nature of the injury in five
#'     groups, in this order: `amputation` (187 rows), `fracture` (242),
#'     `crushing injury` (14), `thermal burn` (15) and `concussion` (6).}
#'   \item{original_event_title}{Character. The event, as OSHA titles it.}
#'   \item{collapsed_event_title}{Factor. The OIICS 2.01 division of the event,
#'     from the first digit of its code, in code order.}
#'   \item{original_source_title}{Character. The source of the injury, as
#'     OSHA titles it.}
#'   \item{collapsed_source_title}{Factor. The OIICS 2.01 division of the
#'     source, from the first digit of its code, in code order.}
#' }
#' @source Occupational Safety and Health Administration. (n.d.). Severe injury
#'   reports \[Data set\]. U.S. Department of Labor. Retrieved October 23, 2026,
#'   from <https://www.osha.gov/severe-injury-reports>
#'
#'   Filters: Year: 2025 and State: Ohio.
#' @details The data are a work of the U.S. government and are in the public
#'   domain. The reports cover employers under federal OSHA jurisdiction. The
#'   OIICS 2.01 divisions come from the Occupational Injury and Illness
#'   Classification System of the U.S. Bureau of Labor Statistics.
#'
#'   The five groups of `collapsed_nature_title` come from the titles of
#'   OSHA like this:
#'   * `amputation`: "Amputations, avulsions, enucleations  unspecified" and
#'     "Amputations involving bone loss".
#'   * `fracture`: "Fractures".
#'   * `crushing injury`: "Nonfatal 'crushing' injuries".
#'   * `thermal burn`: the three titles "Thermal burns" (degree unspecified,
#'     second degree, third degree or higher).
#'   * `concussion`: "Concussions".
#'
#'   Three kinds of report are not in the data on purpose. The title "Avulsions,
#'   enucleations without bone loss" is out, because OSHA does not count an
#'   avulsion as an amputation. The combined titles "Fractures and soft tissue
#'   injuries" and "Fractures and surface, flesh wounds" are out, because they
#'   name more than one injury. The data keep no other column of the download,
#'   for example the employer, the address and the flag for an amputation.
#' @examples
#' table(ohio_injuries$collapsed_nature_title)
#' ohio_injuries$final_narrative[1]
"ohio_injuries"

#' Sample answers for a rubric
#'
#' Twenty sample answers to the question "What does `decide()` do when one
#' call of a batch fails?", with a label for each question of the rubric. We
#' wrote the answers for the vignette "Grading short answers with a rubric".
#'
#' @format A tibble with 20 rows and 8 columns:
#' \describe{
#'   \item{answer_id}{Integer. The number of the answer.}
#'   \item{answer}{Character. The text of the answer.}
#'   \item{keeps_row}{Logical. The answer says that the failed input keeps its
#'     row in the output.}
#'   \item{na_answers}{Logical. The answer says that the answers of the failed
#'     row are `NA`.}
#'   \item{error_text}{Logical. The answer says that the reason of the failure
#'     is in the `.error` column.}
#'   \item{others_continue}{Logical. The answer says that the other inputs of
#'     the batch still get their answers.}
#'   \item{stops_all}{Logical. The answer says that `decide()` stops with an
#'     error, or returns nothing, when one call fails (a wrong claim).}
#'   \item{drops_row}{Logical. The answer says that `decide()` removes the
#'     failed input from the output (a wrong claim).}
#' }
#' @source Written for this package. The labels are the labels of the author.
#' @examples
#' rubric_answers[1:3, c("answer_id", "keeps_row", "stops_all")]
"rubric_answers"

#' Simulated textile images
#'
#' Fifty simulated images of a woven textile, 250 x 250 pixels. Half of them
#' show a flaw in the pattern. Use them to test a decision model on an image
#' task. The files are in `inst/extdata/textiles/`.
#'
#' @format A tibble with 50 rows and 5 columns:
#' \describe{
#'   \item{file}{Character. The name of the JPEG file in
#'     `inst/extdata/textiles/`. The name starts with the folder of the
#'     source (`nominal_`, `local_` or `global_`), because two source files
#'     have the same name.}
#'   \item{class}{Factor. The truth, with the levels `nominal` and
#'     `defective`. Each level has 25 images.}
#'   \item{defect_type}{Factor. `nominal` (no flaw), `local` (a flaw in one
#'     place) or `global` (a flaw that changes the whole pattern).}
#'   \item{role}{Character. `reference` (4 images, to show the model what each
#'     answer looks like) or `input` (46 images, to decide on).}
#'   \item{reference_rank}{Integer. `1` or `2` for the references, two for each
#'     class, and `NA` for the inputs.}
#' }
#' @source Made with the R package spc4sts:
#'
#'   Bui, A. T., & Apley, D. W. (2021). spc4sts: Statistical process control
#'   for stochastic textured surfaces in R. *Journal of Quality Technology,
#'   53*(3), 219-242. \doi{10.1080/00224065.2019.1707730}
#'
#'   Package reference manual:
#'   \url{https://cran.r-project.org/web/packages/spc4sts/refman/spc4sts.html}
#'
#'   The images are shared in the public repository
#'   <https://github.com/fmegahed/qe_genai> (MIT licence). The references are the images of rank
#'   1 and 2 of each class in the study sets. The 46 inputs are 23 images of
#'   each class, drawn at random with a fixed seed from the study design set;
#'   none is a reference. No image of the one-time test set of the study is in
#'   the data. The script `data-raw/textiles.R` builds the data.
#' @examples
#' table(textiles$role, textiles$class)
#' paths <- file.path(
#'   system.file("extdata", "textiles", package = "decisions"), textiles$file
#' )
#' file.exists(paths[1])
"textiles"
