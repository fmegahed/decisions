// Miami theme, HTML escaping and the shared page shell.
import { posix } from "node:path";

export const VERSION = "1.3.1";

export const DEFAULT_TOKENS = {
  bg: "#FAF9F7",
  surface: "#FFFFFF",
  tan: "#EDECE2",
  ink: "#000000",
  muted: "#666666",
  rule: "#CCC9B8",
  accent: "#C41230",
  "accent-strong": "#AD102A",
  "on-accent": "#FFFFFF",
};

const CDNJS = "https://cdnjs.cloudflare.com/ajax/libs";
export const CDN = {
  marked: {
    src: `${CDNJS}/marked/12.0.2/marked.min.js`,
    integrity: "sha512-xeUh+KxNyTufZOje++oQHstlMQ8/rpyzPuM+gjMFYK3z5ILJGE7l2NvYL+XfliKURMpBIKKp1XoPN/qswlSMFA==",
  },
  dompurify: {
    src: `${CDNJS}/dompurify/3.4.16/purify.min.js`,
    integrity: "sha512-flQmhkXNRQ3iUfvtdCobtpMjCb6kE+zLnTiAulAQJ3WykVfy84JvCMOo6vhwWXHTXjR25h9Zj+LyGFRWKjRoag==",
  },
  katex: {
    src: `${CDNJS}/KaTeX/0.16.9/katex.min.js`,
    integrity: "sha512-LQNxIMR5rXv7o+b1l8+N1EZMfhG7iFZ9HhnbJkTp4zjNr5Wvst75AqUeFDxeRUa7l5vEDyUiAip//r+EFLLCyA==",
  },
  katexAutoRender: {
    src: `${CDNJS}/KaTeX/0.16.9/contrib/auto-render.min.js`,
    integrity: "sha512-iWiuBS5nt6r60fCz26Nd0Zqe0nbk1ZTIQbl3Kv7kYsX+yKMUFHzjaH2+AnM6vp2Xs+gNmaBAVWJjSmuPw76Efg==",
  },
  katexCss: {
    src: `${CDNJS}/KaTeX/0.16.9/katex.min.css`,
    integrity: "sha512-fHwaWebuwA7NSF5Qg/af4UeDx9XqUpYpOGgubo3yWu+b2IQR4UeQwbb42Ti7gVAjNtVoI/I9TEoYeu9omwcC6g==",
  },
};

export function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// Escape first, then add <code> and http(s) links. Other link targets stay text.
export function inline(s) {
  return escapeHtml(s)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2">$1</a>');
}

// Relative link between two site paths such as "decisions/index.html".
export function rel(from, to) {
  const r = posix.relative(posix.dirname(from), to);
  return r === "" ? posix.basename(to) : r;
}

export function themeCss(tokens) {
  const vars = Object.entries(tokens).map(([k, v]) => `  --${k}: ${v};`).join("\n");
  return `:root {
  color-scheme: light;
${vars}
  --serif: "Source Serif 4", Georgia, "Times New Roman", serif;
  --sans: Arial, "Helvetica Neue", Helvetica, sans-serif;
  --mono: ui-monospace, Consolas, monospace;
}
*, *::before, *::after { box-sizing: border-box; }
html { scroll-padding-top: 5rem; }
@media (prefers-reduced-motion: no-preference) { html { scroll-behavior: smooth; } }
body { margin: 0; background: var(--bg); color: var(--ink); font: 1rem/1.6 var(--sans); overflow-wrap: break-word; }
h1, h2, h3, h4 { font-family: var(--serif); line-height: 1.25; }
a { color: var(--accent-strong); }
a:hover { color: var(--accent); }
:focus-visible { outline: 3px solid var(--accent); outline-offset: 3px; }
code, pre { font-family: var(--mono); font-size: 0.9em; }
code { background: var(--tan); padding: 0 0.25em; }
pre { background: var(--tan); padding: 1rem; overflow-x: auto; }
pre code { background: none; padding: 0; }
.skip-link { position: absolute; left: 16px; top: -4rem; background: var(--surface); color: var(--ink); padding: 0.5rem 1rem; z-index: 20; }
.skip-link:focus { top: 8px; }
.site-header { background: var(--accent); color: var(--on-accent); }
.site-header .inner { max-width: 76rem; margin: 0 auto; padding: 0.75rem 16px; }
.site-title { margin: 0; font: 700 1.25rem/1.3 var(--serif); }
.site-title a { color: var(--on-accent); text-decoration: none; }
.site-nav { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 0.5rem 1.5rem; margin-top: 0.5rem; }
.site-nav ul { list-style: none; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 0.25rem 0.4rem; }
.nav-label { margin: 0 0 0 0.4rem; font-size: 0.8rem; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; }
.site-nav a, button, .button { display: inline-flex; align-items: center; min-height: 24px; min-width: 24px; padding: 0.25rem 0.5rem; }
.site-nav a { color: var(--on-accent); padding: 0.25rem 0.4rem; }
.site-nav a[aria-current="page"] { font-weight: 700; text-decoration: underline; text-underline-offset: 0.25em; text-decoration-thickness: 3px; }
.site-header :focus-visible { outline-color: var(--on-accent); }
.nav-line { flex: 1 0 100%; margin: 0; padding: 0.25rem 0.4rem; background: var(--accent-strong); color: var(--on-accent); font-size: 0.9rem; line-height: 1.5; text-align: left; }
button, .button { background: var(--tan); color: var(--ink); border: 2px solid var(--ink); font: inherit; cursor: pointer; }
button:hover, .button:hover { background: var(--surface); }
button[aria-pressed="true"] { background: var(--accent-strong); color: var(--on-accent); border-color: var(--accent-strong); }
main { max-width: 76rem; margin: 0 auto; padding: 1.5rem 16px 3rem; }
.site-footer { background: var(--tan); border-top: 1px solid var(--rule); }
.site-footer .inner { max-width: 76rem; margin: 0 auto; padding: 1rem 16px; color: var(--muted); }
.table-wrap { overflow-x: auto; max-width: 100%; }
table { border-collapse: collapse; width: 100%; background: var(--surface); }
th, td { border: 1px solid var(--rule); padding: 0.5rem 0.75rem; text-align: left; vertical-align: top; }
th { background: var(--tan); }
.doc-rail { margin: 0 0 1.5rem; padding: 0.5rem 1rem; background: var(--surface); border: 1px solid var(--rule); }
.doc-rail::before { content: "Contents"; display: block; font: 700 1rem var(--serif); }
.doc-rail ul { list-style: none; margin: 0.25rem 0 0; padding: 0; }
.doc-rail a { display: flex; align-items: center; min-height: 24px; padding: 0.125rem 0; }
img, svg { max-width: 100%; height: auto; }
@media (min-width: 900px) {
  .site-header { position: sticky; top: 0; z-index: 10; }
  html { scroll-padding-top: 11rem; }
  .nav-reuse { margin-left: auto; text-align: right; }
  .nav-reuse .nav-label { margin: 0 0.4rem 0 0; }
  .nav-reuse ul { justify-content: flex-end; }
  .nav-line[data-side="reuse"] { text-align: right; }
  .doc-layout.has-rail { display: grid; grid-template-columns: 15rem minmax(0, 1fr); gap: 2rem; align-items: start; }
  .doc-layout.has-rail .doc-rail { grid-column: 1; grid-row: 1; position: sticky; top: 11rem; margin: 0; }
  .doc-layout.has-rail #doc-content { grid-column: 2; grid-row: 1; }
}
`;
}

// The navigation has two groups, one for each kind of reader, and each group
// is in reading order. "record": how the work was done with Claude Code, in
// the order of the work (the stages, their dates and the milestones, then
// who decided what and the account of who did what, then the documents and
// the results). "reuse": what a reader needs to rerun the work and build on
// it (the documents of the extra pages, then the versions, then the code).
// Each item: label, target, description (the tooltip of the link and the text
// after the link on Home), and an optional test: the page shows only when it
// returns true.
export const NAV_GROUPS = [
  { group: "record", id: "nav-record", label: "Record" },
  { group: "reuse", id: "nav-reuse", label: "Reuse" },
];
const RECORD_NAV = [
  ["Home", "index.html", "The status of the project: the latest release, the open items and the milestones."],
  ["Process", "process/index.html", "The stages of the work, from the inputs to the paper, with their dates."],
  ["Timeline", "timeline/index.html", "The work by date: the stages, the releases and the decisions."],
  ["Progress", "progress/index.html", "The milestones, the tasks that are complete and the paid calls."],
  ["Decisions", "decisions/index.html", "Each decision: who proposed it, who decided it, and how."],
  ["Contributions", "contributions/index.html", "The account of the researchers: who did what, and what no person checked."],
  ["Records", "records/index.html", "The plans, designs, ledgers and reviews of the work."],
  ["Results", "results/index.html", "Each result with its release, its source file and its status.", (m) => m.recordFiles?.results],
];
const RELEASES_NAV = [["Releases", "releases/index.html", "Each tagged version of the code, with its changes and its decisions.",
  (m) => m.recordFiles?.releases]];
export const REPOSITORY_DESCRIPTION = "The code and all files of the project on GitHub.";

// The [label, target, description] items of each group that show for this
// record. The extra pages of site.config.json go at the end of the record
// group, or first in the reuse group (their default); an extra page without a
// description has none. The repository link is not here.
export function navGroups(model) {
  const show = (items) => items.filter(([, , , s]) => !s || s(model))
    .map(([label, target, description]) => [label, target, description]);
  const extra = (group) => (model.config.pages ?? [])
    .filter((p) => (p.group ?? "reuse") === group).map((p) => [p.title, p.path, p.description]);
  return {
    record: [...show(RECORD_NAV), ...extra("record")],
    reuse: [...extra("reuse"), ...show(RELEASES_NAV)],
  };
}

// The description line shows the description of the link under the pointer
// or with the keyboard focus. It keeps that text while the pointer is
// anywhere in the navigation, the line too (WCAG 1.4.13), and shows the
// default (the current page) again when the pointer or the focus leaves.
const NAV_LINE_SCRIPT = `<script>
(() => {
  const nav = document.querySelector(".site-nav");
  const line = nav && nav.querySelector(".nav-line");
  if (!line) return;
  const show = (a) => {
    line.textContent = a.dataset.line;
    line.dataset.side = a.closest(".nav-reuse") ? "reuse" : "record";
  };
  const reset = () => {
    line.textContent = line.dataset.default;
    line.dataset.side = line.dataset.defaultSide;
  };
  nav.querySelectorAll("a[data-line]").forEach((a) => {
    a.addEventListener("mouseenter", () => show(a));
    a.addEventListener("focus", () => show(a));
  });
  nav.addEventListener("mouseleave", reset);
  nav.addEventListener("focusout", (e) => { if (!nav.contains(e.relatedTarget)) reset(); });
})();
</script>`;
const LINE_HINT = "Point to a tab, or move the keyboard focus to it, to read what it holds.";

export function pageShell({ path, title, body, model, head = "", scripts = "" }) {
  const project = model.config.project;
  const repo = model.config.repository;
  const tokens = { ...DEFAULT_TOKENS, ...(model.config.theme || {}) };
  const groups = navGroups(model);
  // A link with a description: aria-describedby gives the text to screen
  // readers (from a hidden span); data-line is the text of the description
  // line, which screen readers do not read twice (aria-hidden).
  let n = 0;
  let current = { line: LINE_HINT, side: "record" };
  const link = ([label, href, description], group, here = false) => {
    const a = `<a href="${escapeHtml(href)}"`;
    const mark = here ? ' aria-current="page"' : "";
    if (!description) return `<li>${a}${mark}>${escapeHtml(label)}</a></li>`;
    const id = `nav-desc-${++n}`;
    const line = `${label}: ${description}`;
    if (here) current = { line, side: group };
    return `<li>${a} aria-describedby="${id}" data-line="${escapeHtml(line)}"${mark}>${escapeHtml(label)}</a>`
      + `<span class="nav-desc" id="${id}" hidden>${escapeHtml(description)}</span></li>`;
  };
  const nav = NAV_GROUPS.map(({ group, id, label }) => {
    const items = groups[group].map(([text, target, description]) =>
      link([text, rel(path, target), description], group, target === path));
    if (group === "reuse") items.push(link(["Repository", repo, REPOSITORY_DESCRIPTION], group));
    return `<div class="nav-group ${id}">
<p class="nav-label" id="${id}">${escapeHtml(label)}</p>
<ul aria-labelledby="${id}">
${items.join("\n")}
</ul>
</div>`;
  });
  nav.push(`<p class="nav-line" aria-hidden="true" data-default="${escapeHtml(current.line)}" `
    + `data-default-side="${current.side}" data-side="${current.side}">${escapeHtml(current.line)}</p>`);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="replication-materials ${VERSION}">
<title>${escapeHtml(title)} · ${escapeHtml(project)}</title>
<style>
${themeCss(tokens)}</style>
${head}
</head>
<body>
<a class="skip-link" href="#main">Skip to main content</a>
<header class="site-header">
<div class="inner">
<p class="site-title"><a href="${escapeHtml(rel(path, "index.html"))}">${escapeHtml(project)}</a></p>
<nav class="site-nav" aria-label="Site">
${nav.join("\n")}
</nav>
</div>
</header>
<main id="main">
${body}
</main>
<footer class="site-footer">
<div class="inner">
<p>Built from commit ${escapeHtml(model.build.sha)} on ${escapeHtml(model.build.date)}. <a href="${escapeHtml(repo)}">Repository</a></p>
</div>
</footer>
${NAV_LINE_SCRIPT}
${scripts}
</body>
</html>
`;
}
