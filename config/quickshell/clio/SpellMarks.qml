// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SPELLING'S MARKS ON ONE TEXT — a faint red chip round each word hunspell
// calls wrong (ClioManager's spelling, core/spell.py). Made a child of the
// TextEdit it marks, so its words' rectangles are its own coordinates: the
// editor's blocks and the desktop's stickies wear the same one.
//
// Asked a moment after typing stops; the word the caret is still at the end
// of is not marked until the caret leaves it, as a Mac waits for the word to
// be finished. Qt rich text has no wavy underline, so the marks are drawn
// behind the text, a faint red chip round each word.

import QtQuick
import "../morpheus"
import "notes.js" as N

Item {
  id: sm
  // the TextEdit marked (this is its child) and the manager that asks
  property var field: null
  property var mgr: null
  property bool active: true
  // [{ w, a, b, sugs }]
  property var runs: []
  anchors.fill: parent

  function respell() {
    const m = sm.mgr;
    if (!m || !m.spellOn || !sm.active || !sm.field) {
      if (sm.runs.length > 0) sm.runs = [];
      return;
    }
    const f = sm.field;
    const words = N.spellWords(f.getText(0, f.length));
    m.spellAsk(words.map((x) => x.w));
    const caret = f.activeFocus && f.selectionStart === f.selectionEnd ? f.cursorPosition : -1;
    const out = [];
    for (const x of words) {
      if (x.b === caret) continue;
      const sugs = m.misspelt(x.w);
      if (sugs) out.push({ w: x.w, a: x.a, b: x.b, sugs: sugs });
    }
    // the same answer kept as it is (no marks rebuilt, none drawn in again);
    // a changed one says which words are new, and only those are drawn in
    const sig = (r) => r.a + ":" + r.w;
    const before = {};
    for (const r of sm.runs) before[sig(r)] = true;
    if (out.length === sm.runs.length && out.every((r) => before[sig(r)])) return;
    const fresh = {};
    for (const r of out) if (!before[sig(r)]) fresh[sig(r)] = true;
    sm.fresh = fresh;
    sm.runs = out;
  }
  property var fresh: ({})
  // the wrong word at a position in the text, or null
  function at(pos) {
    for (const r of sm.runs) if (pos >= r.a && pos <= r.b) return r;
    return null;
  }
  // soon: after a keystroke, a caret move, the focus going
  function soon() { wait.restart(); }
  onActiveChanged: sm.soon()
  Component.onCompleted: wait.start()

  Timer { id: wait; interval: 450; onTriggered: sm.respell() }
  Connections {
    target: sm.mgr
    ignoreUnknownSignals: true
    function onSpellEpochChanged() { sm.respell(); }
  }
  Connections {
    target: sm.field
    ignoreUnknownSignals: true
    function onTextChanged() { sm.soon(); }
    function onCursorPositionChanged() { if (sm.mgr && sm.mgr.spellOn) sm.soon(); }
    function onActiveFocusChanged() { sm.soon(); }
  }

  // ── THE MARK: A FAINT RED CHIP ────────────────────────────────────────
  // Behind the word, not under it (user, 2026-10-17): a soft rounded tint
  // the word sits in, the way a tag chip holds a tag — calmer than a wave or
  // a row of dots, and the word stays whole to read. Behind the text (z -1:
  // a child under its TextEdit's own glyphs), a hair wider than the word.
  // A word newly found wrong fades in; one already marked just stays.
  z: -1
  Repeater {
    model: sm.runs
    delegate: Rectangle {
      id: sq
      required property var modelData
      readonly property var f: sm.field
      readonly property rect ra: { void [sq.f.width, sq.f.length, sq.f.font.pixelSize]; return sq.f.positionToRectangle(sq.modelData.a); }
      readonly property rect rb: { void [sq.f.width, sq.f.length, sq.f.font.pixelSize]; return sq.f.positionToRectangle(sq.modelData.b); }
      // a word that ends its line has its end on the next one: measured to
      // its last letter then
      readonly property rect rl: { void [sq.f.width, sq.f.length]; return sq.f.positionToRectangle(Math.max(sq.modelData.a, sq.modelData.b - 1)); }
      readonly property real wordW: Math.max(4, sq.rb.y === sq.ra.y ? sq.rb.x - sq.ra.x : sq.rl.x + sq.f.font.pixelSize * 0.5 - sq.ra.x)
      readonly property int padX: Math.max(2, Math.round(sq.f.font.pixelSize * 0.16))
      x: Math.round(sq.ra.x - sq.padX)
      y: Math.round(sq.ra.y + sq.ra.height * 0.06)
      width: Math.round(sq.wordW + sq.padX * 2)
      height: Math.round(sq.ra.height * 0.9)
      radius: Math.min(height / 2, Math.max(4, Math.round(sq.f.font.pixelSize * 0.3)))
      color: Zenon.alpha(Zenon.red, 0.2)
      border.width: 1
      border.color: Zenon.alpha(Zenon.red, 0.42)
      opacity: 0
      Component.onCompleted: { if (sm.fresh[sq.modelData.a + ":" + sq.modelData.w]) fadeIn.start(); else sq.opacity = 1; }
      NumberAnimation on opacity { id: fadeIn; running: false; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }
  }
}
