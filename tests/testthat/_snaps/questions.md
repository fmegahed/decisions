# questions print briefly

    Code
      question_noul("Is it wet?", true = "Wet.")
    Output
      <decisions::question_noul> Is it wet?
      * true: Wet.
      * false
    Code
      question_choice("Which?", c(normal = "A clean part.", `not sure` = "Unclear."))
    Output
      <decisions::question_choice> Which?
      * normal: A clean part.
      * not sure: Unclear.

