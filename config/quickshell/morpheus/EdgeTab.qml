// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// EDGETAB — previous / next (or a handle) as a tab grown out of the edge it
// sits on: flush there, rounded on the side that faces in, solid, leaning
// out a little under the pointer and nudged the way it goes when clicked.
// Picasso's look (its stage's prev/next and strip handle), lifted out when
// ceres' featured carousel and screenshot lightbox wanted the same
// (user, 2026-10-17: "give them the same look as picasso's").
//
//     EdgeTab { edge: "left"; shown: …; onClicked: step(-1) }
//
// The caller places it (x / y on its edge) and says when it is `shown`;
// `near` scales its opacity (picasso: how close the pointer is to its side).

import QtQuick
import "."

Rectangle {
  id: tab
  // "left", "right" or "bottom" — the edge it grows out of
  property string edge: "left"
  property bool shown: true
  property real near: 1
  property string glyph: tab.edge === "left" ? "" : tab.edge === "right" ? "" : ""
  // how far a click leans it: the way it goes for the sides
  property real nudge: tab.edge === "left" ? -6 : tab.edge === "right" ? 6 : -4
  // the long side, and how far it stands out at rest / under the pointer
  property real length: 52
  property real rest: 17
  property real grown: 22
  property real glyphSize: Zenon.px(tab.side ? 16 : 14)

  readonly property bool side: tab.edge !== "bottom"
  readonly property bool hot: tabMa.containsMouse
  readonly property bool pressed: tabMa.pressed
  readonly property real depth: tab.hot ? tab.grown : tab.rest
  signal clicked()

  width: tab.side ? tab.depth : tab.length
  height: tab.side ? tab.length : tab.depth
  Behavior on width { enabled: tab.side; NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
  Behavior on height { enabled: !tab.side; NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
  // rounded only on the free side
  topLeftRadius: tab.edge === "left" ? 0 : 7
  bottomLeftRadius: tab.edge === "right" ? 7 : 0
  topRightRadius: tab.edge === "right" ? 0 : 7
  bottomRightRadius: tab.edge === "left" ? 7 : 0
  // solid: the strip's color, laid over black rather than over what is
  // behind it
  readonly property color base: Qt.tint(Qt.tint(Zenon.ground, Zenon.layerBg), Zenon.headBg)
  color: tabMa.pressed ? Qt.tint(tab.base, Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.28))
    : tab.hot ? Qt.tint(tab.base, Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.16))
    : tab.base
  border.width: 1
  border.color: Zenon.border
  opacity: tab.shown ? tab.near : 0
  visible: opacity > 0.01
  Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

  // a click leans it the way it goes, and it eases back (no overshoot:
  // the bounce is kept for things arriving, 2026-10-20)
  transform: Translate { id: tabNudge }
  SequentialAnimation {
    id: tabNudgeAnim
    NumberAnimation { target: tabNudge; property: tab.side ? "x" : "y"; to: tab.nudge
                      duration: Math.round(70 * Zenon.cfg.motionScale); easing.type: Easing.OutCubic }
    NumberAnimation { target: tabNudge; property: tab.side ? "x" : "y"; to: 0
                      duration: Math.round(260 * Zenon.cfg.motionScale); easing.type: Easing.OutCubic }
  }
  // no line along the edge it grows out of
  Rectangle {
    color: tab.color
    x: tab.edge === "left" ? 0 : tab.edge === "right" ? parent.width - 1 : 1
    y: tab.side ? 1 : parent.height - 1
    width: tab.side ? 1 : parent.width - 2
    height: tab.side ? parent.height - 2 : 1
  }
  Text {
    anchors.centerIn: parent
    // nudged off the flush edge, into the middle of what shows
    anchors.horizontalCenterOffset: tab.edge === "left" ? -1 : tab.edge === "right" ? 1 : 0
    anchors.verticalCenterOffset: tab.side ? 0 : 1
    text: tab.glyph
    color: tab.hot ? Zenon.cyan : Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: tab.glyphSize
  }
  MouseArea {
    id: tabMa
    anchors.fill: parent
    anchors.margins: -4
    hoverEnabled: true
    onClicked: { tabNudgeAnim.restart(); tab.clicked(); }
  }
}
