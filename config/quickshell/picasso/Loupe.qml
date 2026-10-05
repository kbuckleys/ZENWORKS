// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE LOUPE — a round glass over the picture, held up with ctrl: the part
// under the pointer, closer, while the picture itself stays where it is.
// Loaded by ViewerWindow by its url, only while ctrl is held.
//
// The same picture by the same url as the stage, so Qt's cache has it
// already; turned and mirrored as Scene turns it (the mirror first, then the
// turn). Not the look — this is for reading detail, and the look is the
// picture's own business.

import QtQuick
import Quickshell.Widgets
import "../morpheus"

Item {
  id: lp
  width: 260
  height: 260

  property url source
  // the picture upright, and as it is shown (turned)
  property real nw: 0
  property real nh: 0
  property real tw: 0
  property real th: 0
  property int rotate: 0
  property bool mirror: false
  // the point looked at, in the turned picture's pixels
  property real px: 0
  property real py: 0
  // how many screen pixels each of the picture's covers
  property real mag: 4

  // round, as Thumb is: Quickshell's clipping rectangle
  ClippingRectangle {
    id: lens
    anchors.fill: parent
    radius: width / 2
    color: "#000000"
    Item {
      width: lp.tw * lp.mag
      height: lp.th * lp.mag
      x: lp.width / 2 - lp.px * lp.mag
      y: lp.height / 2 - lp.py * lp.mag
      Image {
        id: glass
        anchors.centerIn: parent
        width: lp.nw * lp.mag
        height: lp.nh * lp.mag
        source: lp.source
        fillMode: Image.Stretch
        autoTransform: true
        asynchronous: true
        cache: true
        // as the stage asks, so it is the same entry in the cache
        sourceSize.width: 0
        smooth: lp.mag < 3
        mipmap: lp.mag < 1
        transform: [
          Scale { origin.x: glass.width / 2; origin.y: glass.height / 2; xScale: lp.mirror ? -1 : 1 },
          Rotation { origin.x: glass.width / 2; origin.y: glass.height / 2; angle: lp.rotate }
        ]
      }
    }
  }
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: "transparent"
    border.width: 2
    border.color: Zenon.cyan
  }
  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 14
    width: magText.implicitWidth + 12
    height: 18
    radius: 9
    color: "#cc000000"
    Text {
      id: magText
      anchors.centerIn: parent
      text: Math.round(lp.mag * 100) + "%  ·  ctrl+wheel"
      color: Zenon.white
      font.family: Zenon.face
      font.pixelSize: 10
    }
  }
}
