// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' what the picture is … logic, out of TerminusWindow.qml
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
import "../morpheus/lagnotes.js" as LagNotes
import "../morpheus/thumbs.js" as Thumbs
import "tags.js" as Tags
import "collections.js" as Coll

Item {
  id: listing
  property var term: null

  // Timed for lag.log: from something applied to the window's next frame,
  // which is where its items are built, laid out and handed to the GPU —
  // the part the apply's own time does not see. A listing, a preview, a
  // cursor move (see drawnAfter's callers); each waits for the same frame.
  property var drawnWait: []
  function drawnAfter(label, t0) {
    listing.drawnWait = listing.drawnWait.filter((d) => d.label !== label)
      .concat([{ label: label, t0: t0 || Date.now() }]);
  }
  Connections {
    target: listing.Window.window
    ignoreUnknownSignals: true
    function onFrameSwapped() {
      if (listing.drawnWait.length === 0) return;
      // a hidden window draws no frames: what waited through that is not
      // a measurement ("341484ms", and "4564ms" for the window built hidden
      // at start and shown later), and is dropped
      const now = Date.now();
      for (const d of listing.drawnWait) if (now - d.t0 < 2000) LagNotes.mark(d.label, d.t0);
      listing.drawnWait = [];
    }
  }
  readonly property alias infoDelay: infoDelay
  readonly property alias listProc: listProc

  function cacheInfo(path, info) {
    const c = term.infoCache;
    const o = term.infoOrder.slice();
    if (c[path] === undefined) o.push(path);
    c[path] = info;
    while (o.length > 48) delete c[o.shift()];
    term.infoCache = c;
    term.infoOrder = o;
  }
  Timer {
    id: infoDelay
    // longer than the preview's 55ms: this is the one probe with no cheap
    // path. A picture's own preview is just Qt pointed at the file, but its
    // dimensions cost a process either way, so holding Down through a
    // background directory should start none of them.
    interval: 110
    onTriggered: term.loadPreviewInfo()
  }
  // The probe carries the path and kind it was STARTED for. They used to be
  // read off root at the end: a probe still out when the cursor moved on
  // was then parsed as the new file's kind and cached under the new file's
  // path — and the new file's own probe had been a no-op restart. Two files
  // of the same kind swapped metadata for as long as the window stayed open.
  Process {
    id: infoProc
    property string infoFor: ""
    property string infoKind: ""
    property bool again: false
    onExited: if (infoProc.again) { infoProc.again = false; Qt.callLater(term.loadPreviewInfo); }
    stdout: StdioCollector {
      id: infoOut
      waitForEnd: true
      onStreamFinished: {
        const r = term.currentRow();
        const kind = infoProc.infoKind;
        const info = kind === "video"
          ? Terminus.parseVideoInfo(infoOut.text)
          : (kind === "audio"
            ? Terminus.parseAudioInfo(infoOut.text)
            : (kind === "text"
              ? Terminus.parseTextInfo(infoOut.text)
              : (kind === "pdf"
                ? Terminus.parsePdfInfo(infoOut.text)
                : Terminus.parseImageInfo(infoOut.text))));
        // Cached even when the cursor has moved on: the work is already done,
        // and walking back up the list should not pay for it twice.
        //
        // A FAILURE is not cached. Remembering a null would turn one probe
        // that lost a race — against a file still being written, most often —
        // into a file that has no metadata for as long as the window is open.
        if (info && infoProc.infoFor !== "")
          term.cacheInfo(infoProc.infoFor, info);
        if (r && r.path === infoProc.infoFor) term.previewInfo = info;
      }
    }
  }
  function loadPreviewInfo() {
    term.previewInfo = null;
    if (term.viewMode !== "columns") return;
    const r = term.currentRow();
    if (!r || r.isDir) return;
    const kind = Terminus.isVideo(r.name) ? "video"
      : (Terminus.isAudio(r.name) ? "audio"
        : (Terminus.isImage(r.name) ? "image"
          // OR whatever the pane actually decided. A great many text files
          // have no extension to recognise — .zshrc, a Makefile, a script —
          // and those are exactly the ones previewKind gets right by looking
          // at the bytes. The name is only the fast path.
          : (Terminus.isPdf(r.name) ? "pdf"
            : ((Terminus.isText(r.name) || term.previewKind === "text")
              ? "text" : ""))));
    if (kind === "") return;
    const hit = term.infoCache[r.path];
    if (hit !== undefined) { term.previewInfo = hit; return; }
    term.previewInfoFor = r.path;
    term.previewInfoKind = kind;
    // one probe at a time; the one asked for meanwhile runs when it ends
    if (infoProc.running) { infoProc.again = true; return; }
    infoProc.infoFor = r.path;
    infoProc.infoKind = kind;
    infoProc.command = ["sh", "-c",
      kind === "video" ? Terminus.videoInfoCommand(r.path)
        : (kind === "audio" ? Terminus.audioInfoCommand(r.path)
          : (kind === "text" ? Terminus.textInfoCommand(r.path)
            : (kind === "pdf" ? Terminus.pdfInfoCommand(r.path)
              : Terminus.imageInfoCommand(r.path))))];
    infoProc.running = true;
  }
  // One page render at a time, and it is the LATEST ask that runs next. The
  // page is always written to the same pdfStem file, so a render still out
  // for the previous PDF finished into it after pdfFor had moved on, and the
  // old document's page was shown under the new one's name.
  function renderPdf(path) {
    term.pdfFor = path;
    if (pdfProc.running) { pdfProc.again = true; return; }
    pdfProc.renderedFor = path;
    pdfProc.command = ["sh", "-c", Terminus.pdfCommand(path, term.pdfStem)];
    pdfProc.running = true;
  }
  Process {
    id: pdfProc
    property string renderedFor: ""
    property bool again: false
    onExited: (code) => {
      if (pdfProc.again) {
        pdfProc.again = false;
        // overtaken: its page is not the one wanted, so it is not shown
        if (pdfProc.renderedFor !== term.pdfFor) {
          Qt.callLater(() => term.renderPdf(term.pdfFor));
          return;
        }
      }
      // the stamp is what makes Qt reload a file it has already cached under
      // this exact name
      // NOT gated on previewKind any more. Quick look renders pages in list
      // and grid views, where the preview pane has computed nothing and the
      // kind is "none" — so the guard threw away the stamp for exactly the
      // renders it had asked for, and the page never appeared.
      if (code === 0) term.previewStamp++;
      else term.pdfFor = "";
    }
  }
  // The model, its index and the diff that keeps them in step all moved into
  // Pane, because there are two of them now and a window-wide one could only
  // ever describe the half the keyboard was in. The argument for them has not
  // changed and lives there; what changed is that each half has its own, so
  // the item drawing a directory is the same item from the moment it is
  // listed until the moment you leave it.
  function rowFor(path) { return term.act.rowFor(path); }
  // FUNCTIONS, not bindings. As properties these recomputed whenever `marked`
  // changed — every pointer move of a drag-select — and the context menu's
  // item list depended on `acting`, so it rebuilt its labels each time even
  // while closed. Nothing needs either until something acts.
  function markedRows() {
    const out = [];
    const v = term.view;
    const m = term.marked;
    for (let i = 0; i < v.length; ++i)
      if (m[v[i].path]) out.push(v[i]);
    return out;
  }
  // What a verb acts on: everything ticked, or the row under the cursor when
  // nothing is. The same rule zeus' kill list uses, and the reason you can
  // rename a file without marking it first.
  function acting() {
    // a verb chosen from a held row's menu (RowMenu.run): that row, or the
    // marks if it is one of them
    const h = term.heldBox.row;
    if (h) return term.marked[h.path] ? term.markedRows() : [h];
    const m = term.markedRows();
    if (m.length > 0) return m;
    const r = term.view[term.sel];
    return r ? [r] : [];
  }
  // THROUGH THE PANE, NOT THROUGH THE PROXY, and the difference is not
  // cosmetic. `root.view` is a binding onto the active pane's own `view`, and
  // inside that pane's onViewChanged handler the binding has not been
  // re-evaluated yet — the pane's rows are the new ones and root.view still
  // answers with the old. Measured: the handler that fires the instant a
  // directory's rows land read 29 rows and a cursor on the directory we had
  // just LEFT, settled the preview on it, and was corrected sixty
  // milliseconds later when something else touched the binding.
  //
  // That is the list that flashes in the last column. Reading the pane
  // directly cannot be a frame behind it.
  function currentRow() { return term.heldBox.row || term.act.view[term.act.sel] || null; }
  // The colour and the glyph are worked out ONCE PER LISTING and stored on the
  // row, not asked for every time a delegate is drawn.
  //
  // They used to be functions called from bindings, which means once per row
  // per repaint: categoryOf does string work and glyphFor does map lookups,
  // and in a directory of a couple of thousand entries that is the frame
  // budget spent on answers that cannot change. `enrich` runs over the rows as
  // they arrive and the delegates read a field.
  function inkFor(e) { return Terminus.rowInk(e); }
  // The NAME's ink, which is not the glyph's. The glyph already says what
  // kind of file it is, in its shape and its colour; the name saying it a
  // second time spent five colours on one fact and left none for anything
  // else a name might want to say. So the kinds are the glyph's alone, and
  // the name keeps only what is about the ENTRY rather than its type: a
  // directory, a link and where it leads, something you can run, an empty file.
  function nameInkFor(e) { return Terminus.rowNameInk(e); }
  // shared with every other row of files — see terminus.js
  function nameInkOf(e) { return Terminus.nameInkOf(e); }
  // shared with every other row of files — see terminus.js
  function inkOf(e) { return Terminus.inkOf(e); }
  // Icons.glyphFor answers from a table of extensions somebody wrote down,
  // and the set of image formats is not a set anybody finishes writing down:
  // forty-one of the ones this window already calls images had no line in it
  // and drew the plain page — the same mark a file type nothing recognises
  // gets, beside a .cr2 drawing a picture.
  //
  // So when the table has nothing, the KIND answers instead. This window has
  // already worked the kind out for the sort and the colour, and it is the
  // one place that knows it — Icons is shared with artemis and has no
  // opinion about what counts as an image.
  //
  // Fonts are asked for separately because kindOf folds them into
  // "document": right for sorting, where a .ttf belongs among the things you
  // open rather than the things you play, and wrong here, where they have a
  // glyph of their own.
  // shared with every other row of files — see terminus.js
  function glyphOf(r) { return Terminus.glyphOf(r, Icons); }
  function enrich(rows) {
    for (const r of rows) {
      r.inkKey = Terminus.inkKeyOf(r);
      r.nameKey = Terminus.nameKeyOf(r);
      r.ink = Zenon[r.inkKey];
      r.nameInk = Zenon[r.nameKey];
      r.glyph = term.glyphOf(r);
      // The metadata cells USED to be computed here as well — kind, the
      // relative time and the size string. They are not any more; see kindOf
      // below. ink and glyph stay, because every view draws those for every
      // row and there is no listing where they are not wanted.
    }
    return rows;
  }
  //
  // These three were moved INTO enrich once, for a good reason: `reuseItems`
  // rebinds `entry` on every recycled delegate, and a function call in a
  // binding is interpreted every time. The reason was good and the placement
  // was wrong, because enrich runs over the WHOLE listing the moment it is
  // parsed — so a four thousand entry directory paid four thousand date
  // calculations, four thousand walks of five extension tables and four
  // thousand size formats before it could draw anything, to fill in cells
  // that only the list view's metadata columns ever read. The grid draws none
  // of them. The miller middle column draws none of them. Even in the list
  // only the rows actually on screen are ever bound. Measured, that pass was
  // most of the cost of arriving in a large directory.
  //
  // MEMOISED ONTO THE ROW, so the original argument still holds: the first
  // delegate to want a cell pays for it, every rebind after that is a property
  // read, and a row nobody looks at costs nothing at all.
  function kindOf(e) {
    if (e.kind === undefined)
      e.kind = e.isDir ? "directory"
        : (e.isLink && e.broken ? "broken link" : Terminus.kindOf(e.name));
    return e.kind;
  }
  // A relative time freezes until the next listing rather than refreshing
  // whenever a row happens to be recycled. Nothing was refreshing it on a
  // clock before either — bindings do not re-evaluate because time passed —
  // so this only makes the column CONSISTENT: the rows you scroll to do not
  // read a few minutes fresher than the rows you started on.
  function whenOf(e) {
    if (e.when === undefined) e.when = Terminus.formatTime(e.mtime);
    return e.when;
  }
  // Directories have no honest size until du has been round, so theirs stays
  // the size cell's business.
  function sizeTextOf(e) {
    if (e.sizeText === undefined)
      e.sizeText = e.isDir ? "" : Terminus.formatSize(e.size);
    return e.sizeText;
  }
  Process {
    id: listProc
    // see startListing
    onExited: if (term.listAgain) Qt.callLater(term.startListing)
    stdout: StdioCollector {
      id: listOut
      waitForEnd: true
      onStreamFinished: {
        // read for a directory we have since left — the one queued behind it
        // is for this one
        if (term.listFor !== term.cwd) { Qt.callLater(term.startListing); return; }
        // Byte-identical output means nothing in this directory changed, so
        // there is nothing to redraw. inotify fires close_write and attrib for
        // files whose presence, size and mtime are all unchanged, and
        // rebuilding the model for those was pure churn — one string compare
        // makes them free.
        // null, never "", is the "nothing loaded yet" sentinel — see the
        // property's own note. An EMPTY DIRECTORY prints nothing, so an empty
        // string is a perfectly real listing and must not read as "unchanged".
        if (listOut.text === term.lastListing) return;
        term.act.lastListing = listOut.text;
        // timed for lag.log (see morpheus/LagWatch): a listing is parsed and
        // its rows built on the GUI thread
        const lagT0 = Date.now();
        try {
          term.rememberListing(term.cwd, listOut.text);
          // WHICH FILE the cursor was on, not which index. A directory that
          // other programs are writing to — /tmp above all — reorders under you,
          // and an index that survives a rebuild points at whatever moved into
          // that slot. The cursor is what `d`, Return and the menu act on, so
          // letting it drift is letting those act on a file you did not choose.
          const wasOn = term.view[term.sel] ? term.view[term.sel].path : "";
          const keep = term.keepScroll();
          // The same hold enter() takes, for the other way rows arrive — see
          // `arriving`. Between the assignment below and the cursor being put
          // back a few lines later, "what is under the cursor" has a complete
          // and wrong answer, and everything watching the cursor believed it.
          term.arriving = true;
          term.act.raw = term.enrich(Terminus.parseListing(listOut.text, term.cwd));
          term.cutTaken(term.cwd, term.act.raw);
          // The listing also says which of this directory's remembered
          // branches are no longer here — see dropGone.
          term.act.forgetVanished(term.cwd, term.act.raw);
          // a directory you walk into while the mode is on measures itself,
          // because a usage view of a directory it has not looked at is a column
          // of dashes
          if (term.usage) Qt.callLater(term.measureAll);
          // Land on the directory we just came out of rather than on the first
          // row: walking up and back down a tree should return you to where you
          // were, not to the top of every level on the way.
          // Whether this listing is one the CURSOR should be moved for. A
          // deliberate landing — arriving in a directory, or a file just made —
          // scrolls to the row. A directory that merely changed underneath does
          // not: you may have scrolled somewhere on purpose, and dragging the
          // view back to the cursor every time inotify fires is what made a busy
          // directory impossible to read.
          let land = false;
          if (term.wantSel !== "") land = term.landWanted();
          else if (wasOn !== "") {
            // the same file, wherever it ended up. THROUGH THE PANE: the rows
            // were written two statements ago and `root.view` is a binding onto
            // them, which has not been re-evaluated yet — it still answers with
            // the listing this one replaced. See currentRow.
            const v = term.act.view;
            for (let i = 0; i < v.length; ++i) {
              if (v[i].path === wasOn) { term.act.sel = i; break; }
            }
          }
          Qt.callLater(term.makeThumbs);
          // AND THE DIRECTORY UNDER THE CURSOR. Arriving somewhere puts the
          // cursor on row 0 without it having MOVED, so onSelChanged never
          // fires — which is exactly the case where you are most likely to
          // step straight on into the first directory you see.
          //
          // UNGATED. The directory's remembered view is applied around this
          // moment, not before it, so asking "is this a grid" here answers
          // about the view being left. warmPeek asks again when it runs,
          // which is 260ms later and after the dust has settled.
          term.splitPaneRef.warmAim.restart();
          if (term.act.sel >= term.act.view.length)
            term.act.sel = Math.max(0, term.act.view.length - 1);
          // Rows in, cursor placed: one preview, of the right row.
          term.arriving = false;
          if (term.viewMode === "columns") term.refreshPreview();
          if (land) Qt.callLater(term.positionSel);
          else {
            // SYNCHRONOUSLY, in the same tick as the assignment above. The view
            // drops its offset the moment the model is replaced — which happens
            // inside `root.act.raw = ...`, before this function returns — so
            // putting it back here means no frame is ever drawn at the wrong
            // place. Deferring it to a callLater also worked, and you could see
            // it work: the listing jumped to the top and then snapped back.
            term.restoreScroll(keep);
            // and again once the view has settled its own contentHeight, which
            // it may still have been estimating a moment ago. putScroll returns
            // immediately when there is nothing to change, so this is free in
            // the ordinary case.
            Qt.callLater(() => term.restoreScroll(keep));
          }
        } finally {
          LagNotes.mark("terminus listing " + term.act.raw.length + " rows", lagT0);
          // and until it is on screen: the rows' items are made and laid
          // out after this, in the frame it asks for — see drawnAt below
          listing.drawnAfter("terminus " + term.act.raw.length + " rows drawn", lagT0);
        }
      }
    }
  }
  function startListing() {
    if (listProc.running) { term.listAgain = true; return; }
    term.listAgain = false;
    term.listFor = term.cwd;
    listProc.command = ["sh", "-c", Terminus.listCommand(term.cwd)];
    listProc.running = true;
  }
  // `full` means the DIRECTORY changed. A plain refresh — after an action, or
  // when inotify says something moved in the current directory — re-reads only
  // the current listing.
  //
  // It used to do all three every time: current listing, parent listing and a
  // preview reload. The parent cannot have changed unless you moved, and the
  // preview cannot have changed unless the cursor moved, so an event in the
  // current directory cost three processes and three model swaps to answer a
  // question about one of them. That was the redraw in the split view.
  function refresh(full) {
    if (term.searchMode !== "") return;   // results are not a directory
    term.startListing();
    // Together with the listing, so the marks arrive with the rows they are
    // about — and again after every job, because this is the one view in the
    // window that a `git commit` in another terminal can make wrong.
    term.scanGit();
    if (full) {
      // THE ROOT HAS NO PARENT, and dirname("/") is "/" — so asking for it
      // listed the root twice, once in the column you are standing in and
      // again in the column that is meant to say where you came from. An
      // empty column is the truth: there is nothing above this.
      // Drawn from what is already known FIRST, and confirmed by the
      // process behind it — which usually has nothing to add.
      term.seedParent();
      if (term.cwd === "/") { term.parentRows = []; term.parentListing = null; }
      else {
        term.startParent();
      }
      term.previewRef.previewDelay.restart();
    }
  }
}
