// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import "../morpheus"

// HOW MUCH OF THE WAIT IS BEHIND YOU. Under "81 days until christmas": a
// hairline from last christmas to this one, filled as far as today. The two
// ends are named under it, and the fill grows in when it appears.
Item {
  id: root

  property var progress: null   // {from, to, frac} — see Metis.yearProgress

  implicitHeight: 32

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    y: 6
    height: 3
    radius: 1.5
    color: Zenon.border

    Rectangle {
      id: fill
      height: parent.height
      radius: parent.radius
      color: Zenon.blue
      width: parent.width * (root.progress ? root.progress.frac : 0)
      Behavior on width { NumberAnimation { duration: Zenon.slow * 2; easing.type: Zenon.ease } }
    }

    Rectangle {
      x: fill.width - width / 2
      anchors.verticalCenter: parent.verticalCenter
      width: 7
      height: 7
      radius: 3.5
      color: Zenon.blue
    }
  }

  Text {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    text: root.progress ? root.progress.from : ""
    color: Zenon.muted
    font.family: Zenon.face
    font.weight: 500
    font.pixelSize: 11
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    text: root.progress ? Math.round(root.progress.frac * 100) + "% of the way" : ""
    color: Zenon.keyInk
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: 11
    font.features: { "tnum": 1 }
  }

  Text {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    text: root.progress ? root.progress.to : ""
    color: Zenon.muted
    font.family: Zenon.face
    font.weight: 500
    font.pixelSize: 11
  }
}
