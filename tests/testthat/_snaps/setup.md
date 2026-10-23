# a setup prints its pieces and no key

    Code
      print(setup)
    Output
      <decisions::decision_setup>
      * Model: jev-1.13.0
      * URL: https://api.typesafe.ai/v1/systemone
      * Questions: quality (2 answers)
      * Reference images: 3
      * Image settings: max_size = 768, upscale = FALSE, crop = "none"
      * Calibrated: no

---

    Code
      print(decision_setup(typesafe, list(refund = refund, urgency = urgency),
      max_size = NULL, crop = function(img) c(0, 0, 10, 10)))
    Output
      <decisions::decision_setup>
      * Model: jev-1.13.0
      * URL: https://api.typesafe.ai/v1/systemone
      * Questions: refund (2 answers), urgency (3 answers)
      * Reference images: 0
      * Image settings: max_size = NULL, upscale = FALSE, crop = a function
      * Calibrated: no

