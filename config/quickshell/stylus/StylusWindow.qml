// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// STYLUS' WINDOW — Disk Utility's shape (user, 2026-10-24): every drive
// in a sidebar with its volumes under it, the one chosen in full beside it,
// and what can be done to it in the toolbar. A drive shows its partition
// map; a volume shows what is taking up its room, by kind (the shell's
// colored UsageBar, as terminus' Info sheet wears it). The doing happens
// in sheets over it — writing an image, and terminus' own DiskTool for
// First Aid and Erase; the window itself never turns into a form.
//
// The system's own disk is listed and never written, erased, repaired or
// unmounted from here (S.offWhy says so on every button). Drives come and
// go as they are plugged (forge.py watch, tethered, only while this is
// open). The sidebar makes room for itself as terminus', plato's and
// minerva's do (terminus/SideRoom). A write is the manager's, so this
// window can shut and the write goes on.
//
//   ↑ ↓     a drive          w       write an image to it
//   m       mount, unmount   ctrl e  eject
//   ctrl o  open an image    ctrl b  the sidebar
//   esc     the sheet, then the window

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../morpheus/controls" as Ctl
import "../terminus"
import "../terminus/terminus.js" as Terminus
import "../hermes"
import "../hestia/hestia.js" as Health
import "../ceres"
import "../terminus/usage.js" as U
import "stylus.js" as S

FloatingWindow {
  id: sw
  title: "stylus"
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: 1040
  implicitHeight: 660
  minimumSize: Qt.size(720, 480)

  property var mgr: null

  onVisibleChanged: if (!sw.visible) Qt.callLater(() => { if (sw.mgr) sw.mgr.retire(sw); sw.destroy(); })
  onClosed: sw.visible = false
  Component.onCompleted: {
    sw.refresh();
    // a write running when the window opens: its sheet, at once
    if (sw.mgr && sw.mgr.writing) sw.sheetOpen = true;
  }

  // terminus' bar height (user, 2026-10-24: lower, the count beside the name)
  readonly property int headH: Zenon.toolbarH
  readonly property int sideW: 280
  readonly property var settings: sw.mgr ? sw.mgr.settings : S.defaults()
  readonly property bool sideOpen: sw.settings.sidebar

  // ── THE DRIVES ─────────────────────────────────────────────────────────
  property var drives: []
  // the drive chosen (its udisks block), and a partition of it picked in
  // the sidebar ("" for the whole drive)
  property string sel: ""
  property string part: ""
  // a drive asked for by device before the list had it (ipc `drive`)
  property string wantDev: ""
  readonly property var drive: sw.drives.find((d) => d.block === sw.sel) || null
  readonly property var order: S.ordered(sw.drives)
  // the volume picked under it, or null for the drive as a whole
  readonly property var vol: S.partOf(sw.drive, sw.part)
  // why each action is off for what is chosen, "" when it is not
  function off(action) { return S.offWhy(action, sw.drive, sw.vol); }
  // `after`, once the new list is in (an unlock's mount)
  function refresh(after) {
    sw.mgr.ask(["drives"], (list) => {
      if (!Array.isArray(list)) return;
      const ds = list;
      const want = sw.wantDev !== "" ? ds.find((d) => d.dev === sw.wantDev || d.parts.some((q) => q.dev === sw.wantDev)) : null;
      sw.drives = ds;
      sw.askHealth();
      if (want) { sw.choose(want); sw.wantDev = ""; }
      // the one chosen went: the first there is (a new one plugged in
      // while nothing was chosen is chosen)
      else if (!sw.drive) { const o = S.ordered(ds); sw.sel = o.length ? o[0].block : ""; sw.part = ""; }
      // a volume that went: its drive
      else if (sw.part !== "" && !S.partOf(sw.drive, sw.part)) sw.part = "";
      const p = {};
      ds.forEach((d) => { if (sw.picked[d.block]) p[d.block] = true; });
      sw.picked = p;
      if (after) after();
    });
  }
  // ── HEALTH ─────────────────────────────────────────────────────────────
  // hestia's SMART reader (health.py disks), asked with the drives and,
  // while a drive's own self-test runs, every few seconds until it is done
  property var health: []
  function healthOf(d) { return d ? (sw.health.find((h) => h.id === d.id) || null) : null; }
  function verdictOf(d) { const h = sw.healthOf(d); return h && h.kind ? Health.diskVerdict(h) : null; }
  function askHealth() { sw.mgr.ask(["disks"], (j) => { if (Array.isArray(j)) sw.health = j; }, sw.mgr.healthCore); }
  readonly property bool testing: sw.health.some((h) => Health.selftestOf(h).running)
  Timer { interval: 5000; repeat: true; running: sw.testing; onTriggered: sw.askHealth() }
  property bool asking: false
  function selftest(what) {
    const d = sw.drive;
    if (!d || sw.asking) return;
    sw.asking = true;
    sw.mgr.ask(["selftest", d.id, what], (j) => {
      sw.asking = false;
      if (j && j.ok) sw.say(what === "abort" ? "Self-test stopped" : "Self-test started — the drive runs it on its own", false);
      else sw.say(j && j.why ? j.why : "The self-test could not start", true);
      sw.askHealth();
    }, sw.mgr.healthCore);
  }

  function choose(d, partDev) { sw.sel = d ? d.block : ""; sw.part = partDev || ""; }
  function move(by) {
    const i = sw.order.findIndex((d) => d.block === sw.sel);
    const n = Math.max(0, Math.min(sw.order.length - 1, i + by));
    if (sw.order.length) sw.choose(sw.order[n]);
  }
  function wantDrive(dev) { sw.wantDev = dev; sw.refresh(); sw.refocus(); }
  function setSidebar(on) { sw.mgr.set("sidebar", on); }
  // plugged in or pulled out: forge's watch waits out a burst, then says
  Process {
    running: true
    command: Paths.tether(["python3", "-I", Quickshell.shellDir + "/stylus/core/forge.py", "watch"])
    stdout: SplitParser { splitMarker: "\n"; onRead: (line) => sw.refresh() }
  }

  // ── THE IMAGE ──────────────────────────────────────────────────────────
  property string path: ""
  property var probe: null
  property var sumsCheck: null       // { running } or { done } (forge sums)
  readonly property var sums: S.sumsOf(sw.probe, sw.sumsCheck)

  // ── WHO SIGNED IT ──────────────────────────────────────────────────────
  // forge sig, after the probe: the image's signature or its checksums';
  // a signer's key is fetched only when asked (it goes into your keyring)
  property var sigState: null
  readonly property var sig: S.sigWords(sw.sigState)
  property bool fetching: false
  function runSig(p) {
    sw.mgr.ask(["sig", p], (j) => { if (sw.path === p) sw.sigState = j && !j.ev ? j : null; });
  }
  function fetchKey() {
    if (!sw.sig.key || sw.fetching) return;
    sw.fetching = true;
    sw.mgr.ask(["fetchkey", sw.sig.key], (j) => {
      sw.fetching = false;
      if (j && j.ok) sw.runSig(sw.path);
      else sw.say(j && j.why ? j.why : "The key could not be fetched", true);
    });
  }

  // ── A WINDOWS INSTALLER'S SPLIT: wimlib, installed through Ceres the
  // first time a big install.wim needs it
  property bool haveWimlib: false
  Process {
    running: true
    command: ["sh", "-c", "command -v wimlib-imagex"]
    onExited: (code) => sw.haveWimlib = code === 0
  }

  // ── A DOWNLOAD ─────────────────────────────────────────────────────────
  property bool downloadOpen: false
  function downloadAsk() {
    sw.downloadOpen = true;
    if (!sw.mgr.downloadJob) downloadBody.reset();
    Qt.callLater(() => downloadBody.forceActiveFocus());
  }
  function closeDownload() {
    sw.downloadOpen = false;
    if (sw.mgr.downloadJob && !sw.mgr.downloading) sw.mgr.clearDownload();
    sw.refocus();
  }
  // a finished download: the image chosen, in the write sheet
  function downloaded(path) {
    sw.downloadOpen = false;
    sw.mgr.clearDownload();
    sw.load(path);
  }
  function load(p) {
    if (sw.busy) { sw.say("A write is running — wait for it or stop it", true); return; }
    sw.srcMode = "image";
    sw.srcBlock = "";
    sw.path = p;
    sw.probe = null;
    sw.stopSums();
    sw.sigState = null;
    sw.mgr.clearJob();
    sw.mgr.ask(["probe", p], (j) => {
      if (sw.path !== p) return;
      if (!j || j.ev === "done") { sw.path = ""; sw.say(j && j.why ? j.why : "That file could not be read as an image", true); return; }
      sw.probe = j;
      if (j.sums) sw.runSums(p);
      sw.runSig(p);
    });
    sw.writeSheet();
  }
  function openAsk() {
    if (sw.busy || !sw.mgr.fileManager) return;
    const start = sw.path !== "" ? sw.path.replace(/\/[^/]*$/, "") : UserDirs.downloads;
    sw.mgr.fileManager.choose(false, start, (paths) => { if (paths && paths.length > 0) sw.load(paths[0]); });
  }
  function runSums(p) {
    sw.sumsCheck = { running: true };
    sumsProc.command = ["python3", "-I", sw.mgr.core, "sums", p];
    sumsProc.running = true;
  }
  function stopSums() { if (sumsProc.running) sumsProc.signal(15); sw.sumsCheck = null; }
  Process {
    id: sumsProc
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => {
        const e = S.parseEvent(line);
        if (e && e.ev === "done" && sw.sumsCheck) sw.sumsCheck = { done: e };
      }
    }
  }

  // ── WHERE A WRITE COMES FROM: an image file, or another drive (a clone)
  property string srcMode: "image"
  property string srcBlock: ""
  readonly property var srcDrive: sw.drives.find((d) => d.block === sw.srcBlock) || null
  function setSourceMode(m) {
    if (sw.srcMode === m) return;
    sw.srcMode = m;
    sw.srcBlock = "";
    sw.path = "";
    sw.probe = null;
    sw.stopSums();
  }
  function pickSource(d) {
    sw.srcMode = "drive";
    sw.srcBlock = d.block;
    sw.path = d.dev;
    sw.probe = S.driveSource(d);
    sw.stopSums();
    // a drive is not its own copy, nor written as well
    if (sw.picked[d.block]) sw.toggle(d);
  }
  function restoreAsk() { sw.writeSheet(); sw.setSourceMode("image"); sw.openAsk(); }
  function cloneAsk() { sw.writeSheet(); sw.setSourceMode("drive"); }

  // ── WRITING ────────────────────────────────────────────────────────────
  readonly property var job: sw.mgr ? sw.mgr.job : null
  readonly property bool busy: !!sw.mgr && sw.mgr.writing
  // other drives added to the write in its sheet, { block: true }
  property var picked: ({})
  function toggle(d) {
    const p = Object.assign({}, sw.picked);
    if (p[d.block]) delete p[d.block]; else p[d.block] = true;
    sw.picked = p;
  }
  readonly property var targets: sw.drive ? [sw.drive].concat(sw.drives.filter((d) => d.block !== sw.sel && d.block !== sw.srcBlock && sw.picked[d.block])) : []
  readonly property string blocked: S.blocker(sw.probe, sw.targets, sw.busy)
  property bool sheetOpen: false
  function writeSheet() {
    if (!sw.drive && !sw.job) { sw.say("Plug in a drive first", false); return; }
    if (!sw.job && sw.off("write") !== "") { sw.say(sw.off("write"), true); return; }
    if (sw.job && !sw.busy && !sw.sheetOpen) sw.mgr.clearJob();
    sw.sheetOpen = true;
  }
  function closeSheet() {
    sw.sheetOpen = false;
    if (sw.job && !sw.busy) sw.mgr.clearJob();
    sw.refocus();
  }
  function startWrite() {
    if (sw.blocked !== "") return;
    if (sw.probe && sw.probe.kind === "windows" && sw.probe.windows && sw.probe.windows.split && !sw.haveWimlib) {
      const asked = Ceres.install("wimlib", "to split a Windows install.wim", (ok) => {
        if (!ok) { sw.say("wimlib was not installed", true); return; }
        sw.haveWimlib = true;
        sw.startWrite();
      });
      if (!asked) sw.say("Ceres is busy — try again once it is done", true);
      return;
    }
    sw.mgr.write(sw.path, sw.probe, sw.targets, true);
    sw.picked = ({});
  }
  // the drive in the sidebar while a write runs: how far
  function jobCount(d) {
    if (!sw.job || !sw.job.drives.some((x) => x.block === d.block)) return "";
    if (sw.job.result) { const r = S.resultOf(sw.job.result, d.dev); return r && r.ok ? "✓" : "✕"; }
    return sw.job.phase === "write" || sw.job.phase === "verify" ? Math.floor((sw.job.frac || 0) * 100) + "%" : "…";
  }

  // ── EJECT ──────────────────────────────────────────────────────────────
  // terminus' Safely remove: its partitions unmounted, then powered off
  function eject() {
    const d = sw.drive;
    if (sw.off("eject") !== "") { sw.say(sw.off("eject"), true); return; }
    if (sw.busy || ejectProc.running) return;
    // a disk image is let go of, not powered off
    if (d.kind === "loop") {
      if (d.parts.some((q) => q.mounts.length > 0)) d.parts.forEach((q) => { if (q.mounts.length) sw.leaveMountEverywhere(q.mounts[0]); });
      sw.mgr.ask(["detach", d.dev], (j) => {
        sw.say(j && j.ok ? "Detached" : (j && j.why ? j.why : "It could not be detached"), !(j && j.ok));
        sw.refresh();
      });
      return;
    }
    ejectProc.command = ["sh", "-c", Terminus.ejectCommand(d.dev, d.parts.filter((q) => q.mounts.length > 0).map((q) => q.dev))];
    ejectProc.running = true;
  }
  Process {
    id: ejectProc
    stdout: StdioCollector { id: ejectOut; waitForEnd: true }
    stderr: StdioCollector { id: ejectErr; waitForEnd: true }
    onExited: (code) => {
      const said = (ejectOut.text.trim() || ejectErr.text.trim()).split("\n").pop();
      sw.say(code === 0 ? said : said || "It could not be ejected", code !== 0);
      sw.refresh();
    }
  }

  // ── MOUNT, UNMOUNT ─────────────────────────────────────────────────────
  // terminus' own commands (its NTFS fallbacks, its "in use by" on busy)
  // An encrypted volume: locked, Mount asks for the passphrase first (the
  // unlock sheet); mounted, Unmount locks it again after (forge lock does
  // both, as you would want a stick you are about to pull)
  function mountToggle() {
    const p = sw.vol;
    if (!p) { sw.say("Pick a volume in the sidebar", false); return; }
    if (sw.off("mount") !== "") { sw.say(sw.off("mount"), true); return; }
    if (mountProc.running || sw.asking) return;
    const on = p.mounts.length > 0;
    if (p.encrypted && !p.inner) { sw.unlockAsk(); return; }
    if (p.encrypted && on) { sw.lockVol(); return; }
    const f = S.fsPart(p);
    if (on) sw.leaveMountEverywhere(p.mounts[0]);
    mountProc.command = ["sh", "-c", on ? Terminus.unmountCommand(f.dev) : Terminus.mountCommand(f.dev, f.fstype)];
    mountProc.running = true;
  }

  // ── UNLOCK, LOCK ───────────────────────────────────────────────────────
  // the passphrase goes to forge on stdin, never as an argument, and is not
  // kept: the field is cleared the moment it is sent
  property bool unlockOpen: false
  property string unlockWhy: ""
  function unlockAsk() { sw.unlockWhy = ""; sw.unlockOpen = true; unlockBody.reset(); }
  function closeUnlock() { sw.unlockOpen = false; sw.refocus(); }
  function unlock(pass) {
    const p = sw.vol;
    if (!p || sw.asking) return;
    sw.asking = true;
    sw.mgr.ask(["unlock", p.dev], (j) => {
      sw.asking = false;
      if (!j || !j.ok) { sw.unlockWhy = j && j.why ? j.why : "It could not be unlocked"; return; }
      sw.closeUnlock();
      // then what is inside, mounted, once the list has it
      sw.refresh(() => { const v = sw.vol; if (v && v.inner && v.mounts.length === 0) sw.mountToggle(); });
    }, sw.mgr.core, pass);
  }
  function lockVol() {
    const p = sw.vol;
    if (!p || sw.asking) return;
    if (sw.off("lock") !== "") { sw.say(sw.off("lock"), true); return; }
    sw.asking = true;
    if (p.mounts.length) sw.leaveMountEverywhere(p.mounts[0]);
    sw.mgr.ask(["lock", p.dev], (j) => {
      sw.asking = false;
      sw.say(j && j.ok ? "Locked" : (j && j.why ? j.why : "It could not be locked"), !(j && j.ok));
      sw.refresh();
    });
  }

  // ── SURFACE SCAN ───────────────────────────────────────────────────────
  readonly property var scanJob: sw.mgr ? sw.mgr.scanJob : null
  function scanAsk() {
    const d = sw.drive;
    if (!d || sw.mgr.scanning) return;
    if (sw.busy && sw.job.drives.some((x) => x.block === d.block)) { sw.say("It is being written — scan it after", true); return; }
    sw.mgr.scan(d);
  }
  Process {
    id: mountProc
    stdout: StdioCollector { id: mountOut; waitForEnd: true }
    onExited: (code) => {
      const said = mountOut.text.trim().split("\n").pop() || "";
      sw.say(code === 0 ? said : Terminus.tidyDiskError(said), code !== 0);
      sw.refresh();
    }
  }

  // ── FIRST AID AND ERASE: TERMINUS' DISKTOOL, HOSTED HERE ───────────────
  // DiskTool asks its host for the disks (terminus' records, for a whole
  // drive's other partitions), to step out of a mount, to look again, to
  // say how it went, and to ask in red before an erase. These are those.
  readonly property var disks: sw.drives.reduce((a, d) => a.concat((d.parts || []).map((p) => S.asDisk(d, p))), [])
  property string status: ""
  onStatusChanged: if (sw.status !== "") { sw.say(sw.status, false); sw.status = ""; }
  function warn(t) { sw.say(t, true); }
  function pollDisks() { sw.refresh(); }
  // terminus' windows step out of it first, as its own unmount does
  function leaveMountEverywhere(mp) {
    const fm = sw.mgr ? sw.mgr.fileManager : null;
    for (const w of (fm && fm.wins) || []) { try { if (w) w.leaveMount(mp); } catch (e) {} }
  }
  property var asked: null           // { heading, detail, items, onYes }
  property int askPick: 1
  function confirmErase(heading, detail, items, onYes) {
    sw.asked = { heading: heading, detail: detail, items: items || [], onYes: onYes };
    sw.askPick = 1;
    keys.forceActiveFocus();
  }
  function answer(yes) {
    const a = sw.asked;
    sw.asked = null;
    if (yes && a && a.onYes) a.onYes();
    if (tool.open) toolClaim.restart();
    else if (sw.partOpen) partBody.forceActiveFocus();
    else sw.refocus();
  }
  QtObject {
    id: tool
    property bool open: false
    property string mode: "repair"
    property var held: null
    property var have: ({})
    property var preset: null
  }
  // `preset` opens the card already set (Reset to a normal drive)
  function diskTool(mode, preset) {
    const why = sw.off(mode === "format" ? "erase" : "repair");
    if (why !== "") { sw.say(why, true); return; }
    // the whole drive: its first volume, with the whole-drive scope chosen;
    // a drive with none, as itself
    const p = S.fsPart(sw.vol) || sw.drive.parts[0];
    tool.held = p ? S.asDisk(sw.drive, p) : S.wholeDisk(sw.drive);
    tool.preset = preset || null;
    tool.mode = mode;
    tool.open = true;
    toolScan.running = true;
    sw.resetTool();
    toolClaim.restart();
  }
  function resetTool() {
    toolBody.reset();
    if (tool.mode === "format" && !sw.vol && !tool.preset) toolBody.scope = sw.drive && sw.drive.table === "dos" ? "msdos" : "gpt";
  }
  function resetDrive() {
    if (sw.vol) sw.choose(sw.drive);
    sw.diskTool("format", S.resetPreset(sw.drive));
  }

  // ── BENCHMARK ──────────────────────────────────────────────────────────
  property bool benchOpen: false
  function benchAsk() {
    if (!sw.drive && !sw.mgr.benchJob) return;
    if (sw.mgr.benchJob && !sw.mgr.benching && sw.mgr.benchJob.drive.block !== (sw.drive ? sw.drive.block : "")) sw.mgr.clearBench();
    sw.benchOpen = true;
    Qt.callLater(() => benchBody.forceActiveFocus());
  }
  function closeBench() { sw.benchOpen = false; sw.refocus(); }

  // ── DISK IMAGES: a new one, one attached; either is chosen once it is in
  property bool imageOpen: false
  function imageAsk() { sw.imageOpen = true; imageBody.reset(); Qt.callLater(() => imageBody.forceActiveFocus()); }
  function closeImage() { sw.imageOpen = false; sw.refocus(); }
  function imageMade(dev) { sw.closeImage(); sw.say("Made and attached", false); sw.wantDrive(dev); }
  function attachAsk() {
    if (!sw.mgr.fileManager) return;
    sw.mgr.fileManager.choose(false, UserDirs.documents, (paths) => {
      if (!paths || paths.length === 0) return;
      sw.mgr.ask(["attach", paths[0]], (j) => {
        if (j && j.ok) { sw.say("Attached", false); sw.wantDrive(j.dev); }
        else sw.say(j && j.why ? j.why : "It could not be attached", true);
      });
    });
  }

  // ── BACK UP ────────────────────────────────────────────────────────────
  // a running or finished backup opens the sheet on itself
  property bool backupOpen: false
  function backupAsk() {
    if (!sw.drive && !sw.mgr.backupJob) return;
    sw.backupOpen = true;
    if (!sw.mgr.backupJob) backupBody.reset();
    Qt.callLater(() => backupBody.forceActiveFocus());
  }
  function closeBackup() {
    sw.backupOpen = false;
    if (sw.mgr.backupJob && !sw.mgr.backingUp) sw.mgr.clearBackup();
    sw.refocus();
  }

  // ── PARTITION ──────────────────────────────────────────────────────────
  property bool partOpen: false
  function partitionAsk() {
    const why = sw.off("partition");
    if (why !== "") { sw.say(why, true); return; }
    if (sw.busy) { sw.say("A write is running — wait for it or stop it", true); return; }
    sw.partOpen = true;
    partBody.reset(sw.vol ? sw.vol.dev : "");
    Qt.callLater(() => partBody.forceActiveFocus());
  }
  function closePartition() { sw.partOpen = false; sw.refocus(); }

  // ── RENAME ─────────────────────────────────────────────────────────────
  property bool renameOpen: false
  function renameAsk() {
    const why = sw.off("rename");
    if (why !== "") { sw.say(why, true); return; }
    sw.renameOpen = true;
    renameBody.reset();
  }
  function closeRename() { sw.renameOpen = false; sw.refocus(); }
  function rename(label, name) {
    const args = ["rename", sw.vol.dev].concat(label !== null ? ["--label", label] : []).concat(name !== null ? ["--name", name] : []);
    sw.mgr.ask(args, (j) => {
      if (j && j.ok) { sw.say("Renamed", false); sw.closeRename(); }
      else sw.say(j && j.why ? j.why : "It could not be renamed", true);
      sw.refresh();
    });
  }
  function closeTool() {
    if (toolBody.running) return;
    tool.open = false;
    sw.refocus();
  }
  Process {
    id: toolScan
    command: ["sh", "-c", Terminus.fsToolsCommand()]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { tool.have = Terminus.parseFsTools(text); sw.resetTool(); }
    }
  }
  // the card takes the keys once it is there (terminus' diskToolClaim)
  Timer {
    id: toolClaim
    interval: 40
    repeat: true
    property int tries: 0
    onRunningChanged: if (running) tries = 0
    onTriggered: {
      if (!tool.open || sw.asked || toolBody.activeFocus || tries++ > 12) { stop(); return; }
      toolBody.forceActiveFocus();
    }
  }

  function refocus() { Qt.callLater(() => keys.forceActiveFocus()); }

  // ── WHAT WAS JUST DONE, SAID ONCE ─────────────────────────────────────
  function say(t, bad) { saidBox.say(t, bad); }

  // ── MENUS ──────────────────────────────────────────────────────────────
  function moreMenu() {
    const p = moreBtn.mapToItem(menu, 0, moreBtn.height + 4);
    menu.open(p.x, p.y, [
      { text: "Open an image…", icon: "\u{F0770}", mark: "ctrl o", enabled: !sw.busy && sw.off("write") === "", run: () => sw.openAsk() },
      { text: "Download a Linux…", icon: "\u{F01DA}", run: () => sw.downloadAsk() },
      { isSeparator: true },
      { text: "New disk image…", icon: "\u{F104B}", run: () => sw.imageAsk() },
      { text: "Attach a disk image…", icon: "\u{F05EE}", run: () => sw.attachAsk() },
      sw.vol ? { text: "Rename…", icon: "\u{F0455}", mark: "f2", enabled: sw.off("rename") === "", run: () => sw.renameAsk() }
             : { text: "Reset to a normal drive…", icon: "\u{F099B}", enabled: !sw.busy && !!sw.drive && sw.off("erase") === "" && sw.off("write") === "",
                 run: () => sw.resetDrive() },
      { isSeparator: true },
      { text: "Look again", icon: "\u{F0450}", run: () => sw.refresh() }
    ], moreBtn);
  }
  // a drive's or a volume's own menu: what the toolbar does, there
  function rowMenu(d, partDev, item, x, y) {
    sw.choose(d, partDev);
    const v = S.partOf(d, partDev);
    const pt = item.mapToItem(menu, x, y);
    const items = [];
    if (!v) items.push({ text: "Write an image…", icon: "\u{F0D13}", mark: "w", enabled: !sw.busy && sw.off("write") === "", run: () => sw.writeSheet() });
    if (!v) items.push({ text: "Restore from a backup…", icon: "\u{F099B}", enabled: !sw.busy && sw.off("write") === "", run: () => sw.restoreAsk() });
    if (!v) items.push({ text: "Copy another drive onto it…", icon: "\u{F018F}", enabled: !sw.busy && sw.off("write") === "", run: () => sw.cloneAsk() });
    items.push({ text: "Back up to an image…", icon: "\u{F006F}", mark: "b", enabled: !sw.mgr.backingUp, run: () => sw.backupAsk() });
    if (v) items.push({ text: v.encrypted && !v.inner ? "Unlock…" : v.mounts.length ? (v.encrypted ? "Unmount and lock" : "Unmount") : "Mount",
                        icon: v.encrypted && !v.inner ? "\u{F033E}" : v.mounts.length ? "\uF052" : "\uF0AB", mark: "m",
                        enabled: sw.off("mount") === "", run: () => sw.mountToggle() });
    if (v && v.encrypted && v.inner && !v.mounts.length)
      items.push({ text: "Lock", icon: "\u{F033E}", enabled: sw.off("lock") === "", run: () => sw.lockVol() });
    if (v) items.push({ text: "Rename…", icon: "\u{F0455}", mark: "f2", enabled: sw.off("rename") === "", run: () => sw.renameAsk() });
    if (v) items.push({ text: "First Aid…", icon: "\uF0AD", enabled: sw.off("repair") === "", run: () => sw.diskTool("repair") });
    items.push({ text: "Partition…", icon: "\u{F012B}", mark: "p", enabled: !sw.busy && sw.off("partition") === "", run: () => sw.partitionAsk() });
    items.push({ text: "Erase…", icon: "\uF1C0", enabled: !sw.busy && sw.off("erase") === "", run: () => sw.diskTool("format") });
    if (!v) items.push({ text: "Reset to a normal drive…", icon: "\u{F099B}", enabled: !sw.busy && sw.off("erase") === "" && sw.off("write") === "",
                         run: () => sw.resetDrive() });
    if (!v) items.push({ text: "Benchmark…", icon: "\u{F04C5}", enabled: !sw.mgr.benching, run: () => sw.benchAsk() });
    if (!v) items.push({ text: d.kind === "loop" ? "Detach" : "Eject", icon: "\u{F01EA}", mark: "ctrl e", enabled: !sw.busy && sw.off("eject") === "", run: () => sw.eject() });
    items.push({ isSeparator: true });
    if (v && v.mounts.length) items.push({ text: "Open in Terminus", icon: "\u{F0DCF}", enabled: !!sw.mgr.fileManager,
                                           run: () => sw.mgr.fileManager.reveal(v.mounts[0]) });
    const dev = v ? v.dev : d.dev;
    items.push({ text: "Copy device path", icon: "\u{F018F}", run: () => { Quickshell.clipboardText = dev; sw.say("Copied " + dev, false); } });
    menu.open(pt.x, pt.y, items);
  }


  // ── KEYS ───────────────────────────────────────────────────────────────
  Item {
    id: keys
    focus: true
    Keys.onPressed: (e) => {
      const ctrl = e.modifiers & Qt.ControlModifier;
      const k = e.key;
      e.accepted = true;
      if (sw.asked) {
        if (k === Qt.Key_Escape) sw.answer(false);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) sw.answer(sw.askPick === 0);
        else if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Tab) sw.askPick = 1 - sw.askPick;
        return;
      }
      if (sw.renameOpen || sw.unlockOpen || sw.partOpen || sw.backupOpen || sw.downloadOpen || sw.benchOpen || sw.imageOpen) { e.accepted = false; return; }
      if (sw.sheetOpen) {
        if (k === Qt.Key_Escape) sw.closeSheet();
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && !sw.job) sw.startWrite();
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && sw.job && sw.job.result) sw.closeSheet();
        else if (ctrl && k === Qt.Key_O) sw.openAsk();
        else e.accepted = false;
        return;
      }
      if (k === Qt.Key_Escape) { sw.visible = false; return; }
      if (ctrl && k === Qt.Key_O) { sw.openAsk(); return; }
      if (ctrl && k === Qt.Key_B) { sw.setSidebar(!sw.sideOpen); return; }
      if (ctrl && k === Qt.Key_E) { sw.eject(); return; }
      if (k === Qt.Key_W && !ctrl) { sw.writeSheet(); return; }
      if (k === Qt.Key_M && !ctrl) { sw.mountToggle(); return; }
      if (k === Qt.Key_F2) { sw.renameAsk(); return; }
      if (k === Qt.Key_P && !ctrl) { sw.partitionAsk(); return; }
      if (k === Qt.Key_B && !ctrl) { sw.backupAsk(); return; }
      if (k === Qt.Key_Down) { sw.move(1); return; }
      if (k === Qt.Key_Up) { sw.move(-1); return; }
      e.accepted = false;
    }
  }

  // ── DROPPED FILES ──────────────────────────────────────────────────────
  property bool dropOver: false
  DropArea {
    anchors.fill: parent
    keys: ["text/uri-list"]
    onEntered: sw.dropOver = !sw.busy
    onExited: sw.dropOver = false
    onDropped: (d) => {
      sw.dropOver = false;
      const paths = (d.urls || []).map((u) => decodeURIComponent(String(u).replace(/^file:\/\//, "")));
      if (paths.length > 0) sw.load(paths[0]);
    }
  }

  // ── THE SIDEBAR MAKES ROOM FOR ITSELF ──────────────────────────────────
  SideRoom {
    id: room
    window: sw
    anchor: keys
    shown: sw.sideOpen
    want: sw.sideW
    box: sideBox
    edge: "left"
  }

  // ── THE STAGE ──────────────────────────────────────────────────────────
  Item {
    id: stage
    anchors.fill: parent

    // the window's ground, beside the sidebar
    Rectangle { z: -1; x: sideBox.width; width: parent.width - x; height: parent.height; color: Zenon.layerBg }

    // ── the drives ───────────────────────────────────────────────────────
    // THE WINDOW'S WHOLE HEIGHT, as terminus' and plato's: the head and the
    // hint bar end at it
    Item {
      id: sideBox
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      // while Hyprland resizes the window for it, the sidebar is whatever
      // the window has gained (SideRoom); otherwise it slides on its own
      width: room.keepW >= 0 ? Math.max(0, Math.min(sw.sideW, sw.width - room.keepW)) : sw.sideOpen ? sw.sideW : 0
      visible: width > 0
      Behavior on width {
        enabled: !room.following
        NumberAnimation { duration: Math.round(Zenon.normal * 1.4); easing.type: Zenon.travelEase }
      }
      clip: true
      z: 2
      // the suite's sidebar glass, straight on the window's blur
      SideGlass { edge: "right" }

      Flickable {
        id: sideList
        x: sideBox.width - sw.sideW
        // from the top: the head stands beside the sidebar, not over it
        y: 8
        width: sw.sideW
        height: parent.height - 8
        clip: true
        contentWidth: width
        contentHeight: sideCol.implicitHeight + 16
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: sideCol
          x: 8
          width: parent.width - 16
          Repeater {
            model: S.sections(sw.drives)
            Column {
              id: sect
              required property var modelData
              required property int index
              width: sideCol.width
              SideHead { first: sect.index === 0; ruled: false; label: sect.modelData.label; width: parent.width }
              Repeater {
                model: sect.modelData.drives
                Column {
                  id: driveRows
                  required property var modelData
                  width: sect.width
                  ShelfRow {
                    id: driveRow
                    width: parent.width
                    glyph: S.driveGlyph(driveRows.modelData)
                    // a worn or failing drive says so in its glyph, whether or
                    // not it is the one chosen
                    readonly property var verdict: sw.verdictOf(driveRows.modelData)
                    glyphInk: verdict && verdict.level === "bad" ? Zenon.red : verdict && verdict.level === "warn" ? Zenon.yellow
                      : sw.sel === driveRows.modelData.block ? Zenon.cyan : "transparent"
                    label: S.driveTitle(driveRows.modelData)
                    count: sw.jobCount(driveRows.modelData) || Terminus.formatSize(driveRows.modelData.size)
                    countInk: sw.jobCount(driveRows.modelData) !== "" ? Zenon.cyan : Zenon.accentMuted
                    here: sw.sel === driveRows.modelData.block && sw.part === ""
                    onClicked: { sw.choose(driveRows.modelData); sw.refocus(); }
                    TapHandler {
                      acceptedButtons: Qt.RightButton
                      onTapped: (pt) => sw.rowMenu(driveRows.modelData, "", driveRow, pt.position.x, pt.position.y)
                    }
                  }
                  // its partitions, under it: picking one rings it in the map
                  Repeater {
                    model: driveRows.modelData.parts
                    ShelfRow {
                      id: partRow
                      required property var modelData
                      width: driveRows.width
                      indent: 34
                      // its color in the map, as the key's rounded square
                      // (md-square_rounded; user, 2026-10-24)
                      glyph: "\u{F14FB}"
                      glyphInk: Zenon[S.partInk(driveRows.modelData, modelData.dev)] || Zenon.muted
                      label: S.partName(modelData)
                      count: Terminus.formatSize(modelData.size)
                      // an unmounted volume reads fainter, as Disk Utility greys one
                      countInk: modelData.mounts.length ? Zenon.accentMuted : Zenon.muted
                      here: sw.part === modelData.dev
                      onClicked: { sw.choose(driveRows.modelData, modelData.dev); sw.refocus(); }
                      TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: (pt) => sw.rowMenu(driveRows.modelData, partRow.modelData.dev, partRow, pt.position.x, pt.position.y)
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      ElasticScroll { anchors.fill: sideList; view: sideList }
      Scrollbar { flick: sideList; anchors.right: parent.right; anchors.top: sideList.top; anchors.bottom: sideList.bottom }
    }

    // ── the head ─────────────────────────────────────────────────────────
    Item {
      id: head
      z: 3
      anchors.left: sideBox.right
      anchors.right: parent.right
      height: sw.headH
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
      DialogButton {
        id: sideBtn
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: 30
        glyph: true
        // the sidebar shown or not, minerva's glyphs for the left side
        label: sw.sideOpen ? "\u{EC02}" : "\u{EBF3}"
        ink: sw.sideOpen ? Zenon.cyan : Zenon.muted
        onClicked: sw.setSidebar(!sw.sideOpen)
        HoverHandler { onHoveredChanged: hovered ? tip.show(sideBtn, "Sidebar") : tip.hide(sideBtn) }
      }
      Text {
        id: brand
        anchors.left: sideBtn.right
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: "Stylus"
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(16)
      }
      // beside the name: the drives, the write as it goes, or how it went
      Text {
          anchors.left: brand.right
          anchors.leftMargin: 10
          anchors.right: tools.left
          anchors.rightMargin: 14
          anchors.baseline: brand.baseline
          elide: Text.ElideRight
          text: S.headWords(sw.job, sw.drives)
          color: sw.job && sw.job.result && !sw.job.result.ok ? Zenon.red : Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
      }
      // what can be done to the drive chosen; Back up, Clone and Reset
      // join Write here as they are built
      Row {
        id: tools
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        // each says why when it is off (the system disk's, mostly)
        Repeater {
          model: [
            { id: "repair", glyph: "\uF0AD", tip: "First Aid", run: () => sw.diskTool("repair") },
            { id: "partition", glyph: "\u{F012B}", tip: "Partition", run: () => sw.partitionAsk() },
            { id: "erase", glyph: "\uF1C0", tip: "Erase", run: () => sw.diskTool("format") },
            { id: "backup", glyph: "\u{F006F}", tip: sw.mgr && sw.mgr.backingUp ? "Backing up" : "Back up", run: () => sw.backupAsk() },
            { id: "write", glyph: "\u{F0D13}", tip: sw.busy ? "Writing" : "Write an image, or copy a drive", run: () => sw.writeSheet() },
            sw.vol ? { id: "mount", glyph: sw.vol.encrypted && !sw.vol.inner ? "\u{F033E}" : sw.vol.mounts.length ? "\uF052" : "\uF0AB",
                       tip: sw.vol.encrypted && !sw.vol.inner ? "Unlock" : sw.vol.mounts.length ? (sw.vol.encrypted ? "Unmount and lock" : "Unmount") : "Mount",
                       run: () => sw.mountToggle() }
                   : { id: "eject", glyph: "\u{F01EA}", tip: sw.drive && sw.drive.kind === "loop" ? "Detach" : "Eject", run: () => sw.eject() }
          ]
          DialogButton {
            id: toolBtn
            required property var modelData
            readonly property string why: modelData.id === "write" && sw.job ? "" : modelData.id === "backup" ? "" : sw.off(modelData.id)
            implicitHeight: 30
            glyph: true
            label: modelData.glyph
            ink: modelData.id === "write" && sw.busy ? Zenon.cyan : Zenon.accentMuted
            ready: toolBtn.why === "" && !(sw.busy && modelData.id !== "write" && modelData.id !== "mount")
            held: modelData.id === "write" ? sw.sheetOpen : modelData.id === "partition" ? sw.partOpen : modelData.id === "backup" ? sw.backupOpen : (modelData.id === "repair" || modelData.id === "erase") && tool.open && (tool.mode === "format") === (modelData.id === "erase")
            onClicked: modelData.run()
            HoverHandler { onHoveredChanged: hovered ? tip.show(toolBtn, toolBtn.why !== "" ? modelData.tip + " — " + toolBtn.why : modelData.tip) : tip.hide(toolBtn) }
          }
        }
        DialogButton {
          id: moreBtn
          implicitHeight: 30
          glyph: true
          label: "\u{F01D8}"
          held: menu.isOpen && menu.held === moreBtn
          onClicked: sw.moreMenu()
          HoverHandler { onHoveredChanged: hovered ? tip.show(moreBtn, "More") : tip.hide(moreBtn) }
        }
      }
    }

    // ── the drive or volume chosen ───────────────────────────────────────
    Flickable {
      id: pane
      anchors.left: sideBox.right
      anchors.right: parent.right
      anchors.top: head.bottom
      anchors.bottom: foot.top
      clip: true
      contentWidth: width
      contentHeight: paneCol.implicitHeight + 64
      boundsBehavior: Flickable.StopAtBounds
      visible: !!sw.drive
      Column {
        id: paneCol
        x: 32
        y: 32
        width: Math.min(pane.width - 64, 820)
        spacing: 26

        Row {
          width: parent.width
          spacing: 18
          Text {
            anchors.verticalCenter: parent.verticalCenter
            // a volume wears the drive's glyph, quieter
            text: S.driveGlyph(sw.drive)
            color: sw.vol ? Zenon.accentMuted : Zenon.cyan
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(48)
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
              text: sw.vol ? S.partName(sw.vol) : S.driveTitle(sw.drive)
              color: Zenon.ink
              font.family: Zenon.face
              font.weight: Zenon.titleWeight
              font.pixelSize: Zenon.px(22)
            }
            Text {
              text: sw.vol ? S.volumeLine(sw.vol) : S.detailLine(sw.drive)
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
          }
        }

        // a write to this drive with its sheet put away: the row, and a
        // tap brings the sheet back
        StylusDrive {
          visible: !sw.vol && !!sw.job && !sw.sheetOpen && !!sw.drive && sw.job.drives.some((d) => d.block === sw.drive.block)
          drive: sw.drive
          job: sw.job
          TapHandler { onTapped: sw.writeSheet() }
        }

        // a drive: where its partitions lie
        StylusMap { visible: !sw.vol; width: parent.width; drive: sw.drive; hot: sw.part }

        // a volume: what is taking up its room, by kind
        Column {
          visible: !!sw.vol
          width: parent.width
          spacing: 12
          UsageScan {
            id: use
            visible: false
            mount: sw.vol && sw.vol.mounts.length ? sw.vol.mounts[0] : ""
            active: !!sw.vol
          }
          UsageBar {
            visible: use.mount !== "" && use.error === ""
            width: parent.width
            height: 26
            segments: use.segments
          }
          Item {
            visible: use.mount !== "" && use.error === ""
            width: parent.width
            height: freeText.implicitHeight
            Text {
              id: freeText
              text: U.freeWords(use.df)
              color: Zenon.ink
              font.family: Zenon.face
              font.weight: Zenon.titleWeight
              font.pixelSize: Zenon.px(13)
            }
            Text {
              anchors.right: parent.right
              anchors.baseline: freeText.baseline
              text: use.words + (use.scanning || use.words === "" ? "" : "  \u00b7  sort again")
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
              TapHandler { enabled: !use.scanning; onTapped: use.rescan() }
            }
          }
          UsageLegend { visible: use.mount !== "" && use.error === ""; width: parent.width; items: use.legend }
          Text {
            visible: use.mount === "" || use.error !== ""
            text: use.error !== "" ? use.error
              : sw.vol && sw.vol.encrypted && !sw.vol.inner ? "Locked — unlock it to see what is on it"
              : sw.vol && sw.vol.fstype ? "Not mounted — mount it to see what is on it" : "No filesystem on it"
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
        }

        // a drive: how it is, by its own SMART, and its self-test
        HermesCard {
          id: healthCard
          readonly property var h: sw.healthOf(sw.drive)
          readonly property var verdict: sw.verdictOf(sw.drive)
          readonly property var test: Health.selftestOf(healthCard.h)
          // the surface scan, this drive's if it is the one scanned
          readonly property bool scanHere: !!sw.scanJob && !!sw.drive && sw.scanJob.drive.block === sw.drive.block
          readonly property bool scanRuns: healthCard.scanHere && !sw.scanJob.result
          readonly property var scan: S.scanWords(sw.scanJob, sw.drive)
          // every drive: one that keeps no SMART can still be read end to end
          visible: !sw.vol && !!sw.drive && sw.drive.kind !== "loop"
          glyph: "\u{F05F6}"
          glyphInk: !healthCard.verdict ? Zenon.cyan : healthCard.verdict.level === "bad" ? Zenon.red
            : healthCard.verdict.level === "warn" ? Zenon.yellow : Zenon.green
          title: "Health"
          note: healthCard.verdict ? healthCard.verdict.words : "It keeps no SMART data"
          trailing: [
            DialogButton {
              visible: !!healthCard.verdict && !healthCard.test.running
              implicitHeight: 28
              label: "Quick test"
              ready: !sw.asking
              onClicked: sw.selftest("short")
            },
            DialogButton {
              visible: !!healthCard.verdict && !healthCard.test.running
              implicitHeight: 28
              label: "Full test"
              ready: !sw.asking
              onClicked: sw.selftest("extended")
            },
            DialogButton {
              visible: healthCard.test.running
              implicitHeight: 28
              label: "Stop test"
              ink: Zenon.red
              ready: !sw.asking
              onClicked: sw.selftest("abort")
            },
            DialogButton {
              implicitHeight: 28
              label: healthCard.scanRuns ? "Stop scan" : "Surface scan"
              ink: healthCard.scanRuns ? Zenon.red : Zenon.accentMuted
              // one scan at a time, whichever drive
              ready: healthCard.scanRuns || !(sw.mgr && sw.mgr.scanning)
              onClicked: healthCard.scanRuns ? sw.mgr.stopScan() : sw.scanAsk()
            }
          ]
          Repeater {
            model: healthCard.h ? Health.diskHealthFacts(healthCard.h).filter((r) => r[0] !== "Health") : []
            HermesFact {
              required property var modelData
              label: modelData[0]
              value: modelData[1]
            }
          }
          HermesFact { visible: !!healthCard.verdict; label: "Self-test"; value: healthCard.test.words }
          // the running test's own fill, under its words
          Item {
            visible: healthCard.test.running && healthCard.test.left >= 0
            width: parent.width
            height: 18
            Rectangle {
              id: testBand
              x: 18
              width: parent.width - 36
              height: 6
              radius: Zenon.rad(3)
              color: Zenon.wash(0.06)
              ProgressFill { anchors.fill: parent; radius: testBand.radius; frac: (100 - healthCard.test.left) / 100 }
            }
          }
          HermesFact { label: "Surface scan"; value: healthCard.scan.words }
          Item {
            visible: healthCard.scanRuns
            width: parent.width
            height: 18
            Rectangle {
              id: scanBand
              x: 18
              width: parent.width - 36
              height: 6
              radius: Zenon.rad(3)
              color: Zenon.wash(0.06)
              ProgressFill { anchors.fill: parent; radius: scanBand.radius; frac: S.phaseFrac(sw.scanJob) }
            }
          }
        }

        HermesCard {
          glyph: "\u{F02FD}"
          title: "Information"
          Repeater {
            model: sw.vol ? S.volumeFacts(sw.drive, sw.vol, use.df) : S.facts(sw.drive)
            HermesFact {
              required property var modelData
              label: modelData[0]
              value: modelData[1]
            }
          }
        }
      }
    }
    ElasticScroll { anchors.fill: pane; view: pane }
    // up under the head, down under the hints, frosted, as hestia's pages
    // (morpheus/ScrollEdge, under the bars: their z is above)
    ScrollEdge { view: pane; follow: true; chromeTop: 0 }
    ScrollEdge { view: pane; below: true; follow: true; bar: foot }
    Scrollbar { flick: pane; anchors.right: parent.right; anchors.top: pane.top; anchors.bottom: pane.bottom }

    EmptyState {
      anchors.centerIn: pane
      visible: !sw.drive
      text: "No drives"
    }

    Ctl.Said {
      anchors.horizontalCenter: pane.horizontalCenter
      anchors.bottom: foot.top
      anchors.bottomMargin: 18
      z: 5
      maxWidth: 560
      id: saidBox
      lasts: 3200
    }

    HintBar {
      id: foot
      z: 3
      anchors.bottom: parent.bottom
      anchors.left: sideBox.right
      anchors.right: parent.right
      rows: sw.asked ? [["return", "answer"], ["←→", "choose"], ["esc", "cancel"]]
        : sw.partOpen ? [["↑↓", "partition or free space"], ["esc", "done"]]
        : sw.backupOpen ? [["return", "back up"], ["esc", "close"]]
        : sw.downloadOpen ? [["↑↓", "distribution"], ["return", "download"], ["esc", "close"]]
        : sw.benchOpen ? [["return", "start"], ["esc", "close"]]
        : sw.imageOpen ? [["esc", "cancel"]]
        : sw.renameOpen ? [["return", "rename"], ["esc", "cancel"]]
        : sw.unlockOpen ? [["return", "unlock"], ["esc", "cancel"]]
        : tool.open ? [["return", tool.mode === "format" ? "erase" : "check"], ["esc", "close"]]
        : sw.sheetOpen ? (sw.job ? [["esc", sw.busy ? "hide" : "close"]] : [["return", "write"], ["ctrl o", "open"], ["esc", "cancel"]])
        : sw.vol ? [["↑↓", "drive"]].concat(sw.off("mount") === "" ? [["m", sw.vol.encrypted && !sw.vol.inner ? "unlock" : sw.vol.mounts.length ? "unmount" : "mount"]] : [])
            .concat(sw.off("rename") === "" ? [["f2", "rename"]] : [])
            .concat([["ctrl b", "sidebar"], ["esc", "close"]])
        : [["↑↓", "drive"], ["w", "write"]].concat(sw.off("partition") === "" ? [["p", "partition"]] : [])
            .concat([["ctrl e", "eject"], ["ctrl b", "sidebar"], ["esc", "close"]])
    }
  }

  // ── THE WRITE SHEET ────────────────────────────────────────────────────
  InputShield { visible: sw.sheetOpen && !sw.busy; onClicked: sw.closeSheet() }
  Sheet {
    shown: sw.sheetOpen
    fromTop: head.height
    leftInset: sideBox.width
    cardW: 600
    cardH: writeBody.implicitHeight
    StylusWrite { id: writeBody; width: parent.width; win: sw }
  }

  // ── FIRST AID AND ERASE ────────────────────────────────────────────────
  InputShield { visible: tool.open && !sw.asked; onClicked: sw.closeTool() }
  Sheet {
    shown: tool.open
    fromTop: head.height
    leftInset: sideBox.width
    cardW: tool.mode === "format" ? 680 : 600
    cardH: toolBody.implicitHeight
    DiskTool {
      id: toolBody
      width: parent.width
      height: parent.height
      host: sw
      disk: tool.held
      mode: tool.mode
      have: tool.have
      preset: tool.preset
      // hung from the head like stylus' other sheets, named inside
      heading: (tool.mode === "format" ? (tool.preset ? "Reset " : "Erase ") : "First Aid on ")
        + (tool.preset ? S.driveTitle(sw.drive) : toolBody.title !== "" ? toolBody.title : "the disk")
      pad: 24
      onClosed: sw.closeTool()
    }
  }

  // ── UNLOCK ─────────────────────────────────────────────────────────────
  InputShield { visible: sw.unlockOpen; onClicked: sw.closeUnlock() }
  Sheet {
    shown: sw.unlockOpen
    fromTop: head.height
    leftInset: sideBox.width
    cardW: 520
    cardH: unlockBody.implicitHeight
    StylusUnlock { id: unlockBody; width: parent.width; win: sw }
  }

  // ── RENAME ─────────────────────────────────────────────────────────────
  InputShield { visible: sw.renameOpen; onClicked: sw.closeRename() }
  Sheet {
    shown: sw.renameOpen
    fromTop: head.height
    leftInset: sideBox.width
    cardW: 600
    cardH: renameBody.implicitHeight
    StylusRename { id: renameBody; width: parent.width; win: sw }
  }

  // ── BENCHMARK, A NEW DISK IMAGE ────────────────────────────────────────
  InputShield { visible: sw.benchOpen; onClicked: sw.closeBench() }
  Sheet {
    shown: sw.benchOpen
    fromTop: head.height
    leftInset: sideBox.width
    cardW: 600
    cardH: benchBody.implicitHeight
    StylusBench { id: benchBody; width: parent.width; win: sw }
  }
  InputShield { visible: sw.imageOpen; onClicked: if (!imageBody.working) sw.closeImage() }
  Sheet {
    shown: sw.imageOpen
    fromTop: head.height
    leftInset: sideBox.width
    cardW: 640
    cardH: imageBody.implicitHeight
    StylusImage { id: imageBody; width: parent.width; win: sw }
  }

  // ── A DOWNLOAD ─────────────────────────────────────────────────────────
  InputShield { visible: sw.downloadOpen; onClicked: sw.closeDownload() }
  Sheet {
    shown: sw.downloadOpen
    fromTop: head.height
    leftInset: sideBox.width
    cardW: 600
    cardH: downloadBody.implicitHeight
    StylusDownload { id: downloadBody; width: parent.width; win: sw }
  }

  // ── BACK UP ────────────────────────────────────────────────────────────
  InputShield { visible: sw.backupOpen; onClicked: sw.closeBackup() }
  Sheet {
    shown: sw.backupOpen
    fromTop: head.height
    leftInset: sideBox.width
    cardW: 600
    cardH: backupBody.implicitHeight
    StylusBackup { id: backupBody; width: parent.width; win: sw }
  }

  // ── PARTITION ──────────────────────────────────────────────────────────
  InputShield { visible: sw.partOpen && !sw.asked; onClicked: if (!partBody.working) sw.closePartition() }
  Sheet {
    shown: sw.partOpen
    fromTop: head.height
    leftInset: sideBox.width
    cardW: 680
    cardH: partBody.implicitHeight
    StylusPartition { id: partBody; width: parent.width; win: sw }
  }

  // ── ASKING FIRST, IN RED: DiskTool's erase, a partition's delete ──────
  InputShield { visible: !!sw.asked; onClicked: sw.answer(false) }
  Sheet {
    shown: !!sw.asked
    fromTop: head.height
    leftInset: sideBox.width
    cardW: 540
    cardH: askBody.implicitHeight
    ConfirmBody {
      id: askBody
      width: parent.width
      question: sw.asked ? sw.asked.heading : ""
      glyph: "\u{F0028}"
      glyphInk: Zenon.red
      detail: sw.asked ? sw.asked.detail : ""
      items: sw.asked ? sw.asked.items : []
      choices: [{ label: "Erase", ink: Zenon.red }, { label: "Cancel", ink: Zenon.accentMuted }]
      pick: sw.askPick
      onPicked: (i) => sw.askPick = i
      onChose: (i) => sw.answer(i === 0)
    }
  }

  PopMenu { id: menu; anchors.fill: parent; window: sw; onClosed: sw.refocus() }
  WindowTip { id: tip; window: sw }
}
