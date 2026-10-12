// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ABOUT THIS COMPUTER, unfolded — the About row's fold-out, laid out as
// fastfetch prints itself: the distro's logo on the left in the panel's
// accent, the facts beside it as `key  value` lines, and the theme's inks
// as a strip of swatches under them. What it reads is Oracle.computer
// (fastfetch's JSON through Ora.readComputer).
//
// Loaded by URL from OracleWindow, not named as a type: oracle/ has a
// qmldir, and a type added to one is not seen until the shell restarts.

import QtQuick
import "oracle.js" as Ora
import "../morpheus"
import "../ceres"

Item {
  id: pc
  // the panel's palette, handed in rather than reached for
  property string face: Zenon.face
  property color fgColor: Zenon.white
  property color dimColor: Zenon.muted
  property color highlight: Zenon.cyan

  readonly property var c: (Oracle.revision, Oracle.computer)
  readonly property bool reading: (Oracle.revision, Oracle.computerReading)
  readonly property var rows: pc.c && pc.c.ok ? pc.c.rows : []

  implicitHeight: body.implicitHeight + 28

  Row {
    id: body
    x: 24
    y: 6
    width: pc.width - 48
    spacing: 28

    // the logo, as fastfetch puts its ascii art beside the facts
    Item {
      width: 132
      height: Math.max(132, facts.implicitHeight)
      visible: pc.rows.length > 0
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4
        text: pc.c ? pc.c.glyph : ""
        color: pc.highlight
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(104)
      }
    }

    Column {
      id: facts
      width: body.width - (pc.rows.length > 0 ? 132 + body.spacing : 0)
      spacing: 4

      // the distro's name, as fastfetch heads its print, and a rule under it
      Text {
        visible: pc.rows.length > 0
        text: pc.c ? pc.c.title : ""
        color: pc.highlight
        font.family: pc.face
        font.weight: Font.DemiBold
        font.pixelSize: Zenon.px(17)
      }
      Rectangle {
        visible: pc.rows.length > 0
        width: Math.min(facts.width, 220)
        height: 1
        color: Zenon.border
      }
      Item { width: 1; height: 2; visible: pc.rows.length > 0 }

      Repeater {
        model: pc.rows
        delegate: Row {
          id: fact
          required property var modelData
          width: facts.width
          spacing: 12
          Text {
            id: factKey
            width: 128
            elide: Text.ElideRight
            text: fact.modelData.k
            color: pc.highlight
            font.family: pc.face
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(14)
          }
          Text {
            width: fact.width - factKey.width - fact.spacing
            elide: Text.ElideRight
            text: fact.modelData.v
            color: pc.fgColor
            font.family: pc.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
        }
      }

      // the inks, as fastfetch ends with its colour blocks
      Row {
        visible: pc.rows.length > 0
        topPadding: 8
        spacing: 0
        Repeater {
          model: ["red", "yellow", "green", "cyan", "blue", "magenta", "pink", "sand"]
          delegate: Rectangle {
            required property string modelData
            required property int index
            width: 26
            height: 14
            color: Zenon[modelData]
            topLeftRadius: index === 0 ? 3 : 0
            bottomLeftRadius: index === 0 ? 3 : 0
            topRightRadius: index === 7 ? 3 : 0
            bottomRightRadius: index === 7 ? 3 : 0
          }
        }
      }

      // nothing to show: still reading, or why not
      Text {
        visible: pc.rows.length === 0
        width: facts.width
        wrapMode: Text.Wrap
        text: pc.reading ? "Reading…"
          : pc.c && pc.c.missing ? "fastfetch is not installed — it is what reads the machine for this."
          : pc.c ? pc.c.why : ""
        color: pc.dimColor
        font.family: pc.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }

      Row {
        topPadding: 10
        spacing: 8
        DialogButton {
          visible: !!pc.c && !!pc.c.missing
          label: Ceres.installing ? "Installing…" : "Install fastfetch"
          ink: pc.highlight
          primary: true
          ready: !Ceres.installing
          onClicked: Ceres.install("fastfetch", "for About this computer in Oracle",
            (ok) => { if (ok) Oracle.readComputer(true); })
        }
        DialogButton {
          visible: !pc.c || !pc.c.missing
          label: pc.reading ? "Reading…" : "Read again"
          ink: pc.fgColor
          ready: !pc.reading
          onClicked: Oracle.readComputer(true)
        }
      }
    }
  }
}
