// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' tags … logic, out of TerminusWindow.qml
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
  id: tagging
  property var term: null

  FileView {
    id: tagFile
    path: Quickshell.statePath("terminus-tags.json")
    blockLoading: true
    printErrors: false
    // Same reason bookmarkFile watches: a second terminus window writing a
    // tag should show up here without a restart. And the same two-signal
    // dance — reload() only QUEUES the read, textChanged is where the bytes
    // actually land. See the long note on bookmarkFile.
    watchChanges: true
    onFileChanged: tagFile.reload()
    onTextChanged: term.loadTags()
  }
  function tagState() {
    try {
      const o = JSON.parse(String(tagFile.text() || "") || "{}");
      return {
        defs: Array.isArray(o.defs) ? o.defs : [],
        index: (o.index && typeof o.index === "object") ? o.index : ({}),
        // How each tag's page likes to be read, by tag name. A collection
        // keeps this on its own record; a tag has no record, so it lives
        // here beside the definitions.
        views: (o.views && typeof o.views === "object") ? o.views : ({}),
        // ── WHAT BECAME OF EACH OF THE SEVEN ─────────────────────────
        // Presets are offered whether or not anything uses them, which
        // made renaming one impossible to SEE: the files moved, the
        // definition moved, and the old name sat in the list exactly
        // where it had been, with the new one added underneath. A rename
        // that leaves both names on screen is a create, whatever it did
        // underneath.
        //
        // preset name -> what it is called now, or "" if it was
        // forgotten. The NAME rather than a bare "hidden" flag, because
        // the slot is the other half of reading as a rename: the row has
        // to change its wording where it stands, not vanish from the
        // fourth line and reappear at the bottom.
        gone: (o.gone && typeof o.gone === "object" && !Array.isArray(o.gone))
          ? o.gone : ({})
      };
    } catch (e) {
      // A corrupt file is not a reason to lose the session. The index
      // rebuilds from disk anyway, and defs is the only real casualty.
      return { defs: [], index: ({}), views: ({}), gone: ({}) };
    }
  }
  function loadTags() {
    // As loadCollections does, and for the same reason: tagMarks feeds
    // every row's dots and tagViews feeds the sidebar.
    const txt = String(tagFile.text() || "");
    if (txt === term.tagRaw) return;
    term.tagRaw = txt;
    const st = term.tagState();
    term.tagDefs = st.defs;
    term.tagMarks = st.index;
    term.tagViews = st.views;
    term.tagGone = st.gone;
  }
  // Every write goes through here and re-reads first, for the reason
  // editBookmarks does: the file is shared by every terminus window, so
  // "what I think it holds" is not what it holds. reload() queues, and
  // waitForJob() is what actually blocks until the bytes have landed.
  function editTags(mutate) {
    tagFile.reload();
    tagFile.waitForJob();
    const st = term.tagState();
    mutate(st);
    // In memory first, so the listing repaints on this frame; the write
    // comes back round through onTextChanged and re-derives the same thing.
    term.tagDefs = st.defs;
    term.tagMarks = st.index;
    term.tagViews = st.views;
    term.tagGone = st.gone;
    tagFile.setText(JSON.stringify(st));
  }
  // Answers with the PRESET whose place this name holds, or "" when the
  // name is the user's own. A renamed preset is still one of the seven:
  // `crimson` is where `red` lives now, and the lineup is fixed even when
  // its wording is not. Used to keep a default from being removed.
  function presetSlot(name) {
    if (name === "") return "";
    if (Tags.presetInk(name) !== "" && term.tagGone[name] === undefined)
      return name;
    for (const k in term.tagGone)
      if (term.tagGone[k] === name) return k;
    return "";
  }
  // A STORED COLOUR FIRST, then the seven that come with one, then a
  // fallback. The middle step is what lets "red" be red without anything
  // having been written to the state file — and the last is not a default
  // so much as a refusal to draw nothing: a tag another program wrote, or
  // one whose definition was lost, is still on the file and still has to
  // be visible.
  function tagInk(name) {
    for (let i = 0; i < term.tagDefs.length; ++i)
      if (term.tagDefs[i].name === name)
        return Zenon[term.tagDefs[i].ink] || Zenon.cyan;
    const preset = Tags.presetInk(name);
    if (preset !== "") return Zenon[preset] || Zenon.cyan;
    return Zenon.cyan;
  }
  function tagsFor(path) { return term.tagMarks[path] || []; }
  // Nothing in the delete, trash or rename paths ever touched the index, and
  // the one thing that prunes it — pruneTagIndex — can only drop a path a
  // stat run ASKED about. A file deleted out of a collection is gone from
  // that query's answer, so it is never asked about again and never pruned:
  // the sidebar goes on counting it, and "green 2" points at one file.
  //
  // A RESTART DOES NOT FIX IT either, though it looks as though it might:
  // loadTags re-reads the JSON and believes it. Only the palette's "reindex
  // tags" repairs it, by walking the disk.
  //
  // Both halves are cheap and exact at the moment the verb runs: it knows
  // which paths are about to stop existing, and which are about to become a
  // different path.
  function forgetTags(paths) {
    if (!paths || paths.length === 0) return;
    const hit = paths.filter((p) => term.tagMarks[p] !== undefined);
    // editTags reloads the shared file and waits for the write; not worth
    // paying for the overwhelmingly common case of untagged files.
    if (hit.length === 0) return;
    term.editTags((st) => {
      for (let i = 0; i < hit.length; ++i) delete st.index[hit[i]];
    });
  }
  // `pairs` is [[from, to], …]. The tag travels with the file: the xattr
  // moved with it on disk, so leaving the index behind would be the index
  // disagreeing with the truth it is a cache of.
  function moveTags(pairs) {
    if (!pairs || pairs.length === 0) return;
    const hit = pairs.filter((q) => term.tagMarks[q[0]] !== undefined);
    if (hit.length === 0) return;
    term.editTags((st) => {
      for (let i = 0; i < hit.length; ++i) {
        const v = st.index[hit[i][0]];
        if (v === undefined) continue;
        delete st.index[hit[i][0]];
        st.index[hit[i][1]] = v;
      }
    });
  }
  function pruneTagIndex(asked, rows) {
    if (!asked || asked.length === 0) return;
    const alive = ({});
    for (let i = 0; i < rows.length; ++i) alive[rows[i].path] = true;
    const gone = [];
    for (let j = 0; j < asked.length; ++j)
      if (!alive[asked[j]] && term.tagMarks[asked[j]]) gone.push(asked[j]);
    if (gone.length === 0) return;
    term.editTags((st) => {
      for (let k = 0; k < gone.length; ++k) delete st.index[gone[k]];
    });
  }
  // Named on the window so ipc can reach it: the sheet's own id is not
  // visible from the manager, which is where the handler has to live.
  function openTagPicker() { term.tagPickRef.ask(); }
  // `page` picks the tab: 0 properties, 1 permissions.
  function openProperties(page) {
    term.propsRef.ask();
    if (page === 1 && term.propsRef.hasPerms) term.propsRef.tab = 1;
  }
  function openCollectionEditor(id) { term.collEditRef.ask(id === undefined ? -1 : id); }
  // The attribute FIRST, the index after, and the index only for the files
  // the write actually reported success for. An index that records a tag the
  // file does not carry is worse than no index: it puts the file in the
  // sidebar listing, where clicking it finds nothing.
  Process {
    id: tagWriteProc
    property var pending: []
    // writes asked for while one is out, in order — see applyTagPairs
    property var queue: []
    // A preset name being put back into use — see applyTagPairs.
    property string homing: ""
    stderr: StdioCollector {
      id: tagWriteErr
      waitForEnd: true
      onStreamFinished: {
        const e = String(tagWriteErr.text || "").trim();
        if (e !== "") term.warn(e.split("\n")[0]);
      }
    }
    onExited: (code) => {
      if (code !== 0) {
        term.warn("could not tag");
        tagWriteProc.pending = [];
        tagWriteProc.homing = "";
        term.drainTagWrites();
        return;
      }
      const pairs = tagWriteProc.pending;
      const back = tagWriteProc.homing;
      term.editTags((st) => {
        for (let i = 0; i < pairs.length; ++i) {
          const e = pairs[i];
          if (e.names.length === 0) delete st.index[e.path];
          else st.index[e.path] = e.names;
        }
        // ── USING ONE OF THE SEVEN AGAIN BRINGS IT HOME ─────────────
        // A retired preset comes back into the list on its own the
        // moment a file carries it, because the list is built from the
        // tally as well as from the presets. It would come back at the
        // BOTTOM though, as a tag that merely shares a name with one of
        // the seven, and the row it used to occupy would stay missing.
        if (back !== "" && st.gone && st.gone[back] !== undefined)
          delete st.gone[back];
      });
      tagWriteProc.homing = "";
      tagWriteProc.pending = [];
      term.refresh();
      term.drainTagWrites();
    }
  }
  // `homing` names a tag that is being PUT ON something, so that one of
  // the seven can take its own place back — see the write's onExited.
  //
  // QUEUED, because what the exit records is `pending`: a second write asked
  // for while the first was out replaced it, the second command never ran
  // (`running = true` on a running Process is a no-op), and the index then
  // recorded tags that were never written to any file.
  function applyTagPairs(pairs, homing) {
    if (!pairs || pairs.length === 0) return;
    tagWriteProc.queue = tagWriteProc.queue.concat([{ pairs: pairs, homing: homing || "" }]);
    term.drainTagWrites();
  }
  function drainTagWrites() {
    if (tagWriteProc.running || tagWriteProc.queue.length === 0) return;
    const job = tagWriteProc.queue[0];
    tagWriteProc.queue = tagWriteProc.queue.slice(1);
    tagWriteProc.homing = job.homing;
    tagWriteProc.pending = job.pairs;
    tagWriteProc.command = ["sh", "-c", Tags.writeManyCommand(job.pairs)];
    tagWriteProc.running = true;
  }
  // One gesture both ways, across a whole selection — see Tags.toggleAcross
  // for why a mixed selection adds rather than flipping each row.
  function toggleTagFor(paths, name) {
    if (!paths || paths.length === 0) return;
    const r = Tags.toggleAcross(term.tagMarks, paths, name);
    term.applyTagPairs(r.pairs, r.added ? name : "");
    term.status = (r.added ? "tagged " : "untagged ")
      + paths.length + (paths.length === 1 ? " item" : " items");
  }
  // What every verb acts on: the marked set, or the row under the cursor.
  // acting() hands back ROWS, which is what the other verbs want; this one
  // only needs where they are.
  function toggleTagHere(name) {
    // The one verb that acts on the marked set without running anything,
    // so the chokepoints above never see it. toggleTagFor itself is left
    // alone: it is also the IPC entry point, called with an explicit path
    // that has nothing to do with what is ticked on screen.
    term.toggleTagFor(term.acting().map((r) => r.path), name);
    term.spendMarks();
  }
  function defineTag(name, ink) {
    const clean = Tags.normalise([name]);
    if (clean.length === 0) return;
    term.editTags((st) => {
      for (let i = 0; i < st.defs.length; ++i)
        if (st.defs[i].name === clean[0]) { st.defs[i].ink = ink; return; }
      st.defs.push({ name: clean[0], ink: ink });
    });
  }
  // Forgets the DEFINITION, and takes the tag off every file that carries it
  // — a tag dropped from the sidebar that left itself on forty files would
  // come back the next time the index was rebuilt.
  // Renaming writes every file that carries it — there is no central
  // record to edit — and then moves the definition so the colour follows.
  function renameTag(from, to) {
    const pairs = Tags.renamePairs(term.tagMarks, from, to);
    const want = Tags.normalise([to])[0] || "";
    if (from === "" || want === "" || want === from) return;
    // Carried onto the new name below, so a preset keeps its colour.
    // The NAME of the Zenon colour, not the colour: that is what a
    // definition stores and what tagInk resolves on the way out. Handing
    // it the resolved value made the lookup miss and every renamed preset
    // came out in the default cyan.
    const ink = Tags.presetInk(from) || "cyan";
    term.editTags((st) => {
      // The view follows the name, or the page you had arranged comes back
      // arranged differently for no reason you could point at.
      if (st.views && st.views[from] !== undefined) {
        if (st.views[want] === undefined) st.views[want] = st.views[from];
        delete st.views[from];
      }
      let moved = false;
      for (let i = 0; i < st.defs.length; ++i) {
        if (st.defs[i].name !== from) continue;
        // Straight onto the new name unless something already answers to
        // it, in which case the existing definition wins — the colour you
        // can see beside the tag you typed is the one you meant.
        const taken = st.defs.some((d) => d.name === want);
        if (taken) st.defs.splice(i, 1);
        else st.defs[i].name = want;
        moved = true;
        break;
      }
      // `from` had no definition of its own — a preset that files are
      // carrying — and those files are about to answer to `want`. Define
      // the new name with the colour they were wearing, or it arrives
      // with no ink and the row goes grey.
      if (!moved && !st.defs.some((d) => d.name === want))
        st.defs.push({ name: want, ink: ink });

      // ── AND THE ROW ITSELF CHANGES ITS NAME ──────────────────────
      // A definition was moved or removed above, so a tag of one's own
      // has already followed. A PRESET is not in the list because of a
      // definition — it is in the list because it is one of the seven —
      // so unless its slot is told what it is called now, the old name
      // stays put and the new one arrives as an extra row.
      if (!st.gone || Array.isArray(st.gone) || typeof st.gone !== "object")
        st.gone = ({});
      if (Tags.presetInk(from) !== "") st.gone[from] = want;
      // `from` may itself be what a preset was renamed to two renames
      // ago; the slot follows the chain rather than stopping at the
      // first name it was given.
      for (const k in st.gone)
        if (st.gone[k] === from) st.gone[k] = want;
      // And renaming something ONTO a preset's name brings it home.
      if (st.gone[want] !== undefined) delete st.gone[want];

      // A DEFINITION THAT ONLY RESTATES A PRESET IS NOT ONE. Coming home
      // leaves the travelling definition behind under the preset's own
      // name and its own colour, which records nothing — tagInk falls
      // through to exactly that answer with no definition at all. A
      // preset deliberately redefined in a DIFFERENT colour is a real
      // definition and stays.
      st.defs = st.defs.filter((d) => Tags.presetInk(d.name) !== d.ink);
    });
    if (pairs.length > 0) term.applyTagPairs(pairs);
    term.status = "renamed " + from + " \u2192 " + want;
  }
  // The sidebar lists a tag exactly while something wears it, so taking it
  // off the sidebar is taking it off those files. The definition stays — a
  // preset keeps its slot and its colour, a tag you made stays in the
  // picker — and the files stay where they are. Asked first, because it is
  // one click that reaches every file the tag is on.
  function clearTag(name) {
    const paths = Tags.pathsWith(term.tagMarks, name);
    if (paths.length === 0) return;
    term.confirmRef.ask("Clear " + name + "?",
      "it comes off " + paths.length + (paths.length === 1 ? " item" : " items")
        + " \u2014 the files themselves are untouched",
      "Clear", () => {
        term.applyTagPairs(paths.map((p) => ({
          path: p,
          names: (term.tagMarks[p] || []).filter((t) => t !== name)
        })));
        term.status = "cleared " + name;
      });
  }
  function dropTag(name) {
    // ── THE LINEUP IS FIXED ───────────────────────────────────────────
    // The seven can be renamed — that is a change of wording, and the
    // slot stays. Removing one is a change to the lineup itself, and the
    // lineup is not the user's to shorten: the colours are what a tag
    // picker offers on a machine where nothing has been tagged yet, and
    // a picker that can be emptied has nothing to offer. Caught here as
    // well as in the sheet so no other caller can get round it.
    if (term.presetSlot(name) !== "") {
      term.warn(name + " is a default tag");
      return;
    }
    const paths = Tags.pathsWith(term.tagMarks, name);
    const pairs = paths.map((p) => ({
      path: p,
      names: (term.tagMarks[p] || []).filter((t) => t !== name)
    }));
    term.editTags((st) => {
      st.defs = st.defs.filter((d) => d.name !== name);
      if (st.views) delete st.views[name];
    });
    term.applyTagPairs(pairs);
  }
  // The whole point of the index is that this does NOT run often. It is the
  // repair, for when something outside terminus has been moving tagged files
  // around, not part of startup.
  Process {
    id: tagScanProc
    // the directory this run is sweeping: only that part of the index is
    // the scan's to replace — see Tags.mergeScan
    property string root: ""
    stdout: StdioCollector {
      id: tagScanOut
      waitForEnd: true
      onStreamFinished: {
        const found = Tags.parseTagDump(tagScanOut.text);
        const under = tagScanProc.root;
        term.editTags((st) => { st.index = Tags.mergeScan(st.index, found, under); });
        term.status = "indexed " + Object.keys(found).length + " tagged";
      }
    }
  }
  function rebuildTagIndex(where) {
    // one sweep at a time: a second one started mid-run would be a no-op
    // restart, and its directory would be merged with the first one's answer
    if (tagScanProc.running) { term.status = "already indexing tags\u2026"; return; }
    term.status = "indexing tags\u2026";
    tagScanProc.root = where || Paths.home();
    tagScanProc.command = ["sh", "-c", Tags.scanTagsCommand(tagScanProc.root)];
    tagScanProc.running = true;
  }
}
