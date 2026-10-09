// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHETHER HYPRLAND'S LAYOUT OWNS A WINDOW'S SIZE — tiled, maximized or
// fullscreen — for the windows that widen themselves to make room for a
// panel (terminus' sidebar, plato's tree; see terminus.js splitRoom, which
// declines exactly these three).
//
// Known BEFORE a toggle rather than asked at it. Asking at the toggle held
// the panel still for the round trip to hyprctl, and leaving that hold in a
// window no resize would ever come to is where the panel jumped instead of
// sliding. Read when the window appears, and again whenever Hyprland says a
// window opened, moved, or changed its floating or fullscreen state.
//
//     LayoutProbe { id: layout; title: root.title }
//     ... if (layout.laidOut) just slide; else make room
//
// `note(w)` takes a hyprctl window object the holder already has in hand
// (its own fit query), so the two never disagree.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
  id: probe

  // the window's title, as hyprctl reports it (class org.quickshell)
  property string title: ""
  property bool laidOut: false

  function note(w) {
    if (w) probe.laidOut = !w.floating || !!w.fullscreen;
  }
  function refresh() { proc.running = false; proc.running = true; }

  Process {
    id: proc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      id: out
      onStreamFinished: {
        let list = [];
        try { list = JSON.parse(out.text); } catch (e) { return; }
        probe.note(list.find((c) => c.class === "org.quickshell" && c.title === probe.title));
      }
    }
  }
  // a burst of events (a window opening fires several) is one read
  Timer { id: soon; interval: 120; onTriggered: probe.refresh() }
  Connections {
    target: Hyprland
    function onRawEvent(ev) {
      const n = ev.name;
      if (n === "changefloatingmode" || n === "fullscreen" || n === "openwindow"
          || n === "movewindowv2" || n === "workspacev2") soon.restart();
    }
  }
  onTitleChanged: soon.restart()
  Component.onCompleted: soon.restart()
}
