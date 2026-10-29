// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── ONE NERD GLYPH, LOOKED AT (user, 2026-10-14) ────────────────────────
// The split beside ideo's grid: the selected icon large, then what it is
// called, which set it is from, and the ways to write it down. Its own file
// rather than an inline component, so a live reload picks it up.

import QtQuick
import "../morpheus"

Item {
  id: pv
  // { cls, code, char } from ideo.js parseNerdCss, or null
  property var entry: null
  property color ink: Zenon.pink

  // the class's prefix names the set it came from
  readonly property var sets: ({
    "md": "Material Design", "fa": "Font Awesome", "fae": "Font Awesome Extension",
    "dev": "Devicons", "cod": "Codicons", "oct": "Octicons", "seti": "Seti-UI",
    "custom": "Custom", "weather": "Weather Icons", "linux": "Font Logos",
    "pom": "Pomicons", "pl": "Powerline", "ple": "Powerline Extra",
    "iec": "IEC Power Symbols", "indent": "Indentation", "indentation": "Indentation"
  })
  readonly property string cls: pv.entry ? String(pv.entry.cls) : ""
  readonly property var parts: pv.cls.replace(/^nf-/, "").split("-")
  readonly property string setKey: pv.parts.length > 1 ? pv.parts[0] : ""
  readonly property string setName: pv.sets[pv.setKey] || pv.setKey
  // "nf-md-arrow_left_bold" → "arrow left bold"
  readonly property string niceName: pv.parts.length > 1
    ? pv.parts.slice(1).join(" ").replace(/_/g, " ") : pv.cls
  readonly property string hex: pv.entry ? String(pv.entry.code).toUpperCase() : ""
  // What the pane needs to show all of itself. A filter can leave the grid
  // one row tall, and the pane shares the grid's height, so ideo holds the
  // grid open to this rather than letting the details spill off the card.
  readonly property int needH: Math.ceil(body.implicitHeight) + 24

  // the seam to the grid
  Rectangle {
    width: 1
    height: parent.height
    color: Zenon.border
  }

  Column {
    id: body
    visible: !!pv.entry
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: 18
    anchors.rightMargin: 16
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8

    // the glyph on its own, no chip round it (user, 2026-10-14)
    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Zenon.px(96)
      height: Zenon.px(88)
      Text {
        anchors.centerIn: parent
        text: pv.entry ? pv.entry.char : ""
        color: Zenon.white
        font.family: "Symbols Nerd Font"
        font.pixelSize: Zenon.px(64)
      }
    }

    // the same glyph at the sizes it is mostly used at
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 14
      Repeater {
        model: [14, 18, 24, 32]
        Text {
          required property var modelData
          anchors.verticalCenter: parent.verticalCenter
          text: pv.entry ? pv.entry.char : ""
          color: Zenon.soft
          font.family: "Symbols Nerd Font"
          font.pixelSize: modelData
        }
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: pv.niceName
      color: pv.ink
      elide: Text.ElideRight
      font.family: Zenon.face
      font.weight: 600
      font.pixelSize: Zenon.px(16)
    }

    // the details close together (user, 2026-10-14: less padding)
    Column {
      width: parent.width
      spacing: 0
      Repeater {
        model: [["set", pv.setName], ["class", pv.cls], ["codepoint", "U+" + pv.hex],
                ["escape", "\\u" + pv.hex.toLowerCase()], ["html", "&#x" + pv.hex.toLowerCase() + ";"]]
        Row {
          required property var modelData
          width: parent.width
          spacing: 8
          Text {
            textFormat: Text.PlainText
            width: 70
            horizontalAlignment: Text.AlignRight
            text: modelData[0]
            color: Zenon.muted
            font.family: Zenon.face
            font.pixelSize: Zenon.px(13)
          }
          Text {
            width: parent.width - 78
            text: modelData[1]
            textFormat: Text.PlainText
            color: Zenon.white
            elide: Text.ElideMiddle
            font.family: Zenon.face
            font.pixelSize: Zenon.px(13)
          }
        }
      }
    }

  }
}
