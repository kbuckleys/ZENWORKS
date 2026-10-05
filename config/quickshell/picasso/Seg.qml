// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A button in a row of answers. `chosen` is what will be done;
// `current` is what the monitor has now, ringed faintly while nothing is
// chosen, so leaving a row alone does not look like choosing it.
//
// One of picasso's controls, shared by the focus card and the viewer.

import QtQuick
import "../morpheus"

Rectangle {
  id: seg
  property string label: ""
  property bool chosen: false
  property bool current: false
  property bool kbOn: false
  property bool live: true
  default property alias inner: segInner.data
  signal hit()
  readonly property bool lit: seg.chosen || segMa.containsMouse || seg.current
  readonly property color ink: seg.chosen ? Zenon.cyan
    : (segMa.containsMouse || seg.current ? Zenon.white : Zenon.muted)
  height: 34
  radius: 5
  opacity: seg.live ? 1 : 0.4
  color: seg.chosen
    ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.16)
    : (segMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03))
  border.width: 1
  border.color: seg.chosen ? Zenon.cyan
    : (seg.current ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.4)
                   : Zenon.border)
  Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

  Item { id: segInner; anchors.fill: parent }
  Text {
    anchors.centerIn: parent
    visible: seg.label !== ""
    text: seg.label
    color: seg.ink
    font.family: Zenon.face
    font.weight: seg.chosen ? 600 : Font.Normal
    font.pixelSize: 13
  }
  MouseArea {
    id: segMa
    anchors.fill: parent
    hoverEnabled: true
    enabled: seg.live
    onClicked: seg.hit()
  }
  Ring { on: seg.kbOn }
}
