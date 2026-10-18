// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A COMMIT'S CHECKS, EACH — its dot and its name, and a click opens its
// log on the forge. Under a few, all of them; past `most`, the failed and
// running first and a count of the rest. History's commit and the push
// chip's bubble.

import QtQuick
import Quickshell
import "../morpheus"

Column {
  id: cr
  property var c: null
  property int most: 8
  property real textSize: Zenon.px(13)
  spacing: 4
  readonly property var runs: {
    const rs = cr.c && cr.c.runs ? cr.c.runs.slice() : [];
    const rank = { failure: 0, pending: 1, success: 2, neutral: 3 };
    rs.sort((a, b) => (rank[a.state] || 0) - (rank[b.state] || 0));
    return rs;
  }
  Repeater {
    model: cr.runs.slice(0, cr.most)
    delegate: Row {
      id: one
      required property var modelData
      spacing: 8
      CiDot { anchors.verticalCenter: parent.verticalCenter; c: ({ state: one.modelData.state === "neutral" ? "neutral" : one.modelData.state }); size: cr.textSize * 0.65 }
      Text {
        width: cr.width - 20
        elide: Text.ElideRight
        text: one.modelData.name + (one.modelData.state === "failure" ? "  — failed" : one.modelData.state === "pending" ? "  — running" : "")
        color: one.modelData.url ? Zenon.ink : Zenon.accentSoft
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: cr.textSize
        MouseArea {
          anchors.fill: parent
          enabled: !!one.modelData.url
          cursorShape: Qt.PointingHandCursor
          onClicked: Quickshell.execDetached(["xdg-open", one.modelData.url])
        }
      }
    }
  }
  Text {
    visible: cr.runs.length > cr.most
    text: "And " + (cr.runs.length - cr.most) + " more"
    color: Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: cr.textSize
  }
}
