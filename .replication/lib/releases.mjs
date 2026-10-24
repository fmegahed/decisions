// Releases and headline results read from optional record files.

import { existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { parseTables, findTable, RecordFormatError } from "./tables.mjs";

export const RELEASE_COLUMNS = ["Tag", "Date", "Commit", "Summary", "Decisions", "Results"];
export const RESULT_COLUMNS = ["ID", "Release", "Result", "Value", "Source", "Decisions", "Replaces"];

const TAG = /^v\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/;
const DATE = /^(\d{4}-\d{2}-\d{2})(?:T(\d{2}:\d{2})Z)?$/;
const COMMIT = /^[0-9a-f]{7,40}$/;
const RESULT_ID = /^H(\d+)$/;
const DECISION_ID = /^D(\d+)$/;
const RANGE = /^(\S+)\s+to\s+(\S+)$/;

const none = (value) => value === "" || value === "-";
const list = (value) => (none(value) ? [] : value.split(",").map((s) => s.trim()).filter(Boolean));

// "-", or a comma list of decision IDs and ranges like "D1 to D63".
// A range gives the decisions in it that exist (D<n> IDs only).
function decisionRefs(value, known, name, file, line) {
  const out = [];
  const need = (id) => {
    if (!/^(D\d+|R-\S+)$/.test(id)) {
      throw new RecordFormatError(file, line, `${name} "${value}" must be "-", decision IDs, or a range like D1 to D63.`);
    }
    if (!known.includes(id)) throw new RecordFormatError(file, line, `unknown decision "${id}".`);
    return id;
  };
  for (const item of list(value)) {
    const range = RANGE.exec(item);
    if (range) {
      const [from, to] = [range[1], range[2]].map((id) => DECISION_ID.exec(need(id)));
      if (!from || !to || Number(from[1]) > Number(to[1])) {
        throw new RecordFormatError(file, line, `${name} range "${item}" must go from a lower D number to a higher one.`);
      }
      for (const id of known) {
        const d = DECISION_ID.exec(id);
        if (d && Number(d[1]) >= Number(from[1]) && Number(d[1]) <= Number(to[1]) && !out.includes(id)) out.push(id);
      }
    } else if (!out.includes(need(item))) out.push(item);
  }
  return out;
}

export function readReleases(text, file, decisionIds) {
  const table = findTable(parseTables(text, file), "Releases", RELEASE_COLUMNS, file);
  const seen = new Set();
  return table.rows.map(({ line, cells: c }) => {
    if (!TAG.test(c.Tag)) {
      throw new RecordFormatError(file, line, `Tag "${c.Tag}" must look like v1.2.3 or v1.2.3-rc.1.`);
    }
    if (seen.has(c.Tag)) throw new RecordFormatError(file, line, `duplicate tag "${c.Tag}".`);
    seen.add(c.Tag);
    const date = DATE.exec(c.Date);
    if (!date) {
      throw new RecordFormatError(file, line, `Date "${c.Date}" must look like 2026-10-19 or 2026-10-19T14:30Z.`);
    }
    if (!COMMIT.test(c.Commit)) {
      throw new RecordFormatError(file, line, `Commit "${c.Commit}" must be 7 to 40 lower-case hex digits.`);
    }
    return {
      tag: c.Tag, date: date[1], time: date[2] ?? null, commit: c.Commit, summary: c.Summary,
      decisionIds: decisionRefs(c.Decisions, decisionIds, "Decisions", file, line),
      resultIds: list(c.Results), line,
    };
  });
}

// Source is a file in the repository, with an optional #anchor.
function checkSource(source, root, file, line) {
  const path = source.split("#")[0];
  const parts = path.split("/");
  const fail = () => new RecordFormatError(file, line, `Source "${source}" is not a file in the repository.`);
  if (path === "" || /[:\\]/.test(path) || parts.some((p) => p === "" || p === "." || p === "..")) throw fail();
  const full = join(root, path);
  if (!existsSync(full) || !statSync(full).isFile()) throw fail();
}

export function readResults(text, file, { root, releaseTags, decisionIds }) {
  const table = findTable(parseTables(text, file), "Results", RESULT_COLUMNS, file);
  const num = (id) => Number(RESULT_ID.exec(id)[1]);
  const seen = new Set();
  const rows = table.rows.map(({ line, cells: c }) => {
    if (!RESULT_ID.test(c.ID)) throw new RecordFormatError(file, line, `ID "${c.ID}" must look like H1.`);
    if (seen.has(c.ID)) throw new RecordFormatError(file, line, `duplicate result ID "${c.ID}".`);
    seen.add(c.ID);
    if (!none(c.Release) && !releaseTags.includes(c.Release)) {
      throw new RecordFormatError(file, line, `Release "${c.Release}" is not a tag in releases.md. Use "-" if not released yet.`);
    }
    checkSource(c.Source, root, file, line);
    return {
      id: c.ID, release: none(c.Release) ? null : c.Release, result: c.Result, value: c.Value, source: c.Source,
      decisionIds: decisionRefs(c.Decisions, decisionIds, "Decisions", file, line),
      replaces: list(c.Replaces), line,
    };
  });
  for (const r of rows) {
    for (const id of r.replaces) {
      if (!seen.has(id)) throw new RecordFormatError(file, r.line, `unknown result "${id}".`);
      if (num(id) >= num(r.id)) throw new RecordFormatError(file, r.line, `${r.id} cannot replace a later result ${id}.`);
    }
  }
  return rows.sort((a, b) => num(a.id) - num(b.id));
}

// The two files must agree both ways: each result in the Results cell of a release
// belongs to that release, and each result with a Release is in the Results cell of that release.
export function checkReleaseResults(releases, results, releasesFile, resultsFile) {
  const byId = new Map(results.map((r) => [r.id, r]));
  for (const r of releases) {
    for (const id of r.resultIds) {
      const result = byId.get(id);
      if (!result) throw new RecordFormatError(releasesFile, r.line, `unknown result "${id}".`);
      if (result.release !== r.tag) {
        const owner = result.release === null ? "has no release" : `belongs to release ${result.release}`;
        throw new RecordFormatError(releasesFile, r.line, `Results lists ${id}, but ${id} ${owner}.`);
      }
    }
  }
  const byTag = new Map(releases.map((r) => [r.tag, r]));
  for (const result of results) {
    if (result.release !== null && !byTag.get(result.release)?.resultIds.includes(result.id)) {
      throw new RecordFormatError(resultsFile, result.line,
        `${result.id} belongs to release ${result.release}, but that release does not list it.`);
    }
  }
}
