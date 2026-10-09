// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// An on / off with its words beside it.
//
// One of picasso's controls, shared by the focus card and the viewer.

import QtQuick
import "../morpheus"

Item {
  id: sw
  property string label: ""
  property bool on: false
  property bool kbOn: false
  signal toggled()
  height: 28
  width: parent ? parent.width : 200

  Rectangle {
    id: swTrack
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: 34
    height: 18
    radius: 9
    color: sw.on ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.35)
                 : Zenon.wash(0.08)
    border.width: 1
    border.color: sw.on ? Zenon.cyan : Zenon.border
    Rectangle {
      x: sw.on ? parent.width - width - 3 : 3
      anchors.verticalCenter: parent.verticalCenter
      width: 12
      height: 12
      radius: 6
      color: sw.on ? Zenon.cyan : Zenon.muted
      Behavior on x { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
    }
    Ring { on: sw.kbOn }
  }
  Text {
    anchors.left: swTrack.right
    anchors.leftMargin: 10
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: sw.label
    color: sw.on ? Zenon.white : Zenon.muted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(14)
    elide: Text.ElideRight
  }
  MouseArea {
    anchors.fill: parent
    onClicked: sw.toggled()
  }
}
