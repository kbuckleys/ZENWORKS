// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE JOURNAL'S CALENDAR — chronos' month (its header, its chevrons, its
// rounded day cells, today filled), with what the journal knows laid on it,
// as Apple's Journal does: a day written on with a picture wears that
// picture, a day written on without one is tinted (more entries, more
// tint), and a mood felt that day is a dot in its color. A day clicked
// shows only its entries, clicked again all of them; an empty day starts an
// entry on it. ‹ › and the wheel walk the months, « » and shift the years,
// the month's name goes back to today.

import QtQuick
import Quickshell.Widgets
import "../morpheus"
import "notes.js" as N

Column {
  id: cal
  property var win: null
  property var entries: []
  property var stats: ({ days: {} })
  property int year: new Date().getFullYear()
  property int month: new Date().getMonth()
  readonly property var cells: N.monthGrid(cal.year, cal.month)
  readonly property string today: N.dayKey(Date.now())
  readonly property real cellW: Math.floor(cal.width / 7)
  readonly property real cellH: Math.round(Math.min(56, cal.cellW * 0.86))
  spacing: 6

  // each day written on: how many, the first picture, the last mood
  readonly property var days: {
    const out = {};
    for (const n of cal.entries || []) {
      const k = N.dayKey(n.date);
      const o = out[k] || (out[k] = { count: 0, pic: "", mood: null });
      o.count++;
      if (!o.pic && !n.sealed && n.d && n.d.images && n.d.images.length) o.pic = n.d.images[0];
      if (n.mood && !o.mood) o.mood = N.moodOf(n.mood.v);
    }
    return out;
  }
  readonly property int monthCount: {
    let c = 0;
    for (const x of cal.cells) if (!x.out && cal.days[x.key]) c += cal.days[x.key].count;
    return c;
  }

  function step(d) {
    let m = cal.month + d, y = cal.year;
    if (m < 0) { m = 11; y--; } else if (m > 11) { m = 0; y++; }
    cal.month = m;
    cal.year = y;
  }
  function goToday() { cal.year = new Date().getFullYear(); cal.month = new Date().getMonth(); }

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: (e) => { const d = e.angleDelta.y > 0 ? -1 : 1; if (e.modifiers & Qt.ShiftModifier) cal.step(12 * d); else cal.step(d); }
  }

  // «  ‹  October 2026  ›  »
  Item {
    width: parent.width
    height: 34
    Row {
      anchors.centerIn: parent
      spacing: 2
      Chevron { glyph: "«"; onActivated: cal.step(-12) }
      Chevron { glyph: "‹"; onActivated: cal.step(-1) }
      Item {
        width: Math.max(170, monthRow.implicitWidth + 16)
        height: 34
        Row {
          id: monthRow
          anchors.centerIn: parent
          spacing: 8
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: N.MONTHS[cal.month]
            color: headMa.containsMouse ? Zenon.ink : Zenon.cyan
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(17)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String(cal.year)
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
        }
        MouseArea { id: headMa; anchors.fill: parent; hoverEnabled: true; onClicked: cal.goToday() }
      }
      Chevron { glyph: "›"; onActivated: cal.step(1) }
      Chevron { glyph: "»"; onActivated: cal.step(12) }
    }
  }

  Row {
    Repeater {
      model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
      delegate: Text {
        required property string modelData
        required property int index
        width: cal.cellW
        height: 20
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: modelData
        color: index >= 5 ? Zenon.accentMuted : Zenon.accentSoft
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(11)
      }
    }
  }

  Grid {
    columns: 7
    Repeater {
      model: cal.cells
      delegate: Item {
        id: cell
        required property var modelData
        required property int index
        readonly property var day: cal.days[modelData.key] || null
        readonly property int count: cell.day ? cell.day.count : 0
        readonly property bool chosen: !!cal.win && cal.win.day === modelData.key
        readonly property bool isToday: modelData.key === cal.today
        readonly property bool pic: !!cell.day && cell.day.pic !== "" && !!cal.win
        width: cal.cellW
        height: cal.cellH
        opacity: modelData.out ? 0.45 : 1

        ClippingRectangle {
          id: face
          anchors.fill: parent
          anchors.margins: 2
          radius: 8
          color: cell.isToday ? Zenon.cyan
            : cell.count > 0 ? Zenon.alpha(Zenon.cyan, Math.min(0.34, 0.12 + 0.08 * cell.count))
            : dayMa.containsMouse ? Zenon.wash(0.08) : "transparent"
          // the day's picture, darkened under its number
          Image {
            anchors.fill: parent
            visible: cell.pic
            source: cell.pic ? "file://" + cal.win.mgr.base + "/" + cell.day.pic : ""
            sourceSize.width: 160
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
          }
          Rectangle { anchors.fill: parent; visible: cell.pic; color: Zenon.shadowRgb; opacity: 0.32 }
        }
        // chosen: ringed, over whatever the day wears
        Rectangle {
          anchors.fill: face
          radius: face.radius
          color: "transparent"
          border.width: cell.chosen ? 2 : cell.isToday && cell.pic ? 2 : 0
          border.color: cell.chosen ? Zenon.alpha(Zenon.ink, 0.85) : Zenon.cyan
        }
        Text {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: cell.day && cell.day.mood ? -3 : 0
          text: cell.modelData.day
          color: cell.isToday && !cell.pic ? Zenon.onAccent : cell.pic ? "#ffffff" : cell.index % 7 >= 5 ? Zenon.accentMuted : Zenon.ink
          style: cell.pic ? Text.Raised : Text.Normal
          styleColor: Zenon.alpha(Zenon.shadowRgb, 0.5)
          font.family: Zenon.face
          font.weight: cell.count > 0 || cell.isToday ? Font.Black : Font.DemiBold
          font.pixelSize: Zenon.px(13)
          font.features: { "tnum": 1 }
        }
        // the mood felt that day
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 7
          width: 5
          height: 5
          radius: 2.5
          visible: !!cell.day && !!cell.day.mood
          color: cell.day && cell.day.mood ? Zenon[cell.day.mood.ink] || Zenon.accentMuted : "transparent"
          border.width: cell.pic || cell.isToday ? 1 : 0
          border.color: "#ffffff"
        }
        MouseArea {
          id: dayMa
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {
            if (cell.count === 0) {
              // a day with nothing: write about it
              cal.win.newEntry(cell.modelData.ms + 12 * 3600000);
              return;
            }
            cal.win.day = cell.chosen ? "" : cell.modelData.key;
            cal.win.wantTop = true;
          }
        }
      }
    }
  }

  Text {
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    text: cal.monthCount === 0 ? "Nothing written this month — a day clicked starts one"
      : cal.monthCount + (cal.monthCount === 1 ? " entry" : " entries") + " this month"
    color: Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(11)
    bottomPadding: 4
  }

  // chronos' chevron
  component Chevron: Item {
    id: chev
    property string glyph: ""
    signal activated()
    width: 24
    height: 34
    Text {
      anchors.centerIn: parent
      text: chev.glyph
      color: chevMa.containsMouse ? Zenon.cyan : Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(17)
    }
    MouseArea { id: chevMa; anchors.fill: parent; hoverEnabled: true; onClicked: chev.activated() }
  }
}
