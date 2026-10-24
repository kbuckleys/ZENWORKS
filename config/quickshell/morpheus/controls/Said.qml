// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT WAS JUST DONE, SAID ONCE: the small hud pill a window shows over its
// foot ("Saved", "Copied", a failure in red) and fades out again. Nine
// windows wore this as their own Rectangle; where it stands and how long
// the words stay are still each window's (its said/saidBad and say()).
//
//   import "../morpheus/controls" as Ctl
//   Ctl.Said {
//     anchors.horizontalCenter: body.horizontalCenter
//     anchors.bottom: foot.top
//     anchors.bottomMargin: 18
//     text: win.said
//     bad: win.saidBad
//   }
//
// A directory with no qmldir, imported by path (see Check.qml).

import QtQuick
import ".."

Rectangle {
  id: said
  property string text: ""
  // a failure: red words, a red rim
  property bool bad: false
  // the widest it grows; past that the words are cut with an ellipsis
  property real maxWidth: 560
  property real ground: 0.85
  property int pixelSize: Zenon.px(15)

  width: Math.min(saidText.implicitWidth + 32, said.maxWidth)
  height: 34
  radius: Zenon.windowRadius
  color: Zenon.hud(said.ground)
  border.width: 1
  border.color: said.bad ? Zenon.alpha(Zenon.red, 0.6) : Zenon.border
  opacity: said.text !== "" ? 1 : 0
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
  Text {
    id: saidText
    anchors.centerIn: parent
    width: Math.min(implicitWidth, parent.width - 32)
    elide: Text.ElideRight
    text: said.text
    color: said.bad ? Zenon.red : Zenon.ink
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: said.pixelSize
  }
}
