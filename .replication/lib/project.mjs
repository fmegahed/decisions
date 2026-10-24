// Assembles the markdown record of a project into one SiteModel.

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { parseTables, findTable, readMeta, RecordFormatError } from "./tables.mjs";
import { DEFAULT_TOKENS } from "./html.mjs";
import {
  readPeople, readDecisions, readRulings, readCorrectionsTable, applyCorrections, readTopics, readChecksTable, applyChecks,
} from "./decisions.mjs";
import { readReleases, readResults, checkReleaseResults } from "./releases.mjs";

export const FORMAT_VERSION = 1;
export const MILESTONE_COLUMNS = ["ID", "Milestone", "State", "Plan", "Ledger"];
export const STATES = ["done", "now", "next", "planned", "blocked"];
export const OPEN_ITEM_COLUMNS = ["ID", "Item", "Blocks", "Owner"];
export const PROCESS_COLUMNS = ["Time (UTC)", "Stage", "Who", "What happened", "Records", "Session"];
export const STAGES = ["inputs", "brainstorm", "spec-review", "plan", "build", "evaluate", "paper"];
export const BUDGET_COLUMNS = ["Date", "Service", "Purpose", "Max calls", "Max cost (USD)", "Approved by"];
export const CALL_CSV_COLUMNS = [
  "time_utc", "call_id", "purpose", "model", "request_id", "status",
  "latency_ms", "input_tokens", "output_tokens", "cost_usd",
];
export const DOC_KINDS = ["design", "plan", "ledger", "investigation", "review", "findings"];

const CONFIG_FILE = ".replication/site.config.json";
const REPOSITORY = /^https:\/\/github\.com\/[^/]+\/[^/]+$/;
const HEX_COLOUR = /^#[0-9A-Fa-f]{6}$/;
const TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?Z$/;
const DATE_PREFIX = /^(\d{4}-\d{2}-\d{2})-/;
const round3 = (n) => Math.round(n * 1000) / 1000;

// RFC 4180: quoted fields may hold commas, quotes ("") and line breaks. CRLF or LF.
export function parseCsv(text) {
  const records = [];
  let rec = [];
  let cur = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') { cur += '"'; i++; }
      else if (ch === '"') quoted = false;
      else cur += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ",") { rec.push(cur); cur = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text[i + 1] === "\n") i++;
      rec.push(cur); records.push(rec); rec = []; cur = "";
    } else cur += ch;
  }
  if (cur !== "" || rec.length) { rec.push(cur); records.push(rec); }
  const [header, ...rows] = records.filter((r) => r.length > 1 || r[0] !== "");
  if (!header) return [];
  return rows.map((r) => Object.fromEntries(header.map((h, k) => [h, r[k] ?? ""])));
}

function readRequired(base, rel) {
  const path = join(base, rel);
  if (!existsSync(path)) throw new RecordFormatError(rel, 1, "file not found");
  return readFileSync(path, "utf8");
}

const listMd = (base, dir) =>
  existsSync(join(base, dir))
    ? readdirSync(join(base, dir)).filter((f) => f.endsWith(".md")).sort().map((f) => `${dir}/${f}`)
    : [];

function oneOf(value, allowed, name, file, line) {
  if (!allowed.includes(value)) {
    throw new RecordFormatError(file, line, `${name} "${value}" is not allowed. Use one of: ${allowed.join(", ")}.`);
  }
  return value;
}

function number(value, name, file, line) {
  const n = Number(value);
  if (value.trim() === "" || !Number.isFinite(n)) {
    throw new RecordFormatError(file, line, `${name} "${value}" is not a number.`);
  }
  return n;
}

// Extra pages: project files (for example a rendered analysis) that the site
// publishes as they are, at pages/<file name>. Each file must be inside the
// project; the build copies it byte for byte.
function readPages(root, raw, bad) {
  if (raw.pages === undefined) return [];
  if (!Array.isArray(raw.pages)) {
    throw bad('pages must be a list, for example [{ "file": "analysis.html", "title": "Analysis" }].');
  }
  const names = new Map();
  return raw.pages.map((page, k) => {
    if (page === null || typeof page !== "object" || Array.isArray(page)) {
      throw bad(`pages[${k}] must be an object with file and title.`);
    }
    if (typeof page.title !== "string" || page.title.trim() === "") {
      throw bad(`pages[${k}].title must be a non-empty string.`);
    }
    // The navigation group of the page: "record" (how the work was done) or
    // "reuse" (what a reader needs to rerun the work), the default.
    const group = page.group ?? "reuse";
    if (group !== "record" && group !== "reuse") {
      throw bad(`pages[${k}].group must be "record" or "reuse", not "${page.group}".`);
    }
    // An optional one-line description: the tooltip of the link and the text
    // after the link on the Home page.
    const { description } = page;
    if (description !== undefined && (typeof description !== "string" || description.trim() === "")) {
      throw bad(`pages[${k}].description must be a non-empty string.`);
    }
    const { file } = page;
    const parts = typeof file === "string" ? file.split("/") : [];
    if (typeof file !== "string" || /[\\:]/.test(file)
      || parts.some((part) => part === "" || part === "." || part === "..")) {
      throw bad(`pages[${k}].file "${file}" must be a relative path inside the project, with "/" between folders.`);
    }
    const path = join(root, file);
    if (!existsSync(path) || !statSync(path).isFile()) throw bad(`pages[${k}].file "${file}" is not a file.`);
    const name = parts[parts.length - 1];
    if (names.has(name)) throw bad(`pages[${k}].file has the same file name as pages[${names.get(name)}].file.`);
    names.set(name, k);
    return { file, title: page.title, path: `pages/${name}`, group, ...(description !== undefined && { description }) };
  });
}

function loadConfig(root) {
  const path = join(root, CONFIG_FILE);
  if (!existsSync(path)) throw new RecordFormatError(CONFIG_FILE, 1, "file not found");
  let raw;
  try {
    raw = JSON.parse(readFileSync(path, "utf8"));
  } catch (e) {
    throw new RecordFormatError(CONFIG_FILE, 1, `not valid JSON (${e.message}).`);
  }
  const bad = (detail) => new RecordFormatError(CONFIG_FILE, 1, detail);
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) throw bad("the file must hold a JSON object.");
  if (typeof raw.format_version !== "number") throw bad("format_version must be a number.");
  if (raw.format_version > FORMAT_VERSION) {
    throw new Error(
      `${CONFIG_FILE} has format_version ${raw.format_version}, but this skill reads version ${FORMAT_VERSION}. ` +
      "Run the update procedure of the replication-materials skill.");
  }
  if (typeof raw.project !== "string" || raw.project.trim() === "") throw bad("project must be a non-empty string.");
  // The pages put these values into links and CSS, so only these forms are allowed.
  if (typeof raw.repository !== "string" || !REPOSITORY.test(raw.repository)) {
    throw bad(`repository must look like https://github.com/[owner]/[repo], not "${raw.repository}".`);
  }
  const theme = raw.theme === undefined ? {} : raw.theme;
  if (theme === null || typeof theme !== "object" || Array.isArray(theme)) {
    throw bad('theme must be an object, for example { "accent": "#00563F" }.');
  }
  for (const [key, value] of Object.entries(theme)) {
    if (!Object.hasOwn(DEFAULT_TOKENS, key)) {
      throw bad(`theme key "${key}" is not a token. Use one of: ${Object.keys(DEFAULT_TOKENS).join(", ")}.`);
    }
    if (typeof value !== "string" || !HEX_COLOUR.test(value)) {
      throw bad(`theme value ${key} "${value}" must look like #RRGGBB.`);
    }
  }
  const pages = readPages(root, raw, bad);
  return { project: raw.project, repository: raw.repository, format_version: raw.format_version, theme, pages };
}

function countTasks(base, rel, pattern, file, line, what) {
  if (!existsSync(join(base, rel))) {
    throw new RecordFormatError(file, line, `${what} file "${rel}" does not exist.`);
  }
  return [...readFileSync(join(base, rel), "utf8").matchAll(pattern)];
}

function readMilestones(base, file, tables) {
  const table = findTable(tables, "Milestones", MILESTONE_COLUMNS, file);
  return table.rows.map(({ line, cells: c }) => {
    const plan = c.Plan === "-" ? null : c.Plan;
    const ledger = c.Ledger === "-" ? null : c.Ledger;
    const tasksTotal = plan
      ? countTasks(base, plan, /^### Task \d+/gm, file, line, "Plan").length : null;
    const tasksDone = ledger
      ? new Set(countTasks(base, ledger, /^Task (\d+): complete\b/gm, file, line, "Ledger").map((m) => m[1])).size
      : null;
    return {
      id: c.ID, title: c.Milestone, state: oneOf(c.State, STATES, "State", file, line),
      plan, ledger, tasksDone, tasksTotal,
    };
  });
}

function readEvents(text, file) {
  const table = findTable(parseTables(text, file), null, PROCESS_COLUMNS, file);
  return table.rows
    .map(({ line, cells: c }) => {
      if (!TIME.test(c["Time (UTC)"])) {
        throw new RecordFormatError(file, line, `Time (UTC) "${c["Time (UTC)"]}" must look like 2026-10-19T14:30Z.`);
      }
      return {
        time: c["Time (UTC)"], stage: oneOf(c.Stage, STAGES, "Stage", file, line),
        who: c.Who, what: c["What happened"], records: c.Records, session: c.Session,
      };
    })
    .sort((a, b) => Date.parse(a.time) - Date.parse(b.time));
}

function readAllDecisions(base, people) {
  const file = "project/decisions.md";
  const text = readRequired(base, file);
  const dNum = (d) => Number(d.id.match(/\d+/)?.[0] ?? Infinity);
  const rows = readDecisions(text, file, people).sort((a, b) => dNum(a) - dNum(b));
  const rulings = listMd(base, "plans").filter((f) => f.endsWith("-ledger.md"))
    .flatMap((f) => readRulings(readFileSync(join(base, f), "utf8"), f));
  const corrected = applyCorrections([...rows, ...rulings], readCorrectionsTable(text, file), people, file);
  return {
    decisions: applyChecks(corrected, readChecksTable(text, file), people, file),
    topics: readTopics(text, file),
  };
}

// Releases and results are optional. Releases come first because each result names the tag of its release.
function readReleasesAndResults(root, base, decisionIds) {
  const [releasesFile, resultsFile] = ["project/releases.md", "project/results.md"];
  const read = (rel) => (existsSync(join(base, rel)) ? readFileSync(join(base, rel), "utf8") : null);
  const releasesText = read(releasesFile);
  const resultsText = read(resultsFile);
  const releases = releasesText === null ? [] : readReleases(releasesText, releasesFile, decisionIds);
  const results = resultsText === null ? []
    : readResults(resultsText, resultsFile, { root, releaseTags: releases.map((r) => r.tag), decisionIds });
  checkReleaseResults(releases, results, releasesFile, resultsFile);
  // Newest first. On the same date and time, the later row is the newer release: the file is append-only.
  const when = (r) => r.date + (r.time ?? "");
  releases.sort((a, b) => (when(a) < when(b) ? 1 : when(a) > when(b) ? -1 : b.line - a.line));
  return { releases, results, files: { releases: releasesText !== null, results: resultsText !== null } };
}

function docKind(rel) {
  const suffix = rel.match(/-([a-z]+)\.md$/)?.[1];
  if (DOC_KINDS.includes(suffix)) return suffix;
  if (rel === "project/contributions.md") return "contributions";
  if (rel.startsWith("probes/")) return "probes";
  if (rel.startsWith("calls/")) return "calls";
  if (rel.startsWith("findings/")) return "findings";
  if (rel.startsWith("plans/")) return "plan";
  return "readme";
}

// A plan shows its task count. A ledger shows its finished tasks and its rulings.
function docSize(path, kind, text, decisions) {
  const count = (n, one, many) => `${n} ${n === 1 ? one : many}`;
  if (kind === "plan") {
    const n = [...text.matchAll(/^### Task \d+/gm)].length;
    return n ? count(n, "task", "tasks") : null;
  }
  if (kind === "ledger") {
    const done = new Set([...text.matchAll(/^Task (\d+): complete\b/gm)].map((m) => m[1])).size;
    const rulings = decisions.filter((d) => d.file === path).length;
    return `${count(done, "task", "tasks")} complete; ${count(rulings, "ruling", "rulings")}`;
  }
  return null;
}

function readDocuments(base, milestones, decisions) {
  const probes = existsSync(join(base, "probes"))
    ? readdirSync(join(base, "probes"), { recursive: true })
        .map((p) => p.replaceAll("\\", "/")).filter((p) => p.endsWith("/README.md")).sort()
        .map((p) => `probes/${p}`)
    : [];
  const paths = ["README.md", ...listMd(base, "plans"), ...listMd(base, "findings"), ...probes, "calls/README.md", "project/contributions.md"]
    .filter((p) => existsSync(join(base, p)));
  return paths.map((path) => {
    const text = readFileSync(join(base, path), "utf8");
    const { title, meta } = readMeta(text, path);
    const parts = path.split("/");
    const datedName = path.startsWith("probes/") ? parts[1] : parts[parts.length - 1];
    const kind = docKind(path);
    const milestone = milestones.find((m) => m.plan === path || m.ledger === path)?.id ?? null;
    return {
      path, title: title ?? parts[parts.length - 1], kind,
      date: datedName.match(DATE_PREFIX)?.[1] ?? null, status: meta.Status ?? null, text,
      writtenBy: meta["Written by"] ?? null, approvedBy: meta["Approved by"] ?? null,
      milestone, size: docSize(path, kind, text, decisions),
    };
  }).sort((a, b) => (a.date === b.date ? 0 : a.date === null ? 1 : b.date === null ? -1 : a.date < b.date ? -1 : 1)
    || (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
}

function readCalls(base) {
  const budgets = [];
  const readme = "calls/README.md";
  if (existsSync(join(base, readme))) {
    const table = findTable(parseTables(readFileSync(join(base, readme), "utf8"), readme), null, BUDGET_COLUMNS, readme);
    for (const { line, cells: c } of table.rows) {
      budgets.push({
        date: c.Date, service: c.Service, purpose: c.Purpose,
        maxCalls: number(c["Max calls"], "Max calls", readme, line),
        maxCostUsd: number(c["Max cost (USD)"], "Max cost (USD)", readme, line),
        approvedBy: c["Approved by"],
      });
    }
  }
  const services = new Map();
  const entry = (service) => {
    if (!services.has(service)) services.set(service, { service, calls: 0, costUsd: 0, maxCalls: 0, maxCostUsd: 0 });
    return services.get(service);
  };
  for (const b of budgets) {
    const s = entry(b.service);
    s.maxCalls += b.maxCalls;
    s.maxCostUsd += b.maxCostUsd;
  }
  const dir = join(base, "calls");
  const csvs = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith("-calls.csv")).sort() : [];
  for (const f of csvs) {
    const rel = `calls/${f}`;
    const text = readFileSync(join(base, rel), "utf8");
    const header = text.split(/\r?\n/, 1)[0].split(",").map((h) => h.trim());
    const missing = CALL_CSV_COLUMNS.filter((c) => !header.includes(c));
    if (missing.length) throw new RecordFormatError(rel, 1, `lacks column(s) ${missing.join(", ")}.`);
    // A budget row joins its log by name: Service is the <service> of
    // calls/<service>-calls.csv. A log that no row names has no budget.
    const name = f.slice(0, -"-calls.csv".length);
    if (!budgets.some((b) => b.service === name)) {
      throw new RecordFormatError(rel, 1,
        `no budget row in calls/README.md has the Service "${name}". Write "${name}" in the Service column of the budget rows of this log.`);
    }
    const s = entry(name);
    parseCsv(text).forEach((r, k) => {
      s.calls += 1;
      // A failed call can have no cost: an empty cell counts as 0 (Task 4 ruling).
      s.costUsd += r.cost_usd.trim() === "" ? 0 : number(r.cost_usd, "cost_usd", rel, k + 2);
    });
  }
  const list = [...services.values()].sort((a, b) => a.service.localeCompare(b.service))
    .map((s) => ({ ...s, costUsd: round3(s.costUsd), maxCostUsd: round3(s.maxCostUsd) }));
  return { budgets, services: list };
}

function gitSha(root) {
  try {
    const out = execFileSync("git", ["rev-parse", "--short", "HEAD"], {
      cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return out || "local";
  } catch {
    return "local";
  }
}

export function loadProject(root, opts = {}) {
  const config = loadConfig(root);
  const base = join(root, "replication_materials");
  const roadmapFile = "project/roadmap.md";
  const roadmap = readRequired(base, roadmapFile);
  const people = readPeople(roadmap, roadmapFile);
  const roadmapTables = parseTables(roadmap, roadmapFile);
  const milestones = readMilestones(base, roadmapFile, roadmapTables);
  const openItems = findTable(roadmapTables, "Open items", OPEN_ITEM_COLUMNS, roadmapFile).rows.map(({ cells: c }) => ({
    id: c.ID, item: c.Item, blocks: c.Blocks, owner: c.Owner,
  }));
  const { decisions, topics } = readAllDecisions(base, people);
  const { releases, results, files: recordFiles } = readReleasesAndResults(root, base, decisions.map((d) => d.id));
  const tally = new Map();
  for (const d of decisions) for (const id of d.decidedBy) tally.set(id, (tally.get(id) ?? 0) + 1);
  const byDecider = [...tally].map(([id, count]) => ({ id, name: people.get(id).name, count }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
  return {
    config, people, milestones, openItems,
    status: {
      current: milestones.find((m) => m.state === "now") ?? null,
      next: milestones.find((m) => m.state === "next") ?? null,
    },
    decisions,
    topics,
    releases,
    results,
    recordFiles,
    events: readEvents(readRequired(base, "project/process.md"), "project/process.md"),
    documents: readDocuments(base, milestones, decisions),
    calls: readCalls(base),
    counts: { byDecider },
    build: { sha: opts.gitSha ?? gitSha(root), date: opts.buildDate ?? new Date().toISOString().slice(0, 10) },
  };
}
