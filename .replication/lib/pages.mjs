// Page renderers: SiteModel in, a Map of site path to HTML out.
import { readFileSync } from "node:fs";
import { escapeHtml, inline, rel, pageShell, navGroups, NAV_GROUPS, REPOSITORY_DESCRIPTION, CDN } from "./html.mjs";
import { STAGES } from "./project.mjs";

const read = (f) => readFileSync(new URL(f, import.meta.url), "utf8");
const CLIENT_JS = read("./linkpath.js") + read("./client.js");

const PAGE_CSS = `<style>
.lead { font-size: 1.15rem; max-width: 48rem; }
.strip { list-style: none; margin: 1rem 0; padding: 0; display: flex; flex-wrap: wrap; gap: 0.5rem; }
.strip li { background: var(--surface); border: 2px solid var(--ink); padding: 0.5rem 0.75rem; }
.strip .state { font-weight: 700; text-transform: uppercase; font-size: 0.8rem; letter-spacing: 0.04em; }
.strip .now { background: var(--tan); }
.filter-group { margin: 0 0 0.75rem; }
.filter-group p { margin: 0 0 0.25rem; font-weight: 700; }
.filter-group .buttons { display: flex; flex-wrap: wrap; gap: 0.5rem; }
.table-wrap { margin: 1rem 0; }
.table-wrap table { min-width: 36rem; }
caption { text-align: left; font-weight: 700; padding: 0 0 0.5rem; }
.note { color: var(--muted); }
.timeline-list { list-style: none; margin: 0 0 1rem; padding: 0; }
.timeline-list li { padding: 0.25rem 0; }
.bar-track { position: relative; height: 0.75rem; min-width: 8rem; background: var(--tan); }
.bar { position: absolute; top: 0; bottom: 0; background: var(--accent-strong); }
#doc-content { max-width: 52rem; }
#doc-content table { min-width: 0; }
#doc-fallback { white-space: pre-wrap; }
</style>`;

const personName = (model, id) => model.people.get(id)?.name ?? id;
const names = (model, ids) => ids.map((id) => personName(model, id)).join(", ") || "-";
const docPath = (p) => `docs/${p.replace(/\.md$/, "")}/index.html`;
const clientScript = () => `<script>\n${CLIENT_JS}</script>`;

function table(caption, headers, rows) {
  const head = headers.map((h) => `<th scope="col">${escapeHtml(h)}</th>`).join("");
  return `<div class="table-wrap" tabindex="0" role="region" aria-label="${escapeHtml(caption)}">
<table>
<caption>${escapeHtml(caption)}</caption>
<thead><tr>${head}</tr></thead>
<tbody>
${rows.join("\n")}
</tbody>
</table>
</div>`;
}

const tr = (cells, attrs = "") => `<tr${attrs}>${cells.map((c) => `<td>${c}</td>`).join("")}</tr>`;

// groups: [{ key, label, options: [{ value, label }] }]. The "All" button clears a group.
function filterBar(groups, total) {
  const html = groups.map((g) => {
    const buttons = [{ value: "", label: "All" }, ...g.options].map((o) =>
      `<button type="button" data-filter-key="${g.key}" data-filter-value="${escapeHtml(o.value)}" aria-pressed="${o.value === "" ? "true" : "false"}">${escapeHtml(o.label)}</button>`);
    return `<div class="filter-group" role="group" aria-label="${escapeHtml(g.label)}">
<p>${escapeHtml(g.label)}</p>
<div class="buttons">${buttons.join("\n")}</div>
</div>`;
  });
  return `<div data-filters hidden>
${html.join("\n")}
</div>
<p data-filter-count aria-live="polite">Showing ${total} of ${total}.</p>`;
}

// A link to the document page when the path is a record document, else code text.
function recordRef(model, from, path) {
  if (!path || path === "-") return "-";
  const clean = path.split("#")[0];
  if (model.documents.some((d) => d.path === clean)) {
    return `<a href="${escapeHtml(rel(from, docPath(clean)))}">${escapeHtml(path)}</a>`;
  }
  return `<code>${escapeHtml(path)}</code>`;
}

function shell(model, path, title, body, extra = {}) {
  return pageShell({ path, title, body, model, head: PAGE_CSS + (extra.head ?? ""), scripts: extra.scripts ?? "" });
}

export function renderHome(model) {
  const path = "index.html";
  const readme = model.documents.find((d) => d.path === "README.md");
  const lead = readme?.text.split(/\r?\n\r?\n/).map((p) => p.trim())
    .find((p) => p && !p.startsWith("#") && !p.startsWith("|") && !p.startsWith("```"));
  const { current, next } = model.status;
  const ms = (m) => (m ? `${escapeHtml(m.id)} ${escapeHtml(m.title)}` : "none");
  const strip = model.milestones.length
    ? `<ol class="strip">\n${model.milestones.map((m) =>
      `<li class="${escapeHtml(m.state)}"><span class="state">${escapeHtml(m.state)}</span> ${escapeHtml(m.id)} ${escapeHtml(m.title)}</li>`).join("\n")}\n</ol>`
    : "<p>No milestones yet.</p>";
  const counts = model.counts.byDecider.length
    ? `<ul>\n${model.counts.byDecider.map((c) => `<li>${escapeHtml(c.name)}: ${c.count}</li>`).join("\n")}\n</ul>`
    : "<p>No decisions yet.</p>";
  const link = (target, label) => `<li><a href="${escapeHtml(rel(path, target))}">${label}</a></li>`;
  // The pages under the two reader groups of the navigation, in its order,
  // each with its description as visible text (screens with no hover).
  const groups = navGroups(model);
  const described = (item, description) => (description ? item.replace(/<\/li>$/, `: ${escapeHtml(description)}</li>`) : item);
  const pageLinks = NAV_GROUPS.map(({ group, label }) => {
    const items = groups[group].filter(([, target]) => target !== "index.html")
      .map(([text, target, description]) => described(link(target, escapeHtml(text)), description));
    if (group === "reuse") {
      items.push(described(`<li><a href="${escapeHtml(model.config.repository)}">Repository</a></li>`, REPOSITORY_DESCRIPTION));
    }
    return `<h3>${escapeHtml(label)}</h3>
<ul>
${items.join("\n")}
</ul>`;
  }).join("\n");
  const release = model.releases[0];
  const nowItems = [
    `<li>Latest release: ${release ? `${escapeHtml(release.tag)}, ${escapeHtml(release.date)}` : "No release yet."}</li>`,
    `<li>Milestone in progress: ${current ? ms(current) : "No milestone is in progress."}</li>`,
  ].join("\n");
  const open = model.openItems.length
    ? `<ul>
${model.openItems.map((o) => `<li>${escapeHtml(o.id)}: ${escapeHtml(o.item)}</li>`).join("\n")}
</ul>`
    : "<p>No open items.</p>";
  const body = `<h1>${escapeHtml(model.config.project)}</h1>
${lead ? `<p class="lead">${inline(lead)}</p>` : ""}
<h2>Now</h2>
<ul>
${nowItems}
</ul>
<h3>Open items</h3>
${open}
<h2>Status</h2>
<p>Current milestone: ${ms(current)}. Next milestone: ${ms(next)}. Date: ${escapeHtml(model.build.date)}.</p>
<h2>Milestones</h2>
${strip}
<h2>Decisions by decider</h2>
${counts}
<h2>Pages</h2>
${pageLinks}`;
  return shell(model, path, "Home", body);
}

export function renderRecords(model) {
  const path = "records/index.html";
  const kinds = [...new Set(model.documents.map((d) => d.kind))];
  // The name of a short link holds its visible text and the title (WCAG 2.5.3).
  const rows = model.documents.map((d) => tr([
    escapeHtml(d.date ?? "-"),
    `<a href="${escapeHtml(rel(path, docPath(d.path)))}">${escapeHtml(d.title)}</a>`,
    escapeHtml(d.kind), escapeHtml(d.milestone ?? "-"), escapeHtml(d.size ?? "-"), escapeHtml(d.status ?? "-"),
    `<a href="${escapeHtml(rel(path, docPath(d.path)))}" aria-label="${escapeHtml(`Page: ${d.title}`)}">Page</a> `
      + `<a href="${escapeHtml(`${model.config.repository}/blob/main/replication_materials/${d.path}`)}" aria-label="${escapeHtml(`GitHub: ${d.title}`)}">GitHub</a>`,
  ], ` data-row data-kind="${escapeHtml(d.kind)}"`));
  const content = model.documents.length
    ? filterBar([{ key: "kind", label: "Kind", options: kinds.map((k) => ({ value: k, label: k })) }], model.documents.length)
      + table("All documents", ["Date", "Title", "Kind", "Milestone", "Size", "Status", "Links"], rows)
    : "<p>No documents yet.</p>";
  return shell(model, path, "Records", `<h1>Records</h1>\n${content}`, { scripts: model.documents.length ? clientScript() : "" });
}

const PERSON_NONE = new Set(["claude", "subagent", "unknown"]);
const isPerson = (id) => !PERSON_NONE.has(id);
// The Timeline counts a decision only when Claude Code or a subagent alone decided it.
const isClaudeDecision = (d) => d.decidedBy.every((id) => id === "claude" || id === "subagent");
const pct = (n) => `${Math.round(n * 100) / 100}%`;
const when = (d) => (d.time ? `${d.date} ${d.time}` : d.date);
const note = (text) => `<br><span class="note">${text}</span>`;

// A table whose first column holds row headers. rows: [{ label, cells: [value] }].
function grid(caption, corner, cols, rows) {
  const head = [corner, ...cols].map((h) => `<th scope="col">${escapeHtml(h)}</th>`).join("");
  const body = rows.map((r) => `<tr><th scope="row">${escapeHtml(r.label)}</th>${r.cells.map((c) => `<td>${escapeHtml(String(c))}</td>`).join("")}</tr>`);
  return `<div class="table-wrap" tabindex="0" role="region" aria-label="${escapeHtml(caption)}">
<table>
<caption>${escapeHtml(caption)}</caption>
<thead><tr>${head}</tr></thead>
<tbody>
${body.join("\n")}
</tbody>
</table>
</div>`;
}

const bar = (n, max) => `<div class="bar-track" aria-hidden="true"><div class="bar" aria-hidden="true" style="left:0;width:${pct((n / max) * 100)}"></div></div>`;

// Bins for "Decisions over time": days, or hours when every decision has one date.
function timeBins(decisions) {
  const dates = new Set(decisions.map((d) => d.date));
  const bins = new Map();
  const add = (key) => bins.set(key, (bins.get(key) ?? 0) + 1);
  const byKey = (a, b) => (a[0] < b[0] ? -1 : 1);
  if (dates.size >= 2 || !decisions.some((d) => d.time)) {
    for (const d of decisions) add(d.date);
    return [...bins].sort(byKey);
  }
  for (const d of decisions) if (d.time) add(`${d.time.slice(0, 2)}:00`);
  const sorted = [...bins].sort(byKey);
  const none = decisions.filter((d) => !d.time).length;
  return none ? [...sorted, ["No time", none]] : sorted;
}

const topicList = (model) => [...new Set([...model.topics.map((t) => t.topic), ...model.decisions.map((d) => d.topic).filter(Boolean)])];

export function renderDecisions(model) {
  const path = "decisions/index.html";
  const deciders = [...new Set(model.decisions.flatMap((d) => d.decidedBy))];
  const hows = [...new Set(model.decisions.map((d) => d.how))];
  const topics = topicList(model);
  const rows = model.decisions.map((d) => {
    const fix = (d.corrected
      ? note(`Corrected by ${escapeHtml(d.corrected.by)}, ${escapeHtml(d.corrected.date)}.${
        d.corrected.notes.length ? ` ${escapeHtml(d.corrected.notes.join(" "))}` : ""}`)
      : "")
      + d.checks.map((c) => note(`Checked by ${escapeHtml(c.by)}, ${escapeHtml(c.date)}.`)).join("");
    const detail = (d.impact ? note(`Impact: ${escapeHtml(d.impact)}`) : "")
      + (d.replaces.length ? note(`Replaces ${escapeHtml(d.replaces.join(", "))}.`) : "")
      + (d.checked ? "" : note("Not checked by a person."));
    return tr([
      escapeHtml(d.id), escapeHtml(when(d)), inline(d.text) + fix + detail,
      escapeHtml(names(model, d.proposedBy)), escapeHtml(names(model, d.decidedBy)),
      escapeHtml(d.how), recordRef(model, path, d.evidence), recordRef(model, path, d.source),
    ], ` data-row data-decided="${escapeHtml(d.decidedBy.join(" "))}" data-how="${escapeHtml(d.how)}" data-topic="${escapeHtml(d.topic ?? "")}"`);
  });
  const groups = [
    { key: "decided", label: "Decided by", options: deciders.map((id) => ({ value: id, label: personName(model, id) })) },
    { key: "how", label: "How", options: hows.map((h) => ({ value: h, label: h })) },
  ];
  if (topics.length) groups.push({ key: "topic", label: "Topic", options: topics.map((t) => ({ value: t, label: t })) });

  let content = "<p>No decisions yet.</p>";
  if (model.decisions.length) {
    content = filterBar(groups, model.decisions.length)
      + table("All decisions", ["ID", "Date", "Decision", "Proposed by", "Decided by", "How", "Evidence", "Source"], rows);
    const own = model.decisions.filter((d) => d.how !== "ruling");
    if (topics.length && own.length) {
      const cols = [...new Set(own.flatMap((d) => d.decidedBy))];
      const keys = [...topics, ...(own.some((d) => !d.topic) ? [null] : [])];
      const trows = keys.map((t) => {
        const set = own.filter((d) => d.topic === t);
        return { label: t ?? "No topic", cells: [...cols.map((c) => set.filter((d) => d.decidedBy.includes(c)).length), set.length] };
      });
      content += `\n<h2>Who decided, by topic</h2>\n${grid("Who decided, by topic", "Topic", [...cols.map((c) => personName(model, c)), "Total"], trows)}`;
    }
    if (own.length) {
      const bins = timeBins(own);
      const max = Math.max(...bins.map((b) => b[1]));
      content += `\n<h2>Decisions over time</h2>\n${table("Decisions over time", ["Period", "Decisions", "Chart"],
        bins.map(([label, n]) => tr([escapeHtml(label), String(n), bar(n, max)])))}`;
    }
  }
  return shell(model, path, "Decisions", `<h1>Decisions</h1>\n${content}`, { scripts: model.decisions.length ? clientScript() : "" });
}

export function renderContributions(model) {
  const path = "contributions/index.html";
  const all = model.decisions;
  const own = all.filter((d) => d.how !== "ruling");
  const rulings = all.length - own.length;
  const unchecked = all.filter((d) => !d.checked).length;
  const account = model.documents.find((d) => d.path === "project/contributions.md");
  // A value of the Item/Value table, or "-". One end period goes, so that the sentence ends once.
  const item = (v) => escapeHtml((v ?? "-").replace(/\.$/, "") || "-");
  let body = "<h1>Contributions</h1>\n<h2>Account of the researchers</h2>\n";
  body += account
    ? `<p><a href="${escapeHtml(rel(path, docPath(account.path)))}">${escapeHtml(account.title)}</a></p>
<p>Status: ${item(account.status)}. Written by: ${item(account.writtenBy)}. Approved by: ${item(account.approvedBy)}.</p>`
    : "<p>The researchers have not written their account yet.</p>";
  if (!all.length) return shell(model, path, "Contributions", `${body}\n<p>No decisions yet.</p>`);

  body += `\n<p>${unchecked === 0 ? "A person checked every decision."
    : `${unchecked} ${unchecked === 1 ? "decision is" : "decisions are"} not checked by a person. The Decisions page marks each of them.`}</p>\n`;

  const side = (key) => [...new Set(own.flatMap((d) => d[key]))];
  const rowIds = side("proposedBy");
  const colIds = side("decidedBy");
  const cell = (r, c) => own.filter((d) => d.proposedBy.includes(r) && d.decidedBy.includes(c)).length;
  body += `<h2>Who proposed and who decided</h2>
${own.length ? grid("Who proposed and who decided", "Proposed by (rows), decided by (columns)", colIds.map((c) => personName(model, c)),
    rowIds.map((r) => ({ label: personName(model, r), cells: colIds.map((c) => cell(r, c)) }))) : "<p>No decisions yet.</p>"}
${rulings ? `<p class="note">${rulings} ${rulings === 1 ? "ruling" : "rulings"} by Claude Code ${rulings === 1 ? "is" : "are"} not in the grid.</p>` : ""}
`;

  const list = (caption, ds) => (ds.length
    ? table(caption, ["ID", "Date", "Decision", "Evidence"], ds.map((d) => tr([
      escapeHtml(d.id), escapeHtml(when(d)),
      inline(d.text) + (d.checked ? "" : note("not checked by a person")), recordRef(model, path, d.evidence)])))
    : "<p>No decisions in this group.</p>");
  const byPerson = own.filter((d) => d.proposedBy.some(isPerson));
  const aiThenPerson = own.filter((d) => d.proposedBy.some((id) => id === "claude" || id === "subagent") && d.decidedBy.some(isPerson));
  body += `<h2>Proposed by the researchers</h2>\n${list("Decisions proposed by the researchers", byPerson)}
<h2>Proposed by Claude Code and decided by a researcher</h2>\n${list("Decisions proposed by Claude Code and decided by a researcher", aiThenPerson)}
`;

  const pairs = all.flatMap((d) => d.replaces.map((old) => `<li>${escapeHtml(old)} → replaced by ${escapeHtml(d.id)}</li>`));
  body += `<h2>Replaced decisions</h2>\n${pairs.length ? `<ul>\n${pairs.join("\n")}\n</ul>` : "<p>No decision is replaced.</p>"}\n`;

  const fixes = all.flatMap((d) => [
    ...(d.corrected ? [tr([escapeHtml(d.id), "Correction", escapeHtml(d.corrected.by), escapeHtml(d.corrected.date),
      escapeHtml([d.corrected.fields.join(", "), d.corrected.notes.join(" ")].filter(Boolean).join(": ") || "-")])] : []),
    ...d.checks.map((c) => tr([escapeHtml(d.id), "Check", escapeHtml(c.by), escapeHtml(c.date), escapeHtml(c.note || "-")])),
  ]);
  // Every row names its maker in By: a person, Claude Code, Subagent or Unknown (Ruling 12).
  body += `<h2>Corrections and checks</h2>\n${fixes.length
    ? table("Corrections and checks", ["Decision", "Kind", "By", "Date", "Detail"], fixes) : "<p>No corrections or checks yet.</p>"}`;
  return shell(model, path, "Contributions", body);
}

const repoUrl = (model) => model.config.repository.replace(/\/$/, "");
// name: an accessible name that starts with the label, for a link whose label alone is too short.
const extLink = (href, label, name) =>
  `<a href="${escapeHtml(href)}"${name ? ` aria-label="${escapeHtml(name)}"` : ""}>${escapeHtml(label)}</a>`;

export function renderReleases(model) {
  const path = "releases/index.html";
  const repo = repoUrl(model);
  const byId = new Map(model.decisions.map((d) => [d.id, d]));
  const resultById = new Map(model.results.map((r) => [r.id, r]));
  const parts = model.releases.map((r, i) => {
    const older = model.releases[i + 1];
    const links = [extLink(`${repo}/tree/${r.tag}`, "Files at this tag", `Files at this tag: ${r.tag}`),
      extLink(`${repo}/commit/${r.commit}`, `Commit ${r.commit.slice(0, 7)}`)];
    if (older) links.push(extLink(`${repo}/compare/${older.tag}...${r.tag}`, `Changes since ${older.tag}`));
    const dRows = r.decisionIds.map((id) => byId.get(id)).filter(Boolean)
      .map((d) => tr([escapeHtml(d.id), inline(d.text), escapeHtml(names(model, d.proposedBy)), escapeHtml(names(model, d.decidedBy))]));
    const rRows = r.resultIds.map((id) => resultById.get(id)).filter(Boolean)
      .map((x) => tr([escapeHtml(x.id), inline(x.result), escapeHtml(x.value)]));
    return `<section>
<h2>${escapeHtml(r.tag)}</h2>
<p class="note">${escapeHtml(r.date)}${r.time ? ` ${escapeHtml(r.time)} UTC` : ""}</p>
<p>${inline(r.summary)}</p>
<ul>
${links.map((l) => `<li>${l}</li>`).join("\n")}
</ul>
${dRows.length ? table(`Decisions in ${r.tag}`, ["ID", "Decision", "Proposed by", "Decided by"], dRows) : "<p>No decisions in this release.</p>"}
${rRows.length ? table(`Results in ${r.tag}`, ["ID", "Result", "Value"], rRows) : "<p>No results in this release.</p>"}
</section>`;
  });
  const content = parts.length ? parts.join("\n") : "<p>No releases yet.</p>";
  return shell(model, path, "Releases", `<h1>Releases</h1>\n${content}`);
}

export function renderResults(model) {
  const path = "results/index.html";
  const repo = repoUrl(model);
  const replacedBy = new Map();
  for (const r of model.results) for (const old of r.replaces) replacedBy.set(old, [...(replacedBy.get(old) ?? []), r.id]);
  const status = (r) => (replacedBy.has(r.id) ? `Replaced by ${replacedBy.get(r.id).join(", ")}` : "Current");
  const releases = [...new Set(model.results.map((r) => r.release).filter(Boolean))];
  const hasUnreleased = model.results.some((r) => !r.release);
  // readResults requires Source to be a file, so each result has one.
  const source = (r) => extLink(`${repo}/blob/${r.release ?? "main"}/${r.source}`, r.source);
  const rows = model.results.map((r) => tr([
    escapeHtml(r.id), escapeHtml(r.release ?? "-"), inline(r.result), escapeHtml(r.value), source(r),
    escapeHtml(r.decisionIds.join(", ") || "-"), escapeHtml(status(r)),
  ], ` data-row data-release="${escapeHtml(r.release ?? "unreleased")}" data-status="${replacedBy.has(r.id) ? "Replaced" : "Current"}"`));
  const relOptions = [...releases.map((t) => ({ value: t, label: t })), ...(hasUnreleased ? [{ value: "unreleased", label: "Not released" }] : [])];
  const content = model.results.length
    ? filterBar([
      { key: "release", label: "Release", options: relOptions },
      { key: "status", label: "Status", options: [{ value: "Current", label: "Current" }, { value: "Replaced", label: "Replaced" }] },
    ], model.results.length)
      + table("All results", ["ID", "Release", "Result", "Value", "Source", "Decisions", "Status"], rows)
    : "<p>No results yet.</p>";
  return shell(model, path, "Results", `<h1>Results</h1>\n${content}`, { scripts: model.results.length ? clientScript() : "" });
}

export function renderProgress(model) {
  const path = "progress/index.html";
  const msRows = model.milestones.map((m) => tr([
    escapeHtml(m.id), escapeHtml(m.title), escapeHtml(m.state),
    m.plan ? recordRef(model, path, m.plan) : "-",
    // Count only for a plan with a ledger (spec Section 9).
    m.tasksTotal === null || m.tasksDone === null ? "-" : `${m.tasksDone} of ${m.tasksTotal}`,
  ]));
  const itemRows = model.openItems.map((o) => tr([o.id, o.item, o.blocks, o.owner].map((s) => escapeHtml(s))));
  const callRows = model.calls.services.map((s) => tr([
    escapeHtml(s.service), String(s.calls), s.maxCalls ? String(s.maxCalls) : "-",
    `${s.costUsd} USD`, s.maxCostUsd ? `${s.maxCostUsd} USD` : "-",
  ]));
  const body = `<h1>Progress</h1>
<h2>Milestones</h2>
${msRows.length ? table("Milestones", ["ID", "Milestone", "State", "Plan", "Tasks complete"], msRows) : "<p>No milestones yet.</p>"}
<h2>Open items</h2>
${itemRows.length ? table("Open items and blockers", ["ID", "Item", "Blocks", "Owner"], itemRows) : "<p>No open items.</p>"}
<h2>Paid calls</h2>
${callRows.length ? table("Paid calls by service", ["Service", "Calls", "Max calls", "Cost", "Max cost"], callRows) : "<p>No paid calls yet.</p>"}`;
  return shell(model, path, "Progress", body);
}

export function renderTimeline(model) {
  const path = "timeline/index.html";
  // Each item: { date, time ("HH:MM[:SS]" or null), order, html }. Dates are UTC.
  const items = [];
  for (const e of model.events) {
    items.push({ date: e.time.slice(0, 10), time: e.time.slice(11).replace("Z", ""), order: 0,
      html: `<strong>${escapeHtml(e.stage)}</strong>, ${escapeHtml(names(model, [e.who]))}: ${escapeHtml(e.what)}` });
  }
  const counts = new Map();
  const idNum = (id) => Number(id.replace(/\D+/g, "")) || 0;
  for (const d of model.decisions) {
    if (isClaudeDecision(d)) counts.set(d.date, (counts.get(d.date) ?? 0) + 1);
    else {
      // With no person among the deciders (for example "unknown"), the item names the deciders.
      const who = d.decidedBy.some(isPerson) ? "" : ` <span class="note">Decided by ${escapeHtml(names(model, d.decidedBy))}.</span>`;
      items.push({ date: d.date, time: d.time, order: idNum(d.id),
        html: `<strong>${escapeHtml(d.id)}</strong>${d.time ? ` ${escapeHtml(d.time)}` : ""}: ${inline(d.text)}${who}` });
    }
  }
  for (const r of model.releases) {
    items.push({ date: r.date, time: r.time, order: 1e9,
      html: `<span class="note">Tag</span> <strong>${escapeHtml(r.tag)}</strong>${r.time ? ` ${escapeHtml(r.time)}` : ""}: ${inline(r.summary)}` });
  }
  const dates = [...new Set([...items.map((i) => i.date), ...counts.keys()])].sort().reverse();
  const stages = STAGES.filter((s) => model.events.some((e) => e.stage === s));
  const head = `<h1>Timeline</h1>
<p class="note">Milestones are not on this page because they have no dates. See <a href="${escapeHtml(rel(path, "progress/index.html"))}">Progress</a>.</p>
`;
  if (!dates.length) return shell(model, path, "Timeline", `${head}<p>No events yet.</p>`);

  let body = head;
  if (stages.length) {
    const ms = (t) => Date.parse(t);
    const first = Math.min(...model.events.map((e) => ms(e.time)));
    const span = Math.max(...model.events.map((e) => ms(e.time))) - first;
    const rows = stages.map((s) => {
      const times = model.events.filter((e) => e.stage === s).map((e) => e.time);
      const stamps = times.map(ms);
      const start = Math.min(...stamps);
      const end = Math.max(...stamps);
      const left = span ? ((start - first) / span) * 100 : 0;
      const width = span ? Math.max(((end - start) / span) * 100, 1) : 100;
      const bar = `<div class="bar-track" aria-hidden="true"><div class="bar" aria-hidden="true" style="left:${pct(Math.min(left, 100 - Math.min(width, 100)))};width:${pct(width)}"></div></div>`;
      return tr([escapeHtml(s), escapeHtml(times.reduce((a, b) => (ms(a) <= ms(b) ? a : b))),
        escapeHtml(times.reduce((a, b) => (ms(a) >= ms(b) ? a : b))), String(times.length), bar]);
    });
    body += `<h2>Stages</h2>
${table("Process stages", ["Stage", "Start", "End", "Events", "Span"], rows)}
`;
  }
  for (const date of dates) {
    const day = items.filter((i) => i.date === date);
    const timed = day.filter((i) => i.time).sort((a, b) => a.time.localeCompare(b.time) || a.order - b.order);
    const untimed = day.filter((i) => !i.time).sort((a, b) => a.order - b.order);
    const lis = [...timed, ...untimed].map((i) => `<li>${i.time ? `<span class="note">${escapeHtml(i.time)}</span> ` : ""}${i.html}</li>`);
    const n = counts.get(date);
    if (n) {
      const label = n === 1 ? "1 decision or ruling by Claude Code" : `${n} decisions and rulings by Claude Code`;
      lis.push(`<li><a href="${escapeHtml(rel(path, "decisions/index.html"))}">${label}</a></li>`);
    }
    body += `<h2>${escapeHtml(date)}</h2>
<ul class="timeline-list">
${lis.join("")}
</ul>
`;
  }
  return shell(model, path, "Timeline", body);
}

export function renderProcess(model) {
  const path = "process/index.html";
  const head = ["Time (UTC)", "Stage", "Who", "What happened", "Records", "Session"];
  const row = (e) => tr([e.time, e.stage, names(model, [e.who]), e.what, e.records, e.session].map((s) => escapeHtml(s)));
  let body = "<h1>Process</h1>\n";
  if (!model.events.length) body += "<p>No events yet.</p>";
  else {
    body += `<h2>By date</h2>\n${table("Events by date", head, model.events.map(row))}\n<h2>By stage</h2>\n`;
    for (const stage of STAGES) {
      const events = model.events.filter((e) => e.stage === stage);
      if (events.length) body += `<h3>${escapeHtml(stage)}</h3>\n${table(`Events in stage ${stage}`, head, events.map(row))}\n`;
    }
  }
  return shell(model, path, "Process", body);
}

// Safe inside a script tag: no "<" survives.
const jsonForScript = (v) => JSON.stringify(v).replace(/</g, "\\u003c");

export function renderDocument(model, doc) {
  const path = docPath(doc.path);
  const pages = Object.fromEntries(model.documents.map((d) => [d.path, rel(path, docPath(d.path))]));
  const repo = model.config.repository.replace(/\/$/, "");
  const ctx = {
    folder: doc.path.includes("/") ? doc.path.slice(0, doc.path.lastIndexOf("/")) : "",
    pages,
    blobBase: `${repo}/blob/main/replication_materials/`,
    // Images load the raw file (Ruling 17). loadProject accepts only https://github.com/<owner>/<repo>.
    rawBase: `${repo.replace(/^https:\/\/github\.com\//, "https://raw.githubusercontent.com/")}/main/replication_materials/`,
  };
  const sri = (c) => `src="${c.src}" integrity="${c.integrity}" crossorigin="anonymous"`;
  const head = `<link rel="stylesheet" href="${CDN.katexCss.src}" integrity="${CDN.katexCss.integrity}" crossorigin="anonymous">`;
  const scripts = `<script type="application/json" id="doc-md">${jsonForScript(doc.text)}</script>
<script type="application/json" id="doc-ctx">${jsonForScript(ctx)}</script>
<script ${sri(CDN.marked)}></script>
<script ${sri(CDN.dompurify)}></script>
<script ${sri(CDN.katex)}></script>
<script ${sri(CDN.katexAutoRender)}></script>
${clientScript()}`;
  const body = `<h1>${escapeHtml(doc.title)}</h1>
<p class="note">${escapeHtml(doc.path)}${doc.status ? ` · Status: ${escapeHtml(doc.status)}` : ""}</p>
<div class="doc-layout">
<div id="doc-content">
<pre id="doc-fallback" tabindex="0">${escapeHtml(doc.text)}</pre>
</div>
</div>`;
  return shell(model, path, doc.title, body, { head, scripts });
}

export function renderSite(model) {
  const site = new Map([
    ["index.html", renderHome(model)],
    ["records/index.html", renderRecords(model)],
    ["decisions/index.html", renderDecisions(model)],
    ["contributions/index.html", renderContributions(model)],
    ["timeline/index.html", renderTimeline(model)],
    ["progress/index.html", renderProgress(model)],
    ["process/index.html", renderProcess(model)],
  ]);
  // A missing file means no page. A file with no rows gives a page with an empty state.
  if (model.recordFiles?.releases) site.set("releases/index.html", renderReleases(model));
  if (model.recordFiles?.results) site.set("results/index.html", renderResults(model));
  for (const doc of model.documents) site.set(docPath(doc.path), renderDocument(model, doc));
  return site;
}
