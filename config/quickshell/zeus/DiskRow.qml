// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One mounted filesystem, as a line under zeus' graphs: where it is mounted,
// what it is, how full, and what is going through it right now. One entry of
// Sysmon.disks; its rates are looked up by device in Sysmon.diskRates, so the
// row is built once per mount and only its numbers move.

import QtQuick
import "../morpheus"
import "../morpheus/helpers.js" as Helpers

Item {
  id: diskRow
  property var disk: ({})
  // told by zeus, so this file knows nothing about the panel it sits in
  property int rowH: 30
  property color fullInk: Zenon.red
  property color textInk: Zenon.white
  property color dimInk: Zenon.muted
  readonly property var rate: Sysmon.diskRates[diskRow.disk.dev] ?? null
  readonly property color ink: diskRow.disk.pct >= 90 ? diskRow.fullInk : Sysmon.diskReadInk
  height: diskRow.rowH

  Text {
    id: diskTarget
    anchors.left: parent.left
    anchors.leftMargin: 22
    anchors.verticalCenter: parent.verticalCenter
    width: 132
    elide: Text.ElideMiddle
    text: diskRow.disk.target ?? ""
    color: diskRow.ink
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: 13
  }

  Text {
    id: diskSource
    anchors.left: diskTarget.right
    anchors.leftMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    width: 170
    elide: Text.ElideMiddle
    text: (diskRow.disk.dev ?? "") + " \u00b7 " + (diskRow.disk.fstype ?? "")
    color: diskRow.dimInk
    font.family: Zenon.face
    font.pixelSize: 12
  }

  // how full, as a bar over its own trough, the way the bar's meters are
  Rectangle {
    id: diskTrough
    anchors.left: diskSource.right
    anchors.leftMargin: 8
    anchors.right: diskSize.left
    anchors.rightMargin: 18
    anchors.verticalCenter: parent.verticalCenter
    height: 8
    radius: 4
    color: Zenon.trough(diskRow.ink)

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * Math.min(1, (diskRow.disk.pct ?? 0) / 100)
      radius: 4
      color: diskRow.ink
      Behavior on width { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
    }
  }

  Text {
    id: diskSize
    anchors.right: diskIo.left
    anchors.rightMargin: 18
    anchors.verticalCenter: parent.verticalCenter
    width: 150
    horizontalAlignment: Text.AlignRight
    text: (diskRow.disk.pct ?? 0) + "% \u00b7 "
      + Helpers.sizeFormat(diskRow.disk.used ?? 0) + " / " + Helpers.sizeFormat(diskRow.disk.size ?? 0)
    color: diskRow.textInk
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: 13
  }

  Row {
    id: diskIo
    anchors.right: parent.right
    anchors.rightMargin: 24
    anchors.verticalCenter: parent.verticalCenter
    width: 170
    layoutDirection: Qt.RightToLeft
    spacing: 10
    Text {
      text: "\u2191 " + Helpers.powFormat(diskRow.rate ? diskRow.rate.write : 0)
      color: Sysmon.diskWriteInk
      font.family: Zenon.face
      font.pixelSize: 12
    }
    Text {
      text: "\u2193 " + Helpers.powFormat(diskRow.rate ? diskRow.rate.read : 0)
      color: Sysmon.diskReadInk
      font.family: Zenon.face
      font.pixelSize: 12
    }
  }
}
