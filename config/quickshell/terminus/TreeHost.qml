// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE HOST A TREE OF EntryRows READS — for a tree that is not terminus'
// own window. terminus/EntryRow.qml draws a row (glyph, name, the tree's
// guides and chevron, git's letter, rename in place) and reads what it needs
// to know about where it is off `host`. Terminus' window is that host for
// its listings; this is the host for a tree standing elsewhere: terminus'
// measurements at the tree's text size, git's letters when given, and the
// columns, tags, disk usage and drag and drop terminus has and such a tree
// does not, at their "nothing here" values.
//
// Lifted out of morpheus/FileTree (2026-10-11) so delphi's Changes could be
// the same tree — FileTree and Changes are its two holders.
//
//     TreeHost { fontSize: 15; root: "/x"; marks: { "/x/a": "modified" }
//                noteWidth: 40          // room kept at a row's right end
//                renameCommit: (entry, text) => …   renameEnd: (cancel) => …
//                menuOpen: (item, m) => … }
// A holder that renames in place sets `renaming` and `renamePath`; one with
// a menu sets `menuItem` and binds `sideMenuAt` (the row it is about).

import QtQuick
import "../morpheus"
import "terminus.js" as Terminus

QtObject {
  id: host

  // ── what the holder sets ───────────────────────────────────────────
  property real fontSize: 15
  // the tree's top (EntryRow reads it as the directory being listed)
  property string root: ""
  // git's state per path, a directory wearing its worst (terminus.js
  // gitWorse); empty: no git gutter at all
  property var marks: ({})
  // directories that are repositories, path → true (FileTree reads them
  // with each branch; see TerminusWindow.repoDirs)
  property var repoDirs: ({})
  // directories read and found empty: no chevron
  property var empties: ({})
  // width kept free at a row's right end, for the holder's own word
  property int noteWidth: 0
  // a cut-short name rested on: the holder's NamePeek, (row, entry) → …
  property var namePeek: null
  function peekName(row, entry) { if (host.namePeek) host.namePeek(row, entry); }
  // rename in place and the row menu, the holder's to do
  property var renameCommit: null
  property var renameEnd: null
  property var menuOpen: null

  // ── terminus' measurements, at this size ───────────────────────────
  // terminus draws at zoom 1 for 16px text
  readonly property real zoom: host.fontSize / 16
  // 24, as terminus' rows now are (user, 2026-10-08)
  readonly property int rowH: Math.round(24 * host.zoom)
  // Tighter than terminus' 28: a level's step is where a sidebar's width
  // goes, and at 28 two levels down left a name a hundred pixels to live
  // in. The guides are drawn against this, so nothing else moves.
  readonly property int treeStep: Math.round(20 * host.zoom)
  readonly property int treeArrowW: Math.round(14 * host.zoom)
  readonly property int doubleMs: 400
  property bool hoverRow: false
  // the row's two acknowledgements, a light across a row that was opened
  // or just made: terminus bumps these, and so could a holder that wants them
  property int openPulse: 0
  property int madePulse: 0
  readonly property string cwd: host.root
  readonly property string searchMode: ""
  readonly property bool modal: false
  readonly property int markedCount: 0
  readonly property bool railHover: false
  readonly property bool railDragging: false

  // ── git ────────────────────────────────────────────────────────────
  readonly property bool git: Object.keys(host.marks).length > 0
  readonly property var gitMarks: host.marks
  function gitInk(state) { return Terminus.gitInk(state); }

  readonly property var dirEmpty: host.empties

  // ── the columns: the name takes the whole row ──────────────────────
  readonly property var colPlain: ({ name: 1, where: 0, kind: 0, size: 0, time: 0 })
  readonly property var colFound: host.colPlain
  readonly property var colFoundNarrow: host.colPlain
  function colWidths(inner, f) { return { name: inner - host.noteWidth, where: 0, kind: 0, size: 0, time: 0 }; }
  readonly property var dirSizes: ({})
  readonly property bool usage: false
  readonly property real usageMax: 0
  readonly property real otherUsageMax: 0
  function usageOf(e) { return 0; }
  function sizeTextOf(e) { return Terminus.formatSize(e.size); }
  function whenOf(e) { return Terminus.formatTime(e.mtime); }
  function kindOf(e) { return e.isDir ? "directory" : Terminus.kindOf(e.name); }
  readonly property var tagMarks: ({})
  function tagInk(name) { return Zenon.accentMuted; }
  function isBookmarked(p) { return false; }

  // no dragging out, and nothing dropped in
  readonly property string dropDir: ""
  function dropDirAt() {}
  function beginDrag() {}
  readonly property var dragProxy: null
  readonly property string freshPath: ""

  // ── rename in place, and the row menu ──────────────────────────────
  property bool renaming: false
  property string renamePath: ""
  function commitRename(entry, text) { if (host.renameCommit) host.renameCommit(entry, text); else host.renaming = false; }
  function endRename(cancel) { if (host.renameEnd) host.renameEnd(cancel); else host.renaming = false; }
  // The row a menu is open about, which EntryRow outlines with terminus'
  // HeldRing (it reads sideMenuAt, terminus' name for it).
  property var menuItem: null
  property var sideMenuAt: null
  function openMenuAt(item, m) {
    host.menuItem = item;
    if (host.menuOpen) host.menuOpen(item, m);
  }
}
