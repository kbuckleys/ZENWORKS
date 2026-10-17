// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE APP, AS A CARD — the Store's shelves and grids are made of these.
//
// The icon with its source's mark in the corner, the name, a line of what
// it is, and the one thing to do: Get, or Open when it is already here. The
// card itself opens the app's page.
//
// ON A FAINT CHIP (user, 2026-10-14): no frame and NO HOVER TINT — the
// suite's rule — just the chip, and the keys' cursor in the accent.

import QtQuick
import Quickshell
import "../morpheus"
import "."

Item {
  id: card

  property var app: null
  property bool here: false        // the keys' cursor
  property bool busy: false        // a job is running: Get waits
  signal opened()
  signal got()
  signal launched()

  implicitHeight: 84

  Rectangle {
    anchors.fill: parent
    anchors.margins: 3
    radius: Zenon.windowRadius
    color: card.here ? Zenon.alpha(Zenon.cyan, 0.10) : Zenon.wash(0.035)
    border.width: card.here ? 1 : 0
    border.color: Zenon.alpha(Zenon.cyan, 0.6)
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  MouseArea {
    id: cardMa
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: card.opened()
  }

  StoreIcon {
    id: icon
    anchors.left: parent.left
    anchors.leftMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    app: card.app
    size: 56
  }

  Column {
    anchors.left: icon.right
    anchors.leftMargin: 14
    anchors.right: getBtn.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
      text: card.app ? card.app.name : ""
      color: Zenon.white
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(15)
      lineHeight: 0.95
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: card.app ? card.app.summary : ""
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
  }

  StoreGet {
    id: getBtn
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    app: card.app
    busy: card.busy
    onGot: card.got()
    onLaunched: card.launched()
  }
}
