// People, decisions, rulings and corrections read from record files.

import { parseTables, findTable, fenceFlags, RecordFormatError } from "./tables.mjs";

export const PEOPLE_COLUMNS = ["ID", "Name", "Role", "Link"];
export const DECISION_COLUMNS = ["ID", "Date", "Decision", "Proposed by", "Decided by", "How", "Evidence", "Source"];
export const CORRECTION_COLUMNS = ["Decision", "Field", "New value", "Checked by", "Date", "Note"];
export const TOPIC_COLUMNS = ["Topic", "Meaning"];
export const CHECK_COLUMNS = ["Decision", "Checked by", "Date", "Note"];
export const HOW_VALUES = ["chat", "question", "review", "measurement", "plan-approval", "playback", "ruling", "classified"];
export const BUILT_IN_PEOPLE = { claude: "Claude Code", subagent: "Subagent", unknown: "Unknown" };

// Correction "Field" values and the decision property each one replaces.
const CORRECTION_FIELDS = {
  "Decision": "text",
  "Proposed by": "proposedBy",
  "Decided by": "decidedBy",
  "How": "how",
  "Evidence": "evidence",
};

export function readPeople(roadmapText, file) {
  const table = findTable(parseTables(roadmapText, file), "People", PEOPLE_COLUMNS, file);
  const people = new Map();
  for (const [id, name] of Object.entries(BUILT_IN_PEOPLE)) people.set(id, { id, name, role: "", link: "" });
  for (const { line, cells: c } of table.rows) {
    // A row must not replace a built-in name: that would change who a decision shows (A3).
    if (Object.hasOwn(BUILT_IN_PEOPLE, c.ID)) {
      throw new RecordFormatError(file, line,
        `ID "${c.ID}" is a built-in ID. Do not use ${Object.keys(BUILT_IN_PEOPLE).join(", ")} in ## People.`);
    }
    people.set(c.ID, { id: c.ID, name: c.Name, role: c.Role, link: c.Link });
  }
  return people;
}

function personIds(value, people, file, line) {
  const ids = value.split(",").map((s) => s.trim()).filter(Boolean);
  if (!ids.length) throw new RecordFormatError(file, line, "a person ID is required.");
  for (const id of ids) {
    if (!people.has(id)) {
      throw new RecordFormatError(file, line, `unknown person "${id}". Known IDs: ${[...people.keys()].join(", ")}.`);
    }
  }
  return ids;
}

function checkHow(value, file, line) {
  if (!HOW_VALUES.includes(value)) {
    throw new RecordFormatError(file, line, `How "${value}" is not allowed. Use one of: ${HOW_VALUES.join(", ")}.`);
  }
  return value;
}

// An empty cell or "-" means "not given".
const given = (value) => {
  const v = (value ?? "").trim();
  return v === "" || v === "-" ? null : v;
};

const TIME_OF_DAY = /^([01]\d|2[0-3]):[0-5]\d$/;
const DECISION_ID = /^D(\d+)$/;

// claude, subagent and unknown are not people.
const isPerson = (id) => !Object.hasOwn(BUILT_IN_PEOPLE, id);

// A decision needs a check when its How is classified, in its row or after a correction.
// Only a person removes the mark: with a check, or with a correction. A correction by a
// built-in ID is valid, but it does not count.
const isChecked = (d, needsCheck) => !needsCheck || d.checks.length > 0 || Boolean(d.corrected?.byIds.some(isPerson));
// Before a correction or a check changes d.checked: does d need a check now?
const needsCheck = (d) => !d.checked || d.how === "classified";

export function readTopics(text, file) {
  const table = parseTables(text, file).find((t) => t.heading === "Topics");
  if (!table) return [];
  const seen = new Set();
  return findTable([table], "Topics", TOPIC_COLUMNS, file).rows.map(({ line, cells: c }) => {
    if (given(c.Topic) === null) {
      throw new RecordFormatError(file, line, "the Topic cell is empty. Write a topic or remove the row.");
    }
    if (seen.has(c.Topic)) throw new RecordFormatError(file, line, `duplicate topic "${c.Topic}".`);
    seen.add(c.Topic);
    return { topic: c.Topic, meaning: c.Meaning };
  });
}

export function readChecksTable(text, file) {
  const table = parseTables(text, file).find((t) => t.heading === "Checks");
  return table ? findTable([table], "Checks", CHECK_COLUMNS, file) : null;
}

export function readDecisions(text, file, people) {
  const table = findTable(parseTables(text, file), "Decisions", DECISION_COLUMNS, file);
  const topics = readTopics(text, file).map((t) => t.topic);
  if (table.columns.includes("Topic") && !parseTables(text, file).some((t) => t.heading === "Topics")) {
    throw new RecordFormatError(file, table.line, "a Topic column needs a ## Topics table.");
  }
  const seen = new Set();
  const rows = table.rows.map(({ line, cells: c }) => {
    if (seen.has(c.ID)) throw new RecordFormatError(file, line, `duplicate decision ID "${c.ID}".`);
    seen.add(c.ID);
    const time = given(c["Time (UTC)"]);
    if (time !== null && !TIME_OF_DAY.test(time)) {
      throw new RecordFormatError(file, line, `Time (UTC) "${time}" must look like 14:30.`);
    }
    const topic = given(c.Topic);
    if (topic !== null && !topics.includes(topic)) {
      throw new RecordFormatError(file, line, `Topic "${topic}" is not in ## Topics. Use one of: ${topics.join(", ")}.`);
    }
    const replaces = (given(c.Replaces) ?? "").split(",").map((s) => s.trim()).filter(Boolean);
    const d = {
      id: c.ID,
      date: c.Date,
      time,
      text: c.Decision,
      proposedBy: personIds(c["Proposed by"], people, file, line),
      decidedBy: personIds(c["Decided by"], people, file, line),
      how: checkHow(c.How, file, line),
      evidence: c.Evidence,
      source: c.Source,
      topic,
      impact: given(c.Impact),
      replaces,
      file,
      line,
      corrected: null,
      checks: [],
    };
    d.checked = isChecked(d, d.how === "classified");
    return d;
  });
  // Replaces points to earlier decisions only, so check it after all rows are read.
  for (const d of rows) {
    const mine = DECISION_ID.exec(d.id);
    for (const id of d.replaces) {
      const theirs = DECISION_ID.exec(id);
      if (!theirs) {
        throw new RecordFormatError(file, d.line, `Replaces "${id}" must be a decision ID like D3.`);
      }
      if (!seen.has(id)) throw new RecordFormatError(file, d.line, `unknown decision "${id}".`);
      if (mine && Number(theirs[1]) >= Number(mine[1])) {
        throw new RecordFormatError(file, d.line, `${d.id} cannot replace a later decision ${id}.`);
      }
    }
  }
  return rows;
}

// A ruling line starts with "Ruling:" or "Ruling <n>:", after an optional "- ", backtick
// and "Task <n>:" or "Final:" prefix. Prose that mentions "Ruling:" later in a line is not a ruling.
const RULING = /^\s*(?:-\s+)?(`)?(?:(?:Task \d+[a-z]?|Final):\s+)?Ruling(?:\s+\d+)?:\s*(.+)$/;

export function readRulings(text, ledgerPath) {
  const base = ledgerPath.split("/").pop();
  const m = base.match(/^(\d{4}-\d{2}-\d{2})-(.+)-ledger\.md$/);
  if (!m) {
    throw new RecordFormatError(ledgerPath, 1, `ledger file name must look like YYYY-MM-DD-<topic>-ledger.md, not "${base}".`);
  }
  const [, date, topic] = m;
  const lines = text.split(/\r?\n/);
  const inFence = fenceFlags(lines);
  const rulings = [];
  lines.forEach((line, i) => {
    if (inFence[i]) return;
    const r = line.match(RULING);
    if (!r) return;
    // The same shape as a row of decisions.md (M12).
    rulings.push({
      id: `R-${date}-${topic}-${rulings.length + 1}`,
      date,
      time: null,
      // Only the form "`Ruling: x`" wraps the line in backticks: then drop the closing one.
      text: (r[1] ? r[2].replace(/`\s*$/, "") : r[2]).trim(),
      proposedBy: ["claude"],
      decidedBy: ["claude"],
      how: "ruling",
      evidence: "",
      source: `${ledgerPath}:${i + 1}`,
      topic: null,
      impact: null,
      replaces: [],
      file: ledgerPath,
      line: i + 1,
      corrected: null,
      checks: [],
      checked: true,
    });
  });
  return rulings;
}

export function readCorrectionsTable(text, file) {
  const table = parseTables(text, file).find((t) => t.heading === "Corrections");
  return table ? findTable([table], "Corrections", CORRECTION_COLUMNS, file) : null;
}

export function applyCorrections(decisions, table, people, file) {
  const out = decisions.map((d) => ({ ...d }));
  if (!table) return out;
  const byId = new Map(out.map((d) => [d.id, d]));
  for (const { line, cells: c } of table.rows) {
    const d = byId.get(c.Decision);
    if (!d) throw new RecordFormatError(file, line, `correction names unknown decision "${c.Decision}".`);
    const prop = CORRECTION_FIELDS[c.Field];
    if (!prop) {
      throw new RecordFormatError(file, line,
        `correction Field "${c.Field}" is not allowed. Use one of: ${Object.keys(CORRECTION_FIELDS).join(", ")}.`);
    }
    const [checker] = personIds(c["Checked by"], people, file, line);
    const value = c["New value"];
    if (prop === "proposedBy" || prop === "decidedBy") d[prop] = personIds(value, people, file, line);
    else if (prop === "how") d.how = checkHow(value, file, line);
    else d[prop] = value;
    const prev = d.corrected ?? { by: "", byIds: [], date: "", notes: [], fields: [] };
    // by and date are of the last row. byIds holds each checker ID, in row order.
    d.corrected = {
      by: people.get(checker).name,
      byIds: prev.byIds.includes(checker) ? prev.byIds : [...prev.byIds, checker],
      date: c.Date,
      notes: c.Note ? [...prev.notes, c.Note] : prev.notes,
      fields: prev.fields.includes(c.Field) ? prev.fields : [...prev.fields, c.Field],
    };
    d.checked = isChecked(d, needsCheck(d));
  }
  return out;
}

export function applyChecks(decisions, table, people, file) {
  const out = decisions.map((d) => ({ ...d }));
  if (!table) return out;
  const byId = new Map(out.map((d) => [d.id, d]));
  for (const { line, cells: c } of table.rows) {
    const d = byId.get(c.Decision);
    if (!d) throw new RecordFormatError(file, line, `check names unknown decision "${c.Decision}".`);
    const ids = personIds(c["Checked by"], people, file, line);
    const builtIn = ids.find((id) => !isPerson(id));
    if (builtIn) {
      throw new RecordFormatError(file, line,
        `Checked by "${builtIn}" must be a person of ## People. Only a person can check a decision.`);
    }
    d.checks = [...d.checks, { by: people.get(ids[0]).name, byId: ids[0], date: c.Date, note: c.Note }];
    d.checked = isChecked(d, needsCheck(d));
  }
  return out;
}
