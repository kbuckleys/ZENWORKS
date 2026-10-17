// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CLIO'S EDITOR — a note as a column of blocks (Block.qml), written into as
// one page. Return splits a block, backspace at its start joins it to the
// one before; the arrows and a drag run from block to block; a selection
// can cover many, and is cut, copied, formatted or typed over as one.
// Markdown typed at a line's start becomes its kind ("- ", "1. ", "[] ",
// "# ", "> "); ">>" links another note; a line ending in "=" is worked out
// (Math Notes, through metis).
//
//   load(blocks, opts)     a note into it; `base` is where its files are
//   blocks                 what it holds now — stored() strips the keys
//   edited()               something changed: the owner saves, later
//
// Every gesture lands on one overlay over the column and is handed to the
// block under it (Block.control): a checkbox, a fold, a picture's corner,
// a link — or the words, where the caret goes. TextEdits never take the
// mouse themselves; that is what lets a drag cross from one to the next.

import QtQuick
import Quickshell
import "../morpheus"
import "../morpheus/undo"
import "notes.js" as N

Item {
  id: ed

  // ── WHAT IT SHOWS ──────────────────────────────────────────────────────
  property var blocks: []
  property int rev: 0
  property string base: ""
  // the notebook (ClioManager), for what a block asks of it — a picture's
  // transparency (Block's media.clear); null where there is none
  property var mgr: null
  property bool readOnly: false
  // a box ticked sinks under the unticked ones (Apple's "Sort checked items")
  property bool sinkOnTick: false
  property real textSize: Zenon.px(16)
  property string face: Zenon.face
  // the page's own width, centered when the pane is wider (Apple's column)
  property real maxColumn: 760
  readonly property real columnW: Math.max(200, Math.min(ed.width - 2 * ed.sidePad, ed.maxColumn))
  property real sidePad: 34
  property real topPad: 18
  property real bottomPad: 120
  // a header drawn above the first block (a journal entry's date and mood)
  property alias header: headerSlot.data
  // under the last block (the note's backlinks), over the gestures
  property alias footer: footerSlot.data
  readonly property Flickable flick: view
  readonly property Item content: page

  signal edited()
  // the right button: where, and what it was over
  signal menuAsked(real x, real y, var info)
  signal linkClicked(string href)
  // ">>" typed: the owner shows its notes; insertNoteLink() answers
  signal noteLinkAsked()
  // a sum to work out (Math Notes): mathAnswer(seq, text) answers
  signal mathAsked(int seq, string expr)
  // a picture or a sketch opened (double click)
  signal mediaOpened(var block)
  signal fileOpened(var block)
  // ctrl+v with a picture on the clipboard is the owner's to keep
  signal pasteAsked()
  // ctrl+shift+v: the clipboard's words without their formatting
  signal pastePlainAsked()
  // the caret left the bottom of the last block downwards, or Esc
  signal escaped()
  // files dropped on the note from outside (terminus, say), and where:
  // `at` is the gap they land in, as dropAt
  signal filesDropped(var paths, int at)
  // pictures just put in, to be read (their words, for search: NotePane)
  signal picturesAdded(var srcs)

  // blocks by key
  property var _byKey: ({})
  function blockOf(k) { return ed._byKey[k] || null; }
  function indexOf(k) { for (let i = 0; i < ed.blocks.length; i++) if (ed.blocks[i]._key === k) return i; return -1; }
  function keyAt(i) { return i >= 0 && i < ed.blocks.length ? ed.blocks[i]._key : ""; }
  function itemOf(k) { const i = ed.indexOf(k); return i >= 0 ? rep.itemAt(i) : null; }

  // numbers and folds, worked out once per change
  property var _numbers: []
  property var _hidden: []
  function numberOf(i) { return ed._numbers[i] || 1; }
  function isHidden(k) { const i = ed.indexOf(k); return i >= 0 && !!ed._hidden[i]; }
  function canFold(k) { void ed.rev; const i = ed.indexOf(k); return i >= 0 && N.foldable(ed.blocks, i); }
  onRevChanged: { ed._numbers = N.numbering(ed.blocks); ed._hidden = N.hidden(ed.blocks); Qt.callLater(ed.relayout); }

  ListModel { id: keys }
  property int _keyN: 0
  function _mk(b) { const o = Object.assign({}, b); o._key = "k" + (++ed._keyN); ed._byKey[o._key] = o; return o; }

  // ── IN AND OUT ─────────────────────────────────────────────────────────
  function load(bs, opts) {
    opts = opts || {};
    ed.ghost = "";
    ed.cross = null;
    ed.mediaSel = "";
    ed.findHits = [];
    ed._byKey = ({});
    const list = (bs && bs.length ? bs : [N.block("title", "")]).map((b) => ed._mk(b));
    ed.blocks = list;
    keys.clear();
    for (const b of list) keys.append({ key: b._key });
    ed.rev++;
    // a note loaded is a fresh history; an undo's own reload keeps it
    if (!opts.keepUndo) history.clear();
    ed._lastSnap = 0;
    // (an undo keeps the page where it was: from the top, the caret was
    // only revealed at the window's edge, and the note seemed to jump)
    if (!opts.keepY) view.contentY = 0;
    if (opts.focus) Qt.callLater(() => ed.focusEnd(opts.focus === "start"));
  }
  // what is there, as it is kept: no runtime keys
  function stored() {
    ed.flushTyping();
    return ed.blocks.map((b) => { const o = {}; for (const k in b) if (k !== "_key") o[k] = b[k]; return o; });
  }

  // a color by name painted for the screen, a link painted cyan; and back
  function inkHex(name) { return String(Zenon[name] || Zenon.ink).toLowerCase(); }
  function markHex(name) {
    const c = Zenon.mix(Zenon.ground, Zenon[name] || Zenon.sand, Zenon.light ? 0.35 : 0.4);
    return String(Qt.rgba(c.r, c.g, c.b, 1)).toLowerCase();
  }
  function display(h) {
    let s = N.paint(h || "", ed.inkHex, ed.markHex);
    s = s.replace(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi, (m, a, t) => "<a" + a + "><span style=\"color:" + String(Zenon.cyan) + "; text-decoration: underline;\">" + t + "</span></a>");
    return s;
  }
  function keep(h) { return N.unpaint(N.tidy(h), ed.inkHex, ed.markHex); }

  // ── TYPING ─────────────────────────────────────────────────────────────
  // A block's TextEdit changed under the keys: its run is read back (and
  // split, if a paste put paragraphs into it), the note told.
  property var _dirtyKeys: ({})
  function typed(k, item) {
    ed.snap(false);
    ed._dirtyKeys[k] = item;
    typingTimer.restart();
    // a ghost answer goes with any edit but the one that asked it
    if (ed.ghostKey === k) ed.ghost = "";
    mathTimer.restart();
    Qt.callLater(() => ed.tagCheck(item));
    ed.edited();
  }

  // ── SMART PUNCTUATION ──────────────────────────────────────────────────
  // " and ' open after a space, a bracket or the line's start, and close
  // otherwise (an apostrophe is a closing ’); a second - after a word is an
  // em dash. Not in Monostyled blocks, and never at a line's start, where
  // "---" is a divider. Ctrl+Z after one takes it back to what was typed.
  function smarten(it, b, e) {
    if (!ed.mgr || !ed.mgr.smartPunct || b.k === "mono" || !it.isText) return false;
    const te = it.te;
    if (te.selectionStart !== te.selectionEnd) return false;
    const pos = te.cursorPosition;
    const prev = pos > 0 ? te.getText(pos - 1, pos) : "";
    if (e.text === "\"" || e.text === "'") {
      const open = prev === "" || /[\s(\[{\u2014\u2013\u201C\u2018]/.test(prev);
      const ch = e.text === "\"" ? (open ? "\u201C" : "\u201D") : (open ? "\u2018" : "\u2019");
      te.insert(pos, ch);
      return true;
    }
    if (e.text === "-" && prev === "-" && pos >= 2 && te.getText(0, pos) !== "-" && !/\s/.test(te.getText(pos - 2, pos - 1))) {
      te.remove(pos - 1, pos);
      te.insert(pos - 1, "\u2014");
      return true;
    }
    return false;
  }

  // ── #TAG, COMPLETED ────────────────────────────────────────────────────
  // A # and the start of a word: the notebook's tags that begin so, offered
  // under the caret, the most used first. Tab or Return takes the one lit,
  // ↑↓ choose, Esc puts them away; typing on narrows them.
  property string tagKey: ""
  property int tagFrom: -1
  property var tagHits: []
  property int tagAt: 0
  property point tagSpot: Qt.point(0, 0)
  function tagClear() { if (ed.tagHits.length > 0) ed.tagHits = []; ed.tagKey = ""; ed.tagFrom = -1; }
  function tagCheck(it) {
    if (!it || !it.isText || it.kind === "mono" || !ed.mgr || !it.te.activeFocus) { ed.tagClear(); return; }
    const te = it.te;
    const pos = te.cursorPosition;
    const back = te.getText(Math.max(0, pos - 48), pos);
    const m = back.match(new RegExp("(^|[\\s(])#([" + N.LETTER + "0-9_-]*)$"));
    if (!m) { ed.tagClear(); return; }
    const pre = m[2].toLowerCase();
    const rows = N.tagRows(ed.mgr.notes.filter((n) => n.kind !== "sticky"))
      .filter((t) => t.name.startsWith(pre) && t.name !== pre)
      .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name)).slice(0, 6);
    if (rows.length === 0) { ed.tagClear(); return; }
    ed.tagKey = it.key;
    ed.tagFrom = pos - m[2].length - 1;
    ed.tagHits = rows.map((t) => t.name);
    ed.tagAt = 0;
    const r = te.cursorRectangle;
    ed.tagSpot = te.mapToItem(ed, r.x, r.y + r.height + 4);
  }
  function tagTake(name) {
    const it = ed.itemOf(ed.tagKey);
    if (!it || ed.tagFrom < 0) { ed.tagClear(); return; }
    const te = it.te;
    const from = ed.tagFrom + 1, to = te.cursorPosition;
    ed.tagClear();
    te.forceActiveFocus();
    te.remove(from, to);
    te.insert(from, N.escape(name) + "&nbsp;");
  }
  function tagKeyPress(k, e) {
    if (ed.tagHits.length === 0 || ed.tagKey !== k) return false;
    if (e.key === Qt.Key_Down) { ed.tagAt = (ed.tagAt + 1) % ed.tagHits.length; return true; }
    if (e.key === Qt.Key_Up) { ed.tagAt = (ed.tagAt - 1 + ed.tagHits.length) % ed.tagHits.length; return true; }
    if (e.key === Qt.Key_Tab || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { ed.tagTake(ed.tagHits[ed.tagAt]); return true; }
    if (e.key === Qt.Key_Escape) { ed.tagClear(); return true; }
    return false;
  }
  Timer { id: typingTimer; interval: 120; onTriggered: ed.flushTyping() }
  function flushTyping() {
    const d = ed._dirtyKeys;
    ed._dirtyKeys = ({});
    for (const k in d) {
      const it = d[k];
      const b = ed.blockOf(k);
      if (!b || !it) continue;
      if (b.k === "mono") { b.h = it.te.text; it.shown = b.h; continue; }
      const raw = it.te.text;
      // more than one paragraph: a paste, or Qt splitting on its own
      const plainNow = it.te.getText(0, it.te.length);
      if (plainNow.indexOf(String.fromCharCode(0x2029)) >= 0) { ed.splitPasted(k, raw); continue; }
      b.h = ed.keep(N.inline(raw));
      it.shown = b.h;
    }
  }
  // a paste of many paragraphs: the block becomes them
  function splitPasted(k, raw) {
    const i = ed.indexOf(k);
    if (i < 0) return;
    const old = ed.blocks[i];
    const parsed = N.blocksOf(raw).map((b) => { b.h = ed.keep(b.h); return b; });
    if (parsed.length === 0) parsed.push(N.block("body", ""));
    // the block keeps its own kind for its first paragraph (a heading
    // pasted into stays a heading) unless the paste said what it is
    if (parsed[0].k === "body" && old.k !== "body") { parsed[0].k = old.k; if (old.k === "check") parsed[0].c = !!old.c; }
    ed.replace(i, 1, parsed, { at: i + parsed.length - 1, pos: "end" });
  }

  // ── STRUCTURE ──────────────────────────────────────────────────────────
  // `count` blocks at `i` replaced with `list`; the caret then goes to
  // `caret` ({ at: index, pos: number | "end" | "start" })
  function replace(i, count, list, caret) {
    ed.flushTyping();
    ed.snap(true);
    const made = list.map((b) => ed._mk(b));
    const pics = made.filter((b) => b.k === "image" && b.src && !b.ocr).map((b) => b.src);
    if (pics.length) Qt.callLater(() => ed.picturesAdded(pics));
    for (let n = 0; n < count; n++) { delete ed._byKey[ed.blocks[i + n]._key]; }
    const next = ed.blocks.slice(0, i).concat(made).concat(ed.blocks.slice(i + count));
    ed.blocks = next;
    // the model: rows removed and inserted, the rest left alone
    if (count > 0) keys.remove(i, count);
    for (let n = 0; n < made.length; n++) keys.insert(i + n, { key: made[n]._key });
    if (ed.blocks.length === 0) { ed.blocks = [ed._mk(N.block("body", ""))]; keys.append({ key: ed.blocks[0]._key }); }
    ed.anchor = null;
    ed.rev++;
    ed.edited();
    if (caret) Qt.callLater(() => ed.place(caret.at, caret.pos));
  }
  function setAttr(k, field, value) {
    const b = ed.blockOf(k);
    if (!b) return;
    ed.flushTyping();
    ed.snap(true);
    if (value === undefined || value === null || value === false && field !== "c" || value === 0 && field === "l") delete b[field];
    else b[field] = value;
    ed.rev++;
    ed.edited();
  }
  // caret into block `i` at `pos` ("start", "end", a number, or {x} to
  // keep a column when moving up and down)
  function place(i, pos) {
    i = Math.max(0, Math.min(ed.blocks.length - 1, i));
    const it = rep.itemAt(i);
    if (!it) return;
    ed.cross = null;
    if (!it.isText) {
      if (it.kind === "table" && it.table()) { const t = it.table(); t.focusCell(pos === "end" ? t.nRows - 1 : 0, pos === "end" ? t.nCols - 1 : 0); return; }
      ed.mediaSel = it.key;
      keySink.forceActiveFocus();
      ed.reveal(it, null);
      return;
    }
    ed.mediaSel = "";
    it.te.forceActiveFocus();
    if (pos === "start") it.te.cursorPosition = 0;
    else if (pos === "end" || pos === undefined) it.te.cursorPosition = it.te.length;
    else if (typeof pos === "object") it.te.cursorPosition = it.te.positionAt(pos.x - it.te.x, pos.top ? 1 : it.te.height - 1);
    else it.te.cursorPosition = Math.max(0, Math.min(it.te.length, pos));
    it.te.deselect();
    ed.reveal(it, it.te.cursorRectangle);
  }
  function focusEnd(start) {
    // the last text block (a new note: its title)
    if (start) { ed.place(0, "start"); return; }
    // back to where the caret was, a table's cell included
    const cur = ed.current();
    if (cur && cur.kind === "table" && cur.table()) { cur.table().refocus(); return; }
    if (cur && cur.isText) { cur.te.forceActiveFocus(); return; }
    for (let i = ed.blocks.length - 1; i >= 0; i--) if (N.isText(ed.blocks[i])) { ed.place(i, "end"); return; }
    ed.place(ed.blocks.length - 1, "end");
  }
  property string cursorKey: ""
  function focused(k) { if (ed.tagKey !== "" && ed.tagKey !== k) ed.tagClear(); ed.cursorKey = k; if (ed.mediaSel !== "" && ed.mediaSel !== k) ed.mediaSel = ""; }
  function caretMoved(k, it) {
    if (!ed.crossing) ed.cross = null;
    if (ed.tagKey !== "" && (k !== ed.tagKey || it.te.cursorPosition <= ed.tagFrom)) ed.tagClear();
    ed.reveal(it, it.te.cursorRectangle);
  }
  // the caret kept in view as it moves (the glide is Elastic's)
  function reveal(it, r) {
    if (!it) return;
    const y = it.y + page.y + (r ? r.y + it.te.y + (it.te.parent ? it.te.parent.y : 0) : 0);
    const h = r ? r.height : it.height;
    const pad = 40;
    if (y - pad < view.contentY) view.contentY = Math.max(0, y - pad);
    else if (y + h + pad > view.contentY + view.height)
      view.contentY = Math.min(Math.max(0, view.contentHeight - view.height), y + h + pad - view.height);
  }

  // the block the caret is in, and the caret
  function current() { return ed.itemOf(ed.cursorKey); }

  // ── KEYS ───────────────────────────────────────────────────────────────
  function key(k, it, e) {
    const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier, alt = e.modifiers & Qt.AltModifier;
    const te = it.te;
    const pos = te.cursorPosition;
    const len = te.length;
    const hasSel = te.selectionStart !== te.selectionEnd;
    const i = ed.indexOf(k);
    const b = ed.blocks[i];
    if (!b) return false;
    if (ed.readOnly) {
      if (ctrl && e.key === Qt.Key_C) return false;
      if (ctrl && e.key === Qt.Key_A) { ed.selectAll(); return true; }
      return false;
    }

    // a selection over several blocks takes every key first
    if (ed.cross && ed.crossKey(e)) return true;
    // then the tags offered, if any
    if (ed.tagKeyPress(k, e)) return true;
    // curly quotes and dashes, as typed (Settings: Smart punctuation)
    if (!ctrl && !alt && ed.smarten(it, b, e)) return true;

    // undo is the page's, not one block's
    if (ctrl && e.key === Qt.Key_Z && !shift) { ed.undo(); return true; }
    if (ctrl && (e.key === Qt.Key_Y || (shift && e.key === Qt.Key_Z))) { ed.redo(); return true; }
    if (ctrl && e.key === Qt.Key_A) {
      if (hasSel && te.selectionStart === 0 && te.selectionEnd === len || len === 0) { ed.selectAll(); return true; }
      return false;
    }
    if (ctrl && e.key === Qt.Key_V && !shift) { ed.pasteAsked(); return true; }
    if (ctrl && e.key === Qt.Key_V && shift) { ed.pastePlainAsked(); return true; }
    if (ctrl && !shift && e.key === Qt.Key_B) { ed.mark("b"); return true; }
    if (ctrl && !shift && e.key === Qt.Key_I) { ed.mark("i"); return true; }
    if (ctrl && !shift && e.key === Qt.Key_U) { ed.mark("u"); return true; }
    if (ctrl && shift && e.key === Qt.Key_X) { ed.mark("s"); return true; }
    if (ctrl && shift && !alt) {
      const kinds = { [Qt.Key_T]: "title", [Qt.Key_H]: "heading", [Qt.Key_J]: "subheading", [Qt.Key_B]: "body",
                      [Qt.Key_M]: "mono", [Qt.Key_L]: "check", [Qt.Key_7]: "bullet", [Qt.Key_8]: "dash", [Qt.Key_9]: "number",
                      [Qt.Key_Ampersand]: "bullet", [Qt.Key_Asterisk]: "dash", [Qt.Key_ParenLeft]: "number", [Qt.Key_Greater]: "quote" };
      if (kinds[e.key]) { ed.setKind(kinds[e.key]); return true; }
      if (e.key === Qt.Key_U) { ed.toggleCheck(); return true; }
    }
    if (ctrl && alt && e.key === Qt.Key_T) { ed.insertTable(); return true; }

    // Math Notes: tab takes the answer
    if (e.key === Qt.Key_Tab && ed.ghostKey === k && ed.ghost !== "") { ed.takeGhost(it); return true; }

    if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !ctrl) {
      if (shift && b.k !== "mono") { te.insert(pos, "<br />"); return true; }
      return ed.enter(i, it, pos, len, hasSel);
    }
    if (e.key === Qt.Key_Backspace && !hasSel && pos === 0 && !ctrl) return ed.backAtStart(i, it);
    if (e.key === Qt.Key_Delete && !hasSel && pos === len) return ed.joinNext(i, it);
    if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
      if (b.k === "mono" && e.key === Qt.Key_Tab) { te.insert(pos, "    "); return true; }
      ed.indent(e.key === Qt.Key_Backtab || shift ? -1 : 1);
      return true;
    }
    if (e.key === Qt.Key_Space && !ctrl && b.k !== "mono" && pos <= 6) {
      const lead = te.getText(0, pos) + " ";
      const sc = N.shortcut(lead);
      if (sc && (b.k === "body" || N.isList(b) && sc.k !== b.k)) {
        te.remove(0, pos);
        ed.flushTyping();
        ed.setKind(sc.k, sc.c);
        return true;
      }
    }
    if (e.key === Qt.Key_Greater && pos > 0 && te.getText(pos - 1, pos) === ">" && b.k !== "mono") {
      te.remove(pos - 1, pos);
      ed.noteLinkAsked();
      return true;
    }
    if (e.key === Qt.Key_QuoteLeft && b.k === "body" && te.getText(0, pos) === "``" && len === 2) {
      te.remove(0, 2);
      ed.flushTyping();
      ed.setKind("mono");
      return true;
    }
    if (e.key === Qt.Key_Minus && b.k === "body" && te.getText(0, len) === "--" && pos === 2) {
      // "---": a divider, and a fresh line under it
      te.remove(0, 2);
      ed.flushTyping();
      ed.replace(i, 1, [N.block("rule", ""), N.block("body", "")], { at: i + 1, pos: "start" });
      return true;
    }

    // alt ↑ ↓: the line itself carried past the one above or below (a
    // checklist reordered by keys), the caret going with it
    if (alt && !ctrl && !shift && (e.key === Qt.Key_Up || e.key === Qt.Key_Down)) {
      const to = e.key === Qt.Key_Up ? i - 1 : i + 2;
      if (to < 0 || to > ed.blocks.length) return true;
      ed.moveBlock(k, to, false);
      ed.mediaSel = "";
      const at = ed.indexOf(k);
      Qt.callLater(() => ed.place(at, pos));
      return true;
    }

    // the arrows, across blocks
    const lineTop = te.cursorRectangle.y <= te.positionToRectangle(0).y + 1;
    const lineBottom = te.cursorRectangle.y >= te.positionToRectangle(len).y - 1;
    if (e.key === Qt.Key_Up && lineTop && !ctrl) {
      if (shift) { ed.extend(i, it, -1); return true; }
      if (i === 0) { te.cursorPosition = 0; return true; }
      ed.go(i, -1, { x: te.cursorRectangle.x + te.x, top: false });
      return true;
    }
    if (e.key === Qt.Key_Down && lineBottom && !ctrl) {
      if (shift) { ed.extend(i, it, 1); return true; }
      if (i === ed.blocks.length - 1) { te.cursorPosition = len; return true; }
      ed.go(i, 1, { x: te.cursorRectangle.x + te.x, top: true });
      return true;
    }
    if (e.key === Qt.Key_Left && pos === 0 && !hasSel && !shift && i > 0) { ed.go(i, -1, "end"); return true; }
    if (e.key === Qt.Key_Right && pos === len && !hasSel && !shift && i < ed.blocks.length - 1) { ed.go(i, 1, "start"); return true; }
    if (ctrl && e.key === Qt.Key_Home) { ed.place(0, "start"); return true; }
    if (ctrl && e.key === Qt.Key_End) { ed.focusEnd(false); return true; }
    if (e.key === Qt.Key_Escape) { te.deselect(); ed.escaped(); return true; }
    return false;
  }
  // the next shown block that way, skipping folded ones
  function go(i, d, pos) {
    let j = i + d;
    while (j >= 0 && j < ed.blocks.length && ed._hidden[j]) j += d;
    if (j < 0 || j >= ed.blocks.length) return;
    ed.place(j, pos);
  }

  function enter(i, it, pos, len, hasSel) {
    const b = ed.blocks[i];
    const te = it.te;
    if (hasSel) { te.remove(te.selectionStart, te.selectionEnd); pos = te.cursorPosition; len = te.length; }
    if (b.k === "mono") {
      // a code block takes newlines; an empty last line leaves it
      const t = te.text;
      if (pos === len && t.endsWith("\n")) {
        te.remove(len - 1, len);
        ed.flushTyping();
        ed.replace(i + 1, 0, [N.block("body", "")], { at: i + 1, pos: "start" });
        return true;
      }
      te.insert(pos, "\n");
      return true;
    }
    ed.flushTyping();
    const empty = len === 0;
    // an empty list item, quote or heading ends the run: it becomes a line
    if (empty && (N.isList(b) || b.k === "quote")) {
      if (b.l) { ed.setAttr(it.key, "l", b.l - 1); return true; }
      ed.setKind("body");
      return true;
    }
    const left = pos === 0 ? "" : ed.keep(it.range(0, pos));
    const right = pos >= len ? "" : ed.keep(it.range(pos, len));
    const kind = N.isList(b) || b.k === "quote" ? b.k : "body";
    const extra = {};
    if (b.l && (N.isList(b) || b.k === "quote")) extra.l = b.l;
    if (kind === "check") extra.c = false;
    // Return at the very start of a non-empty line: an empty line above it
    if (pos === 0 && len > 0) {
      const above = N.block(N.isHeading(b) ? "body" : kind, "", extra);
      ed.replace(i, 0, [above], { at: i + 1, pos: "start" });
      return true;
    }
    const first = Object.assign({}, b, { h: left });
    delete first._key;
    ed.replace(i, 1, [first, N.block(kind, right, extra)], { at: i + 1, pos: "start" });
    return true;
  }
  function backAtStart(i, it) {
    const b = ed.blocks[i];
    if (N.isList(b) || b.k === "quote" || N.isHeading(b) && i > 0 || b.k === "mono") {
      if (b.l) { ed.setAttr(it.key, "l", b.l - 1); return true; }
      ed.setKind("body");
      return true;
    }
    if (b.l) { ed.setAttr(it.key, "l", b.l - 1); return true; }
    if (i === 0) return true;
    // the block before: a picture is chosen first (a second backspace
    // takes it), a line is joined
    let j = i - 1;
    while (j > 0 && ed._hidden[j]) j--;
    const p = ed.blocks[j];
    if (!N.isText(p)) {
      if (it.te.length === 0) { ed.replace(i, 1, [], null); }
      ed.mediaSel = p._key;
      keySink.forceActiveFocus();
      return true;
    }
    return ed.join(j, i);
  }
  function joinNext(i, it) {
    if (i >= ed.blocks.length - 1) return true;
    const n = ed.blocks[i + 1];
    if (!N.isText(n)) { ed.mediaSel = n._key; keySink.forceActiveFocus(); return true; }
    return ed.join(i, i + 1);
  }
  // block `b` joined onto the end of block `a`
  function join(a, b) {
    ed.flushTyping();
    const A = ed.blocks[a], B = ed.blocks[b];
    const at = rep.itemAt(a) ? rep.itemAt(a).te.length : 0;
    const merged = Object.assign({}, A);
    delete merged._key;
    merged.h = A.k === "mono" ? A.h + N.plain(B.h) : A.h + (B.k === "mono" ? N.htmlOfText(B.h) : B.h);
    const list = [merged];
    // anything between (folded away) stays, after
    for (let x = a + 1; x < b; x++) { const o = Object.assign({}, ed.blocks[x]); delete o._key; list.push(o); }
    ed.replace(a, b - a + 1, list, { at: a, pos: at });
    return true;
  }

  // ── WHAT A BLOCK IS ────────────────────────────────────────────────────
  // the blocks the caret or the selection covers
  function targets() {
    if (ed.cross) {
      const out = [];
      for (let x = ed.cross.from; x <= ed.cross.to; x++) out.push(x);
      return out;
    }
    const i = ed.indexOf(ed.cursorKey !== "" ? ed.cursorKey : ed.mediaSel);
    return i >= 0 ? [i] : [];
  }
  function setKind(k, checked) {
    const ts = ed.targets();
    if (ts.length === 0) return;
    ed.flushTyping();
    ed.snap(true);
    // all of them that kind already: back to lines (a toggle, as Apple's)
    const all = ts.every((x) => ed.blocks[x].k === k);
    for (const x of ts) {
      const b = ed.blocks[x];
      if (!N.isText(b)) continue;
      const to = all && k !== "body" ? "body" : k;
      if (b.k === "mono" && to !== "mono") b.h = N.htmlOfText(b.h);
      else if (to === "mono" && b.k !== "mono") b.h = N.plain(b.h);
      b.k = to;
      if (to === "check") b.c = !!checked; else delete b.c;
      if (!N.isHeading(b)) delete b.fold;
      if (!(N.isList(b) || to === "quote" || to === "body") || N.isHeading(b)) delete b.l;
    }
    ed.rev++;
    for (const x of ts) { const it = rep.itemAt(x); if (it) it.reload(); }
    ed.edited();
    const it = ed.current();
    if (it && !ed.cross) Qt.callLater(() => { if (it.te) it.te.forceActiveFocus(); });
  }
  // how the lines of the blocks in hand sit: "" (along the left, or the
  // right for a right-to-left script), "center", "right", "justify". A
  // picture chosen: its row's, kept on the row's first block
  function setAlign(a) {
    let ts;
    if (ed.mediaSel !== "" && !ed.cross) ts = [ed.rowStart(ed.indexOf(ed.mediaSel))];
    else ts = ed.targets().map((x) => ed.sideKind(ed.blocks[x]) ? ed.rowStart(x) : x)
      .filter((x, n, all) => all.indexOf(x) === n && (ed.sideKind(ed.blocks[x]) || N.isText(ed.blocks[x]) && ed.blocks[x].k !== "mono"));
    if (ts.length === 0 || ts[0] < 0) return;
    ed.flushTyping();
    ed.snap(true);
    for (const x of ts) { if (a) ed.blocks[x].align = a; else delete ed.blocks[x].align; }
    ed.rev++;
    ed.edited();
  }
  function alignHere() {
    void ed.rev; void ed.cursorKey; void ed.mediaSel;
    const k = ed.mediaSel !== "" ? ed.mediaSel : ed.cursorKey;
    const i = ed.indexOf(k);
    if (i < 0) return "";
    const b = ed.blocks[ed.sideKind(ed.blocks[i]) ? ed.rowStart(i) : i];
    return b && b.align ? b.align : "";
  }
  // the first block of the row block i stands in (itself, alone)
  function rowStart(i) { if (i < 0) return i; while (i > 0 && ed.joins(i)) i--; return i; }
  // a picture's row: how it is aligned (its first block's say)
  function rowAlign(k) {
    void ed.rev; void ed.blocks;
    const i = ed.indexOf(k);
    if (i < 0) return "";
    const b = ed.blocks[ed.rowStart(i)];
    return b && b.align ? b.align : "";
  }
  // an aligned row's block x: the row's pictures packed together (each as
  // wide as it is drawn) and the group set center or right; justified,
  // spread from edge to edge
  function rowX(k) {
    void ed.rev; void ed.blocks;
    const i = ed.indexOf(k);
    if (i < 0) return 0;
    const s = ed.rowStart(i);
    let e = i;
    while (e + 1 < ed.blocks.length && ed.joins(e + 1)) e++;
    const a = ed.rowAlign(k), ws = [];
    for (let x = s; x <= e; x++) { const it = rep.itemAt(x); ws.push(it ? it.width : 0); }
    const before = ws.slice(0, i - s).reduce((p, w) => p + w, 0);
    const sum = ws.reduce((p, w) => p + w, 0), n = ws.length;
    if (a === "justify") return n === 1 ? 0 : before + (i - s) * Math.max(ed.rowGap, (ed.columnW - sum) / (n - 1));
    const total = sum + ed.rowGap * (n - 1);
    const start = Math.max(0, a === "center" ? (ed.columnW - total) / 2 : ed.columnW - total);
    return Math.round(start + before + (i - s) * ed.rowGap);
  }
  function toggleCheck(k) {
    const ts = k ? [ed.indexOf(k)] : ed.targets();
    const checks = ts.filter((x) => x >= 0 && ed.blocks[x].k === "check");
    if (checks.length === 0) { ed.setKind("check"); return; }
    ed.flushTyping();
    ed.snap(true);
    const to = !checks.every((x) => ed.blocks[x].c);
    for (const x of checks) ed.blocks[x].c = to;
    ed.rev++;
    ed.edited();
    if (to && ed.sinkOnTick) sinkTimer.restart();
  }
  // a beat after the tick, so the box is seen ticked before it moves
  Timer { id: sinkTimer; interval: 450; onTriggered: ed.sinkChecked() }
  // every box, ticked or not; or the ticked ones moved under the rest
  function checkAll(on) {
    ed.flushTyping();
    ed.snap(true);
    for (const b of ed.blocks) if (b.k === "check") b.c = on;
    ed.rev++;
    ed.edited();
  }
  // every ticked item gone, in one undo step (Apple's "Delete Checked Items")
  function deleteTicked() {
    ed.flushTyping();
    const gone = [];
    ed.blocks.forEach((b, x) => { if (b.k === "check" && b.c) gone.push(x); });
    if (gone.length === 0) return 0;
    ed.snap(true);
    for (let n = gone.length - 1; n >= 0; n--) {
      const x = gone[n];
      delete ed._byKey[ed.blocks[x]._key];
      keys.remove(x, 1);
    }
    ed.blocks = ed.blocks.filter((b) => !(b.k === "check" && b.c));
    if (ed.blocks.length === 0) { ed.blocks = [ed._mk(N.block("body", ""))]; keys.append({ key: ed.blocks[0]._key }); }
    ed.anchor = null;
    ed.rev++;
    ed.edited();
    return gone.length;
  }
  function sinkChecked() {
    ed.flushTyping();
    // within each run of checklist items: the ticked ones last, in order
    const out = [];
    let run = [];
    const flushRun = () => { out.push(...run.filter((b) => !b.c), ...run.filter((b) => b.c)); run = []; };
    for (const b of ed.blocks) {
      if (b.k === "check") run.push(b); else { flushRun(); out.push(b); }
    }
    flushRun();
    if (out.every((b, i) => b === ed.blocks[i])) return;
    ed.replace(0, ed.blocks.length, out.map((b) => { const o = Object.assign({}, b); delete o._key; return o; }), null);
  }
  function indent(d) {
    const ts = ed.targets();
    ed.flushTyping();
    ed.snap(true);
    for (const x of ts) {
      const b = ed.blocks[x];
      if (!N.isText(b) || N.isHeading(b)) continue;
      const l = Math.max(0, Math.min(N.MAX_LEVEL, (b.l || 0) + d));
      if (l === 0) delete b.l; else b.l = l;
    }
    ed.rev++;
    ed.edited();
  }
  function fold(k) {
    const b = ed.blockOf(k);
    if (!b) return;
    ed.setAttr(k, "fold", !b.fold);
  }

  // ── MARKS AND COLORS ──────────────────────────────────────────────────
  // a run of each block in the selection, rewritten by `fn(run)`; with no
  // selection, the word under the caret (Apple's), else the whole line
  function rewrite(fn) {
    ed.flushTyping();
    ed.snap(true);
    const spans = ed.spans();
    for (const s of spans) {
      const it = rep.itemAt(s.i);
      if (!it || !it.isText || ed.blocks[s.i].k === "mono" || s.b <= s.a) continue;
      const run = it.range(s.a, s.b);
      const next = fn(ed.keep(run));
      it.te.remove(s.a, s.b);
      it.te.insert(s.a, ed.display(next));
      const len = it.te.length;
      if (s.keep) it.te.select(s.a, Math.min(len, s.a + (s.b - s.a)));
    }
    ed.flushTyping();
    ed.edited();
  }
  // [{ i, a, b, keep }] — what a format acts on
  function spans() {
    if (ed.cross) {
      const out = [];
      for (let x = ed.cross.from; x <= ed.cross.to; x++) {
        const it = rep.itemAt(x);
        if (!it || !it.isText) continue;
        const a = x === ed.cross.from ? ed.cross.fromPos : 0;
        const b = x === ed.cross.to ? ed.cross.toPos : it.te.length;
        out.push({ i: x, a: a, b: b, keep: false });
      }
      return out;
    }
    const it = ed.current();
    if (!it || !it.isText) return [];
    const i = ed.indexOf(it.key);
    const te = it.te;
    if (te.selectionStart !== te.selectionEnd) return [{ i: i, a: te.selectionStart, b: te.selectionEnd, keep: true }];
    return [{ i: i, a: 0, b: te.length, keep: false }];
  }
  function mark(tag) {
    // one answer for the whole selection: on unless all of it is already
    const runs = ed.spans().map((s) => { const it = rep.itemAt(s.i); return it && s.b > s.a ? it.range(s.a, s.b) : ""; }).filter((r) => r !== "");
    const on = !runs.every((r) => N.marked(r, tag));
    ed.rewrite((run) => on ? (N.marked(run, tag) ? run : N.toggleMark(run, tag)) : N.unmark(run, tag));
  }
  function ink(name) {
    ed.rewrite((run) => N.colour(run, "color", name ? N.sentinel("ink", N.INKS.indexOf(name)) : ""));
  }
  function highlight(name) {
    ed.rewrite((run) => N.colour(run, "background-color", name ? N.sentinel("mark", N.MARKERS.indexOf(name)) : ""));
  }
  // a typeface for the words in hand only, the rest of the block keeping
  // the note's ("" takes them back to it) — notes.js face
  // a wrong word put right: the suggestion in its place, one undo step
  function respellWord(key, run, word) {
    const it = ed.itemOf(key);
    if (!it || !it.isText || ed.readOnly) return;
    if (it.te.getText(run.a, run.b).replace(/’/g, "'") !== run.w) return;
    ed.flushTyping();
    ed.snap(true);
    it.te.remove(run.a, run.b);
    it.te.insert(run.a, N.escape(word));
    it.te.cursorPosition = run.a + word.length;
    ed.flushTyping();
    ed.edited();
  }
  function runFace(family) {
    ed.rewrite((run) => N.face(run, family));
  }
  function plainText() {
    ed.rewrite((run) => N.escape(N.plain(run)).replace(/\n/g, "<br />"));
  }
  // a link round the selection (or the URL itself, typed in)
  function link(url, label) {
    const it = ed.current();
    if (!it || !it.isText || it.kind === "mono") return;
    const te = it.te;
    const href = /^[a-z][a-z0-9+.-]*:/i.test(url) ? url : "https://" + url;
    ed.snap(true);
    if (te.selectionStart !== te.selectionEnd) {
      const a = te.selectionStart, b = te.selectionEnd;
      const run = ed.keep(it.range(a, b)).replace(/<\/?a\b[^>]*>/gi, "");
      te.remove(a, b);
      te.insert(a, ed.display("<a href=\"" + N.escape(href) + "\">" + run + "</a>"));
    } else {
      te.insert(te.cursorPosition, ed.display("<a href=\"" + N.escape(href) + "\">" + N.escape(label || url) + "</a>") + "&nbsp;");
    }
    ed.edited();
  }
  function insertNoteLink(id, title) {
    const it = ed.current();
    if (!it || !it.isText) return;
    it.te.forceActiveFocus();
    it.te.insert(it.te.cursorPosition, ed.display("<a href=\"clio:note/" + N.escape(id) + "\">" + N.escape(title) + "</a>") + "&nbsp;");
    ed.edited();
  }
  // the selected words, as plain text (for a link's label, a search)
  function selectedText() {
    if (ed.cross) return ed.crossText(false);
    const it = ed.current();
    return it && it.isText ? it.te.selectedText : "";
  }
  // the href under the caret, if any (Edit Link)
  function linkHere() {
    const it = ed.current();
    if (!it || !it.isText) return "";
    const r = it.te.cursorRectangle;
    return it.te.linkAt(r.x + 1, r.y + r.height / 2);
  }

  // ── PUTTING THINGS IN ──────────────────────────────────────────────────
  // after the caret's block (or replacing it when it is an empty line)
  function insertBlocks(list, focusLast) {
    let i = ed.indexOf(ed.cursorKey !== "" ? ed.cursorKey : ed.mediaSel);
    if (i < 0) i = ed.blocks.length - 1;
    const it = rep.itemAt(i);
    const empty = it && it.isText && it.te.length === 0 && ed.blocks[i].k === "body";
    const at = empty ? i : i + 1;
    // something to type on after a picture or a table
    const tail = !N.isText(list[list.length - 1]) && (at + (empty ? 1 : 0) >= ed.blocks.length || !N.isText(ed.blocks[at + (empty ? 1 : 0)]))
      ? [N.block("body", "")] : [];
    ed.replace(at, empty ? 1 : 0, list.concat(tail), { at: at + list.length - (focusLast ? 1 : 0) + (tail.length && !focusLast ? 0 : 0), pos: "end" });
  }
  function insertTable() { ed.insertBlocks([N.block("table", "", { rows: [["", ""], ["", ""], ["", ""]] })], true); }
  function insertRule() { ed.insertBlocks([N.block("rule", "")], false); }
  // a whole block's attachment, handed back by the backend
  function attachBlock(b) { ed.insertBlocks([N.block(b.k, "", { src: b.src, name: b.name, size: b.size })], false); }
  // a rich paste the owner did not take as a picture: the block's own paste
  function pasteText() {
    const it = ed.current();
    if (ed.cross) ed.deleteCross();
    const now = ed.current();
    if (now && now.isText) now.te.paste();
  }

  // PASTE AS PLAIN TEXT (user, 2026-10-15): the words alone, at the caret,
  // over whatever is selected — escaped, a line break a soft break, as a
  // rich paste flattened by "Plain text" (see the rewrite above) would be
  function pastePlain(text) {
    const t = String(text || "").replace(/\r\n?/g, "\n").replace(/\n+$/, "");
    if (t === "" || ed.readOnly) return;
    if (ed.cross) ed.deleteCross();
    const it = ed.current();
    if (!it || !it.isText) return;
    ed.snap(false);
    const te = it.te;
    if (te.selectionStart !== te.selectionEnd) te.remove(te.selectionStart, te.selectionEnd);
    te.insert(te.cursorPosition, it.kind === "mono" ? t : N.escape(t).replace(/\n/g, "<br />"));
  }

  // ── TABLES ─────────────────────────────────────────────────────────────
  function cellTyped(k, r, c, h) {
    const b = ed.blockOf(k);
    if (!b || !b.rows[r]) return;
    ed.snap(false);
    b.rows[r][c] = h;
    ed.edited();
  }
  function cellKey(k, tbl, r, c, te, e) {
    const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
    if (ctrl && e.key === Qt.Key_Z && !shift) { ed.undo(); return true; }
    if (ctrl && (e.key === Qt.Key_Y || shift && e.key === Qt.Key_Z)) { ed.redo(); return true; }
    if (ctrl && !shift && e.key === Qt.Key_B) { ed.cellMark(te, "b"); return true; }
    if (ctrl && !shift && e.key === Qt.Key_I) { ed.cellMark(te, "i"); return true; }
    if (ctrl && !shift && e.key === Qt.Key_U) { ed.cellMark(te, "u"); return true; }
    if (e.key === Qt.Key_Tab && !shift) {
      if (c + 1 < tbl.nCols) tbl.focusCell(r, c + 1, 0);
      else if (r + 1 < tbl.nRows) tbl.focusCell(r + 1, 0, 0);
      else { ed.tableRow(k, r + 1); Qt.callLater(() => tbl.focusCell(r + 1, 0, 0)); }
      return true;
    }
    if (e.key === Qt.Key_Backtab || e.key === Qt.Key_Tab && shift) {
      if (c > 0) tbl.focusCell(r, c - 1); else if (r > 0) tbl.focusCell(r - 1, tbl.nCols - 1);
      return true;
    }
    const top = te.cursorRectangle.y <= te.positionToRectangle(0).y + 1;
    const bottom = te.cursorRectangle.y >= te.positionToRectangle(te.length).y - 1;
    if (e.key === Qt.Key_Up && top) { if (r > 0) tbl.focusCell(r - 1, c); else ed.go(ed.indexOf(k), -1, "end"); return true; }
    if (e.key === Qt.Key_Down && bottom) { if (r + 1 < tbl.nRows) tbl.focusCell(r + 1, c); else ed.go(ed.indexOf(k), 1, "start"); return true; }
    if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !shift) {
      if (r + 1 < tbl.nRows) tbl.focusCell(r + 1, c, 0); else ed.go(ed.indexOf(k), 1, "start");
      return true;
    }
    if (e.key === Qt.Key_Escape) { ed.go(ed.indexOf(k), 1, "start"); return true; }
    return false;
  }
  function cellMark(te, tag) {
    const a = te.selectionStart, b = te.selectionEnd;
    if (b <= a) return;
    const run = ed.keep(N.inline(te.getFormattedText(a, b)));
    te.remove(a, b);
    te.insert(a, ed.display(N.toggleMark(run, tag)));
    te.select(a, b);
  }
  function tableRow(k, at, remove) {
    const b = ed.blockOf(k);
    if (!b) return;
    ed.snap(true);
    const rows = b.rows.map((r) => r.slice());
    if (remove) { if (rows.length > 1) rows.splice(at, 1); }
    else rows.splice(at, 0, rows[0].map(() => ""));
    b.rows = rows;
    ed.rev++;
    ed.edited();
  }
  function tableCol(k, at, remove) {
    const b = ed.blockOf(k);
    if (!b) return;
    ed.snap(true);
    b.rows = b.rows.map((r) => { const o = r.slice(); if (remove) { if (o.length > 1) o.splice(at, 1); } else o.splice(at, 0, ""); return o; });
    ed.rev++;
    ed.edited();
  }

  // ── MEDIA ──────────────────────────────────────────────────────────────
  property string mediaSel: ""
  // a picture, a file, a divider or a table picked up and carried to
  // another place in the note: `dragKey` the one carried, `dropAt` the
  // gap it would land in (0 before the first block … length after the last)
  property string dragKey: ""
  property int dropAt: -1
  // or, carried onto the right of another picture or file: that one's
  // index, the carried one to stand beside it
  property int dropBeside: -1
  // `beside`: standing in the row of the block before where it lands
  // (false: a line of its own)
  function moveBlock(k, to, beside) {
    const from = ed.indexOf(k);
    if (from < 0 || ed.readOnly) return;
    to = Math.max(0, Math.min(ed.blocks.length, to));
    const was = !!ed.blockOf(k).beside;
    // the gaps either side of it leave it where it is (but maybe now in a row)
    if (to === from || to === from + 1) { if (was !== !!beside) ed.setBeside(k, beside); ed.mediaSel = k; return; }
    ed.flushTyping();
    ed.snap(true);
    if (beside) ed.blockOf(k).beside = true; else delete ed.blockOf(k).beside;
    const dest = to > from ? to - 1 : to;
    const next = ed.blocks.slice();
    const moved = next.splice(from, 1)[0];
    next.splice(dest, 0, moved);
    ed.blocks = next;
    keys.move(from, dest, 1);
    ed.anchor = null;
    ed.rev++;
    ed.edited();
    ed.mediaSel = k;
    Qt.callLater(() => ed.reveal(ed.itemOf(k), null));
  }
  // the gap a point in the overlay is nearest: above a block's middle, the
  // gap before it
  // blocks put in at gap `at`, the last one then chosen (a picture) or the
  // caret at its end (words)
  function insertAt(at, list) {
    if (!list.length || ed.readOnly) return;
    at = Math.max(0, Math.min(ed.blocks.length, at));
    const last = list[list.length - 1];
    ed.replace(at, 0, list, N.isText(last) ? { at: at + list.length - 1, pos: "end" } : null);
    if (!N.isText(last)) { ed.mediaSel = ed.keyAt(at + list.length - 1); keySink.forceActiveFocus(); }
  }
  // ── ROWS ───────────────────────────────────────────────────────────────
  // A picture, a sketch or a file can stand beside the one before it (its
  // `beside`), when that one is one of those too: they share the column's
  // width, side by side, up to four to a row. Carried onto the right of
  // another, or from the menu; carried into a gap, it is on its own again.
  readonly property int rowGap: 10
  readonly property int rowMax: 4
  function sideKind(b) { return !!b && (b.k === "image" || b.k === "sketch" || b.k === "file"); }
  // whether block i stands in the row of the one before it
  function joins(i) {
    if (i <= 0 || i >= ed.blocks.length) return false;
    const b = ed.blocks[i];
    if (!b.beside || !ed.sideKind(b) || !ed.sideKind(ed.blocks[i - 1])) return false;
    let n = 1;
    for (let s = i - 1; s > 0 && ed.joins(s); s--) n++;
    return n < ed.rowMax;
  }
  // a block's place in its row: which, of how many
  function shareOf(k) {
    const i = ed.indexOf(k);
    if (i < 0) return { slot: 0, n: 1 };
    let s = i, e = i;
    while (s > 0 && ed.joins(s)) s--;
    while (e + 1 < ed.blocks.length && ed.joins(e + 1)) e++;
    return { slot: i - s, n: e - s + 1 };
  }
  // every block's y, from the heights above it: a row is as tall as its
  // tallest. Run as heights change (Block) and as blocks come and go.
  function relayout() {
    let rowTop = 0, rowH = 0;
    for (let i = 0; i < rep.count; i++) {
      const it = rep.itemAt(i);
      if (!it) continue;
      const h = it.visible ? it.height : 0;
      if (ed.joins(i)) { it.y = rowTop; rowH = Math.max(rowH, h); }
      else { rowTop += rowH; it.y = rowTop; rowH = h; }
    }
    col.height = rowTop + rowH;
  }
  onBlocksChanged: Qt.callLater(ed.relayout)
  function setBeside(k, on) { ed.setAttr(k, "beside", on ? true : null); }

  // the words read off a picture, kept on every block showing it — quietly:
  // not a step to undo
  function setOcr(src, text) {
    let any = false;
    for (const b of ed.blocks) if (b.k === "image" && b.src === src && b.ocr !== text) { b.ocr = text; any = true; }
    if (any) { ed.rev++; ed.edited(); }
  }

  // the gap after the block the caret (or the chosen picture) is in
  function caretGap() {
    const i = ed.indexOf(ed.cursorKey !== "" ? ed.cursorKey : ed.mediaSel);
    return i < 0 ? ed.blocks.length : i + 1;
  }
  // something dragged in from outside is over the note
  property bool dropOver: false
  function gapAt(h) {
    if (!h) return -1;
    // a row is one line: the gap before it or after it, never inside
    let s = h.i, e = h.i;
    while (s > 0 && ed.joins(s)) s--;
    while (e + 1 < ed.blocks.length && ed.joins(e + 1)) e++;
    return h.y < h.it.height / 2 ? s : e + 1;
  }
  function deleteMedia() {
    const i = ed.indexOf(ed.mediaSel);
    if (i < 0) return;
    ed.mediaSel = "";
    ed.replace(i, 1, [], { at: Math.max(0, i - 1), pos: "end" });
  }
  function resizeMedia(k, w) {
    const b = ed.blockOf(k);
    if (!b) return;
    b.w = Math.max(0.15, Math.min(1, w));
    ed.rev++;
  }
  // a picture redrawn (a sketch saved again): its Image asked afresh
  function touchMedia(k, extra) {
    const b = ed.blockOf(k);
    if (!b) return;
    ed.snap(true);
    Object.assign(b, extra || {});
    b.v = (b.v || 0) + 1;
    ed.rev++;
    ed.edited();
  }
  Item {
    id: keySink
    Keys.onPressed: (e) => {
      const ctrl = e.modifiers & Qt.ControlModifier;
      const i = ed.indexOf(ed.mediaSel);
      if (e.key === Qt.Key_Backspace || e.key === Qt.Key_Delete) { if (!ed.readOnly) ed.deleteMedia(); e.accepted = true; return; }
      if (ctrl && e.key === Qt.Key_Z) { ed.undo(); e.accepted = true; return; }
      // alt ↑ ↓ carries it up or down past the block next to it
      if (e.modifiers & Qt.AltModifier && (e.key === Qt.Key_Up || e.key === Qt.Key_Down)) {
        ed.moveBlock(ed.mediaSel, e.key === Qt.Key_Up ? i - 1 : i + 2);
        e.accepted = true;
        return;
      }
      if (e.key === Qt.Key_Up || e.key === Qt.Key_Left) { ed.go(i, -1, "end"); e.accepted = true; return; }
      if (e.key === Qt.Key_Down || e.key === Qt.Key_Right) { ed.go(i, 1, "start"); e.accepted = true; return; }
      if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
        if (ed.readOnly) return;
        ed.replace(i + 1, 0, [N.block("body", "")], { at: i + 1, pos: "start" });
        e.accepted = true;
        return;
      }
      if (e.key === Qt.Key_Escape) { ed.mediaSel = ""; ed.escaped(); e.accepted = true; return; }
      if (ctrl && e.key === Qt.Key_A) { ed.selectAll(); e.accepted = true; return; }
      // typing on a chosen picture: a new line after it
      if (!ed.readOnly && e.text && e.text.length > 0 && e.text.charCodeAt(0) >= 32 && !ctrl) {
        ed.replace(i + 1, 0, [N.block("body", N.escape(e.text))], { at: i + 1, pos: "end" });
        e.accepted = true;
      }
    }
  }

  // ── A SELECTION OVER MANY BLOCKS ───────────────────────────────────────
  // { from, fromPos, to, toPos } in reading order, and `anchor` (where it
  // started) so a drag or shift+arrow can swing round it
  property var cross: null
  property var anchor: null
  property bool crossing: false
  onCrossChanged: ed.paintCross()
  function setCross(a, z) {
    // a = { i, p }, z = { i, p }
    const fwd = a.i < z.i || a.i === z.i && a.p <= z.p;
    const s = fwd ? a : z, e = fwd ? z : a;
    if (s.i === e.i) {
      ed.cross = null;
      const it = rep.itemAt(s.i);
      if (it && it.isText) { ed.crossing = true; it.te.forceActiveFocus(); it.te.select(a.p, z.p); ed.crossing = false; }
      return;
    }
    ed.cross = { from: s.i, fromPos: s.p, to: e.i, toPos: e.p };
  }
  function paintCross() {
    ed.crossing = true;
    for (let x = 0; x < rep.count; x++) {
      const it = rep.itemAt(x);
      if (!it || !it.isText) continue;
      if (!ed.cross || x < ed.cross.from || x > ed.cross.to) { it.te.deselect(); continue; }
      const a = x === ed.cross.from ? ed.cross.fromPos : 0;
      const b = x === ed.cross.to ? ed.cross.toPos : it.te.length;
      it.te.select(a, b);
    }
    ed.crossing = false;
  }
  function selectAll() {
    const last = ed.blocks.length - 1;
    const it = rep.itemAt(last);
    ed.anchor = { i: 0, p: 0 };
    ed.cross = last === 0 ? null : { from: 0, fromPos: 0, to: last, toPos: it && it.isText ? it.te.length : 0 };
    if (last === 0 && it && it.isText) it.te.selectAll();
    keySink.forceActiveFocus();
    crossSink.forceActiveFocus();
  }
  function extend(i, it, d) {
    // shift+↑/↓ past a block's edge: the selection reaches into the next
    if (!ed.anchor || !ed.cross) ed.anchor = { i: i, p: it.te.selectionStart !== it.te.selectionEnd && d > 0 ? it.te.selectionStart : it.te.selectionEnd };
    const at = ed.cross ? (ed.cross.from === ed.anchor.i && ed.cross.fromPos === ed.anchor.p ? { i: ed.cross.to, p: ed.cross.toPos } : { i: ed.cross.from, p: ed.cross.fromPos }) : { i: i, p: it.te.cursorPosition };
    let j = at.i + d;
    if (j < 0 || j >= ed.blocks.length) return;
    const n = rep.itemAt(j);
    ed.setCross(ed.anchor, { i: j, p: d > 0 ? (n && n.isText ? n.te.length : 0) : 0 });
    crossSink.forceActiveFocus();
  }
  // the selection's words
  function crossText(rich) {
    if (!ed.cross) return "";
    const parts = [];
    for (let x = ed.cross.from; x <= ed.cross.to; x++) {
      const it = rep.itemAt(x);
      const b = ed.blocks[x];
      if (!it) continue;
      if (!it.isText) { if (rich) parts.push(b); continue; }
      const a = x === ed.cross.from ? ed.cross.fromPos : 0;
      const e = x === ed.cross.to ? ed.cross.toPos : it.te.length;
      if (rich) { const o = Object.assign({}, b, { h: ed.keep(it.range(a, e)) }); delete o._key; parts.push(o); }
      else parts.push(it.plainRange(a, e));
    }
    return rich ? parts : parts.join("\n");
  }
  function deleteCross() {
    const c = ed.cross;
    if (!c) return;
    ed.flushTyping();
    const first = rep.itemAt(c.from), last = rep.itemAt(c.to);
    const A = ed.blocks[c.from], Z = ed.blocks[c.to];
    const keepA = first && first.isText ? ed.keep(first.range(0, c.fromPos)) : null;
    const keepZ = last && last.isText ? ed.keep(last.range(c.toPos, last.te.length)) : "";
    const list = [];
    let caret = { at: c.from, pos: c.fromPos };
    if (keepA !== null) {
      const o = Object.assign({}, A, { h: keepA + (A.k === "mono" ? N.plain(keepZ) : keepZ) });
      delete o._key;
      list.push(o);
    } else if (keepZ !== "") list.push(N.block("body", keepZ));
    if (list.length === 0) { list.push(N.block("body", "")); caret.pos = 0; }
    ed.cross = null;
    ed.anchor = null;
    ed.replace(c.from, c.to - c.from + 1, list, caret);
  }
  function crossKey(e) {
    const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
    if (ctrl && e.key === Qt.Key_C) { ed.copyCross(); return true; }
    if (ctrl && e.key === Qt.Key_X) { if (ed.readOnly) return true; ed.copyCross(); ed.deleteCross(); return true; }
    if (ctrl && e.key === Qt.Key_A) { ed.selectAll(); return true; }
    if (ctrl && e.key === Qt.Key_Z) { ed.cross = null; ed.undo(); return true; }
    if (ctrl && !shift && e.key === Qt.Key_B) { ed.mark("b"); return true; }
    if (ctrl && !shift && e.key === Qt.Key_I) { ed.mark("i"); return true; }
    if (ctrl && !shift && e.key === Qt.Key_U) { ed.mark("u"); return true; }
    if (ctrl && shift && e.key === Qt.Key_X) { ed.mark("s"); return true; }
    if (ctrl && e.key === Qt.Key_V) { if (ed.readOnly) return true; ed.deleteCross(); Qt.callLater(ed.pasteAsked); return true; }
    if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) { ed.indent(e.key === Qt.Key_Backtab || shift ? -1 : 1); return true; }
    if (ctrl && shift) return false;
    if (e.key === Qt.Key_Escape) { const c = ed.cross; ed.cross = null; ed.place(c.to, c.toPos); return true; }
    if (shift && (e.key === Qt.Key_Up || e.key === Qt.Key_Down)) {
      const it = rep.itemAt(ed.cross.to);
      ed.extend(ed.cross.to, it, e.key === Qt.Key_Up ? -1 : 1);
      return true;
    }
    if (e.key === Qt.Key_Up || e.key === Qt.Key_Left) { const c = ed.cross; ed.cross = null; ed.place(c.from, c.fromPos); return true; }
    if (e.key === Qt.Key_Down || e.key === Qt.Key_Right) { const c = ed.cross; ed.cross = null; ed.place(c.to, c.toPos); return true; }
    if (ed.readOnly) return true;
    if (e.key === Qt.Key_Backspace || e.key === Qt.Key_Delete) { ed.deleteCross(); return true; }
    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { ed.deleteCross(); return true; }
    if (e.text && e.text.length > 0 && e.text.charCodeAt(0) >= 32 && !ctrl) {
      const t = e.text;
      ed.deleteCross();
      Qt.callLater(() => { const it = ed.current(); if (it && it.isText) it.te.insert(it.te.cursorPosition, it.kind === "mono" ? t : N.escape(t)); });
      return true;
    }
    return false;
  }
  function copyCross() {
    const parts = ed.crossText(true);
    clip.textFormat = TextEdit.RichText;
    clip.text = N.htmlOf(parts, ed.base);
    clip.selectAll();
    clip.copy();
    clip.text = "";
  }
  // the copy's go-between: a TextEdit puts html and plain text on the
  // clipboard together, which is what a paste elsewhere wants
  TextEdit { id: clip; visible: false; textFormat: TextEdit.RichText }
  Item {
    id: crossSink
    Keys.onPressed: (e) => { if (ed.cross && ed.crossKey(e)) e.accepted = true; }
  }
  // copy the whole note (the menu's "Copy note")
  function copyAll() {
    clip.textFormat = TextEdit.RichText;
    clip.text = N.htmlOf(ed.stored(), "file://" + ed.base);
    clip.selectAll();
    clip.copy();
    clip.text = "";
  }

  // ── UNDO ───────────────────────────────────────────────────────────────
  // Whole snapshots of the page: a structural change takes one before it
  // happens; typing takes one when it starts again after a pause.
  UndoStack { id: history }
  property real _lastSnap: 0
  function state() {
    const it = ed.current();
    return { blocks: ed.blocks.map((b) => { const o = Object.assign({}, b); delete o._key; if (o.rows) o.rows = o.rows.map((r) => r.slice()); return o; }),
             at: it ? ed.indexOf(it.key) : 0, pos: it && it.isText ? it.te.cursorPosition : 0 };
  }
  function snap(structural) {
    const now = Date.now();
    if (!structural && now - ed._lastSnap < 1200) { ed._lastSnap = now; return; }
    ed._lastSnap = now;
    // typing still waiting to be read is part of the state before
    const pending = Object.keys(ed._dirtyKeys).length > 0;
    if (pending && structural) {
      const d = ed._dirtyKeys;
      ed._dirtyKeys = ({});
      for (const k in d) { const b = ed.blockOf(k), it = d[k]; if (b && it) { b.h = b.k === "mono" ? it.te.text : ed.keep(N.inline(it.te.text)); it.shown = b.h; } }
    }
    history.record(ed.state());
  }
  function restore(st) {
    const y = view.contentY;
    ed.load(st.blocks, { keepY: true, keepUndo: true });
    view.contentY = Math.max(0, Math.min(y, view.contentHeight - view.height));
    Qt.callLater(() => { view.contentY = Math.max(0, Math.min(y, view.contentHeight - view.height)); ed.place(st.at, st.pos); });
    ed.edited();
  }
  function undo() {
    ed.flushTyping();
    if (!history.canUndo) return;
    ed.restore(history.undo(ed.state()));
    ed._lastSnap = 0;
  }
  function redo() {
    if (!history.canRedo) return;
    ed.restore(history.redo(ed.state()));
    ed._lastSnap = 0;
  }

  // ── MATH NOTES ─────────────────────────────────────────────────────────
  property string ghost: ""
  property string ghostKey: ""
  property int _mathSeq: 0
  Timer {
    id: mathTimer
    interval: 350
    onTriggered: {
      const it = ed.current();
      if (!it || !it.isText || it.kind === "mono" || ed.readOnly) return;
      const te = it.te;
      if (te.cursorPosition !== te.length) return;
      const lines = N.plain(ed.blockOf(it.key).h).split("\n");
      const line = lines[lines.length - 1];
      if (!/=\s*$/.test(line)) return;
      const i = ed.indexOf(it.key);
      const earlier = [];
      for (let x = 0; x < i; x++) if (N.isText(ed.blocks[x])) earlier.push(...N.plain(ed.blocks[x].h).split("\n"));
      earlier.push(...lines.slice(0, -1));
      const expr = N.mathAsk(line, N.mathVars(earlier));
      if (!expr) return;
      ed.ghostKey = it.key;
      ed.mathAsked(++ed._mathSeq, expr);
    }
  }
  function mathAnswer(seq, text) {
    if (seq !== ed._mathSeq) return;
    ed.ghost = text || "";
  }
  function takeGhost(it) {
    const t = ed.ghost;
    ed.ghost = "";
    const te = it.te;
    const before = te.getText(te.length - 1, te.length);
    te.insert(te.length, (before === "=" ? " " : "") + ed.display("<span style=\"color:" + N.sentinel("ink", N.INKS.indexOf("yellow")) + ";\">" + N.escape(t) + "</span>") + "&nbsp;");
  }

  // ── FIND ───────────────────────────────────────────────────────────────
  // every place the words are, in reading order: [{ i, a, b }]
  property var findHits: []
  property int findAt: -1
  property string findQuery: ""
  // words shown for a moment — a note opened from a search, or at one of
  // its highlights: scrolled to and lit yellow, then let go
  property bool flashing: false
  function flashText(q) {
    ed.find(String(q || ""));
    if (ed.findHits.length === 0) { ed.findQuery = ""; return; }
    ed.flashing = true;
    flashTimer.restart();
  }
  Timer {
    id: flashTimer
    interval: 1600
    onTriggered: {
      if (!ed.flashing) return;
      ed.flashing = false;
      ed.unmarkHit();
      ed.findQuery = "";
      ed.findHits = [];
      ed.findAt = -1;
    }
  }
  // the match shown before, unmarked: selections persist, so a step into
  // another block left the last one marked too
  function unmarkHit() {
    const h = ed.findHits[ed.findAt];
    const it = h ? rep.itemAt(h.i) : null;
    if (it && it.isText) it.te.deselect();
  }
  function find(q) {
    ed.flushTyping();
    ed.unmarkHit();
    ed.findQuery = q;
    const out = [];
    const lq = q.toLowerCase();
    if (lq !== "") {
      for (let x = 0; x < ed.blocks.length; x++) {
        const it = rep.itemAt(x);
        if (!it || !it.isText) continue;
        const t = it.te.getText(0, it.te.length).toLowerCase();
        let at = t.indexOf(lq);
        while (at >= 0) { out.push({ i: x, a: at, b: at + lq.length }); at = t.indexOf(lq, at + Math.max(1, lq.length)); }
      }
    }
    ed.findHits = out;
    ed.findAt = out.length > 0 ? 0 : -1;
    ed.showHit();
  }
  function findStep(d) {
    if (ed.findHits.length === 0) return;
    ed.unmarkHit();
    ed.findAt = (ed.findAt + d + ed.findHits.length) % ed.findHits.length;
    ed.showHit();
  }
  function showHit() {
    const h = ed.findHits[ed.findAt];
    if (!h) return;
    // unfold what hides it
    if (ed._hidden[h.i]) for (let x = h.i - 1; x >= 0; x--) if (ed.blocks[x].fold) { ed.blocks[x].fold = false; ed.rev++; }
    const it = rep.itemAt(h.i);
    if (!it) return;
    it.te.select(h.a, h.b);
    ed.reveal(it, it.te.positionToRectangle(h.a));
  }
  // find put away: no match left marked (the selection IS the mark, and a
  // persistent one stayed after the bar closed — user, 2026-10-17); the
  // caret goes to the end of the match it was on. Whether it placed one.
  function endFind() {
    const h = ed.findHits[ed.findAt];
    ed.unmarkHit();
    ed.findQuery = "";
    ed.findHits = [];
    ed.findAt = -1;
    const it = h ? rep.itemAt(h.i) : null;
    if (!it || !it.isText) return false;
    it.te.forceActiveFocus();
    it.te.cursorPosition = h.b;
    return true;
  }
  function replaceHit(t) {
    const h = ed.findHits[ed.findAt];
    if (!h) return;
    const it = rep.itemAt(h.i);
    ed.snap(true);
    it.te.remove(h.a, h.b);
    it.te.insert(h.a, N.escape(t));
    ed.find(ed.findQuery);
  }
  function replaceAll(t) {
    ed.snap(true);
    for (let x = ed.findHits.length - 1; x >= 0; x--) {
      const h = ed.findHits[x];
      const it = rep.itemAt(h.i);
      if (!it) continue;
      it.te.remove(h.a, h.b);
      it.te.insert(h.a, N.escape(t));
    }
    ed.find(ed.findQuery);
  }

  // ── THE PAGE ───────────────────────────────────────────────────────────
  property string hoverKey: ""
  property string hoverLink: ""
  readonly property Item linkSpotItem: linkSpot
  Flickable {
    id: view
    anchors.fill: parent
    contentWidth: width
    contentHeight: page.y + page.height + footerSlot.height + ed.bottomPad
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    interactive: false

    Item {
      id: page
      x: Math.round((view.width - ed.columnW) / 2)
      y: ed.topPad
      width: ed.columnW
      height: headerSlot.height + col.height

      Item {
        id: headerSlot
        width: parent.width
        height: childrenRect.height
      }
      // the blocks, one under another, save a row of pictures and files
      // side by side (see ROWS): placed by relayout, not by a Column
      Item {
        id: col
        y: headerSlot.height
        width: parent.width
        height: 0
        Repeater {
          id: rep
          model: keys
          delegate: Block { editor: ed }
          onItemAdded: Qt.callLater(ed.relayout)
          onItemRemoved: Qt.callLater(ed.relayout)
        }
      }
      // beside one: an upright line at its right
      Rectangle {
        readonly property var target: ed.dropBeside < 0 ? null : rep.itemAt(ed.dropBeside)
        visible: ed.dragKey !== "" && !!target
        x: target ? target.x + target.width + ed.rowGap / 2 - 1.5 : 0
        y: target ? col.y + target.y : 0
        width: 3
        height: target ? target.height : 0
        radius: 1.5
        color: Zenon.cyan
      }
      // where a carried block would land: a line in the gap
      Rectangle {
        readonly property var gapItem: ed.dropAt < 0 ? null : rep.itemAt(Math.min(ed.dropAt, rep.count - 1))
        visible: (ed.dragKey !== "" || ed.dropOver) && ed.dropBeside < 0 && !!gapItem
        x: -6
        width: parent.width + 12
        height: 3
        radius: 1.5
        color: Zenon.cyan
        y: !gapItem ? 0 : col.y + (ed.dropAt >= rep.count ? gapItem.y + gapItem.height : gapItem.y) - 1
      }
    }

    // ── EVERY GESTURE, OVER EVERYTHING ──
    MouseArea {
      id: overlay
      x: page.x - 34
      y: page.y + col.y
      width: page.width + 34 + 12
      height: Math.max(col.height, view.contentHeight - y)
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      hoverEnabled: true
      preventStealing: true
      property var grab: null
      property var downAt: null
      property bool moved: false
      // the block under a point in the overlay, and the point in it
      function hit(mx, my) {
        const y = my;
        let best = null;
        const cx = mx - 34;
        for (let x = 0; x < rep.count; x++) {
          const it = rep.itemAt(x);
          if (!it || !it.visible) continue;
          // in a row, the one across from the point (or the last before it)
          if (y >= it.y && y < it.y + it.height) {
            if (!best || best.y !== it.y || cx >= it.x - ed.rowGap / 2) best = it;
            continue;
          }
          if (best && y >= best.y && y < best.y + best.height) continue;
          if (y >= it.y + it.height) best = it;
        }
        if (!best) best = rep.itemAt(0);
        return best ? { it: best, i: ed.indexOf(best.key), x: cx - best.x, y: y - best.y } : null;
      }
      onPositionChanged: (m) => {
        const h = overlay.hit(m.x, m.y);
        if (h && !overlay.pressed) {
          ed.hoverKey = h.it.key;
          overlay.cursorShape = h.it.cursorAt(h.x, h.y);
          // a link under the pointer (a note's: peeked at, NotePane)
          const tp = h.it.isText ? h.it.textPoint(h.x, h.y) : null;
          ed.hoverLink = tp ? h.it.te.linkAt(tp.x, tp.y) : "";
          if (ed.hoverLink !== "") { linkSpot.x = m.x - 6; linkSpot.y = m.y - 10; }
        }
        if (!overlay.pressed || !overlay.downAt) return;
        if (Math.abs(m.x - overlay.downAt.x) + Math.abs(m.y - overlay.downAt.y) > 3) overlay.moved = true;
        if (overlay.grab) { overlay.grab.move(m.x, m.y); return; }
        if (overlay.downAt.carry) {
          if (ed.dragKey === "" && Math.abs(m.x - overlay.downAt.x) + Math.abs(m.y - overlay.downAt.y) > 8) ed.dragKey = overlay.downAt.carry;
          if (ed.dragKey === "") return;
          // over the right of a picture or a file: beside it, in its row
          const mine = ed.blockOf(ed.dragKey);
          const side = !!h && h.it.key !== ed.dragKey && ed.sideKind(mine) && ed.sideKind(h.it.b) && h.x > h.it.width * 0.62;
          ed.dropBeside = side ? h.i : -1;
          ed.dropAt = side ? h.i + 1 : ed.gapAt(h);
          overlay.cursorShape = Qt.ClosedHandCursor;
          overlay.edgeScroll(m.y);
          return;
        }
        if (!h || !overlay.downAt.text) return;
        // the words: a selection from the press to here, across blocks
        const z = { i: h.i, p: h.it.isText ? h.it.posAt(h.x, h.y) : (h.y < h.it.height / 2 ? 0 : 0) };
        if (!h.it.isText && h.i > overlay.downAt.i) z.p = 0;
        ed.setCross(ed.anchor, z);
        if (ed.cross) crossSink.forceActiveFocus();
        overlay.edgeScroll(m.y);
      }
      // the page follows a drag past its edges
      function edgeScroll(my) {
        const vy = my + overlay.y - view.contentY;
        if (vy < 20) view.contentY = Math.max(0, view.contentY - 12);
        else if (vy > view.height - 20) view.contentY = Math.min(Math.max(0, view.contentHeight - view.height), view.contentY + 12);
      }
      onExited: { ed.hoverKey = ""; ed.hoverLink = ""; }
      // where the link under the pointer is, for a bubble to hang from
      Item { id: linkSpot; width: 12; height: 20 }
      onCanceled: { ed.dragKey = ""; ed.dropAt = -1; ed.dropBeside = -1; overlay.grab = null; overlay.downAt = null; }
      onPressed: (m) => {
        overlay.moved = false;
        overlay.grab = null;
        const h = overlay.hit(m.x, m.y);
        if (!h) return;
        const shift = m.modifiers & Qt.ShiftModifier;
        if (m.button === Qt.RightButton) {
          const c = h.it.control(h.x, h.y);
          // a right click inside a selection keeps it; elsewhere the caret goes there first
          const inSel = ed.cross && h.i >= ed.cross.from && h.i <= ed.cross.to
            || h.it.isText && h.it.te.selectionStart !== h.it.te.selectionEnd
               && h.it.posAt(h.x, h.y) >= h.it.te.selectionStart && h.it.posAt(h.x, h.y) <= h.it.te.selectionEnd;
          if (!inSel && h.it.isText) ed.place(h.i, h.it.posAt(h.x, h.y));
          if (c && c.act === "cell" && h.it.table()) h.it.table().focusCell(c.r, c.c, c.pos);
          if (!h.it.isText && c && (c.act === "media" || c.act === "file" || c.act === "resize")) { ed.mediaSel = h.it.key; keySink.forceActiveFocus(); }
          const p = overlay.mapToItem(ed, m.x, m.y);
          // a wrong word under the pointer: its suggestions head the menu
          const sp = h.it.isText ? h.it.spellAt(h.it.posAt(h.x, h.y)) : null;
          ed.menuAsked(p.x, p.y, { key: h.it.key, kind: h.it.kind, control: c, spell: sp,
                                   link: c && c.act === "link" ? c.href : "", cell: c && c.act === "cell" ? c : null });
          return;
        }
        const c = h.it.control(h.x, h.y);
        if (c) {
          if (c.act === "check") { if (!ed.readOnly) ed.toggleCheck(h.it.key); return; }
          if (c.act === "fold") { ed.fold(h.it.key); return; }
          if (c.act === "link" && !shift) { overlay.downAt = { x: m.x, y: m.y, i: h.i, text: false, link: c.href }; return; }
          if (c.act === "media" || c.act === "file" || c.act === "grip") {
            ed.cross = null;
            ed.mediaSel = h.it.key;
            keySink.forceActiveFocus();
            // held and moved, it is carried (see onPositionChanged)
            if (!ed.readOnly) overlay.downAt = { x: m.x, y: m.y, carry: h.it.key };
            return;
          }
          if (c.act === "resize" && !ed.readOnly) {
            ed.mediaSel = h.it.key;
            ed.snap(true);
            const k = h.it.key, room = Math.max(80, h.it.width - h.it.indentW), x0 = m.x, w0 = h.it.b.w || 1;
            overlay.grab = { move: (x, y) => ed.resizeMedia(k, w0 + (x - x0) / room), release: () => ed.edited() };
            overlay.downAt = { x: m.x, y: m.y };
            return;
          }
          if (c.act === "cell") {
            const t = h.it.table();
            if (t) t.focusCell(c.r, c.c, c.pos);
            return;
          }
          if (c.act === "beside") {
            // the empty space beside a picture: the caret after it
            ed.place(h.i, "end");
            return;
          }
        }
        if (!h.it.isText) return;
        // a third click on the word just doubled: its whole row (the
        // press comes as a plain one after a double click, so it is
        // caught here — the double click's handler never sees it)
        const t3 = overlay.tripleAt;
        if (!shift && overlay.tripleTimer.running && t3 && t3.i === h.i && Math.abs(m.x - t3.x) + Math.abs(m.y - t3.y) < 10) {
          overlay.tripleTimer.stop();
          overlay.tripleAt = null;
          ed.cross = null;
          ed.mediaSel = "";
          h.it.te.forceActiveFocus();
          h.it.te.selectAll();
          ed.anchor = { i: h.i, p: 0 };
          overlay.downAt = null;
          return;
        }
        const pos = h.it.posAt(h.x, h.y);
        if (shift && (ed.cursorKey !== "" || ed.cross)) {
          if (!ed.anchor) { const cur = ed.current(); ed.anchor = cur ? { i: ed.indexOf(cur.key), p: cur.te.cursorPosition } : { i: h.i, p: pos }; }
          ed.setCross(ed.anchor, { i: h.i, p: pos });
          if (ed.cross) crossSink.forceActiveFocus();
          overlay.downAt = { x: m.x, y: m.y, i: h.i, text: true };
          return;
        }
        ed.cross = null;
        ed.mediaSel = "";
        // other blocks let their old selection go
        for (let x = 0; x < rep.count; x++) { const o = rep.itemAt(x); if (o && o.isText && o !== h.it) o.te.deselect(); }
        h.it.te.forceActiveFocus();
        h.it.te.cursorPosition = pos;
        h.it.te.deselect();
        ed.anchor = { i: h.i, p: pos };
        overlay.downAt = { x: m.x, y: m.y, i: h.i, text: true };
      }
      onReleased: (m) => {
        if (overlay.grab) { overlay.grab.release(); overlay.grab = null; }
        if (ed.dragKey !== "") {
          const k = ed.dragKey, to = ed.dropAt, beside = ed.dropBeside >= 0;
          ed.dragKey = "";
          ed.dropAt = -1;
          ed.dropBeside = -1;
          if (to >= 0) ed.moveBlock(k, to, beside);
          keySink.forceActiveFocus();
        }
        if (overlay.downAt && overlay.downAt.link && !overlay.moved) ed.linkClicked(overlay.downAt.link);
        overlay.downAt = null;
      }
      onDoubleClicked: (m) => {
        const h = overlay.hit(m.x, m.y);
        if (!h || m.button !== Qt.LeftButton) return;
        const c = h.it.control(h.x, h.y);
        if (c && (c.act === "media")) { ed.mediaOpened(ed.blockOf(h.it.key)); return; }
        if (c && c.act === "file") { ed.fileOpened(ed.blockOf(h.it.key)); return; }
        if (!h.it.isText) return;
        // a word; a third click (see onPressed) the row
        h.it.te.cursorPosition = h.it.posAt(h.x, h.y);
        h.it.te.selectWord();
        overlay.tripleAt = { i: h.i, x: m.x, y: m.y };
        overlay.tripleTimer.restart();
      }
      property var tripleAt: null
      readonly property Timer tripleTimer: Timer { interval: 400 }
    }
    // after the overlay, so what is in it takes its own clicks
    Item {
      id: footerSlot
      x: page.x
      y: page.y + col.y + col.height
      width: page.width
      height: childrenRect.height
    }
  }
  // ── DROPPED IN FROM OUTSIDE ──
  // files (terminus' rows, a picture from anywhere) go in as pictures and
  // files where the line shows; words dropped go in as paragraphs
  DropArea {
    anchors.fill: view
    enabled: !ed.readOnly
    function gap(d) {
      const p = view.mapToItem(overlay, d.x, d.y);
      return ed.gapAt(overlay.hit(p.x, p.y));
    }
    onEntered: (d) => {
      if (!d.hasUrls && !d.hasText) { d.accepted = false; return; }
      ed.dropOver = true;
      ed.dropAt = gap(d);
    }
    onPositionChanged: (d) => {
      ed.dropAt = gap(d);
      const vy = d.y;
      if (vy < 30) view.contentY = Math.max(0, view.contentY - 12);
      else if (vy > view.height - 30) view.contentY = Math.min(Math.max(0, view.contentHeight - view.height), view.contentY + 12);
    }
    onExited: { ed.dropOver = false; ed.dropAt = -1; }
    onDropped: (d) => {
      const at = gap(d);
      ed.dropOver = false;
      ed.dropAt = -1;
      const paths = (d.urls || []).map((u) => String(u)).filter((u) => u.startsWith("file://"))
        .map((u) => decodeURIComponent(u.replace(/^file:\/\/[^/]*/, "")));
      if (paths.length) { d.acceptProposedAction(); ed.filesDropped(paths, at); return; }
      const words = d.hasText ? String(d.text || "") : (d.urls || []).map((u) => String(u)).join("\n");
      if (words.trim() === "") return;
      d.acceptProposedAction();
      ed.insertAt(at, words.replace(/\r/g, "").split("\n").map((l) => N.block("body", N.escape(l))));
    }
  }

  ElasticScroll { id: wheel; anchors.fill: view; view: view }
  Scrollbar { flick: view; anchors.right: view.right; anchors.top: view.top; anchors.bottom: view.bottom }

  // the tags offered (tagCheck), under the caret
  Rectangle {
    visible: ed.tagHits.length > 0
    z: 60
    x: Math.min(ed.tagSpot.x, ed.width - width - 8)
    y: ed.tagSpot.y
    width: Math.max(160, tagCol.implicitWidth + 12)
    height: tagCol.implicitHeight + 8
    radius: Zenon.menuRadius
    color: Zenon.menuBgSolid
    border.width: 1
    border.color: Zenon.border
    Column {
      id: tagCol
      x: 4
      y: 4
      Repeater {
        model: ed.tagHits
        delegate: Rectangle {
          required property string modelData
          required property int index
          width: Math.max(152, tagWord.implicitWidth + 24)
          height: Zenon.menuRowHeight - 4
          radius: Zenon.windowRadius
          color: index === ed.tagAt || tagRowMouse.containsMouse ? Zenon.menuHi : "transparent"
          Text {
            id: tagWord
            anchors.verticalCenter: parent.verticalCenter
            x: 10
            text: "#" + modelData
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(14)
          }
          MouseArea { id: tagRowMouse; anchors.fill: parent; hoverEnabled: true; onClicked: ed.tagTake(modelData) }
        }
      }
    }
  }
}
