#!/usr/bin/env bash
# Start ONE blind description loop of gpt-6-luna (vignette 5): a fresh,
# isolated Claude Code agent in the sandbox of one dataset. The flags are the
# flags of scripts/fair_run_loop.sh in the study folder.
#
# From the package root, in Git Bash:
#   bash data-raw/study_again/loop/run_loop.sh DATASET             # starts the agent
#   bash data-raw/study_again/loop/run_loop.sh --dry-run DATASET   # prints the command only
#
# DATASET: extrusion, microstructure, pipe_staple or textiles.
# DECISIONS_LOOP_CHECK_ONLY=true: a rehearsal. The agent gets the variable, so
#   score.sh runs the checks only and makes no paid call.
#
# The script refuses to start when the sandbox does not exist, or when the
# mirror of the loop log (outside the sandbox) already has rows. The agent
# runs with the sandbox as its working folder:
#   --restricted: no user, project or local settings; the file tools stay in
#     the working folder; no code-running tool unless --tools names it.
#   --safe-mode: no CLAUDE.md, skills, plugins, hooks, MCP servers or agents.
#   --strict-mcp-config (with no --mcp-config): no MCP server.
#   --settings blockReadsOutsideWorkingDirectories: the file tools refuse
#     reads outside the sandbox.
#   --tools: only Read, Write, Edit, Glob, Grep, Bash and TodoWrite.
#   --allowedTools: Read, Glob, Grep and TodoWrite; writes only to
#     candidates/*.csv; Bash only for the scoring forms.
#   --disallowedTools: no write to score.sh, LOOP.md, labels.csv,
#     loop_log.csv or generic_description.csv.
#   --permission-mode dontAsk and --permission-prompts none: any other call
#     is denied.
#   --disable-slash-commands, the pinned model, and a new session ID, so the
#     path of the transcript is known. The script prints that path at the end.
# The md5 check of score.sh and the audit of the transcript (audit.R) are a
# second layer. The agent runs on this machine, not in a container or a VM.
set -euo pipefail

usage="Usage: bash data-raw/study_again/loop/run_loop.sh [--dry-run] DATASET"
refuse() { echo "Refused: $*" >&2; exit 1; }

dry_run=false
if [ "${1:-}" = "--dry-run" ]; then dry_run=true; shift; fi
if [ "$#" -ne 1 ]; then echo "$usage" >&2; exit 2; fi
dataset=$1
case "$dataset" in
  extrusion|microstructure|pipe_staple|textiles) ;;
  pan_images) refuse "Pans have no loop." ;;
  *) refuse "DATASET must be extrusion, microstructure, pipe_staple or textiles." ;;
esac

# DECISIONS_LOOP_CHECK_ONLY: "true" (any case, spaces trimmed), "false" or empty.
check_only=$(printf '%s' "${DECISIONS_LOOP_CHECK_ONLY:-}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
case "$check_only" in ""|false|true) ;; *) refuse "DECISIONS_LOOP_CHECK_ONLY must be true or false." ;; esac

# Windows form of a path (C:/...), which Claude Code and R use.
win_path() { if command -v cygpath > /dev/null; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

kit=$(cd "$(dirname "$0")" && pwd)
sandbox_dir="/c/Users/megahefm/decisions-openai-loops/$dataset"
mirror="$kit/${dataset}_loop_log.csv"
[ -d "$sandbox_dir" ] || refuse "The sandbox does not exist: $sandbox_dir. Run make_sandbox.R first."
if [ -e "$mirror" ] && [ "$(wc -l < "$mirror")" -gt 1 ]; then
  refuse "The mirror of the loop log already has rows: $mirror"
fi

sandbox=$(win_path "$(cd "$sandbox_dir" && pwd)")
# A version 4 UUID from 16 random bytes.
hex=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
variant=$(printf '%x' $(( (0x${hex:16:2} & 0x3f) | 0x80 )))
session_id="${hex:0:8}-${hex:8:4}-4${hex:13:3}-${variant}${hex:18:2}-${hex:20:12}"
# Claude Code names the project folder of a working folder by its path, with
# each character that is not a letter or a digit replaced by "-".
slug=$(printf '%s' "$sandbox" | sed 's/[^A-Za-z0-9]/-/g')
config_dir=$(win_path "${CLAUDE_CONFIG_DIR:-${USERPROFILE:-$HOME}/.claude}")
transcript="$config_dir/projects/$slug/$session_id.jsonl"

cmd=(claude -p "Read LOOP.md and follow it."
  --restricted --safe-mode --strict-mcp-config
  --settings '{"permissions":{"blockReadsOutsideWorkingDirectories":true}}'
  --tools "Read,Write,Edit,Glob,Grep,Bash,TodoWrite"
  --allowedTools Read Glob Grep TodoWrite "Edit(./candidates/*.csv)"
  "Bash(bash score.sh:*)" "Bash(./score.sh:*)"
  --disallowedTools "Edit(./score.sh)" "Edit(./LOOP.md)" "Edit(./labels.csv)"
  "Edit(./loop_log.csv)" "Edit(./generic_description.csv)"
  --disable-slash-commands --permission-mode dontAsk --permission-prompts none
  --model claude-opus-5-5
  --session-id "$session_id")

# Print an argument as a shell word: in single quotes when it holds a double
# quote, in double quotes when it needs quotes, else as it is.
quote() {
  case "$1" in
    *\"*) printf "'%s'" "$1" ;;
    *[!A-Za-z0-9_./:=,@%+-]*) printf '"%s"' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}
line=""
for arg in "${cmd[@]}"; do line="$line${line:+ }$(quote "$arg")"; done

echo "Dataset: $dataset"
echo "Sandbox: $sandbox"
echo "Session ID: $session_id"
if [ "$check_only" = "true" ]; then
  echo "Rehearsal: DECISIONS_LOOP_CHECK_ONLY=true goes to the agent. score.sh runs the checks only (no paid call)."
fi
echo "Command:"
echo "cd \"$sandbox\""
echo "$line"

if [ "$dry_run" = "true" ]; then
  echo "Transcript: $transcript"
  echo "Dry run: claude was not started."
  exit 0
fi

command -v claude > /dev/null || refuse "claude is not on the PATH."
echo "Claude Code version: $(claude --version)"
if [ -n "$check_only" ]; then export DECISIONS_LOOP_CHECK_ONLY="$check_only"; fi
status=0
(cd "$sandbox_dir" && "${cmd[@]}") || status=$?
echo "Exit status of claude: $status"
echo "Transcript: $transcript"
echo "Audit with: Rscript data-raw/study_again/loop/audit.R $dataset \"$transcript\""
exit "$status"
