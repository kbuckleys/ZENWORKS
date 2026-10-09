// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' the sidebar … logic, out of TerminusWindow.qml
// (2026-10-08). The state stays on the window (term); the window keeps a
// one-line forwarder for each function here, so callers are unchanged.

import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Effects
import QtMultimedia
import Qt.labs.folderlistmodel
import "../morpheus"
import "../picasso"
import "../oracle"
import "terminus.js" as Terminus
import "../morpheus/icons.js" as Icons
import "../morpheus/thumbs.js" as Thumbs
import "tags.js" as Tags
import "collections.js" as Coll

Item {
  id: sideMarks
  property var term: null

  function toggleSidebar() { term.setSidebar(!term.sidebar); }
  function setSidebar(on) {
    if (on === term.sidebar) return;
    term.sidebar = on;
    term.sideRoom(on);
  }
  // IN THIS ORDER: the slide switched back on, THEN the target moved.
  // sideKeepW = -1 alone did both at once, in whichever order Qt chose, and
  // with the target first the sidebar jumped instead of sliding — every
  // toggle in a tiled or maximized window, where no resize ever comes.
  function releaseSideFollow() {
    term.sideFollowing = false;
    term.sideKeepW = -1;
    term.sideCeilingRef.stop();
  }
  // LANDED: THE OTHER ORDER. The window's width arrives here before the
  // sidebar's binding has seen it, so `side` still holds its width from
  // before the resize (0 opening, the full width closing). Switching the
  // slide back on first eased it from that stale width all over again —
  // the listing took the whole window for a moment, reflowed to a column
  // more, and reflowed back as the sidebar slid in. With the slide still
  // off, the sidebar goes straight to the width the window just gained.
  function noteSideWidth() {
    if (term.sideKeepW >= 0 && term.sideTarget > 0
        && Math.abs(term.width - term.sideTarget) < 1) {
      term.sideKeepW = -1;
      term.sideFollowing = false;
      term.sideCeilingRef.stop();
    }
  }
  function sideRoom(shown) {
    if (!term.visible) return;
    if (term.sideLayoutRef.laidOut) { term.sideGrew = 0; return; }
    if (shown) {
      if (term.sideGrew > 0) return;
      term.sideWant = term.width + Math.round(term.sidebarWidth);
    } else if (term.sideGrew > 0) term.sideWant = term.width - term.sideGrew;
    else return;
    term.sideFollowing = true;
    term.sideKeepW = term.width - term.sideRef.width;
    term.sideTarget = 0;
    term.sideCeilingRef.restart();
    term.sideFor = shown;
    term.sidePending = true;
    sideFitProc.running = false;
    sideFitProc.running = true;
  }
  Process {
    id: sideFitProc
    command: ["sh", "-c", "hyprctl -j activewindow; echo '@@mons'; hyprctl -j monitors"]
    stdout: StdioCollector {
      id: sideFitOut
      onStreamFinished: {
        if (!term.sidePending) return;
        // asked for a state we have since toggled out of
        if (term.sideFor !== term.sidebar) { term.sidePending = false; return; }
        const parts = sideFitOut.text.split("@@mons");
        let w = null, mons = null;
        try { w = JSON.parse(parts[0]); mons = JSON.parse(parts[1]); } catch (e) { term.releaseSideFollow(); return; }
        // the window the toggle happened in is the focused one; anything
        // else answering here is not ours to resize
        if (!w || w.class !== "org.quickshell" || w.title !== term.title) { term.releaseSideFollow(); return; }
        term.sidePending = false;
        term.sideLayoutRef.note(w);
        const room = Terminus.splitRoom(w, mons, term.sideWant, 16, 560, "left");
        // no resize coming (tiled, or no room): the sidebar slides as before
        if (!room) term.releaseSideFollow();
        else {
          term.sideTarget = w.size[0] + room.dw;
          Terminus.splitRoomDispatches(w.address, room).forEach((d) => Hyprland.dispatch(d));
        }
        term.sideGrew = term.sideFor && room ? room.dw : 0;
        term.saveSide();
      }
    }
  }
  // Three rows claimed to be where you are at once: the bookmark for the
  // directory, and EVERY disk whose mount is a prefix of it — with / and
  // /home both mounted that is two disks for any path under home. Each drew
  // its own bar, and the single travelling cursor went to whichever claimed
  // last. Leaving a collection flips them all back at the same moment, and
  // the last one is the bottom disk: the cursor went all the way to the
  // bottom of the sidebar.
  //
  // Answered once, here, so the rows only compare against it. A bookmark
  // for the exact directory beats a disk that merely contains it, and the
  // longest mount beats a shorter one — /home is a better answer than / for
  // /home/buck.
  //
  // A PREFIX IS NOT A PATH: "/home" is a prefix of the string "/homework"
  // and has nothing to do with it, so the test is the whole component.
  function under(path, mount) {
    if (mount === "" || path === "") return false;
    if (mount === "/") return path.charAt(0) === "/";
    return path === mount || path.indexOf(mount + "/") === 0;
  }
  // A disk with its CURRENT figures: the record says what the disk is, the
  // map says how full it is now.
  function diskLive(d) {
    if (!d) return d;
    const u = term.diskUse[d.path];
    return u ? Object.assign({}, d, u) : d;
  }
  Process {
    id: diskProc
    stdout: StdioCollector {
      id: diskOut
      waitForEnd: true
      onStreamFinished: {
        const found = Terminus.parseDisks(diskOut.text);
        const key = Terminus.diskKey(found);
        // ── THE SAME DISKS, FULLER OR EMPTIER ──────────────────────
        // The key is which disks there are and where they are mounted —
        // it is what decides whether something ARRIVED. It says nothing
        // about how full they are, so returning on it froze every gauge
        // at whatever the first poll saw: copy a film onto a stick and
        // its bar never moved. The figures are compared separately and
        // taken whenever they change; only a changed key goes on to the
        // arrival logic below.
        //
        // INTO A MAP OF THEIR OWN, not into root.disks: replacing that list
        // rebuilds every disk row in the sidebar and the sheet, and doing it
        // every two seconds of a copy would blink the sidebar's cursor off
        // and on. The rows read their figures through diskLive instead.
        const use = ({});
        for (const d of found) use[d.path] = { avail: d.avail, fsSize: d.fsSize, fsUsed: d.fsUsed };
        if (JSON.stringify(use) !== JSON.stringify(term.diskUse)) term.diskUse = use;
        if (key === term.diskKey) return;
        // Something appeared or was mounted. Opening the sidebar unasked is
        // justified exactly once — when a disk shows up that was NOT THERE A
        // MOMENT AGO, which is the moment you want to see it.
        //
        // `seen` is what makes that "a moment ago" real. Without it the first
        // poll of the session counted every disk in the machine as newly
        // arrived and threw the sidebar open on startup, every time.
        const grew = term.diskSeen && found.length > term.disks.length;
        // before root.disks is replaced: what is new is measured against it
        const fresh = Terminus.arrivals(term.diskSeen ? term.disks : null, found);
        // A mount that was here last poll and is not now: unmounted from
        // this window, another one, a terminal or the stick pulled out. Every
        // pane and tab standing inside it steps out, rather than showing the
        // contents of a disk that is no longer there until you touch a row.
        const gone = Terminus.mountsGone(term.disks, found);
        term.disks = found;
        for (const mp of gone) term.leaveMount(mp);
        term.diskKey = key;
        term.diskSeen = true;
        if (grew && term.visible) term.setSidebar(true);
        if (fresh.length > 0 && term.ownsDiskPrompt()) term.plugRef.add(fresh);
        term.plugRef.settle();
      }
    }
  }
  function pollDisks() {
    if (diskProc.running) return;
    diskProc.command = ["sh", "-c", Terminus.disksCommand()];
    diskProc.running = true;
  }
  function drainMounts() {
    if (mountProc.running || term.mountQueue.length === 0) return;
    const q = term.mountQueue.slice();
    mountProc.command = ["sh", "-c", q.shift()];
    term.mountQueue = q;
    mountProc.running = true;
  }
  Process {
    id: mountProc
    onExited: Qt.callLater(term.drainMounts)
    stdout: StdioCollector {
      id: mountOut
      waitForEnd: true
      onStreamFinished: {
        const t = String(mountOut.text || "").trim();
        // udisks' own words either way — but a mount that WORKED is an
        // ordinary note, not the red of a refusal
        const last = t.split("\n").pop();
        const ok = /^(Mounted|Unmounted|Safe to remove)\b/.test(last);
        // the LAST line is the verdict: a chain says each step, and a
        // fallback mount says what it settled for (read-only, and why)
        if (ok) term.status = /^Unmounted, safe/.test(last) ? last : t.split("\n")[0];
        else term.warn(Terminus.tidyDiskError(t));
        // a mount that failed is not one to wait for — the new-disk card
        // would otherwise sit on "Mounting…" for good
        if (!/^(Mounted|Unmounted|Safe to remove)\b/.test(t.split("\n").pop())) term.plugRef.goAfter = "";
        // an unmount chain says each step; the last line is the verdict
        if (/Safe to remove$/.test(t)) term.status = "safe to remove";
        if (/^Mounted .*\(read-only/.test(last)) term.warn(last.replace(/^Mounted \S+ at /, ""));
        // re-read straight away rather than waiting for the next tick, so the
        // row stops saying "mount" the instant it is mounted
        term.diskKey = "";
        diskProc.command = ["sh", "-c", Terminus.disksCommand()];
        diskProc.running = true;
      }
    }
  }
  // Every pane and background tab standing in `mp` (or under it) goes home.
  // Called when a mount goes away, and BEFORE this window unmounts one: the
  // listing, the watch and the thumbnailers all stand in the directory, and a
  // disk you are looking at is a disk that is busy.
  function leaveMount(mp) {
    if (!mp || mp === "/" || Terminus.isSystemMount(mp)) return;
    const inside = (p) => p === mp || String(p || "").indexOf(mp + "/") === 0;
    const home = Paths.home();
    if (inside(term.pas.cwd)) {
      term.pas.cwd = home;
      term.pas.raw = [];
      term.pas.lastListing = null;
      term.pas.sel = 0;
      term.refreshOther();
    }
    if (inside(term.cwd)) {
      if (term.searchMode !== "") term.clearSearch();
      term.goTo(home);
    }
    let moved = false;
    const next = term.tabs.map((t, i) => {
      if (i === term.tab || !t) return t;
      const a = inside(t.cwd), b = inside(t.otherCwd);
      if (!a && !b) return t;
      moved = true;
      const c = Object.assign({}, t);
      if (a) { c.cwd = home; c.rows = []; c.listing = undefined; c.sel = 0; c.trail = []; c.trailAt = -1; }
      if (b) { c.otherCwd = home; c.otherRaw = []; c.otherSel = 0; }
      return c;
    });
    if (moved) term.tabs = next;
  }
  // The same, in every terminus window — the one unmounting is not the only
  // one that may be standing on the disk.
  function leaveMountEverywhere(mp) {
    const ws = term.mgr ? term.mgr.wins : [term];
    for (const w of ws) { try { if (w) w.leaveMount(mp); } catch (e) {} }
  }
  function mountDisk(d) {
    const q = term.mountQueue.slice();
    if (d.mount !== "") term.leaveMountEverywhere(d.mount);
    q.push(d.mount === "" ? Terminus.mountCommand(d.path, d.fstype) : Terminus.unmountCommand(d.path));
    term.mountQueue = q;
    term.drainMounts();
  }
  // Everything on the device this partition belongs to, unmounted, and the
  // device powered off — see Terminus.ejectCommand. Through the mount queue,
  // so it waits for anything already mounting.
  function ejectDisk(d) {
    const dev = d.device !== "" ? d.device : d.path;
    const on = term.disks.filter(x => (x.device !== "" ? x.device : x.path) === dev
                                      && x.mount !== "");
    for (const x of on) term.leaveMountEverywhere(x.mount);
    const parts = on.map(x => x.path);
    const q = term.mountQueue.slice();
    q.push(Terminus.ejectCommand(dev, parts));
    term.mountQueue = q;
    term.drainMounts();
  }
  // ONE THING ASKS. Every open terminus polls lsblk, and a disk plugged in
  // with three windows up is one question, not three. The window you are
  // using asks — and only that one: with none of them holding the keyboard
  // the pill asks instead (terminus/PlugPanel), which is on screen wherever
  // you are. The pill checks `keyed` the same way and stands down for it.
  function ownsDiskPrompt() {
    return !term.isPicker && term.shown && term.keyed;
  }
  // Right-clicking a disk in the sidebar used to do what a left click does.
  // A disk has more to it than going there: it can be taken away, its path
  // copied, and looked at — so it gets the menu every other thing in this
  // window has, and Properties opens diskInfo, a card of what the disk is.
  // The erase question for DiskTool, on the confirmation sheet in red.
  function confirmErase(heading, detail, items, onYes) {
    term.confirmRef.askMany(heading, detail,
      [{ label: "Format", ink: Zenon.red, act: onYes }], items);
  }
  function diskMenu(item, x, y, d) {
    if (!d) return;
    const on = d.mount !== "";
    const out = [];
    if (on) {
      out.push({ label: "Open", act: () => term.goTo(d.mount) });
      out.push({ label: "Open in new tab", act: () => term.newTab(d.mount) });
    } else {
      out.push({ label: "Mount", act: () => term.mountDisk(d) });
    }
    if (on && !Terminus.isSystemMount(d.mount))
      out.push({ label: "Unmount", act: () => term.mountDisk(d) });
    if (Terminus.ejectable(d))
      out.push({ label: "Safely remove", act: () => term.ejectDisk(d) });
    out.push({ sep: true });
    if (on)
      out.push({ label: "Copy mount point",
                 act: () => term.copyText(d.mount, "copied " + d.mount) });
    out.push({ label: "Copy device path",
               act: () => term.copyText(d.path, "copied " + d.path) });
    // The system's own disks are never repaired or formatted from here: they
    // cannot be unmounted while the system runs on them.
    if (!Terminus.isSystemMount(d.mount)) {
      out.push({ sep: true });
      out.push({ label: "Check and repair\u2026", act: () => term.diskToolRef.ask(d, "repair") });
      out.push({ label: "Format\u2026", act: () => term.diskToolRef.ask(d, "format") });
    }
    out.push({ sep: true });
    out.push({ label: "Properties", act: () => term.diskInfoRef.ask(d) });
    term.menuPopRef.menu.openCustom(item, { x: x, y: y }, out, false);
    term.sideMenuAt = item;
  }
}
