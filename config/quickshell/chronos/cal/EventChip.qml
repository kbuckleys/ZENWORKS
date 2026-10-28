// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// AN EVENT ON ITS DAY — a month's cell, a week's all-day row. A timed one
// in a month is a dot, its title and its time (Apple Calendar's); an
// all-day one a bar of its color. A Clio task due that day (`task`) is a
// hollow box and its title, opened in Clio at the item.
//
//   drag it          to another day: in a month, onto the cell (the window
//                    lights it, monthIsoAt); in a week's all-day row, across
//   click            open it           right click   its menu
//
// In a directory with no qmldir, as EventBlock.

import QtQuick
import "../../morpheus"
import "../../terminus" as Term
import "../chronos.js" as Chr

Rectangle {
  id: chip
  property var win: null
  property var ev: null
  property bool dot: false
  // "month" (dropped on a cell) or "row" (a week's all-day row: across)
  property string mode: "month"
  property real colW: 100
  property int days: 1
  property int dayIndex: 0

  readonly property bool task: !!chip.ev && !!chip.ev.task
  readonly property color ink: chip.task ? Zenon.accentMuted : chip.win ? chip.win.evInk(chip.ev) : Zenon.cyan
  readonly property bool chosen: !!chip.win && !chip.task && chip.win.isSelected(chip.ev)
  property bool dragging: false
  property bool waiting: false
  property int dDays: 0
  function settle() { chip.dragging = false; chip.waiting = false; chip.dDays = 0; if (chip.win) chip.win.dropIso = ""; }

  z: chip.dragging || chip.waiting ? 50 : 1
  radius: Zenon.rad(1)
  color: chip.dot || chip.task ? (chip.chosen ? Zenon.alpha(chip.ink, 0.2) : "transparent")
    : Zenon.alpha(chip.ink, chip.chosen || chip.dragging ? 0.42 : 0.24)
  border.width: chip.chosen && !chip.dot ? 1 : 0
  border.color: chip.ink
  opacity: chip.dragging && chip.mode === "month" ? 0.55 : 1
  transform: Translate { x: chip.mode === "row" ? chip.dDays * chip.colW : 0 }
  clip: true

  Rectangle { visible: !chip.dot && !chip.task; width: 3; height: parent.height; radius: 1; color: chip.ink }
  Rectangle {
    visible: chip.dot || chip.task
    x: 3
    anchors.verticalCenter: parent.verticalCenter
    width: 7
    height: 7
    radius: chip.task ? 1.5 : 3.5
    color: chip.task ? "transparent" : chip.ink
    border.width: chip.task ? 1.2 : 0
    border.color: chip.ink
  }
  Text {
    id: when
    visible: chip.dot && !!chip.ev && chip.ev.start !== ""
    anchors.right: parent.right
    anchors.rightMargin: 4
    anchors.verticalCenter: parent.verticalCenter
    text: chip.ev ? chip.ev.start : ""
    color: Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(11)
  }
  Text {
    textFormat: Text.PlainText
    x: chip.dot || chip.task ? 15 : 8
    anchors.verticalCenter: parent.verticalCenter
    width: chip.width - x - 4 - (when.visible ? when.implicitWidth + 6 : 0)
    elide: Text.ElideRight
    text: chip.ev ? chip.ev.title + (chip.ev.repeats ? "  \u{F0456}" : "") : ""
    color: chip.task ? Zenon.accentMuted : Zenon.ink
    font.family: Zenon.face
    font.weight: chip.task ? Zenon.weight : Font.DemiBold
    font.pixelSize: Zenon.px(12)
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    property point p0: Qt.point(0, 0)
    onPressed: (m) => {
      if (!chip.win || !chip.ev || chip.waiting) return;
      if (chip.task) return;
      chip.win.select(chip.ev);
      if (m.button === Qt.RightButton) { chip.win.eventMenu(chip.ev, chip, m.x, m.y); return; }
      p0 = mapToItem(null, m.x, m.y);
    }
    onPositionChanged: (m) => {
      if (!pressed || chip.task || !(m.buttons & Qt.LeftButton) || chip.waiting) return;
      const p = mapToItem(null, m.x, m.y), dx = p.x - p0.x, dy = p.y - p0.y;
      if (!chip.dragging && Math.abs(dx) + Math.abs(dy) < 5) return;
      chip.dragging = true;
      if (chip.mode === "row")
        chip.dDays = Math.max(-chip.dayIndex, Math.min(chip.days - 1 - chip.dayIndex, Math.round(dx / chip.colW)));
      else {
        const iso = chip.win.monthIsoAt(p.x, p.y);
        chip.win.dropIso = iso;
        chip.dDays = iso !== "" ? Chr.daysBetween(chip.ev.date, iso) : 0;
      }
    }
    onReleased: (m) => {
      if (m.button === Qt.RightButton || chip.waiting) return;
      if (chip.task) { chip.win.openTask(chip.ev); return; }
      if (!chip.dragging) { chip.win.open(chip.ev); return; }
      const d = chip.dDays;
      if (d === 0) { chip.settle(); return; }
      chip.dragging = false;
      chip.waiting = true;
      if (chip.win) chip.win.dropIso = "";
      const sh = chip.ev.allDay ? { ds: d, de: d } : { ds: d * 1440, de: d * 1440 };
      chip.win.moveEvent(chip.ev, sh.ds, sh.de, (ok) => { if (!ok && chip) chip.settle(); });
    }
    onCanceled: chip.settle()
  }
  // ringed while its right click's menu is up (terminus' HeldRing)
  Term.HeldRing {
    anchors.fill: parent
    radius: parent.radius
    z: 10
    on: !!parent.win && !!parent.ev && parent.win.heldKey === parent.ev.uid + "|" + parent.ev.date
  }
}
