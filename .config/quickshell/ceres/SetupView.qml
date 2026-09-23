// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SETUP — what ceres needs and does not have, and one button that fetches it.
//
// Each missing package with what ceres wants it for, so it reads as a short
// list of things to install rather than a list of failures. When paru itself
// is missing, the one choice that is yours to make: the tagged release, or
// the latest commit. Both are built from their AUR recipe, which takes the
// source from paru's GitHub — so pacman tracks the result like any package,
// and paru can update itself from then on.

import QtQuick
import "../morpheus"
import "."

Item {
  id: view

  // "paru" or "paru-git"; the holder reads it when Install is pressed
  property string choice: "paru"
  // what the content needs, for a window sizing itself to it
  readonly property real needH: setupCol.implicitHeight

  Column {
    id: setupCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: 14

    Text {
      text: "Ceres needs a few things first"
      color: Zenon.white
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: 22
    }

    Column {
      width: parent.width
      spacing: 6
      Repeater {
        model: Ceres.deps.missing
        delegate: Row {
          required property var modelData
          spacing: 12
          Text {
            width: 190
            textFormat: Text.StyledText
            text: modelData.pkg + (modelData.aur ? "  <font color='" + Zenon.magenta + "'>AUR</font>" : "")
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 17
          }
          Text {
            width: view.width - 202
            wrapMode: Text.Wrap
            text: modelData.why.join("; ")
            color: Zenon.keyInk
            font.family: Zenon.face
            font.pixelSize: 16
          }
        }
      }
    }

    // ── which paru ──────────────────────────────────────────────────────
    Column {
      visible: Ceres.deps.paru
      width: parent.width
      spacing: 10
      topPadding: 8

      Text {
        text: "Build paru from"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: 15
      }

      Row {
        spacing: 12
        Repeater {
          model: [["paru", "Latest release", "the tagged version, updated when paru cuts one"],
                  ["paru-git", "Latest commit", "follows paru's GitHub master as it moves"]]
          delegate: Rectangle {
            id: opt
            required property var modelData
            readonly property bool on: view.choice === opt.modelData[0]
            width: (view.width - 12) / 2
            height: optCol.implicitHeight + 24
            radius: Zenon.windowRadius
            color: opt.on ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.2) : "transparent"
            border.width: 1
            border.color: opt.on ? Zenon.cyan : Zenon.border
            Column {
              id: optCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: 4
              Text {
                text: opt.modelData[0]
                color: opt.on ? Zenon.cyan : Zenon.white
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: 18
              }
              Text {
                text: opt.modelData[1]
                color: Zenon.white
                font.family: Zenon.face
                font.pixelSize: 16
              }
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: opt.modelData[2]
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 15
              }
            }
            TapHandler { onTapped: view.choice = opt.modelData[0] }
          }
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Built from its AUR recipe, which fetches the source from github.com/Morganamilo/paru, "
          + "and installed by pacman, so paru is tracked like any other package. Building compiles Rust "
          + "and takes a few minutes."
        color: Zenon.muted
        font.family: Zenon.face
        font.pixelSize: 15
      }
    }
  }
}
