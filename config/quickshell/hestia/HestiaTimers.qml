// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Hestia's timers — systemd's and yours: what each starts, when it last
// ran and when it runs next, soonest first. A click shows the service it
// starts.

import QtQuick
import "../morpheus"
import "hestia.js" as H

Item {
  id: tp

  property var mgr: null
  property var win: null
  readonly property var rows: tp.mgr ? tp.mgr.timers : []
  property int sel: -1
  // "in 4 h" goes stale: the words are redrawn each minute
  property double now: Date.now()
  Timer { interval: 60000; repeat: true; running: tp.visible; onTriggered: tp.now = Date.now() }

  onVisibleChanged: if (tp.visible && tp.mgr) { tp.now = Date.now(); tp.mgr.refreshTimers(); }

  EmptyState {
    anchors.centerIn: parent
    visible: tp.rows.length === 0
    text: "No timers"
  }
  // a timer clicked flashes, then its service opens (morpheus/RowFlash)
  RowFlash { id: rowFlash }
  ListView {
    id: list
    anchors.fill: parent
    anchors.topMargin: 12
    clip: true
    model: tp.rows.length
    ElasticScroll { view: list }
    CursorBand { follows: list; index: tp.sel; shown: tp.sel >= 0 }
    delegate: Item {
      id: trow
      required property int index
      readonly property var r: tp.rows[index] || null
      width: list.width
      height: 54
      FlashOver { flash: rowFlash; index: trow.index }
      Text {
        id: tglyph
        x: 24
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F051B}"
        color: trow.r && trow.r.next ? Zenon.cyan : Zenon.accentMuted
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(17)
      }
      Column {
        anchors.left: tglyph.right
        anchors.leftMargin: 14
        anchors.right: times.left
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: trow.r ? H.shortName(trow.r.unit.replace(/\.timer$/, "")) + (trow.r.scope === "user" ? "  (yours)" : "") : ""
          color: Zenon.white
          font.family: Zenon.face
          font.weight: 600
          font.pixelSize: Zenon.px(14)
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: trow.r ? trow.r.desc || trow.r.activates : ""
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      Column {
        id: times
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        width: 220
        spacing: 2
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignRight
          text: !trow.r ? "" : trow.r.next ? "Next " + H.relUs(trow.r.next, tp.now) : "Not scheduled"
          color: trow.r && trow.r.next ? Zenon.ink : Zenon.accentMuted
          font.family: Zenon.face
          font.weight: 600
          font.pixelSize: Zenon.px(13)
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignRight
          text: !trow.r ? "" : trow.r.last ? "Last ran " + H.relUs(trow.r.last, tp.now) : "Never ran"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      MouseArea {
        anchors.fill: parent
        onClicked: {
          tp.sel = trow.index;
          const r = trow.r;
          if (r && r.activates && tp.win) rowFlash.flashThen(trow.index, () => tp.win.showUnit(r.activates, r.scope));
        }
      }
    }
  }
  // up under the head, down under the hints, frosted (morpheus/ScrollEdge)
  ScrollEdge { view: list; follow: true; chromeTop: tp.win ? -tp.win.headH : 0 }
  ScrollEdge { view: list; below: true; follow: true; bar: tp.win ? tp.win.footItem : null }
  Scrollbar { flick: list; anchors.right: parent.right; anchors.top: list.top; anchors.bottom: list.bottom }
}
