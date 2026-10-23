# Build the dataset `rubric_answers`: 20 sample answers to the question
# "What does `decide()` do when one call of a batch fails?", with the label
# of the author for each question of the rubric. We wrote the answers for
# the vignette "Grading short answers with a rubric".
#
# Run from the package root: Rscript data-raw/rubric_answers.R

samples <- tibble::tribble(
  ~answer, ~keeps_row, ~na_answers, ~error_text, ~others_continue, ~stops_all, ~drops_row,
  "decide() keeps the row of the failed call. The answers in that row are NA, and the .error column holds the reason. The other inputs get their answers.", TRUE, TRUE, TRUE, TRUE, FALSE, FALSE,
  "The failed input still has a row, in the same place. Its answers are NA and .error says why.", TRUE, TRUE, TRUE, FALSE, FALSE, FALSE,
  "It stops and throws an error, so you get no result at all.", FALSE, FALSE, FALSE, FALSE, TRUE, FALSE,
  "The function removes the failed rows from the table, so the output is shorter than the input.", FALSE, FALSE, FALSE, FALSE, FALSE, TRUE,
  "The row of the failed call has NA values. Everything else works as before.", TRUE, TRUE, FALSE, TRUE, FALSE, FALSE,
  "It writes the error message into the .error column and goes on with the other inputs.", FALSE, FALSE, TRUE, TRUE, FALSE, FALSE,
  "I think it tries the call again and again until it works.", FALSE, FALSE, FALSE, FALSE, FALSE, FALSE,
  "One failed call stops the whole batch, and you lose the answers of the other inputs.", FALSE, FALSE, FALSE, FALSE, TRUE, FALSE,
  "The row stays in the output and its answer is NA. The reason for the failure is in .error. The call does not stop.", TRUE, TRUE, TRUE, TRUE, FALSE, FALSE,
  "The failed input gets NA answers, and the batch goes on.", FALSE, TRUE, FALSE, TRUE, FALSE, FALSE,
  "decide() skips the input that failed. It does not put that input in the output.", FALSE, FALSE, FALSE, FALSE, FALSE, TRUE,
  "The output has one row for each input, also for the inputs that fail. The failed rows hold the text of the error.", TRUE, FALSE, TRUE, FALSE, FALSE, FALSE,
  "Nothing happens. It just works.", FALSE, FALSE, FALSE, FALSE, FALSE, FALSE,
  "It gives a warning and drops that input. The other rows are fine.", FALSE, FALSE, FALSE, TRUE, FALSE, TRUE,
  "The reason for the failure is kept in the .error column, word for word from the provider. The answers of that row are NA.", TRUE, TRUE, TRUE, FALSE, FALSE, FALSE,
  "If one call fails, the other calls still go on and give their answers. The failed one has NA.", FALSE, TRUE, FALSE, TRUE, FALSE, FALSE,
  "The whole decide() call fails with the first HTTP error.", FALSE, FALSE, FALSE, FALSE, TRUE, FALSE,
  "Each input keeps its row, in order. A failed call has NA answers and a message in .error. The rest of the batch is not affected.", TRUE, TRUE, TRUE, TRUE, FALSE, FALSE,
  "decide() stops after the first failure, but it saves the finished answers to the path file.", FALSE, FALSE, FALSE, FALSE, TRUE, FALSE,
  "The failed row is marked with an error message. Then the model is asked again at once, up to ten times.", TRUE, FALSE, TRUE, FALSE, FALSE, FALSE
)

rubric_answers <- tibble::add_column(samples, answer_id = seq_len(nrow(samples)), .before = 1)
stopifnot(nrow(rubric_answers) == 20, !anyNA(rubric_answers))
usethis::use_data(rubric_answers, overwrite = TRUE, compress = "xz")
