// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ALEXANDRIA'S LIBRARY — everything about fonts that is not drawing: what
// fontconfig says is installed, folded into families; a face's characters
// (its charset) as an index a grid can walk; the names of those characters
// (Unicode's, and Nerd Fonts' for the private use area); the search over
// them; and the shell text that installs and removes a font. Tests in
// oracle/tests/alexandria.js.

// ── WHAT IS INSTALLED ─────────────────────────────────────────────────────
// One face a line. family[0] / style[0]: the first of fontconfig's names is
// the one the font calls itself in English.
.pragma library
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file — every row, tile, card and sheet — evaluated all of
// it again; a profile caught terminus.js and icons.js costing hundreds of ms
// that way (qmlprofiler, 2026-10-09).

const LIST_FORMAT = "%{family[0]}\\t%{style[0]}\\t%{file}\\t%{weight}\\t%{slant}\\t%{spacing}\\t%{fontformat}\\t%{index}\\n";

function listCommand() {
  return "fc-list --format '" + LIST_FORMAT.replace(/\\\\/g, "\\") + "'";
}

// fontconfig's weight scale (thin 0 … regular 80, medium 100, semibold 180,
// bold 200, black 210) as a CSS weight, 100–900.
function cssWeight(fc) {
  const w = Number(fc);
  if (isNaN(w)) return 400;
  if (w < 20) return 100;
  if (w < 45) return 200;
  if (w < 62) return 300;
  if (w < 90) return 400;
  if (w < 140) return 500;
  if (w < 190) return 600;
  if (w < 203) return 700;
  if (w < 208) return 800;
  return 900;
}

const WEIGHT_NAMES = { 100: "Thin", 200: "ExtraLight", 300: "Light", 400: "Regular", 500: "Medium",
                       600: "SemiBold", 700: "Bold", 800: "ExtraBold", 900: "Black" };
function weightName(css) { return WEIGHT_NAMES[css] || String(css); }

// Where a user's own fonts live: the ones Alexandria installs, and the only
// ones it will remove (the rest belong to pacman).
function userDirs(home) { return [home + "/.local/share/fonts/", home + "/.fonts/"]; }
function isUserFile(file, home) {
  return userDirs(home).some((d) => String(file).indexOf(d) === 0);
}
function installDir(home) { return home + "/.local/share/fonts"; }

// fc-list's lines → families, by name, each with its styles, lightest first.
// `familyOf` folds a name into the family it belongs to — oracle's, which
// makes JetBrainsMono Nerd Font Mono and Propo one family, as oracle's Font
// list does (pass x => x to keep every name apart).
function parseList(text, home, familyOf) {
  const fold = familyOf || ((x) => x);
  const by = {};
  const seenFace = {};
  for (const line of String(text || "").split("\n")) {
    const f = line.split("\t");
    if (f.length < 3 || f[0].trim() === "" || f[2].trim() === "") continue;
    const raw = f[0].split(",")[0].trim();
    const name = fold(raw) || raw;
    const file = f[2].trim();
    const idx = Number(f[7]) || 0;
    // a variable font is listed once per named instance; a file + index +
    // style is one face
    const key = file + "#" + idx + "#" + f[1];
    if (seenFace[key]) continue;
    seenFace[key] = true;
    const fam = by[name] || (by[name] = { name: name, variants: [], styles: [], files: [],
                                          mono: false, nerd: false, user: false, system: false, formats: [] });
    if (fam.variants.indexOf(raw) < 0) fam.variants.push(raw);
    const spacing = Number(f[5]);
    const fc = Number(f[3]);
    const style = {
      family: raw, style: (f[1] || "Regular").split(",")[0].trim() || "Regular",
      file: file, index: idx, fcWeight: isNaN(fc) ? 80 : fc, css: cssWeight(f[3]),
      italic: Number(f[4]) > 0, mono: spacing >= 90, format: (f[6] || "").trim()
    };
    fam.styles.push(style);
    if (fam.files.indexOf(file) < 0) fam.files.push(file);
    if (style.format !== "" && fam.formats.indexOf(style.format) < 0) fam.formats.push(style.format);
    if (style.mono) fam.mono = true;
    if (/Nerd Font|\bNF[MP]?$/.test(raw)) fam.nerd = true;
    if (isUserFile(file, home)) fam.user = true;
    else fam.system = true;
  }
  const out = Object.keys(by).map((k) => by[k]);
  for (const fam of out) fam.styles.sort(styleOrder);
  out.sort((a, b) => cmp(a.name.toLowerCase(), b.name.toLowerCase()));
  return out;
}

function cmp(a, b) { return a < b ? -1 : a > b ? 1 : 0; }

// lightest first, upright before italic, the plain cut before Mono/Propo
function styleOrder(a, b) {
  return (a.css - b.css) || ((a.italic ? 1 : 0) - (b.italic ? 1 : 0))
    || (a.family.length - b.family.length) || cmp(a.style, b.style);
}

// The style a weight asks for: the upright one nearest it (CSS weights).
function styleNear(fam, css, italic) {
  if (!fam || fam.styles.length === 0) return -1;
  let best = -1, bd = 1e9;
  for (let i = 0; i < fam.styles.length; ++i) {
    const s = fam.styles[i];
    const d = Math.abs(s.css - css) * 4 + ((!!s.italic !== !!italic) ? 1000 : 0)
      + (s.family === fam.name ? 0 : 1);
    if (d < bd) { bd = d; best = i; }
  }
  return best;
}

// What a style is called on its own: "SemiBold Italic", and the cut when the
// family has more than one ("Mono", "Propo").
function styleLabel(fam, s) {
  const cut = s.family !== fam.name && s.family.indexOf(fam.name) === 0
    ? s.family.slice(fam.name.length).trim() : "";
  return cut !== "" ? s.style + "  ·  " + cut : s.style;
}

// ── THE SHELVES ───────────────────────────────────────────────────────────
const SHELVES = [
  { id: "all",  label: "All",          glyph: "" },
  { id: "fav",  label: "Bookmarks",    glyph: "\uF02E" },
  { id: "mono", label: "Monospaced",   glyph: "" },
  { id: "nerd", label: "Nerd Fonts",   glyph: "\u{F0AEC}" },
  { id: "user", label: "Installed by you", glyph: "" },
  { id: "system", label: "System",     glyph: "" },
];

function onShelf(fam, shelf, favs) {
  switch (shelf) {
  case "fav": return !!(favs && favs[fam.name]);
  case "mono": return fam.mono;
  case "nerd": return fam.nerd;
  case "user": return fam.user;
  case "system": return fam.system;
  default: return true;
  }
}

// What a family is known as besides its name: Apple ships San Francisco as
// "SF …", so "san francisco" found nothing (the user's report).
const ALIASES = [
  [/^SF\b/, "san francisco apple"],
  [/^New York\b/, "apple serif"],
  [/Nerd Font|\bNF[MP]?$/, "nerd icons glyphs"],
  [/^Noto\b/, "google"],
  [/^JetBrains/, "jbm"],
];
function aliasesOf(name) {
  return ALIASES.filter((a) => a[0].test(name)).map((a) => a[1]).join(" ");
}

// Every word somewhere in the name, a variant's, an alias, or the
// directories its files are in (apple, noto, TTF), in any order — the rule
// the shell's other filters keep.
function familyMatches(fam, query) {
  const q = String(query || "").trim().toLowerCase();
  if (q === "") return true;
  if (fam.hay === undefined) {
    const dirs = {};
    for (const f of fam.files) { const d = String(f).split("/"); dirs[d[d.length - 2] || ""] = true; }
    fam.hay = (fam.name + " " + fam.variants.join(" ") + " " + aliasesOf(fam.name) + " "
               + Object.keys(dirs).join(" ")).toLowerCase();
  }
  return q.split(/\s+/).every((w) => fam.hay.indexOf(w) >= 0);
}

function shelve(fams, shelf, query, favs) {
  return (fams || []).filter((f) => onShelf(f, shelf, favs) && familyMatches(f, query));
}

function shelfCount(fams, shelf, favs) {
  let n = 0;
  for (const f of fams || []) if (onShelf(f, shelf, favs)) ++n;
  return n;
}

// ── A FACE'S CHARACTERS ───────────────────────────────────────────────────
// `fc-query -f '%{charset}'` — hex codepoints and ranges, space separated —
// as an index: the ranges, and where each starts in the run of all of them,
// so cell i of a grid is a binary search away from its codepoint.
function parseCharset(text) {
  const ranges = [];
  for (const tok of String(text || "").trim().split(/\s+/)) {
    if (tok === "") continue;
    const m = /^([0-9a-fA-F]+)(?:-([0-9a-fA-F]+))?$/.exec(tok);
    if (!m) continue;
    const lo = parseInt(m[1], 16), hi = m[2] ? parseInt(m[2], 16) : lo;
    if (hi >= lo) ranges.push([lo, hi]);
  }
  ranges.sort((a, b) => a[0] - b[0]);
  return indexOf(ranges);
}

// A sorted list of [lo, hi] as an index.
function indexOf(ranges) {
  const starts = [];
  let n = 0;
  for (const r of ranges) { starts.push(n); n += r[1] - r[0] + 1; }
  return { ranges: ranges, starts: starts, count: n };
}

// An index of a plain list of codepoints (a search's answer).
function indexOfList(cps) {
  const ranges = [];
  for (const c of cps) {
    const last = ranges[ranges.length - 1];
    if (last && c === last[1] + 1) last[1] = c;
    else ranges.push([c, c]);
  }
  return indexOf(ranges);
}

function codeAt(ix, i) {
  if (!ix || i < 0 || i >= ix.count) return -1;
  let lo = 0, hi = ix.ranges.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (ix.starts[mid] <= i) lo = mid; else hi = mid - 1;
  }
  return ix.ranges[lo][0] + (i - ix.starts[lo]);
}

function posOf(ix, cp) {
  if (!ix) return -1;
  for (let k = 0; k < ix.ranges.length; ++k) {
    const r = ix.ranges[k];
    if (cp >= r[0] && cp <= r[1]) return ix.starts[k] + cp - r[0];
  }
  return -1;
}

function covers(ix, cp) { return posOf(ix, cp) >= 0; }

// The part of an index inside [lo, hi].
function clip(ix, lo, hi) {
  const out = [];
  for (const r of ix.ranges) {
    const a = Math.max(r[0], lo), b = Math.min(r[1], hi);
    if (a <= b) out.push([a, b]);
  }
  return indexOf(out);
}

// ── WHAT A CHARACTER IS CALLED ────────────────────────────────────────────
function hex(cp) {
  const h = Number(cp).toString(16).toUpperCase();
  return h.length < 4 ? "0000".slice(h.length) + h : h;
}
function uplus(cp) { return "U+" + hex(cp); }
function charOf(cp) { return cp >= 0 ? String.fromCodePoint(cp) : ""; }

// The ways a character is written down, for the copy buttons.
function spellings(cp, nerdName) {
  const out = [
    { key: "char", label: "Character", text: charOf(cp) },
    { key: "code", label: "Codepoint", text: uplus(cp) },
    { key: "escape", label: "Escape", text: cp > 0xFFFF ? "\\u{" + hex(cp) + "}" : "\\u" + hex(cp) },
    { key: "html", label: "HTML", text: "&#x" + hex(cp) + ";" },
  ];
  if (nerdName) out.push({ key: "nerd", label: "Nerd name", text: "nf-" + nerdName });
  return out;
}

// /usr/share/unicode/UnicodeData.txt → { names: {cp: NAME}, spans: [[lo, hi, NAME-ish]] }.
// Controls are called by their old name; the big ranges (CJK, Hangul …)
// come as a First/Last pair and are named per codepoint from the span.
function parseUnicodeData(text) {
  // A WALK, NOT A SPLIT. 41,000 lines, of which only the first two fields
  // are wanted: splitting every line into its fifteen and running two
  // regexes on each was 198 ms on the GUI thread the first time a glyphs
  // page asked for names (qmlprofiler, 2026-10-09). Only the few names in
  // angle brackets (ranges, controls) are looked at further.
  const src = String(text || "");
  const names = {};
  const spans = [];
  let open = null;
  let i = 0;
  const n = src.length;
  while (i < n) {
    let e = src.indexOf("\n", i);
    if (e < 0) e = n;
    const s1 = src.indexOf(";", i);
    if (s1 > i && s1 < e) {
      let s2 = src.indexOf(";", s1 + 1);
      if (s2 < 0 || s2 > e) s2 = e;
      const cp = parseInt(src.slice(i, s1), 16);
      let nm = src.slice(s1 + 1, s2);
      if (nm.charCodeAt(0) === 60) {          // "<"
        if (nm.endsWith(", First>")) { open = [cp, nm.slice(1, -8)]; i = e + 1; continue; }
        if (nm.endsWith(", Last>") && open) {
          spans.push([open[0], cp, open[1].toUpperCase()]);
          open = null;
          i = e + 1;
          continue;
        }
        if (nm === "<control>") {
          const f = src.slice(i, e).split(";");
          nm = f[10] ? f[10] : "CONTROL";
        }
      }
      names[cp] = nm;
    }
    i = e + 1;
  }
  return { names: names, spans: spans };
}

// /usr/share/unicode/Blocks.txt → [[lo, hi, name]]
function parseBlocks(text) {
  const out = [];
  for (const line of String(text || "").split("\n")) {
    const m = /^([0-9A-Fa-f]+)\.\.([0-9A-Fa-f]+);\s*(.+?)\s*$/.exec(line);
    if (m) out.push([parseInt(m[1], 16), parseInt(m[2], 16), m[3]]);
  }
  return out;
}

// Nerd Fonts' sets in the private use area (v3), so its icons are shelved
// by where they came from rather than as one "Private Use Area".
const NERD_SETS = [
  [0xE000, 0xE00A, "Pomicons"],
  [0xE0A0, 0xE0D7, "Powerline"],
  [0xE200, 0xE2A9, "Font Awesome Extension"],
  [0xE300, 0xE3E3, "Weather Icons"],
  [0xE5FA, 0xE6B7, "Seti-UI + Custom"],
  [0xE700, 0xE8EF, "Devicons"],
  [0xEA60, 0xEC1E, "Codicons"],
  [0xED00, 0xF2FF, "Font Awesome"],
  [0xF300, 0xF381, "Font Logos"],
  [0xF400, 0xF533, "Octicons"],
  [0xF0001, 0xF1AF0, "Material Design"],
];

function spanOf(list, cp) {
  let lo = 0, hi = list.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const r = list[mid];
    if (cp < r[0]) hi = mid - 1;
    else if (cp > r[1]) lo = mid + 1;
    else return r;
  }
  return null;
}

function blockName(cp, blocks) {
  const n = spanOf(NERD_SETS, cp);
  if (n) return n[2];
  const b = spanOf(blocks || [], cp);
  return b ? b[2] : "";
}

// The groups a face's characters fall into — Unicode's blocks, Nerd's sets
// inside the private use area — in order, each with how many it holds.
function groupsOf(ix, blocks) {
  const out = [];
  const bounds = [];
  for (const n of NERD_SETS) bounds.push(n);
  for (const b of blocks || []) {
    // a block the Nerd sets carve up is left to them
    if (NERD_SETS.some((n) => n[0] >= b[0] && n[1] <= b[1])) {
      let at = b[0];
      for (const n of NERD_SETS) {
        if (n[0] < b[0] || n[1] > b[1]) continue;
        if (n[0] > at) bounds.push([at, n[0] - 1, b[2]]);
        at = n[1] + 1;
      }
      if (at <= b[1]) bounds.push([at, b[1], b[2]]);
    } else bounds.push(b);
  }
  bounds.sort((a, b) => a[0] - b[0]);
  // ONE PASS over both, each sorted: a block's count is the overlap of the
  // ranges from the first that has not ended before it. It was a clip of
  // the whole charset per block — every range, times ~340 blocks — and a
  // CJK face (thousands of ranges) took ~400 ms in the shell's engine.
  const rs = ix.ranges;
  let k = 0;
  const byName = {};
  for (const b of bounds) {
    while (k < rs.length && rs[k][1] < b[0]) k++;
    let n = 0;
    for (let j = k; j < rs.length && rs[j][0] <= b[1]; j++)
      n += Math.min(rs[j][1], b[1]) - Math.max(rs[j][0], b[0]) + 1;
    if (n === 0) continue;
    const g = byName[b[2]];
    if (g) { g.count += n; g.ranges.push([b[0], b[1]]); continue; }
    const ng = { name: b[2], lo: b[0], hi: b[1], count: n, ranges: [[b[0], b[1]]] };
    byName[b[2]] = ng;
    out.push(ng);
  }
  return out;
}

// An index of only a group's characters.
function groupIndex(ix, group) {
  const parts = [];
  for (const r of group.ranges) for (const c of clip(ix, r[0], r[1]).ranges) parts.push(c);
  parts.sort((a, b) => a[0] - b[0]);
  return indexOf(parts);
}

// Nerd Fonts' glyphnames.json → {cp: ["md-folder", …]}
function parseNerdNames(text) {
  const out = {};
  let j = null;
  try { j = JSON.parse(String(text || "")); } catch (e) { return out; }
  if (!j || typeof j !== "object") return out;
  for (const k in j) {
    if (k === "METADATA") continue;
    const v = j[k];
    if (!v || typeof v.code !== "string") continue;
    const cp = parseInt(v.code, 16);
    if (isNaN(cp)) continue;
    (out[cp] || (out[cp] = [])).push(k);
  }
  return out;
}
const NERD_NAMES_URL = "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json";

function unicodeName(cp, uni) {
  if (!uni) return "";
  const n = uni.names[cp];
  if (n) return n;
  const s = spanOf(uni.spans, cp);
  if (!s) return "";
  if (/^CJK IDEOGRAPH|^TANGUT IDEOGRAPH|^CJK/.test(s[2])) return s[2].replace(/,.*$/, "") + "-" + hex(cp);
  return s[2].replace(/,.*$/, "");
}

// What to call it: Nerd's name for its icons, Unicode's for the rest.
function glyphName(cp, uni, nerd) {
  const nn = nerd && nerd[cp];
  if (nn && nn.length > 0) return nn[0];
  return unicodeName(cp, uni).toLowerCase();
}

// ── THE SEARCH ────────────────────────────────────────────────────────────
// A query is a codepoint ("U+F031", "0xf031", "f031"), a character itself,
// or words that all have to be in its name ("folder open"). A hex word is
// both ("face"), so both are asked. → the codepoints, in the face's order.
function searchGlyphs(ix, query, uni, nerd) {
  const q = String(query || "").trim();
  if (q === "" || !ix) return [];
  const out = [];
  const seen = {};
  const add = (c) => { if (!seen[c] && covers(ix, c)) { seen[c] = true; out.push(c); } };
  const code = /^(?:u\+|0x|\\u\{?)?([0-9a-f]{2,6})\}?$/i.exec(q);
  if (code) add(parseInt(code[1], 16));
  const chars = Array.from(q);
  if (chars.length === 1 && !/[a-z0-9]/i.test(q)) add(q.codePointAt(0));
  const words = q.toLowerCase().replace(/^nf-/, "").split(/[\s_]+/).filter((w) => w !== "");
  const wordy = words.length > 0 && !(chars.length === 1 && !/[a-z0-9]/i.test(q));
  if (wordy) {
    for (const r of ix.ranges) for (let c = r[0]; c <= r[1]; ++c) {
      if (seen[c]) continue;
      let hay = "";
      const nn = nerd && nerd[c];
      if (nn) hay = nn.join(" ");
      const un = uni ? (uni.names[c] || "") : "";
      if (un !== "") hay += " " + un.toLowerCase();
      if (hay === "") continue;
      if (words.every((w) => hay.indexOf(w) >= 0)) { seen[c] = true; out.push(c); }
    }
  }
  return out.sort((a, b) => a - b);
}

// ── INSTALLING AND REMOVING ───────────────────────────────────────────────
function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

// Copied into the user's font directory (never over a file already there:
// a second copy gets a number) and fontconfig told. Prints each file's new
// path, one a line.
function installCommand(files, home) {
  const dir = installDir(home);
  return "d=" + quote(dir) + "\nmkdir -p \"$d\" || exit 1\n"
    + "for f in \"$@\"; do\n"
    + "  b=$(basename -- \"$f\"); t=\"$d/$b\"; n=2\n"
    + "  while [ -e \"$t\" ]; do cmp -s -- \"$f\" \"$t\" && break; t=\"$d/${b%.*}-$n.${b##*.}\"; n=$((n+1)); done\n"
    + "  [ -e \"$t\" ] || cp -- \"$f\" \"$t\" || exit 1\n"
    + "  printf '%s\\n' \"$t\"\n"
    + "done\n"
    + "fc-cache -f \"$d\" >/dev/null 2>&1\nexit 0\n";
}

// To the trash (it can come back) — only files of the user's own; fontconfig
// told after.
function removeCommand(files, home) {
  const mine = (files || []).filter((f) => isUserFile(f, home));
  if (mine.length === 0) return "exit 1\n";
  return "gio trash -- \"$@\" || exit 1\nfc-cache -f " + quote(installDir(home)) + " >/dev/null 2>&1\nexit 0\n";
}

const FONT_FILE = /\.(ttf|otf|ttc|otc|pfb|pfa|woff2?)$/i;
function isFontFile(path) { return FONT_FILE.test(String(path)); }

// The opening line of the specimen, until you type your own.
const SAMPLES = [
  "Sphinx of black quartz, judge my vow",
  "The quick brown fox jumps over the lazy dog",
  "Pack my box with five dozen liquor jugs",
  "0123456789 (){}[] <> != => -> === :: && ||",
  "Ἀλεξάνδρεια · Alexandria · الإسكندرية",
];

// A paragraph for the reading view
const PARAGRAPH = "The library of Alexandria was one of the largest and most significant "
  + "libraries of the ancient world. It was dedicated to the Muses, the nine goddesses of the "
  + "arts, and it is said to have held hundreds of thousands of scrolls, copied from every "
  + "ship that put into the harbour. Its scholars measured the earth, edited Homer, and "
  + "catalogued everything they could lay their hands on.";

// The alphabet line of the specimen, Latin's
const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789  &@#$%*  .,;:!?  ()[]{}<>  \"'`~^|\\/  →←↑↓  äéîøüß  ½ ¾ €£¥";

// ── THE SPECIMEN IN ANOTHER LANGUAGE ─────────────────────────────────────
// Each writing system the specimen can be set in: its name in itself, its
// lines, its letters, a paragraph. Offered only for a face that HAS every one
// of its letters — Qt would fill the rest from another font, and a specimen
// that is half someone else's face says nothing about this one.
const SCRIPTS = [
  { id: "latin", label: "Latin", samples: SAMPLES, alphabet: ALPHABET, paragraph: PARAGRAPH,
    probe: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" },
  { id: "vietnamese", label: "Tiếng Việt",
    samples: ["Thư viện Alexandria", "Tiếng Việt có dấu: ắ ằ ẳ ẵ ặ ế ề ể ễ ệ"],
    alphabet: "ĂÂĐÊÔƠƯ ăâđêôơư\nẠẢẤẦẨẪẬ ạảấầẩẫậ\nẾỀỂỄỆ ếềểễệ  ỐỒỔỖỘ ốồổỗộ\nỚỜỞỠỢ ớờởỡợ  ỨỪỬỮỰ ứừửữự",
    paragraph: "Thư viện Alexandria là một trong những thư viện lớn nhất và quan trọng nhất của thế giới cổ đại.",
    probe: "ĂÂĐÊÔƠƯăâđêôơưạảấầẩẫậếềểễệốồổỗộớờởỡợứừửữự" },
  { id: "greek", label: "Ελληνικά",
    samples: ["Ξεσκεπάζω την ψυχοφθόρα βδελυγμία", "Ἀλεξάνδρεια"],
    alphabet: "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ\nαβγδεζηθικλμνξοπρστυφχψω",
    paragraph: "Η Βιβλιοθήκη της Αλεξάνδρειας ήταν μία από τις μεγαλύτερες και σημαντικότερες βιβλιοθήκες του αρχαίου κόσμου.",
    probe: "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩαβγδεζηθικλμνξοπρστυφχψωάέήίόύώ" },
  { id: "cyrillic", label: "Кириллица",
    samples: ["Съешь же ещё этих мягких французских булок, да выпей чаю", "Александрия"],
    alphabet: "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ\nабвгдеёжзийклмнопрстуфхцчшщъыьэюя",
    paragraph: "Александрийская библиотека была одной из крупнейших и важнейших библиотек древнего мира.",
    probe: "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя" },
  { id: "arabic", label: "العربية",
    samples: ["نص حكيم له سر قاطع وذو شأن عظيم مكتوب على ثوب أخضر ومغلف بجلد أزرق", "الإسكندرية"],
    alphabet: "ا ب ت ث ج ح خ د ذ ر ز س ش ص ض ط ظ ع غ ف ق ك ل م ن ه و ي\n٠١٢٣٤٥٦٧٨٩",
    paragraph: "كانت مكتبة الإسكندرية واحدة من أكبر وأهم مكتبات العالم القديم.",
    probe: "ابتثجحخدذرزسشصضطظعغفقكلمنهوي" },
  { id: "hebrew", label: "עברית",
    samples: ["דג סקרן שט בים מאוכזב ולפתע מצא חברה", "אלכסנדריה"],
    alphabet: "א ב ג ד ה ו ז ח ט י כ ך ל מ ם נ ן ס ע פ ף צ ץ ק ר ש ת",
    paragraph: "ספריית אלכסנדריה הייתה אחת הספריות הגדולות והחשובות של העולם העתיק.",
    probe: "אבגדהוזחטיכךלמםנןסעפףצץקרשת" },
  { id: "devanagari", label: "हिन्दी",
    samples: ["अलेक्ज़ेंड्रिया का पुस्तकालय", "नमस्ते दुनिया"],
    alphabet: "अ आ इ ई उ ऊ ए ऐ ओ औ\nक ख ग घ च छ ज झ ट ठ ड ढ त थ द ध न प फ ब भ म य र ल व श ष स ह\n० १ २ ३ ४ ५ ६ ७ ८ ९",
    paragraph: "अलेक्ज़ेंड्रिया का पुस्तकालय प्राचीन विश्व के सबसे बड़े और महत्वपूर्ण पुस्तकालयों में से एक था।",
    probe: "अआइईउऊएऐओऔकखगघचछजझटठडढतथदधनपफबभमयरलवशषसह्ािीुूेैोौं" },
  { id: "thai", label: "ไทย",
    samples: ["เป็นมนุษย์สุดประเสริฐเลิศคุณค่า", "ห้องสมุดอเล็กซานเดรีย"],
    alphabet: "กขฃคฅฆงจฉชซฌญฎฏฐฑฒณดตถทธนบปผฝพฟภมยรลวศษสหฬอฮ\n๐๑๒๓๔๕๖๗๘๙",
    paragraph: "ห้องสมุดแห่งอเล็กซานเดรียเป็นหนึ่งในห้องสมุดที่ใหญ่และสำคัญที่สุดของโลกยุคโบราณ",
    probe: "กขคฆงจฉชซญดตถทธนบปผฝพฟภมยรลวศษสหอฮะาำิีึืุู่้๊๋" },
  { id: "georgian", label: "ქართული",
    samples: ["ალექსანდრიის ბიბლიოთეკა"],
    alphabet: "ა ბ გ დ ე ვ ზ თ ი კ ლ მ ნ ო პ ჟ რ ს ტ უ ფ ქ ღ ყ შ ჩ ც ძ წ ჭ ხ ჯ ჰ",
    paragraph: "ალექსანდრიის ბიბლიოთეკა ანტიკური სამყაროს ერთ-ერთი უდიდესი ბიბლიოთეკა იყო.",
    probe: "აბგდევზთიკლმნოპჟრსტუფქღყშჩცძწჭხჯჰ" },
  { id: "chinese", label: "中文",
    samples: ["我能吞下玻璃而不伤身体", "亚历山大图书馆"],
    alphabet: "永  天地玄黄 宇宙洪荒 日月盈昃 辰宿列张\n一二三四五六七八九十 百千万",
    paragraph: "亚历山大图书馆是古代世界最大、最重要的图书馆之一。",
    probe: "永天地玄黄宇宙洪荒日月盈昃辰宿列张我能吞下玻璃而不伤身体亚历山大图书馆是古代世界最重要之一" },
  { id: "japanese", label: "日本語",
    samples: ["いろはにほへと ちりぬるを", "アレクサンドリア図書館"],
    alphabet: "あいうえお かきくけこ さしすせそ\nアイウエオ カキクケコ サシスセソ\n日本語の文字",
    paragraph: "アレクサンドリア図書館は、古代世界で最も大きく重要な図書館の一つでした。",
    probe: "あいうえおかきくけこさしすせそいろはにほへとちりぬるをアイウエオカキクケコサシスセソレクンドリア図書館日本語文字古代世界最大重要一" },
  { id: "korean", label: "한국어",
    samples: ["키스의 고유조건은 입술끼리 만나야 하고 특별한 기술은 필요치 않다", "알렉산드리아 도서관"],
    alphabet: "ㄱ ㄴ ㄷ ㄹ ㅁ ㅂ ㅅ ㅇ ㅈ ㅊ ㅋ ㅌ ㅍ ㅎ\nㅏ ㅑ ㅓ ㅕ ㅗ ㅛ ㅜ ㅠ ㅡ ㅣ\n가 나 다 라 마 바 사 아 자 차 카 타 파 하",
    paragraph: "알렉산드리아 도서관은 고대 세계에서 가장 크고 중요한 도서관 중 하나였다.",
    probe: "ㄱㄴㄷㄹㅁㅂㅅㅇㅈㅊㅋㅌㅍㅎㅏㅑㅓㅕㅗㅛㅜㅠㅡㅣ가나다라마바사아자차카타파하키스의고유조건은입술끼리만나야특별한기술필요치않" },
];

function scriptOf(id) {
  for (const s of SCRIPTS) if (s.id === id) return s;
  return SCRIPTS[0];
}

// Does the face (its charset index) have every letter of this script's probe?
function hasScript(ix, script) {
  if (!ix || ix.count === 0) return false;
  for (const ch of script.probe) if (!covers(ix, ch.codePointAt(0))) return false;
  return true;
}

// The scripts a face can be shown in, Latin always first when it has it.
function scriptsOf(ix) {
  return SCRIPTS.filter((s) => hasScript(ix, s));
}
