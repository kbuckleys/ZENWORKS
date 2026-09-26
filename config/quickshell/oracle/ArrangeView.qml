// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE DESK, DRAWN — oracle's Display arrangement, the way the old System
// Preferences had it: every lit monitor as the rectangle it covers, to scale,
// dragged to where it sits on your desk. Dropped, it snaps against the others
// (see Ora.snapArrangement) and every screen's exact position is written at
// once, under the same "keep these settings?" as any other display change.
import QtQuick
import "oracle.js" as Ora
import "../morpheus"

Item {
  id: arr

  // the panel's palette, handed in rather than reached for
  property string face: Zenon.face
  property color fgColor: Zenon.white
  property color dimColor: Zenon.muted
  property color headColor: Zenon.cyan
  property color highlight: Zenon.cyan

  // What was just dropped, shown until hyprland reports the layout it made —
  // otherwise a screen would jump back to where it was for the second between
  // the write and the rescan.
  property var preview: null
  readonly property var rects: arr.preview || Oracle.arrangeRects
  Connections {
    target: Oracle
    function onArrangeRectsChanged() { arr.preview = null; }
  }

  Text {
    id: title
    anchors.left: parent.left
    anchors.leftMargin: 24
    anchors.top: parent.top
    anchors.topMargin: 12
    text: "Arrangement"
    color: Zenon.white
    font.family: arr.face
    font.weight: Font.Medium
    font.pixelSize: 17
  }

  Text {
    id: blurb
    anchors.left: title.left
    anchors.right: parent.right
    anchors.rightMargin: 24
    anchors.top: title.bottom
    anchors.topMargin: 2
    elide: Text.ElideRight
    text: "Drag a screen to where it sits on your desk. It snaps against the others."
    color: arr.dimColor
    font.family: arr.face
    font.pixelSize: 14
  }

  Item {
    id: stage
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: blurb.bottom
    anchors.bottom: parent.bottom
    anchors.margins: 16
    anchors.leftMargin: 24
    anchors.rightMargin: 24

    // the whole desk, and the scale that fits it with room to drag around it
    readonly property var bounds: {
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      for (const r of arr.rects) {
        x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y);
        x1 = Math.max(x1, r.x + r.w); y1 = Math.max(y1, r.y + r.h);
      }
      return isFinite(x0) ? { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : { x: 0, y: 0, w: 1, h: 1 };
    }
    readonly property real k: Math.min(stage.width * 0.62 / Math.max(1, bounds.w),
                                       stage.height * 0.9 / Math.max(1, bounds.h))
    readonly property real ox: (stage.width - bounds.w * k) / 2 - bounds.x * k
    readonly property real oy: (stage.height - bounds.h * k) / 2 - bounds.y * k

    Repeater {
      model: arr.rects

      Rectangle {
        id: box
        required property var modelData
        required property int index

        readonly property real homeX: stage.ox + box.modelData.x * stage.k
        readonly property real homeY: stage.oy + box.modelData.y * stage.k

        x: box.homeX
        y: box.homeY
        width: box.modelData.w * stage.k
        height: box.modelData.h * stage.k
        z: boxMa.drag.active ? 2 : 1
        radius: 3
        // the monitor's own ink, the same one its rows below wear
        readonly property color ink: Oracle.displayAccent(box.modelData.name)
        color: Qt.rgba(box.ink.r, box.ink.g, box.ink.b, boxMa.drag.active ? 0.30 : 0.14)
        border.width: boxMa.drag.active || boxMa.containsMouse ? 2 : 1
        border.color: box.ink

        Column {
          anchors.centerIn: parent
          spacing: 2
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: box.modelData.name
            color: box.ink
            font.family: arr.face
            font.weight: Font.DemiBold
            font.pixelSize: 13
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: box.modelData.w + "×" + box.modelData.h
            color: arr.dimColor
            font.family: arr.face
            font.pixelSize: 11
          }
        }

        MouseArea {
          id: boxMa
          anchors.fill: parent
          hoverEnabled: true
          drag.target: box
          drag.threshold: 2
          onReleased: {
            if (!drag.active && Math.abs(box.x - box.homeX) < 1 && Math.abs(box.y - box.homeY) < 1) return;
            const lx = Math.round((box.x - stage.ox) / stage.k);
            const ly = Math.round((box.y - stage.oy) / stage.k);
            const snapped = Ora.snapArrangement(arr.rects, box.index, lx, ly);
            arr.preview = snapped;
            // the drag broke the bindings; they are put back, onto the new place
            box.x = Qt.binding(() => box.homeX);
            box.y = Qt.binding(() => box.homeY);
            Oracle.setDisplayPositions(snapped);
          }
        }
      }
    }
  }
}
