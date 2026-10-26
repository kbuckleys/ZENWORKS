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

  // INSTANT IN, A QUICK FADE OUT (user, 2026-10-26: "remove the fade in.
  // so the switcher is instant at spawn"). Hyprland's layer fade is off for
  // it (rules.lua), since a layer rule cannot keep only one way of it; the
  // fade out is this one. `drawn` is let go by hand once the fade is done,
  // never by a binding, so the layer cannot blink off and on.
  property bool drawn: false
  property real cardOpacity: 1
  visible: sw.drawn
  onShownChanged: {
    if (sw.shown) {
      fadeOut.stop();
      sw.cardOpacity = 1;
      sw.drawn = true;
      peekLater.restart();
    } else {
      peekLater.stop();
      fadeOut.restart();
    }
  }
  NumberAnimation {
    id: fadeOut
    target: sw; property: "cardOpacity"; to: 0
    duration: Zenon.fast; easing.type: Zenon.ease
    onFinished: if (!sw.shown) sw.drawn = false
  }

  // ── THE PEEK ── (user, 2026-10-26) every window but the picked one fades
  // while the card is up, so the picked one shows through: rules.lua fades
  // what carries the tag zen-peek, and a tag taken off gives a window back
  // exactly what its own rules said. Only the windows that change are
  // dispatched (S.peekPlan); a beat after the card is up, so a quick tap of
  // Super+Tab flashes nothing.
  property var peeked: []
  property bool peeking: false
  function peek(pick) {
    const p = S.peekPlan(sw.windows.map((w) => w.address), pick, sw.peeked);
    for (const a of p.add) Hyprland.dispatch(Hypr.tagWindow(Hypr.byAddress(a), "zen-peek", true));
    for (const a of p.drop) Hyprland.dispatch(Hypr.tagWindow(Hypr.byAddress(a), "zen-peek", false));
    sw.peeked = p.tagged;
  }
  Timer {
    id: peekLater
    interval: 150
    onTriggered: {
      const w = sw.windows[sw.at];
      if (!sw.shown || !w) return;
      sw.peeking = true;
      sw.peek(w.address);
    }
  }
  onAtChanged: {
    const w = sw.windows[sw.at];
    if (sw.peeking && w) sw.peek(w.address);
  }
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
      // a peek a reload or crash left behind (finish never ran) is lifted
      for (const t of Hyprland.toplevels.values)
        Hyprland.dispatch(Hypr.tagWindow(Hypr.byAddress(t.address), "zen-peek", false));
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
      // the tiles are built now (the Repeater's model follows `open`); laid
      // out now too, not at the frame's end, so the layer is asked for at
      // the card's real size the first time
      grid.forceLayout();
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
    // the lit one closed: `at` may not change, yet it names the next window
    // now, which the peek still had faded
    if (sw.peeking) sw.peek(left[sw.at].address);
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
    // focused AND raised: focus alone left a window under the floating ones
    // over it (user, 2026-10-26). Raised even when it already has the focus.
    if (go && sw.open && w)
      Quickshell.execDetached(Off.wanted([Hypr.focusWindow(Hypr.byAddress(w.address)),
                                          Hypr.raiseWindow(Hypr.byAddress(w.address))]));
    sw.peeking = false;
    sw.peek("");
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

  MenuShadow { panel: card; cornerRadius: card.radius; opacity: sw.cardOpacity }

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
    opacity: sw.cardOpacity

    Grid {
      id: grid
      x: 16
      y: 16
      columns: sw.perRow
      spacing: 8

      Repeater {
        // built the moment a press opens it, BEFORE the layer maps: gated
        // on `visible`, the surface mapped at the empty card's size and
        // then resized as the tiles came, a configure round trip late — the
        // "tiny bit of delay on spawn" (user, 2026-10-26). Kept while it
        // fades out; gone (and nothing captured) once it has.
        model: sw.open || sw.drawn ? sw.windows : []
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
