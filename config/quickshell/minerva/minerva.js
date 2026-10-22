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
//   a book: { path, kind, title, author, cover, opened, added, pos,
//             progress, bookmarks: [mark], highlights: [mark], shelves:
//             [name], finished (ms, 0: not), readMs (time spent in it) }
//   kind:     "pdf" · "epub" · "comic" (cbz/cbr) · "text" (txt/md)
//   a place (pos, mark.where): { page } for a PDF or a comic (0-based), or
//             { chapter, frac } for an EPUB or a text (frac 0…1 down the
//             chapter); an EPUB highlight adds { start, end }, its words'
//             span in the chapter's plain text
//   a mark:   { id, where, text, at, note, color, comment, quads } — note:
//             the clio note a highlight went into ("" until it has);
//             color: one of COLORS; comment: what you wrote on it; quads:
//             a PDF highlight's outline on its page, in points
//             ([[[x, y], …], …], one polygon per line)

var KINDS = { pdf: "PDF", epub: "EPUB", comic: "Comic", text: "Text" };
var EXTS = { pdf: "pdf", epub: "epub", cbz: "comic", cbr: "comic", txt: "text", md: "text", markdown: "text" };

function kindOf(path) {
  var m = /\.([A-Za-z0-9]+)$/.exec(String(path || ""));
  return m ? EXTS[m[1].toLowerCase()] || "" : "";
}
// a PDF and a comic are pages; an EPUB and a text are chapters
function paged(kind) { return kind === "pdf" || kind === "comic"; }
function nameOf(path) {
  return String(path || "").replace(/.*\//, "").replace(/\.(pdf|epub|cbz|cbr|txt|md|markdown)$/i, "");
}

// ── SETTINGS ─────────────────────────────────────────────────────────────
// fontSize, lineHeight and width are an EPUB's (a PDF is set as printed);
// zoom is a PDF's default ("width": fit the page's width)
// theme: the page's colours (THEMES); spread: a PDF's or a comic's pages
// one at a time, two side by side, or two with the cover alone; sort and
// view: the library's order and which of it; shelves: the shelves made, in
// their order; watch: directories whose books join the library by
// themselves; translateTo: the look-up card's language; speakRate: reading
// aloud's pace
function defaults() {
  return { fontSize: 19, lineHeight: 1.6, width: 720, serif: true, sidebar: true, zoom: "width",
           theme: "auto", spread: "off", sort: "recent", view: "all", shelf: "", shelves: [], watch: [],
           translateTo: "en", speakRate: 1 };
}
var THEMES = ["auto", "paper", "sepia", "night"];
var SPREADS = ["off", "on", "cover"];
var SORTS = ["recent", "title", "author", "progress", "added"];
var VIEWS = ["all", "reading", "unread", "finished"];
function oneOf(list, v, d) { return list.indexOf(v) >= 0 ? v : d; }
function names(list) {
  var seen = {}, out = [];
  (Array.isArray(list) ? list : []).forEach(function (n) {
    n = String(n || "").trim();
    if (n && !seen[n.toLowerCase()]) { seen[n.toLowerCase()] = true; out.push(n); }
  });
  return out;
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
  d.theme = oneOf(THEMES, s.theme, d.theme);
  d.spread = oneOf(SPREADS, s.spread, d.spread);
  d.sort = oneOf(SORTS, s.sort, d.sort);
  d.view = oneOf(VIEWS, s.view, d.view);
  d.shelves = names(s.shelves);
  d.shelf = d.shelves.indexOf(s.shelf) >= 0 ? s.shelf : "";
  d.watch = names(s.watch).filter(function (p) { return p.charAt(0) === "/"; });
  if (typeof s.translateTo === "string" && /^[a-z]{2,3}(-[A-Za-z]{2,4})?$/.test(s.translateTo)) d.translateTo = s.translateTo;
  if (typeof s.speakRate === "number") d.speakRate = Math.max(0.5, Math.min(2, Math.round(s.speakRate * 10) / 10));
  // the window's own size, less the sidebar's room (MinervaWindow keepSize);
  // none until it has closed once
  if (Array.isArray(s.winSize) && s.winSize.length === 2 && s.winSize.every(function (n) { return typeof n === "number" && isFinite(n); }))
    d.winSize = [Math.max(820, Math.min(8000, Math.round(s.winSize[0]))), Math.max(560, Math.min(8000, Math.round(s.winSize[1])))];
  return d;
}

// ── THE LIBRARY ──────────────────────────────────────────────────────────
var MAX_BOOKS = 2000;
var COLORS = ["yellow", "green", "blue", "pink", "magenta"];

function cleanPos(kind, p) {
  if (!p || typeof p !== "object") return paged(kind) ? { page: 0 } : { chapter: 0, frac: 0 };
  if (paged(kind)) return { page: Math.max(0, Math.floor(Number(p.page) || 0)) };
  var out = { chapter: Math.max(0, Math.floor(Number(p.chapter) || 0)),
              frac: Math.max(0, Math.min(1, Number(p.frac) || 0)) };
  if (typeof p.start === "number" && typeof p.end === "number" && p.end > p.start && p.start >= 0) {
    out.start = Math.floor(p.start);
    out.end = Math.floor(p.end);
  }
  return out;
}
function cleanQuads(q) {
  if (!Array.isArray(q)) return [];
  return q.slice(0, 200).map(function (poly) {
    return (Array.isArray(poly) ? poly : []).filter(function (pt) {
      return Array.isArray(pt) && typeof pt[0] === "number" && typeof pt[1] === "number";
    }).map(function (pt) { return [Math.round(pt[0] * 10) / 10, Math.round(pt[1] * 10) / 10]; });
  }).filter(function (poly) { return poly.length >= 3; });
}
function cleanMark(kind, m) {
  if (!m || typeof m !== "object" || !m.where) return null;
  var out = { id: String(m.id || newId()), where: cleanPos(kind, m.where), text: String(m.text || ""),
              at: Number(m.at) || 0, note: String(m.note || ""),
              color: oneOf(COLORS, m.color, COLORS[0]), comment: String(m.comment || "") };
  var q = cleanQuads(m.quads);
  if (q.length) out.quads = q;
  return out;
}
function cleanBook(b) {
  if (!b || typeof b !== "object" || !b.path) return null;
  var kind = KINDS[b.kind] ? b.kind : kindOf(b.path);
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
    bookmarks: marks(b.bookmarks), highlights: marks(b.highlights),
    added: Number(b.added) || Number(b.opened) || 0, shelves: names(b.shelves),
    finished: Number(b.finished) || 0, readMs: Math.max(0, Number(b.readMs) || 0)
  };
}
function parseLibrary(text) {
  var j;
  try { j = JSON.parse(String(text || "")); } catch (e) { j = null; }
  var out = { books: [], settings: defaults(), stats: cleanStats(null) };
  if (!j || typeof j !== "object") return out;
  out.settings = cleanSettings(j.settings);
  out.stats = cleanStats(j.stats);
  var seen = {};
  (Array.isArray(j.books) ? j.books : []).forEach(function (b) {
    var c = cleanBook(b);
    if (c && !seen[c.path]) { seen[c.path] = true; out.books.push(c); }
  });
  return out;
}
function serializeLibrary(lib) {
  return JSON.stringify({ settings: cleanSettings(lib.settings), stats: cleanStats(lib.stats),
                          books: (lib.books || []).slice(0, MAX_BOOKS) }, null, 1) + "\n";
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
// books found in a watched directory: the ones not in yet join at the end,
// unread (never opened); the rest are left as they are
function addFound(books, paths, at) {
  var have = {}, out = (books || []).slice();
  out.forEach(function (b) { have[b.path] = true; });
  (paths || []).forEach(function (p) {
    if (have[p] || !kindOf(p)) return;
    have[p] = true;
    var b = cleanBook({ path: p, added: at || Date.now() });
    if (b) out.push(b);
  });
  return out.slice(0, MAX_BOOKS);
}

// ── THE LIBRARY, SHOWN ───────────────────────────────────────────────────
// unread: never opened · reading: opened, not finished · finished: said so
function stateOf(b) { return !b ? "unread" : b.finished > 0 ? "finished" : b.opened > 0 ? "reading" : "unread"; }
// which books, by state, shelf and typed words
function filterBooks(books, view, shelf, query) {
  var q = String(query || "").trim().toLowerCase();
  return (books || []).filter(function (b) {
    if (view && view !== "all" && stateOf(b) !== view) return false;
    if (shelf && (b.shelves || []).indexOf(shelf) < 0) return false;
    return !q || (b.title + " " + b.author + " " + b.path).toLowerCase().indexOf(q) >= 0;
  });
}
function byText(a, b) { return String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: "base" }); }
// an author sorted by their surname ("Ursula K. Le Guin" under L is out of
// reach without a list; the last word is near enough)
function surname(a) { var w = String(a || "").trim().split(/\s+/); return w[w.length - 1] || ""; }
function sortBooks(books, by) {
  var list = (books || []).slice();
  var recent = function (a, b) { return (b.opened || 0) - (a.opened || 0) || (b.added || 0) - (a.added || 0); };
  if (by === "title") list.sort(function (a, b) { return byText(a.title, b.title); });
  else if (by === "author") list.sort(function (a, b) {
    return (!a.author) - (!b.author) || byText(surname(a.author), surname(b.author)) || byText(a.title, b.title);
  });
  else if (by === "progress") list.sort(function (a, b) { return b.progress - a.progress || recent(a, b); });
  else if (by === "added") list.sort(function (a, b) { return (b.added || 0) - (a.added || 0) || byText(a.title, b.title); });
  else list.sort(recent);
  return list;
}
// a shelf ticked or not on a book
function toggleShelf(list, name) {
  list = names(list);
  var i = list.indexOf(name);
  if (i >= 0) list.splice(i, 1); else list.push(name);
  return list;
}

// ── TIME SPENT READING ───────────────────────────────────────────────────
// stats: { days: { "2026-10-21": ms } } — the whole library's, a year kept
function cleanStats(s) {
  var out = { days: {} };
  if (!s || typeof s !== "object" || !s.days || typeof s.days !== "object") return out;
  Object.keys(s.days).filter(function (k) { return /^\d{4}-\d\d-\d\d$/.test(k) && Number(s.days[k]) > 0; })
    .sort().slice(-400).forEach(function (k) { out.days[k] = Math.round(Number(s.days[k])); });
  return out;
}
function pad2(n) { return (n < 10 ? "0" : "") + n; }
function dayKey(ms) { var d = new Date(ms); return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()); }
function addTime(stats, ms, at) {
  var s = cleanStats(stats), k = dayKey(at || Date.now());
  s.days[k] = (s.days[k] || 0) + Math.max(0, Math.round(ms));
  return s;
}
// days in a row with a minute's reading or more, ending today (or
// yesterday: a streak is not broken until a whole day has gone by)
function streak(stats, now) {
  var days = (stats && stats.days) || {}, n = 0, t = now || Date.now();
  var on = function (ms) { return (days[dayKey(ms)] || 0) >= 60000; };
  if (!on(t)) t -= 86400000;
  while (on(t) && n < 400) { n++; t -= 86400000; }
  return n;
}
// the last `n` days' time, oldest first
function lastDays(stats, n, now) {
  var days = (stats && stats.days) || {}, out = [], t = now || Date.now();
  for (var i = n - 1; i >= 0; --i) out.push(days[dayKey(t - i * 86400000)] || 0);
  return out;
}
// how long the rest will take, at the pace read so far (ms; -1: not known
// yet — a few percent and a couple of minutes first)
function timeLeft(b) {
  if (!b || b.finished > 0 || b.progress < 0.03 || b.readMs < 120000) return -1;
  return Math.round(b.readMs * (1 - b.progress) / b.progress);
}
function spanWords(ms) {
  if (ms < 60000) return "under a minute";
  var m = Math.round(ms / 60000);
  if (m < 60) return m + " min";
  var h = Math.floor(m / 60), r = m % 60;
  return h + " h" + (r ? " " + r + " min" : "");
}

var _n = 0;
function newId() { _n = (_n + 1) % 1296; return Date.now().toString(36) + _n.toString(36); }

function addMark(list, where, text, at, extra) {
  return (list || []).concat([Object.assign({ id: newId(), where: where, text: String(text || ""), at: at || Date.now(),
                                              note: "", color: COLORS[0], comment: "" }, extra || {})]);
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
// how far through a PDF or a comic: the last page is the end
function pdfProgress(page, count) {
  return count > 1 ? Math.max(0, Math.min(1, page / (count - 1))) : 1;
}
function percentWords(p) { return Math.round((Number(p) || 0) * 100) + "%"; }

// "Page 12" / "Chapter 3 · 40%" — a place, said
function whereWords(kind, where, chapters) {
  if (!where) return "";
  if (paged(kind)) return "Page " + ((where.page || 0) + 1);
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
  ink = String(ink); link = String(link);
  return '<html><head><style>a { color: ' + link + '; text-decoration: none; } '
    + "p, li, blockquote { line-height: " + lh + "%; } "
    + "h1, h2, h3 { font-weight: 700; } blockquote { font-style: italic; } "
    + 'img { max-width: 100%; }</style></head><body style="color: ' + ink + ';">'
    + String(body || "") + "</body></html>";
}
// ── THE PAGE'S COLOURS ───────────────────────────────────────────────────
// { bg, ink, link } for a chapter, and for a page drawn as printed the two
// ends its tones are laid between (lo: what was black, hi: what was white
// — a PDF page goes through morpheus/shaders/pagetone). `shell` is the
// shell's own { bg, ink, link }; "auto" sets a chapter in it and leaves a
// printed page as printed. A comic is always as drawn.
var TONES = {
  paper: { bg: "#ffffff", ink: "#1d1d1f", link: "#2a62c9" },
  sepia: { bg: "#f4ecd8", ink: "#3d3022", link: "#8a5524" },
  night: { bg: "#151517", ink: "#d4d4d8", link: "#7fb0ff" }
};
// `shell`: { bg, ink, link } the shell's own colours, for auto, and
// `night`, the shell theme's dark side (user, 2026-10-22: night follows the
// theme's tone) — TONES.night only when none is given
function themeOf(theme, kind, shell) {
  var t = theme === "night" && shell && shell.night ? shell.night : TONES[theme];
  if (!t) return paged(kind) ? { bg: TONES.paper.bg, ink: TONES.paper.ink, link: "", tone: false }
    : { bg: shell.bg, ink: shell.ink, link: shell.link, tone: false };
  return { bg: t.bg, ink: t.ink, link: t.link, tone: kind === "pdf" && theme !== "paper" };
}

// ── PAGES LAID OUT ───────────────────────────────────────────────────────
// A PDF's or a comic's pages at a zoom, one to a row or two side by side
// ("cover": the first alone, as a printed book opens). sizes: [{ width,
// height }] in points. → { rects: [{ x, y, w, h }], rows: [[page…]],
// tops: [row y…, foot], rowOf: [row of page…], contentW, contentH }
// `top`: room over the first row (the window's frosted head, which the
// pages scroll on under)
function layoutPages(sizes, zoom, spread, pad, gap, viewW, top) {
  var n = (sizes || []).length, rows = [], rowOf = [];
  for (var i = 0; i < n; ) {
    var two = spread === "on" || (spread === "cover" && i > 0);
    var row = two && i + 1 < n ? [i, i + 1] : [i];
    row.forEach(function (p) { rowOf[p] = rows.length; });
    rows.push(row);
    i += row.length;
  }
  var widths = rows.map(function (r) {
    return r.reduce(function (w, p) { return w + Math.round(sizes[p].width * zoom); }, 0) + (r.length - 1) * gap;
  });
  var widest = widths.reduce(function (a, b) { return Math.max(a, b); }, 1);
  var contentW = Math.max(viewW || 0, widest + 2 * pad);
  var rects = [], tops = [pad + (top || 0)];
  rows.forEach(function (r, k) {
    var h = r.reduce(function (m, p) { return Math.max(m, Math.round(sizes[p].height * zoom)); }, 0);
    var x = Math.round((contentW - widths[k]) / 2);
    r.forEach(function (p) {
      var w = Math.round(sizes[p].width * zoom), ph = Math.round(sizes[p].height * zoom);
      rects[p] = { x: x, y: tops[k] + Math.round((h - ph) / 2), w: w, h: ph };
      x += w + gap;
    });
    tops.push(tops[k] + h + gap);
  });
  return { rects: rects, rows: rows, tops: tops, rowOf: rowOf, contentW: contentW,
           contentH: (n ? tops[tops.length - 1] - gap : 0) + pad };
}
// the row at y (its index), by halving
function rowAt(tops, y) {
  var lo = 0, hi = Math.max(0, tops.length - 2);
  while (lo < hi) {
    var mid = (lo + hi + 1) >> 1;
    if (tops[mid] <= y) lo = mid; else hi = mid - 1;
  }
  return lo;
}
// the zoom that fits the widest row's width, or a whole row in the view
function fitZoom(sizes, spread, mode, row, pad, gap, viewW, viewH) {
  var l = layoutPages(sizes, 1, spread, 0, 0, 0);
  var widest = 1, tall = 1;
  l.rows.forEach(function (r) {
    widest = Math.max(widest, r.reduce(function (w, p) { return w + sizes[p].width; }, 0));
  });
  (l.rows[row] || l.rows[0] || []).forEach(function (p) { tall = Math.max(tall, sizes[p].height); });
  var byW = (viewW - 2 * pad - (spread === "off" ? 0 : gap)) / widest;
  return Math.max(0.05, mode === "page" ? Math.min(byW, (viewH - 2 * pad) / tall) : byW);
}

// ── HIGHLIGHTS, OUT ──────────────────────────────────────────────────────
// a book's highlights as Markdown, in reading order: each a quote, where it
// is, and what you wrote on it
function highlightsMarkdown(book, chapters) {
  if (!book) return "";
  var out = ["# " + book.title + (book.author ? "\n\n*" + book.author + "*" : ""), ""];
  sortMarks(book.highlights).forEach(function (h) {
    out.push("> " + String(h.text).replace(/\n+/g, " "));
    out.push("");
    out.push("— " + whereWords(book.kind, h.where, chapters) + (h.color && h.color !== COLORS[0] ? " · " + h.color : ""));
    if (h.comment) { out.push(""); out.push(h.comment); }
    out.push("");
  });
  return out.join("\n").replace(/\n{3,}/g, "\n\n").trim() + "\n";
}

// ── READ ALOUD ───────────────────────────────────────────────────────────
// the sentences of a text, as spans: [{ start, end }] — the end stops at
// the stop, the space after it belongs to no one. Long runs without a
// stop are cut at a space near 300 characters, so a voice never waits on
// a page-long "sentence".
function sentences(text) {
  var s = String(text || ""), out = [], i = 0, n = s.length;
  while (i < n) {
    while (i < n && /\s/.test(s.charAt(i))) i++;
    if (i >= n) break;
    var j = i, cut = -1;
    while (j < n) {
      var c = s.charAt(j);
      if (/[.!?\u2026]/.test(c) || c === "\n" || c === "\u2029") {
        while (j + 1 < n && /[.!?\u2026"'\u201d\u2019)\]]/.test(s.charAt(j + 1))) j++;
        if (c === "\n" || c === "\u2029" || j + 1 >= n || /\s/.test(s.charAt(j + 1))) { j++; break; }
      }
      if (j - i > 300 && cut < 0 && /\s/.test(c)) { cut = j; break; }
      j++;
    }
    var end = cut >= 0 ? cut : j;
    var e = end;
    while (e > i && /\s/.test(s.charAt(e - 1))) e--;
    if (e > i && /[\w\u00c0-\uffff]/.test(s.slice(i, e))) out.push({ start: i, end: e });
    i = end;
  }
  return out;
}

// "ch:3#end" → { chapter: 3, anchor: "end" }; anything else is the web's
function internalLink(href) {
  var m = /^ch:(\d+)(?:#(.*))?$/.exec(String(href || ""));
  return m ? { chapter: Number(m[1]), anchor: m[2] || "" } : null;
}
