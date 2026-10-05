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
