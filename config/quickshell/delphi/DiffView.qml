// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A DIFF, LINE BY LINE — and every line ADDRESSABLE, which is what staging a
// part of a file needs and what plato's undo preview (one block of rich
// text) cannot give. One row per line, per hunk head and (with more than one
// file) per file head, in a ListView, so a diff of 20 000 lines costs what
// fits on the screen.
//
//     DiffView { files: diff.files; editable: true
//                onStage: (chosen) => …   // {hunk: null | [lines]} }
//
// A cursor (the shell's SelectBar) and, with shift or a drag, a range. What
// the range covers is what `chosen()` hands back: its changed lines, by
// hunk; with no range, the hunk the cursor is in. Changed words inside a
// changed line (the backend pairs - and + lines and diffs them by word) are
// lit stronger than the line.
//
// Colours are slots (green, red, muted…), read when drawn, so a theme change
// repaints a diff already on screen.

import QtQuick
import "../morpheus"
import "../terminus"
import "delphi.js" as D

Item {
  id: dv
  property var files: []
  // whether lines can be picked at all (a commit's diff is only read)
  property bool editable: false
  property bool more: false
  property string empty: "No changes"
  property var host: null
  readonly property var rows: D.diffRows(dv.files || [])
  property int cursor: 0
  property int anchor: -1
  readonly property int lo: dv.anchor < 0 ? dv.cursor : Math.min(dv.anchor, dv.cursor)
  readonly property int hi: dv.anchor < 0 ? dv.cursor : Math.max(dv.anchor, dv.cursor)
  readonly property bool ranged: dv.anchor >= 0 && dv.anchor !== dv.cursor
  readonly property real rowH: Math.round(Zenon.px(15) * 1.6)
  readonly property var stats: D.diffStats(dv.files || [])
  signal activated(var chosen)      // return / double click: the default verb
  signal wantMore()
  signal touched()                  // the pointer pressed in it

  onFilesChanged: {
    dv.cursor = Math.max(0, Math.min(dv.cursor, dv.rows.length - 1));
    dv.anchor = -1;
  }
  // the first change, for a file just opened
  function toFirst() {
    dv.anchor = -1;
    dv.cursor = Math.max(0, D.nextChange(dv.rows, -1, 1));
    list.positionViewAtIndex(Math.max(0, dv.cursor - 3), ListView.Beginning);
  }
  function chosen() {
    if (dv.rows.length === 0) return null;
    if (dv.ranged) return D.chosenIn(dv.rows, dv.lo, dv.hi);
    const h = D.hunkAt(dv.rows, dv.cursor);
    if (h < 0) return null;
    const o = {};
    o[h] = null;
    return o;
  }
  // only the line under the cursor (when it is a change)
  function chosenLine() {
    const r = dv.rows[dv.cursor];
    return r && r.kind === "line" && r.t !== " " ? D.chosenIn(dv.rows, dv.cursor, dv.cursor) : null;
  }
  readonly property string pathAtCursor: {
    const r = dv.rows[dv.cursor];
    if (!r || !dv.files[r.fi]) return "";
    return dv.files[r.fi].new || dv.files[r.fi].old || "";
  }
  readonly property int lineAtCursor: {
    const r = dv.rows[dv.cursor];
    return r && r.kind === "line" ? (r.nu || r.old || 1) : 1;
  }

  function move(d, extend) {
    if (dv.rows.length === 0) return;
    if (extend && dv.anchor < 0) dv.anchor = dv.cursor;
    if (!extend) dv.anchor = -1;
    dv.cursor = Math.max(0, Math.min(dv.rows.length - 1, dv.cursor + d));
    list.positionViewAtIndex(dv.cursor, ListView.Contain);
  }
  function jump(d) {
    dv.anchor = -1;
    dv.cursor = D.nextChange(dv.rows, dv.cursor, d);
    list.positionViewAtIndex(dv.cursor, ListView.Contain);
  }
  function jumpHunk(d) {
    dv.anchor = -1;
    let i = dv.cursor + d;
    while (i >= 0 && i < dv.rows.length && dv.rows[i].kind !== "hunk") i += d;
    if (i >= 0 && i < dv.rows.length) {
      dv.cursor = i;
      list.positionViewAtIndex(i, ListView.Beginning);
    }
  }
  function page(d) { dv.move(d * Math.max(1, Math.floor(list.height / dv.rowH) - 2), false); }

  // what a row's text becomes with its changed words lit: rich text, only for
  // the lines that have them — every other line is plain, and cheap
  function richOf(r) {
    const esc = (t) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/\t/g, "    ").replace(/ /g, "&nbsp;");
    const bg = Zenon.hex(Zenon.alpha(r.t === "+" ? Zenon.green : Zenon.red, 0.32));
    let out = "", at = 0;
    for (const sp of r.spans) {
      out += esc(r.text.slice(at, sp[0]));
      out += "<span style=\"background-color:" + bg + "\">" + esc(r.text.slice(sp[0], sp[1])) + "</span>";
      at = sp[1];
    }
    return out + esc(r.text.slice(at));
  }

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    topMargin: 8
    bottomMargin: 8
    model: dv.rows
    cacheBuffer: 600
    reuseItems: true
    readonly property real numW: Math.max(3, String(Math.max(1, ...dv.rows.map((r) => Math.max(r.old || 0, r.nu || 0)))).length) * Zenon.px(10) + 10

    SelectBar { view: list; host: dv.host; index: dv.cursor; rowH: dv.rowH; color: Zenon.alpha(Zenon.cyan, 0.16) }

    delegate: Item {
      id: row
      required property var modelData
      required property int index
      width: list.width
      height: dv.rowH
      readonly property var r: row.modelData
      readonly property bool picked: dv.ranged && row.index >= dv.lo && row.index <= dv.hi

      // the line's own ground: added, removed, or nothing
      Rectangle {
        anchors.fill: parent
        visible: row.r.kind === "line" && row.r.t !== " "
        color: Zenon.alpha(row.r.t === "+" ? Zenon.green : Zenon.red, 0.09)
      }
      // a hunk's head: where it is in the file, and the function it is in
      Rectangle {
        anchors.fill: parent
        visible: row.r.kind === "hunk"
        color: Zenon.wash(0.04)
        Rectangle { width: parent.width; height: 1; color: Zenon.border }
      }
      Rectangle {
        anchors.fill: parent
        visible: row.r.kind === "file"
        color: Zenon.wash(0.07)
      }
      // in the range being picked
      Rectangle {
        anchors.fill: parent
        visible: row.picked
        color: Zenon.alpha(Zenon.cyan, 0.14)
        Rectangle { width: 3; height: parent.height; color: Zenon.cyan }
      }

      Text {
        id: oldNum
        visible: row.r.kind === "line"
        x: 6
        width: list.numW
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignRight
        text: row.r.old ? row.r.old : ""
        color: Zenon.dimInk
        font.family: Zenon.faceFixed
        font.features: { "tnum": 1 }
        font.pixelSize: Zenon.px(13)
      }
      Text {
        id: newNum
        visible: row.r.kind === "line"
        x: oldNum.x + list.numW + 4
        width: list.numW
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignRight
        text: row.r.nu ? row.r.nu : ""
        color: Zenon.dimInk
        font.family: Zenon.faceFixed
        font.features: { "tnum": 1 }
        font.pixelSize: Zenon.px(13)
      }
      Text {
        id: mark
        visible: row.r.kind === "line"
        x: newNum.x + list.numW + 10
        width: 14
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        text: row.r.kind !== "line" || row.r.t === " " ? "" : row.r.t
        color: row.r.t === "+" ? Zenon.green : Zenon.red
        font.family: Zenon.faceFixed
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(15)
      }
      Text {
        visible: row.r.kind === "line"
        anchors.left: mark.right
        anchors.right: parent.right
        anchors.rightMargin: 12
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        clip: true
        textFormat: row.r.spans ? Text.RichText : Text.PlainText
        text: row.r.kind !== "line" ? "" : row.r.spans ? dv.richOf(row.r) : row.r.text.replace(/\t/g, "    ")
        color: row.r.t === " " ? Zenon.soft : Zenon.ink
        font.family: Zenon.faceFixed
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
      Text {
        visible: row.r.kind === "line" && row.r.noeol
        anchors.right: parent.right
        anchors.rightMargin: 12
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        text: "no newline at end"
        color: Zenon.muted
        font.family: Zenon.face
        font.italic: true
        font.pixelSize: Zenon.px(12)
      }
      Text {
        visible: row.r.kind === "hunk"
        x: 14
        width: parent.width - 28
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: row.r.kind !== "hunk" ? "" : row.r.text + (row.r.section ? "   ·   " + row.r.section : "")
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      Text {
        visible: row.r.kind === "file"
        x: 14
        width: parent.width - 28
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideMiddle
        text: row.r.kind !== "file" ? "" : (row.r.from ? row.r.from + "  →  " : "") + row.r.path
          + (row.r.binary ? "   ·   binary" : row.r.status !== "modified" ? "   ·   " + row.r.status : "")
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(14)
      }
    }

    footer: Item {
      width: list.width
      height: dv.more ? 56 : 0
      DialogButton {
        visible: dv.more
        anchors.centerIn: parent
        label: "Show more of the diff"
        onClicked: dv.wantMore()
      }
    }
  }
  // picking with the pointer: a click sets the cursor, shift extends, a drag
  // is a range; a double click is the page's verb (stage, unstage)
  MouseArea {
    anchors.fill: list
    anchors.rightMargin: 12
    acceptedButtons: Qt.LeftButton
    property bool dragging: false
    function at(m) { return list.indexAt(m.x + list.contentX, m.y + list.contentY); }
    onPressed: (m) => {
      dv.touched();
      const i = at(m);
      if (i < 0) return;
      if ((m.modifiers & Qt.ShiftModifier) && dv.editable) {
        if (dv.anchor < 0) dv.anchor = dv.cursor;
        dv.cursor = i;
      } else {
        dv.cursor = i;
        dv.anchor = dv.editable ? i : -1;
      }
      dragging = dv.editable;
      if (dv.host && dv.host.refocus) dv.host.refocus();
    }
    onPositionChanged: (m) => {
      if (!dragging) return;
      const i = at(m);
      if (i >= 0) dv.cursor = i;
    }
    onReleased: {
      dragging = false;
      if (dv.anchor === dv.cursor) dv.anchor = -1;
    }
    onDoubleClicked: (m) => {
      const i = at(m);
      if (i < 0 || !dv.editable) return;
      dv.cursor = i;
      dv.anchor = -1;
      dv.activated(dv.chosen());
    }
  }
  ElasticScroll { anchors.fill: list; view: list }
  Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }

  EmptyMark {
    anchors.centerIn: parent
    visible: dv.rows.length === 0 && dv.empty !== ""
    word: dv.empty
  }
}
