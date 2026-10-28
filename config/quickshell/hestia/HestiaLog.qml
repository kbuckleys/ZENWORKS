// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Journal lines, newest at the foot: the time, who wrote it, and what it
// said — errors in red, warnings in yellow, notices in the accent. Both
// the Journal page and a service's own log are this.
//
// A ListModel underneath, appended to while following, so a busy journal
// adds rows rather than rebuilding the list; held to the newest `max`.
// While following, it stays at the foot — unless you have scrolled up to
// read, and then it stays where you are until you come back down.

import QtQuick
import "../morpheus"
import "hestia.js" as H

Item {
  id: lg

  property int max: 2000
  property bool showUnit: true
  property string emptyText: "Nothing in the journal"
  property bool loading: false
  readonly property int count: rows.count
  // the list itself, for a ScrollEdge to run it under the bars
  readonly property alias view: list
  readonly property bool atFoot: list.atYEnd || list.contentHeight <= list.height

  function setRows(arr) {
    rows.clear();
    const a = H.capRows(arr || [], lg.max);
    for (const r of a) rows.append(r);
    Qt.callLater(() => list.positionViewAtEnd());
  }
  function append(r) {
    if (!r) return;
    const stay = lg.atFoot;
    rows.append(r);
    if (rows.count > lg.max) rows.remove(0, rows.count - lg.max);
    if (stay) Qt.callLater(() => list.positionViewAtEnd());
  }
  function clear() { rows.clear(); }
  // a row's words, for copying
  function textOf(i) {
    const r = rows.get(i);
    return r ? H.clock(r.t) + "  " + r.ident + (r.pid ? "[" + r.pid + "]" : "") + ": " + r.msg : "";
  }
  property int sel: -1

  ListModel { id: rows }

  EmptyState {
    anchors.centerIn: parent
    width: Math.min(parent.width - 60, 460)
    visible: rows.count === 0
    text: lg.loading ? "Reading the journal…" : lg.emptyText
  }

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    model: rows
    boundsBehavior: Flickable.StopAtBounds
    ElasticScroll { view: list }
    CursorBand { follows: list; index: lg.sel; shown: lg.sel >= 0 }
    delegate: Item {
      id: line
      required property int index
      required property var t
      required property var prio
      required property string ident
      required property string unit
      required property string msg
      readonly property string role: H.prioRole(prio)
      readonly property color ink: line.role === "bad" ? Zenon.red : line.role === "warn" ? Zenon.yellow
        : line.role === "note" ? Zenon.cyan : Zenon.ink
      width: list.width
      height: Math.max(28, msgText.contentHeight + 8)
      Text {
        textFormat: Text.PlainText
        id: timeText
        x: 16
        y: 4
        // today's lines say only the time; older ones the day too
        width: Math.max(84, implicitWidth)
        text: H.clock(line.t)
        color: Zenon.accentMuted
        font.family: Zenon.faceCode
        font.weight: Zenon.codeWeight
        font.pixelSize: Zenon.px(14)
        font.features: { "tnum": 1 }
      }
      Text {
        textFormat: Text.PlainText
        id: identText
        x: timeText.x + timeText.width + 10
        y: 4
        width: 170
        elide: Text.ElideRight
        text: line.ident !== "" ? line.ident : (lg.showUnit ? H.shortName(line.unit) : "")
        color: line.role === "plain" ? Zenon.accentSoft : line.ink
        font.family: Zenon.faceCode
        font.weight: Math.min(900, Zenon.codeWeight + 100)
        font.pixelSize: Zenon.px(14)
      }
      Text {
        textFormat: Text.PlainText
        id: msgText
        x: identText.x + identText.width + 10
        y: 4
        width: line.width - x - 18
        wrapMode: Text.WrapAnywhere
        text: line.msg
        color: line.ink
        font.family: Zenon.faceCode
        font.weight: Zenon.codeWeight
        font.pixelSize: Zenon.px(14)
      }
      MouseArea { anchors.fill: parent; onClicked: lg.sel = line.index }
    }
  }
  Scrollbar { flick: list; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom }
}
