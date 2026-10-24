// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A BAR METER over one of Sysmon's readings — CpuModule, MemoryModule and
// GpuModule are this with their reading plugged in (they were three copies
// of it, 2026-10-24). Display only: the reading, its history and its ink all
// come from Sysmon, which zeus reads too, so the meter here and the graph
// there cannot drift.
//
// Clicking reports the click and nothing else — what opens is shell.qml's
// business, the same way the bell reports to howler and the clock to chronos.

import QtQuick
import "."

Item {
  id: meter
  implicitWidth: row.implicitWidth
  implicitHeight: Zenon.slot

  property int usage: 0
  // false: a reading that cannot report its load (an Intel GPU) says "n/a"
  // rather than showing an empty meter that reads as an idle one
  property bool usageKnown: true
  property string tooltipText: ""
  property var history: []
  property color accent: Zenon.ink
  // the tooltip's text is Helpers.tooltip markup (memory's is plain)
  property bool styled: true
  property bool tipWhen: meter.tooltipText !== ""

  signal activated()

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: Zenon.padModule
    rightPadding: Zenon.padModule

    Meter {
      anchors.verticalCenter: parent.verticalCenter
      visible: meter.usageKnown
      value: meter.usage / 100
      accent: meter.accent
    }
    BarText {
      anchors.verticalCenter: parent.verticalCenter
      visible: !meter.usageKnown
      src: "n/a"
      textColor: Zenon.muted
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: meter.activated()
  }

  Tooltip {
    anchorItem: meter
    cursorArea: mouse
    text: meter.tooltipText
    styled: meter.styled
    show: mouse.containsMouse && meter.tipWhen
    series: [{ values: meter.history, line: meter.accent }]
  }
}
