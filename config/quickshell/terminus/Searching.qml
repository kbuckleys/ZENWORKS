// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' searching … logic, out of TerminusWindow.qml
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
  id: searching
  property var term: null

  function applyPendingRealm() {
    const p = term.pendingRealm;
    if (!p) return;
    term.pendingRealm = null;
    term.searchMode = p.mode;
    term.searchQuery = p.query;
    if (p.id !== undefined) term.collOpenId = p.id;
    if (p.folder) term.applyCollectionView(p.folder);
    if (p.tag !== undefined) term.applyTagView(p.tag);
  }
  Process {
    id: searchProc
    property string askedKey: ""
    property bool again: false
    onExited: if (searchProc.again) { searchProc.again = false; Qt.callLater(term.runSearch); }
    stdout: StdioCollector {
      id: searchOut
      waitForEnd: true
      onStreamFinished: {
        if (searchProc.askedKey !== term.searchKey()) return;
        const paths = String(searchOut.text || "").split("\u0000")
          .map((x) => x.replace(/\/+$/, ""))
          .filter((x) => x !== "");
        if (paths.length === 0) {
          term.applyPendingRealm();
          term.act.raw = [];
          term.status = "no matches";
          // a re-ask that found nothing: its aim must not be taken by
          // whatever listing arrives next
          term.wantSel = "";
          term.reAt = -1;
          return;
        }
        term.runStat(paths, []);
      }
    }
  }
  // ONE STAT AT A TIME, AND THE NEWEST QUESTION WINS. `running = true` on a
  // running Process is a no-op, and this used to set askedFor first: open a
  // second tag page while the first was still being stat'ed and the FIRST
  // page's answer was pruned against the SECOND page's paths — every tagged
  // file of the new tag missing from the old rows was deleted from the tag
  // index, and the old rows were drawn under the new tag's name. Now a
  // request made mid-run waits for the run to end, each run keeps the
  // question it was actually asked, and an answer that has been overtaken is
  // used for pruning (it is still true about its own paths) but not drawn.
  function runStat(paths, asked) {
    if (statProc.running) { statProc.next = { paths: paths, asked: asked }; return; }
    statProc.askedFor = asked;
    statProc.command = Terminus.statArgv(paths);
    statProc.running = true;
  }
  Process {
    id: statProc
    // Which paths this run was asked about, so a reply can be compared
    // against the question. Only the tag and collection pages set it.
    property var askedFor: []
    property var next: null
    onExited: {
      if (!statProc.next) return;
      const n = statProc.next;
      statProc.next = null;
      Qt.callLater(() => term.runStat(n.paths, n.asked));
    }
    stdout: StdioCollector {
      id: statOut
      waitForEnd: true
      onStreamFinished: {
        const rows = term.enrich(Terminus.parseStat(statOut.text));
        // THE INDEX LEARNS FROM ITS OWN MISSES. A tagged file deleted or
        // moved by something that is not terminus leaves an entry behind,
        // and that entry is not harmless: it inflates the sidebar's count
        // and it is a row that cannot be opened. `find` has just told us
        // which of the paths we asked about still exist, so the ones it
        // did not answer for are gone — and this is the one moment we know
        // that for certain without going and looking.
        term.pruneTagIndex(statProc.askedFor, rows);
        // overtaken: the page it was for is no longer the one being opened
        if (statProc.next) return;
        // Everything the new realm is, in one frame with its rows.
        term.applyPendingRealm();
        term.act.raw = rows;
        term.act.sel = 0;
        // ── UNLESS SOMETHING ASKED FOR A ROW ────────────────────────
        // sel = 0 is right when a results page has just OPENED: the rows
        // are a set you have not seen and the first is as good as any. It
        // is wrong when the same page is re-run because something on it
        // was created, renamed or deleted — that is not an arrival, and
        // being thrown back to the top of a hundred rows after every
        // action is its own kind of broken. reCollect arms the aim with
        // the row you were standing on.
        //
        // ONE ATTEMPT, then disarmed either way: the row may have been
        // the very thing that was just deleted, and an aim left armed
        // would be taken by whatever listing arrived next.
        if (term.wantSel !== "") {
          const landed = term.landWanted();
          term.wantSel = "";
          if (!landed && term.reAt >= 0)
            term.act.sel = Math.max(0,
              Math.min(term.reAt, term.act.view.length - 1));
        }
        term.reAt = -1;
        // ── THE CURSOR LANDS, IT DOES NOT TRAVEL ────────────────────
        // The rows under it are now a completely different set, so the
        // bar easing from wherever it was is easing between two places
        // that have nothing to do with each other — visibly, for a
        // frame or two, across a results list that just appeared.
        //
        // thawPulse is the existing way to say "re-seat without
        // travelling"; see its own note.
        term.thawPulse++;
        // ── AND THE BRANCHES, WHICH THE QUERY DOES NOT COVER ────────
        // The rows above are the TOP LEVEL. A row spliced in by opening a
        // directory came from that directory's own listing and nothing re-read
        // it, so deleting a file inside an expanded branch of a collection
        // left it on screen — while the directory above it correctly worked
        // out it was now empty and dropped its marker. Two halves of one
        // row set disagreeing, and re-opening the page did not help
        // because only the half that comes from the query was replaced.
        //
        // A directory listing has the watcher for this. A collection has
        // none — it is a snapshot of a question — so the moment its rows
        // land is the moment to refresh the other half too.
        //
        // HERE rather than in reCollect, so that OPENING a page repairs
        // branches left stale by an earlier visit as well; by this line
        // the tree is the new page's, so liveBranches names its branches
        // and not the ones we have just navigated away from.
        if (term.act.treed) term.rereadBranches(term.act.liveBranches());
        term.status = term.rows.length + " matches";
        Qt.callLater(term.positionSel);
      }
    }
  }
  function search(mode, query) {
    if (query === "") return;
    // WHERE YOU WERE, so Escape can put you back there.
    //
    // Results are a page of their own, not a directory: they come from all
    // over the tree and the cursor lands on whichever of them ranked first.
    // Leaving them used to re-list wherever you happened to be with the cursor
    // wherever the results had left it, so a search you decided against cost
    // you your place. Recorded only on the way IN, so refining a search twice
    // still returns to where the first one started.
    if (term.searchMode === "") {
      const r = term.currentRow();
      term.searchBackCwd = term.cwd;
      term.searchBackSel = r ? r.path : "";
      term.searchBackView = { view: term.viewMode, zoom: term.zoom,
                              thumbZoom: term.act.zoom };
    }
    term.searchMode = mode;
    term.searchQuery = query;
    // Held, for the reason openCollection gives: an empty listing between
    // two full ones is a flash, and the header already says what is going
    // on. The results replace these when they land.
    term.status = "searching…";
    term.runSearch();
  }
  // One search at a time, for the question as it stands NOW. A re-search
  // landing during a slow grep was a no-op restart, and the older query's
  // results were then shown under the new one — so they are only drawn when
  // the run is still the current question, and a run that was overtaken
  // makes way for one that is.
  function searchKey() { return term.searchMode + "\n" + term.searchQuery + "\n" + term.cwd; }
  function runSearch() {
    if (term.searchMode !== "find" && term.searchMode !== "grep") return;
    if (searchProc.running) { searchProc.again = true; return; }
    searchProc.askedKey = term.searchKey();
    searchProc.command = ["sh", "-c", term.searchMode === "grep"
      ? Terminus.grepCommand(term.cwd, term.searchQuery)
      : Terminus.findCommand(term.cwd, term.searchQuery)];
    searchProc.running = true;
  }
}
