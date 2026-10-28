// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A TIMED EVENT IN THE HOURS (a week, a day) — the calendar window's
// (user, 2026-10-28: "let me resize events, give them a context menu").
// Its color as a wash and a bar down its edge, the title, its time and
// place under it.
//
//   drag it          to another time, to the quarter hour, and in a week to
//                    another day; its new times shown as it goes
//   drag its foot    to make it longer or shorter
//   click            open it          right click   its menu
//
// The move is the window's (moveEvent: a repeat asks first, undo keeps it).
// In a directory with no qmldir, imported by path: a type added to
// chronos/qmldir is not seen by a live reload.

import QtQuick
import "../../morpheus"
import "../../terminus" as Term
import "../chronos.js" as Chr

Rectangle {
  id: blk
  property var win: null
  property var ev: null
  property int s: 0               // minutes into the day it starts, and ends
  property int e: 60
  property real hourH: 48
  property real colW: 100         // a day's width, for a drag across days
  property int days: 1            // the days in view
  property int dayIndex: 0        // which of them this is

  // the drag under way: days across, minutes down; a resize moves the end
  property bool dragging: false
  property bool resizing: false
  property bool waiting: false    // let go, the move asked for — held there
  property int dDays: 0
  property int dMins: 0
  function settle() { blk.dragging = false; blk.resizing = false; blk.waiting = false; blk.dDays = 0; blk.dMins = 0; }

  readonly property color ink: blk.win ? blk.win.evInk(blk.ev) : Zenon.cyan
  readonly property bool chosen: !!blk.win && blk.win.isSelected(blk.ev)
  readonly property int ns: blk.resizing ? blk.s : blk.s + blk.dMins
  readonly property int ne: blk.resizing ? Math.max(blk.s + 15, blk.e + blk.dMins) : blk.e + blk.dMins

  z: blk.dragging || blk.waiting ? 50 : blk.chosen ? 2 : 1
  radius: Zenon.rad(1)
  color: Zenon.alpha(blk.ink, blk.chosen || blk.dragging ? 0.42 : 0.22)
  border.width: blk.chosen ? 1 : 0
  border.color: blk.ink
  clip: true
  opacity: blk.dragging ? 0.92 : 1
  transform: Translate { x: blk.dDays * blk.colW; y: blk.resizing ? 0 : blk.dMins / 60 * blk.hourH }
  // grown or shrunk by a resize, as it is dragged
  property real baseH: 0
  height: Math.max(Zenon.px(12) + 8, blk.baseH + (blk.resizing ? (blk.ne - blk.e) / 60 * blk.hourH : 0))

  Rectangle { width: 3; height: parent.height; radius: 1; color: blk.ink }
  Column {
    x: 8
    y: 3
    width: blk.width - 12
    Text {
      textFormat: Text.PlainText
      width: parent.width
      elide: Text.ElideRight
      text: blk.ev ? blk.ev.title + (blk.ev.repeats ? "  \u{F0456}" : "") : ""
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Font.DemiBold
      font.pixelSize: Zenon.px(12)
    }
    Text {
      width: parent.width
      visible: blk.height > Zenon.px(12) * 2 + 10 || blk.dragging
      elide: Text.ElideRight
      text: !blk.ev ? "" : blk.dragging || blk.waiting ? Chr.hhmm(((blk.ns % 1440) + 1440) % 1440) + " – " + Chr.hhmm(((blk.ne % 1440) + 1440) % 1440)
        : Chr.eventTime(blk.ev) + (blk.ev.location ? " · " + blk.ev.location : "")
      color: blk.dragging ? Zenon.ink : Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(11)
    }
  }
  // the foot to take hold of, shown while the pointer is on it
  Rectangle {
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(28, parent.width * 0.4)
    height: 3
    radius: 1.5
    color: blk.ink
    opacity: ma.footHover || blk.resizing ? 0.9 : 0
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    property point p0: Qt.point(0, 0)
    property bool footHover: false
    cursorShape: ma.footHover || blk.resizing ? Qt.SizeVerCursor : Qt.ArrowCursor
    onPressed: (m) => {
      if (!blk.win || !blk.ev || blk.waiting) return;
      blk.win.select(blk.ev);
      if (m.button === Qt.RightButton) { blk.win.eventMenu(blk.ev, blk, m.x, m.y); return; }
      ma.p0 = ma.mapToItem(null, m.x, m.y);
      blk.resizing = m.y > blk.height - 8;
    }
    onPositionChanged: (m) => {
      ma.footHover = m.y > blk.height - 8;
      if (!ma.pressed || !(m.buttons & Qt.LeftButton) || blk.waiting) return;
      const p = ma.mapToItem(null, m.x, m.y), dx = p.x - ma.p0.x, dy = p.y - ma.p0.y;
      if (!blk.dragging && Math.abs(dx) + Math.abs(dy) < 5) return;
      blk.dragging = true;
      blk.dMins = Chr.snapMinutes(dy, blk.hourH);
      blk.dDays = blk.resizing || blk.days <= 1 ? 0
        : Math.max(-blk.dayIndex, Math.min(blk.days - 1 - blk.dayIndex, Math.round(dx / blk.colW)));
    }
    onReleased: (m) => {
      if (m.button === Qt.RightButton || blk.waiting) return;
      if (!blk.dragging) { blk.resizing = false; blk.win.open(blk.ev); return; }
      const sh = Chr.dragShift(blk.ev, blk.dDays, blk.dMins, blk.resizing, blk.e - blk.s);
      if (sh.ds === 0 && sh.de === 0) { blk.settle(); return; }
      blk.dragging = false;
      blk.waiting = true;
      // held where it was dropped until the events are read again (which
      // remakes this); put back if the move does not happen
      blk.win.moveEvent(blk.ev, sh.ds, sh.de, (ok) => { if (!ok && blk) blk.settle(); });
    }
    onCanceled: blk.settle()
  }
  // ringed while its right click's menu is up (terminus' HeldRing)
  Term.HeldRing {
    anchors.fill: parent
    radius: parent.radius
    z: 10
    on: !!parent.win && !!parent.ev && parent.win.heldKey === parent.ev.uid + "|" + parent.ev.date
  }
}
