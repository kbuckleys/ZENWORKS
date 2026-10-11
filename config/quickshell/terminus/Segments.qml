// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A FEW CHOICES, ONE OF THEM ON — one bordered pill split into its options,
// a hairline between them, the chosen one lit by ONE highlight that slides
// to whichever is chosen (user, 2026-10-11) rather than each part lighting
// itself. For a view's handful of ways to look (open or closed, whose,
// which history, which forge) and a window's few pages (alexandria's,
// ceres' switch — this was theirs first, written in each). Sized by its
// words; no hover, no hand cursor (the suite's controls answer neither).
//
//     Segments { options: [["open", "Open"], ["closed", "Closed"]]
//                current: pg.showing; onChose: (v) => pg.showing = v
//                onPointed: (v, item, inside) => …   // a tooltip, say }
//
// terminus' PrefSeg is the settings panel's own (enrolled with its window
// for the keyboard); this is the one for anywhere else.

import QtQuick
import "../morpheus"

Item {
  id: segs
  // [[value, label], …]
  property var options: []
  property string current: ""
  property real textSize: Zenon.px(14)
  // the unlit words' ink; the lit one's is the accent
  property color ink: Zenon.muted
  signal chose(string value)
  // the pointer on an option, or off it — for the holder's tooltip
  signal pointed(string value, Item at, bool inside)

  readonly property int index: segs.options.findIndex((o) => o[0] === segs.current)
  implicitWidth: row.implicitWidth + 2
  implicitHeight: Math.round(segs.textSize * 2.1)
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Zenon.windowRadius
    color: Zenon.wash(0.04)
  }

  // the one highlight, under the words, sliding to the chosen option
  readonly property Item litItem: segs.index >= 0 && rep.count > segs.index ? rep.itemAt(segs.index) : null
  Rectangle {
    id: lit
    visible: !!segs.litItem
    x: segs.litItem ? row.x + segs.litItem.x + 2 : 0
    y: 3
    width: segs.litItem ? segs.litItem.width - 4 : 0
    height: segs.height - 6
    radius: Math.max(0, Zenon.windowRadius - 2)
    color: Zenon.alpha(Zenon.cyan, 0.16)
    Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
    Behavior on width { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
  }

  Row {
    id: row
    x: 1
    y: 1
    height: segs.height - 2
    Repeater {
      id: rep
      model: segs.options
      delegate: Item {
        id: one
        required property var modelData
        required property int index
        readonly property bool on: segs.current === one.modelData[0]
        width: label.implicitWidth + 28
        height: row.height
        // between two options, a hairline
        Rectangle {
          visible: one.index > 0
          width: 1
          height: parent.height - 10
          anchors.verticalCenter: parent.verticalCenter
          color: Zenon.border
        }
        Text {
          id: label
          anchors.centerIn: parent
          text: one.modelData[1]
          color: one.on ? Zenon.cyan : segs.ink
          Behavior on color { ColorAnimation { duration: Zenon.fast } }
          font.family: Zenon.face
          font.weight: Font.Bold
          font.features: { "tnum": 1 }
          font.pixelSize: segs.textSize
        }
        HoverHandler { onHoveredChanged: segs.pointed(one.modelData[0], one, hovered) }
        TapHandler { onTapped: segs.chose(one.modelData[0]) }
      }
    }
  }

  // the border over everything, so no fill ever sits on it (ceres' rule)
  Rectangle {
    anchors.fill: parent
    radius: Zenon.windowRadius
    color: "transparent"
    border.width: 1
    border.color: Zenon.border
  }
}
