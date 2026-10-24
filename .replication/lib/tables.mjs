// Markdown table and metadata parser for record files.

export class RecordFormatError extends Error {
  constructor(file, line, detail) {
    super(`${file}:${line}: ${detail}`);
    this.name = "RecordFormatError";
    this.file = file;
    this.line = line;
  }
}

const SEPARATOR = /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/;

function splitRow(line) {
  const cells = [];
  let cur = "";
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === "\\" && line[i + 1] === "|") {
      cur += "|";
      i++;
    } else if (ch === "|") {
      cells.push(cur);
      cur = "";
    } else {
      cur += ch;
    }
  }
  cells.push(cur);
  if (cells[0].trim() === "") cells.shift();
  if (cells.length && cells[cells.length - 1].trim() === "") cells.pop();
  return cells.map((c) => c.trim());
}

const isRow = (l) => l !== undefined && l.trim().startsWith("|");

// For each line, true when it is a code-fence line or lies inside a code fence.
export function fenceFlags(lines) {
  let fence = null;
  return lines.map((line) => {
    const f = line.match(/^\s*(```+|~~~+)/);
    if (fence) {
      if (f && f[1][0] === fence[0] && f[1].length >= fence.length) fence = null;
      return true;
    }
    if (f) {
      fence = f[1];
      return true;
    }
    return false;
  });
}

// With { lenient: true } a row with the wrong number of cells is skipped instead of thrown.
export function parseTables(text, file, { lenient = false } = {}) {
  const lines = text.split(/\r?\n/);
  const tables = [];
  const inFence = fenceFlags(lines);
  let heading = null;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (inFence[i]) continue;
    const h = line.match(/^#{1,6}\s+(.*?)\s*#*\s*$/);
    if (h) {
      heading = h[1];
      continue;
    }
    if (isRow(line) && isRow(lines[i + 1]) && SEPARATOR.test(lines[i + 1])) {
      const columns = splitRow(line);
      const table = { heading, line: i + 1, columns, rows: [] };
      i += 2;
      for (; i < lines.length && isRow(lines[i]); i++) {
        const cells = splitRow(lines[i]);
        if (cells.length !== columns.length) {
          if (lenient) continue;
          throw new RecordFormatError(
            file, i + 1,
            `row has ${cells.length} cells but the header has ${columns.length} (${columns.join(", ")}).`);
        }
        table.rows.push({ line: i + 1, cells: Object.fromEntries(columns.map((c, k) => [c, cells[k]])) });
      }
      i--;
      tables.push(table);
    }
  }
  return tables;
}

export function findTable(tables, heading, columns, file) {
  const table = heading === null ? tables[0] : tables.find((t) => t.heading === heading);
  if (!table) {
    const what = heading === null ? "a table" : `table "${heading}"`;
    throw new RecordFormatError(file, 1, `${what} not found. Expected columns: ${columns.join(", ")}.`);
  }
  const missing = columns.filter((c) => !table.columns.includes(c));
  if (missing.length) {
    throw new RecordFormatError(
      file, table.line,
      `table "${table.heading}" lacks column(s) ${missing.join(", ")}. Expected columns: ${columns.join(", ")}.`);
  }
  return table;
}

// Reads the title and the first Item/Value table. A document is prose, so a sloppy
// table elsewhere in it must not stop the build: parsing here is lenient.
export function readMeta(text, file) {
  const m = text.match(/^# (.*?)\s*$/m);
  const title = m ? m[1] : null;
  const t = parseTables(text, file, { lenient: true }).find(
    (x) => x.columns.length === 2 && x.columns[0] === "Item" && x.columns[1] === "Value");
  const meta = {};
  if (t) for (const r of t.rows) meta[r.cells.Item] = r.cells.Value;
  return { title, meta };
}
