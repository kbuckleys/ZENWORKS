// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT WAS JUST DONE, SAID ONCE: the small hud pill a window shows over its
// foot ("Saved", "Copied", a failure in red) and fades out again. Nine
// windows wore this as their own Rectangle; where it stands, and how long
// the words stay (`lasts`), are still each window's.
//
//   import "../morpheus/controls" as Ctl
//   Ctl.Said {
//     id: saidBox
//     anchors.horizontalCenter: body.horizontalCenter
//     anchors.bottom: foot.top
//     anchors.bottomMargin: 18
//     lasts: 2600
//   }
//   function say(t, bad) { saidBox.say(t, bad); }
//
// IT KEEPS ITS OWN WORDS (audit, 2026-10-27): say() puts them up and they
// go after `lasts` ms. Eleven windows each kept a said string, a bad flag
// and a Timer to clear them, alike but for how long; that is here now, and
// a window's say() hands over.
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
  // how long words stay up after say(), in ms
  property int lasts: 2600

  function say(t, isBad) {
    said.text = String(t ?? "");
    said.bad = !!isBad;
    clearAfter.restart();
  }
  Timer { id: clearAfter; interval: said.lasts; onTriggered: said.text = "" }

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
    textFormat: Text.PlainText
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
