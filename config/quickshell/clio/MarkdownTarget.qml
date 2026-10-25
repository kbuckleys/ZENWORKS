// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE FORMAT BAR OVER PLAIN MARKDOWN — what clio/FormatBar asks of a
// BlockEditor, answered by writing the Markdown itself into a plain-text
// TextEdit: a style is the line's "## ", a list its "- " or "1. ", the quote
// its "> ", Mono a ``` fence round the lines, a mark the ** or * or ~~ round
// the words (Delphi's release notes, written as Markdown — user, 2026-10-25).
// Every change goes in as the TextEdit's own edit, so ctrl z takes it back.
//
//     MarkdownTarget { id: md; field: someTextEdit }
//     FormatBar { ed: md; aligns: false; marks: ["b", "i", "s"] }

import QtQuick

QtObject {
  id: md
  property var field: null

  // what a FormatBar reads (no alignment, no faces, no pictures in Markdown)
  readonly property string alignNow: ""
  readonly property string faceHere: ""
  readonly property string mediaSel: ""
  readonly property string kindHere: {
    const f = md.field;
    if (!f) return "";
    void f.text; void f.cursorPosition;
    if (md.inMono) return "mono";
    const u = md.underlined(f.text, f.cursorPosition);
    return u ? u.kind : md.kindOf(md.lineAt(f.text, f.cursorPosition).text);
  }
  readonly property bool inMono: {
    const f = md.field;
    if (!f) return false;
    void f.text; void f.cursorPosition;
    return md.fenced(f.text, f.cursorPosition);
  }
  readonly property var marksHere: {
    const f = md.field;
    if (!f) return ({});
    void f.text; void f.cursorPosition; void f.selectionStart; void f.selectionEnd;
    const l = md.lineAt(f.text, f.selectionStart);
    const a = f.selectionStart - l.a, b = Math.min(f.selectionEnd, l.b) - l.a;
    return { b: md.within(l.text, /\*\*([^*]+?)\*\*|__([^_]+?)__/g, a, b),
             i: md.within(md.unbold(l.text), /\*([^*\s][^*]*?)\*|(^|[^\w])_([^_\s][^_]*?)_(?!\w)/g, a, b),
             s: md.within(l.text, /~~([^~]+?)~~/g, a, b) };
  }

  // ── READING THE TEXT ──
  // the line a position is on: { a, b, text } (b before its newline)
  function lineAt(t, pos) {
    const a = t.lastIndexOf("\n", pos - 1) + 1;
    let b = t.indexOf("\n", pos);
    if (b < 0) b = t.length;
    return { a: a, b: b, text: t.slice(a, b) };
  }
  // the whole lines the selection (or the caret) touches
  function span() {
    const f = md.field, t = f.text;
    const a = md.lineAt(t, f.selectionStart).a;
    const end = f.selectionEnd > f.selectionStart && t.charAt(f.selectionEnd - 1) === "\n" ? f.selectionEnd - 1 : f.selectionEnd;
    const b = md.lineAt(t, end).b;
    return { a: a, b: b, lines: t.slice(a, b).split("\n") };
  }
  // inside a ``` fence: an odd count of fences on the lines before
  function fenced(t, pos) {
    const before = t.slice(0, md.lineAt(t, pos).a);
    return (before.match(/^\s*```/mg) || []).length % 2 === 1;
  }
  function kindOf(line) {
    let m;
    if ((m = line.match(/^(#{1,6})\s/))) return m[1].length === 1 ? "title" : m[1].length === 2 ? "heading" : "subheading";
    if (/^>\s?/.test(line)) return "quote";
    if (/^\s*[-*+]\s+\[[ xX]\]\s/.test(line)) return "check";
    if (/^\s*\d+[.)]\s/.test(line)) return "number";
    if (/^\s*[-*+]\s/.test(line)) return "bullet";
    return "body";
  }
  // AN UNDERLINED HEADING — words with a line of = (a title) or - (a
  // heading) right under them, GitHub's other way to write one (user,
  // 2026-10-25). The one at a position, on its words or on its underline:
  // { kind, a, b } over both lines, or null.
  function isUnder(line) { return /^ {0,3}(=+|-+)\s*$/.test(line); }
  function isWords(line) { return line.trim() !== "" && !md.isUnder(line) && md.kindOf(line) === "body" && !/^\s*([-*_])(\s*\1){2,}\s*$/.test(line); }
  function underlined(t, pos) {
    let l = md.lineAt(t, pos);
    let u = l.b < t.length ? md.lineAt(t, l.b + 1) : null;
    if (md.isUnder(l.text) && l.a > 0) { u = l; l = md.lineAt(t, l.a - 1); }
    if (!u || !md.isUnder(u.text) || !md.isWords(l.text) || md.fenced(t, l.a)) return null;
    return { kind: u.text.trim().charAt(0) === "=" ? "title" : "heading", a: l.a, b: u.b };
  }
  // the line without what made it its kind (its indent kept)
  function bare(line) {
    return line.replace(/^#{1,6}\s+/, "").replace(/^>\s?/, "")
      .replace(/^(\s*)(?:[-*+]\s+\[[ xX]\]|[-*+]|\d+[.)])\s+/, "$1");
  }
  // ** pairs blanked out, so a lone * reads as italic
  function unbold(s) { return s.replace(/\*\*([^*]+?)\*\*/g, (m) => " ".repeat(m.length)); }
  // is [a, b) (or the caret at a) inside one of re's spans
  function within(s, re, a, b) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(s)) !== null) {
      if (a >= m.index && Math.max(a, b) <= m.index + m[0].length && a < m.index + m[0].length) return true;
      if (m[0].length === 0) re.lastIndex++;
    }
    return false;
  }
  // the lines written back, the same lines chosen after. Only what differs
  // is touched: a lead added or taken off is one edit, so one ctrl z (a
  // remove and an insert are two — TextEdit has no replace)
  function put(a, b, text) {
    const f = md.field;
    const old = f.text.slice(a, b);
    let p = 0;
    while (p < old.length && p < text.length && old.charAt(p) === text.charAt(p)) p++;
    let q = 0;
    while (q < old.length - p && q < text.length - p && old.charAt(old.length - 1 - q) === text.charAt(text.length - 1 - q)) q++;
    if (old.length - p - q > 0) f.remove(a + p, b - q);
    if (text.length - p - q > 0) f.insert(a + p, text.slice(p, text.length - q));
    f.select(a, a + text.length);
    f.forceActiveFocus();
  }

  // ── WHAT THE BAR DOES ──
  function setKind(k) {
    const f = md.field;
    if (!f || f.readOnly) return;
    const sp = md.span();
    // an underlined heading at either end taken in whole (Mono fences both
    // its lines), and read as its # form: what the bar writes back is a #
    // heading or plain words
    const t = f.text;
    const first = md.underlined(t, sp.a), last = md.underlined(t, sp.b);
    if (first && first.a < sp.a) sp.a = first.a;
    if (last && last.b > sp.b) sp.b = last.b;
    sp.lines = t.slice(sp.a, sp.b).split("\n");
    if (k === "mono") { md.fence(sp); return; }
    for (let i = sp.lines.length - 1; i > 0; --i)
      if (md.isUnder(sp.lines[i]) && md.isWords(sp.lines[i - 1])) {
        sp.lines[i - 1] = (sp.lines[i].trim().charAt(0) === "=" ? "# " : "## ") + sp.lines[i - 1].trim();
        sp.lines.splice(i, 1);
      }
    // all of them that kind already: back to lines (a toggle, as Clio's)
    const all = sp.lines.every((l) => md.kindOf(l) === k);
    const to = all && k !== "body" ? "body" : k;
    let n = 0;
    const lead = { title: "# ", heading: "## ", subheading: "### ", quote: "> ", bullet: "- ", dash: "- ", check: "- [ ] " };
    const out = sp.lines.map((l) => {
      if (l.trim() === "" && sp.lines.length > 1) return l;
      const bare = md.bare(l);
      const indent = (to === "bullet" || to === "dash" || to === "number" || to === "check") ? bare.match(/^\s*/)[0] : "";
      const words = bare.replace(/^\s*/, "");
      if (to === "body") return bare;
      if (to === "number") return indent + (++n) + ". " + words;
      return indent + lead[to] + words;
    });
    md.put(sp.a, sp.b, out.join("\n"));
  }
  // Mono: the lines in a ``` fence, or out of the one they are in
  function fence(sp) {
    const f = md.field, t = f.text;
    if (md.fenced(t, sp.a)) {
      // the fence round them: its opening line above, its closing below
      const open = t.lastIndexOf("```", sp.a);
      const oa = md.lineAt(t, open);
      const close = t.indexOf("```", sp.b);
      if (open < 0 || close < 0) return;
      const cb = md.lineAt(t, close);
      const inner = t.slice(oa.b + 1, cb.a > oa.b + 1 ? cb.a - 1 : oa.b + 1);
      md.put(oa.a, cb.b, inner);
      return;
    }
    md.put(sp.a, sp.b, "```\n" + sp.lines.join("\n") + "\n```");
  }
  function mark(tag) {
    const f = md.field;
    if (!f || f.readOnly || md.inMono) return;
    const sign = tag === "b" ? "**" : tag === "i" ? "*" : tag === "s" ? "~~" : "";
    if (sign === "") return;
    let a = f.selectionStart, b = f.selectionEnd;
    const t = f.text;
    // nothing chosen: the word at the caret
    if (a === b) {
      while (a > 0 && /\w/.test(t.charAt(a - 1))) a--;
      while (b < t.length && /\w/.test(t.charAt(b))) b++;
    }
    const n = sign.length;
    // already wrapped in it: unwrapped
    if (a >= n && t.slice(a - n, a) === sign && t.slice(b, b + n) === sign
        && !(sign === "*" && (t.charAt(a - n - 1) === "*" || t.charAt(b + n) === "*"))) {
      f.remove(b, b + n);
      f.remove(a - n, a);
      f.select(a - n, b - n);
      f.forceActiveFocus();
      return;
    }
    const word = t.slice(a, b);
    if (word.length > 2 * n && word.startsWith(sign) && word.endsWith(sign)) {
      md.put(a, b, word.slice(n, word.length - n));
      return;
    }
    f.insert(b, sign);
    f.insert(a, sign);
    if (a === b) f.cursorPosition = a + n; else f.select(a + n, b + n);
    f.forceActiveFocus();
  }
  // a list item deeper or shallower: two spaces, as Clio writes them
  function indent(d) {
    const f = md.field;
    if (!f || f.readOnly) return;
    const sp = md.span();
    md.put(sp.a, sp.b, sp.lines.map((l) => d > 0 ? (l.trim() === "" ? l : "  " + l) : l.replace(/^ {1,2}/, "")).join("\n"));
  }
  // words at the caret, over what is chosen (a menu's Insert)
  function insert(text) {
    const f = md.field;
    if (!f || f.readOnly) return;
    if (f.selectionStart !== f.selectionEnd) f.remove(f.selectionStart, f.selectionEnd);
    const at = f.cursorPosition;
    f.insert(at, text);
    f.cursorPosition = at + text.length;
    f.forceActiveFocus();
  }
  // a link: round the words chosen, or `label` (the address itself) at the
  // caret — [words](address)
  function link(url, label) {
    const f = md.field;
    if (!f || f.readOnly) return;
    const href = /^[a-z][a-z0-9+.-]*:/i.test(url) ? url : "https://" + url;
    const words = f.selectionStart !== f.selectionEnd ? f.selectedText : (label || url);
    md.insert("[" + words.replace(/[\[\]]/g, "\\$&") + "](" + href + ")");
  }
  // a divider on a line of its own
  function rule() {
    const f = md.field;
    if (!f || f.readOnly) return;
    const l = md.lineAt(f.text, f.cursorPosition);
    const at = l.b;
    const lead = l.text.trim() === "" ? "" : "\n\n";
    f.insert(at, lead + "---\n");
    f.cursorPosition = at + lead.length + 4;
    f.forceActiveFocus();
  }
  // the marks off the words chosen (the caret's line, with none chosen)
  function plainText() {
    const f = md.field;
    if (!f || f.readOnly || md.inMono) return;
    let a = f.selectionStart, b = f.selectionEnd;
    if (a === b) { const l = md.lineAt(f.text, a); a = l.a; b = l.b; }
    const s = f.text.slice(a, b);
    const out = s.replace(/\*\*([^*]+?)\*\*|__([^_]+?)__/g, "$1$2").replace(/~~([^~]+?)~~/g, "$1")
      .replace(/\*([^*\s][^*]*?)\*/g, "$1").replace(/(^|[^\w])_([^_\s][^_]*?)_(?!\w)/g, "$1$2")
      .replace(/`([^`]+)`/g, "$1");
    if (out !== s) md.put(a, b, out);
  }
}
