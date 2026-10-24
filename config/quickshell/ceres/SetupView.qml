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
//
// And once, whether the Store should carry Flathub's apps too (user,
// 2026-10-14): asked here so Ceres fetches Flatpak with everything else, as
// it fetches paru — see Ceres.flatpakAsk. Opt-in: unticked until ticked.

import QtQuick
import "../morpheus"
import "../morpheus/controls" as Controls
import "."

Item {
  id: view

  // "paru" or "paru-git"; the holder reads it when Install is pressed
  property string choice: "paru"
  // Flatpak too? — read with `choice` when Install is pressed
  property bool flatpak: false
  // what the content needs, for a window sizing itself to it
  readonly property real needH: setupCol.implicitHeight
  // the names' column, as wide as the longest (archlinux-appstream-data ran
  // into its reason at a fixed 190)
  FontMetrics { id: mfName; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: Zenon.px(17) }
  readonly property real nameW: {
    let w = 190;
    for (const m of Ceres.deps.missing)
      w = Math.max(w, Math.ceil(mfName.advanceWidth(m.pkg + (m.aur ? "  AUR" : ""))) + 4);
    return w;
  }

  Column {
    id: setupCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: 14

    Text {
      text: Ceres.deps.missing.length ? "Ceres needs a few things first" : "One question for the Store"
      color: Zenon.white
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(22)
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
            width: view.nameW
            textFormat: Text.StyledText
            linkColor: Zenon.link   // a link in it is the theme's (Zenon.link)
            text: modelData.pkg + (modelData.aur ? "  <font color='" + Zenon.magenta + "'>AUR</font>" : "")
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(17)
          }
          Text {
            width: view.width - view.nameW - 12
            wrapMode: Text.Wrap
            text: modelData.why.join("; ")
            color: Zenon.accentKey
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(16)
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
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(15)
      }

      ParuChoice {
        width: parent.width
        choice: view.choice
        onPicked: (pkg) => view.choice = pkg
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Built from its AUR recipe, which fetches the source from github.com/Morganamilo/paru, "
          + "and installed by pacman, so paru is tracked like any other package. Building compiles Rust "
          + "and takes a few minutes."
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
    }

    // ── Flatpak too? ────────────────────────────────────────────────────
    Column {
      visible: Ceres.flatpakAsk
      width: parent.width
      spacing: 10
      topPadding: 8

      Text {
        text: "Apps in the Store"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(15)
      }

      // ONE BOX, NOT TWO CARDS: Arch and the AUR are always there — two
      // cards side by side read as Arch OR Flatpak (user, 2026-10-14)
      Rectangle {
        id: fpCard
        width: parent.width
        height: fpCol.implicitHeight + 24
        radius: Zenon.windowRadius
        color: view.flatpak ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.2) : "transparent"
        border.width: 1
        border.color: view.flatpak ? Zenon.cyan : Zenon.border
        Controls.Check {
          id: fpBox
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          lit: view.flatpak
          // the card's tap below takes a tap on the box too — both answered
          // it, and a click on the box ticked it twice: nothing
        }
        Column {
          id: fpCol
          anchors.left: fpBox.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          Text {
            text: "Also add Flatpak apps"
            color: view.flatpak ? Zenon.cyan : Zenon.white
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(18)
          }
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: "Sandboxed apps from Flathub, in the Store beside the repos and the AUR"
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
        }
        TapHandler { onTapped: view.flatpak = !view.flatpak }
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: view.flatpak
          ? "Installs flatpak and adds Flathub as a source for the whole system. Each Flatpak "
            + "install then asks whether it is for everyone or just you."
          : "Flatpak can be added later from Settings."
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
    }
  }
}
