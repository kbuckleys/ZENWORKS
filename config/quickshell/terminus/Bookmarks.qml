// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' bookmarks … logic, out of TerminusWindow.qml
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
  id: bookmarks
  property var term: null

  FileView {
    id: bookmarkFile
    path: Quickshell.statePath("terminus-bookmarks")
    blockLoading: true
    printErrors: false
    // FileView can watch its own file, which is the one kind of watching
    // quickshell does offer — so a bookmark added in another terminus window,
    // or edited by hand, shows up here without a restart.
    watchChanges: true

    // TWO SIGNALS, AND THEY ARE NOT THE SAME EVENT. This took three goes.
    //
    // `fileChanged` says the file on disk is no longer what we hold. It
    // refreshes nothing by itself, so it has to ask — and `reload()` only
    // QUEUES the read. text() immediately afterwards still answers with the
    // copy we already had, which is what defeated every previous attempt
    // here: a "we are writing" flag that got stuck and swallowed other
    // windows' changes, and then a comparison against the text we last wrote
    // which compared the OLD content against the NEW and concluded it was
    // somebody else's news — so it re-derived the list from the stale bytes
    // and put back the bookmark you had just removed, about a second after
    // you removed it. That was the "not instant".
    //
    // `textChanged` is where the new bytes actually arrive. By then the
    // question "what does the file say" has an answer, and it does not matter
    // who wrote it: our own write lands here too and simply re-derives the
    // array the sidebar is already showing. There is no state left to get
    // stuck, and nothing to compare.
    onFileChanged: bookmarkFile.reload()
    onTextChanged: term.loadBookmarks()
  }
  function readBookmarks() {
    return String(bookmarkFile.text() || "").split("\n")
      .map((l) => l.trim()).filter((l) => l !== "");
  }
  function loadBookmarks() { term.setBookmarks(term.readBookmarks()); }
  // ONLY WHEN IT IS DIFFERENT. The sidebar's Repeater takes a plain array, and
  // a plain array cannot say "the same, reordered": every assignment throws
  // every row away and builds them again. A move assigned it three times — the
  // re-read, the result, and the file watch echoing the write back — and the
  // first of those destroyed the very row whose drag was still finishing, so
  // the list blinked empty and left a ghost label behind for a beat.
  function setBookmarks(list) {
    const cur = term.bookmarks;
    if (cur.length === list.length && cur.every((p, i) => p === list[i])) return;
    term.bookmarks = list;
  }
  function isBookmarked(path) { return term.bookmarks.indexOf(path) >= 0; }
  // Every change goes through here, and it re-reads before it writes.
  //
  // The list is shared by every terminus window, so "what I think it is" is not
  // good enough to base a write on — the copy in hand can be stale, and a
  // read-modify-write on a stale copy silently reverts whatever another window
  // did. Re-reading immediately before mutating makes the last write win on
  // the CURRENT list rather than on an old one.
  function editBookmarks(mutate) {
    // Re-read before mutating, FOR REAL. reload() queues the read and
    // waitForJob() is what blocks until it has landed — without it, the
    // "modify the CURRENT list rather than an old one" this function exists
    // for was operating on exactly the old one it was trying to avoid.
    // Blocking is already the deal here: blockLoading is on, and this is one
    // short line-per-path file.
    bookmarkFile.reload();
    bookmarkFile.waitForJob();
    // Mutated off the file, not off root.bookmarks via an assignment: going
    // through loadBookmarks here would rebuild the sidebar once for the read
    // and again for the result.
    const next = term.readBookmarks();
    mutate(next);
    // In memory first, so the sidebar changes on this frame. The write comes
    // back round through onTextChanged and re-derives the same array, which
    // setBookmarks sees is the same and leaves alone.
    term.setBookmarks(next);
    bookmarkFile.setText(next.join("\n") + "\n");
  }
  // One key, both directions: bookmarking the directory you are in and removing
  // it again are the same gesture, and a separate "unbookmark" would need you
  // to know which one you had. Takes any directory, not just the one you are
  // standing in.
  function toggleBookmarkFor(path) {
    let removed = false;
    term.editBookmarks((list) => {
      const at = list.indexOf(path);
      removed = at >= 0;
      if (removed) list.splice(at, 1);
      else list.push(path);
    });
    term.status = removed ? "bookmark removed" : "bookmarked";
  }
  // Anything dragged onto the sidebar can be offered as a bookmark; only
  // directories become one. Whether a dropped path IS a directory is asked of the
  // disk, because a drag from another application says nothing about it —
  // and asked in argv, so no file name is ever read by a shell.
  function localPaths(urls) {
    const out = [];
    for (const u of urls || []) {
      const t = String(u);
      const p = Terminus.pathFromUri(t);
      if (p !== "") out.push(p);
    }
    return out;
  }
  function bookmarkDropped(urls) {
    const paths = term.localPaths(urls).filter((p) => term.bookmarks.indexOf(p) < 0);
    if (paths.length === 0) {
      if (term.localPaths(urls).length > 0) term.status = "already bookmarked";
      return;
    }
    if (bookmarkProbe.running) return;
    bookmarkProbe.asked = paths.length;
    bookmarkProbe.command = ["sh", "-c",
      "for p; do [ -d \"$p\" ] && printf '%s\\n' \"$p\"; done; exit 0",
      "terminus-bookmark"].concat(paths);
    bookmarkProbe.running = true;
  }
  Process {
    id: bookmarkProbe
    property int asked: 0
    stdout: StdioCollector {
      id: bookmarkProbeOut
      onStreamFinished: {
        const dirs = String(bookmarkProbeOut.text).split("\n").filter((l) => l !== "");
        const skipped = bookmarkProbe.asked - dirs.length;
        if (dirs.length === 0) {
          term.status = "only directories can be bookmarked";
          return;
        }
        term.editBookmarks((list) => {
          for (const d of dirs) if (list.indexOf(d) < 0) list.push(d);
        });
        term.status = (dirs.length === 1 ? "bookmarked" : "bookmarked " + dirs.length)
          + (skipped > 0 ? " · " + skipped + (skipped === 1 ? " file" : " files")
             + " skipped" : "");
      }
    }
  }
  function armSideSlide() { term.sideSlide = true; sideSlideOff.restart(); }
  Timer {
    id: sideSlideOff
    interval: Zenon.fast + 40
    onTriggered: term.sideSlide = false
  }
  // ONE MOVE, wherever it was asked for. The sidebar drags and the bookmark
  // sheet presses alt-arrows, and both mean "put this one there" — the file is
  // the order, so whichever does it, both lists follow.
  // `to` is the INDEX it ends up at, which is what the sheet's alt-arrows
  // already mean. A drag speaks in insertion points instead — where the line
  // is drawn, 0..n — and converts before it calls this; see the handler.
  function moveBookmark(from, to, quiet) {
    const n = term.bookmarks.length;
    const t = Math.max(0, Math.min(n - 1, to));
    if (from < 0 || from >= n || from === t) return;
    term.editBookmarks((list) => {
      const item = list.splice(from, 1)[0];
      list.splice(t, 0, item);
    });
    // a drag says it by the row landing where you put it
    if (!quiet) term.status = "bookmark moved";
  }
  function removeBookmark(path) {
    term.editBookmarks((list) => {
      const at = list.indexOf(path);
      if (at >= 0) list.splice(at, 1);
    });
    term.status = "bookmark removed";
  }
  function toggleBookmark() { term.toggleBookmarkFor(term.cwd); }
  // What the hint bar should CALL that toggle, which depends on which way it
  // is about to go. A key that does two opposite things should not describe
  // itself with one of them.
  function bookmarkVerb() {
    const r = term.currentRow();
    const onRow = !!(r && r.isDir);
    const path = onRow ? r.path : term.cwd;
    if (term.isBookmarked(path)) return "remove bookmark";
    return onRow ? "bookmark item" : "bookmark this directory";
  }
  // What `b b` acts on: the directory under the cursor if there is one, and
  // otherwise the directory you are standing in. A file cannot be bookmarked —
  // the sidebar navigates to what it lists — so the cursor being on one falls
  // through to the containing directory rather than doing nothing.
  function toggleBookmarkHere() {
    const r = term.currentRow();
    if (r && r.isDir) term.toggleBookmarkFor(r.path);
    else term.toggleBookmark();
  }
}
