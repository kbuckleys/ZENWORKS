// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE WINDOW SWITCHER — Super+Tab held: a row of every window, a picture of
// each, most recently used first. Tab steps on, Shift+Tab back, letting go
// of Super goes to the one lit. The card shows on the first press, with no
// wait (user, 2026-10-25); a quick tap still lands on the window before.
//
// HYPRLAND HOLDS THE KEYS, NOT THIS. binds.lua's cycle/cycleBack send
// `Switcher step next|back <seq>`, and a watch there on the chord's modifier
// sends `Switcher commit <seq>` once it is up — hyprland knows when a key
// comes up (hl.is_key_down); a layer that grabbed the keyboard would only
// know when it had the focus in time, and would take Super+Esc and every
// other bind away while it was open. So this takes no keyboard at all.
//
// THE SEQ: each `qs ipc call` is its own process, so a quick tap's step and
// commit can land in either order. Every press counts up; a commit for a
// step not seen yet waits for it. A smaller number than the last is
// hyprland's config reloaded (the count starts again), not an old press.
//
// ONE APP'S WINDOWS: `step app|appBack` (binds.lua's cycleApp, Super+Ctrl+
// Tab) is the same card holding only the windows of the app in front —
// what Cmd+` is on macOS.
//
// ON A TILE: the pointer lights it, a click goes there, a middle click or
// its × (shown while the pointer is on it) closes that window — closed as
// its own button would, so an app with unsaved work still asks.
//
// The pictures are live (ScreencopyView, live: true, user 2026-10-25) and
// only while the card is up: its tiles exist only then, so nothing is
// captured the rest of the time. Windows on other workspaces are shown too
// (an app may not draw new frames while it is out of sight, so those can
// hold still); picking one there takes you to it.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "."
import "switcher.js" as S
import "icons.js" as Icons
import "offspecial.js" as Off
import "hypr.js" as Hypr

PanelWindow {
  id: sw

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "zenworks-switcher"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  // [{ address, win }] at the moment it opened, in S.ordered order
  property var windows: []
  property int at: 0
  // stepping; `shown` is the card, up whenever there are two to pick from
  property bool open: false
  property bool shown: false
  property int lastSeq: 0
  property int pendingCommit: 0

  Binding { target: Zenon; property: "tipsAway"; value: sw.shown }

  // the workspace strip's quick rise and fade (user, 2026-10-25), started
  // a frame after the surface is asked for — see WorkspaceStrip
  property real showFactor: 0
  visible: sw.shown || sw.showFactor > 0.01
  onShownChanged: {
    if (sw.shown) { fallOut.stop(); sw.showFactor = 0; riseIn.restart(); }
    else { riseIn.stop(); fallOut.restart(); }
  }
  SequentialAnimation {
    id: riseIn
    PauseAnimation { duration: 16 }
    NumberAnimation { target: sw; property: "showFactor"; to: 1; duration: Zenon.fast; easing.type: Easing.OutCubic }
  }
  NumberAnimation { id: fallOut; target: sw; property: "showFactor"; to: 0; duration: Zenon.fast; easing.type: Easing.InCubic }

  implicitWidth: card.width + Zenon.menuShadowPad * 2
  implicitHeight: card.height + Zenon.menuShadowPad * 2

  // ── MOST RECENTLY USED ──
  property var mru: []
  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      if (Hyprland.activeToplevel) sw.mru = S.touch(sw.mru, Hyprland.activeToplevel.address);
    }
  }
  // what hyprland remembers from before the shell started, once its
  // clients have been read
  Component.onCompleted: { Hyprland.refreshToplevels(); seedLater.start(); }
  Timer {
    id: seedLater
    interval: 1500
    onTriggered: {
      const seeded = S.seed(Hyprland.toplevels.values.map((t) => ({
        address: t.address,
        history: t.lastIpcObject && t.lastIpcObject.focusHistoryID !== undefined ? t.lastIpcObject.focusHistoryID : -1 })));
      sw.mru = sw.mru.concat(seeded.filter((a) => sw.mru.indexOf(a) < 0));
    }
  }

  // ── STEPPING ──
  IpcHandler {
    target: "Switcher"
    // `next`, `back`, `app`, `appBack` — words, not ±1: the ipc command
    // line takes -1 for a flag
    function step(way: string, seq: int): void {
      sw.step(way === "back" || way === "appBack" ? -1 : 1, seq, way === "app" || way === "appBack");
    }
    function commit(seq: int): void { sw.commitAt(seq); }
    function cancel(): void { sw.finish(false); }
  }

  // which app a window is; the suite's own windows share quickshell's app
  // id and are told apart by title (each Window's title:, as oracle's
  // window rules do), so Super+Ctrl+Tab in Terminus is Terminus' windows
  function appOf(t) {
    const id = t && t.wayland ? String(t.wayland.appId || "") : "";
    return id === "org.quickshell" ? id + "\n" + String(t.title || "") : id;
  }
  function step(dir, seq, oneApp) {
    if (seq < sw.lastSeq) sw.pendingCommit = 0;
    sw.lastSeq = seq;
    if (!sw.open) {
      const app = sw.appOf(Hyprland.activeToplevel);
      const here = Hyprland.toplevels.values.filter((t) => t.wayland && (!oneApp || sw.appOf(t) === app));
      if (here.length === 0) return;
      // closed windows out of the order — pruned against every window, not
      // `here`: one app's card would otherwise forget the others' order
      sw.mru = sw.mru.filter((a) => Hyprland.toplevels.values.some((t) => t.address === a));
      sw.windows = S.ordered(here.map((t) => ({ address: t.address, win: t })), sw.mru);
      sw.at = S.firstStop(dir, sw.windows.length);
      sw.lastPoint = null;
      sw.open = true;
      sw.shown = sw.windows.length > 1;
    } else {
      sw.at = S.stepFrom(sw.at, dir, sw.windows.length);
    }
    idle.restart();
    if (sw.pendingCommit >= seq) sw.finish(true);
  }
  // a window closed from its tile: out of the row at once, the lit one
  // kept where it was
  function closeAt(i) {
    const w = sw.windows[i];
    if (!w) return;
    Hyprland.dispatch(Hypr.closeWindow(Hypr.byAddress(w.address)));
    const left = sw.windows.slice();
    left.splice(i, 1);
    sw.windows = left;
    if (left.length === 0) { sw.finish(false); return; }
    if (sw.at > i || sw.at >= left.length) sw.at = Math.max(0, sw.at - 1);
    idle.restart();
  }
  property var lastPoint: null
  function pointerMoved(p) {
    if (sw.lastPoint === null) { sw.lastPoint = p; return false; }
    if (Math.abs(p.x - sw.lastPoint.x) + Math.abs(p.y - sw.lastPoint.y) < 4) return false;
    sw.lastPoint = p;
    return true;
  }
  function commitAt(seq) {
    if (sw.open && seq >= sw.lastSeq) sw.finish(true);
    else sw.pendingCommit = seq;
  }
  function finish(go) {
    idle.stop();
    const w = sw.windows[sw.at];
    if (go && sw.open && w && !(Hyprland.activeToplevel && Hyprland.activeToplevel.address === w.address))
      Quickshell.execDetached(Off.wanted(Hypr.focusWindow(Hypr.byAddress(w.address))));
    sw.open = false;
    sw.shown = false;
    sw.pendingCommit = 0;
  }

  // a commit that never came (hyprland reloaded mid-hold): put away, unswitched
  Timer { id: idle; interval: 10000; onTriggered: sw.finish(false) }

  // ── THE CARD ──
  readonly property real tileW: Zenon.px(15) * 17
  readonly property real shotH: Math.round(sw.tileW * 0.62)
  readonly property int perRow: Math.max(1, Math.min(sw.windows.length,
    Math.floor(((sw.screen ? sw.screen.width : 1920) * 0.9 - 32) / (sw.tileW + 8))))

  // the card's rise too: MenuShadow follows the card's geometry, not its
  // transform, and would sit in place while the card came up into it
  MenuShadow { panel: card; cornerRadius: card.radius; opacity: sw.showFactor; transform: Translate { y: (1 - sw.showFactor) * 14 } }

  Rectangle {
    id: card
    x: Zenon.menuShadowPad
    y: Zenon.menuShadowPad
    width: grid.implicitWidth + 32
    height: grid.implicitHeight + 32
    radius: Zenon.windowRadius
    color: Zenon.layerBg
    border.width: 1
    border.color: Zenon.border
    opacity: sw.showFactor
    transform: Translate { y: (1 - sw.showFactor) * 14 }

    Grid {
      id: grid
      x: 16
      y: 16
      columns: sw.perRow
      spacing: 8

      Repeater {
        // kept while it fades out; gone (and nothing captured) once it has
        model: sw.visible ? sw.windows : []
        delegate: Item {
          id: tile
          required property var modelData
          required property int index
          readonly property var win: tile.modelData.win
          readonly property bool lit: tile.index === sw.at
          readonly property string appId: tile.win && tile.win.wayland ? String(tile.win.wayland.appId || "") : ""
          readonly property string wsName: tile.win && tile.win.workspace ? String(tile.win.workspace.name) : ""
          width: sw.tileW
          height: sw.shotH + nameRow.height + 26

          Rectangle {
            anchors.fill: parent
            radius: Zenon.radiusCard
            color: Zenon.menuHi
            visible: tile.lit
          }

          // the picture, kept to its window's shape inside the frame
          Item {
            id: frame
            x: 10
            y: 10
            width: parent.width - 20
            height: sw.shotH
            ScreencopyView {
              id: shot
              readonly property real aspect: shot.sourceSize.height > 0 ? shot.sourceSize.width / shot.sourceSize.height : 16 / 10
              anchors.centerIn: parent
              width: Math.min(frame.width, frame.height * shot.aspect)
              height: Math.min(frame.height, frame.width / shot.aspect)
              captureSource: tile.win ? tile.win.wayland : null
              live: true
              paintCursor: false
            }
            // nothing to show yet (or ever, for a window that will not be
            // captured): its glyph, large
            Text {
              anchors.centerIn: parent
              visible: !shot.hasContent
              text: Icons.appGlyph([tile.appId, tile.win ? tile.win.title : ""]) || "\u{F05C4}"
              color: Zenon.muted
              font.family: Zenon.face
              font.pixelSize: Zenon.px(36)
            }
          }

          Row {
            id: nameRow
            x: 10
            anchors.top: frame.bottom
            anchors.topMargin: 8
            width: parent.width - 20
            spacing: 6
            Text {
              id: glyph
              text: Icons.appGlyph([tile.appId, tile.win ? tile.win.title : ""]) || "\u{F05C4}"
              color: tile.lit ? Zenon.cyan : Zenon.accentMuted
              font.family: Zenon.face
              font.pixelSize: Zenon.px(15)
            }
            Text {
              width: nameRow.width - glyph.implicitWidth - ws.implicitWidth - nameRow.spacing * 2
              text: tile.win ? tile.win.title : ""
              elide: Text.ElideRight
              color: tile.lit ? Zenon.white : Zenon.soft
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
            // which workspace, when it is not this one
            Text {
              id: ws
              text: tile.win && tile.win.workspace && Hyprland.focusedWorkspace
                && tile.win.workspace !== Hyprland.focusedWorkspace
                ? tile.wsName.replace(/^special:/, "") : ""
              color: Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
          }

          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            // only a pointer that moves: the card opening under a resting
            // one would otherwise take the pick from the keys
            onPositionChanged: (mouse) => { if (sw.pointerMoved(mapToItem(null, mouse.x, mouse.y))) sw.at = tile.index; }
            onClicked: (mouse) => {
              if (mouse.button === Qt.MiddleButton) { sw.closeAt(tile.index); return; }
              sw.at = tile.index;
              sw.finish(true);
            }
          }

          // close it: there while the pointer is on the tile (or on the ×)
          ClearChip {
            anchors { right: frame.right; top: frame.top; rightMargin: 4; topMargin: 4 }
            size: Zenon.px(16)
            shown: hover.containsMouse || onChip.hovered
            onClicked: sw.closeAt(tile.index)
            HoverHandler { id: onChip }
          }
        }
      }
    }
  }
}
