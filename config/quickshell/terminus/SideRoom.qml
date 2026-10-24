// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A FLOATING WINDOW MAKES ROOM FOR ITS SIDEBAR, AND GIVES IT BACK — the
// QML half of morpheus/room.js: the hyprctl round trip, the one resize per
// toggle, and the sidebar following the window while Hyprland animates it.
// Written out by hand in terminus, plato and minerva before this file;
// stylus was the first to use it, and the other three moved onto it the
// same day (2026-10-24).
//
//     SideRoom { id: room; window: win; anchor: keys; shown: win.sideOpen
//                want: win.sideW; box: sideBox; edge: "left" }
//     Item { id: sideBox
//       width: room.keepW >= 0 ? Math.max(0, Math.min(win.sideW, win.width - room.keepW))
//         : win.sideOpen ? win.sideW : 0
//       Behavior on width { enabled: !room.following; NumberAnimation { … } } }
//
// Floating, the window widens by the sidebar from the `edge` it stands on,
// so what is beside it holds still (pushed inward only when the monitor's
// edge is in the way), and hiding it gives back exactly what was added.
// Tiled, fullscreen or maximized, the layout owns the size: nothing is
// resized and the sidebar just slides (LayoutProbe knows which, before the
// toggle).
//
// ONE ANIMATION, NOT TWO. While Hyprland resizes, the rest of the window
// keeps its width (`keepW`, the window less the sidebar at the toggle) and
// the sidebar is exactly what the window has gained; `following` turns the
// sidebar's own slide off meanwhile. Released when the window lands, or
// after a ceiling. Each request says what it was for and resizes at most
// once: a quick show-hide must not land the show's answer after the hide
// and ratchet the window wider (terminus' split had that bug).
//
// Only the window the toggle happened in (`anchor`'s window is active):
// one setting shown in several windows widens only the one you are in.

import QtQuick
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus/room.js" as Room

Item {
  id: room

  property var window: null
  // any item in the window: whose Window.active says the toggle was here
  property Item anchor: null
  // the sidebar as wanted, its full width, and the item that shows it
  property bool shown: false
  property real want: 0
  property Item box: null
  property string edge: "left"
  // the narrowest the window may be made when the room is given back
  property int minW: 640
  // false holds the window's size still (minerva's focus mode)
  property bool active: true

  // what the window was widened by, so a hide gives back only that
  property int grew: 0
  property real keepW: -1
  property bool following: false
  // the layout owns the size (tiled, fullscreen, maximized): a window that
  // keeps its own size (minerva's winSize) keeps none then
  readonly property bool laidOut: layout.laidOut

  property int wantW: 0
  property bool forShown: false
  property bool pending: false
  property int target: 0

  onShownChanged: room.fit(room.shown)

  // TWO RELEASES, IN OPPOSITE ORDERS (terminus' SideMarks had both; one
  // release() for both was the 2026-10-24 regression: "this used to work
  // great before the helper").
  // A toggle or the ceiling: the slide switched back on, THEN the target
  // moved — with the target first the sidebar jumped instead of sliding.
  function release() {
    room.following = false;
    room.keepW = -1;
    ceiling.stop();
  }
  // LANDED: the window's width arrives before the box's binding has seen
  // it, so the box still holds its width from before the resize (0
  // opening, the full width closing). The slide switched on first eased it
  // from that stale width all over again — the page took the whole window
  // for a moment, reflowed, and reflowed back as the sidebar slid in. With
  // the slide still off, the box goes straight to what the window gained.
  function landed() {
    room.keepW = -1;
    room.following = false;
    ceiling.stop();
  }
  LayoutProbe { id: layout; title: room.window ? room.window.title : "" }
  Timer { id: ceiling; interval: 1500; onTriggered: room.release() }
  Connections {
    target: room.window
    function onWidthChanged() {
      if (room.keepW >= 0 && room.target > 0 && Math.abs(room.window.width - room.target) < 1) room.landed();
    }
  }

  function fit(shown) {
    if (!room.window || !room.anchor || !room.anchor.Window.active || !room.active) return;
    if (layout.laidOut) { room.grew = 0; return; }
    const w = room.window.width;
    if (shown) {
      if (room.grew > 0) return;
      room.wantW = w + Math.round(room.want);
    } else if (room.grew > 0) room.wantW = w - room.grew;
    // already out when the window floated (it opened tiled): closing still
    // gives its width back
    else if (room.box && room.box.width > 0.5) room.wantW = w - Math.round(room.box.width);
    else return;
    room.following = true;
    room.keepW = w - (room.box ? room.box.width : 0);
    room.target = 0;
    ceiling.restart();
    room.forShown = shown;
    room.pending = true;
    proc.running = false;
    proc.running = true;
  }
  Process {
    id: proc
    command: ["sh", "-c", "hyprctl -j activewindow; echo '@@mons'; hyprctl -j monitors"]
    stdout: StdioCollector {
      id: out
      onStreamFinished: {
        if (!room.pending) return;
        // asked for a state since toggled out of
        if (room.forShown !== room.shown) { room.pending = false; return; }
        const parts = out.text.split("@@mons");
        let w = null, mons = null;
        try { w = JSON.parse(parts[0]); mons = JSON.parse(parts[1]); } catch (e) { room.release(); return; }
        // the focused window is the one toggled; anything else is not ours
        if (!w || w.class !== "org.quickshell" || w.title !== room.window.title) { room.release(); return; }
        room.pending = false;
        layout.note(w);
        const r = Room.make(w, mons, room.wantW, 16, room.minW, room.edge);
        if (!r) room.release();
        else {
          room.target = w.size[0] + r.dw;
          Room.dispatches(w.address, r).forEach((d) => Hyprland.dispatch(d));
        }
        room.grew = room.forShown && r ? r.dw : 0;
      }
    }
  }
}
