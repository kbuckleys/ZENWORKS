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

  // THE OSD'S POP (user, 2026-10-26: the workspace and window switchers
  // "should also have the same OSD animations" — howler/HowlerOsd): in over
  // its size and back with OutBack, out with InBack, a swell then down to
  // where it came from. No rise any more. Started a frame after the surface
  // is asked for: the layer maps as `drawn` flips, and a pop started that
  // same frame had run its first part before there was anything to see.
  // `drawn` is let go only once the pop back has finished, and never by a
  // binding: a layer's `visible` must not blink false between two states.
  property bool shown: false
  property bool drawn: false
  visible: strip.drawn
  readonly property int popMs: Zenon.normal * 2
  SequentialAnimation {
    id: arrive
    PauseAnimation { duration: 16 }
    ParallelAnimation {
      NumberAnimation { target: body; property: "scale"; from: 0.72; to: 1; duration: strip.popMs; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
      NumberAnimation { target: body; property: "opacity"; to: 1; duration: Zenon.fast; easing.type: Zenon.ease }
    }
  }
  ParallelAnimation {
    id: leave
    NumberAnimation { target: body; property: "scale"; to: 0.72; duration: strip.popMs; easing.type: Easing.InBack; easing.overshoot: 2.2 }
    NumberAnimation { target: body; property: "opacity"; to: 0; duration: strip.popMs; easing.type: Easing.InQuart }
    onFinished: { strip.shown = false; strip.drawn = false; }
  }
  // up, with the pop; already up, it only holds longer
  // (caught going, it pops again from where the pop begins, as the OSD does)
  function show() {
    const going = leave.running;
    leave.stop();
    if (!strip.shown || going) {
      if (!going) body.opacity = 0;
      strip.shown = true;
      strip.drawn = true;
      arrive.restart();
    }
    hold.restart();
  }
  // room for the swell past its size
  readonly property real popRoom: Math.ceil(Math.max(card.width, card.height) * 0.04)

  implicitWidth: card.width + (Zenon.menuShadowPad + strip.popRoom) * 2
  implicitHeight: card.height + (Zenon.menuShadowPad + strip.popRoom) * 2

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "workspacev2" || !Oracle.workspaceStrip) return;
      const id = parseInt(String(event.data).split(",")[0]);
      if (!(id > 0)) return;
      strip.show();
    }
  }
  Timer { id: hold; interval: 900; onTriggered: { arrive.stop(); leave.restart(); } }

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

  // the pop is on one item that holds both, so the shadow is carried with
  // the card rather than sitting in place under it (MenuShadow follows
  // geometry, not transforms)
  Item {
    id: body
    anchors.fill: parent
    opacity: 0
    scale: 0.72

    MenuShadow { panel: card; cornerRadius: card.radius }

    Rectangle {
      id: card
      x: Zenon.menuShadowPad + strip.popRoom
      y: Zenon.menuShadowPad + strip.popRoom
      width: row.implicitWidth + 20
      height: row.implicitHeight + 20
      color: Zenon.floor(Zenon.glass(Oracle.notifBgOpacity))
      border.color: Zenon.border
      border.width: 1
      radius: Zenon.windowRadius * 2

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
}
