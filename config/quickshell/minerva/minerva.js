// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

.pragma library
// ONE COPY FOR THE WHOLE SHELL (see morpheus/icons.js).
//
// MINERVA'S PURE HALF: the library (what you have opened, where you were in
// it, your bookmarks and highlights), how far through a book you are, the
// words for a place in one, and the reading settings — so the window only
// draws, and oracle/tests/minerva.js checks the rest.
//
//   a book: { path, kind: "pdf"|"epub", title, author, cover, opened,
//             pos, progress, bookmarks: [mark], highlights: [mark] }
//   a place (pos, mark.where): { page } for a PDF (0-based), or
//             { chapter, frac } for an EPUB (frac 0…1 down the chapter)
//   a mark:   { id, where, text, at, note } — note: the clio note a
//             highlight went into ("" until it has)

var KINDS = { pdf: "PDF", epub: "EPUB" };

function kindOf(path) {
  var m = /\.([A-Za-z0-9]+)$/.exec(String(path || ""));
  var ext = m ? m[1].toLowerCase() : "";
  return ext === "pdf" ? "pdf" : ext === "epub" ? "epub" : "";
}
function nameOf(path) {
  return String(path || "").replace(/.*\//, "").replace(/\.(pdf|epub)$/i, "");
}

// ── SETTINGS ─────────────────────────────────────────────────────────────
// fontSize, lineHeight and width are an EPUB's (a PDF is set as printed);
// zoom is a PDF's default ("width": fit the page's width)
function defaults() {
  return { fontSize: 19, lineHeight: 1.6, width: 720, serif: true, sidebar: true, zoom: "width" };
}
function cleanSettings(s) {
  var d = defaults();
  if (!s || typeof s !== "object") return d;
  if (typeof s.fontSize === "number") d.fontSize = Math.max(12, Math.min(40, Math.round(s.fontSize)));
  if (typeof s.lineHeight === "number") d.lineHeight = Math.max(1.1, Math.min(2.4, Math.round(s.lineHeight * 10) / 10));
  if (typeof s.width === "number") d.width = Math.max(420, Math.min(1400, Math.round(s.width / 20) * 20));
  if (typeof s.serif === "boolean") d.serif = s.serif;
  if (typeof s.sidebar === "boolean") d.sidebar = s.sidebar;
  if (s.zoom === "width" || s.zoom === "page" || typeof s.zoom === "number")
    d.zoom = typeof s.zoom === "number" ? Math.max(0.25, Math.min(6, s.zoom)) : s.zoom;
  return d;
}

// ── THE LIBRARY ──────────────────────────────────────────────────────────
var MAX_BOOKS = 200;

function cleanPos(kind, p) {
  if (!p || typeof p !== "object") return kind === "pdf" ? { page: 0 } : { chapter: 0, frac: 0 };
  if (kind === "pdf") return { page: Math.max(0, Math.floor(Number(p.page) || 0)) };
  return { chapter: Math.max(0, Math.floor(Number(p.chapter) || 0)),
           frac: Math.max(0, Math.min(1, Number(p.frac) || 0)) };
}
function cleanMark(kind, m) {
  if (!m || typeof m !== "object" || !m.where) return null;
  return { id: String(m.id || newId()), where: cleanPos(kind, m.where), text: String(m.text || ""),
           at: Number(m.at) || 0, note: String(m.note || "") };
}
function cleanBook(b) {
  if (!b || typeof b !== "object" || !b.path) return null;
  var kind = b.kind === "pdf" || b.kind === "epub" ? b.kind : kindOf(b.path);
  if (!kind) return null;
  var marks = function (list) {
    return (Array.isArray(list) ? list : []).map(function (m) { return cleanMark(kind, m); })
      .filter(function (m) { return m; });
  };
  return {
    path: String(b.path), kind: kind,
    title: String(b.title || "") || nameOf(b.path), author: String(b.author || ""),
    cover: String(b.cover || ""), opened: Number(b.opened) || 0,
    pos: cleanPos(kind, b.pos), progress: Math.max(0, Math.min(1, Number(b.progress) || 0)),
    bookmarks: marks(b.bookmarks), highlights: marks(b.highlights)
  };
}
function parseLibrary(text) {
  var j;
  try { j = JSON.parse(String(text || "")); } catch (e) { j = null; }
  var out = { books: [], settings: defaults() };
  if (!j || typeof j !== "object") return out;
  out.settings = cleanSettings(j.settings);
  var seen = {};
  (Array.isArray(j.books) ? j.books : []).forEach(function (b) {
    var c = cleanBook(b);
    if (c && !seen[c.path]) { seen[c.path] = true; out.books.push(c); }
  });
  return out;
}
function serializeLibrary(lib) {
  return JSON.stringify({ settings: cleanSettings(lib.settings), books: (lib.books || []).slice(0, MAX_BOOKS) }, null, 1) + "\n";
}
function bookOf(books, path) {
  for (var i = 0; i < (books || []).length; ++i) if (books[i].path === path) return books[i];
  return null;
}
// a book opened, or changed: first in the list, the fields laid over it
function upsert(books, path, fields) {
  var old = bookOf(books, path) || cleanBook({ path: path });
  if (!old) return books || [];
  var merged = cleanBook(Object.assign({}, old, fields || {}));
  return [merged].concat((books || []).filter(function (b) { return b.path !== path; })).slice(0, MAX_BOOKS);
}
// changed where it stands (a bookmark, a place): not moved to the front
function update(books, path, fields) {
  return (books || []).map(function (b) { return b.path === path ? cleanBook(Object.assign({}, b, fields)) : b; });
}
function remove(books, path) { return (books || []).filter(function (b) { return b.path !== path; }); }

var _n = 0;
function newId() { _n = (_n + 1) % 1296; return Date.now().toString(36) + _n.toString(36); }

function addMark(list, where, text, at) {
  return (list || []).concat([{ id: newId(), where: where, text: String(text || ""), at: at || Date.now(), note: "" }]);
}
function setMark(list, id, fields) {
  return (list || []).map(function (m) { return m.id === id ? Object.assign({}, m, fields) : m; });
}
function dropMark(list, id) { return (list || []).filter(function (m) { return m.id !== id; }); }
// a bookmark already standing here? (a page; or a chapter within 2%)
function markHere(list, where) {
  for (var i = 0; i < (list || []).length; ++i) {
    var w = list[i].where;
    if (where.page !== undefined ? w.page === where.page
        : w.chapter === where.chapter && Math.abs((w.frac || 0) - (where.frac || 0)) < 0.02) return list[i];
  }
  return null;
}
// in reading order
function sortMarks(list) {
  return (list || []).slice().sort(function (a, b) {
    var wa = a.where, wb = b.where;
    if (wa.page !== undefined) return wa.page - wb.page || a.at - b.at;
    return wa.chapter - wb.chapter || wa.frac - wb.frac || a.at - b.at;
  });
}

// ── HOW FAR ──────────────────────────────────────────────────────────────
// an EPUB's chapters weighed by their words, so a short preface does not
// count as much as the longest chapter
function epubProgress(chapters, chapter, frac) {
  var total = 0, before = 0;
  (chapters || []).forEach(function (c, i) {
    var w = Math.max(1, Number(c.words) || 1);
    total += w;
    if (i < chapter) before += w;
  });
  if (total <= 0) return 0;
  var here = chapters && chapters[chapter] ? Math.max(1, Number(chapters[chapter].words) || 1) : 0;
  return Math.max(0, Math.min(1, (before + here * (Number(frac) || 0)) / total));
}
function pdfProgress(page, count) {
  return count > 1 ? Math.max(0, Math.min(1, page / (count - 1))) : 1;
}
function percentWords(p) { return Math.round((Number(p) || 0) * 100) + "%"; }

// "Page 12" / "Chapter 3 · 40%" — a place, said
function whereWords(kind, where, chapters) {
  if (!where) return "";
  if (kind === "pdf") return "Page " + ((where.page || 0) + 1);
  var c = chapters && chapters[where.chapter];
  var name = c && c.title ? c.title : "Chapter " + ((where.chapter || 0) + 1);
  return name + " · " + Math.round((where.frac || 0) * 100) + "%";
}

// "2 hours ago"-free: a date the way the library shows when you last read
function openedWords(ms, now) {
  if (!ms) return "";
  var d = Math.floor(((now || Date.now()) - ms) / 86400000);
  if (d <= 0) return "Today";
  if (d === 1) return "Yesterday";
  if (d < 7) return d + " days ago";
  if (d < 31) return Math.floor(d / 7) + (d < 14 ? " week ago" : " weeks ago");
  return new Date(ms).toISOString().slice(0, 10);
}

// ── SEARCH ───────────────────────────────────────────────────────────────
function escapeHtml(s) {
  return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
// a hit's snippet with its words lit
function litSnippet(snippet, words, ink) {
  var s = escapeHtml(snippet), q = escapeHtml(String(words || "").trim());
  if (!q) return s;
  var low = s.toLowerCase(), ql = q.toLowerCase(), out = "", i = 0, at;
  while ((at = low.indexOf(ql, i)) >= 0) {
    out += s.slice(i, at) + '<b><font color="' + ink + '">' + s.slice(at, at + q.length) + "</font></b>";
    i = at + q.length;
  }
  return out + s.slice(i);
}

// ── AN EPUB CHAPTER, SET ─────────────────────────────────────────────────
// What the reader wraps around a chapter's rich text: its colours and its
// measure, as Qt's rich text takes them (no CSS boxes, only these).
function chapterHtml(body, ink, link, lineHeight) {
  var lh = Math.round((Number(lineHeight) || 1.6) * 100);
  return '<html><head><style>a { color: ' + link + '; text-decoration: none; } '
    + "p, li, blockquote { line-height: " + lh + "%; } "
    + "h1, h2, h3 { font-weight: 700; } blockquote { font-style: italic; } "
    + 'img { max-width: 100%; }</style></head><body style="color: ' + ink + ';">'
    + String(body || "") + "</body></html>";
}
// "ch:3#end" → { chapter: 3, anchor: "end" }; anything else is the web's
function internalLink(href) {
  var m = /^ch:(\d+)(?:#(.*))?$/.exec(String(href || ""));
  return m ? { chapter: Number(m[1]), anchor: m[2] || "" } : null;
}
