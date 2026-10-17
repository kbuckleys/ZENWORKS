// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CLIO'S NOTEBOOK, THE PURE HALF — what a note and a journal entry are, made
// of blocks; reading Qt's rich text into blocks and writing blocks back out
// (to a sticky, to Markdown, to HTML); search, the list's date headings, the
// containers' tree; the journal's streaks and calendar. No window, no disk:
// everything here runs under node (oracle/tests/clio-notes.js).
//
// A NOTE IS A LIST OF BLOCKS, not one rich-text document. A block is one
// paragraph of one kind — a heading, a checklist item, a picture — and the
// window draws each with an item of its own: a checkbox is a real checkbox,
// a picture a real picture, a table a grid. Inside a text block the words
// are Qt's inline rich text (bold, a link, a color), kept as the run of
// inline markup a TextEdit hands back.
//
//   { k: kind, h: inline html, c: checked, l: indent level,
//     src, name, size: an attachment's,  w: a picture's width (0..1),
//     rows: [[html…]…] a table's cells,  fold: a heading folded shut }

.pragma library

// ── THE KINDS OF BLOCK ───────────────────────────────────────────────────
// `text`: typed into. `list`: a marker in front and indentable. The names
// are what Apple's Format menu calls them.
var KINDS = {
  title:      { text: true, label: "Title",       glyph: "\u{F05F4}" },
  heading:    { text: true, label: "Heading",     glyph: "\u{F026B}" },
  subheading: { text: true, label: "Subheading",  glyph: "\u{F026C}" },
  body:       { text: true, label: "Body",        glyph: "\u{F09A8}" },
  mono:       { text: true, label: "Monostyled",  glyph: "", plain: true },
  quote:      { text: true, label: "Block quote", glyph: "\u{F0757}" },
  bullet:     { text: true, list: true, label: "Bulleted list", glyph: "" },
  dash:       { text: true, list: true, label: "Dashed list",   glyph: "\u{F0374}" },
  number:     { text: true, list: true, label: "Numbered list", glyph: "" },
  check:      { text: true, list: true, label: "Checklist",     glyph: "\u{F0C52}" },
  image:      { label: "Picture",  glyph: "" },
  file:       { label: "File",     glyph: "" },
  table:      { label: "Table",    glyph: "" },
  sketch:     { label: "Sketch",   glyph: "\u{F03EB}" },
  rule:       { label: "Divider",  glyph: "\u{F06D7}" }
};

function isText(b) { return !!b && !!KINDS[b.k] && !!KINDS[b.k].text; }
function isList(b) { return !!b && !!KINDS[b.k] && !!KINDS[b.k].list; }
function isHeading(b) { return !!b && (b.k === "title" || b.k === "heading" || b.k === "subheading"); }
// a heading's rank, for folding: a title folds everything under it, a
// heading what is under it up to the next heading or title
function rank(b) { return b.k === "title" ? 1 : b.k === "heading" ? 2 : b.k === "subheading" ? 3 : 9; }

var MAX_LEVEL = 6;

// ── IDS ──────────────────────────────────────────────────────────────────
var _seq = 0;
function newId(prefix) {
  _seq = (_seq + 1) % 1679616;
  return (prefix || "c") + Date.now().toString(36) + _seq.toString(36)
    + Math.floor(Math.random() * 1296).toString(36);
}

function block(k, h, extra) {
  var b = { k: KINDS[k] ? k : "body", h: h || "" };
  if (extra) for (var key in extra) b[key] = extra[key];
  if (b.k === "check" && b.c === undefined) b.c = false;
  return b;
}

// A note as made: a title waiting for its first line. `start` is the kind
// the first line takes (a setting: Apple's "New notes start with").
function blankNote(folder, start) {
  var now = Date.now();
  return { v: 1, id: newId("n"), kind: "note", folder: folder || "",
           blocks: [block(KINDS[start] && KINDS[start].text ? start : "title", "")],
           created: now, modified: now, pinned: false, deleted: 0 };
}

// A journal entry: dated today unless told, an optional title, then words.
// `prompt`: the reflection it answers, drawn over it (Apple's suggestion).
function blankEntry(journal, date, prompt) {
  var now = Date.now();
  return { v: 1, id: newId("e"), kind: "entry", journal: journal || "",
           blocks: [block("title", ""), block("body", "")],
           created: now, modified: now, date: date || now, deleted: 0,
           mood: null, bookmark: false, prompt: prompt || "" };
}

// ── READING A SAVED ONE ──────────────────────────────────────────────────
// Every field present and of its type, whatever the file said: the window
// reads them unguarded.
var ALIGNS = ["center", "right", "justify"];

function cleanBlock(b) {
  if (!b || typeof b !== "object") return null;
  var out = block(String(b.k || "body"), String(b.h || ""));
  if (out.k === "check") out.c = !!b.c;
  var l = Math.round(Number(b.l) || 0);
  if (l > 0) out.l = Math.min(MAX_LEVEL, l);
  if (b.src) out.src = String(b.src);
  if (b.name) out.name = String(b.name);
  if (b.size) out.size = Number(b.size) || 0;
  if (b.w) out.w = Math.max(0.15, Math.min(1, Number(b.w) || 1));
  if (b.fold && isHeading(out)) out.fold = true;
  if (b.strokes) out.strokes = b.strokes;
  if (b.aspect) out.aspect = Math.max(0.1, Math.min(4, Number(b.aspect) || 0.6));
  // standing beside the block before it, in a row (pictures and files)
  if (b.beside && (out.k === "image" || out.k === "sketch" || out.k === "file")) out.beside = true;
  // how its lines sit (BlockEditor.setAlign); along the left is no field
  // (a picture's or a file's: its row's, when it leads one)
  if ((isText(out) && out.k !== "mono" || out.k === "image" || out.k === "sketch" || out.k === "file")
      && ALIGNS.indexOf(b.align) >= 0) out.align = b.align;
  // a checklist item's reminder, when it is due (ms)
  if (b.due && out.k === "check") out.due = Number(b.due) || 0;
  // the words read off a picture (tesseract), for search and for copying
  if (b.ocr && out.k === "image") out.ocr = String(b.ocr);
  if (out.k === "table") {
    var rows = Array.isArray(b.rows) ? b.rows : [];
    var w = 0;
    for (var i = 0; i < rows.length; i++) if (Array.isArray(rows[i])) w = Math.max(w, rows[i].length);
    w = Math.max(1, w);
    out.rows = [];
    for (var r = 0; r < Math.max(1, rows.length); r++) {
      var row = [];
      for (var c = 0; c < w; c++) row.push(rows[r] && rows[r][c] !== undefined ? String(rows[r][c]) : "");
      out.rows.push(row);
    }
  }
  return out;
}

function clean(n) {
  if (!n || typeof n !== "object" || !n.id) return null;
  var out = {
    v: 1, id: String(n.id), kind: n.kind === "entry" ? "entry" : "note",
    created: Number(n.created) || 0, modified: Number(n.modified) || Number(n.created) || 0,
    deleted: Number(n.deleted) || 0, pinned: !!n.pinned
  };
  if (out.kind === "note") out.folder = String(n.folder || "");
  else {
    out.journal = String(n.journal || "");
    out.date = Number(n.date) || out.created;
    out.mood = cleanMood(n.mood);
    out.bookmark = !!n.bookmark;
    out.prompt = String(n.prompt || "");
  }
  // a name given it (the menu's Rename…): its title, over the first line
  if (n.name && String(n.name).trim() !== "") out.name = String(n.name).trim().slice(0, 200);
  // a sticky in the Trash: where it stood, to stand there again
  if (n.fromDesktop && typeof n.fromDesktop === "object") out.fromDesktop = n.fromDesktop;
  // the files a locked note uses from other notes, said in the clear
  if (Array.isArray(n.uses) && n.uses.length) out.uses = n.uses.map(String);
  // when its file was last written, as read (the sync guard: ClioManager)
  if (n._disk) out._disk = Number(n._disk) || 0;
  // sealed: the blocks are on disk encrypted, and only the head is readable
  if (n.sealed) {
    out.sealed = String(n.sealed);
    out.title = String(n.title || "Locked note");
    out.blocks = null;
    return out;
  }
  var bs = [];
  var src = Array.isArray(n.blocks) ? n.blocks : [];
  for (var i = 0; i < src.length; i++) {
    var b = cleanBlock(src[i]);
    if (b) bs.push(b);
  }
  if (bs.length === 0) bs.push(block(out.kind === "entry" ? "body" : "title", ""));
  out.blocks = bs;
  return out;
}

// What goes to disk: the note without anything the window worked out for
// itself (its `d`erived head, recomputed on load).
function stored(n) {
  var out = {};
  // (`_` fields are the window's own bookkeeping, never written)
  for (var k in n) if (k !== "d" && k !== "open" && k.charAt(0) !== "_") out[k] = n[k];
  return out;
}

// ── INLINE HTML ──────────────────────────────────────────────────────────
var ENTITIES = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " };

function unescape(s) {
  return String(s).replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, function (m, e) {
    if (e[0] === "#") {
      var n = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return isNaN(n) ? m : String.fromCodePoint(n);
    }
    var v = ENTITIES[e.toLowerCase()];
    return v !== undefined ? v : m;
  });
}

function escape(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// The words of a run of inline markup. A line break is a newline; the
// marks Qt leaves round a copied range are not words.
function plain(html) {
  var s = String(html || "");
  if (s.indexOf("<") < 0 && s.indexOf("&") < 0) return s;
  s = s.replace(/<!--[\s\S]*?-->/g, "").replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]*>/g, "");
  return unescape(s).replace(/ /g, " ");
}

// A run of inline markup made safe to keep: what a TextEdit hands back is
// its whole document; only the inside of its one paragraph is the block.
function fragment(html) {
  var s = String(html || "");
  var i = s.indexOf("<body");
  if (i >= 0) {
    var open = s.indexOf(">", i);
    var close = s.lastIndexOf("</body>");
    if (open >= 0) s = s.slice(open + 1, close > open ? close : s.length);
  }
  return s.replace(/<!--\/?(?:Start|End)Fragment-->/g, "").trim();
}

// The run inside a TextEdit's one paragraph. An empty block is "", never a
// paragraph of nothing.
function inline(html) {
  var s = fragment(html);
  var m = s.match(/^\s*<(p|li|h\d|pre)\b[^>]*>([\s\S]*)<\/\1>\s*$/i);
  if (m && m[2].search(/<(p|li|h\d|pre)\b/i) < 0) s = m[2];
  s = tidy(s);
  return plain(s).replace(/\s/g, "") === "" && s.indexOf("<img") < 0 ? "" : s;
}

// What is not ours to keep from a run: a face and a size (a block's kind
// says those), the blue Qt paints a link in (the window paints its own),
// empty spans, and the color sentinels decoded back (see paint).
function tidy(s) {
  s = String(s || "");
  s = s.replace(/<a\b([^>]*)><span style="[^"]*">([\s\S]*?)<\/span><\/a>/gi, "<a$1>$2</a>");
  s = s.replace(/style="([^"]*)"/gi, function (m, st) {
    var kept = st.split(";").map(function (d) { return d.trim(); }).filter(function (d) {
      // a face chosen for a run is kept: it carries the 'clio-face' marker
      // family (see face), which a paste's own fonts do not
      if (/^font-family/i.test(d)) return FACE_MARK.test(d);
      return d !== "" && !/^(font-size|-qt-|margin|text-indent|line-height)/i.test(d)
        && !/^text-decoration:\s*none$/i.test(d);
    });
    return kept.length === 0 ? "style=\"\"" : "style=\" " + kept.join("; ") + ";\"";
  });
  for (var i = 0; i < 3; i++) s = s.replace(/<span style="">([\s\S]*?)<\/span>/gi, "$1").replace(/<span>([\s\S]*?)<\/span>/gi, "$1");
  return s;
}

// ── COLORS, BY NAME ─────────────────────────────────────────────────────
// A color typed into a note is one of the theme's, by NAME: written out as
// a sentinel hex nobody would choose, and painted the theme's real color
// only while it is on screen — so a note colored under one theme is still
// colored right under the next (themes memory: a color copied is frozen).
var INKS = ["magenta", "pink", "yellow", "green", "blue", "cyan", "red"];
var MARKERS = ["sand", "pink", "green", "blue", "magenta"];
function sentinel(kind, i) {
  // #01c1xy: "c1" for clio; x = 0 text, 1 marker
  var h = (kind === "mark" ? 16 : 0) + i;
  return "#01c1" + (h < 16 ? "0" : "") + h.toString(16);
}
// sentinel → color (painting) and back (keeping). `ink(name)` and
// `mark(name)` give the color as #rrggbb.
function paint(html, ink, mark) {
  return String(html || "").replace(/#01c1([0-9a-f]{2})/gi, function (m, x) {
    var v = parseInt(x, 16);
    if (v >= 16) return MARKERS[v - 16] ? mark(MARKERS[v - 16]) : m;
    return INKS[v] ? ink(INKS[v]) : m;
  });
}
function unpaint(html, ink, mark) {
  var s = String(html || "");
  for (var i = 0; i < INKS.length; i++) s = s.split(String(ink(INKS[i])).toLowerCase()).join(sentinel("ink", i));
  for (var j = 0; j < MARKERS.length; j++) s = s.split(String(mark(MARKERS[j])).toLowerCase()).join(sentinel("mark", j));
  return s;
}

// ── BOLD, ITALIC, AND THE REST: WHAT QT MAKES OF THEM ────────────────────
// Inserted as <b>, read back as a span's font-weight; asked "is this bold"
// has to look for what the tag became (clio.js says why at length).
var MARKS = {
  b: { probe: /font-weight:\s*[6-9]\d\d/i, strip: /font-weight:\s*\d+\s*;?/gi, open: "<b>", close: "</b>" },
  i: { probe: /font-style:\s*italic/i, strip: /font-style:\s*italic\s*;?/gi, open: "<i>", close: "</i>" },
  u: { probe: /text-decoration:[^;"]*underline/i, strip: /text-decoration:[^;"]*underline[^;"]*;?/gi, open: "<u>", close: "</u>" },
  s: { probe: /text-decoration:[^;"]*line-through/i, strip: /text-decoration:[^;"]*line-through[^;"]*;?/gi, open: "<s>", close: "</s>" }
};
function marked(run, tag) {
  var m = MARKS[tag];
  return !!m && m.probe.test(String(run || ""));
}
function unmark(run, tag) {
  var m = MARKS[tag];
  if (!m) return run;
  return tidy(String(run || "").replace(m.strip, ""));
}
function toggleMark(run, tag) {
  var m = MARKS[tag];
  if (!m) return run;
  return marked(run, tag) ? unmark(run, tag) : m.open + run + m.close;
}
// a color on a run: `css` is "color" or "background-color"; value "" takes it off
function colour(run, css, value) {
  var re = css === "color" ? /(^|[\s;"])color:\s*#[0-9a-f]{6}\s*;?/gi : /background-color:\s*#[0-9a-f]{6}\s*;?/gi;
  var s = tidy(String(run || "").replace(re, "$1"));
  if (!value) return s;
  return "<span style=\"" + css + ":" + value + ";\">" + s + "</span>";
}

// ── THE WORDS TO SPELL ───────────────────────────────────────────────────
// [{ w, a, b }] of a block's plain text: letters with ' or ’ inside. Not a
// word to check: one with a digit, a #tag, an @name, an address (a run with
// :// or a dot in it, or www.), and a short acronym in capitals.
// Letters by range, not \p{L}: QML's engine has no Unicode property escapes
// (the regex compiled and matched nothing). Latin, Greek, Cyrillic,
// Armenian, Hebrew, Arabic, Devanagari and the Latin/Greek extensions, with
// combining marks.
var LETTER = "A-Za-zªµºÀ-ÖØ-öø-ʯ̀-ͯͰ-ϿЀ-ԯ"
  + "Ա-ևא-תؠ-ٟऀ-ॿḀ-῿";
var SPELL_TOKEN = new RegExp("[" + LETTER + "0-9_./:@#'’-]+", "g");
var SPELL_WORD = new RegExp("[" + LETTER + "]+(?:['’][" + LETTER + "]+)*", "g");
var SPELL_DOTTED = new RegExp("[" + LETTER + "]\\.[" + LETTER + "]");
function spellWords(t) {
  var out = [];
  var s = String(t || "");
  var re = new RegExp(SPELL_TOKEN.source, "g");
  var m;
  while ((m = re.exec(s)) !== null) {
    var tok = m[0];
    if (/:\/\/|^www\.|@|^#/.test(tok)) continue;
    if (SPELL_DOTTED.test(tok)) continue;
    var inner = new RegExp(SPELL_WORD.source, "g");
    var w;
    while ((w = inner.exec(tok)) !== null) {
      var word = w[0];
      var a = m.index + w.index;
      var next = s.charAt(a + word.length);
      var prev = a > 0 ? s.charAt(a - 1) : "";
      if (/\d/.test(prev) || /\d|_/.test(next)) continue;
      if (word.length < 2) continue;
      if (word.length <= 5 && word === word.toUpperCase()) continue;
      out.push({ w: word.replace(/’/g, "'"), a: a, b: a + word.length });
    }
  }
  return out;
}

// ── A FACE FOR A RUN ─────────────────────────────────────────────────────
// A word or a selection in a typeface of its own, the rest of the block
// keeping the note's (user, 2026-10-17). Written with a second family that
// names no font, 'clio-face': Qt keeps the list as it was given, and it is
// how tidy tells a face chosen here from the fonts a paste brings along
// (those go, as before). "" takes the run back to the note's face.
var FACE_MARK = /clio-face/i;
function face(run, family) {
  var s = String(run || "").replace(/font-family:[^;"]*clio-face[^;"]*;?/gi, "");
  s = tidy(s);
  if (!family) return s;
  return "<span style=\"font-family:'" + String(family).replace(/['"<>;]/g, "") + "','clio-face';\">" + s + "</span>";
}
// the chosen face in a run, if one covers it all ("" when none or mixed)
function faceOf(run) {
  var all = String(run || "").match(/font-family:\s*'([^']*)'\s*,\s*'clio-face'/gi);
  if (!all) return "";
  var names = all.map(function (m) { return m.replace(/font-family:\s*'([^']*)'.*/i, "$1"); });
  for (var i = 1; i < names.length; i++) if (names[i] !== names[0]) return "";
  return names[0];
}

// ── MANY PARAGRAPHS INTO BLOCKS ──────────────────────────────────────────
// Whatever Qt made of a paste, or a sticky's text: its paragraphs, list
// items, headings, code and tables, each one block. A tolerant walk over
// Qt's own markup (which is regular: see oracle/tests/clio-notes.js), not a
// browser's.
function blocksOf(html) {
  var s = fragment(html);
  var out = [];
  var lists = [];        // [{ ordered }]
  var cur = null;        // the block being filled: { k, h, … }
  var depth = 0;         // inside a table: its own walk
  var pre = false;
  function flush() {
    if (!cur) return;
    if (cur.k === "body") {
      // a paragraph that is one picture is a picture; one that is wholly
      // large and bold is the heading stickyOf wrote
      var img = cur.h.match(/^\s*<img\b[^>]*src="([^"]*)"[^>]*\/?>\s*$/i);
      if (img) { out.push(block("image", "", { src: unescape(img[1]).replace(/^file:\/\//, "") })); cur = null; return; }
      var big = cur.h.match(/^\s*<span style="([^"]*font-size:\s*(x-large|large)[^"]*)">([\s\S]*)<\/span>\s*$/i);
      if (big && big[3].indexOf("<span") < 0) cur = block(big[2].toLowerCase() === "x-large" ? "title" : "heading", big[3]);
    }
    cur.h = cur.k === "mono" ? cur.h : inline(cur.h);
    out.push(cur);
    cur = null;
  }
  var re = /<(\/?)([a-z0-9]+)\b([^>]*?)(\/?)>|([^<]+)/gi;
  var m;
  var tableStart = -1;
  while ((m = re.exec(s)) !== null) {
    if (m[5] !== undefined) {
      if (depth > 0) continue;
      var t = m[5];
      // between two lines of code: Qt's own newline, not the text's
      if (cur && cur.k === "mono" && !pre) continue;
      if (!cur) {
        if (t.replace(/\s/g, "") === "") continue;
        cur = block("body", "");
      }
      cur.h += cur.k === "mono" ? unescape(t) : t;
      continue;
    }
    var close = m[1] === "/", tag = m[2].toLowerCase(), attrs = m[3] || "", self = m[4] === "/";
    if (tag === "table") {
      if (!close) { if (depth === 0) { flush(); tableStart = m.index; } depth++; }
      else if (--depth === 0) {
        out.push(tableOf(s.slice(tableStart, re.lastIndex)));
        tableStart = -1;
      }
      continue;
    }
    if (depth > 0) continue;
    if (tag === "ul" || tag === "ol") {
      if (!close) lists.push({ ordered: tag === "ol", dash: /list-style-type:\s*square/i.test(attrs) });
      else lists.pop();
      continue;
    }
    if (tag === "p" || tag === "li" || tag === "div" || /^h[1-6]$/.test(tag) || tag === "pre" || tag === "blockquote") {
      if (close) { if (tag === "pre") pre = false; else flush(); continue; }
      if (tag === "pre") {
        pre = true;
        // Qt writes one <pre> per line: lines in a row are one block
        if (cur && cur.k === "mono") { cur.h += "\n"; continue; }
        flush();
        cur = block("mono", "");
        continue;
      }
      flush();
      var k = "body", extra = {};
      if (tag === "li") {
        var L = lists[lists.length - 1] || { ordered: false };
        k = /class="checked"/i.test(attrs) ? "check" : /class="unchecked"/i.test(attrs) ? "check"
          : L.ordered ? "number" : L.dash ? "dash" : "bullet";
        if (k === "check") extra.c = /class="checked"/i.test(attrs);
        if (lists.length > 1) extra.l = Math.min(MAX_LEVEL, lists.length - 1);
      } else if (tag === "h1") k = "title";
      else if (tag === "h2") k = "heading";
      else if (/^h[3-6]$/.test(tag)) k = "subheading";
      else if (tag === "blockquote") k = "quote";
      else if (/margin-left:\s*[1-9]\d*px;[^"]*margin-right:\s*[1-9]/i.test(attrs)) k = "quote";
      cur = block(k, "", extra);
      continue;
    }
    if (tag === "hr") { flush(); out.push(block("rule", "")); continue; }
    if (tag === "br") {
      if (!cur) cur = block("body", "");
      cur.h += cur.k === "mono" ? "\n" : "<br />";
      continue;
    }
    if (tag === "img" && !cur) {
      var src = (attrs.match(/src="([^"]*)"/i) || [])[1];
      if (src) { out.push(block("image", "", { src: unescape(src).replace(/^file:\/\//, "") })); continue; }
    }
    if (tag === "body" || tag === "html" || tag === "head" || tag === "meta" || tag === "style" || tag === "title") continue;
    // anything inline: kept as written
    if (!cur) cur = block("body", "");
    if (cur.k !== "mono") cur.h += m[0];
    void self;
  }
  flush();
  // a mono block's trailing newline is the last <pre>'s, not the text's
  for (var i = 0; i < out.length; i++) if (out[i].k === "mono") out[i].h = out[i].h.replace(/\n+$/, "");
  return out;
}

function tableOf(html) {
  var rows = [];
  var rowRe = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi, r;
  while ((r = rowRe.exec(html)) !== null) {
    var cells = [];
    var cellRe = /<t[dh]\b[^>]*>([\s\S]*?)<\/t[dh]>/gi, c;
    while ((c = cellRe.exec(r[1])) !== null) cells.push(inline(c[1]));
    rows.push(cells);
  }
  return cleanBlock({ k: "table", rows: rows.length ? rows : [[""]] });
}

// ── AND BACK OUT ─────────────────────────────────────────────────────────
// Blocks as one HTML document: for a sticky (Qt reads it back), an export,
// the clipboard. `base`: where attachments live, for an image's src.
function htmlOf(blocks, base, opts) {
  opts = opts || {};
  var out = [];
  var open = [];   // list tags open, by level
  var nums = numbering(blocks);
  function closeTo(n) { while (open.length > n) out.push("</" + open.pop() + ">"); }
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i];
    if (isList(b) && !opts.flat) {
      var tag = b.k === "number" ? "ol" : "ul";
      var lvl = (b.l || 0) + 1;
      closeTo(lvl);
      if (open.length === lvl && open[lvl - 1] !== tag) closeTo(lvl - 1);
      while (open.length < lvl) {
        out.push(tag === "ol" ? "<ol>" : b.k === "dash" ? "<ul style=\"list-style-type: square;\">" : "<ul>");
        open.push(tag);
      }
      out.push(b.k === "check" ? "<li class=\"" + (b.c ? "checked" : "unchecked") + "\">" + b.h + "</li>" : "<li>" + b.h + "</li>");
      continue;
    }
    closeTo(0);
    var src = b.src ? (base ? base + "/" : "") + b.src : "";
    var al = b.align ? " style=\"text-align: " + b.align + ";\"" : "";
    switch (b.k) {
      case "title": out.push("<h1" + al + ">" + b.h + "</h1>"); break;
      case "heading": out.push("<h2" + al + ">" + b.h + "</h2>"); break;
      case "subheading": out.push("<h3" + al + ">" + b.h + "</h3>"); break;
      case "mono": out.push("<pre>" + escape(b.h) + "</pre>"); break;
      case "quote": out.push("<blockquote" + al + ">" + b.h + "</blockquote>"); break;
      case "rule": out.push("<hr />"); break;
      case "image": case "sketch":
        out.push("<p" + al + "><img src=\"" + escape(opts.sticky ? "file://" + src : src) + "\""
          + (opts.imgWidth ? " width=\"" + Math.round(opts.imgWidth * (b.w || 1)) + "\"" : "") + " /></p>");
        break;
      case "file": out.push("<p" + al + "><a href=\"" + escape(src) + "\">" + escape(b.name || "file") + "</a></p>"); break;
      case "table":
        out.push("<table border=\"1\" cellpadding=\"6\" style=\"border-collapse: collapse;\">"
          + b.rows.map(function (row) { return "<tr>" + row.map(function (c) { return "<td>" + c + "</td>"; }).join("") + "</tr>"; }).join("")
          + "</table>");
        break;
      case "check":
        out.push("<p" + al + ">" + (b.c ? "☑ " : "☐ ") + b.h + "</p>"); break;
      case "bullet": case "dash": case "number":
        out.push("<p" + al + ">" + (b.k === "number" ? nums[i] + ". " : b.k === "dash" ? "– " : "• ") + b.h + "</p>"); break;
      default: out.push("<p" + al + ">" + b.h + "</p>");
    }
  }
  closeTo(0);
  return out.join("\n");
}

// A sticky's text: what it can draw. The board's TextEdit has no lists or
// pictures of its own, so a checklist is its boxes as characters and a
// list its markers; a heading is bold and larger.
function stickyOf(blocks) {
  var nums = numbering(blocks);
  var out = [];
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i];
    var pad = b.l ? " ".repeat(b.l) : "";
    switch (b.k) {
      case "title": out.push("<p><span style=\" font-size:x-large;\"><b>" + b.h + "</b></span></p>"); break;
      case "heading": out.push("<p><span style=\" font-size:large;\"><b>" + b.h + "</b></span></p>"); break;
      case "subheading": out.push("<p><span style=\" font-weight:700;\">" + b.h + "</span></p>"); break;
      case "mono": out.push("<p>" + escape(b.h).replace(/\n/g, "<br />") + "</p>"); break;
      case "check": out.push("<p>" + pad + (b.c ? "☑ " : "☐ ") + b.h + "</p>"); break;
      case "bullet": out.push("<p>" + pad + "• " + b.h + "</p>"); break;
      case "dash": out.push("<p>" + pad + "– " + b.h + "</p>"); break;
      case "number": out.push("<p>" + pad + nums[i] + ". " + b.h + "</p>"); break;
      case "rule": out.push("<p>———</p>"); break;
      case "table": for (var r = 0; r < b.rows.length; r++) out.push("<p>" + b.rows[r].join(" │ ") + "</p>"); break;
      case "image": case "sketch": case "file": out.push("<p>[" + escape(b.name || KINDS[b.k].label) + "]</p>"); break;
      default: out.push("<p>" + b.h + "</p>");
    }
  }
  return out.join("");
}

// A sticky's text into blocks: its paragraphs, and the boxes and markers
// stickyOf wrote turned back into what they were.
function blocksOfSticky(html) {
  var bs = blocksOf(html || "");
  for (var i = 0; i < bs.length; i++) {
    var b = bs[i];
    if (b.k !== "body") continue;
    var p = plain(b.h);
    var lead = p.match(/^([ ]*)(☐|☑|•|–|\d+\.)\s/);
    if (!lead) continue;
    var cut = lead[0].length;
    var kind = lead[2] === "☐" || lead[2] === "☑" ? "check" : lead[2] === "•" ? "bullet"
      : lead[2] === "–" ? "dash" : "number";
    var nb = block(kind, dropChars(b.h, cut));
    if (kind === "check") nb.c = lead[2] === "☑";
    if (lead[1].length) nb.l = lead[1].length;
    bs[i] = nb;
  }
  return bs.length ? bs : [block("body", "")];
}

// The first `n` characters of a run's text taken off its front, its markup
// kept for the rest.
function dropChars(html, n) {
  var s = String(html || "");
  var out = "", left = n, i = 0;
  while (i < s.length) {
    if (s[i] === "<") {
      var e = s.indexOf(">", i);
      if (e < 0) e = s.length - 1;
      out += s.slice(i, e + 1);
      i = e + 1;
      continue;
    }
    var len = 1;
    if (s[i] === "&") {
      var semi = s.indexOf(";", i);
      if (semi > i && semi - i < 10) len = semi - i + 1;
    }
    if (left > 0) left--; else out += s.slice(i, i + len);
    i += len;
  }
  return tidy(out);
}

// ── MARKDOWN ─────────────────────────────────────────────────────────────
function mdInline(html) {
  var s = String(html || "");
  s = s.replace(/<br\s*\/?>/gi, "  \n");
  s = s.replace(/<a\b[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, function (m, href, t) {
    return "[" + mdInline(t) + "](" + unescape(href) + ")";
  });
  // a span says several things at once: each becomes its mark
  s = s.replace(/<span style="([^"]*)">([\s\S]*?)<\/span>/gi, function (m, st, t) {
    var o = "", c = "";
    if (MARKS.b.probe.test(st)) { o += "**"; c = "**" + c; }
    if (MARKS.i.probe.test(st)) { o += "*"; c = "*" + c; }
    if (MARKS.s.probe.test(st)) { o += "~~"; c = "~~" + c; }
    if (/background-color/i.test(st)) { o += "=="; c = "==" + c; }
    return o + mdInline(t) + c;
  });
  s = s.replace(/<(b|strong)>([\s\S]*?)<\/\1>/gi, "**$2**").replace(/<(i|em)>([\s\S]*?)<\/\1>/gi, "*$2*")
    .replace(/<(s|del)>([\s\S]*?)<\/\1>/gi, "~~$2~~").replace(/<code>([\s\S]*?)<\/code>/gi, "`$1`");
  return unescape(s.replace(/<[^>]*>/g, "")).replace(/ /g, " ");
}

function markdownOf(blocks, base) {
  var nums = numbering(blocks);
  var out = [];
  var prevList = false;
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i];
    var list = isList(b);
    if (out.length && !(list && prevList)) out.push("");
    prevList = list;
    var pad = "  ".repeat(b.l || 0);
    var src = b.src ? (base ? base + "/" : "") + b.src : "";
    switch (b.k) {
      case "title": out.push("# " + mdInline(b.h)); break;
      case "heading": out.push("## " + mdInline(b.h)); break;
      case "subheading": out.push("### " + mdInline(b.h)); break;
      case "mono": out.push("```\n" + b.h + "\n```"); break;
      case "quote": out.push("> " + mdInline(b.h).replace(/\n/g, "\n> ")); break;
      case "bullet": out.push(pad + "- " + mdInline(b.h)); break;
      case "dash": out.push(pad + "- " + mdInline(b.h)); break;
      case "number": out.push(pad + nums[i] + ". " + mdInline(b.h)); break;
      case "check": out.push(pad + "- [" + (b.c ? "x" : " ") + "] " + mdInline(b.h)); break;
      case "rule": out.push("---"); break;
      case "image": case "sketch": out.push("![" + (b.name || "") + "](" + encodeURI(src) + ")"); break;
      case "file": out.push("[" + (b.name || "file") + "](" + encodeURI(src) + ")"); break;
      case "table":
        var rows = b.rows;
        out.push("| " + rows[0].map(cellMd).join(" | ") + " |");
        out.push("|" + rows[0].map(function () { return " --- "; }).join("|") + "|");
        for (var r = 1; r < rows.length; r++) out.push("| " + rows[r].map(cellMd).join(" | ") + " |");
        break;
      default: out.push(mdInline(b.h));
    }
  }
  return out.join("\n") + "\n";
}
function cellMd(h) { return mdInline(h).replace(/\|/g, "\\|").replace(/\n/g, " "); }

function textOf(blocks) {
  var nums = numbering(blocks);
  return blocks.map(function (b, i) {
    var pad = "  ".repeat(b.l || 0);
    if (b.k === "check") return pad + (b.c ? "☑ " : "☐ ") + plain(b.h);
    if (b.k === "bullet") return pad + "• " + plain(b.h);
    if (b.k === "dash") return pad + "– " + plain(b.h);
    if (b.k === "number") return pad + nums[i] + ". " + plain(b.h);
    if (b.k === "table") return b.rows.map(function (r) { return r.map(plain).join("\t"); }).join("\n");
    if (b.k === "rule") return "———";
    if (b.k === "image" || b.k === "sketch" || b.k === "file") return "[" + (b.name || KINDS[b.k].label) + "]";
    return b.k === "mono" ? b.h : plain(b.h);
  }).join("\n");
}

// A whole note for a browser: its blocks in a page of their own.
function pageOf(title, blocks, base) {
  return "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>" + escape(title) + "</title>\n"
    + "<style>body{font-family:system-ui,sans-serif;max-width:46em;margin:3em auto;padding:0 1em;line-height:1.5}"
    + "img{max-width:100%}pre{background:#f2f2f2;padding:.8em;border-radius:6px;overflow:auto}"
    + "blockquote{border-left:3px solid #ccc;margin-left:0;padding-left:1em;color:#555}"
    + "li.checked{list-style:'\\2611  '}li.unchecked{list-style:'\\2610  '}td{border:1px solid #ccc}</style>\n"
    + "</head><body>\n" + htmlOf(blocks, base) + "\n</body></html>\n";
}

// ── NUMBERS AND FOLDS ────────────────────────────────────────────────────
// A numbered item's number: counted along its run at its own level, a
// deeper item between not breaking the count, anything shallower or not a
// list starting it again.
function numbering(blocks) {
  var out = [];
  var counts = [];
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i];
    if (!isList(b)) { counts = []; out.push(0); continue; }
    var l = b.l || 0;
    counts.length = Math.min(counts.length, l + 1);
    if (b.k === "number") {
      counts[l] = (counts[l] || 0) + 1;
      out.push(counts[l]);
    } else {
      counts[l] = 0;
      out.push(0);
    }
  }
  return out;
}

// Which blocks a folded heading has put away: everything after it up to
// the next heading of its rank or above.
function hidden(blocks) {
  var out = [];
  var fold = 99;
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i];
    if (isHeading(b) && rank(b) <= fold) fold = 99;
    out.push(fold < 99);
    if (isHeading(b) && b.fold && fold === 99) fold = rank(b);
  }
  return out;
}
// can this heading fold — is there anything under it?
function foldable(blocks, i) {
  var b = blocks[i];
  if (!isHeading(b)) return false;
  var n = blocks[i + 1];
  return !!n && !(isHeading(n) && rank(n) <= rank(b));
}

// ── TYPED SHORTCUTS ──────────────────────────────────────────────────────
// What a line becomes when it starts like Markdown: "- " a dashed list,
// "* " bullets, "1. " numbers, "[] " a checklist, "# " a heading… `lead` is
// the block's plain text up to the caret, just after a space was typed.
var SHORTCUTS = [
  [/^[-–—] $/, "dash"], [/^[*•] $/, "bullet"], [/^1[.)] $/, "number"],
  [/^\[ ?\] $/, "check"], [/^- \[ ?\] $/, "check"], [/^\[[xX]\] $/, "check", true],
  [/^# $/, "title"], [/^## $/, "heading"], [/^### $/, "subheading"],
  [/^> $/, "quote"], [/^``` ?$/, "mono"]
];
function shortcut(lead) {
  for (var i = 0; i < SHORTCUTS.length; i++)
    if (SHORTCUTS[i][0].test(lead)) return { k: SHORTCUTS[i][1], cut: lead.length, c: !!SHORTCUTS[i][2] };
  return null;
}

// ── WHAT A NOTE IS, AT A GLANCE ──────────────────────────────────────────
// Worked out once per change and kept on the note as `d`: the list, the
// search and the sidebar read these, never the blocks.
var TAG_RE = /(^|[\s(])#([A-Za-z0-9_À-￿][A-Za-z0-9_\-\/À-￿]*)/g;

function tagsOf(text) {
  var out = [];
  var m;
  TAG_RE.lastIndex = 0;
  while ((m = TAG_RE.exec(text)) !== null) {
    var t = m[2].replace(/[-\/]+$/, "");
    if (/^\d+$/.test(t)) continue;
    if (out.indexOf(t.toLowerCase()) < 0) out.push(t.toLowerCase());
  }
  return out;
}

function derive(n) {
  if (!n.blocks) {
    return { title: n.name || n.title || "Locked note", preview: "", text: "", tags: [], words: 0, chars: 0,
             checks: 0, done: 0, images: [], files: 0, table: false, sketch: false, links: [] };
  }
  var bs = n.blocks;
  var title = "", rest = [], all = [], images = [], files = 0, table = false, sketch = false;
  var checks = 0, done = 0, links = [];
  for (var i = 0; i < bs.length; i++) {
    var b = bs[i];
    if (b.k === "image" || b.k === "sketch") { images.push(b.src); if (b.k === "sketch") sketch = true; }
    if (b.k === "file") files++;
    if (b.k === "check") { checks++; if (b.c) done++; }
    var t = b.k === "table" ? b.rows.map(function (r) { return r.map(plain).join(" "); }).join(" ")
      : b.k === "mono" ? b.h : b.k === "image" && b.ocr ? b.ocr : plain(b.h);
    if (b.k === "table") table = true;
    var lm, lre = /href="clio:note\/([^"]+)"/g;
    while ((lm = lre.exec(b.h || "")) !== null) if (links.indexOf(lm[1]) < 0) links.push(lm[1]);
    all.push(t);
    if (t.trim() === "") continue;
    if (title === "" && isText(b)) title = t.trim().split("\n")[0];
    else if (b.k !== "image") rest.push(t.trim().replace(/\s+/g, " "));
  }
  var text = all.join("\n");
  // (no \p{L}: QML's engine takes it and matches nothing)
  var words = (text.match(/\S+/g) || []).filter(function (w) { return /[A-Za-z0-9\u00C0-\uFFFF]/.test(w); }).length;
  return {
    title: (n.name || title).slice(0, 200),
    preview: rest.join("  ").slice(0, 240),
    text: text,
    tags: tagsOf(text),
    words: words,
    chars: text.replace(/\s/g, "").length,
    checks: checks, done: done,
    images: images, files: files, table: table, sketch: sketch, links: links
  };
}

// ── RECENT ──
// The notes and entries last written or opened (`seen`: id → when), the
// latest day first: the sidebar's Recent. Nothing in the Trash, nothing empty
// and never opened since it was made.
function recent(notes, seen, k) {
  var out = [];
  for (var i = 0; i < notes.length; i++) {
    var n = notes[i];
    if (n.deleted || (n.kind !== "note" && n.kind !== "entry")) continue;
    var at = n.modified || 0;
    if (!at) continue;
    if (n.blocks && (n.d ? n.d.text : derive(n).text).trim() === "") continue;
    out.push({ n: n, at: at });
  }
  // by when each was last EDITED, newest first (user, 2026-10-14): not by
  // day, not by being opened — choosing a row never moves it, writing in
  // one brings it to the top
  out.sort(function (a, b) { return b.at - a.at; });
  return out.slice(0, k || 5);
}

function titleOf(n, untitled) {
  var t = n.d ? n.d.title : derive(n).title;
  return t !== "" ? t : (untitled || (n.kind === "entry" ? "" : "New Note"));
}

// ── SEARCH ───────────────────────────────────────────────────────────────
// Every word somewhere — the title counting most. And Apple's search tokens,
// typed: #tag, is:pinned, is:locked, has:checklist, has:picture, has:file,
// has:table, has:sketch, is:done (every box ticked), is:todo; and when:
// edited:today, edited:week, edited:month, edited:year, edited:7d (any
// number of days), the same for created: (a smart container's rules).
function terms(query) {
  var words = [], filters = [];
  String(query || "").toLowerCase().split(/\s+/).forEach(function (w) {
    if (w === "") return;
    if (/^#./.test(w) || /^(is|has|edited|created):./.test(w)) filters.push(w);
    else words.push(w);
  });
  return { words: words, filters: filters };
}

// how far back a when-rule reaches, in days (today: since midnight)
function sinceOf(v, now) {
  if (v === "today") return dayStart(now);
  var days = v === "week" ? 7 : v === "month" ? 30 : v === "year" ? 365 : /^\d+d$/.test(v) ? parseInt(v, 10) : -1;
  return days < 0 ? -1 : now - days * 86400000;
}
function passes(n, f, now) {
  var d = n.d || derive(n);
  if (f[0] === "#") return d.tags.indexOf(f.slice(1)) >= 0;
  var when = f.match(/^(edited|created):(.+)$/);
  if (when) {
    var since = sinceOf(when[2], now || Date.now());
    return since < 0 || (when[1] === "edited" ? n.modified : n.created) >= since;
  }
  switch (f) {
    case "is:pinned": return !!n.pinned;
    case "is:locked": return !!n.sealed || !!n.locked;
    case "is:bookmarked": return !!n.bookmark;
    case "is:done": return d.checks > 0 && d.done === d.checks;
    case "is:todo": return d.checks > d.done;
    case "has:checklist": return d.checks > 0;
    case "has:picture": case "has:image": case "has:photo": return d.images.length > 0;
    case "has:file": case "has:attachment": return d.files > 0 || d.images.length > 0;
    case "has:table": return d.table;
    case "has:sketch": case "has:drawing": return d.sketch;
    case "has:link": return /href="/.test(JSON.stringify(n.blocks || []));
    case "has:mood": return !!n.mood;
    case "has:highlight": return /background-color:\s*#01c11/i.test(JSON.stringify(n.blocks || []));
  }
  return true;
}

// 0: not a match; higher is better
function score(n, t) {
  for (var i = 0; i < t.filters.length; i++) if (!passes(n, t.filters[i])) return 0;
  if (t.words.length === 0) return 1;
  var d = n.d || derive(n);
  var title = d.title.toLowerCase(), body = d.text.toLowerCase();
  var s = 1;
  for (var w = 0; w < t.words.length; w++) {
    var q = t.words[w];
    var at = title.indexOf(q);
    if (at === 0) s += 40;
    else if (at > 0) s += 20;
    else if (body.indexOf(q) >= 0) s += 5;
    else if (d.tags.indexOf(q) >= 0) s += 5;
    else return 0;
  }
  return s;
}

// ── THE LIST ─────────────────────────────────────────────────────────────
// `scope`: { shelf: "all" | "trash" | "folder" | "tag" | "smart", id }.
// Pinned first (unless searching or in the trash), then by the sort:
// "modified", "created" or "title".
function shelve(notes, scope, query, sort, folders) {
  scope = scope || { shelf: "all" };
  var t = terms(query);
  var inTrash = scope.shelf === "trash";
  var fold = scope.shelf === "folder" ? subfolders(folders || [], scope.id) : null;
  var smart = scope.shelf === "smart" ? (folders || []).filter(function (f) { return f.id === scope.id; })[0] : null;
  var st = smart ? terms(smart.query || "") : null;
  var rows = [];
  for (var i = 0; i < notes.length; i++) {
    var n = notes[i];
    if (n.kind !== "note") continue;
    if (inTrash !== (n.deleted > 0)) continue;
    if (fold && fold.indexOf(n.folder) < 0) continue;
    if (scope.shelf === "tag" && (n.d || derive(n)).tags.indexOf(scope.id) < 0) continue;
    if (st && score(n, st) === 0) continue;
    var s = score(n, t);
    if (s === 0) continue;
    rows.push({ n: n, s: s });
  }
  var searching = t.words.length > 0;
  rows.sort(function (a, b) {
    if (searching && a.s !== b.s) return b.s - a.s;
    if (!inTrash && !!a.n.pinned !== !!b.n.pinned) return a.n.pinned ? -1 : 1;
    return compare(a.n, b.n, sort);
  });
  return rows.map(function (r) { return r.n; });
}

function compare(a, b, sort) {
  if (sort === "title") {
    var c = titleOf(a).localeCompare(titleOf(b), undefined, { sensitivity: "base", numeric: true });
    return c !== 0 ? c : b.modified - a.modified;
  }
  if (sort === "created") return b.created - a.created;
  return b.modified - a.modified;
}

// a container and every container under it
function subfolders(folders, id) {
  var out = [id];
  for (var grew = true; grew;) {
    grew = false;
    for (var i = 0; i < folders.length; i++) {
      var f = folders[i];
      if (!f.query && out.indexOf(f.parent || "") >= 0 && out.indexOf(f.id) < 0 && f.id !== "") { out.push(f.id); grew = true; }
    }
  }
  return out;
}

// The containers as the sidebar lists them: each under its parent, with how
// deep it sits and how many notes it holds (its own and its children's).
// `shut`: containers folded in the sidebar — their children are left out.
function folderRows(folders, notes, shut) {
  var counts = {};
  for (var i = 0; i < notes.length; i++) {
    var n = notes[i];
    if (n.kind === "note" && !n.deleted) counts[n.folder || ""] = (counts[n.folder || ""] || 0) + 1;
  }
  var plain_ = folders.filter(function (f) { return !f.query; });
  var out = [];
  function walk(parent, depth) {
    var kids = plain_.filter(function (f) { return (f.parent || "") === parent; })
      .sort(function (a, b) { return a.name.localeCompare(b.name, undefined, { sensitivity: "base", numeric: true }); });
    for (var k = 0; k < kids.length; k++) {
      var f = kids[k];
      var all = subfolders(plain_, f.id);
      var count = 0;
      for (var j = 0; j < all.length; j++) count += counts[all[j]] || 0;
      var has = plain_.some(function (x) { return x.parent === f.id; });
      out.push({ id: f.id, name: f.name, depth: depth, count: count, kids: has, shut: !!(shut && shut[f.id]) });
      if (!(shut && shut[f.id])) walk(f.id, depth + 1);
    }
  }
  walk("", 0);
  return out;
}

// would moving `id` under `parent` put it inside itself?
function wouldLoop(folders, id, parent) {
  return subfolders(folders, id).indexOf(parent) >= 0;
}

function tagRows(notes) {
  var c = {};
  for (var i = 0; i < notes.length; i++) {
    var n = notes[i];
    if (n.deleted || !n.d) continue;
    for (var j = 0; j < n.d.tags.length; j++) c[n.d.tags[j]] = (c[n.d.tags[j]] || 0) + 1;
  }
  return Object.keys(c).sort().map(function (k) { return { name: k, count: c[k] }; });
}

// ── DATES ────────────────────────────────────────────────────────────────
var MONTHS = ["January", "February", "March", "April", "May", "June", "July",
              "August", "September", "October", "November", "December"];
var DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function dayStart(ms) { var d = new Date(ms); d.setHours(0, 0, 0, 0); return d.getTime(); }
function dayKey(ms) { var d = new Date(ms); return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate(); }
function daysBetween(a, b) { return Math.round((dayStart(b) - dayStart(a)) / 86400000); }

// The list's headings, as Apple's: Today, Yesterday, Previous 7 Days,
// Previous 30 Days, then the months of this year, then the years.
function sectionOf(n, sort, now) {
  if (sort === "title") return "";
  var ms = sort === "created" ? n.created : n.modified;
  if (!ms) return "Undated";
  var ago = daysBetween(ms, now);
  if (ago <= 0) return "Today";
  if (ago === 1) return "Yesterday";
  if (ago < 7) return "Previous 7 Days";
  if (ago < 30) return "Previous 30 Days";
  var d = new Date(ms), t = new Date(now);
  if (d.getFullYear() === t.getFullYear()) return MONTHS[d.getMonth()];
  return String(d.getFullYear());
}

function two(n) { return n < 10 ? "0" + n : String(n); }
function clock(ms) { var d = new Date(ms); return two(d.getHours()) + ":" + two(d.getMinutes()); }

// A date as short as it can be and still be read: the time today, the
// weekday this week, the day and month this year, the full date before.
// a day as the sidebar's Recent says it: Today, Yesterday, a weekday this
// week, a date before
function dayShort(ms, now) {
  if (!ms) return "";
  var ago = daysBetween(ms, now);
  return ago <= 0 ? "Today" : dateShort(ms, now);
}
function dateShort(ms, now) {
  if (!ms) return "";
  var ago = daysBetween(ms, now);
  var d = new Date(ms);
  if (ago <= 0) return clock(ms);
  if (ago === 1) return "Yesterday";
  if (ago < 7) return DAYS[d.getDay()];
  if (d.getFullYear() === new Date(now).getFullYear()) return d.getDate() + " " + MONTHS[d.getMonth()].slice(0, 3);
  return d.getDate() + " " + MONTHS[d.getMonth()].slice(0, 3) + " " + d.getFullYear();
}

function dateLong(ms) {
  var d = new Date(ms);
  return DAYS[d.getDay()] + ", " + d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear();
}
function dateTime(ms) { return dateLong(ms) + " at " + clock(ms); }

// ── THE JOURNAL ──────────────────────────────────────────────────────────
// Entries, newest first, by their own date (an entry can be about another
// day than the one it was written on). Filters as Apple's: bookmarked,
// with photos, with a mood, a reflection; a day picked on the calendar.
function entries(notes, journal, opts) {
  opts = opts || {};
  var t = terms(opts.query || "");
  var out = [];
  for (var i = 0; i < notes.length; i++) {
    var n = notes[i];
    if (n.kind !== "entry" || n.deleted) continue;
    if (journal && n.journal !== journal) continue;
    if (opts.day && dayKey(n.date) !== opts.day) continue;
    var f = opts.filter || "";
    if (f === "bookmarked" && !n.bookmark) continue;
    if (f === "photos" && !(n.d && n.d.images.length)) continue;
    if (f === "mood" && !n.mood) continue;
    if (f === "reflection" && !n.prompt) continue;
    if (score(n, t) === 0) continue;
    out.push(n);
  }
  out.sort(function (a, b) { return b.date - a.date || b.created - a.created; });
  return out;
}

// The heading over a run of entries: the month, and the year once it is
// not this one.
function entrySection(n, now) {
  var d = new Date(n.date), t = new Date(now);
  return MONTHS[d.getMonth()] + (d.getFullYear() === t.getFullYear() ? "" : " " + d.getFullYear());
}

// Insights: the streak (days in a row with an entry, ending today or
// yesterday — a streak is not broken until a whole day is missed), the
// longest, this year's entries, words written, days written on.
function insights(list, now) {
  var days = {};
  var words = 0, year = 0, thisYear = new Date(now).getFullYear();
  for (var i = 0; i < list.length; i++) {
    var n = list[i];
    days[dayKey(n.date)] = (days[dayKey(n.date)] || 0) + 1;
    words += n.d ? n.d.words : 0;
    if (new Date(n.date).getFullYear() === thisYear) year++;
  }
  var streak = 0;
  var t = dayStart(now);
  if (!days[dayKey(t)]) t -= 86400000;
  while (days[dayKey(t)]) { streak++; t = dayStart(t - 43200000); }
  var keys = Object.keys(days).map(function (k) { var p = k.split("-"); return new Date(+p[0], +p[1] - 1, +p[2]).getTime(); })
    .sort(function (a, b) { return a - b; });
  var longest = 0, run = 0, prev = 0;
  for (var j = 0; j < keys.length; j++) {
    run = prev && daysBetween(prev, keys[j]) === 1 ? run + 1 : 1;
    longest = Math.max(longest, run);
    prev = keys[j];
  }
  return { streak: streak, longest: longest, year: year, words: words, days: days, total: list.length,
           daysWritten: keys.length };
}

// A month laid out as weeks, Monday first: each cell { day, key, out } —
// `out` for the days of the months either side that fill its first and
// last weeks.
function monthGrid(year, month) {
  var first = new Date(year, month, 1);
  var lead = (first.getDay() + 6) % 7;
  var start = new Date(year, month, 1 - lead);
  var cells = [];
  for (var i = 0; i < 42; i++) {
    var d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
    if (i >= 35 && d.getMonth() !== month) break;
    cells.push({ day: d.getDate(), key: dayKey(d.getTime()), ms: d.getTime(), out: d.getMonth() !== month });
  }
  return cells;
}

// ── MOODS ────────────────────────────────────────────────────────────────
// How it felt, as Apple's State of Mind: a place on a scale from very
// unpleasant to very pleasant, and the words for it.
var MOODS = [
  { v: -3, label: "Very Unpleasant", ink: "magenta" },
  { v: -2, label: "Unpleasant", ink: "blue" },
  { v: -1, label: "Slightly Unpleasant", ink: "cyan" },
  { v: 0, label: "Neutral", ink: "muted" },
  { v: 1, label: "Slightly Pleasant", ink: "green" },
  { v: 2, label: "Pleasant", ink: "sand" },
  { v: 3, label: "Very Pleasant", ink: "yellow" }
];
var FEELINGS = {
  "-3": ["Angry", "Anxious", "Scared", "Overwhelmed", "Ashamed", "Disgusted", "Hopeless", "Jealous"],
  "-2": ["Annoyed", "Frustrated", "Worried", "Sad", "Lonely", "Stressed", "Guilty", "Disappointed"],
  "-1": ["Discouraged", "Irritated", "Drained", "Embarrassed", "Insecure", "Uneasy", "Bored", "Tired"],
  "0": ["Indifferent", "Calm", "Content", "Peaceful", "Thoughtful", "Steady", "Quiet", "Okay"],
  "1": ["Relieved", "Satisfied", "Hopeful", "Amused", "Grateful", "Rested", "Curious", "Focused"],
  "2": ["Happy", "Proud", "Confident", "Brave", "Joyful", "Loved", "Inspired", "Motivated"],
  "3": ["Amazed", "Excited", "Passionate", "Thrilled", "Ecstatic", "Delighted", "Elated", "Grateful"]
};
// and what it was about
var ABOUT = ["Health", "Fitness", "Self-care", "Hobbies", "Identity", "Spirituality", "Community",
             "Family", "Friends", "Partner", "Dating", "Tasks", "Work", "Education", "Travel",
             "Weather", "Current Events", "Money"];

function cleanMood(m) {
  if (!m || typeof m !== "object") return null;
  var v = Math.round(Number(m.v));
  if (isNaN(v) || v < -3 || v > 3) return null;
  var words = Array.isArray(m.words) ? m.words.map(String).slice(0, 8) : [];
  var about = Array.isArray(m.about) ? m.about.map(String).slice(0, 8) : [];
  return { v: v, words: words, about: about };
}
function moodOf(v) { for (var i = 0; i < MOODS.length; i++) if (MOODS[i].v === v) return MOODS[i]; return MOODS[3]; }

// ── REFLECTIONS ──────────────────────────────────────────────────────────
// What to write about, when nothing comes: a question, a different one each
// day (the day picks it, so it holds still while you think), and more on
// asking.
var PROMPTS = [
  "What made you smile today?",
  "Describe a moment this week you would like to remember.",
  "What is something you are looking forward to?",
  "Who helped you recently, and how?",
  "What did you learn today that surprised you?",
  "What would make tomorrow a good day?",
  "Write about a place where you feel completely at ease.",
  "What is a small win you have not given yourself credit for?",
  "What has been taking up most of your thoughts lately?",
  "Describe your day in five words, then explain one of them.",
  "What is something you changed your mind about?",
  "Which conversation from this week stays with you?",
  "What are you grateful for right now, in this room?",
  "What drained your energy today, and what gave it back?",
  "If this week had a title, what would it be?",
  "What is a habit you would like to start, and why now?",
  "Write a letter to yourself a year from today.",
  "What did you do today just for you?",
  "Describe a sound, a smell or a taste from today.",
  "What is a challenge you are facing, and what is one step forward?",
  "Who do you miss, and what would you tell them?",
  "What made you feel proud recently?",
  "What is something beautiful you noticed this week?",
  "When did you last lose track of time? What were you doing?",
  "What would you tell a friend who felt the way you feel today?",
  "What is one thing you would like to let go of?",
  "Write about a book, song or film that moved you lately.",
  "What does a perfect ordinary day look like for you?",
  "What are three things that went well today?",
  "What question are you living with right now?",
  "What is a memory that still makes you laugh?",
  "Where did you feel most like yourself today?",
  "What are you avoiding, and what would happen if you did it?",
  "Describe someone you admire in a few sentences.",
  "What did your body need today?",
  "What is something you are curious about?",
  "What surprised you about how you reacted today?",
  "Write about the view from where you are sitting.",
  "What has changed in your life over the past year?",
  "What is a kindness you received or gave this week?"
];
function promptOfDay(ms, offset) {
  var n = Math.floor(dayStart(ms) / 86400000) + (offset || 0);
  return PROMPTS[((n % PROMPTS.length) + PROMPTS.length) % PROMPTS.length];
}

// ── MATH ─────────────────────────────────────────────────────────────────
// A line ending in "=" is a sum to work out (Apple's Math Notes): its
// expression is what comes after the last ":" (or the line's start), and a
// name given a value on an earlier line ("rent = 1200") stands for it.
function mathAsk(line, earlier) {
  var m = String(line).match(/^(.*?)\s*=\s*$/);
  if (!m) return null;
  var expr = m[1];
  var colon = expr.lastIndexOf(":");
  if (colon >= 0) expr = expr.slice(colon + 1);
  expr = expr.trim();
  if (expr === "" || !/[\d)]/.test(expr) && !earlier) return null;
  // a definition is not a sum
  if (/^[A-Za-z_][\w ]*$/.test(expr) && !(earlier && earlier[expr.trim()])) return null;
  var vars = earlier || {};
  var names = Object.keys(vars).sort(function (a, b) { return b.length - a.length; });
  for (var i = 0; i < names.length; i++) {
    var re = new RegExp("(^|[^A-Za-z_])" + names[i].replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "(?![A-Za-z_])", "g");
    expr = expr.replace(re, "$1(" + vars[names[i]] + ")");
  }
  if (!/\d/.test(expr)) return null;
  return expr;
}
// names given values on lines like "rent = 1200" or "tax = rent * 0.2"
function mathVars(lines) {
  var vars = {};
  for (var i = 0; i < lines.length; i++) {
    var m = String(lines[i]).match(/^\s*([A-Za-z_][A-Za-z_ ]{0,30}?)\s*=\s*([^=]+?)\s*$/);
    if (!m) continue;
    var v = mathAsk(m[2] + "=", vars);
    if (v) vars[m[1].trim()] = v;
  }
  return vars;
}

// ── KEEPING FOLDERS AND JOURNALS ─────────────────────────────────────────
function cleanMeta(m) {
  m = m && typeof m === "object" ? m : {};
  var folders = (Array.isArray(m.folders) ? m.folders : []).filter(function (f) { return f && f.id && f.name; })
    .map(function (f) {
      var o = { id: String(f.id), name: String(f.name), parent: String(f.parent || "") };
      if (f.query) o.query = String(f.query);
      return o;
    });
  var journals = (Array.isArray(m.journals) ? m.journals : []).filter(function (j) { return j && j.id && j.name; })
    .map(function (j) { return { id: String(j.id), name: String(j.name), hue: String(j.hue || "cyan"), locked: !!j.locked }; });
  if (journals.length === 0) journals.push({ id: "journal", name: "Journal", hue: "cyan", locked: false });
  // templates: a name and blocks (no pictures or files — see templateOf)
  var templates = (Array.isArray(m.templates) ? m.templates : []).filter(function (t) { return t && t.id && t.name; })
    .map(function (t) {
      return { id: String(t.id), name: String(t.name),
               blocks: (Array.isArray(t.blocks) ? t.blocks : []).map(cleanBlock).filter(function (b) { return !!b; }) };
    });
  // the template a day's journal entry starts from ("" none)
  var daily = String(m.daily || "");
  if (!templates.some(function (t) { return t.id === daily; })) daily = "";
  // words taught to the spelling (Learn Spelling), with the notebook so
  // another machine knows them too
  var learned = (Array.isArray(m.learned) ? m.learned : []).map(String).filter(function (w) { return w !== "" && w.length <= 60; });
  return { folders: folders, journals: journals, templates: templates, daily: daily, learned: learned };
}

// a name not yet taken among `names`: "New Container", "New Container 2"…
function freeName(base, names) {
  var lower = names.map(function (n) { return String(n).toLowerCase(); });
  if (lower.indexOf(base.toLowerCase()) < 0) return base;
  for (var i = 2; ; i++) if (lower.indexOf((base + " " + i).toLowerCase()) < 0) return base + " " + i;
}

// A file name for an export: the title, made safe, not empty.
function fileName(title, ext) {
  var s = String(title || "").replace(/[\/\\:*?"<>|\u0000-\u001f]/g, " ").replace(/\s+/g, " ").trim().slice(0, 80);
  return (s === "" ? "Note" : s) + "." + ext;
}

// The size of a file, said.
function sizeText(n) {
  n = Number(n) || 0;
  if (n < 1024) return n + " B";
  if (n < 1048576) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + " KB";
  if (n < 1073741824) return (n / 1048576).toFixed(1) + " MB";
  return (n / 1073741824).toFixed(1) + " GB";
}

// a run of inline markup made from plain text (a typed table cell, a title)
function htmlOfText(t) { return escape(t).replace(/\n/g, "<br />"); }

// does a link point inside clio? its note's id, else ""
function noteLink(href) { var m = String(href || "").match(/^clio:note\/(.+)$/); return m ? m[1] : ""; }

// ── SKETCHES ─────────────────────────────────────────────────────────────
// A sketch is its strokes, kept by color NAME and in coordinates scaled to
// its width (x, y in 0..1 of the width) — drawn afresh at any size, in the
// theme of the moment. `ink(name)` gives the color.
//   strokes: [{ c: "ink" | a hue name, w: width as a share of the width,
//               hl: a highlighter (wide, see-through), p: [[x, y]…] }]
function paintStrokes(ctx, strokes, width, ink) {
  for (var i = 0; i < (strokes || []).length; i++) {
    var s = strokes[i];
    var p = s.p || [];
    if (p.length === 0) continue;
    ctx.save();
    ctx.globalAlpha = s.hl ? 0.35 : 1;
    ctx.strokeStyle = ink(s.c);
    ctx.fillStyle = ink(s.c);
    ctx.lineWidth = Math.max(1, (s.w || 0.006) * width);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.beginPath();
    if (p.length === 1) {
      ctx.arc(p[0][0] * width, p[0][1] * width, ctx.lineWidth / 2, 0, Math.PI * 2);
      ctx.fill();
    } else {
      ctx.moveTo(p[0][0] * width, p[0][1] * width);
      // through the midpoints: a curve, not a polyline
      for (var j = 1; j < p.length - 1; j++) {
        var mx = (p[j][0] + p[j + 1][0]) / 2 * width, my = (p[j][1] + p[j + 1][1]) / 2 * width;
        ctx.quadraticCurveTo(p[j][0] * width, p[j][1] * width, mx, my);
      }
      ctx.lineTo(p[p.length - 1][0] * width, p[p.length - 1][1] * width);
      ctx.stroke();
    }
    ctx.restore();
  }
}
// strokes thinned as they are kept: points closer than a pixel's worth dropped
function thin(points, minStep) {
  var out = [];
  for (var i = 0; i < points.length; i++) {
    var q = points[i];
    var last = out[out.length - 1];
    if (!last || Math.abs(q[0] - last[0]) + Math.abs(q[1] - last[1]) >= minStep || i === points.length - 1)
      out.push([Math.round(q[0] * 10000) / 10000, Math.round(q[1] * 10000) / 10000]);
  }
  return out;
}

// ── TEMPLATES ────────────────────────────────────────────────────────────
// A note kept to start others from: its words, lists, tables and dividers,
// without its pictures and files (those belong to the note they are in).
// {date} {weekday} {time} {day} {month} {year} are filled in when used.
function templateOf(blocks) {
  return (blocks || []).filter(function (b) { return !b.src; }).map(function (b) {
    var o = JSON.parse(JSON.stringify(b));
    delete o._key; delete o.due; delete o.fold;
    if (o.k === "check") o.c = false;
    return o;
  });
}
// A Markdown (or plain text) file as blocks — markdownOf read back: what it
// writes, this reads; pictures and files are left out as templateOf does.
function mdRun(s) {
  var codes = [];
  var t = escape(s).replace(/`([^`]+)`/g, function (m, c) { codes.push(c); return "\u0000" + (codes.length - 1) + "\u0000"; });
  t = t.replace(/!\[[^\]]*\]\([^)]*\)/g, "")
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>')
    .replace(/\*\*([^*]+)\*\*|__([^_]+)__/g, function (m, a, b) { return "<b>" + (a || b) + "</b>"; })
    .replace(/(^|[^*\w])\*([^*\s][^*]*?)\*(?!\*)/g, "$1<i>$2</i>")
    .replace(/(^|[^_\w])_([^_\s][^_]*?)_(?!\w)/g, "$1<i>$2</i>")
    .replace(/~~([^~]+)~~/g, "<s>$1</s>");
  return t.replace(/\u0000(\d+)\u0000/g, function (m, i) { return codes[+i]; });
}
function blocksOfMarkdown(text) {
  var lines = String(text || "").replace(/\r\n?/g, "\n").split("\n");
  var out = [];
  var para = null;
  var endPara = function () { para = null; };
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    var m;
    if (/^\s*```/.test(line)) {
      var code = [];
      for (i++; i < lines.length && !/^\s*```/.test(lines[i]); i++) code.push(lines[i]);
      out.push(block("mono", code.join("\n"))); endPara(); continue;
    }
    if (/^\s*$/.test(line)) { endPara(); continue; }
    if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) { out.push(block("rule", "")); endPara(); continue; }
    if ((m = line.match(/^(#{1,6})\s+(.*?)\s*#*\s*$/))) {
      out.push(block(m[1].length === 1 ? "title" : m[1].length === 2 ? "heading" : "subheading", mdRun(m[2]))); endPara(); continue;
    }
    if (/^\s*\|.*\|\s*$/.test(line)) {
      var rows = [];
      for (; i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i]); i++) {
        if (/^\s*\|(\s*:?-+:?\s*\|)+\s*$/.test(lines[i])) continue;
        rows.push(lines[i].trim().slice(1, -1).replace(/\\\|/g, "\u0001").split("|").map(function (c) { return mdRun(c.trim().replace(/\u0001/g, "|")); }));
      }
      i--;
      var w = Math.max.apply(null, rows.map(function (r) { return r.length; }));
      rows.forEach(function (r) { while (r.length < w) r.push(""); });
      out.push(block("table", "", { rows: rows })); endPara(); continue;
    }
    if ((m = line.match(/^>\s?(.*)$/))) {
      var last = out[out.length - 1];
      if (para && last && last.k === "quote") last.h += "<br />" + mdRun(m[1]);
      else { out.push(block("quote", mdRun(m[1]))); para = out[out.length - 1]; }
      continue;
    }
    if ((m = line.match(/^(\s*)(?:[-*+]|\d+[.)])\s+\[([ xX])\]\s+(.*)$/))) {
      out.push(block("check", mdRun(m[3]), { c: false, l: Math.floor(m[1].replace(/\t/g, "  ").length / 2) })); endPara(); continue;
    }
    if ((m = line.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/))) {
      var l = Math.floor(m[1].replace(/\t/g, "  ").length / 2);
      out.push(block(/\d/.test(m[2]) ? "number" : m[2] === "*" ? "bullet" : "dash", mdRun(m[3]), l ? { l: l } : null)); endPara(); continue;
    }
    // a paragraph: its lines run on, a line ending in two spaces breaks
    var run = mdRun(line.replace(/\s+$/, ""));
    var br = / {2,}$/.test(line);
    if (para && para.k === "body") para.h += (para._br ? "<br />" : " ") + run;
    else { out.push(block("body", run)); para = out[out.length - 1]; }
    para._br = br;
  }
  out.forEach(function (b) { delete b._br; if (b.k !== "mono" && b.k !== "table" && b.k !== "rule") b.h = inline(b.h); });
  return out;
}
function fillTemplate(blocks, ms) {
  var d = new Date(ms);
  var words = { date: dateLong(ms), weekday: DAYS[d.getDay()], time: clock(ms), day: String(d.getDate()),
                month: MONTHS[d.getMonth()], year: String(d.getFullYear()) };
  var fill = function (s) { return String(s || "").replace(/\{(date|weekday|time|day|month|year)\}/g, function (m, k) { return escape(words[k]); }); };
  return (blocks || []).map(function (b) {
    var o = JSON.parse(JSON.stringify(b));
    if (o.h) o.h = fill(o.h);
    if (o.rows) o.rows = o.rows.map(function (r) { return r.map(fill); });
    return o;
  });
}

// ── ON THIS DAY ──────────────────────────────────────────────────────────
// Entries written on this day of the month in earlier years, the nearest
// year first: { n, years } (years ago).
function onThisDay(entries, now) {
  var t = new Date(now), out = [];
  for (var i = 0; i < (entries || []).length; i++) {
    var n = entries[i];
    if (n.deleted || n.kind !== "entry") continue;
    var d = new Date(n.date);
    if (d.getMonth() !== t.getMonth() || d.getDate() !== t.getDate() || d.getFullYear() >= t.getFullYear()) continue;
    out.push({ n: n, years: t.getFullYear() - d.getFullYear() });
  }
  out.sort(function (a, b) { return a.years - b.years || b.n.date - a.n.date; });
  return out;
}

// ── REMINDERS ────────────────────────────────────────────────────────────
// When a checklist item's reminder is due, said briefly: "14:00" today,
// "Tomorrow 09:00", "Thu 18:00" within the week, "20 Oct 09:00" further.
function dueText(due, now) {
  var days = daysBetween(now, due), t = clock(due), d = new Date(due);
  if (days === 0) return t;
  if (days === 1) return "Tomorrow " + t;
  if (days === -1) return "Yesterday " + t;
  if (days > 1 && days < 7) return DAYS[d.getDay()].slice(0, 3) + " " + t;
  return d.getDate() + " " + MONTHS[d.getMonth()].slice(0, 3) + " " + t;
}
// The presets a reminder is set from, as times from `now`
function duePresets(now) {
  var d = new Date(now);
  var at = function (dayOff, h) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + dayOff, h, 0, 0, 0).getTime(); };
  var out = [{ label: "In an hour", due: now + 3600000 }];
  if (d.getHours() < 17) out.push({ label: "This evening", due: at(0, 18) });
  out.push({ label: "Tomorrow morning", due: at(1, 9) });
  var toMon = (8 - d.getDay()) % 7 || 7;
  out.push({ label: "Next week", due: at(toMon, 9) });
  return out;
}
// "2026-10-20 14:00", "20/10 14:00", "14:00" (today, or tomorrow once past),
// "tomorrow 9", "in 2 hours", "in 30 min" → ms, or 0 when it is not a time
function parseWhen(s, now) {
  s = String(s || "").trim().toLowerCase();
  var d = new Date(now), m;
  var hm = function (h, mi) { return [Math.min(23, +h), Math.min(59, +(mi || 0))]; };
  if ((m = s.match(/^in\s+(\d+)\s*(m|min|mins|minutes?|h|hrs?|hours?|d|days?)$/))) {
    var unit = m[2].charAt(0) === "m" ? 60000 : m[2].charAt(0) === "h" ? 3600000 : 86400000;
    return now + (+m[1]) * unit;
  }
  if ((m = s.match(/^(today|tomorrow)(?:\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?)?$/))) {
    var t = hm(m[2] !== undefined ? m[2] : 9, m[3]);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + (m[1] === "tomorrow" ? 1 : 0), t[0], t[1]).getTime();
  }
  if ((m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2})(?::(\d{2}))?)?$/))) {
    var a = hm(m[4] !== undefined ? m[4] : 9, m[5]);
    return new Date(+m[1], +m[2] - 1, +m[3], a[0], a[1]).getTime();
  }
  if ((m = s.match(/^(\d{1,2})\/(\d{1,2})(?:\s+(\d{1,2})(?::(\d{2}))?)?$/))) {
    var b = hm(m[3] !== undefined ? m[3] : 9, m[4]);
    var x = new Date(d.getFullYear(), +m[2] - 1, +m[1], b[0], b[1]).getTime();
    return x < now ? new Date(d.getFullYear() + 1, +m[2] - 1, +m[1], b[0], b[1]).getTime() : x;
  }
  if ((m = s.match(/^(\d{1,2}):(\d{2})$/))) {
    var c = hm(m[1], m[2]);
    var y = new Date(d.getFullYear(), d.getMonth(), d.getDate(), c[0], c[1]).getTime();
    return y <= now ? y + 86400000 : y;
  }
  return 0;
}
// every checklist item due by `now`, not ticked, not yet told: [{ id, key, h, due }]
// (`told`: "id|due|text" → true, kept by the manager)
function dueChecks(notes, now, told) {
  var out = [];
  for (var i = 0; i < (notes || []).length; i++) {
    var n = notes[i];
    if (n.deleted || !n.blocks) continue;
    for (var j = 0; j < n.blocks.length; j++) {
      var b = n.blocks[j];
      if (b.k !== "check" || b.c || !b.due || b.due > now) continue;
      var k = n.id + "|" + b.due + "|" + plain(b.h);
      if (told && told[k]) continue;
      out.push({ id: n.id, key: k, h: plain(b.h), due: b.due });
    }
  }
  return out;
}

// ── THE LAST DAYS, BY MOOD ───────────────────────────────────────────────
// [{ key, ms, wrote, mood }] for the `n` days ending today, oldest first:
// whether anything was written, and the day's mood (the mean of its entries'
// moods, rounded; null when none was logged).
function moodDays(entries, now, n) {
  var by = {};
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i];
    if (e.deleted) continue;
    var k = dayKey(e.date);
    var o = by[k] || (by[k] = { sum: 0, count: 0, wrote: true });
    if (e.mood && typeof e.mood.v === "number") { o.sum += e.mood.v; o.count++; }
  }
  var out = [];
  var t = dayStart(now);
  for (var d = n - 1; d >= 0; d--) {
    var ms = dayStart(t - d * 86400000 + 43200000);
    var key = dayKey(ms);
    var x = by[key];
    out.push({ key: key, ms: ms, wrote: !!x, mood: x && x.count ? Math.round(x.sum / x.count) : null });
  }
  return out;
}

// ── FROM YOUR JOURNAL ────────────────────────────────────────────────────
// One older entry brought back (a month or more ago), the same one all day
// and another tomorrow; null when there is none so old.
function resurface(entries, now) {
  var old = entries.filter(function (e) { return !e.deleted && !e.sealed && e.date < now - 30 * 86400000; });
  if (old.length === 0) return null;
  old.sort(function (a, b) { return a.date - b.date; });
  var k = dayKey(now), h = 0;
  for (var i = 0; i < k.length; i++) h = (h * 31 + k.charCodeAt(i)) % 1000003;
  return old[h % old.length];
}

// ── HIGHLIGHTS ───────────────────────────────────────────────────────────
// Every highlighted run in the notebook: [{ id, title, kind, text, marker,
// modified }], the newest note first. A sealed note keeps its own; a deleted
// one is not asked.
function highlights(notes) {
  var out = [];
  var re = /<span style="[^"]*background-color:\s*#01c1(1[0-9a-f])[^"]*">([\s\S]*?)<\/span>/gi;
  for (var i = 0; i < notes.length; i++) {
    var n = notes[i];
    if (n.deleted || n.sealed || n.kind === "sticky") continue;
    var bs = n.blocks || [];
    for (var j = 0; j < bs.length; j++) {
      var h = String(bs[j].h || "");
      if (h.indexOf("#01c11") < 0) continue;
      var m;
      re.lastIndex = 0;
      while ((m = re.exec(h)) !== null) {
        var t = plain(m[2]).replace(/\s+/g, " ").trim();
        if (t === "") continue;
        out.push({ id: n.id, title: titleOf(n), kind: n.kind, text: t,
                   marker: MARKERS[parseInt(m[1], 16) - 16] || "sand", modified: n.modified || 0 });
      }
    }
  }
  out.sort(function (a, b) { return b.modified - a.modified; });
  return out;
}

// ── BACKLINKS ────────────────────────────────────────────────────────────
// the notes that link to note `id` (with >>), the newest first
function linksTo(notes, id) {
  return (notes || []).filter(function (n) { return !n.deleted && n.id !== id && n.d && n.d.links && n.d.links.indexOf(id) >= 0; })
    .sort(function (a, b) { return b.modified - a.modified; });
}
