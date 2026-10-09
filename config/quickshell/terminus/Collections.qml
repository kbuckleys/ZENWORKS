// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' collections … logic, out of TerminusWindow.qml
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
  id: collections
  property var term: null
  readonly property alias collSettle: collSettle

  FileView {
    id: collFile
    path: Quickshell.statePath("terminus-collections.json")
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: collFile.reload()
    onTextChanged: term.loadCollections()
  }
  function loadCollections() {
    const txt = String(collFile.text() || "");
    // ── A WRITE THAT CHANGES NOTHING IS NOT NEWS ──────────────────────
    // Every save comes back round through onTextChanged, and reassigning
    // the array from it rebuilt the whole Repeater. Opening one
    // collection did that TWENTY times, measured — each rebuild destroyed
    // the row holding the sidebar cursor and built a new one, so the
    // highlight flickered off and only settled a second or two later.
    // That is what "clicking it does not highlight it" was.
    if (txt === term.collRaw) return;
    term.collRaw = txt;
    try {
      const o = JSON.parse(txt || "[]");
      term.collections = Array.isArray(o) ? o : [];
    } catch (e) {
      term.collections = [];
    }
  }
  // Same re-read-before-write discipline the bookmarks and the tags use,
  // and for the same reason: a second window may have added one.
  function editCollections(mutate) {
    collFile.reload();
    collFile.waitForJob();
    let list;
    try {
      const o = JSON.parse(String(collFile.text() || "") || "[]");
      list = Array.isArray(o) ? o : [];
    } catch (e) { list = []; }
    mutate(list);
    term.collections = list;
    collFile.setText(JSON.stringify(list));
  }
  // Zoom used to be stored here too, and it could not be: the grid's zoom
  // is fitted to the pane, so applying a stored value produces a slightly
  // DIFFERENT actual value, which then reads as a change worth saving.
  // Measured converging one write at a time — 1.15026, 1.15227, 1.15392,
  // 1.15524 — and every one of those writes reloaded the file and rebuilt
  // every sidebar row underneath it, which is why the cursor took a second
  // to land on the row you had just clicked.
  //
  // A collection is a place with a shape, not a magnification. The pane's
  // zoom belongs to the pane and the directory records already keep it.
  function rememberCollectionView() {
    const f = term.collById(term.collOpenId);
    if (!f || f.view === term.viewMode) return;
    // An unsaved search keeps its view on itself, for as long as it lives.
    if (f.scratch) { f.view = term.viewMode; return; }
    // The built-in has no record on disk to write to — see recentsCollection.
    if (f.builtin) {
      term.recentsView = term.viewMode;
      term.viewSaveRef.restart();
      return;
    }
    term.editCollections((list) => {
      for (let i = 0; i < list.length; ++i)
        if (list[i].id === term.collOpenId) { list[i].view = term.viewMode; return; }
    });
  }
  // As a collection does — see rememberCollectionView. A tag page is a
  // listing you return to, and how you want it read is a fact about the
  // tag rather than about wherever you happened to be standing when you
  // opened it.
  function rememberTagView() {
    const name = term.openTagName;
    if (name === "") return;
    const cur = term.tagViews[name];
    if (cur && cur.view === term.viewMode) return;
    term.editTags((st) => {
      if (!st.views) st.views = ({});
      st.views[name] = { view: term.viewMode };
    });
  }
  // ALWAYS applied, never skipped. Returning early when a tag had no
  // stored view left the pane in whatever the last directory was using,
  // which is the opposite of what a separate place means: opening a tag
  // from a directory in grid gave you a grid, from a directory in columns gave
  // you columns, and the tag itself never had a view of its own at all.
  //
  // With nothing recorded it takes the default and WRITES IT, so from then
  // on the tag has an opinion of its own that nothing else can move.
  function applyTagView(name) {
    const v = term.tagViews[name];
    const want = (v && v.view && term.viewRing.indexOf(v.view) >= 0)
      ? v.view : Tags.DEFAULT_VIEW;
    term.applyDepth++;
    term.act.viewMode = want;
    Qt.callLater(() => { term.applyDepth = Math.max(0, term.applyDepth - 1); });
    if (!v) term.editTags((st) => {
      if (!st.views) st.views = ({});
      st.views[name] = { view: want };
    });
  }
  // Same rule as applyTagView, same reason: a view is applied every time,
  // whether or not one was stored, because "no opinion yet" must not mean
  // "use the last directory's". A collection that has never been arranged
  // takes the default and records it.
  function applyCollectionView(f) {
    if (!f) return;
    const want = (f.view && term.viewRing.indexOf(f.view) >= 0)
      ? f.view : Coll.DEFAULT_VIEW;
    // Under the same guard the directory views use, so applying one does
    // not immediately read as a change worth remembering.
    term.applyDepth++;
    term.act.viewMode = want;
    Qt.callLater(() => { term.applyDepth = Math.max(0, term.applyDepth - 1); });
    if (f.builtin) return;
    if (!f.view) term.editCollections((list) => {
      for (let i = 0; i < list.length; ++i)
        if (list[i].id === f.id) { list[i].view = want; return; }
    });
  }
  function searchScratch(f, q) {
    f.id = "search:" + Date.now();
    f.builtin = true;
    f.scratch = true;
    f.ink = "sand";
    f.name = q !== "" ? q : Coll.describe(f);
    // the results arrive in the view you were already reading in
    f.view = term.viewMode;
    term.scratchColl = f;
    term.goToCollection(f.id);
  }
  function collById(id) {
    if (id === term.recentsId) return term.recentsCollection;
    if (term.scratchColl && id === term.scratchColl.id) return term.scratchColl;
    for (let i = 0; i < term.collections.length; ++i)
      if (term.collections[i].id === id) return term.collections[i];
    return null;
  }
  function saveCollection(folder) {
    term.editCollections((list) => {
      for (let i = 0; i < list.length; ++i)
        if (list[i].id === folder.id) { list[i] = folder; return; }
      list.push(folder);
    });
  }
  function dropCollection(id) {
    term.editCollections((list) => {
      for (let i = list.length - 1; i >= 0; --i)
        if (list[i].id === id) list.splice(i, 1);
    });
  }
  // setsid, so the whole pipeline gets a process group of its own and
  // cancelling it takes fd, rg and xargs down together. Signalling the
  // Process alone would reach the shell and leave rg running over a home
  // directory, which is the one query here expensive enough to matter.
  Process {
    id: collProc
    property var folder: null
    stdout: StdioCollector {
      id: collOut
      waitForEnd: true
      onStreamFinished: {
        const f = collProc.folder;
        if (!f) return;
        // ── fd MARKS A DIRECTORY WITH A TRAILING SLASH ────────
        // Every other path in this window is bare, and a row carrying
        // "…/nest probe/" is a different string from the same directory
        // named anywhere else. It compared equal to nothing: joinPath made
        // "…/nest probe//new file", so a file created inside a directory in a
        // collection could never be found again — the cursor did not land
        // on it and its name never opened for editing. Nothing else
        // noticed, because within a collection the slashed form was used
        // consistently on both sides of every comparison.
        //
        // Stripped here, where fd's output stops being fd's output, rather
        // than at each of the places that would otherwise have to know.
        let paths = String(collOut.text || "").split("\u0000")
          .filter((p) => p !== "")
          .map((p) => (p.length > 1 && p.charAt(p.length - 1) === "/")
            ? p.slice(0, -1) : p);
        paths = Coll.applyTags(f, paths, term.tagMarks);
        term.finishCollection(paths);
      }
    }
  }
  function finishCollection(paths) {
    if (paths.length === 0) {
      // The one place the listing IS emptied: there is an answer now and
      // it is "nothing". See openCollection for why not before this.
      term.applyPendingRealm();
      term.act.raw = [];
      term.act.sel = 0;
      // This return skips statProc, which is where a re-ask's aim is
      // spent — see reCollect. Nothing to land on, so let them go.
      term.wantSel = "";
      term.reAt = -1;
      term.status = "nothing matches";
      return;
    }
    term.runStat(paths, paths);
  }
  // The same split goTo and enter already have. Everything a person
  // reaches for goes through here so the collection lands in history;
  // back() and forward() call openCollection directly, through travelTo,
  // because a step along the trail must not append to it.
  function goToCollection(id) {
    if (!term.collById(id)) return;
    term.pushTrail("c:" + id);
    term.openCollection(id);
  }
  function openCollection(id) {
    const f = term.collById(id);
    if (!f) return;
    if (term.searchMode === "") {
      const r = term.currentRow();
      term.searchBackCwd = term.cwd;
      term.searchBackSel = r ? r.path : "";
      term.searchBackView = { view: term.viewMode, zoom: term.zoom,
                              thumbZoom: term.act.zoom };
    }
    term.pendingRealm = { mode: "collection", query: f.name,
                          id: id, folder: f };
    // applyCollectionView is part of the switch and waits with it — see
    // applyPendingRealm.

    // A directory that asks only about tags is answered from the index, with
    // no process at all — the same shortcut openTag takes.
    if (Coll.tagsOnly(f)) {
      term.status = "\u2026";
      term.finishCollection(Coll.applyTags(f, Coll.allTagged(term.tagMarks),
                                       term.tagMarks));
      return;
    }

    const cmd = Coll.command(f, Paths.home());
    if (cmd === "") { term.status = "no rules yet"; return; }
    term.status = "searching\u2026";
    collProc.folder = f;
    collProc.running = false;
    collProc.command = ["setsid", "sh", "-c", cmd];
    collProc.running = true;
  }
  Timer {
    id: collSettle
    // The same coalescing the directory watcher uses, and for the same
    // reason: one paste is a burst of completions.
    interval: 250
    onTriggered: term.reSearch()
  }
  // Only a collection used to be: a find, a grep or a tag page kept showing
  // a file you had just deleted, renamed or moved, until you searched
  // again. Same landing as reCollect's — the row you were on, by path, or
  // by index when that row is the one that went.
  function reSearch() {
    const mode = term.searchMode;
    if (mode === "collection") { term.reCollect(); return; }
    if (mode !== "find" && mode !== "grep" && mode !== "tag") return;
    const r = term.currentRow();
    // an aim already set wins — see reCollect
    if (term.wantSel === "") term.wantSel = r ? r.path : "";
    term.reAt = term.act.sel;
    if (mode === "tag") term.openTag(term.openTagName);
    else term.search(mode, term.searchQuery);
  }
  function reCollect() {
    // collOpenId is -1 when nothing is open, never "" — the mode is the
    // real test and the only one needed.
    if (term.searchMode !== "collection") return;
    const f = term.collById(term.collOpenId);
    if (!f) return;
    // ── ARMED ONLY ONCE THE RE-ASK IS CERTAIN ───────────────────────
    // These two are consumed where the rows land, and a run that never
    // reaches that point leaves them set: wantSel in particular is the
    // armed aim the NEXT listing will take, so a collection that failed to
    // re-ask put the cursor on some unrelated row in the next directory
    // opened. Worked out first, armed after the last way out.
    const tagOnly = Coll.tagsOnly(f);
    const cmd = tagOnly ? "" : Coll.command(f, Paths.home());
    if (!tagOnly && cmd === "") return;
    // The row you were on, by path — the indices are about to move.
    // AND by index, because the commonest reason to re-ask is that the row
    // you were standing on has just been deleted: there is no path to come
    // back to, and dumping the cursor at the top of a hundred results is
    // the thing this whole function exists to avoid. Whatever slid into
    // that index is the right answer, which is what a directory listing
    // does too.
    //
    // AN AIM ALREADY SET WINS. commitRename points at the NEW name before
    // the command runs, and overwriting that with "where the cursor is"
    // landed a rename back on the index the old name had rather than on
    // the row it had just become.
    const r = term.currentRow();
    if (term.wantSel === "") term.wantSel = r ? r.path : "";
    term.reAt = term.act.sel;
    if (tagOnly) {
      term.finishCollection(Coll.applyTags(f, Coll.allTagged(term.tagMarks),
                                           term.tagMarks));
      return;
    }
    collProc.folder = f;
    collProc.running = false;
    collProc.command = ["setsid", "sh", "-c", cmd];
    collProc.running = true;
  }
  // Escape while one is still running. A content query over a large tree is
  // seconds of rg, and a page you have already decided against must not go
  // on costing.
  function cancelCollection() {
    if (!collProc.running) return;
    const pid = collProc.processId;
    if (pid > 0)
      Quickshell.execDetached(["sh", "-c", "kill -TERM -" + pid + " 2>/dev/null"]);
    collProc.running = false;
    collProc.folder = null;
  }
  // A fourth searchMode rather than a view of its own, because that is
  // exactly what it is: a set of paths from all over the tree, shown with
  // the WHERE column, not sorted, and left alone by the directory watcher.
  // Everything that already knows how to be a result page knows how to be
  // this one.
  //
  // And it needs no process. `find` and `rg` have to go and look; the index
  // already holds the answer, so this goes straight to the stat stage the
  // other two reach after their search has come back.
  function openTag(name) {
    if (name === "") return;
    if (term.searchMode === "") {
      const r = term.currentRow();
      term.searchBackCwd = term.cwd;
      term.searchBackSel = r ? r.path : "";
      term.searchBackView = { view: term.viewMode, zoom: term.zoom,
                              thumbZoom: term.act.zoom };
    }
    // The same deferral a collection gets — see applyPendingRealm. A tag
    // page needs no search, but it still needs a stat of every path, and
    // that is long enough to see the columns change shape on the old rows
    // and then the rows change under them.
    term.pendingRealm = { mode: "tag", query: name, tag: name };
    const paths = Tags.pathsWith(term.tagMarks, name);
    if (paths.length === 0) {
      // An answer, so the switch happens and the listing empties with it.
      term.applyPendingRealm();
      term.act.raw = [];
      term.act.sel = 0;
      term.status = "nothing tagged " + name;
      term.wantSel = "";
      term.reAt = -1;
      return;
    }
    term.status = "\u2026";
    term.runStat(paths, paths);
  }
  function clearSearch() {
    if (term.searchMode === "") return;
    // ── LEAVING ONE IS A STEP BACK, NOT A NEW PLACE ───────────────────
    // The entry below a collection in the trail is the directory this is
    // about to restore, so walking off the end of it is exactly one step
    // back. Without this the trail still pointed at the collection you had
    // just left and the first Back was spent going nowhere.
    const tp = term.act;
    if (term.searchMode === "collection" && tp.trailAt > 0
        && tp.trail[tp.trailAt] === ("c:" + term.collOpenId)) {
      term.markTrailSel();
      tp.trailAt -= 1;
    }
    // A collection may still be out there running rg. Leaving the page is
    // exactly when it stops being worth anything.
    term.cancelCollection();
    term.collOpenId = -1;
    term.searchMode = "";
    term.searchQuery = "";
    const backCwd = term.searchBackCwd;
    const backSel = term.searchBackSel;
    const backView = term.searchBackView;
    term.searchBackCwd = "";
    term.searchBackSel = "";
    term.searchBackView = null;
    if (backSel !== "") term.wantSel = backSel;
    // Under applyDepth, so putting the pane back the way it was is not
    // itself read as a change worth remembering against the directory.
    if (backView) {
      term.applyDepth++;
      if (backView.view && term.viewRing.indexOf(backView.view) >= 0)
        term.act.viewMode = backView.view;
      const z = Number(backView.zoom);
      if (!isNaN(z) && z > 0) term.zoom = term.zoomClamp(z);
      const tz = Number(backView.thumbZoom);
      if (!isNaN(tz) && tz > 0) term.act.zoom = term.zoomClamp(tz);
      Qt.callLater(() => { term.applyDepth = Math.max(0, term.applyDepth - 1); });
    }
    // THE STALE-LISTING GUARD HAS TO BE STOOD DOWN FIRST.
    //
    // Results replace `root.rows` without touching `lastListing`, so after a
    // search that guard still holds the text of the directory you searched
    // FROM. Escaping out of results re-lists that same directory, the output
    // matches byte for byte, and the "nothing changed" early return leaves the
    // RESULTS on screen — so Escape appeared to do nothing but drop the WHERE
    // column. null can never be a listing, which is the whole reason it is the
    // sentinel.
    term.act.lastListing = null;
    // A result you opened may have moved you somewhere else entirely, so this
    // is a navigation back rather than a re-listing of wherever you are.
    if (backCwd !== "" && backCwd !== term.cwd) {
      // enter() seeds itself from the remembered bytes — see there.
      term.enter(backCwd);
    } else {
      // ── SEEDED THE SAME WAY enter() IS ──────────────────────────────
      // This is the common escape: you opened the collection from the
      // directory you are going back to, so backCwd IS cwd and the
      // branch above does not run. refresh() then asks `find` and the
      // rows arrive a beat later — and in between, the results have
      // already gone and the columns have already changed shape. That
      // gap is the flash on the way OUT, mirroring the one on the way in.
      //
      // The bytes are still in listingText, so the directory can be put
      // back in the same frame the results leave. The refresh behind it
      // returns the identical bytes and recognises itself.
      const seed = term.listingText[term.cwd];
      if (seed !== undefined) {
        term.act.raw = term.enrich(Terminus.parseListing(seed, term.cwd));
        if (term.landWanted()) Qt.callLater(term.positionSel);
      }
      term.refresh(true);
    }
  }
}
