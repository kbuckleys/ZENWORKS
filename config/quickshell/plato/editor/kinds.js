// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A symbol's kind (symbols.lua: the language server's SymbolKind names, or
// "Heading"), as one glyph: what runs, what holds, a heading. One place,
// for the outline picker and the status line's breadcrumb alike.

.pragma library

function glyph(k) {
  k = String(k || "");
  if (/Function|Method|Constructor/.test(k)) return "\u{F0295}";
  if (/Class|Struct|Object|Interface|Module|Namespace|Enum|Package/.test(k)) return "\u{F01A7}";
  if (k === "Heading") return "#";
  return "•";
}
