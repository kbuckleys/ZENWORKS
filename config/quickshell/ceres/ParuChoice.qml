// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHICH PARU — the tagged release or the latest commit, two cards side by
// side. Setup asks it once, before paru exists; Settings asks it again
// whenever you want the other one (user, 2026-10-11), so the cards are one
// piece rather than two copies that drift apart.
//
// `choice` is what is picked, held by whoever asked; a tap says so through
// `picked`. `installed`, when given, marks the card that is the paru on this
// machine now.

import QtQuick
import "../morpheus"

Row {
  id: pick

  property string choice: "paru"
  property string installed: ""
  signal picked(string pkg)

  spacing: 12
  Repeater {
    model: [["paru", "Latest release", "the tagged version, updated when paru cuts one"],
            ["paru-git", "Latest commit", "follows paru's GitHub master as it moves"]]
    delegate: Rectangle {
      id: opt
      required property var modelData
      readonly property bool on: pick.choice === opt.modelData[0]
      readonly property bool here: pick.installed === opt.modelData[0]
      width: (pick.width - 12) / 2
      height: optCol.implicitHeight + 24
      radius: Zenon.windowRadius
      color: opt.on ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.2) : "transparent"
      border.width: 1
      border.color: opt.on ? Zenon.cyan : Zenon.border
      Column {
        id: optCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 4
        Row {
          spacing: 10
          Text {
            text: opt.modelData[0]
            color: opt.on ? Zenon.cyan : Zenon.white
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(18)
          }
          Text {
            anchors.baseline: parent.children[0].baseline
            visible: opt.here
            text: "installed"
            color: Zenon.green
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
        }
        Text {
          text: opt.modelData[1]
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: opt.modelData[2]
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
      }
      TapHandler { onTapped: pick.picked(opt.modelData[0]) }
    }
  }
}
