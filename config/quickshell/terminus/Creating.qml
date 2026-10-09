// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' creating … logic, out of TerminusWindow.qml
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
  id: creating
  property var term: null
  readonly property alias emptyDelay: emptyDelay
  readonly property alias makeGuard: makeGuard

  Timer {
    id: emptyDelay
    interval: 150
    onTriggered: term.probeEmpty()
  }
  Process {
    id: emptyProc
    property var asked: []
    stdout: StdioCollector {
      id: emptyOut
      waitForEnd: true
      onStreamFinished: {
        const full = ({});
        for (const p of String(emptyOut.text || "").split("\u0000"))
          if (p !== "") full[p] = true;
        const next = Object.assign({}, term.dirEmpty);
        for (const d of emptyProc.asked) {
          if (full[d]) delete next[d];
          else next[d] = true;
        }
        term.dirEmpty = next;
      }
    }
  }
  function probeEmpty() {
    if (emptyProc.running) { emptyDelay.restart(); return; }
    const pane = term.act;
    if (!pane || !pane.treed) return;
    const v = pane.view;
    const dirs = [];
    for (let i = 0; i < v.length; ++i)
      if (v[i].isDir) dirs.push(v[i].path);
    if (dirs.length === 0) return;
    emptyProc.asked = dirs;
    emptyProc.command = Terminus.shArgv(Terminus.nonEmptyCommand(dirs));
    emptyProc.running = true;
  }
  // Where a new file belongs, and where a paste lands. One function
  // because it is one question: with a tree open the row under the cursor
  // may live several directories down, and every verb that PUTS something
  // somewhere should agree about where "here" is. A flat listing answers
  // cwd to all of them, so nothing outside the tree changes.
  function cursorDir() {
    const r = term.currentRow();
    if (!r || !term.act.treed) return term.cwd;
    // ── A DIRECTORY UNDER THE CURSOR IS A PLACE ──────────────────────
    // This asked for the directory to be OPEN, which left exactly one
    // hole and it is the one that matters: an EMPTY directory has no
    // chevron — deliberately, there is nothing to disclose — so it can
    // never be open, so nothing could ever be made in it. The one moment
    // you most want to make a file inside a directory is when it is empty.
    //
    // So any directory under the cursor is the place, open or not.
    // startCreate opens it, which is what makes the new row visible.
    if (r.isDir) return r.path;
    const owner = Terminus.dirname(r.path);
    return owner === "" ? term.cwd : owner;
  }
  // The rows already in a directory, so a new name can avoid colliding with
  // them. The listing for cwd, and a branch's own rows for anywhere else.
  function rowsIn(dir) {
    const rows = (dir === term.cwd)
      ? term.rows
      : (term.act.kids["k:" + dir] || []);
    // Anything now really there no longer needs remembering.
    for (let i = 0; i < rows.length; ++i) {
      const p = rows[i].path;
      if (term.justMade[p] !== undefined) delete term.justMade[p];
    }
    return rows;
  }
  function beginCreate() { term.startCreate("file"); }
  function beginMkdir() { term.startCreate("dir"); }
  function startCreate(kind) {
    // A DIALOG IS A PLACE TO PUT THINGS, NOT JUST TO FIND THEM. This refused
    // outright in picker mode, which meant a save dialog could not make the
    // directory you wanted to save into — you cancelled, opened a file manager,
    // made the directory, and started the save again.
    //
    // BOTH kinds are allowed, not just the directory that was actually asked
    // for: `a` is the prefix of the `a /` that makes a directory, so refusing
    // the file half refuses the sequence before it can reach its second key,
    // and the directory could still not be made. An empty file someone asked
    // for twice over is their business.
    // Finish whatever name is being typed rather than refusing: `a` twice in
    // a row is a reasonable thing to do, and the first one silently doing
    // nothing is not a reasonable answer to it.
    if (term.renaming) term.endRename(false);
    // ── WHERE YOU ARE LOOKING, NOT WHERE YOU STARTED ──────────────────
    // cwd was the only possible answer while the list only ever showed
    // cwd. With a tree open, the row under the cursor may live several
    // directories down, and making a file there meant closing the branch,
    // walking in, making it, and walking back out.
    //
    // An OPEN directory takes it inside itself, which is the one place a
    // new thing would be visible immediately. Anything else goes beside
    // the row — which at the top level is cwd, so nothing about the flat
    // case changes.
    const where = term.cursorDir();
    const pane = term.act;
    // ── THE BRANCH IS OPENED FIRST, AND IT IS READ FIRST ──────────────
    // Two reasons, and the first one is a bug that hid behind the second.
    //
    // ORDER. setOpen arms wantSel with the row under the cursor, so that
    // splicing a branch in does not rewind the view — see its note. This
    // ran AFTER the aim at the new file was set, and quietly replaced it
    // with the directory: the cursor landed back on the directory, landWanted
    // was spent on it, and the listing that finally carried the new row
    // found nothing armed. The name never opened for editing. It looked
    // intermittent because a branch already open makes setOpen a no-op,
    // and the same gesture then worked.
    //
    // ROWS. freeName needs to know what is already in the directory, and
    // a branch that has never been opened has no rows at all. It would
    // therefore always choose "new file" — and `touch` on a file that
    // exists quietly bumps its mtime and creates nothing, so making a
    // file inside a closed directory that already had one did nothing
    // whatsoever. Deferred until the branch lands; see pendingMake.
    if (where !== term.cwd && pane && pane.treed) {
      pane.setOpen(where, true);
      if (!pane.kids["k:" + where]) {
        term.pendingMake = { kind: kind, dir: where, cwd: term.cwd };
        makeGuard.restart();
        pane.readKids(where);
        return;
      }
    }
    term.makeIn(kind, where);
  }
  Timer {
    id: makeGuard
    // Generously longer than one `find` over one directory, and far
    // shorter than the time it takes to walk somewhere else and forget
    // this was ever asked for.
    interval: 2500
    onTriggered: term.pendingMake = null
  }
  // Split out of makeIn because the gather verb below needs every word of
  // it — the free name, the aim that opens the rename field, the justMade
  // entry that stops two of them picking the same name, and the branch
  // re-read — and needs to run a DIFFERENT command with the result. The
  // one thing it does not do is decide what to run; that is the caller's.
  function reserveName(stem, where) {
    // ── A NAME ASKED FOR IS AS TAKEN AS A NAME ON DISK ────────────────
    // freeName reads the rows, and the rows are up to a watch settle
    // behind — a quarter of a second. Two `a`s inside that window both
    // computed "new file", and the second command is `touch`, which on
    // an existing file quietly bumps its mtime and creates nothing. So
    // the second one appeared to do nothing at all, and the cursor
    // landed back on the first file.
    //
    // Names this window has asked for are remembered until they turn up
    // in a listing — see justMade — so the second `a` gets "new file 2"
    // whether or not the first has landed yet.
    const near = term.rowsIn(where).slice();
    const now = Date.now();
    for (const p in term.justMade) {
      if (now - term.justMade[p] > term.madeTTL) { delete term.justMade[p]; continue; }
      if (Terminus.dirname(p) === where)
        near.push({ name: Terminus.basename(p) });
    }
    const name = Terminus.freeName(near, stem);
    const path = Terminus.joinPath(where, name);
    term.freshPath = path;
    term.freshHolds = false;
    term.wantSel = path;
    // Capped: an entry is normally dropped the moment the row turns up
    // in a listing, but a create that FAILS — no permission, a full
    // disk — never produces one, and that name would then read as taken
    // for the rest of the session.
    const made = Object.keys(term.justMade);
    if (made.length >= 16) delete term.justMade[made[0]];
    term.justMade[path] = now;
    // ── AND THE BRANCH HAS TO BE RE-READ AFTERWARDS ─────────────────
    // It was read to get here — startCreate opens it and waits — and the
    // file did not exist yet at that point. The watcher covers open
    // branches and would normally catch the create, but the branch may
    // have been opened a moment ago and the watch is still restarting as
    // the command runs; a directory that was empty until now is exactly the
    // case with no other event to fall back on. Named here and re-read
    // when the command lands.
    term.madeIn = where;
    return name;
  }
  function makeIn(kind, where) {
    const name = term.reserveName(
      kind === "dir" ? "new directory" : "new file", where);
    term.run(kind === "dir" ? Terminus.mkdirCommand(where, name)
                            : Terminus.createCommand(where, name));
  }
  // Tick nine things, one gesture: the directory is made, the nine are moved
  // into it, and the cursor lands on it with the name open for typing —
  // which is the whole of it, because a directory made this way is always
  // about to be called something.
  //
  // ONE COMMAND, not a create followed by a move. root.run is asynchronous
  // and the move would have to be fired from the create's completion, which
  // is a callback this window does not have and a race it does not need:
  // mkdir and mv in one shell, with && between them, cannot move anything
  // into a directory that was not made.
  function gatherIntoFolder() {
    const rows = term.acting();
    if (rows.length === 0) { term.warn("nothing to gather"); return; }
    const where = term.cwd;
    // The rows have to be in the directory the directory is being made in, or
    // the move is a move ACROSS directories wearing a tidy-up's clothes.
    // Everything acting() can hand back on a plain listing already is —
    // a results page is the case that is not, and there is no one
    // directory to gather into there.
    if (term.searchMode !== "") {
      term.warn("not on a results page");
      return;
    }
    const paths = rows.map((r) => r.path);
    const name = term.reserveName("new directory", where);
    // NOT disposable: see freshHolds. The selection is in there.
    term.freshHolds = true;
    const dest = Terminus.joinPath(where, name);
    // Recorded so u puts them back. The directory itself is left behind
    // empty, which is what undoing a MOVE means — the directory was never
    // the thing that moved.
    term.pushUndo({ kind: "move",
      pairs: paths.map((x) =>
        [x, Terminus.joinPath(dest, Terminus.basename(x))]) });
    term.moveTags(paths.map((x) =>
      [x, Terminus.joinPath(dest, Terminus.basename(x))]));
    term.run(Terminus.gatherCommand(where, name, paths));
    term.spendMarks();
  }
  // yazi's `D`. Not the trash, and worded so the card cannot be mistaken for
  // the one that is recoverable.
  function deleteForever() {
    const rows = term.acting();
    if (rows.length === 0) return;
    term.confirmRef.ask(
      rows.length === 1 ? "Delete " + rows[0].name + " for good?"
        : "Delete " + rows.length + " items for good?",
      "this cannot be undone — " + (rows.length === 1 ? "it does" : "they do") + " not go to the trash",
      "Delete", () => {
        const doomed = rows.map((r) => r.path);
        term.run(Terminus.deleteCommand(doomed));
        term.forgetTags(doomed);
        term.act.marked = {};
      }, rows.length > 1 ? rows : []);
  }
  // The search sheet — see collEdit.askSearch. "" reopens on the last one.
  function beginSearch(mode) { term.collEditRef.askSearch(mode); }
}
