// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE WORDS OF A RELEASE'S NOTES, AS THE FORGE SHOWS THEM — a run of them
// between pictures and videos (NotesView lays out the parts).
//
// Qt's Markdown does the words. What it cannot be told to draw is drawn
// here, over or under places D.mdLinesOf and D.mdCodeMarks keep in the
// text with invisible marks, found once it is laid out at its width:
//   the hairline under a big heading and for a divider (RULE_MARK), the
//   window's own, not Qt's heavy rule
//   a chip behind `code` in a line, and a card behind a fenced block
//   (CODE_IN/OUT, BLOCK_IN/OUT; user, 2026-10-25), as GitHub draws them

import QtQuick
import "../morpheus"
import "delphi.js" as D

TextEdit {
  id: view
  // the notes, as written; "" shows `empty` instead
  property string body: ""
  property string empty: "No notes"
  property int textSize: Zenon.px(17)

  readonly property bool has: view.body.trim() !== ""
  palette.link: Zenon.link   // the theme's, not the system's blue
  readOnly: true
  selectByMouse: true
  wrapMode: TextEdit.Wrap
  textFormat: view.has ? TextEdit.MarkdownText : TextEdit.PlainText
  text: view.has ? D.mdCodeMarks(D.mdLinesOf(view.body)) : view.empty
  color: view.has ? Zenon.ink : Zenon.accentMuted
  selectionColor: Zenon.alpha(Zenon.cyan, 0.4)
  font.family: Zenon.face
  font.weight: Zenon.weight
  font.pixelSize: view.textSize
  onLinkActivated: (link) => Strings.openLink(link)

  // where the marks landed: rules [y], chips [{ x, y, w, h }], blocks the same
  property var rules: []
  property var chips: []
  property var blocks: []
  function measure() {
    const t = view.getText(0, view.length);
    const at = (i) => view.positionToRectangle(i);
    const ys = [];
    for (let i = t.indexOf(D.RULE_MARK); i >= 0; i = t.indexOf(D.RULE_MARK, i + 1)) {
      const r = at(i);
      ys.push(Math.round(r.y + r.height * 0.3));
    }
    // A CHIP FOR EVERY LINE A SPAN IS ON: walked a character at a time, a
    // new chip where the line changes. A line's chip runs from where the
    // span starts on it to its last character's right edge (its left edge
    // plus the step the characters have been taking), so a span wrapped in
    // a list keeps to the list's indent. Rounded ends only stand off the
    // words where the span itself starts and ends (user, 2026-10-25: wrapped
    // chips ran to the box's edges).
    const cs = [];
    for (let i = t.indexOf(D.CODE_IN); i >= 0; i = t.indexOf(D.CODE_IN, i + 1)) {
      const j = t.indexOf(D.CODE_OUT, i);
      if (j < 0) break;
      let first = at(i), line = first, lastX = first.x, step = 0, starts = true;
      for (let k = i + 1; k <= j; k++) {
        const r = at(k);
        if (Math.abs(r.y - line.y) >= 2) {
          const pad = starts ? 4 : 0;
          cs.push({ x: line.x - pad, y: line.y, w: lastX + step - line.x + pad, h: line.height });
          line = r;
          starts = false;
        } else if (r.x > lastX) step = r.x - lastX;
        lastX = r.x;
      }
      // (a span ending right at a wrap leaves nothing on the new line)
      const pad = starts ? 4 : 0;
      if (starts || lastX > line.x) cs.push({ x: line.x - pad, y: line.y, w: lastX - line.x + pad + 4, h: line.height });
      i = j;
    }
    const bs = [];
    for (let i = t.indexOf(D.BLOCK_IN); i >= 0; i = t.indexOf(D.BLOCK_IN, i + 1)) {
      const j = t.indexOf(D.BLOCK_OUT, i);
      if (j < 0) break;
      const a = at(i), b = at(j);
      // close round its lines: Qt leaves no room after a block, and a card
      // reaching further sat on the next line's words
      bs.push({ x: -8, y: a.y - 4, w: view.width + 16, h: b.y + b.height - a.y + 6 });
      i = j;
    }
    view.rules = ys;
    view.chips = cs;
    view.blocks = bs;
  }
  onContentHeightChanged: Qt.callLater(view.measure)
  onTextChanged: Qt.callLater(view.measure)
  onWidthChanged: Qt.callLater(view.measure)

  // under the words (z below the TextEdit's own drawing): the cards, then
  // the chips; over them, the hairlines
  Repeater {
    model: view.blocks
    delegate: Rectangle {
      required property var modelData
      z: -2
      x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
      radius: Zenon.radiusCard
      color: Zenon.alpha(Zenon.ink, 0.06)
      border.width: 1
      border.color: Zenon.border
    }
  }
  Repeater {
    model: view.chips
    delegate: Rectangle {
      required property var modelData
      z: -1
      x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
      radius: Zenon.radiusControl
      color: Zenon.alpha(Zenon.ink, 0.1)
    }
  }
  Repeater {
    model: view.rules
    delegate: Rectangle { required property real modelData; y: modelData; width: view.width; height: 1; color: Zenon.border }
  }
}
