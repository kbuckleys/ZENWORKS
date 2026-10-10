// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Screen cells, not characters, for the few places QML has to cut a row's
// text by itself (the flashes' ghost text). A wide character — CJK, most
// emoji — is one character in two cells; anything that counted characters
// as cells cut such a row in the wrong place.
//
// nvim is the authority on widths (strdisplaywidth): wherever it can send the
// answer, it does — the cursor's character comes with the frame. This is the
// close approximation for the rest: East Asian Wide and Fullwidth, and the
// emoji planes, are two cells; combining marks are none.

.pragma library

const wide = [
  [0x1100, 0x115F], [0x231A, 0x231B], [0x2329, 0x232A], [0x23E9, 0x23EC],
  [0x23F0, 0x23F0], [0x23F3, 0x23F3], [0x25FD, 0x25FE], [0x2614, 0x2615],
  [0x2648, 0x2653], [0x267F, 0x267F], [0x2693, 0x2693], [0x26A1, 0x26A1],
  [0x26AA, 0x26AB], [0x26BD, 0x26BE], [0x26C4, 0x26C5], [0x26CE, 0x26CE],
  [0x26D4, 0x26D4], [0x26EA, 0x26EA], [0x26F2, 0x26F3], [0x26F5, 0x26F5],
  [0x26FA, 0x26FA], [0x26FD, 0x26FD], [0x2705, 0x2705], [0x270A, 0x270B],
  [0x2728, 0x2728], [0x274C, 0x274C], [0x274E, 0x274E], [0x2753, 0x2755],
  [0x2757, 0x2757], [0x2795, 0x2797], [0x27B0, 0x27B0], [0x27BF, 0x27BF],
  [0x2B1B, 0x2B1C], [0x2B50, 0x2B50], [0x2B55, 0x2B55], [0x2E80, 0x303E],
  [0x3041, 0x33FF], [0x3400, 0x4DBF], [0x4E00, 0x9FFF], [0xA000, 0xA4CF],
  [0xA960, 0xA97F], [0xAC00, 0xD7A3], [0xF900, 0xFAFF], [0xFE10, 0xFE19],
  [0xFE30, 0xFE6F], [0xFF00, 0xFF60], [0xFFE0, 0xFFE6], [0x16FE0, 0x16FE4],
  [0x17000, 0x18CFF], [0x1B000, 0x1B2FF], [0x1F004, 0x1F004], [0x1F0CF, 0x1F0CF],
  [0x1F18E, 0x1F18E], [0x1F191, 0x1F19A], [0x1F200, 0x1F251], [0x1F300, 0x1F64F],
  [0x1F680, 0x1F6FF], [0x1F7E0, 0x1F7EB], [0x1F90C, 0x1F9FF], [0x1FA70, 0x1FAFF],
  [0x20000, 0x3FFFD],
];

function width(ch) {
  const c = ch.codePointAt(0);
  if (c < 0x300) return 1;
  // combining marks, zero-width joiners and variation selectors
  if ((c >= 0x300 && c <= 0x36F) || (c >= 0x200B && c <= 0x200F)
      || (c >= 0xFE00 && c <= 0xFE0F) || (c >= 0x20D0 && c <= 0x20FF)) return 0;
  let lo = 0, hi = wide.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (c < wide[mid][0]) hi = mid - 1;
    else if (c > wide[mid][1]) lo = mid + 1;
    else return 2;
  }
  return 1;
}

// cells [c0, c0 + len) of laid-out text (tabs already expanded): every
// character that starts inside them
function slice(text, c0, len) {
  let cell = 0, out = "";
  const c1 = c0 + len;
  for (const ch of chars(text)) {
    if (cell >= c1) break;
    if (cell >= c0) out += ch;
    cell += width(ch);
  }
  return out;
}

// how many cells `text` takes
function count(text) {
  let n = 0;
  for (const ch of chars(text)) n += width(ch);
  return n;
}

// A row's text as its characters — code points, as nvim counts them. Not
// Array.from: in this engine it splits a character past U+FFFF (a Nerd Font
// icon, most emoji) into its two UTF-16 halves, and every span after one on
// the row came out a character short.
function chars(t) {
  return String(t || "").match(/[\uD800-\uDBFF][\uDC00-\uDFFF]|[\s\S]/g) || [];
}

// ── paths in a row ────────────────────────────────────────────────────
// The words of laid-out text, split where a path cannot go on, each with
// the cells it covers: [{ w, a, b }], cells [a, b). EditorView's hover peek
// and EditorRow's path pills read the same words, so what is lit is what
// the pointer shows.
const stop = /[\s"'`()<>\[\]{},;|=]/;
function words(text) {
  const out = [];
  let cell = 0, w = "", a = 0;
  for (const ch of chars(text)) {
    if (stop.test(ch)) {
      if (w !== "") out.push({ w: w, a: a, b: cell });
      w = "";
    } else {
      if (w === "") a = cell;
      w += ch;
    }
    cell += width(ch);
  }
  if (w !== "") out.push({ w: w, a: a, b: cell });
  return out;
}
// a word as a path: what the peek looks up (`loose`: any slash or dot, a
// bare "notes.md" too), or — not loose — what is plainly one, for the
// pills: rooted (/, ~/, ./, ../, file://) or a slashed name ending in an
// extension. Never a URL, never a comment's //. Trailing . : are prose,
// and a trailing :line or :line:col (an error's, grep's) is a place in the
// file, not its name.
const tail = /(:\d+){0,2}[.:]*$/;
function pathOf(word, loose) {
  let p = String(word).replace(/^file:\/\//, "").replace(tail, "");
  if (p.length < 2 || p.indexOf("://") >= 0 || /^\/+$/.test(p) || p.indexOf("//") >= 0) return "";
  if (loose) return /[\/.]/.test(p) ? p : "";
  if (/^(~|\.{1,2})?\/[\w.@+-]/.test(p) || p === "~") return p;
  if (/^[\w.@+-]+(\/[\w.@+-]+)+\.[A-Za-z0-9]{1,8}$/.test(p)) return p;
  return "";
}
// the plain paths of a row, as cell spans [{ a, b }] (the trailing prose
// trimmed off the span too)
function paths(text) {
  const out = [];
  for (const it of words(text)) {
    const p = pathOf(it.w, false);
    if (p === "") continue;
    const cut = it.w.length - it.w.replace(tail, "").length;
    out.push({ a: it.a, b: it.b - cut });
  }
  return out;
}
