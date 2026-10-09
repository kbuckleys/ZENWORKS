// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' holding your place … logic, out of TerminusWindow.qml
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
  id: preview
  property var term: null
  readonly property alias previewDelay: previewDelay
  readonly property alias scrollHoldExpiry: scrollHoldExpiry

  // THE MODEL IS AN ARRAY, and handing a view a new one is a full reset: Qt
  // rebuilds every delegate and, often enough, drops the scroll to zero.
  // Measured in /tmp, which changes every second or two — contentY went 784
  // to 0, then 2352 to 0, on refreshes that moved no cursor and asked for no
  // repositioning. Anything you had scrolled to was gone, and the row under
  // the pointer with it.
  //
  // The proper cure is a model the view can be told about incrementally
  // rather than handed wholesale, which is a much larger change than this
  // window wants right now. Putting the offset back is the small one, and it
  // is what the symptom actually asks for.
  function keepScroll() {
    return { list: term.actList.contentY, mid: term.midCol.view.contentY,
             parent: term.parCol.view.contentY, grid: term.actGrid.contentY };
  }
  // A toggle that never reached a landing must not leave its view armed for
  // some later, unrelated move to snap back to.
  Timer {
    id: scrollHoldExpiry
    interval: 1500
    onTriggered: term.scrollHold = null
  }
  function settleScroll() {
    if (term.scrollHold) {
      const k = term.scrollHold;
      term.scrollHold = null;
      Qt.callLater(term.restoreScroll, k);
    } else term.positionSel();
  }
  function restoreScroll(keep) {
    if (!keep) return;
    term.putScroll(term.actList, keep.list);
    term.putScroll(term.midCol.view, keep.mid);
    term.putScroll(term.parCol.view, keep.parent);
    term.putScroll(term.actGrid, keep.grid);
  }
  // Clamped, because the listing that came back may be shorter than the one
  // that went in — scrolled to the bottom of a directory that just lost forty
  // rows, the old offset is past the end of the new one.
  function putScroll(v, y) {
    if (!v || y === undefined || y === v.contentY) return;
    const most = Math.max(0, v.contentHeight - v.height);
    v.contentY = Math.max(0, Math.min(most, y));
  }
  // Headings are a list-view idea — see root.grouped — so asking for them
  // anywhere else says so and changes nothing: the switch in the settings
  // panel and the menu's entry are muted there too.
  function toggleGrouped() {
    if (term.viewMode !== "list") {
      term.status = "headings: list view only";
      return;
    }
    term.grouped = !term.grouped;
    term.rememberView();
    term.openingRef.viewSave.restart();
    term.status = term.grouped ? "headings on" : "headings off";
  }
  // Finder's model exactly. Going right: a closed directory opens, an open one
  // hands you its first child, a file does nothing. Going left: an open
  // directory closes, and anything else steps out to whatever contains it.
  //
  // The left-hand fallback at the top level is goUp, not nothing. Finder
  // has a column of chrome to climb out through and this does not, so a key
  // whose whole meaning is "outwards" should keep meaning that when the
  // tree runs out — otherwise the one place left stops working is the place
  // you use it most.
  function treeStepKey(deeper) {
    const r = term.currentRow();
    if (!r) return;
    const pane = term.act;

    if (deeper) {
      if (!r.isDir) return;
      if (!pane.isOpen(r.path)) { pane.setOpen(r.path, true); return; }
      // Already open: step onto the first thing inside it. The children sit
      // directly under it in the flattened view, so this is the next row —
      // unless the directory is empty, in which case there is nothing to step
      // onto and the cursor stays put.
      const v = pane.view;
      const at = pane.sel;
      if (at + 1 < v.length
          && String(v[at + 1].path).indexOf(r.path + "/") === 0) {
        pane.sel = at + 1;
        term.setAnchor(pane.sel);
        term.positionSel();
      }
      return;
    }

    if (r.isDir && pane.isOpen(r.path)) { pane.setOpen(r.path, false); return; }
    // Outwards. The row's own directory is its parent in the tree; when
    // that is the listing itself there is no parent row to land on, so the
    // only way further out is up.
    const owner = Terminus.dirname(r.path);
    if (owner === pane.cwd || owner === "") { term.goUp(); return; }
    term.wantSel = owner;
    if (term.landWanted()) term.positionSel();
    else term.wantSel = "";
  }
  // Shut every branch at once. The counterpart to opening them one at a
  // time, and the way out of a tree that has grown past being useful.
  function collapseAll() {
    let any = false;
    for (const k in term.act.openDirs) { any = true; break; }
    if (!any) { term.status = "nothing expanded"; return; }
    // The cursor may be standing inside one of them — put it on the row
    // that is about to become the deepest thing still on screen.
    // The cursor may be standing inside one of them. Ask for the row it was
    // on; if that row has just been folded away, walk up its path until
    // something still on screen answers — which is the branch it lived in.
    let want = term.currentRow() ? term.currentRow().path : "";
    term.act.writeOpen(({}));
    while (want !== "" && want !== term.cwd) {
      term.wantSel = want;
      if (term.landWanted()) break;
      want = Terminus.dirname(want);
    }
    term.wantSel = "";
    term.positionSel();
    term.status = "collapsed";
  }
  // originY is where a view reckons its first row lives, and it DRIFTS:
  // syncView replaces rows in place rather than clearing — deliberately,
  // so delegates are not rebuilt — and a wholesale replacement while the
  // view is scrolled leaves the origin where the old rows were.
  //
  // Measured after stepping into a directory, back out, and into another:
  // 11 rows, contentHeight 1012, contentY 46 — and the first delegate at
  // y 1038. The viewport covered 46 to 1012 and every row was below it.
  // The grid was not missing a cursor, it was drawing an empty region of
  // itself; the cursor was the only thing still in view, which is what
  // made it look like the opposite.
  //
  // So the bounds are relative to the origin, not to zero. Clamping
  // against 0 — as this did — agreed that 46 was a fine place to be.
  function snapInBounds(v) {
    if (!v) return;
    const lo = v.originY;
    const hi = Math.max(lo, lo + v.contentHeight - v.height);
    if (v.contentY > hi) v.contentY = hi;
    else if (v.contentY < lo) v.contentY = lo;
  }
  function positionSel() {
    // Into bounds BEFORE positioning: Contain is a no-op from out here,
    // so asking it to fix this is asking the wrong question.
    term.snapInBounds(term.actList);
    term.snapInBounds(term.actGrid);
    term.actList.positionViewAtIndex(term.sel, ListView.Contain);
    term.midCol.view.positionViewAtIndex(term.sel, ListView.Contain);
    term.actGrid.positionViewAtIndex(term.sel, GridView.Contain);
  }
  // A LISTING'S BYTES, ARRANGED THE WAY THIS WINDOW ARRANGES LISTINGS. The
  // middle column, the left column and the preview all turn `find` output
  // into rows, and all three had their own copy of the same four calls. One
  // of them is also what lets a column be filled from the remembered bytes
  // rather than from a process — see seedParent and the preview.
  function rowsFromListing(text, dir) {
    return term.enrich(Terminus.sortEntries(
      Terminus.filterEntries(Terminus.parseListing(text, dir), "",
                             term.showHidden, term.portalGhost),
      term.sortKey, term.sortDesc, term.dirsFirst, term.naturalSort,
      term.tagMarks));
  }
  // THE COLUMN YOU CAME FROM IS ALWAYS ALREADY KNOWN. Entering a directory
  // makes its parent the directory you were just standing in, and every
  // listing this window reads is remembered as the bytes it came back as —
  // so the left column can be drawn in the same frame as the step instead of
  // a process later. Without this it went on showing the GRANDPARENT until
  // `find` answered, which is the list that flashed on the way in.
  function seedParent() {
    if (term.cwd === "/") { term.parentRows = []; term.parentListing = null; return; }
    const dir = term.parentOf(term.cwd);
    const seen = term.listingText[dir];
    if (seen === undefined || seen === term.parentListing) return;
    term.parentListing = seen;
    term.parentRows = term.rowsFromListing(seen, dir);
  }
  Process {
    id: parentProc
    // the directory this run is listing — the listing is filed under THAT,
    // never under whatever the parent is by the time it lands
    property string listFor: ""
    property bool again: false
    onExited: if (parentProc.again) { parentProc.again = false; Qt.callLater(term.startParent); }
    stdout: StdioCollector {
      id: parentOut
      waitForEnd: true
      onStreamFinished: {
        const dir = parentProc.listFor;
        // true about `dir` whatever has happened since, so it is kept
        term.rememberListing(dir, parentOut.text);
        // A listing for a directory we have since left the root of — same
        // guard as the launch above, for an answer that was already in flight.
        if (term.cwd === "/") { term.parentRows = []; term.parentListing = null; return; }
        // and a parent we have since stopped being under is not drawn
        if (dir !== term.parentOf(term.cwd)) return;
        // Byte-identical to what the column is already drawing — which is the
        // ordinary case now that it is seeded, since the seed IS the bytes
        // this process was about to return. Rebuilding every row to arrive at
        // the same rows is the redraw this guard exists to refuse.
        if (parentOut.text === term.parentListing) return;
        term.parentListing = parentOut.text;
        term.parentRows = term.rowsFromListing(parentOut.text, dir);
        Qt.callLater(() => term.parCol.view.positionViewAtIndex(term.parentIndex, ListView.Contain));
      }
    }
  }
  // The parent's listing, one at a time. Moving fast re-armed this while a
  // listing was out: the re-arm did nothing, and the old parent's answer was
  // filed under the NEW parent's path — seeding later visits and previews of
  // that directory with another directory's contents.
  function startParent() {
    if (term.cwd === "/") return;
    if (parentProc.running) { parentProc.again = true; return; }
    parentProc.listFor = term.parentOf(term.cwd);
    parentProc.command = ["sh", "-c", Terminus.listCommand(parentProc.listFor)];
    parentProc.running = true;
  }
  function rememberListing(dir, text) {
    if (!dir || dir === "" || text.length > 65536) return;
    const c = Object.assign({}, term.listingText);
    const o = term.listingOrder.slice();
    if (c[dir] === undefined) o.push(dir);
    c[dir] = text;
    while (o.length > 16) delete c[o.shift()];
    term.listingText = c;
    term.listingOrder = o;
  }
  function cachePreview(path, entry) {
    const c = Object.assign({}, term.previewCache);
    const o = term.previewOrder.slice();
    // ONLY IF IT IS NEW, the rule cacheInfo and the thumbnail cache both
    // follow and this one did not. Re-previewing a file you have already
    // seen pushed its path a second time, so the order list filled with
    // duplicates and the eviction below started shifting off names that
    // were still live — the cache held 24 slots and fewer and fewer
    // distinct files, which is why walking back over the same directory kept
    // paying for previews it had already made.
    const fresh = c[path] === undefined;
    c[path] = entry;
    if (fresh) o.push(path);
    while (o.length > 24) delete c[o.shift()];
    term.previewCache = c;
    term.previewOrder = o;
  }
  function prefEnrol(item) {
    const a = term.prefRows.slice();
    a.push(item);
    term.prefRows = a;
  }
  function prefOrder() {
    const rows = term.prefRows.slice();
    rows.sort((a, b) => {
      const pa = a.mapToItem(term.prefsRef.prefsCol, 0, 0);
      const pb = b.mapToItem(term.prefsRef.prefsCol, 0, 0);
      // The column first — a row in the left one comes before every row in the
      // right, however far down it sits. Compared with a tolerance because the
      // two columns are placed by arithmetic on the sheet's width and need not
      // land on whole pixels.
      if (Math.abs(pa.x - pb.x) > 1) return pa.x - pb.x;
      return pa.y - pb.y;
    });
    term.prefRows = rows;
  }
  function prefAt() {
    return (term.prefCursor >= 0 && term.prefCursor < term.prefRows.length)
      ? term.prefRows[term.prefCursor] : null;
  }
  // Past anything not reachable — the one action row switches itself off when
  // there is nothing left to forget — and bounded by the list's own length so
  // a panel of nothing reachable cannot spin.
  function prefStep(d) {
    const n = term.prefRows.length;
    if (n === 0) return;
    let i = term.prefCursor;
    for (let t = 0; t < n; t++) {
      i = (i + d + n) % n;
      if (term.prefRows[i].reachable) break;
    }
    term.prefCursor = i;
  }
  function quickLook() {
    const r = term.currentRow();
    // ── A DIRECTORY IS WORTH LOOKING AT TOO ──────────────────────────────
    // This refused directories outright, on the reasoning that a directory
    // is a thing you go into rather than look at. Finder disagrees, and
    // so does the pointer: stepping through a directory with space held
    // open, every directory was a hole in the sequence. What is IN it is
    // exactly what you wanted to know without going there.
    if (!r) return;
    term.lookFetch();
    term.looking = true;
  }
  // Split out of quickLook and called again on every step, because the arrows
  // walk the listing underneath and each file that arrives may need something
  // nobody has made yet. Run once on the way in, flicking from a picture to
  // the PDF beside it showed the apology for a page that had never been
  // rendered — see lookLayer.look.onRowChanged.
  //
  // Every branch asks first whether the thing it makes is already there, so
  // calling this on a row that needs nothing costs a handful of lookups.
  function lookFetch() {
    const r = term.currentRow();
    if (!r) return;

    // A DIRECTORY'S CONTENTS, through the same funnel the pane uses. The
    // bytes of the last sixteen listings are already remembered, so a
    // directory you have just walked past costs no process at all.
    if (r.isDir) {
      if (r.path === term.previewShown || r.path === term.previewFor) return;
      const seen = term.listingText[r.path];
      if (seen !== undefined) {
        term.settlePreview("dir", term.rowsFromListing(seen, r.path), "", r.path);
        return;
      }
      const hit = term.previewCache[r.path];
      if (hit !== undefined) {
        term.settlePreview(hit.kind, hit.rows, hit.text, r.path);
        return;
      }
      term.previewKind = "dir";
      term.beginPeek(r.path, Terminus.peekCommand(r.path));
      return;
    }
    // THE SHARP COPY, and this is the one place that wants one. The pane
    // takes whatever the grid made at 480; here somebody has asked to look
    // at this file in particular, which is exactly when soft stops being
    // good enough. Called per row, so walking a directory of raws with space
    // held renders each as it arrives.
    term.wantBig(r);
    // A film whose frame has not been pulled yet: ask for it now. This is the
    // one moment somebody is actually looking, so it is the one moment worth
    // making them wait a beat for.
    // A picture Qt cannot open needs the same one-off: the grid builds these
    // for every row it shows, but a LIST never calls makeThumbs, so in a list
    // the preview pane would have nothing to point at.
    if (!term.thumbHas(r)
        && (Terminus.isVideo(r.name) || Terminus.isAudio(r.name)
            || term.needsRender(r))) {
      // The same one-off the preview pane makes for a film it has not seen —
      // see the note beside previewKind = "video".
      term.thumbNow(term.thumbJob(r, term.thumbKind(r)));
    }
    // A PDF HAS NO THUMBNAIL — it has a rendered page, and only the preview
    // pane was ever rendering one. Opened from a list or a grid there was
    // nothing at pdfStem for this file, so quick look said there was nothing
    // to show. Same one-off as the film above.
    if (Terminus.isPdf(r.name) && term.pdfFor !== r.path) {
      term.renderPdf(r.path);
    }

    // ── AND THE TEXT OF A FILE, WHICH IN A LIST NOTHING HAS READ ──────
    // loadPreview stops at its first line when the view is not columns:
    // there is no pane to fill, so reading files to fill it would be work
    // for nothing. Quick look is the exception — it IS the pane, asked for
    // one file at a time — and opened from a list or a grid it drew "no
    // preview available" across every text file in the window.
    //
    // The same one-off the film and the page above make, through the funnel
    // the pane itself uses: beginPeek names the row it is for, and the
    // collector caches the answer under that path, so the pane and the next
    // look at this file both get it for nothing.
    //
    // ── AND WHAT IS INSIDE AN ARCHIVE ─────────────────────────────────
    // The same one-off again. The columns pane lists an archive's contents
    // and quick look drew nothing at all for one — not even the apology,
    // once previewKind happened to be left on "archive" from the pane.
    // Nothing had read it, because reading it is loadPreview's job and
    // loadPreview stops at its first line outside the columns view.
    if (Terminus.isArchive(r.name)) {
      if (r.path !== term.previewShown && r.path !== term.previewFor) {
        const hit = term.previewCache[r.path];
        if (hit !== undefined)
          term.settlePreview(hit.kind, hit.rows, hit.text, r.path);
        else {
          term.previewKind = "archive";
          term.beginPeek(r.path, Terminus.archiveListCommand(r.path));
        }
      }
      // ALREADY READ IS NOT ALREADY SHOWN. When the pane has this very
      // archive settled, the branch above rightly reads nothing — and
      // the viewer was then left holding the empty latch it clears on
      // arrival. Walking onto a directory and back onto an archive hit
      // this every time, and drew a blank card.
      term.lookLayerRef.look.syncTree();
    }

    // A TYPEFACE needs no process: Qt loads the file and the specimen is
    // drawn with it. It needs the KIND set, though — quick look asks the
    // row what it is rather than reading previewKind (see lookLayer.look.pic), but
    // the specimen below is the one part that cannot, because whether a
    // font actually loaded is FontLoader's answer and not the name's.
    if (Terminus.isFont(r.name) && r.path !== term.previewShown)
      term.settlePreview("font", [], "", r.path);

    // By elimination rather than by a list of extensions, exactly as the tail
    // of loadPreview decides it: everything that is not one of the kinds
    // above is read as text and found to be binary or not by its bytes.
    if (!Terminus.isImage(r.name) && !Terminus.isVideo(r.name)
        && !Terminus.isAudio(r.name) && !Terminus.isFont(r.name)
        && !Terminus.isPdf(r.name) && !Terminus.isArchive(r.name)
        && r.path !== term.previewShown && r.path !== term.previewFor) {
      const hit = term.previewCache[r.path];
      if (hit !== undefined)
        term.settlePreview(hit.kind, hit.rows, hit.text, r.path);
      else {
        term.previewKind = "text";
        term.beginPeek(r.path, Terminus.previewCommand(r.path, term.platoRender, 1, Zenon.nvimTheme()));
      }
    }
  }
  // Debounced, not immediate. Holding Down through a directory would otherwise
  // start a process per row and finish them in an order nobody asked for; this
  // way only the row you actually stopped on is ever read.
  Timer {
    id: previewDelay
    // shorter than it was: the work behind a landing is now capped output, a
    // smaller relayout and often a cache hit, so waiting 110ms to start it was
    // most of the delay rather than a guard against it
    interval: 30
    // The metadata rides along, because `sel` is not the only thing that
    // changes what is being previewed. Entering a directory whose first row is
    // already the cursor fires no onSelChanged at all — the whole listing
    // changed underneath a cursor that never moved — and the panel came up
    // with a size and a date and no dimensions. Everything that restarts this
    // timer means "the preview is now of something else", which is exactly
    // when the probe has to run too.
    onTriggered: { term.loadPreview(); term.infoDelayRef.restart(); }
  }
  function resumePreview() {
    if (term.millerAnimRef.running) return;
    // BELT AND BRACES on the fade. millerStep drops the columns to nothing
    // and the animator carries them back, so anything that stops that
    // animator without letting it finish would leave the file list invisible
    // — the worst failure this transition could have. Every slide ends here.
    term.chromeRef.miller.opacity = 1;
    term.previewWanted = false;
    // AND THE ONE REQUEST THE SLIDE WAS HOLDING BACK. Unconditional, because
    // the paths that ask BEFORE stepping and the step that leaves `sel` at 0
    // both end a slide with nothing outstanding — and then the row under the
    // cursor never gets previewed at all. A directory with a single file in
    // it has no second row to move to and would never show one.
    //
    // refreshPreview returns immediately when the pane is already showing the
    // right row, so asking when the answer is in costs nothing.
    term.refreshPreview();
  }
  // ── A HELD KEY PREVIEWS WHERE IT STOPS ─────────────────────────────
  // Every step used to settle the pane at once — from the cache that is a
  // rich-text layout, or a directory's column of delegates rebuilt — so a
  // held arrow (a step every ~33 ms) rebuilt the pane for every row it
  // passed over: 30–58 ms a step to the frame, and runs of 100–160 ms stalls
  // in lag.log (2026-10-09). Steps closer together than `restMs` wait for the
  // cursor to rest, and only the row it rests on is previewed. A deliberate
  // step, at any ordinary pace, is answered as before, in the same frame.
  readonly property int restMs: 90
  property real lastAsk: 0
  Timer {
    id: restDelay
    interval: preview.restMs
    onTriggered: { preview.lastAsk = 0; preview.refreshPreview(); }
  }
  function refreshPreview() {
    const now = Date.now();
    const rapid = now - preview.lastAsk < preview.restMs;
    preview.lastAsk = now;
    if (rapid) { restDelay.restart(); return; }
    if (term.millerAnimRef.running || term.stepping) { term.previewWanted = true; return; }
    term.dirWatchRef.peekAim.restart();
    const r = term.currentRow();
    // The rows under this cursor are the ones being left — see `arriving`.
    if (term.arriving) return;
    // ALREADY ANSWERED, OR ALREADY BEING ANSWERED — see previewShown. The
    // row has not changed, so neither the pane nor the metadata beside it
    // has anything to be told.
    if (r && (r.path === term.previewShown || r.path === term.previewFor))
      return;
    // Metadata takes the same shape as the preview itself: the cache answers
    // in the same frame and only a miss waits behind the debounce. Reading it
    // here rather than leaving it all to loadPreviewInfo is what stops the
    // panel blanking for a tenth of a second every time the cursor walks back
    // over a row it has already been on.
    const known = r ? term.infoCache[r.path] : undefined;
    term.previewInfo = known === undefined ? null : known;
    if (known === undefined) term.infoDelayRef.restart(); else term.infoDelayRef.stop();
    const hit = r ? term.previewCache[r.path] : undefined;
    if (hit !== undefined) {
      term.settlePreview(hit.kind, hit.rows, hit.text, r.path);
      return;
    }
    // an image needs no process either: the pane points Qt at the file
    if (r && !r.isDir && Terminus.isImage(r.name)) {
      term.settlePreview("image", [], "", r.path);
      return;
    }
    // A DIRECTORY WE HAVE ALREADY READ NEEDS NO PROCESS AND NO GAP. The
    // window remembers the last sixteen listings as the bytes they came back
    // as — for seeding a navigation — and a peek wants exactly the same
    // bytes. Without this, walking down a column of directories you have just
    // walked up emptied the pane and refilled it a frame later for every
    // single row, which is the flicker: not a wrong listing, an absent one.
    if (r && r.isDir) {
      const seen = term.listingText[r.path];
      if (seen !== undefined) {
        const rows = term.rowsFromListing(seen, r.path);
        term.settlePreview("dir", rows, "", r.path);
        term.cachePreview(r.path, { kind: "dir", rows: rows });
        return;
      }
    }
    // NOTHING RATHER THAN THE LAST ANSWER while the new one is fetched. The
    // pane held whatever it had until the replacement arrived, which meant a
    // directory's listing sat under a filename it has nothing to do with for
    // as long as the peek took. Empty is honest and it is one frame.
    previewProc.running = false;
    term.previewFor = "";
    term.previewShown = "";
    // Only if there is something to clear. refreshPreview and loadPreview
    // both reach here for the same row — one off the keystroke, one off the
    // debounce behind it — and the second was assigning an empty array over
    // an empty array, which is a full model reset of the pane for no change
    // at all.
    if (term.previewRows.length > 0) term.previewRows = [];
    if (term.previewText !== "") term.previewText = "";
    previewDelay.restart();
  }
  Process {
    id: previewProc
    stdout: StdioCollector {
      id: previewOut
      waitForEnd: true
      onStreamFinished: {
        const t = previewOut.text;
        const cur = term.currentRow();
        // The answer is about a row we have since left. Nothing to draw and
        // above all nothing to cache: a wrong entry here is permanent.
        if (!cur || cur.path !== term.previewFor) return;
        term.previewFor = "";
        if (term.previewKind === "dir") {
          // the same output listing it would produce — see listingText
          term.rememberListing(cur.path, t);
          const rows = cur ? term.rowsFromListing(t, cur.path) : [];
          term.previewRows = rows;
          term.previewShown = cur.path;
          if (cur) term.cachePreview(cur.path, { kind: "dir", rows: rows });
        } else if (term.previewKind === "archive") {
          // Rows, not a block of text: the tree wants a glyph and a colour per
          // entry, the same two a listing gives its rows, and those come from
          // the same enrichment the listing uses rather than from a second
          // idea of what a .rs file looks like. The "and more" marker is not a
          // file and gets neither.
          const rows = Terminus.archiveTree(t);
          for (const e of rows) {
            e.inkKey = e.more ? "muted" : Terminus.inkKeyOf(e);
            e.nameKey = e.more ? "muted" : Terminus.nameKeyOf(e);
            e.ink = Zenon[e.inkKey];
            e.nameInk = Zenon[e.nameKey];
            e.glyph = e.more ? "" : term.glyphOf(e);
          }
          term.previewTree = rows;
          term.previewRows = [];
          term.previewShown = cur.path;
          // an unreadable or empty archive is still not text
          if (rows.length === 0) term.previewKind = "binary";
          if (cur) term.cachePreview(cur.path,
            { kind: term.previewKind, rows: rows });
        } else if (Terminus.looksBinary(t)) {
          term.previewKind = "binary";
          term.previewShown = cur.path;
          term.previewText = "";
          if (cur) term.cachePreview(cur.path, { kind: "binary" });
        } else {
          term.previewKind = "text";
          term.previewShown = cur.path;
          // AN EMPTY FILE HAS NO TEXT, and ansiToRich does not agree: handed
          // "" it returns the <pre> wrapper it wraps everything in, which is
          // a non-empty string that renders as nothing. Everything asking
          // "is there a document here" — the footer, the rule above it —
          // was being told yes by a wrapper around no content. Long lines
          // are cut in there (terminus.js capPreview) — a minified file's
          // one line froze quick look for seconds.
          const rich = String(t).trim() === "" ? "" : Terminus.ansiToRich(t, term.codeFamily);
          term.listingRef.drawnAfter("terminus preview " + Math.round(rich.length / 1024) + " KB drawn");
          term.previewText = rich;
          if (cur) term.cachePreview(cur.path, { kind: "text", text: rich });
        }
      }
    }
  }
  function loadPreview() {
    // Same reason as refreshPreview: the columns are mid-slide and this would
    // sync the scene graph underneath them. refreshPreview reaches here once
    // they stop.
    if (term.millerAnimRef.running) { term.previewWanted = true; return; }
    if (term.viewMode !== "columns") return;
    const r = term.currentRow();
    // the same three questions refreshPreview asks, for the path that
    // arrives here through the debounce
    if (term.arriving) return;
    if (r && (r.path === term.previewShown || r.path === term.previewFor))
      return;
    if (!r) {
      term.previewKind = "none";
      term.previewRows = [];
      term.previewText = "";
      return;
    }

    // already known: no process, no parse, no relayout
    const hit = term.previewCache[r.path];
    if (hit !== undefined) {
      term.settlePreview(hit.kind, hit.rows, hit.text, r.path);
      return;
    }
    // and a directory whose bytes are remembered needs none of the three
    // either — the same seed refreshPreview takes, for the path that gets
    // here through the debounce rather than straight off a keystroke.
    if (r.isDir) {
      const seen = term.listingText[r.path];
      if (seen !== undefined) {
        const rows = term.rowsFromListing(seen, r.path);
        term.settlePreview("dir", rows, "", r.path);
        term.cachePreview(r.path, { kind: "dir", rows: rows });
        return;
      }
    }

    term.previewShown = "";
    if (term.previewRows.length > 0) term.previewRows = [];
    if (term.previewText !== "") term.previewText = "";
    if (r.isDir) {
      term.previewKind = "dir";
      term.beginPeek(r.path, Terminus.peekCommand(r.path));
      return;
    }
    // NOTHING IS READ FOR A FILE WHEN THE PREVIEW IS OFF. Stopped here
    // rather than at the pane that draws it: what costs is the stat, the
    // thumbnail and the decode this dispatcher sets in motion, not the
    // rectangle at the end of it.
    if (!term.previewOn) { term.previewKind = "none"; return; }
    if (Terminus.isImage(r.name)) { term.previewKind = "image"; return; }
    if (Terminus.isVideo(r.name)) {
      term.previewKind = "video";
      // the same cached frame the grid uses, made on demand if the grid has
      // not already asked for it
      if (!term.thumbHas(r)) term.thumbNow(term.thumbJob(r, "v"));
      return;
    }
    if (Terminus.isAudio(r.name)) {
      term.previewKind = "audio";
      // Cover art, through the same cache and the same batch as a video's
      // frame — it is a picture pulled out of a file either way. A track with
      // no art writes nothing and the panel shows its tags alone.
      if (!term.thumbHas(r)) term.thumbNow(term.thumbJob(r, "a"));
      return;
    }
    // A typeface is previewed by BEING the preview: Qt loads the file and the
    // specimen below is drawn with it. Nothing to run, nothing to parse.
    if (Terminus.isFont(r.name)) { term.previewKind = "font"; return; }
    // An archive shows what is inside it. "binary" is true of a .tar.zst and
    // tells you nothing you wanted to know before extracting it.
    if (Terminus.isArchive(r.name)) {
      term.previewKind = "archive";
      term.beginPeek(r.path, Terminus.archiveListCommand(r.path));
      return;
    }
    if (Terminus.isPdf(r.name)) {
      term.previewKind = "pdf";
      term.renderPdf(r.path);
      return;
    }
    term.previewKind = "text";
    term.beginPeek(r.path, Terminus.previewCommand(r.path, term.platoRender, 1, Zenon.nvimTheme()));
  }
  // One way in, so no peek can ever be started without saying what it is for.
  // The old run is stopped first: the collector gathers until the stream ends,
  // and two runs feeding one collector is how half of one listing arrives
  // stapled to half of another.
  function beginPeek(path, command) {
    previewProc.running = false;
    term.previewFor = path;
    previewProc.command = ["sh", "-c", command];
    previewProc.running = true;
  }
  // Deciding a preview WITHOUT a process has to cancel the one in flight, or
  // the answer to a question nobody is asking any more arrives and overwrites
  // the one that is on screen.
  function settlePreview(kind, rows, text, path) {
    // Only when the pane is actually changing subject. Arrowing down a list
    // of already-cached rows settles constantly, and fading on every one of
    // those would turn a crisp cursor into a flicker.
    if ((path || "") !== term.previewShown) {
      term.previewFadeRef.stop();
      term.chromeRef.previewPane.opacity = 0;
      term.previewFadeRef.restart();
    }
    previewProc.running = false;
    term.previewFor = "";
    previewDelay.stop();
    term.previewShown = path || "";
    term.previewKind = kind;
    // ROUTED BY KIND, and the other one emptied. A cached archive comes back
    // through here exactly as a cached directory does, so this is where the
    // two shapes have to be told apart or they never are.
    if (kind === "archive") {
      term.previewTree = rows || [];
      term.previewRows = [];
    } else {
      term.previewRows = rows || [];
      term.previewTree = [];
    }
    term.previewText = text || "";
  }
}
