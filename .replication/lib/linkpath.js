// Where a relative link in a rendered record document should point.
// ctx: { folder, pages, blobBase }. Returns the new href, or null to leave the link alone.
// "..": URL rules apply, so a link can leave the record folder and reach the repository.
function resolveLink(ctx, href) {
  if (/^([a-z][a-z0-9+.-]*:|\/|#)/i.test(href)) return null;
  var base = new URL(ctx.blobBase);
  var url = new URL(ctx.folder ? ctx.folder + "/" + href : href, base);
  if (url.pathname.indexOf(base.pathname) === 0) {
    var path = decodeURIComponent(url.pathname.slice(base.pathname.length));
    if (Object.prototype.hasOwnProperty.call(ctx.pages, path)) return ctx.pages[path] + url.hash;
  }
  return url.href;
}

// Where a relative image in a rendered record document loads from: the raw file in the
// repository (ctx.rawBase, Ruling 17). Returns null to leave the image alone.
function resolveImage(ctx, src) {
  return resolveLink({ folder: ctx.folder, pages: {}, blobBase: ctx.rawBase }, src);
}

// Math spans ($$...$$ and $...$) outside code, replaced by placeholders so that marked cannot
// change them before KaTeX reads them (Ruling 16). Returns { text, spans, key }.
// Inline math stays on one line; display math stops at a blank line. In a table row, math
// never crosses a cell, and "\|" is a pipe, as GFM reads it.
function shieldMath(md) {
  var key = "mathspan";
  while (md.indexOf(key) !== -1) key += "x";
  var spans = [];
  var out = [];
  var chunk = [];
  var fence = null;
  var flush = function () {
    if (chunk.length) out.push(shieldText(chunk.join("\n"), key, spans));
    chunk = [];
  };
  md.split("\n").forEach(function (line) {
    var f = line.match(/^\s*(`{3,}|~{3,})(.*)$/);
    if (fence) {
      out.push(line);
      if (f && f[1][0] === fence[0] && f[1].length >= fence.length && f[2].trim() === "") fence = null;
      return;
    }
    if (f && !(f[1][0] === "`" && f[2].indexOf("`") !== -1)) {
      flush();
      fence = f[1];
      out.push(line);
      return;
    }
    chunk.push(line);
  });
  flush();
  return { text: out.join("\n"), spans: spans, key: key };
}

function restoreMath(text, shield) {
  return text.replace(new RegExp(shield.key + "(\\d+)" + shield.key, "g"), function (m, n) {
    return shield.spans[Number(n)];
  });
}

function isTableRow(s, i) {
  return /^[ \t]*\|/.test(s.slice(s.lastIndexOf("\n", i - 1) + 1));
}

function shieldText(s, key, spans) {
  var r = "";
  var i = 0;
  while (i < s.length) {
    var c = s.charAt(i);
    if (c === "\\") {
      r += s.substr(i, 2);
      i += 2;
    } else if (c === "`") {
      var run = /^`+/.exec(s.slice(i))[0];
      var close = codeEnd(s, i + run.length, run.length);
      var stop = close === -1 ? i + run.length : close + run.length;
      r += s.slice(i, stop);
      i = stop;
    } else if (c === "$") {
      var open = s.charAt(i + 1) === "$" ? 2 : 1;
      var end = mathEnd(s, i + open, open === 2, isTableRow(s, i));
      if (end === -1) {
        r += s.slice(i, i + open);
        i += open;
      } else {
        var source = s.slice(i, end + open);
        spans.push(isTableRow(s, i) ? source.replace(/\\\|/g, "|") : source);
        r += key + (spans.length - 1) + key;
        i = end + open;
      }
    } else {
      r += c;
      i += 1;
    }
  }
  return r;
}

// The start of the closing backtick run of length n, before the next blank line, or -1.
function codeEnd(s, from, n) {
  var blank = s.slice(from).search(/\n[ \t]*\n/);
  var limit = blank === -1 ? s.length : from + blank;
  var re = /`+/g;
  re.lastIndex = from;
  var m;
  while ((m = re.exec(s)) && m.index < limit) if (m[0].length === n) return m.index;
  return -1;
}

// The start of the closing delimiter, as KaTeX auto-render finds it (braces, "\" escapes), or -1.
function mathEnd(s, from, display, row) {
  var delim = display ? "$$" : "$";
  var depth = 0;
  for (var k = from; k < s.length; k++) {
    var ch = s.charAt(k);
    if (depth <= 0 && s.substr(k, delim.length) === delim) return k;
    if (ch === "\n" && (!display || row || /^\n[ \t]*(\n|$)/.test(s.slice(k)))) return -1;
    if (row && ch === "|") return -1;
    if (ch === "\\" && s.charAt(k + 1) !== "\n") k += 1;
    else if (ch === "{") depth += 1;
    else if (ch === "}") depth -= 1;
  }
  return -1;
}
