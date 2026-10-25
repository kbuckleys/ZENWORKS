// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE WORKSPACE STRIP — every time the workspace changes, however it was
// changed (Super+1…5, the bar, a window switched to, a gesture), a strip of
// this screen's workspaces shows low on the screen for a moment: each one's
// number and the apps on it, the one you are on now lit. Then it fades.
//
// Only shown, never clicked: its input region is empty, so the pointer and
// the desktop under it carry on as if it were not there. Oracle › Windows ›
// Workspace strip turns it off.
//
// The card is the volume OSD's (howler/HowlerOsd): the toasts' ground,
// border and corners, MenuShadow behind it — written out from the same
// settings Howler's are (Howler.bg, borderSize, radius), since morpheus
// does not import howler, which imports morpheus.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../oracle"
import "."
import "icons.js" as Icons

PanelWindow {
  id: strip

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "zenworks-workspaces"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  anchors.bottom: true
  margins.bottom: Math.round((strip.screen ? strip.screen.height : 1080) * 0.12)
  color: "transparent"
  mask: Region {}

  // A QUICK RISE AND FADE (user, 2026-10-25): up 14px into place as it
  // fades in, back down as it goes. Run by hand rather than a Behavior, a
  // frame after the surface is asked for: the layer maps as `shown` flips,
  // and a fade started that same frame had already run its first part
  // before there was anything on screen to see it.
  property bool shown: false
  property real showFactor: 0
  visible: strip.shown || strip.showFactor > 0.01
  SequentialAnimation {
    id: riseIn
    PauseAnimation { duration: 16 }
    NumberAnimation { target: strip; property: "showFactor"; to: 1; duration: Zenon.fast; easing.type: Easing.OutCubic }
  }
  NumberAnimation {
    id: fallOut
    target: strip; property: "showFactor"; to: 0; duration: Zenon.fast; easing.type: Easing.InCubic
    onFinished: strip.shown = false
  }
  function show() {
    fallOut.stop();
    if (!strip.shown) { strip.shown = true; strip.showFactor = 0; riseIn.restart(); }
    else if (!riseIn.running) strip.showFactor = 1;
    hold.restart();
  }

  implicitWidth: card.width + Zenon.menuShadowPad * 2
  implicitHeight: card.height + Zenon.menuShadowPad * 2

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "workspacev2" || !Oracle.workspaceStrip) return;
      const id = parseInt(String(event.data).split(",")[0]);
      if (!(id > 0)) return;
      strip.show();
    }
  }
  Timer { id: hold; interval: 900; onTriggered: { riseIn.stop(); fallOut.restart(); } }

  // this screen's workspaces, in number order: [{ ws, apps: [glyph] }]
  readonly property var tiles: {
    const mon = Hyprland.focusedMonitor;
    const tops = Hyprland.toplevels.values;
    return Hyprland.workspaces.values
      .filter((w) => w.id > 0 && (!mon || w.monitor === mon))
      .sort((a, b) => a.id - b.id)
      .map((w) => ({
        ws: w,
        apps: tops.filter((t) => t.workspace === w).map((t) =>
          Icons.appGlyph([t.wayland ? String(t.wayland.appId || "") : "", t.title]) || "\u{F05C4}")
      }));
  }
  readonly property int maxApps: 4
  readonly property real tileW: Zenon.px(15) * 5

  // the card's rise too: MenuShadow follows the card's geometry, not its
  // transform, and would sit in place while the card came up into it
  MenuShadow { panel: card; cornerRadius: card.radius; opacity: strip.showFactor; transform: Translate { y: (1 - strip.showFactor) * 14 } }

  Rectangle {
    id: card
    x: Zenon.menuShadowPad
    y: Zenon.menuShadowPad
    width: row.implicitWidth + 20
    height: row.implicitHeight + 20
    color: Zenon.floor(Zenon.glass(Oracle.notifBgOpacity))
    border.color: Zenon.border
    border.width: 1
    radius: Zenon.windowRadius * 2
    opacity: strip.showFactor
    transform: Translate { y: (1 - strip.showFactor) * 14 }

    Row {
      id: row
      x: 10
      y: 10
      spacing: 6

      Repeater {
        model: strip.tiles
        delegate: Rectangle {
          id: tile
          required property var modelData
          readonly property bool lit: tile.modelData.ws === Hyprland.focusedWorkspace
          width: strip.tileW
          height: num.implicitHeight + apps.implicitHeight + 22
          radius: Zenon.radiusCard
          color: tile.lit ? Zenon.menuHi : "transparent"

          BarText {
            id: num
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            src: String(tile.modelData.ws.id)
            numeric: true
            color: tile.lit ? Zenon.cyan : Zenon.light ? Zenon.dimInk : Zenon.mix(Zenon.dimInk, Zenon.cyan, 0.5)
          }
          // the apps on it, a glyph each; an empty one says so with a dot
          Text {
            id: apps
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: num.bottom
            anchors.topMargin: 6
            readonly property var all: tile.modelData.apps
            text: apps.all.length === 0 ? "·"
              : apps.all.slice(0, strip.maxApps).join(" ")
                + (apps.all.length > strip.maxApps ? " +" + (apps.all.length - strip.maxApps) : "")
            color: tile.lit ? Zenon.white : Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
        }
      }
    }
  }
}
