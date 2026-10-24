# Package index

## Deciders

Name the provider and the model.

- [`decider_typesafe()`](decider_typesafe.md) : Use Jev through the
  TypeSafe API
- [`decider_openai()`](decider_openai.md) : Use the OpenAI Decisions API
- [`decider_foundry()`](decider_foundry.md) : Use Microsoft-Decision-1
  on Microsoft Foundry
- [`decider_openrouter()`](decider_openrouter.md) : Use a decision model
  through OpenRouter
- [`decider_systemone()`](decider_systemone.md) : Use any SystemOne
  server

## Questions

Describe what to decide and the allowed answers.

- [`question_noul()`](question_noul.md) : Ask a question with true or
  false as the answer
- [`question_choice()`](question_choice.md) : Ask a question with named
  choices
- [`question_score()`](question_score.md) : Ask a question with ordered
  score levels

## Decide

- [`decide()`](decide.md) : Ask a decision model typed questions

## Setups

Save, read and build a setup.

- [`decision_setup()`](decision_setup.md) : Make a setup: one complete
  decision
- [`write_setup()`](write_setup.md) : Save a setup as one JSON file
- [`read_setup()`](read_setup.md) : Read a setup file

## Scoring

Score a setup, and run the one-time test.

- [`score_setup()`](score_setup.md) : Score a setup on labeled rows
- [`evaluate_once()`](evaluate_once.md) : Score the test rows one time

## Datasets

- [`ohio_injuries`](ohio_injuries.md) : Severe injury reports from Ohio,
  2025
- [`ohio_recalls`](ohio_recalls.md) : Food recalls of Ohio firms
- [`textiles`](textiles.md) : Simulated textile images
- [`rubric_answers`](rubric_answers.md) : Sample answers for a rubric
