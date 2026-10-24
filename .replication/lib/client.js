(function () {
  "use strict";

  // Filters: one active value per key; "" means all.
  var bar = document.querySelector("[data-filters]");
  if (bar) {
    var rows = Array.prototype.slice.call(document.querySelectorAll("[data-row]"));
    var count = document.querySelector("[data-filter-count]");
    var active = {};
    var apply = function () {
      var shown = 0;
      rows.forEach(function (row) {
        var ok = Object.keys(active).every(function (key) {
          if (!active[key]) return true;
          var have = (row.getAttribute("data-" + key) || "").split(/\s+/);
          return have.indexOf(active[key]) !== -1;
        });
        row.hidden = !ok;
        if (ok) shown += 1;
      });
      if (count) count.textContent = "Showing " + shown + " of " + rows.length + ".";
    };
    var buttons = Array.prototype.slice.call(bar.querySelectorAll("button[data-filter-key]"));
    buttons.forEach(function (b) {
      b.addEventListener("click", function () {
        var key = b.getAttribute("data-filter-key");
        var value = b.getAttribute("data-filter-value");
        active[key] = active[key] === value ? "" : value;
        buttons.forEach(function (o) {
          if (o.getAttribute("data-filter-key") !== key) return;
          var on = o.getAttribute("data-filter-value") === (active[key] || "");
          o.setAttribute("aria-pressed", on ? "true" : "false");
        });
        apply();
      });
    });
    bar.hidden = false;
  }

  // Document pages: render the markdown. The fallback text stays when a library is missing.
  var mdEl = document.getElementById("doc-md");
  var target = document.getElementById("doc-content");
  if (mdEl && target && typeof marked !== "undefined" && typeof DOMPurify !== "undefined") {
    var ctx = JSON.parse(document.getElementById("doc-ctx").textContent);
    var md = JSON.parse(mdEl.textContent);
    var fallback = document.getElementById("doc-fallback");
    var holder = document.createElement("div");
    // marked must not see the math: it would drop "\{", read "*" as emphasis and "\\" as an escape.
    var shield = shieldMath(md);
    holder.innerHTML = DOMPurify.sanitize(marked.parse(shield.text));
    var walker = document.createTreeWalker(holder, NodeFilter.SHOW_TEXT);
    for (var node = walker.nextNode(); node; node = walker.nextNode()) {
      if (node.nodeValue.indexOf(shield.key) !== -1) node.nodeValue = restoreMath(node.nodeValue, shield);
    }

    // marked writes a GFM task item as a bare disabled checkbox. Give each one a name (1.3.1, 4.1.2).
    Array.prototype.forEach.call(holder.querySelectorAll('input[type="checkbox"]'), function (box) {
      if (!box.hasAttribute("aria-label")) box.setAttribute("aria-label", box.checked ? "Done" : "Not done");
    });

    if (typeof renderMathInElement === "function") {
      renderMathInElement(holder, {
        delimiters: [
          { left: "$$", right: "$$", display: true },
          { left: "$", right: "$", display: false },
        ],
        throwOnError: false,
      });
    }

    // The page already has one h1 (the title). Drop a repeat of it and demote any other h1.
    var pageTitle = document.querySelector("h1");
    Array.prototype.forEach.call(holder.querySelectorAll("h1"), function (h, i) {
      if (i === 0 && pageTitle && h.textContent.trim() === pageTitle.textContent.trim()) { h.remove(); return; }
      var h2 = document.createElement("h2");
      h2.innerHTML = h.innerHTML;
      h.parentNode.replaceChild(h2, h);
    });

    Array.prototype.forEach.call(holder.querySelectorAll("a[href]"), function (a) {
      var target = resolveLink(ctx, a.getAttribute("href"));
      if (target !== null) a.setAttribute("href", target);
    });
    Array.prototype.forEach.call(holder.querySelectorAll("img[src]"), function (img) {
      var src = resolveImage(ctx, img.getAttribute("src"));
      if (src !== null) img.setAttribute("src", src);
    });

    // Each table gets a focusable, distinctly labelled region and column scopes.
    var heading = "";
    var tableNo = 0;
    var used = {};
    Array.prototype.slice.call(holder.querySelectorAll("h1,h2,h3,h4,h5,h6,table")).forEach(function (el) {
      if (el.tagName !== "TABLE") { heading = el.textContent.trim(); return; }
      tableNo += 1;
      var label = heading ? heading + " table" : "Table " + tableNo;
      if (used[label]) label = label + " " + tableNo;
      used[label] = true;
      var wrap = document.createElement("div");
      wrap.className = "table-wrap";
      wrap.tabIndex = 0;
      wrap.setAttribute("role", "region");
      wrap.setAttribute("aria-label", label);
      el.parentNode.insertBefore(wrap, el);
      wrap.appendChild(el);
      Array.prototype.forEach.call(el.querySelectorAll("thead th"), function (th) {
        th.setAttribute("scope", "col");
      });
    });
    Array.prototype.forEach.call(holder.querySelectorAll("pre"), function (p) {
      p.tabIndex = 0;
    });

    if (fallback) fallback.remove();
    target.appendChild(holder);

    // Contents rail from the h2 headings, when there are any.
    var heads = holder.querySelectorAll("h2");
    if (heads.length) {
      var rail = document.createElement("nav");
      var list = document.createElement("ul");
      var taken = {};
      rail.className = "doc-rail";
      rail.setAttribute("aria-label", "Contents");
      Array.prototype.forEach.call(heads, function (h, i) {
        if (!h.id) {
          var slug = h.textContent.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "section";
          if (taken[slug] || document.getElementById(slug)) slug = slug + "-" + (i + 1);
          h.id = slug;
        }
        taken[h.id] = true;
        var li = document.createElement("li");
        var a = document.createElement("a");
        a.href = "#" + h.id;
        a.textContent = h.textContent;
        li.appendChild(a);
        list.appendChild(li);
      });
      rail.appendChild(list);
      target.parentNode.insertBefore(rail, target);
      target.parentNode.classList.add("has-rail");
    }
  }
})();
