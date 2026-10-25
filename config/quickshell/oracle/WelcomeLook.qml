// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// MAKE IT YOURS — the very first start's second card, after the cheat
// sheet (ZshSetup sequences them; Oracle.welcomeLookAsked opens it): dark
// or light, an accent, a background. Each is Oracle's own setting, set the
// moment it is picked, so the desktop behind it changes as you choose.
// Oracle's Global and Background sections hold them all afterwards.
//
//   Theme       Zenon dark, Zenon light, or Follow Background
//   Accent      the theme's own, or one of its other hues
//   Background  the Zenworks one stays unless a picture is chosen in
//               Picasso (the card closes and Picasso's setter opens)
//
// Done, Return or Esc closes it.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../morpheus"
// qualified, for Segments alone: oracle and terminus import each other
import "../terminus" as Term

PanelWindow {
  id: look

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "zenworks-welcome"
  WlrLayershell.keyboardFocus: look.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  anchors { left: true; right: true; top: true; bottom: true }
  color: "transparent"

  property bool shown: false
  property real showFactor: look.shown ? 1 : 0
  Behavior on showFactor { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
  visible: look.shown || look.showFactor > 0.01

  Binding { target: Oracle; property: "welcomeLookOpen"; value: look.shown }
  Connections {
    target: Oracle
    function onWelcomeLookAsked() { look.shown = true; Qt.callLater(() => keys.forceActiveFocus()); }
  }
  function close() { look.shown = false; }

  HyprlandFocusGrab {
    windows: [ look ]
    active: look.shown
    onCleared: look.close()
  }

  // the accents on offer: the worn theme's own hues, so each reads on it
  readonly property var hues: ["cyan", "blue", "green", "magenta", "pink", "yellow", "sand", "red"]
  function hex(c) { return String(c).slice(0, 7); }
  readonly property string accentNow: Oracle.accentColor

  Item {
    id: keys
    focus: true
    Keys.onPressed: (e) => {
      if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { look.close(); e.accepted = true; }
    }
  }

  // ── THE SCREEN ──
  Rectangle {
    anchors.fill: parent
    color: Zenon.darken(0.32)
    opacity: look.showFactor
    MouseArea { anchors.fill: parent; onClicked: look.close() }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(look.width - 48, Zenon.px(15) * 34)
    height: body.implicitHeight + 56
    radius: Zenon.windowRadius
    color: Zenon.layerBg
    border.width: 1
    border.color: Zenon.border
    opacity: look.showFactor
    scale: 0.97 + 0.03 * look.showFactor

    MouseArea { anchors.fill: parent }

    Column {
      id: body
      x: 28
      y: 28
      width: card.width - 56
      spacing: 18

      Column {
        spacing: 4
        Text {
          text: "Make it yours"
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(20)
        }
        Text {
          width: body.width
          wrapMode: Text.Wrap
          text: "Pick what you like; it changes as you pick. Oracle keeps all of it for later."
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
      }

      SectionLabel { text: "Theme" }
      Term.Segments {
        options: [["zenon", "Dark"], ["zenon-light", "Light"], ["follow", "Follow background"]]
        current: Oracle.theme
        onChose: (v) => Oracle.set("theme", v)
      }

      SectionLabel { text: "Accent" }
      Row {
        spacing: 10
        Repeater {
          model: look.hues
          delegate: Rectangle {
            id: sw
            required property var modelData
            required property int index
            // the first is the theme's own: no color of its own laid over
            readonly property bool own: sw.index === 0
            readonly property bool on: sw.own ? look.accentNow === "" : look.accentNow === look.hex(Zenon[sw.modelData])
            width: Zenon.px(15) * 2
            height: width
            radius: width / 2
            color: Zenon[sw.modelData]
            border.width: sw.on ? 3 : 1
            border.color: sw.on ? Zenon.ink : Zenon.border
            MouseArea {
              anchors.fill: parent
              onClicked: Oracle.set("accentColor", sw.own ? "" : look.hex(Zenon[sw.modelData]))
            }
          }
        }
      }

      SectionLabel { text: "Background" }
      // the words, then the button under them: side by side they ran
      // past the card on a narrow (portrait) screen (user, 2026-10-25)
      Column {
        spacing: 10
        Text {
          width: body.width
          wrapMode: Text.Wrap
          text: "The Zenworks one, until you choose another."
          color: Zenon.soft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
        DialogButton {
          label: "Choose a picture…"
          ink: Zenon.cyan
          onClicked: {
            look.close();
            Quickshell.execDetached(["qs", "ipc", "call", "Picasso", "toggle"]);
          }
        }
      }

      Item {
        width: body.width
        height: done.height
        DialogButton {
          id: done
          anchors.right: parent.right
          label: "Done"
          ink: Zenon.cyan
          primary: true
          onClicked: look.close()
        }
      }
    }
  }
}
