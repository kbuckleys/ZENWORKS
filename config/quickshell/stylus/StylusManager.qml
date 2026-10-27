// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// STYLUS — an image onto a drive: a Linux ISO onto a USB stick, a Raspberry
// Pi image onto an SD card, packed or not, checked against its sums and
// read back once written.
//
// THIS IS THE PART THAT IS ALWAYS IN THE SHELL: the ipc handler, the
// .desktop entry, and a write while one runs. The window is compiled the
// first time it is opened and thrown away when it shuts; the drive watcher
// is the window's, so nothing runs while it is shut — unless a write does,
// and that outlives the window (howler says when it is done).
//
// The writing is core/forge.py's: udisks opens the drive and polkit asks
// for the password (hyprpolkitagent shows it), so nothing here holds one.
//
//   `qs ipc call Stylus open ""`        the window
//   `qs ipc call Stylus write <file>`   that image, chosen
//   `qs ipc call Stylus drive <dev>`    that drive chosen (a partition's
//                                       device picks the drive it is on)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../morpheus/lagnotes.js" as LagNotes
import "../morpheus/hypr.js" as Hypr
import "stylus.js" as S

Scope {
  id: mgr

  // terminus, handed in by shell.qml, for Open… (its picker)
  property var fileManager: null
  readonly property string core: Quickshell.shellDir + "/stylus/core/forge.py"
  // the drives' SMART and their self-tests: hestia's, not a second reader
  readonly property string healthCore: Quickshell.shellDir + "/hestia/core/health.py"

  // ── ASKING core/forge.py ───────────────────────────────────────────
  // one-off processes, made per ask and destroyed when answered;
  // fn(json | null) — forge's failures come through as its done event
  // ({ ok: false, why }), so the caller can say why. `script` is forge.py
  // unless another is named (healthCore); `input`, one line written to its
  // stdin and stdin shut (a passphrase: never an argument).
  Component { id: procComp; Process {} }
  Component { id: collComp; StdioCollector { waitForEnd: true } }
  function ask(args, fn, script, input) {
    const p = procComp.createObject(mgr);
    if (input !== undefined) {
      p.stdinEnabled = true;
      p.started.connect(() => { p.write(input + "\n"); p.stdinEnabled = false; });
    }
    const out = collComp.createObject(p);
    p.stdout = out;
    out.streamFinished.connect(() => {
      let j = null;
      try { j = JSON.parse(out.text); } catch (e) {}
      fn(j);
      p.destroy();
    });
    p.command = ["python3", "-I", script || mgr.core].concat(args);
    p.running = true;
  }

  // ── KEPT BETWEEN OPENINGS: the sidebar ─────────────────────────────
  property var settings: S.defaults()
  function set(key, value) {
    const s = Object.assign({}, mgr.settings);
    s[key] = value;
    mgr.settings = S.parseSettings(JSON.stringify(s));
    saveTimer.restart();
  }
  FileView {
    id: settingsFile
    path: Quickshell.statePath("stylus.json")
    blockLoading: true
    printErrors: false
    onLoaded: mgr.settings = S.parseSettings(settingsFile.text())
  }
  Timer { id: saveTimer; interval: 400; onTriggered: settingsFile.setText(S.serializeSettings(mgr.settings)) }

  // ── THE LONG RUNS ──────────────────────────────────────────────────
  // Here rather than in the window, so shutting the window does not stop
  // them: a write, a surface scan, a backup, one of each at a time
  // (ForgeJob). Each job, while it runs and after (until the next or a
  // clear): what it is about, phase, frac, rate, phaseMs, result.
  //
  // THE WRITE — `job`: { source, probe, drives, verify, … }. A /dev source
  // is a clone.
  readonly property var job: writeJob.job
  readonly property bool writing: writeJob.running
  function write(source, probe, drives, verify) {
    if (!source || drives.length === 0) return false;
    // a Windows installer is made onto its one drive, not copied
    if (probe && probe.kind === "windows")
      return writeJob.start(["windows", source, drives[0].block], { source: source, probe: probe, drives: [drives[0]], verify: false });
    return writeJob.start(["write", source].concat(drives.map((d) => d.block)).concat(verify ? [] : ["--no-verify"]),
                          { source: source, probe: probe, drives: drives, verify: verify });
  }
  function stop() { writeJob.stop(); }
  function clearJob() { writeJob.clear(); }
  ForgeJob {
    id: writeJob
    core: mgr.core
    dying: "The writer stopped"
    onEnded: if (!mgr.win || !mgr.win.visible) mgr.toast()
  }

  // A SURFACE SCAN — `scanJob`: { drive, … }; hours on a big drive
  readonly property var scanJob: scanJob_.job
  readonly property bool scanning: scanJob_.running
  function scan(drive) { return !!drive && scanJob_.start(["scan", drive.dev], { drive: drive }); }
  function stopScan() { scanJob_.stop(); }
  ForgeJob {
    id: scanJob_
    core: mgr.core
    dying: "The scan stopped"
    onEnded: (j) => {
      if ((mgr.win && mgr.win.visible) || !j) return;
      Quickshell.execDetached(["notify-send", "-a", "stylus", j.result.ok ? "Surface scan: clean" : "Surface scan",
        S.driveTitle(j.drive) + " \u2014 " + (j.result.ok ? "every sector reads" : j.result.why)]);
    }
  }

  // A BACKUP — `backupJob`: { drive, part, out, compress, … }
  readonly property var backupJob: backupJob_.job
  readonly property bool backingUp: backupJob_.running
  function backup(drive, part, out, compress) {
    if (!drive || !out) return false;
    return backupJob_.start(["backup", part ? part.dev : drive.dev, out].concat(compress ? [] : ["--raw"]),
                            { drive: drive, part: part || null, out: out, compress: compress });
  }
  function stopBackup() { backupJob_.stop(); }
  function clearBackup() { backupJob_.clear(); }
  ForgeJob {
    id: backupJob_
    core: mgr.core
    dying: "The backup stopped"
    onEnded: (j) => {
      if ((mgr.win && mgr.win.visible) || !j) return;
      Quickshell.execDetached(["notify-send", "-a", "stylus", j.result.ok ? "Backed up" : "Not backed up",
        j.result.ok ? String(j.out).replace(/.*\//, "") : j.result.why]);
    }
  }

  // A DOWNLOAD — `downloadJob`: { entry, … }; into Downloads, its sums
  // and signature beside it, then chosen in the write sheet
  readonly property var downloadJob: downloadJob_.job
  readonly property bool downloading: downloadJob_.running
  function download(e) {
    if (!e) return false;
    const args = ["download", e.url, UserDirs.downloads, e.file]
      .concat(e.sums ? ["--sums", e.sums.url, e.sums.name] : [])
      .concat(e.sig ? ["--sig", e.sig.url, e.sig.name] : [])
      .concat(e.sha256 && !e.sums ? ["--sha256", e.sha256] : []);
    return downloadJob_.start(args, { entry: e });
  }
  function stopDownload() { downloadJob_.stop(); }
  function clearDownload() { downloadJob_.clear(); }
  ForgeJob {
    id: downloadJob_
    core: mgr.core
    dying: "The download stopped"
    onEnded: (j) => {
      if (!j || !j.result) return;
      if (j.result.ok && mgr.win && mgr.win.visible) { mgr.win.downloaded(j.result.path); return; }
      if (mgr.win && mgr.win.visible) return;
      Quickshell.execDetached(["notify-send", "-a", "stylus", j.result.ok ? "Downloaded" : "Not downloaded",
        j.result.ok ? j.entry.name + " " + j.entry.version : j.result.why]);
    }
  }

  // A BENCHMARK — `benchJob`: { drive, … }; a minute or so, read-only
  readonly property var benchJob: benchJob_.job
  readonly property bool benching: benchJob_.running
  function bench(drive) { return !!drive && benchJob_.start(["bench", drive.dev], { drive: drive }); }
  function stopBench() { benchJob_.stop(); }
  function clearBench() { benchJob_.clear(); }
  ForgeJob { id: benchJob_; core: mgr.core; dying: "The benchmark stopped" }

  function toast() {
    const t = S.toastOf(mgr.job && mgr.job.result, (mgr.job ? mgr.job.drives : []).map((d) => S.driveTitle(d)));
    if (t) Quickshell.execDetached(["notify-send", "-a", "stylus", t.title, t.body]);
  }

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────
  // Offered for disk images in "Open with", never made the default: an ISO
  // is opened (terminus mounts it) far more often than it is written.
  readonly property var launcher: Desktop.launcher("stylus", {
    Type: "Application",
    Name: "Stylus",
    GenericName: "Disk Image Writer",
    Comment: "Write an ISO or a disk image to a USB drive or SD card, in Zenworks",
    Icon: "drive-removable-media",
    Categories: ["System", "Utility"],
    Keywords: ["iso", "usb", "image", "flash", "burn", "write", "sd", "card", "bootable", "etcher", "rufus", "dd"],
    Exec: Desktop.execLine(Quickshell.shellDir + "/stylus/bin/stylus", "%f"),
    Terminal: "false",
    StartupNotify: "false",
    MimeType: ["application/x-iso9660-image", "application/x-cd-image", "application/x-raw-disk-image",
               "application/x-raw-disk-image-xz-compressed"],
  })

  // ── THE WINDOW ─────────────────────────────────────────────────────
  // Floating by its title (hypr/lua/windowdefaults.lua: "stylus").
  property var win: null
  LazyComponent {
    id: lazy
    source: Qt.resolvedUrl("StylusWindow.qml")
    tag: "stylus"
  }
  function withWindow(fn) {
    lazy.withReady(() => {
      let fresh = false;
      if (!mgr.win) {
        const t0 = Date.now();
        mgr.win = lazy.comp.createObject(mgr, { mgr: mgr });
        LagNotes.mark("stylus window", t0);
        if (!mgr.win) return;
        fresh = true;
      }
      const was = !fresh && mgr.win.visible;
      fn(mgr.win);
      mgr.win.visible = true;
      if (was) Hyprland.dispatch(Hypr.focusTitle("stylus"));
    });
  }
  function retire(w) {
    if (mgr.win === w) mgr.win = null;
    if (!mgr.win && lazy.waiting.length === 0) lazy.comp = null;
  }

  function open() { mgr.withWindow((w) => w.refocus()); }
  function choose(path) {
    const p = String(path || "").trim();
    mgr.withWindow((w) => { if (p !== "") w.load(p); else w.refocus(); });
  }
  function pickDrive(dev) {
    const d = String(dev || "").trim();
    mgr.withWindow((w) => { if (d !== "") w.wantDrive(d); else w.refocus(); });
  }

  IpcHandler {
    target: "Stylus"
    function open(section: string): string { mgr.open(); return "ok"; }
    function write(path: string): string { mgr.choose(path); return "ok"; }
    function drive(dev: string): string { mgr.pickDrive(dev); return "ok"; }
  }
}
