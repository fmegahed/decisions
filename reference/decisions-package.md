# decisions: Typed Decisions from Decision Models

Calls decision models. A decision model reads an input and a typed
question. It returns a probability for each allowed answer.

## Start here

1.  Make a decider:
    [`decider_typesafe()`](https://fmegahed.github.io/decisions/reference/decider_typesafe.md),
    [`decider_openai()`](https://fmegahed.github.io/decisions/reference/decider_openai.md),
    [`decider_foundry()`](https://fmegahed.github.io/decisions/reference/decider_foundry.md),
    [`decider_openrouter()`](https://fmegahed.github.io/decisions/reference/decider_openrouter.md)
    or
    [`decider_systemone()`](https://fmegahed.github.io/decisions/reference/decider_systemone.md).
    Each help page says how to get a key and where to put it.

2.  Make a question:
    [`question_noul()`](https://fmegahed.github.io/decisions/reference/question_noul.md),
    [`question_choice()`](https://fmegahed.github.io/decisions/reference/question_choice.md)
    or
    [`question_score()`](https://fmegahed.github.io/decisions/reference/question_score.md).

3.  Call
    [`decide()`](https://fmegahed.github.io/decisions/reference/decide.md).

[`vignette("getting-started")`](https://fmegahed.github.io/decisions/articles/getting-started.md)
shows these steps with saved results.

## Output

[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md)
returns a tibble with one row for each input, a `.pred_class` column and
one `.pred_` column for each allowed answer. A failed call keeps its
row, with `NA` answers and the reason in `.error`.

## Examples that need a key

The hosted services need an API key and can bill each call. So the
examples of
[`decide()`](https://fmegahed.github.io/decisions/reference/decide.md),
[`score_setup()`](https://fmegahed.github.io/decisions/reference/score_setup.md)
and
[`evaluate_once()`](https://fmegahed.github.io/decisions/reference/evaluate_once.md)
are in `\dontrun{}`: each needs an API key and a paid call, so it is not
run on CRAN.

## Links

- Source and bug reports: <https://github.com/fmegahed/decisions>

- Website: <https://fmegahed.github.io/decisions/>

## See also

Useful links:

- <https://github.com/fmegahed/decisions>

- <https://fmegahed.github.io/decisions/>

- Report bugs at <https://github.com/fmegahed/decisions/issues>

## Author

**Maintainer**: Fadel M. Megahed <fmegahed@miamioh.edu>
([ORCID](https://orcid.org/0000-0003-2194-5110))

Authors:

- Fadel M. Megahed <fmegahed@miamioh.edu>
  ([ORCID](https://orcid.org/0000-0003-2194-5110))

- Ying-Ju Chen <ychen4@udayton.edu>
  ([ORCID](https://orcid.org/0000-0002-6444-6859))
