// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' the verbs … logic, out of TerminusWindow.qml
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
  id: clipboard
  property var term: null

  function yank(op) {
    const rows = term.acting();
    if (rows.length === 0) return;
    term.setPending({ op: op, paths: rows.map((r) => r.path),
                      names: rows.map((r) => r.name) });
    // AND ON THE SYSTEM CLIPBOARD, so a copy here means something everywhere
    // else — see clipboardCopyCommand. Its own process rather than the action
    // queue: that queue refreshes the listing and clears the status line when
    // it drains, and putting a clipboard write through it would make `y` blink
    // the directory and wipe the message it had just set.
    term.clipCopyProcRef.command = Terminus.shArgv(
      Terminus.clipboardCopyCommand(rows.map((r) => r.path), op === "move"));
    term.clipCopyProcRef.running = true;
    term.status = rows.length + (op === "copy" ? " to copy" : " to move");
  }
  // Asked on EVERY paste, because the clipboard is the one record of what was
  // copied last. The internal list used to win whenever it was set, and a `y`
  // leaves it set all session — so files copied in Nautilus afterwards could
  // never be pasted here; `p` kept producing the old yank. Now:
  //
  //   the same files the internal list holds  our own yank, still current:
  //                                           the internal list, which knows
  //                                           a cut from a copy
  //   other files                             copied since, elsewhere: they win
  //   an image                                already written by the script
  //   nothing a file manager can use          the internal list if there is
  //                                           one, else nothing to paste
  //
  // And a move already made is not made again: after `x` and `p` the list is
  // spent but the clipboard still names the paths it moved away from, so
  // those read as nothing — see spentClip.
  Process {
    id: clipProc
    stdout: StdioCollector {
      id: clipOut
      waitForEnd: true
      onStreamFinished: {
        const parts = String(clipOut.text || "").split("\u001e");
        const kind = parts[0];
        // An image that exists only on the clipboard has already been written
        // by the script — there was no file to copy, so there was one to make.
        if (kind === "wrote") {
          const name = parts[1] || "";
          term.wantSel = Terminus.joinPath(term.destDir, name);
          term.status = "pasted " + name;
          // Nothing is handed to commitPaste on this branch — the script
          // has already written the file — so the latch is released here
          // or the next paste inherits this one's destination.
          term.pasteDest = "";
          term.refresh();
          return;
        }
        if (kind === "gnome" || kind === "uris") {
          const lines = String(parts[1] || "").split("\n")
            .map((x) => x.trim()).filter((x) => x !== "");
          // GNOME's format leads with the word for the operation; a bare
          // uri-list says nothing about it, and copy is the safe reading.
          let op = "copy";
          if (kind === "gnome" && lines.length > 0) {
            op = lines[0] === "cut" ? "move" : "copy";
            lines.shift();
          }
          const paths = [];
          for (const l of lines) {
            const pth = Terminus.pathFromUri(l);
            if (pth !== "") paths.push(pth);
          }
          if (term.pasteFrom(kind, paths, op)) return;
        } else if (term.pasteFrom(kind, [], "copy")) {
          return;
        }
        term.pasteDest = "";
        term.warn("nothing to paste");
      }
    }
  }
  // False when there is nothing to paste; see Terminus.pasteSource.
  function pasteFrom(kind, paths, op) {
    const src = Terminus.pasteSource(kind, paths,
      term.pending ? term.pending.paths : null,
      term.mgr ? term.mgr.spentClip : []);
    if (src === "none") return false;
    if (src === "clip")
      term.setPending({ op: op, paths: paths,
                        names: paths.map((x) => Terminus.basename(x)) });
    // Straight on through the ordinary path, conflict scan and all.
    term.pastePending();
    return true;
  }
  // Nothing is written until the answer to "what is already there" comes back.
  // cp and mv overwrite in silence, so asking first is the only thing standing
  // between a paste and losing the file that was already in the destination.
  Process {
    id: conflictProc
    stdout: StdioCollector {
      id: conflictOut
      waitForEnd: true
      onStreamFinished: {
        const clash = Terminus.parseClashes(conflictOut.text);
        term.pasteClash = clash;
        // The mode is a plain string, not Terminus.CLASH.overwrite: a QML .js
        // import does not reliably expose top-level `const` bindings on its
        // namespace, and nothing else in this window reads one that way. The
        // names live in CLASH inside terminus.js, where the comparisons are.
        if (clash.length === 0) { term.commitPaste("overwrite"); return; }
        // Three answers, and Overwrite is deliberately NOT the one Enter takes
        // by reflex being listed first — it is, because it is the one you
        // usually mean, but it wears the alarm colour so a blind Enter is at
        // least an informed one. "Keep both" renames the incoming copy; "Skip"
        // keeps what is already there and takes the rest of the selection.
        // ── THE WORD HAS TO BE THE ONE THAT HAPPENS ──────────────────
        // rsync -a merges a directory into one of the same name: the
        // files the destination has and the source does not are left
        // alone, and only the ones that collide are written. So when
        // every clash is a directory, nothing is overwritten in the sense
        // the word means to anyone reading it, and the button said the
        // most alarming untrue thing on the card. Same action, and it
        // was always the safe one — now it says so.
        const n = clash.length;
        const folders = clash.every((c) => c.isDir);
        const what = folders ? (n === 1 ? " directory" : " directories")
                             : (n === 1 ? " item" : " items");
        term.confirmRef.askMany(
          folders
            ? "Merge into " + n + what + "?"
            : (term.pending.op === "copy" ? "Copy" : "Move")
              + " over " + n + what + "?",
          "",
          [{ label: folders ? "Merge" : "Overwrite",
             ink: folders ? Zenon.cyan : Zenon.red,
             act: () => term.commitPaste("overwrite") },
           { label: "Keep both", ink: Zenon.green,
             act: () => term.commitPaste("keep") },
           { label: "Skip", ink: Zenon.blue,
             act: () => term.commitPaste("skip") }],
          clash);
      }
    }
  }
  // `p`: whatever was copied LAST, here or anywhere — the clipboard decides,
  // see clipProc.
  function paste() {
    if (term.pasteDest === "") term.pasteDest = term.cursorDir();
    clipProc.command = ["sh", "-c",
      Terminus.clipboardPasteCommand(term.destDir)];
    clipProc.running = true;
  }
  // THIS list — a drop, a send-to, the other pane — which the clipboard has
  // nothing to say about.
  function pastePending() {
    if (term.pasteDest === "") term.pasteDest = term.cursorDir();
    if (!term.pending || term.pending.paths.length === 0) {
      term.pasteDest = "";
      term.warn("nothing to paste");
      return;
    }
    // ── NOTHING IS MOVED ONTO ITSELF ──────────────────────────────────
    // A cut pasted back where it came from met itself in the clash scan,
    // and Merge or Overwrite ran rsync --remove-source-files with the source
    // and the destination the same item: rsync had nothing to copy, then
    // removed the "source" — the only copy. The directory was simply gone.
    // Those are left where they are; there is nothing to move. And nothing,
    // copy or move, goes into itself or into something it contains.
    const dest = term.destDir;
    const op = term.pending.op;
    const take = term.pending.paths.filter((p) =>
      p !== dest && dest.indexOf(p + "/") !== 0
      && !(op === "move" && Terminus.dirname(p) === dest));
    if (take.length === 0) {
      term.pasteDest = "";
      term.warn(op === "move" ? "already here" : "cannot paste a directory into itself");
      return;
    }
    term.pasteOnly = take.length === term.pending.paths.length ? null : take;
    conflictProc.command = Terminus.shArgv(Terminus.conflictCommand(
      take.map((p) => Terminus.basename(p)), dest));
    conflictProc.running = true;
  }
  function startJob(op, paths, dest, clash) {
    term.spendMarks();
    // setsid, so the job gets a process group of its own and CANCELLING it can
    // take the whole tree down rather than leaving rsync running orphaned.
    const argv = ["setsid"].concat(Terminus.shArgv(
      op === "archive" ? Terminus.archiveJobCommand(paths, dest)
        : op === "extract"
          ? { script: Terminus.extractJobCommand(paths[0], dest), args: [] }
        : Terminus.transferCommand(paths, dest, op === "move", clash)));
    if (Jobs.start(op, paths, dest, argv) < 0) term.warn("could not start");
  }
  function clearEndedJobs() { Jobs.clearEnded(); }
  // cwd was a safe answer for as long as every row on screen was in it.
  // The list's tree broke that: a row inside an opened branch belongs to
  // the branch, and duplicating or extracting it into cwd puts the result
  // somewhere the row is not.
  //
  // One destination per job, so a selection spanning two directories has no
  // single right answer — those fall back to cwd, which is at least where
  // you are standing. A selection from one directory, which is nearly all of
  // them, lands beside itself.
  function homeOf(rows) {
    if (!rows || rows.length === 0) return term.cwd;
    const first = Terminus.dirname(rows[0].path);
    for (let i = 1; i < rows.length; ++i)
      if (Terminus.dirname(rows[i].path) !== first) return term.cwd;
    return first;
  }
  function duplicate() {
    const rows = term.acting();
    if (rows.length === 0) return;
    term.setPending({ op: "copy",
                      paths: rows.map((r) => r.path),
                      names: rows.map((r) => r.name) });
    const home = term.homeOf(rows);
    term.pasteDest = home === term.cwd ? "" : home;
    term.commitPaste("keep");
    term.act.marked = {};
    term.status = rows.length === 1 ? "duplicated"
      : "duplicated " + rows.length;
  }
  function commitPaste(clash) {
    const p = term.pending;
    if (!p) return;
    const dest = term.destDir;
    // what pastePending let through — and the same guard again here, since
    // not every caller comes by way of it: rsync must never be handed an
    // item as its own destination with --remove-source-files
    const paths = (term.pasteOnly || p.paths).filter((x) =>
      x !== dest && dest.indexOf(x + "/") !== 0
      && !(p.op === "move" && Terminus.dirname(x) === dest));
    term.pasteOnly = null;
    if (paths.length === 0) { term.pasteDest = ""; return; }
    // A move is recorded as where each item was and where it is about to be,
    // so undo can put it back precisely. A copy is not recorded at all — see
    // the undo stack's own note.
    //
    // ONLY WHERE THE LANDING IS KNOWN. An item that met a same-named one in
    // the destination does not land at dest/basename in every answer: Keep
    // both renames it on arrival ("name (1)"), Skip leaves it where it was,
    // and a directory Merge folds it into one that already had contents. The
    // record used to assume dest/basename regardless, so undoing a Keep both
    // or a Skip moved the file that was ALREADY in the destination, and
    // undoing a merge carried off everything the directory held before. What
    // can be put back precisely is: everything that did not clash, and a
    // plain file that overwrote its namesake.
    if (p.op === "move") {
      const hit = ({});
      for (const c of (term.pasteClash || [])) hit[c.name] = c;
      const pairs = [];
      const tagPairs = [];
      for (let i = 0; i < paths.length; ++i) {
        const pair = [paths[i], Terminus.joinPath(dest, Terminus.basename(paths[i]))];
        const c = hit[Terminus.basename(paths[i])];
        if (!c) { pairs.push(pair); tagPairs.push(pair); continue; }
        if (clash !== "overwrite") continue;
        tagPairs.push(pair);
        if (!c.isDir) pairs.push(pair);
      }
      if (pairs.length > 0) term.pushUndo({ kind: "move", pairs: pairs });
      if (tagPairs.length > 0) term.moveTags(tagPairs);
    }
    term.pasteClash = [];
    term.startJob(p.op, paths, dest, clash);
    // spent: the next paste is a paste into where you are standing again
    term.pasteDest = "";
    // a move is spent once it lands; a copy can be pasted again elsewhere.
    // The clipboard still names what moved, so that is remembered too.
    if (p.op === "move") {
      if (term.mgr) term.mgr.spentClip = p.paths.slice();
      term.setPending(null);
    }
    term.act.marked = {};
  }
  function trash() {
    const rows = term.acting();
    if (rows.length === 0) return;
    term.askTrash(rows);
  }
  function askTrash(rows) {
    if (!term.confirmTrash) { term.doTrash(rows); return; }
    // One is named in the question; several are listed, one a line.
    term.confirmRef.ask(
      rows.length === 1 ? "Trash " + rows[0].name + "?" : "Trash " + rows.length + " items?",
      ["u", "brings " + (rows.length === 1 ? "it" : "them") + " back"], "Trash",
      () => term.doTrash(rows), rows.length > 1 ? rows : []);
  }
  // The doing, apart from the asking, so both routes run exactly the same
  // thing — including the undo record, which is the whole reason the ask can
  // be skipped at all.
  function doTrash(rows) {
    const paths = rows.map((r) => r.path);
    term.run(Terminus.trashCommand(paths));
    // The xattr goes to the trash with the file, so a restore still knows
    // what it was tagged; it is the INDEX that must stop counting it while
    // it is not in your tree. Reindex after a restore to get it back.
    term.forgetTags(paths);
    // recorded by where they CAME FROM: that is what undo can look up
    term.pushUndo({ kind: "trash", paths: paths });
    term.act.marked = {};
  }
}
