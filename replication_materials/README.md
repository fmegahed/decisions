# decisions

This record follows the R package decisions from the first brainstorm to the submission of version 0.1.0 to CRAN. It is a subset of the record of a larger project: [Beyond CLIP: Calibrated (Few-Shot) Defect Detection With Structured Decision Models](https://github.com/fmegahed/decision-models-for-industrial-image-qc). A paper on that project is in progress. Fadel M. Megahed directed the work with Claude Code (Anthropic), which wrote the code, the documentation and the record. The record follows the Claude Code skill [replication-materials](https://github.com/fmegahed/claude-skills/tree/main/skills/replication-materials) (Megahed, 2026).

People: Fadel M. Megahed (maintainer and author) and Ying-Ju (Tessa) Chen (author). The ideas of the package came from their discussions and build on their joint work. `project/contributions.md` gives the details.

## Project

The project compares structured decision models (Jev and Clef-Flash) with few-shot CLIP for the detection of defects in images of manufactured parts. The package came out of that work. The vignette "Case study: industrial image inspection" repeats the study of the project with the package.

This record keeps the decisions about the package: D39, which first named the package, and the decisions from D136 on. The decisions about the study and the paper (D1 to D135) are in the [record of the project](https://fmegahed.github.io/decision-models-for-industrial-image-qc/). A decision has the same ID in both records.

## Record

The record holds each decision about the package (who proposed it, who decided it, and the words that show it), the design, the plan and the build ledger, the events of the work, and the paid calls that made the saved results of the vignettes. The record of the project is the source. The script `data-raw/record.R` of the package repository copies the part about the package into `replication_materials/`. Do not edit the copy.

## Folders

| Folder | What it holds |
|---|---|
| `plans/` | The design, the plan and the build ledger of the package (milestone M3). |
| `calls/` | The budgets in `README.md` and the logs of the paid calls of the package work in `<service>-calls.csv`. |
| `project/` | The roadmap, the decisions, the process events and the contributions. |

## References

Megahed, F. M. (2026). *replication-materials* (Version 1.3.0) [Claude Code skill]. GitHub. https://github.com/fmegahed/claude-skills/tree/main/skills/replication-materials
