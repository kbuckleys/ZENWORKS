// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' undo … logic, out of TerminusWindow.qml
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
  id: fileOps
  property var term: null
  readonly property alias rescanTick: rescanTick
  readonly property alias trashSizeLater: trashSizeLater
  readonly property alias trashSizeProc: trashSizeProc

  Timer {
    id: undoOfferEnd
    interval: 6000
    onTriggered: term.undoOffer = false
  }
  function pushUndo(entry) {
    term.undoOffer = true;
    undoOfferEnd.restart();
    const next = term.undoStack.slice();
    next.push(entry);
    // deep enough to cover a session's worth of slips, shallow enough that it
    // never becomes a second filesystem held in memory
    while (next.length > 20) next.shift();
    term.undoStack = next;
  }
  function undo() {
    term.undoOffer = false;
    if (term.undoStack.length === 0) { term.warn("nothing to undo"); return; }
    const next = term.undoStack.slice();
    const e = next.pop();
    term.undoStack = next;

    if (e.kind === "trash") {
      // by ORIGINAL PATH, not by the name in the trash: gio appends a suffix
      // when the name is already taken there, so the two are not the same
      // string and only the path is something we actually know.
      term.run(Terminus.restoreCommand(e.paths, "path"));
      term.status = "restored " + e.paths.length;
      return;
    }
    if (e.kind === "move") {
      let cmd = "";
      for (let i = 0; i < e.pairs.length; ++i) {
        const from = e.pairs[i][1], to = e.pairs[i][0];
        cmd += "mkdir -p -- " + Strings.shellQuote(Terminus.dirname(to))
          + " && mv -n -- " + Strings.shellQuote(from) + " "
          + Strings.shellQuote(to) + "\n";
      }
      term.run(cmd);
      term.status = "moved back " + e.pairs.length;
      return;
    }
    term.run(Terminus.renameCommand(e.to, Terminus.basename(e.from)));
    term.status = "rename undone";
  }
  Process {
    id: trashSizeProc
    command: ["sh", "-c", Terminus.trashSizeCommand()]
    stdout: StdioCollector {
      id: trashSizeOut
      waitForEnd: true
      onStreamFinished: term.trashSize = String(trashSizeOut.text || "").trim()
    }
  }
  Timer {
    id: trashSizeLater
    interval: 400
    onTriggered: if ((term.sidebar || term.inTrash) && !trashSizeProc.running) trashSizeProc.running = true
  }
  // Files dropped on the trash row: trashed, as `d` would, asking first if
  // you have it ask. What is already in the trash stays where it is.
  function trashDropped(urls) {
    const inside = Terminus.trashRoot() + "/";
    const paths = term.localPaths(urls).filter((p) => !p.startsWith(inside));
    if (paths.length === 0) return;
    term.askTrash(paths.map((p) => ({ path: p, name: Terminus.basename(p) })));
  }
  function emptyTrash() {
    term.confirmRef.ask("Empty the trash?",
      term.trashSize !== "" ? term.trashSize + " will be deleted for good"
                            : "Everything in it is deleted for good",
      "Delete", () => {
        term.run(Terminus.emptyTrashCommand());
        term.act.marked = {};
        term.status = "trash emptied";
      });
  }
  function restoreSelected() {
    const rows = term.acting();
    if (rows.length === 0) return;
    term.run(Terminus.restoreCommand(rows.map((r) => r.name), "name"));
    term.act.marked = {};
    term.status = "restoring " + rows.length;
  }
  function extractSelected() {
    const rows = term.acting().filter((r) => !r.isDir && Terminus.isArchive(r.name));
    if (rows.length === 0) { term.warn("not an archive"); return; }
    // ONE JOB PER ARCHIVE, handed to the queue that already serialises work.
    // A single script over all of them could only report one count across
    // archives of wildly different sizes, and the panel would step backwards
    // every time it reached the next one.
    // Beside the archive, not in cwd — see homeOf. An archive opened in a
    // branch extracts into that branch.
    for (const r of rows)
      term.startJob("extract", [r.path], Terminus.dirname(r.path), "");
    term.act.marked = {};
  }
  // THE NAME IS NOT ASKED FOR ANY MORE.
  //
  // It was a prompt with the answer already typed into it, and the answer was
  // accepted as-is nearly every time — a dialog charging a keystroke for the
  // privilege of agreeing with it. The suggestion IS the name now: a directory
  // archives under its own name, and a handful of loose files archive under
  // the name of the directory they were sitting in, which is the only name
  // they have in common.
  //
  // What made the prompt worth its keystroke was the chance to notice you were
  // about to write over an archive that was already there. That question has
  // not gone away — it is just only asked when it is a real question, and it
  // is asked in the words a paste already uses.
  function beginArchive(ext) {
    const rows = term.acting();
    if (rows.length === 0) return;
    // ONE DIRECTORY AT A TIME. The archive is made from inside the first row's
    // directory with the others named relative to it, so a selection spanning
    // expanded branches silently left out everything that was not beside
    // the first — the archive looked fine and was missing files.
    const from = Terminus.dirname(rows[0].path);
    if (rows.some((r) => Terminus.dirname(r.path) !== from)) {
      term.warn("archive what is in one directory at a time");
      return;
    }
    const e = (ext && ext !== "") ? ext : ".tar.zst";
    const name = (rows.length === 1 ? Terminus.stem(rows[0].name)
                                    : Terminus.basename(term.cwd)) + e;
    term.archivePending = { paths: rows.map((r) => r.path), name: name };
    archiveClashProc.command = ["sh", "-c",
      Terminus.archiveTargetCommand(term.cwd, name, e)];
    archiveClashProc.running = true;
  }
  // Nothing is written until that answer is in — bsdtar and 7z overwrite in
  // silence, exactly as cp and mv do, so the scan is the whole difference
  // between archiving and losing the archive that was already there.
  Process {
    id: archiveClashProc
    stdout: StdioCollector {
      id: archiveClashOut
      waitForEnd: true
      onStreamFinished: {
        const a = term.archivePending;
        if (!a) return;
        // Empty means the name is free. Otherwise: the name that is taken,
        // and the first one that is not.
        const answer = Terminus.parseConflicts(archiveClashOut.text);
        if (answer.length < 2) { term.commitArchive(a.name); return; }
        // The paste's own three answers, minus the one that would be a second
        // Cancel: SKIP and CANCEL are the same act when there is a single
        // thing to skip, and two buttons that do nothing is not a choice.
        // Overwrite wears the alarm colour here for the reason it does there.
        term.confirmRef.askMany(
          "Archive over " + answer[0] + "?",
          "keep both \u2192 " + answer[1],
          [{ label: "Overwrite", ink: Zenon.red,
             act: () => term.commitArchive(answer[0]) },
           { label: "Keep both", ink: Zenon.green,
             act: () => term.commitArchive(answer[1]) }]);
      }
    }
  }
  function commitArchive(name) {
    const a = term.archivePending;
    if (!a) return;
    term.archivePending = null;
    term.startJob("archive", a.paths, Terminus.joinPath(term.cwd, name), "");
    term.act.marked = {};
  }
  // Paste, but leaving the file where it is. Uses the same yank buffer as a
  // normal paste, because "what am I about to put down" is the same question.
  // Finder's "Make Alias", which is the one shape pasteLink cannot make:
  // an alias BESIDE the original, in one gesture, with no yank first. Not a
  // paste — there is nothing in hand — so it acts on the selection like
  // every other verb here.
  function linkHere() {
    const rows = term.acting();
    if (rows.length === 0) return;
    term.run(Terminus.linkHereCommand(rows.map((r) => r.path)));
    term.act.marked = {};
    term.status = rows.length === 1 ? "symlinked"
      : "symlinked " + rows.length;
  }
  function rotateLook(degrees) {
    const r = term.currentRow();
    if (!r || r.isDir || !Terminus.isImage(r.name)) return;
    rotateProc.path = r.path;
    rotateProc.command = ["sh", "-c", Terminus.rotateCommand(r.path, degrees)];
    rotateProc.running = true;
    term.status = "rotating\u2026";
  }
  Process {
    id: rotateProc
    property string path: ""
    onExited: (code) => {
      if (code !== 0) { term.status = "rotate failed"; return; }
      // The thumbnail is now a picture of the old orientation, and every
      // view that shows one reads it from this map — so it goes, and the
      // grid asks for a new one the next time it needs it.
      const t = Object.assign({}, term.thumbFile);
      delete t[rotateProc.path];
      term.thumbFile = t;
      // AND THE REMEMBERED NAME. Rotating rewrites the file, so its mtime
      // moves and the entry would stop matching anyway — but only once the
      // listing has been re-stat'ed. Dropping it here means the stale
      // picture cannot come back in the window between the two.
      const rx = Object.assign({}, term.thumbIndex);
      if (rx[rotateProc.path] !== undefined) {
        delete rx[rotateProc.path];
        term.thumbIndex = rx;
        term.thumbnailsRef.thumbIndexSave.restart();
      }
      term.imgStamp++;
      term.makeThumbs();
      term.status = "rotated";
    }
  }
  function convertLook(ext) {
    const rows = term.acting();
    const pics = rows.filter((r) => !r.isDir && Terminus.isImage(r.name));
    if (pics.length === 0) return;
    term.run(Terminus.convertCommand(pics.map((r) => r.path), ext));
    term.status = "converted to " + ext;
  }
  function extractAudio() {
    const rows = term.acting();
    const vids = rows.filter((r) => !r.isDir && Terminus.isVideo(r.name));
    if (vids.length === 0) return;
    term.run(Terminus.extractAudioCommand(vids.map((r) => r.path)));
    term.status = vids.length === 1 ? "audio extracted"
      : "audio extracted from " + vids.length;
  }
  function pasteLink(symbolic) {
    if (!term.pending || term.pending.paths.length === 0) return;
    term.run(Terminus.linkCommand(term.pending.paths, term.cursorDir(),
                                  symbolic));
    term.status = symbolic ? "symlinked" : "hard linked";
  }
  // The card and everything it does live in BulkRename.qml (shared with
  // picasso); this opens it on what the window is acting on.
  function beginBulkRename() {
    const rows = term.acting();
    if (rows.length === 0) return;
    term.bulkRef.begin(rows.map((r) => r.name), rows.map((r) => r.path));
  }
  Process {
    id: appsProc
    stdout: StdioCollector {
      id: appsOut
      waitForEnd: true
      onStreamFinished: {
        term.openWithApps = Terminus.parseApps(appsOut.text);
        term.openWithMime = Terminus.parseAppsMime(appsOut.text);
        term.openWithDefault = Terminus.parseAppsDefault(appsOut.text);
        term.appsScanned = true;
        // a scan asked for while this one was out — see findApps
        if (term.appsAgain !== "") {
          const p = term.appsAgain;
          term.appsAgain = "";
          term.findApps(p);
        }
      }
    }
  }
  function findApps(path) {
    // ── A SCAN IN FLIGHT IS WAITED FOR, NOT GIVEN UP ON ──────────────
    // This used to empty the answer and declare it final whenever a scan
    // was already running, so a rescan that landed during one — after a
    // handler was added or removed — left the card with nothing, or with
    // the state of the change before. It runs again as soon as the one in
    // flight is done, and until then the card keeps what it has.
    if (path && appsProc.running) { term.appsAgain = path; return; }
    term.openWithApps = [];
    term.openWithMime = "";
    term.openWithDefault = "";
    term.appsScanned = false;
    // A directory: nothing further is coming, so the answer is in — there is
    // nothing to open this with.
    if (!path) { term.appsScanned = true; return; }
    appsProc.command = ["sh", "-c", Terminus.appsCommand(path)];
    appsProc.running = true;
  }
  function openWith(id, path) {
    term.run(Terminus.openWithCommand(id, path));
  }
  function rescanApps() {
    if (term.appsPath !== "") term.findApps(term.appsPath);
  }
  function setDefaultApp(id) {
    if (!id || term.openWithMime === "") return;
    term.run(Terminus.setDefaultAppCommand(id, term.openWithMime));
    term.status = "default set";
    rescanTick.restart();
  }
  function removeApp(id) {
    if (!id || term.openWithMime === "") return;
    // ── REMOVING THE DEFAULT HANDS IT ON ─────────────────────────────
    // Striking out the application that opens this type took it off the
    // list and left it as the default: xdg-mime still answered with it,
    // the card had no name for an id no longer listed and printed the
    // raw "firefox.desktop", and a double click went on opening it. The
    // next one on the list becomes the default in the same command.
    let cmd = Terminus.removeAppCommand(id, term.openWithMime);
    if (id === term.openWithDefault) {
      const next = term.openWithApps.find((a) => a.id !== id);
      if (next) cmd = "{ " + cmd + "; } && "
        + Terminus.setDefaultAppCommand(next.id, term.openWithMime);
    }
    term.run(cmd);
    term.status = "handler removed";
    rescanTick.restart();
  }
  // A beat, because `run` is a process and the scan that follows reads what
  // that process writes. Asking immediately raced it and showed the list the
  // command had just changed.
  Timer {
    id: rescanTick
    interval: 220
    onTriggered: term.rescanApps()
  }
  // For the file nothing claims. The card lists everything installed rather
  // than everything that matches, because "nothing matches" is precisely how
  // you got here.
  // `launch` false is the properties card's "Add another…": that is about
  // the TYPE, and choosing an application there registers it and makes it
  // the default without opening the file — the right-click "Open with" is
  // the verb that opens. It used to open it either way, so adding Firefox
  // from the card started the film playing behind the card.
  // `alone` is the open that found no handler (see openFile): that was one
  // file, opened by itself, and the selection has nothing to do with it.
  function beginOpenWith(path, launch, alone) {
    if (!path) return;
    // THE SELECTION, with the pointer's row as the fallback — which is what
    // acting() means everywhere else in this window. The row the menu opened
    // on leads, so the type that gets adopted is the one that was asked about.
    const rows = alone ? [] : term.acting();
    const out = [path];
    for (let i = 0; i < rows.length; ++i)
      if (rows[i].path !== path && !rows[i].isDir) out.push(rows[i].path);
    // THE SCAN IS STARTED HERE TOO. It used to be the menu's job alone, so
    // reaching this card by its key — shift+return on a file — opened it with
    // no idea what already handles the type: no "opens with" list at the top,
    // and nothing to remove. The card reads the answer live, so it filling in
    // a moment later is fine.
    //
    // appsPath doubles as what rescanApps re-reads, so a handler removed from
    // inside the card refreshes the card.
    term.appsPath = path;
    term.findApps(path);
    term.appPickRef.ask(out, launch !== false);
  }
  function selectAll() {
    const next = {};
    for (const r of term.view) next[r.path] = true;
    term.act.marked = next;
  }
  function invertSelection() {
    const next = {};
    for (const r of term.view) if (!term.marked[r.path]) next[r.path] = true;
    term.act.marked = next;
  }
  function setSort(key) {
    if (term.sortKey === key) term.sortDesc = !term.sortDesc;
    else { term.sortKey = key; term.sortDesc = false; }
  }
  // Detached, NOT through root.run. run() is the action queue, and every
  // action's exit re-reads the directory, the open branches and wipes the
  // preview cache — a full refresh for putting text on the clipboard, which
  // also cleared the "copied" note the moment it appeared.
  function copyText(text, note) {
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy >/dev/null 2>&1",
      "terminus-copy", String(text)]);
    term.status = note;
  }
  function openShell() {
    term.run(Terminus.shellCommand(term.cwd, term.termCmd));
  }
}
