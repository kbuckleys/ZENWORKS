// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE APP, AS A PICTURE — the front page's artwork row and its Play shelf,
// after the App Store's story cards (user, 2026-10-14): the app's own first
// screenshot, and under it an eyebrow (its section), its name and a line of
// what it is. There is no editor writing headlines here; the app's own words
// are the caption.

import QtQuick
import Quickshell.Widgets
import "../morpheus"
import "store.js" as St

Item {
  id: art
  property var app: null
  property string file: ""          // the screenshot, once it has landed
  signal opened()

  implicitHeight: pic.height + caption.implicitHeight + 10

  ClippingRectangle {
    id: pic
    width: parent.width
    height: Math.round(art.width * 0.56)
    radius: Zenon.windowRadius
    color: Zenon.wash(0.04)
    border.width: 1
    border.color: Zenon.border
    // until it lands: the app's colour, and its icon in the middle
    Rectangle {
      anchors.fill: parent
      visible: shotImg.status !== Image.Ready
      gradient: Gradient {
        GradientStop { position: 0.0; color: Zenon.alpha(art.app && art.app.color ? art.app.color : Zenon.cyan, 0.30) }
        GradientStop { position: 1.0; color: Zenon.alpha(art.app && art.app.color ? art.app.color : Zenon.cyan, 0.06) }
      }
      StoreIcon {
        anchors.centerIn: parent
        app: art.app
        size: Math.round(pic.height * 0.34)
        mark: false
      }
    }
    Image {
      id: shotImg
      anchors.fill: parent
      source: art.file !== "" ? "file://" + art.file : ""
      fillMode: Image.PreserveAspectCrop
      verticalAlignment: Image.AlignTop
      asynchronous: true
      sourceSize.width: 900
      smooth: true
      mipmap: true
      opacity: status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 220 } }
    }
  }

  Column {
    id: caption
    anchors.top: pic.bottom
    anchors.topMargin: 10
    width: parent.width
    spacing: 2
    Text {
      readonly property var sec: St.sectionOf(art.app)
      text: sec ? sec[1].toUpperCase() : ""
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(12)
      font.letterSpacing: 0.8
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: art.app ? art.app.name : ""
      color: Zenon.white
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(16)
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: art.app ? art.app.summary : ""
      color: Zenon.accentKey
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
  }

  MouseArea {
    id: artMa
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: art.opened()
  }
}
