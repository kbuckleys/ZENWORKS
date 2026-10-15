// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE DAY A JOURNAL ENTRY IS ABOUT — Apple lets an entry be dated to
// another day than the one it was written on: a month to pick from, and
// the time.

import QtQuick
import "../morpheus"
import "notes.js" as N

Column {
  id: db
  property var win: null
  signal closed()
  readonly property var n: db.win ? db.win.current : null
  property int year: 2026
  property int month: 0
  property double picked: 0
  property int hour: 12
  property int minute: 0
  readonly property var cells: N.monthGrid(db.year, db.month)
  Connections {
    target: db.win
    function onDateOpenChanged() {
      if (!db.win.dateOpen || !db.n || db.n.kind !== "entry") return;
      const d = new Date(db.n.date);
      db.year = d.getFullYear();
      db.month = d.getMonth();
      db.picked = N.dayStart(db.n.date);
      db.hour = d.getHours();
      db.minute = d.getMinutes();
    }
  }
  function step(d) {
    let m = db.month + d, y = db.year;
    if (m < 0) { m = 11; y--; } else if (m > 11) { m = 0; y++; }
    db.month = m;
    db.year = y;
  }
  function save() {
    if (db.n) db.win.mgr.setField(db.n.id, "date", db.picked + (db.hour * 60 + db.minute) * 60000, false);
    db.closed();
  }

  padding: 20
  spacing: 12
  Item {
    width: db.width - 40
    height: 30
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: N.MONTHS[db.month] + " " + db.year
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(17)
    }
    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4
      DialogButton { glyph: true; label: ""; onClicked: db.step(-1) }
      DialogButton { glyph: true; label: ""; onClicked: db.step(1) }
    }
  }
  Grid {
    columns: 7
    width: db.width - 40
    Repeater {
      model: db.cells
      delegate: Item {
        required property var modelData
        readonly property bool chosen: N.dayStart(modelData.ms) === db.picked
        width: (db.width - 40) / 7
        height: 38
        Rectangle {
          anchors.centerIn: parent
          width: 32
          height: 32
          radius: 16
          color: parent.chosen ? Zenon.cyan : "transparent"
          border.width: N.dayKey(modelData.ms) === N.dayKey(Date.now()) ? 1.5 : 0
          border.color: Zenon.sand
          Text {
            anchors.centerIn: parent
            text: modelData.day
            color: parent.parent.chosen ? Zenon.onAccent : modelData.out ? Zenon.alpha(Zenon.accentMuted, 0.5) : Zenon.ink
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
        }
        MouseArea { anchors.fill: parent; onClicked: db.picked = N.dayStart(modelData.ms) }
      }
    }
  }
  Row {
    spacing: 10
    Text { anchors.verticalCenter: parent.verticalCenter; text: "Time"; color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(14) }
    DialogButton { glyph: true; label: ""; onClicked: { const t = (db.hour * 60 + db.minute - 15 + 1440) % 1440; db.hour = Math.floor(t / 60); db.minute = t % 60; } }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: N.two(db.hour) + ":" + N.two(db.minute)
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(16)
      font.features: { "tnum": 1 }
    }
    DialogButton { glyph: true; label: ""; onClicked: { const t = (db.hour * 60 + db.minute + 15) % 1440; db.hour = Math.floor(t / 60); db.minute = t % 60; } }
  }
  Item {
    width: db.width - 40
    height: 30
    Row {
      anchors.right: parent.right
      spacing: 8
      DialogButton { label: "Cancel"; onClicked: db.closed() }
      DialogButton { label: "Set date"; ink: Zenon.cyan; primary: true; onClicked: db.save() }
    }
  }
}
