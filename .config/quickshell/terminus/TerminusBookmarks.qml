// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TERMINUS' BOOKMARKS — one list, shared by every terminus window.
//
// Kept in the shell's own state directory, not next to the config: it is
// something you accumulate by using terminus, not something you write by hand.
//
// A singleton because the list IS shared: each window used to hold its own
// FileView watching the same file, one inotify watch and one copy per window
// (the pre-warmed spare included), kept in step only through the disk. Now
// there is one reader, and a change made in one window is simply the list
// every window is already bound to.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  property var list: []

  FileView {
    id: file
    path: Quickshell.statePath("terminus-bookmarks")
    blockLoading: true
    printErrors: false
    // FileView can watch its own file, so a bookmark edited by hand shows up
    // without a restart.
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
    onFileChanged: file.reload()
    onTextChanged: root.load()
  }

  function load() {
    root.list = String(file.text() || "").split("\n")
      .map((l) => l.trim()).filter((l) => l !== "");
  }

  function has(path) { return root.list.indexOf(path) >= 0; }

  // Every change goes through here, and it re-reads before it writes: the file
  // can also be edited by hand, and a read-modify-write on a stale copy
  // silently reverts that. reload() queues the read and waitForJob() is what
  // blocks until it has landed; blocking is already the deal here
  // (blockLoading is on, and this is one short line-per-path file).
  function edit(mutate) {
    file.reload();
    file.waitForJob();
    root.load();
    const next = root.list.slice();
    mutate(next);
    // In memory first, so the sidebar changes on this frame. The write comes
    // back round through onTextChanged and re-derives the same array.
    root.list = next;
    file.setText(next.join("\n") + "\n");
  }

  Component.onCompleted: root.load()
}
