// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A DISK WAS PLUGGED IN — asked by the pill. Terminus asks this in its own
// window, but only when you are using it (ownsDiskPrompt there); the rest of
// the time nobody was asking, and a stick went in unnoticed. So the pill
// morphs into the same card — terminus/PlugBody, the same rows and buttons —
// and offers Mount, or Mount & open, which mounts it and opens it in terminus.
//
// IT WAS NOT ASKED FOR, and behaves like it:
//   - It takes no keyboard until you click it. Whatever you were typing
//     into keeps getting the keys. Once clicked it holds the keyboard
//     (Return, Esc, m, ↑↓) and a click elsewhere puts it away.
//   - It takes no clicks outside itself (`mask`), so the screen behind it
//     stays usable.
//   - Left alone it goes away on its own (`idle`).
//   - It never takes the pill from a layer you opened: a disk arriving then
//     waits for the pill to be free, and opening a layer over it puts it
//     away (`held`).
//
// Watched, not polled: `udevadm monitor` says when a block device comes or
// goes, and only then is lsblk read — through terminus.js, the same
// parseDisks / arrivals / mountCommand terminus uses.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland
import "../morpheus"
import "terminus.js" as Terminus

LayerPopup {
  id: popup

  // the file manager, for Mount & open, and for knowing when one of its
  // windows is the one asking
  property var fileManager: null
  // the pill is busy with something you opened, or the screen is locked
  property bool held: false

  readonly property int panelWidth: 640
  function calcHeight() { return body.wantH; }

  // ── the disks ───────────────────────────────────────────────────────────
  property var disks: []
  property bool seen: false
  // device paths asked about this time, in the order they arrived
  property var paths: []
  property int sel: 0
  property string goAfter: ""
  property string mounting: ""
  property string note: ""
  // clicked into: has the keyboard, and a click elsewhere closes it
  property bool engaged: false

  readonly property var rows: {
    const out = [];
    for (const p of popup.paths)
      for (const d of popup.disks) if (d.path === p) { out.push(d); break; }
    return out;
  }
  readonly property bool open: popup.shown && !popup.collapsing

  // A focused terminus window asks for itself — see ownsDiskPrompt there.
  function terminusAsks() {
    const m = popup.fileManager;
    if (!m || !m.wins) return false;
    for (const w of m.wins) {
      try { if (w && w.shown && !w.isPicker && w.keyed) return true; } catch (e) {}
    }
    return false;
  }

  function read() {
    if (lsblk.running) { reread.restart(); return; }
    lsblk.command = ["sh", "-c", Terminus.disksCommand()];
    lsblk.running = true;
  }

  Process {
    id: lsblk
    stdout: StdioCollector {
      id: lsblkOut
      waitForEnd: true
      onStreamFinished: {
        const found = Terminus.parseDisks(lsblkOut.text);
        const fresh = Terminus.arrivals(popup.seen ? popup.disks : null, found);
        popup.disks = found;
        popup.seen = true;
        if (fresh.length > 0 && !popup.terminusAsks()) popup.add(fresh);
        popup.settle();
      }
    }
  }

  // udev says a few things per plug — the disk, then each partition, then
  // their changes — so they are let settle into one read
  Timer { id: reread; interval: 350; onTriggered: popup.read() }

  Process {
    id: udev
    command: ["udevadm", "monitor", "--udev", "--subsystem-match=block"]
    running: true
    stdout: SplitParser {
      onRead: (line) => { if (/\(block\)\s*$/.test(line)) reread.restart(); }
    }
    // it should never end; if it does, start it again rather than going deaf
    onExited: revive.restart()
  }
  Timer { id: revive; interval: 5000; onTriggered: udev.running = true }

  Component.onCompleted: popup.read()

  // ── asking ──────────────────────────────────────────────────────────────
  function add(list) {
    const ps = popup.paths.length > 0 && (popup.open || popup.held) ? popup.paths.slice() : [];
    for (const d of list) if (ps.indexOf(d.path) < 0) ps.push(d.path);
    popup.paths = ps;
    if (!popup.open) { popup.sel = 0; popup.goAfter = ""; popup.mounting = ""; popup.note = ""; }
    popup.ask();
  }

  function ask() {
    if (popup.held || popup.rows.length === 0) return;
    idle.interval = 15000;
    if (!popup.open) {
      popup.engaged = false;
      popup.shown = true;
      popup.collapsing = false;
      popup.playOpen();
    }
    popup.rearm();
  }

  // A disk arriving while the pill was wearing something else waits for it;
  // something opened over the question puts the question away.
  onHeldChanged: {
    if (popup.held) { if (popup.open) popup.dismiss(); }
    else if (popup.rows.length > 0) popup.ask();
  }

  // After every read: open the disk that was waiting to be mounted, and
  // close once every disk it asked about has been pulled out again.
  function settle() {
    if (popup.goAfter !== "") {
      for (const d of popup.disks) {
        if (d.path !== popup.goAfter || d.mount === "") continue;
        popup.goAfter = "";
        popup.openAt(d.mount);
        popup.dismiss();
        return;
      }
    }
    if (popup.mounting !== "") {
      for (const d of popup.disks) {
        if (d.path !== popup.mounting || d.mount === "") continue;
        popup.mounting = "";
        // it says where it went, briefly, then goes
        idle.interval = 4000;
        popup.rearm();
      }
    }
    if (!popup.open && !popup.held) return;
    if (popup.rows.length === 0) popup.dismiss();
    else if (popup.sel >= popup.rows.length) popup.sel = popup.rows.length - 1;
  }

  function dismiss() {
    popup.paths = [];
    popup.goAfter = "";
    popup.mounting = "";
    popup.engaged = false;
    if (!popup.open) return;
    popup.collapsing = true;
    popup.playClose();
  }

  function openAt(mp) {
    if (popup.fileManager) popup.fileManager.reveal(mp);
  }

  // ── mounting, one at a time ─────────────────────────────────────────────
  // As terminus does it: one Process given a second command while it runs
  // drops the first, so Mount all queues.
  property var queue: []

  function mount(d) {
    if (!d || d.mount !== "") return;
    popup.note = "";
    const q = popup.queue.slice();
    q.push(Terminus.mountCommand(d.path, d.fstype));
    popup.queue = q;
    popup.drain();
  }

  function drain() {
    if (mountProc.running || popup.queue.length === 0) return;
    const q = popup.queue.slice();
    mountProc.command = ["sh", "-c", q.shift()];
    popup.queue = q;
    mountProc.running = true;
  }

  Process {
    id: mountProc
    onExited: Qt.callLater(popup.drain)
    stdout: StdioCollector {
      id: mountOut
      waitForEnd: true
      onStreamFinished: {
        const t = String(mountOut.text || "").trim();
        const last = t.split("\n").pop();
        if (!/^Mounted\b/.test(last)) {
          // a mount that failed is not one to wait for
          popup.note = Terminus.tidyDiskError(t);
          popup.goAfter = "";
          popup.mounting = "";
        } else if (/\(read-only/.test(last)) {
          popup.note = last.replace(/^Mounted \S+ at \S+ /, "");
        }
        popup.read();
      }
    }
  }

  function mountOne(i) {
    const d = popup.rows[i];
    if (!d) return;
    if (d.mount !== "") { popup.openAt(d.mount); if (popup.rows.length === 1) popup.dismiss(); return; }
    popup.mount(d);
  }

  // Mount & open, Mount all, or Open — the foot's primary button and Return
  function primary() {
    if (popup.rows.length === 1) {
      const d = popup.rows[0];
      if (d.mount !== "") { popup.openAt(d.mount); popup.dismiss(); return; }
      popup.goAfter = d.path;
      popup.mount(d);
      return;
    }
    const left = popup.rows.filter(d => d.mount === "");
    if (left.length === 0) { popup.dismiss(); return; }
    for (const d of left) popup.mount(d);
  }

  function justMount() {
    const d = popup.rows[0];
    if (!d || d.mount !== "") return;
    popup.mounting = d.path;
    popup.mount(d);
  }

  function step(n) {
    const c = popup.rows.length;
    if (c > 0) popup.sel = (popup.sel + n + c) % c;
  }

  // ── not asked for ───────────────────────────────────────────────────────
  // Counted only while nobody is with it: not under the pointer, not
  // clicked into, not mounting. Each of those ending starts it again.
  Timer {
    id: idle
    interval: 15000
    onTriggered: popup.dismiss()
  }
  function rearm() {
    if (popup.open && !popup.engaged && !hover.hovered && !body.busy) idle.restart();
    else idle.stop();
  }
  onOpenChanged: popup.rearm()
  onEngagedChanged: popup.rearm()
  Connections { target: hover; function onHoveredChanged() { popup.rearm(); } }
  Connections { target: body; function onBusyChanged() { popup.rearm(); } }

  focusable: popup.engaged
  mask: Region { x: panel.x; y: panel.y; width: panel.width; height: panel.height }

  HyprlandFocusGrab {
    windows: [ popup ]
    active: popup.engaged && popup.open
    onCleared: popup.dismiss()
  }

  function engage() {
    if (popup.engaged) return;
    popup.engaged = true;
    keys.forceActiveFocus();
  }

  Item {
    id: keys
    focus: true
    Keys.onPressed: (event) => {
      const k = event.key;
      event.accepted = true;
      if (k === Qt.Key_Escape) popup.dismiss();
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
        if (!body.busy) popup.primary();
      }
      else if (popup.rows.length > 1 && (k === Qt.Key_Down || event.text === "j")) popup.step(1);
      else if (popup.rows.length > 1 && (k === Qt.Key_Up || event.text === "k")) popup.step(-1);
      else if (popup.rows.length > 1 && (event.text === "m" || event.text === "M")) popup.mountOne(popup.sel);
      else event.accepted = false;
    }
  }

  // ── the card ────────────────────────────────────────────────────────────
  Item {
    id: panel
    width: Zenon.layerWidth(popup.panelWidth)
    height: popup.calcHeight()
    Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
    // placed by y, not by an anchor pair — see CeresPanel
    anchors.horizontalCenter: parent.horizontalCenter
    y: Zenon.barTop ? Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
      : parent.height - height - Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
    z: 1
    opacity: popup.contentFade
    transform: Scale {
      origin.x: panel.width / 2
      origin.y: Zenon.barTop ? 0 : panel.height
      xScale: popup.panelX
      yScale: popup.panelY
    }

    HoverHandler { id: hover }
    // a press anywhere on the card is the card being taken up
    MouseArea { anchors.fill: parent; onPressed: popup.engage() }

    LayerShadow {
      panel: bgRoot
      cornerRadius: Zenon.pillRadius
      morphed: popup.morphMode
    }

    ClippingRectangle {
      id: bgRoot
      anchors.fill: parent
      color: popup.morphMode ? "transparent" : Zenon.layerBg
      border.color: Zenon.border
      border.width: 1
      radius: Zenon.pillRadius

      PlugBody {
        id: body
        anchors.fill: parent
        rows: popup.rows
        sel: popup.sel
        goAfter: popup.goAfter
        mounting: popup.mounting
        note: popup.note
        openVerb: true
        details: false
        onSelected: (i) => { popup.sel = i; popup.engage(); }
        onMountOne: (i) => popup.mountOne(i)
        onPrimary: popup.primary()
        onJustMount: popup.justMount()
        onDismissed: popup.dismiss()
      }
    }
  }
}
