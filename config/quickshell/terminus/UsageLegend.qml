// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE KEY UNDER A COLORED USAGEBAR — a swatch, a name and a figure for
// each stretch, flowing onto as many lines as it needs: the kinds on a
// volume (UsageScan.legend), or the partitions on a drive (stylus' map).
//
//     UsageLegend { width: …; items: [{ name, line, ink, hot }] }
//
// `hot` lights one name in the accent (the partition picked). `compact`
// puts name and figure on one line, for a sheet with little room.
// `lineWidth` is how wide it is on one line: what a card that fits its
// content asks for (terminus' disk Info sheet), so the key never wraps.
// Fractional — a caller asking for room rounds it UP (see DiskInfoSheet).

import QtQuick
import "../morpheus"

Flow {
  id: key

  property var items: []
  property bool compact: false
  readonly property real lineWidth: {
    let w = 0, n = 0;
    for (const c of key.children)
      if (c.visible && c.implicitWidth > 0) { w += c.implicitWidth; n++; }
    return n > 0 ? w + (n - 1) * key.spacing : 0;
  }

  spacing: key.compact ? 16 : 22

  Repeater {
    model: key.items
    Row {
      required property var modelData
      spacing: 8
      Rectangle {
        y: 4
        width: 10
        height: 10
        radius: Zenon.rad(3)
        color: modelData.ink
        border.width: 1
        border.color: Zenon.border
      }
      Text {
        visible: key.compact
        text: modelData.name + "  " + modelData.line
        color: modelData.hot ? Zenon.cyan : Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
      Column {
        visible: !key.compact
        spacing: 1
        Text {
          text: modelData.name
          color: modelData.hot ? Zenon.cyan : Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(13)
        }
        Text {
          text: modelData.line
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
    }
  }
}
