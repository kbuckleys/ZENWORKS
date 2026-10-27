// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── NETWORK PLACES ───────────────────────────────────────────────────────
// Windows shares, SFTP, WebDAV, FTP and NFS, in the sidebar under Network
// (2026-10-21). gvfs mounts them (net/netplaces.py, through GIO) and puts
// each under its FUSE directory, so the listing, the previews and every
// file operation work on them as on any directory: nothing else in
// terminus knows a place is remote.
//
// The places you keep are a list in terminus-network.json (address, name,
// user, never a password) shared by every window, watched like the
// bookmarks. A password asked for is handed to gvfs on stdin; "Remember"
// lets gvfs keep it in the Secret Service, so the next connect asks
// nothing. gvfs itself (and gvfs-smb for Windows shares…) is installed
// through Ceres the first time a place needs it.
//
// `term` is the terminus window, as in every helper split out of it.

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../ceres"
import "network.js" as N

Item {
  id: net
  property var term: null

  readonly property string helper: Quickshell.shellDir + "/terminus/net/netplaces.py"
  property var places: []
  property var mounts: []
  readonly property var rows: N.rows(net.places, net.mounts)
  // the address being connected or disconnected, for the row's busy look
  property string busy: ""

  function tell(t) { term.status = t; term.statusBad = false; term.armStatusClear(); }

  // ── THE KEPT PLACES ──
  FileView {
    id: placesFile
    path: Quickshell.statePath("terminus-network.json")
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: net.places = N.parsePlaces(placesFile.text())
  }
  // FileView's own write never fires loaded: places is set first
  function persist(list) {
    net.places = list;
    placesFile.setText(JSON.stringify(list, null, 1) + "\n");
  }
  function keep(place) { net.persist(N.savePlace(net.places, place)); }
  function forget(uri) { net.persist(N.dropPlace(net.places, uri)); }

  // ── WHAT IS MOUNTED ──
  // Asked when a window shows, after every connect or disconnect, and
  // every thirty seconds while the sidebar is out; nothing runs when no
  // place is kept and nothing has ever been mounted.
  Process {
    id: lister
    command: ["python3", "-I", net.helper, "list"]
    stdout: StdioCollector {
      id: listOut
      waitForEnd: true
      onStreamFinished: {
        try {
          const j = JSON.parse(listOut.text);
          if (j && j.ok) net.mounts = j.mounts || [];
        } catch (e) {}
      }
    }
  }
  function refresh() { if (!lister.running) lister.running = true; }
  Timer {
    interval: 30000
    repeat: true
    running: !!net.term && net.term.visible && net.term.sidebar
      && (net.places.length > 0 || net.mounts.length > 0)
    onTriggered: net.refresh()
  }
  Connections {
    target: net.term
    function onVisibleChanged() { if (net.term.visible) net.refresh(); }
  }
  Component.onCompleted: net.refresh()

  // ── CONNECTING ──
  // one at a time. done(result) — netplaces.py's answer — after the window
  // has gone there on success; the connect sheet reads the failures.
  Component { id: procComp; Process { stdinEnabled: true } }
  Component { id: collComp; StdioCollector { waitForEnd: true } }
  function run(args, password, done) {
    const p = procComp.createObject(net);
    const out = collComp.createObject(p);
    p.stdout = out;
    out.streamFinished.connect(() => {
      let j = null;
      try { j = JSON.parse(out.text); } catch (e) {}
      done(j);
      p.destroy();
    });
    p.command = ["python3", "-I", net.helper].concat(args);
    // the password written once python is really there (AtomicWriter's
    // lesson: a write in the same breath as `running` can be lost)
    p.started.connect(() => { p.write((password || "") + "\n"); p.stdinEnabled = false; });
    p.running = true;
  }

  // place: { uri, name, user, domain }; opts: { password, remember, accept }
  function connect(place, opts, done) {
    if (net.busy !== "") return false;
    const o = opts || {};
    const args = ["mount", place.uri];
    if (place.user) args.push("--user", place.user);
    if (place.domain) args.push("--domain", place.domain);
    if (o.remember) args.push("--remember");
    if (o.accept) args.push("--accept");
    net.busy = place.uri;
    net.run(args, o.password || "", (r) => {
      net.busy = "";
      // gvfs is not there yet: Ceres puts it in, then the same connect again
      if (r && r.why === "missing" && !o.installed) {
        const pkgs = N.packagesFor(place.uri);
        const asked = Ceres.install(pkgs, "for network places in Terminus", (ok) => {
          if (ok) net.connect(place, Object.assign({}, o, { installed: true }), done);
          else if (done) done({ ok: false, why: "missing", message: "gvfs was not installed" });
        });
        if (!asked && done) done({ ok: false, why: "error", message: "Ceres is busy — try again once it is done" });
        return;
      }
      net.refresh();
      if (r && r.ok && r.path) term.goTo(r.path);
      if (done) done(r);
    });
    return true;
  }

  // a row chosen in the sidebar: there if mounted; a kept place connects
  // as it is (a remembered password needs nothing), asking only if it must
  function open(row) {
    if (!row) return;
    if (row.path !== "") { term.goTo(row.path); return; }
    net.connect(row, {}, (r) => {
      if (r && r.ok) return;
      if (r && (r.why === "auth" || r.why === "question")) term.connectRef.ask(row, r);
      else term.warn(N.failWords(r));
    });
  }

  function disconnect(row) {
    if (!row || net.busy !== "") return;
    // standing in it: home first, so the listing is not left on a dead path
    if (row.path !== "" && (term.cwd === row.path || term.cwd.startsWith(row.path + "/")))
      term.goTo(Paths.home());
    net.busy = row.uri;
    net.run(["unmount", row.uri], "", (r) => {
      net.busy = "";
      net.refresh();
      if (r && r.ok) net.tell("Disconnected from " + N.label(row));
      else term.warn(r && r.message ? r.message : "Could not disconnect");
    });
  }

  // the sidebar row's right click
  function menu(item, x, y, row) {
    if (!row) return;
    const on = row.path !== "";
    const out = [];
    if (on) {
      out.push({ label: "Open", act: () => term.goTo(row.path) });
      out.push({ label: "Open in new tab", act: () => term.newTab(row.path) });
      out.push({ label: "Disconnect", act: () => net.disconnect(row) });
    } else {
      out.push({ label: "Connect", act: () => net.open(row) });
      out.push({ label: "Connect as…", act: () => term.connectRef.ask(row, null) });
    }
    out.push({ sep: true });
    if (row.saved) {
      out.push({ label: "Edit…", act: () => term.connectRef.ask(row, null) });
      out.push({ label: "Remove from the sidebar", act: () => net.forget(row.uri) });
    } else {
      out.push({ label: "Keep in the sidebar", act: () => net.keep(row) });
    }
    out.push({ label: "Copy address", act: () => term.copyText(row.uri, "Copied " + row.uri) });
    term.menuPopRef.menu.openCustom(item, { x: x, y: y }, out, false);
    term.sideMenuAt = item;
  }
}
