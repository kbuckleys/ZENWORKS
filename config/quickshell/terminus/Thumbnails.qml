// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' thumbnails … logic, out of TerminusWindow.qml
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
  id: thumbnails
  property var term: null
  readonly property alias thumbIndexSave: thumbIndexSave

  FileView {
    id: thumbIndexFile
    path: Thumbs.indexPath()
    blockLoading: true
    // It does not exist until the first save, and saying so on every cold
    // start is noise about a cache doing exactly what a cache does.
    printErrors: false
    // NOT WATCHED, unlike the bookmarks. Every window writes this one and
    // none of them needs the others' news on the frame it lands: a miss
    // costs one md5sum, and watching would have every window re-parse the
    // whole index every time any window finished a batch.
    onTextChanged: term.loadThumbIndex()
  }
  function loadThumbIndex() {
    let o = null;
    try { o = JSON.parse(String(thumbIndexFile.text() || "{}")); } catch (e) { o = null; }
    term.thumbIndex = (o && typeof o === "object" && !Array.isArray(o)) ? o : ({});
  }
  // What the shell named this file last time, if the file is still that
  // file. Size and mtime are two thirds of what the key was made from, and
  // the row carries both — so this is the whole check, and it is free.
  function indexHit(r) {
    const e = term.thumbIndex[r.path];
    if (typeof e !== "string") return "";
    const p = e.split("|");
    if (p.length !== 3) return "";
    // The key is made from `stat -c %Y`, a whole second; the row's mtime is
    // a float off the same stat. Compare what the hash actually saw.
    if (Number(p[0]) !== r.size || Number(p[1]) !== Math.floor(r.mtime)) return "";
    // Either a thumbnail, or the standing answer that there will not be
    // one. Both are answers; only the empty string means "ask".
    return Thumbs.isNone(p[2]) ? Thumbs.none() : Thumbs.fileFor(p[2]);
  }
  // thumbFile is keyed by PATH, and it lives as long as the shell does —
  // days. The index beside it checks size and mtime; the map never did. So
  // once a path held one file and later another (a recording saved as
  // shadows.mp4, renamed away, and a new one saved under the old name),
  // every "is there a thumbnail?" said yes, nothing was made, and quick look
  // drew the OLD film's frame under the new one playing. Renaming made it
  // go away — a new path, no entry — and renaming back brought it back.
  //
  // So a mapped thumbnail counts only while the index still vouches for
  // this version of the file. One that does not is dropped here, and the
  // caller goes on to make a new one exactly as if there had been none.
  // A row with no stat (nothing to compare) is trusted as before.
  function thumbHas(r) {
    if (!r || !term.thumbFile[r.path]) return false;
    if (typeof r.size !== "number" || typeof r.mtime !== "number") return true;
    const e = term.thumbIndex[r.path];
    if (typeof e === "string") {
      const p = e.split("|");
      if (p.length === 3 && Number(p[0]) === r.size
          && Number(p[1]) === Math.floor(r.mtime)) return true;
    }
    const c = Object.assign({}, term.thumbFile);
    delete c[r.path];
    term.thumbFile = c;
    if (term.thumbIndex[r.path] !== undefined) {
      const ix = Object.assign({}, term.thumbIndex);
      delete ix[r.path];
      term.thumbIndex = ix;
      thumbIndexSave.restart();
    }
    return false;
  }
  // The one-off job every "make this row's picture now" site builds, WITH
  // the stat the index needs. Without it the index recorded
  // "undefined|undefined|key", which no check can ever match — so anything
  // first seen outside the grid could never be vouched for.
  function thumbJob(r, kind) {
    return { src: r.path, kind: kind, sz: r.size, mt: Math.floor(r.mtime) };
  }
  function thumbMiss(r) {
    if (!r) return;
    // a tile can be showing the INDEX's answer before thumbFile holds it
    // (Tile.onDisk) — a dead one of those is dropped the same way
    const seen = term.thumbFile[r.path] ? "" : term.indexHit(r);
    const bad = term.thumbFile[r.path] || (Thumbs.isNone(seen) ? "" : seen);
    if (!bad) return;
    const c = Object.assign({}, term.thumbFile);
    delete c[r.path];
    term.thumbFile = c;
    const ix = Object.assign({}, term.thumbIndex);
    if (ix[r.path] !== undefined) {
      delete ix[r.path];
      term.thumbIndex = ix;
      thumbIndexSave.restart();
    }
    if (term.thumbMissed[r.path]) return;
    const m = Object.assign({}, term.thumbMissed);
    m[r.path] = true;
    term.thumbMissed = m;
    // only ever a file in the pool — never whatever else a claim might name
    if (String(bad).indexOf(Thumbs.dir() + "/") === 0)
      Quickshell.execDetached(["rm", "-f", "--", bad]);
    term.splitPaneRef.thumbRetry.restart();
  }
  // Coalesced: a directory of pictures lands in batches of 150 and each one
  // would otherwise rewrite the whole file.
  Timer {
    id: thumbIndexSave
    interval: 1500
    repeat: false
    onTriggered: term.saveThumbIndex()
  }
  function saveThumbIndex() {
    // MERGED, not overwritten. Every terminus window writes this file and
    // each one holds only the directories it happened to look at, so a
    // straight write would drop whatever the others had learned. Same
    // argument as editBookmarks, and the same re-read to settle it.
    thumbIndexFile.reload();
    thumbIndexFile.waitForJob();
    let disk = null;
    try { disk = JSON.parse(String(thumbIndexFile.text() || "{}")); } catch (e) { disk = null; }
    const out = (disk && typeof disk === "object" && !Array.isArray(disk)) ? disk : ({});
    for (const k in term.thumbIndex) out[k] = term.thumbIndex[k];
    // Oldest first: a plain object iterates in insertion order, which is
    // close enough to least-recently-learned for a cache index.
    const keys = Object.keys(out);
    if (keys.length > term.thumbIndexCap) {
      const drop = keys.length - term.thumbIndexCap;
      for (let i = 0; i < drop; ++i) delete out[keys[i]];
    }
    term.thumbIndex = out;
    thumbIndexFile.setText(JSON.stringify(out));
  }
  // ── THE LAST SCREENFULS STAY DECODED — see ThumbKeeper ────────────────
  ThumbKeeper { id: keeper }
  function keepThumb(url) { keeper.keep(url); }

  function noteBlind(name) {
    const n = String(name);
    const cut = n.lastIndexOf(".");
    if (cut <= 0) return;
    const e = n.slice(cut + 1).toLowerCase();
    if (term.blindExt[e]) return;
    const next = Object.assign({}, term.blindExt);
    next[e] = true;
    term.blindExt = next;
  }
  // Whether this file has to go the long way round.
  function needsRender(r) {
    return !!r && !r.isDir && Terminus.isImage(r.name)
      && (Terminus.qtBlind(r.name) || term.blindExt[Terminus.extOf(r.name)] === true);
  }
  // Which of thumbs.js' kinds makes this row's picture, or "" for none. A
  // picture Qt cannot open is `f`, not `i`: thumb.py lays its transparency
  // over a checkerboard, where `i` refuses anything with alpha on the grounds
  // that Qt can show the original — which for these it cannot, so a psd
  // with one transparent pixel showed its glyph forever.
  function thumbKind(r) {
    if (!r || r.isDir) return "";
    if (Terminus.isVideo(r.name)) return "v";
    if (Terminus.isAudio(r.name)) return "a";
    if (term.needsRender(r)) return "f";
    if (Terminus.isImage(r.name)) return "i";
    if (Terminus.docThumb(r.name)) return "d";
    return "";
  }
  Process {
    id: thumbProc
    // What the batch actually MADE, not what it was asked for.
    //
    // This used to mark every job it sent, which was near enough true while
    // the jobs were only pictures and videos. Audio broke it: a track with no
    // cover art produces no file, so the preview pointed an Image at a path
    // that was never written and Qt logged "Cannot open" for it on every
    // visit. The batch now prints the source of each thumbnail that exists
    // when it finishes, and only those are marked.
    // ── AS EACH ONE LANDS, NOT WHEN THE BATCH DOES ───────────────────
    // The batch is 150 pictures (see thumbBatch) and the grid used to hear
    // about none of them until the last was made — a big directory sat on its
    // glyphs for seconds at a time, then filled 150 at once. Each line is a
    // thumbnail that now exists; they are gathered and handed over every
    // few frames (thumbFlush), so the grid fills in as the work is done
    // without rebuilding the map once per picture.
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => {
        const cut = line.indexOf("\t");
        if (cut <= 0) return;
        term.thumbPending[line.slice(0, cut)] = line.slice(cut + 1);
        if (!term.thumbFlushRef.running) term.thumbFlushRef.start();
      }
    }
    // ── AND THE NEXT BATCH, IF THERE IS ONE ──────────────────────────
    // See thumbBatch for why a directory of pictures arrives in pieces.
    onExited: {
      term.thumbFlushRef.stop();
      term.takeThumbs();
      term.thumbJobs = [];
      if (term.thumbQueue.length > 0) Qt.callLater(term.runThumbBatch);
    }
  }
  function takeThumbs() {
    const made = term.thumbPending;
    let any = false;
    for (const k in made) { any = true; break; }
    if (!any) return;
    term.thumbPending = ({});
    const c = Object.assign({}, term.thumbFile);
    const o = term.thumbOrder.slice();
    for (const k in made) {
      // A source generate declined — transparency, which JPEG cannot
      // hold. There is no file to point at; the tile goes on showing
      // the picture itself, exactly as it does for anything uncached.
      if (Thumbs.isNone(made[k])) continue;
      if (c[k] === undefined) o.push(k);
      c[k] = made[k];
    }
    while (o.length > term.thumbCap) delete c[o.shift()];
    term.thumbFile = c;
    term.thumbOrder = o;
    // AND WRITTEN DOWN. The jobs carry the size and mtime the key was
    // made from, so the next visit can check the claim without asking
    // the disk again — see makeThumbs and indexHit. The refusal is worth as
    // much as an answer, and costs more to reach: deciding it is a full
    // decode of the source. Recorded, it happens once for this version.
    const ix = Object.assign({}, term.thumbIndex);
    let add = 0;
    for (const j of term.thumbJobs) {
      const t = made[j.src];
      if (!t) continue;
      const key = Thumbs.isNone(t) ? Thumbs.none() : Thumbs.keyOf(t);
      if (key === "") continue;
      ix[j.src] = j.sz + "|" + j.mt + "|" + key;
      ++add;
    }
    if (add > 0) { term.thumbIndex = ix; thumbIndexSave.restart(); }
  }
  // ONE THUMBNAIL NOW, for the one row somebody is looking at — the preview
  // pane, quick look, Properties. Put at the FRONT of the queue the grid
  // uses rather than started on its own: four copies of this used to set
  // thumbJobs and start thumbProc directly, and while a grid batch was out
  // that replaced the batch's jobs (so its index entries were lost) and the
  // start itself was a no-op, so the one-off never ran either.
  function thumbNow(job) {
    job.now = true;
    term.thumbQueue = [job].concat(term.thumbQueue.filter((j) => j.src !== job.src));
    term.runThumbBatch();
  }
  function runThumbBatch() {
    if (thumbProc.running) { term.splitPaneRef.thumbRetry.restart(); return; }
    const q = term.thumbQueue;
    if (q.length === 0) return;
    const batch = q.slice(0, term.thumbBatch);
    term.thumbQueue = q.slice(term.thumbBatch);
    term.thumbJobs = batch;
    thumbProc.command = ["sh", "-c", Thumbs.generate(batch)];
    thumbProc.running = true;
  }
  // Quick look's own renderer. Separate from thumbProc so a 1600px raw
  // cannot hold up the grid's batch behind it.
  Process {
    id: bigProc
    stdout: StdioCollector {
      id: bigOut
      waitForEnd: true
      onStreamFinished: {
        const made = Thumbs.parseMade(bigOut.text);
        const c = Object.assign({}, term.bigFile);
        for (const k in made) c[k] = made[k];
        term.bigFile = c;
      }
    }
  }
  function wantBig(r) {
    if (!term.needsRender(r)) return;
    const stamp = r.size + "|" + Math.floor(r.mtime);
    if (term.bigFile[r.path] && term.bigStamp[r.path] !== stamp) {
      const c = Object.assign({}, term.bigFile);
      delete c[r.path];
      term.bigFile = c;
    }
    if (term.bigFile[r.path] || bigProc.running) return;
    term.bigStamp[r.path] = stamp;
    bigProc.command = ["sh", "-c",
      Thumbs.generate([{ src: r.path, kind: "f" }], true)];
    bigProc.running = true;
  }
  function makeThumbs() {
    // BOTH panes, because either can be the grid. The second pane's tiles
    // read the same cache and would otherwise sit on their glyphs forever
    // while the pane beside them was full of pictures.
    let want = [];
    if (term.viewMode === "grid") want = want.concat(term.view);
    if (term.dual && term.otherViewMode === "grid")
      want = want.concat(term.otherRows);
    if (want.length === 0) return;
    term.primeThumbs(want);
  }
  // The row-walk, shared with the warm below: resolve what the index
  // already knows, and queue only what it does not.
  function primeThumbs(want) {
    const jobs = [];
    // ── THE INDEX ANSWERS FIRST, AND IT ANSWERS NOW ─────────────
    // Before this, a directory whose thumbnails were ALL on disk still
    // waited on a process: naming them costs a stat and an md5sum each,
    // 0.49s for 481 files, in serial batches of 150 — which is exactly
    // the trickle of pictures filling in that a cache is supposed to
    // prevent. The names were known the first time and thrown away.
    //
    // Now they are kept, and checked here against the row's OWN stat.
    // No process, no wait: a revisited directory is complete on the frame
    // it is drawn.
    const hits = ({});
    let got = 0;
    for (const r of want) {
      if (r.isDir) continue;
      // Audio joins the grid for the same reason it joined the preview: a
      // directory of albums is a directory of covers, and showing eight identical
      // note glyphs is showing nothing. A track without art keeps its glyph.
      const kind = term.thumbKind(r);
      if (kind === "") continue;
      if (term.thumbHas(r)) continue;
      const seen = term.indexHit(r);
      // A standing "none" for an f or d file is a verdict from before
      // thumb.py could make one — the old alpha refusal, or a document
      // nothing rendered. Asked again; neither kind ever records "none", so
      // this cannot repeat.
      if (Thumbs.isNone(seen) && (kind === "f" || kind === "d")) {
        jobs.push({ src: r.path, kind: kind, sz: r.size, mt: Math.floor(r.mtime) });
        continue;
      }
      if (seen !== "") {
        // NONE is an answer too: nothing to map, and nothing to ask for.
        if (!Thumbs.isNone(seen)) { hits[r.path] = seen; ++got; }
        continue;
      }
      jobs.push({ src: r.path, kind: kind, sz: r.size, mt: Math.floor(r.mtime) });
    }
    if (got > 0) {
      const c = Object.assign({}, term.thumbFile);
      const o = term.thumbOrder.slice();
      for (const k in hits) { if (c[k] === undefined) o.push(k); c[k] = hits[k]; }
      while (o.length > term.thumbCap) delete c[o.shift()];
      term.thumbFile = c;
      term.thumbOrder = o;
    }
    if (jobs.length === 0) return;
    // A batch already running is not a reason to skip: it may have been asked
    // for the OTHER pane's rows, and dropping this request left the pane you
    // just stepped into showing glyphs. Deferred rather than dropped.
    //
    // BELOW the index lookup, not above it. Nothing up there needs a
    // process, and returning early meant a directory you stepped into while
    // another pane's batch was still running showed glyphs for everything
    // it already had on disk.
    if (thumbProc.running) { term.splitPaneRef.thumbRetry.restart(); return; }
    // Queued rather than run: the list may be longer than one command can
    // carry — see thumbBatch. A new directory's batch replaces the old one's,
    // but not a one-off still waiting for the row somebody is looking at.
    const srcs = ({});
    for (const j of jobs) srcs[j.src] = true;
    term.thumbQueue = term.thumbQueue.filter((j) => j.now && !srcs[j.src]).concat(jobs);
    term.runThumbBatch();
  }
}
