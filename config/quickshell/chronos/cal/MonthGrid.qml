// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SIDEBAR'S MONTH, drawn as the panel's (Quick Access) is (user,
// 2026-10-28: "the mini calendar in the sidebar should mimic the one in
// quick access, with the same visual properties"): the month in the accent
// and its year muted between ‹ › and « », weekdays bold with the weekend
// muted, days in rounded cells — today filled in the accent, the day in
// view ringed — a weather dot under a day the forecast reaches and a
// yellow one in the corner of a day with something on it. The wheel pages
// months (years with shift); the month's name goes back to today.
//
// A year's twelve wear it too (user, 2026-10-28): `header` off (the year
// names each month itself), `fixed` keeping the month's own days only.
//
// In a directory with no qmldir, as EventBlock.

import QtQuick
import "../../morpheus"
import ".."
import "../chronos.js" as Chr
import "../weather.js" as Wx

Column {
  id: mg
  property var win: null
  // the month shown, and the day in view (ringed)
  property var month: new Date()
  property string selIso: ""
  // days that have something on them: iso → anything
  property var marked: ({})
  property bool header: true
  property bool fixed: false
  signal picked(var date)
  signal opened(var date)
  signal stepped(int months)

  readonly property real cellW: Math.floor(mg.width / 7)
  readonly property real cellH: Math.round(mg.cellW * 0.82)
  readonly property var cells: Chr.monthGrid(mg.month.getFullYear(), mg.month.getMonth())
  readonly property string todayIso: mg.win ? mg.win.todayIso : Chr.isoOf(new Date())
  spacing: 4

  function roleColor(code) {
    const r = Wx.role(code);
    if (r === "sun") return Zenon.sand;
    if (r === "cloud") return Zenon.cyan;
    if (r === "rain") return Zenon.blue;
    if (r === "snow") return Zenon.white;
    if (r === "sleet") return Zenon.pink;
    if (r === "storm") return Zenon.magenta;
    return Zenon.muted;
  }

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: (event) => {
      const d = event.angleDelta.y > 0 ? -1 : 1;
      mg.stepped(event.modifiers & Qt.ShiftModifier ? d * 12 : d);
    }
  }

  component Chevron: Item {
    id: chev
    property string glyph: ""
    signal activated()
    width: 20
    height: 28
    Text {
      anchors.centerIn: parent
      text: chev.glyph
      color: chevMa.pressed ? Zenon.cyan : Zenon.muted
      Behavior on color { ColorAnimation { duration: Zenon.fast } }
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(16)
    }
    MouseArea { id: chevMa; anchors.fill: parent; onClicked: chev.activated() }
  }

  // «  ‹  October 2026  ›  »
  Item {
    visible: mg.header
    width: mg.width
    height: mg.header ? 28 : 0
    Row {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      Chevron { glyph: "«"; onActivated: mg.stepped(-12) }
      Chevron { glyph: "‹"; onActivated: mg.stepped(-1) }
    }
    Row {
      anchors.centerIn: parent
      spacing: 6
      Text {
        anchors.baseline: yearText.baseline
        text: Chr.monthName(mg.month.getMonth())
        color: headMa.pressed ? Zenon.white : Zenon.cyan
        Behavior on color { ColorAnimation { duration: Zenon.fast } }
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(15)
      }
      Text {
        id: yearText
        text: String(mg.month.getFullYear())
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }
    MouseArea {
      id: headMa
      anchors.centerIn: parent
      width: parent.width - 90
      height: parent.height
      onClicked: mg.picked(new Date())
    }
    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      Chevron { glyph: "›"; onActivated: mg.stepped(1) }
      Chevron { glyph: "»"; onActivated: mg.stepped(12) }
    }
  }

  Row {
    Repeater {
      model: 7
      delegate: Text {
        required property int index
        width: mg.cellW
        height: 20
        text: Chr.dayShort(index)
        color: index >= 5 ? Zenon.muted : Zenon.keyInk
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(11)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  Grid {
    columns: 7
    Repeater {
      model: mg.cells
      delegate: Item {
        id: dayCell
        required property var modelData
        required property int index
        width: mg.cellW
        height: mg.cellH
        readonly property string iso: Chr.isoDay(dayCell.modelData.y, dayCell.modelData.m, dayCell.modelData.d)
        readonly property bool isToday: dayCell.iso === mg.todayIso
        readonly property bool isSel: dayCell.iso === mg.selIso
        readonly property bool weekend: dayCell.index % 7 >= 5
        readonly property var forecast: Weather.dayFor(dayCell.iso)
        readonly property date day: new Date(dayCell.modelData.y, dayCell.modelData.m, dayCell.modelData.d)
        // a year's month shows its own days alone
        readonly property bool gone: mg.fixed && !dayCell.modelData.cur
        opacity: dayCell.gone ? 0 : 1

        Rectangle {
          anchors.centerIn: parent
          width: mg.cellW - 4
          height: mg.cellH - 3
          radius: Zenon.windowRadius
          color: dayCell.isToday ? Zenon.cyan
            : dayCell.isSel ? Zenon.menuHi
            : dayMa.pressed ? Zenon.pressTile(false) : Zenon.alpha(Zenon.border, 0)
          border.color: dayCell.isSel && !dayCell.isToday ? Zenon.cyan : "transparent"
          border.width: 1
          Behavior on color { ColorAnimation { duration: Zenon.fast } }
        }
        Text {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: dayCell.forecast ? -2 : 0
          text: String(dayCell.modelData.d)
          color: dayCell.isToday ? Zenon.black
            : !dayCell.modelData.cur ? Zenon.dimInk
            : dayCell.weekend ? Zenon.muted : Zenon.white
          font.family: Zenon.face
          font.weight: dayCell.isToday ? Font.Black : Font.Bold
          font.pixelSize: Zenon.px(12)
        }
        // the forecast's condition, in its color
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 3
          width: 3
          height: 3
          radius: 1.5
          visible: dayCell.forecast !== null
          color: dayCell.isToday ? Zenon.black : mg.roleColor(dayCell.forecast ? dayCell.forecast.code : 0)
        }
        // something on it: a dot in the corner
        Rectangle {
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: 4
          anchors.rightMargin: 5
          width: 4
          height: 4
          radius: 2
          visible: !!mg.marked[dayCell.iso]
          color: dayCell.isToday ? Zenon.black : Zenon.yellow
        }
        MouseArea {
          id: dayMa
          anchors.fill: parent
          enabled: !dayCell.gone
          onClicked: mg.picked(dayCell.day)
          onDoubleClicked: mg.opened(dayCell.day)
        }
      }
    }
  }
}
