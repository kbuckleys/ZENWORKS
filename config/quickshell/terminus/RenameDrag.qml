// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' renaming … logic, out of TerminusWindow.qml
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
  id: renameDrag
  property var term: null
  readonly property alias springGrace: springGrace

  function beginRename() {
    if (!term.currentRow()) return;
    term.renamePath = term.currentRow().path;
    // `r` is never a creation, so Escape out of it must not delete anything —
    // and a create whose listing never came back would otherwise leave its
    // path armed behind an unrelated rename.
    term.freshPath = "";
    term.renaming = true;
  }
  function endRename(cancelled) {
    if (!term.renaming) return;
    term.renaming = false;
    term.renamePath = "";
    const fresh = term.freshPath;
    const holds = term.freshHolds;
    term.freshPath = "";
    term.freshHolds = false;
    if (cancelled === true && fresh !== "" && !holds) {
      term.run(Terminus.deleteCommand([fresh]));
      // The name is free again the moment the file goes — see unreserve.
      term.unreserve(fresh);
      // AND THE CURSOR COMES BACK TO THE DIRECTORY, not to whatever index the
      // row happened to occupy. Clamping alone would drop it on the last
      // row of the list, which for a branch halfway down is nowhere near
      // where you were working.
      const owner = Terminus.dirname(fresh);
      if (owner !== "" && owner !== term.cwd) term.wantSel = owner;
    }
    term.contentRef.forceActiveFocus();
  }
  // justMade holds the names this window has asked for but not yet seen in
  // a listing, so two quick creates cannot both pick "new file". It is
  // pruned when the row turns up — and a create that is CANCELLED, or
  // renamed into something else, produces no such row, so its name stayed
  // reserved for the rest of the session. Eight cancelled attempts in one
  // directory and the next one is offered as "new file 9", which is what the
  // capture shows.
  function unreserve(path) {
    if (path !== "" && term.justMade[path] !== undefined)
      delete term.justMade[path];
  }
  function commitRename(entry, name) {
    // Read BEFORE endRename, which is what clears it.
    const fresh = term.freshPath;
    const wasFresh = fresh !== "" && !!entry && entry.path === fresh;
    term.endRename(false);
    const typed = String(name || "").trim();
    // An empty answer on a thing that was just created keeps the name it
    // arrived with, which is the whole point of it arriving with one.
    if (!entry || typed === "" || typed === entry.name) return;
    // ENDING IN A SLASH MEANS A DIRECTORY, which is what the keymap has
    // promised `a` does all along and what the field used to refuse outright.
    // It is only offered for something JUST CREATED: on an existing file a
    // trailing slash would mean replacing it with a directory, which is a request
    // to destroy whatever is in it, and nobody types that on purpose.
    const asDir = /\/+$/.test(typed);
    const want = typed.replace(/\/+$/, "");
    if (want === "") return;
    // A name is a name, not a path: a slash inside it would move the file
    // somewhere else under the guise of renaming it.
    if (want.indexOf("/") >= 0) { term.warn("a name cannot contain /"); return; }
    const to = Terminus.joinPath(Terminus.dirname(entry.path), want);
    if (asDir) {
      if (!wasFresh) { term.warn("a name cannot contain /"); return; }
      term.run(Terminus.recreateAsDir(fresh, to));
      term.unreserve(fresh);
      term.wantSel = to;
      return;
    }
    // ── AND IF THAT NAME IS ALREADY TAKEN ───────────────────────────
    // mv replaces an existing file without a word, so typing the name of
    // something that is already there quietly destroyed it — including
    // straight after `a`, where naming the new file after one you already
    // had was an easy thing to do by accident. The same three answers a
    // paste gets, because it is the same question.
    const near = term.rowsIn(Terminus.dirname(entry.path));
    const from = entry.path;
    if (near.some((r) => r.name === want && r.path !== from)) {
      term.confirmRef.askMany(
        "\u201c" + want + "\u201d already exists",
        // The directory's own name, not its path: the path is the width of
        // the card and the only part of it that is news is the last piece.
        "in " + (Terminus.basename(Terminus.dirname(from)) || "/"),
        // No Cancel of ours — askMany puts one on every card it draws, and
        // two of them side by side is a card that looks like it is asking
        // something it is not.
        [{ label: "Replace", ink: Zenon.red,
           act: () => term.applyRename(from, want, wasFresh, fresh, true) },
         { label: "Keep both", ink: Zenon.green,
           act: () => term.applyRename(from,
                        Terminus.freeNameKeeping(near, want),
                        wasFresh, fresh, false) }]);
      return;
    }
    term.applyRename(from, want, wasFresh, fresh, false);
  }
  // The doing, apart from the asking — so the answer to a clash runs
  // exactly what an unclashing rename runs, down to the undo record.
  function applyRename(from, want, wasFresh, fresh, over) {
    const to = Terminus.joinPath(Terminus.dirname(from), want);
    term.run(over ? Terminus.renameOverCommand(from, want)
                  : Terminus.renameCommand(from, want));
    term.moveTags([[from, to]]);
    if (wasFresh) term.unreserve(fresh);
    // Replace leaves nothing to put back for the file that was written
    // over — the record is about the one that moved, which is all a
    // rename ever moves.
    term.pushUndo({ kind: "rename", from: from, to: to });
    // land on it under its new name rather than wherever the old one sorted
    term.wantSel = to;
  }
  // wl-copy, the same way folio puts a clip back on the clipboard
  function copyPath() {
    const rows = term.acting();
    if (rows.length === 0) return;
    term.copyText(rows.map((r) => r.path).join("\n"), "path copied");
  }
  // Straight into picasso's own store, not a command. It is a singleton in
  // this same shell, so setting a background from here is a property write and
  // the daemon repaints from the same binding the picker uses — no file to
  // hand over and nothing to keep in step.
  function setWallpaper(screenName) {
    const r = term.currentRow();
    if (!r || r.isDir || !Terminus.isImage(r.name)) return;
    if (screenName) Picasso.setFor(screenName, r.path);
    else Picasso.setAll(r.path);
    term.status = "background set";
  }
  // Which rows a rubber band covers. Worked out from the geometry rather than
  // by asking each delegate whether it intersects: a ListView only realises
  // the delegates near the viewport, so anything scrolled out has no item to
  // ask — but it still has an index, and the index is what the band is really
  // selecting.
  function applyBand(x1, y1, x2, y2, base) {
    const next = Object.assign({}, base);
    let lo = -1, hi = -1;

    // MEASURED FROM THE ACTIVE PANE, not from the body. band.x1/x2 are body
    // coordinates — zoneL is activePaneX — and a grid is placed at the pane's
    // own left edge. On the left half activePaneX is 0 and the two agree; on
    // the RIGHT half every column index came out a pane's width too far along,
    // past the end of the row, and the band selected nothing at all.
    const bx1 = x1 - term.activePaneX;
    const bx2 = x2 - term.activePaneX;

    if (term.viewMode === "grid") {
      const g = term.actGrid;
      const cols = Math.max(1, Math.floor(g.width / g.cellWidth));
      const r1 = Math.floor((y1 + g.contentY) / g.cellHeight);
      const r2 = Math.floor((y2 + g.contentY) / g.cellHeight);
      const c1 = Math.floor(bx1 / g.cellWidth);
      const c2 = Math.floor(bx2 / g.cellWidth);
      for (let r = Math.max(0, r1); r <= r2; ++r) {
        for (let c = Math.max(0, c1); c <= Math.min(cols - 1, c2); ++c) {
          const i = r * cols + c;
          if (i >= 0 && i < term.view.length) next[term.view[i].path] = true;
        }
      }
      term.act.marked = next;
      return;
    }

    // both single-column views: the band is a range of rows
    const view = term.viewMode === "list" ? term.actList : term.midCol.view;
    // In the miller layout the middle column is inset by the parent column, so
    // a drag started over the parent or the preview is not a selection of
    // anything in the middle one and must not act like it.
    if (term.viewMode === "columns") {
      // Same correction: these widths are inside the pane, the band's x is not.
      const left = term.parCol.width + 1;
      const right = left + term.midCol.width;
      if (bx2 < left || bx1 > right) { term.act.marked = next; return; }
    }
    // ── ROWS ARE NOT ALL THE SAME HEIGHT ANY MORE ────────────────────
    // Dividing by rowH is exact and cheap and stays the path taken almost
    // always — but with headings on, a cell that carries one is taller than
    // the rest and the arithmetic drifts by a heading's height for every
    // band the drag has crossed. indexAt asks the view, which knows.
    if (term.grouped && term.viewMode === "list") {
      lo = term.bandIndexAt(view, y1);
      hi = term.bandIndexAt(view, y2);
    } else {
      lo = Math.floor((y1 + view.contentY) / term.rowH);
      hi = Math.floor((y2 + view.contentY) / term.rowH);
    }
    // a drag that has not crossed a row boundary selects the same rows it
    // already did, and rebuilding the map for that is work with no result
    if (lo === term.chromeRef.band.lastLo && hi === term.chromeRef.band.lastHi) return;
    term.chromeRef.band.lastLo = lo;
    term.chromeRef.band.lastHi = hi;
    const v = term.view;
    for (let i = Math.max(0, lo); i <= Math.min(v.length - 1, hi); ++i)
      next[v[i].path] = true;
    term.act.marked = next;
  }
  // Which row is under a y inside the view, heights and all. -1 above the
  // first row and `count` below the last, so a drag that runs off either end
  // still selects everything it crossed rather than collapsing to nothing —
  // indexAt answers -1 for both "before the start" and "after the end", and
  // those are opposite ends of the range being built.
  function bandIndexAt(view, y) {
    const cy = y + view.contentY;
    const i = view.indexAt(8, cy);
    if (i >= 0) return i;
    return cy < 0 ? -1 : view.count;
  }
  // text/uri-list is the one thing every file-aware application on the desktop
  // agrees on, so dragging a row into Firefox or a terminal hands over the
  // same list a file manager would. Dragging the CURSOR row alone would be
  // wrong when a selection exists — you dragged the selection.
  // Fills the drag card in for whatever is about to be dragged, renders it,
  // and hands the url back. Asynchronous by nature — grabToImage answers on
  // the next frame — so the caller starts the drag from inside the callback,
  // with the button still held, which is all the platform needs.
  function dragPicture(entry, then) {
    const rows = term.dragRows(entry);
    const first = rows[0] || entry;
    term.dragCardRef.count = rows.length;
    term.dragCardRef.label = rows.length === 1
      ? (first ? first.name : "") : rows.length + " items";
    term.dragCardRef.glyph = (first && first.glyph) ? first.glyph : "";
    term.dragCardRef.ink = (first && first.ink !== undefined) ? first.ink : Zenon.white;
    term.dragCardRef.picture(then);
  }
  // Starts a drag of `entry` (or the marked set) from a row or tile. (hx, hy)
  // is where the pointer sits on the picture.
  function beginDrag(entry, hx, hy) {
    term.draggingRow = true;
    term.dragProxyRef.uris = term.dragUris(entry);
    term.dragPaths = term.dragRows(entry).filter((r) => !!r).map((r) => r.path);
    term.dragProxyRef.Drag.hotSpot = Qt.point(hx, hy);
    // The picture first, then the drag: Drag.imageSource has to be set
    // before active goes true, or the platform has already taken the
    // gesture and started carrying nothing.
    term.dragPicture(entry, (url) => {
      term.dragProxyRef.Drag.imageSource = url;
      term.dragProxyRef.Drag.active = true;
    });
  }
  // The rows a drag is actually about: the marked set when there is one, and
  // otherwise the row under the pointer. Exactly the rule dragUris always
  // used — written once now, because the picture and the payload have to
  // agree about what is being dragged or the card lies about the drop.
  function dragRows(entry) {
    const marked = term.markedRows();
    return marked.length > 0 ? marked : (entry ? [entry] : []);
  }
  function dragUris(entry) {
    return term.dragRows(entry).filter((r) => !!r)
      .map((r) => Strings.fileUrl(r.path)).join("\r\n");
  }
  // WHICH directory a drop means is a question about where the pointer is,
  // not about which item accepted it — there is one DropArea over the whole
  // body (see dropHint), and it already answers the same question for which
  // PANE the drop lands in. This just asks it one level finer.
  //
  // mapFromItem rather than hand-rolled offsets: the second pane's views are
  // nested a level deeper than the first pane's, and arithmetic written here
  // would have to know that and would break the day it moves. indexAt wants
  // CONTENT coordinates, which is what contentX/contentY add back.
  function dropDirAt(x, y) {
    term.dropViaFile = false;
    const other = term.dual && (x < term.activePaneX
                             || x > term.activePaneX + term.activePaneW);
    if (other) {
      return term.dropRowAt(term.otherViewMode === "grid" ? term.gridOf(term.pas.side) : term.listOf(term.pas.side),
                            term.otherRows, x, y, term.pas);
    }
    // MILLER HAS THREE LISTINGS ON SCREEN and the drop belongs to whichever
    // one the pointer is over. This used to ask `list`, which is not the view
    // columns mode draws with and is not even visible in it — so every drop
    // resolved to the pane's own directory, and dropUris then discarded it as
    // a file dropped into the directory it was already in. That is why dragging
    // onto a directory in the same directory did nothing here and worked
    // everywhere else.
    if (term.viewMode === "columns") {
      const inMid = term.dropRowAt(term.midCol.view, term.view, x, y);
      if (inMid !== "") return inMid;
      const inParent = term.dropRowAt(term.parCol.view, term.parentRows, x, y);
      if (inParent !== "") return inParent;
      // The preview column is a directory rather than a row in one — the same
      // reading a click there gets, so a drop and a click mean the same thing.
      if (term.previewKind === "dir" && term.chromeRef.previewPane.visible) {
        const q = term.chromeRef.previewPane.mapFromItem(term.chromeRef.dropHint, x, y);
        if (q.x >= 0 && q.y >= 0 && q.x <= term.chromeRef.previewPane.width
            && q.y <= term.chromeRef.previewPane.height) {
          const cur = term.currentRow();
          if (cur && cur.isDir) return cur.path;
        }
      }
      return "";
    }
    return term.dropRowAt(term.viewMode === "grid" ? term.actGrid : term.actList,
                          term.view, x, y, term.act);
  }
  function assistSideAt(x) {
    return !term.dual ? term.paneSide : (x >= term.paneX(1) ? 1 : 0);
  }
  // The view under a point in dropHint's space, and the part of it that is
  // actually on screen there — measured against dropHint, so a view taller
  // than what shows cannot put its edge zone somewhere you cannot reach.
  function assistViewAt(x, y) {
    const vs = [term.chromeRef.listA, term.chromeRef.listB, term.chromeRef.gridA, term.chromeRef.gridB,
                term.midCol ? term.midCol.view : null,
                term.parCol ? term.parCol.view : null];
    for (let i = 0; i < vs.length; ++i) {
      const v = vs[i];
      if (!v || !v.visible) continue;
      const p = v.mapFromItem(term.chromeRef.dropHint, x, y);
      if (p.x >= 0 && p.x <= v.width && p.y >= 0 && p.y <= v.height) return v;
    }
    return null;
  }
  function dragAssistMove(x, y) {
    term.assistAt = Qt.point(x, y);
    const v = term.assistViewAt(x, y);
    let speed = 0;
    if (v && v.contentHeight > v.height) {
      const top = v.mapToItem(term.chromeRef.dropHint, 0, 0).y;
      const shown = Math.max(0, top);
      const bottom = Math.min(term.chromeRef.dropHint.height, top + v.height);
      const e = term.dragEdge;
      const up = y < shown + e ? (shown + e - y) / e : 0;
      const down = y > bottom - e ? (y - (bottom - e)) / e : 0;
      // squared: the outer part of the zone creeps, the edge runs. In
      // pixels a SECOND, not a tick — see assistTick.
      const top_ = term.assistTopSpeed(v);
      speed = up > 0 ? -top_ * Math.min(1, up) * Math.min(1, up)
            : down > 0 ? top_ * Math.min(1, down) * Math.min(1, down) : 0;
    }
    term.assistView = v;
    term.assistSpeed = speed;
    term.springCheck();
  }
  // Measured in ROWS, not pixels. A list row is 26px and a grid tile is
  // several times that, so one pixel speed for both carried a list past
  // its rows at a run and walked a grid past its tiles — the grid felt slow
  // because, row for row, it was. About thirty rows a second at the edge in
  // either, with the list's old pace as the floor.
  function assistTopSpeed(v) {
    const pitch = (v && v.cellHeight) ? v.cellHeight : term.rowH;
    return Math.max(1750, pitch * 30);
  }
  function dragAssistStop(hold) {
    term.assistSpeed = 0;
    term.assistView = null;
    springTimer.stop();
    term.springDir = "";
    term.dropViaFile = false;
    if (hold === true) {
      term.springHeld = term.springHeld.concat(term.springOpened);
      term.springOpened = [];
    } else term.springShut();
  }
  Timer {
    id: assistTick
    interval: 16
    repeat: true
    running: term.assistSpeed !== 0 && term.assistView !== null
    // BY THE CLOCK, not by the tick. A grid of thumbnails does not draw at
    // sixty frames while it scrolls, and a fixed step per tick slowed down
    // exactly where there was most to draw.
    property real last: 0
    onRunningChanged: assistTick.last = Date.now()
    onTriggered: {
      const v = term.assistView;
      if (!v) return;
      const now = Date.now();
      const dt = Math.min(0.1, (now - assistTick.last) / 1000);
      assistTick.last = now;
      const lo = v.originY || 0;
      const hi = lo + Math.max(0, v.contentHeight - v.height);
      const y = Math.max(lo, Math.min(hi, v.contentY + term.assistSpeed * dt));
      if (y === v.contentY) return;
      v.contentY = y;
      // the rows moved under a pointer that did not
      term.dropDir = term.dropDirAt(term.assistAt.x, term.assistAt.y);
      term.springCheck();
    }
  }
  function springCheck() {
    const side = term.assistSideAt(term.assistAt.x);
    const d = term.dropDir;
    const ok = d !== "" && !term.dropViaFile
      && !term.dragPaths.some((p) => d === p || d.indexOf(p + "/") === 0);
    if (!ok) { springTimer.stop(); term.springDir = ""; return; }
    if (term.dropDir === term.springDir && springTimer.running) return;
    term.springDir = term.dropDir;
    term.springSide = side;
    springTimer.restart();
  }
  Timer {
    id: springTimer
    interval: term.springMs
    onTriggered: {
      const dir = term.springDir;
      if (dir === "" || term.dropDir !== dir) return;
      term.springDir = "";
      // IN THE LIST A HOLD ONLY EVER OPENS THE BRANCH — it never goes in.
      // The list already shows a directory's contents in place, so walking
      // into one is not what you are asking for; there is no second stage.
      // An open directory, or an empty one with nothing to disclose, stays as
      // it is, and so does which pane is active.
      //
      // The chevron's own path, scroll hold and all, because it is the one
      // that already keeps the rows under the pointer where they were and
      // the cursor on its file — see root.scrollHold.
      const pane = !term.dual || term.springSide === term.paneSide
        ? term.act : term.pas;
      if (pane.treed) {
        if (pane.isOpen(dir) || term.dirEmpty[dir] === true) return;
        if (term.dual) term.activatePane(term.springSide);
        term.scrollHold = term.keepScroll();
        term.previewRef.scrollHoldExpiry.restart();
        pane.setOpen(dir, true);
        term.springOpened = term.springOpened.concat([{ pane: pane, dir: dir }]);
        return;
      }
      if (term.dual) term.activatePane(term.springSide);
      term.goTo(dir);
      term.dropDir = "";
    }
  }
  Timer {
    id: springGrace
    interval: 1000
    onTriggered: term.springShut(term.springHeld)
  }
  function springShut(list) {
    const held = list !== undefined;
    const opened = held ? list : term.springOpened;
    if (opened.length === 0) return;
    if (held) term.springHeld = []; else term.springOpened = [];
    term.scrollHold = term.keepScroll();
    term.previewRef.scrollHoldExpiry.restart();
    for (let i = opened.length - 1; i >= 0; --i) {
      const o = opened[i];
      if (o.pane.isOpen(o.dir)) o.pane.setOpen(o.dir, false);
    }
    // a collapse lands nothing, so nothing else would put the view back
    if (term.scrollHold) term.settleScroll();
  }
  // The row under the pointer in one particular view, or "" for none of it.
  //
  // mapFromItem rather than hand-rolled offsets: the second pane's views are
  // nested a level deeper than the first pane's, and arithmetic written here
  // would have to know that and would break the day it moves. indexAt wants
  // CONTENT coordinates, which is what contentX/contentY add back.
  function dropRowAt(v, rows, x, y, pane) {
    if (!v || !v.visible || !rows) return "";
    const p = v.mapFromItem(term.chromeRef.dropHint, x, y);
    if (p.x < 0 || p.y < 0 || p.x > v.width || p.y > v.height) return "";
    const i = v.indexAt(p.x + v.contentX, p.y + v.contentY);
    if (i < 0 || i >= rows.length) return "";
    const r = rows[i];
    if (!r) return "";
    if (r.isDir) return r.path;
    // Anything else means the directory it is sitting in. At the top of the
    // listing that is the pane's own directory, which is what the empty
    // space already means — but a file INSIDE AN OPEN BRANCH is sitting in
    // that branch, and dropping on it has to put things there. Opening a
    // directory on hold (springTimer) is what makes those rows appear under a
    // drag; landing the drop in cwd instead would be the wrong place with
    // the right directory in plain view. Depth, not the path, says which: a
    // collection's top-level rows live all over the disk.
    if (pane && pane.treed && pane.depthOf(r.path) > 0) {
      const owner = Terminus.dirname(r.path);
      if (owner !== "") {
        term.dropViaFile = true;
        return owner;
      }
    }
    return "";
  }
  // One curl per URL, through the ordinary action queue so they arrive in the
  // order they were dropped and the listing refreshes when each one lands.
  //
  // The LAST one is the one landed on, which is the one you were looking at
  // when you let go of a single drop and a reasonable answer for several.
  function fetchInto(urls, dest) {
    for (const u of urls) {
      const name = Terminus.urlFallbackName(u);
      term.wantSel = Terminus.joinPath(dest, name);
      term.run(Terminus.fetchUrlCommand(u, dest, name));
    }
    term.status = urls.length === 1 ? "fetching\u2026"
      : "fetching " + urls.length + "\u2026";
  }
  // EVERY WAY A DRAG CAN NAME WHAT IT IS CARRYING.
  //
  // `urls` is the parsed list and it is the right answer when there is one.
  // But a picture dragged off a web page does not always arrive that way:
  // Firefox offers text/x-moz-url, which is the address on one line and the
  // page's title on the next, and a drag carrying only that left `urls` empty
  // — so the drop was read as "nothing we can use" and silently ignored. That
  // is most of why dragging an image in from a browser did nothing.
  function urlsFrom(d) {
    if (d.urls && d.urls.length > 0) return d.urls;
    const out = [];
    const take = (text) => {
      for (const line of String(text || "").split(/[\r\n]+/)) {
        const t = line.trim();
        // The title line of a moz-url, and the comment lines a uri-list is
        // allowed to carry, are not addresses.
        if (t === "" || t.charAt(0) === "#") continue;
        if (t.indexOf("http://") === 0 || t.indexOf("https://") === 0
            || t.indexOf("file://") === 0) out.push(t);
      }
    };
    if (d.hasUrls) take(d.text);
    for (const f of ["text/uri-list", "text/x-moz-url", "text/plain"]) {
      if (out.length > 0) break;
      if (d.formats && d.formats.indexOf(f) >= 0) take(d.getDataAsString(f));
    }
    return out;
  }
  // `extra` is optional: menu entries offered beside Move and Copy — the
  // sidebar adds "Add to bookmarks" when what is dropped could become one.
  function dropUris(urls, action, dest, atItem, atX, atY, extra) {
    const more = extra || [];
    const into = (dest && dest !== "") ? dest : term.cwd;
    const paths = [];
    // THINGS DROPPED IN FROM OUTSIDE THE MACHINE. An image dragged off a web
    // page is not a file and never was — it arrives as an http address, and
    // this used to discard it along with the text selections and the colours,
    // so dragging a picture out of a browser into a file manager did nothing
    // at all. Dropping one HERE plainly means "keep this here", so it is
    // fetched into the directory it landed on.
    const remote = [];
    // A drop with nothing we can use — a text selection, a colour — is not
    // for us. Now that the DropArea takes everything, this is the filter.
    if (!urls || urls.length === 0) return;
    for (const u of urls) {
      const t = String(u);
      if (t.indexOf("http://") === 0 || t.indexOf("https://") === 0) {
        remote.push(t);
        continue;
      }
      const path = Terminus.pathFromUri(t);
      if (path === "") continue;
      // dropping a directory into itself is not a move, it is a mistake —
      // and neither is dropping one into something it contains, which mv
      // refuses anyway ("cannot move a directory into itself"). Catching it
      // here means the answer is nothing happening rather than an error.
      if (path === into || Terminus.dirname(path) === into) continue;
      if (into.indexOf(path + "/") === 0) continue;
      paths.push(path);
    }
    if (remote.length > 0) term.fetchInto(remote, into);
    if (paths.length === 0 && more.length === 0) return;
    const names = paths.map((p) => Terminus.basename(p));
    const drop = (op) => {
      term.setPending({ op: op, paths: paths, names: names });
      term.pasteDest = into === term.cwd ? "" : into;
      term.pastePending();
      // the branches a drag opened stay a moment longer — see springGrace
      springGrace.restart();
    };
    // ASKED WHERE IT WAS DROPPED, not in the middle of the screen.
    //
    // This was a confirm card: a drop that had just landed on a particular
    // directory threw a dialog into the centre of the window, and answering it
    // meant travelling back from where the pointer already was. A small menu
    // at the release point is the same question asked in the place the answer
    // is about — and it is dismissed the way every other menu is, so letting
    // go of the idea costs an Escape or a click rather than finding "Cancel".
    //
    // The dragged action is still offered FIRST, so the modifier held during
    // the drag is the one Return takes: the menu confirms the guess rather
    // than discarding it.
    const moving = action === Qt.MoveAction;
    const moveHere = { label: "Move here", act: () => drop("move") };
    const copyHere = { label: "Copy here", act: () => drop("copy") };
    const order = paths.length === 0 ? []
      : (moving ? [moveHere, copyHere] : [copyHere, moveHere]);
    for (const m of more) order.push(m);
    order.push({ sep: true });
    // Abort is spelled out rather than left to Escape: a menu that appeared
    // under your hand should be dismissable by the same hand.
    order.push({ label: "Abort", act: () => {} });
    // ── ON A LAYER, NOT IN A POPUP ────────────────────────────────────
    // This used menu.openCustom, which puts the card in an xdg_popup
    // parented to this window. A popup stacks above its OWN parent and
    // nothing else — so dragging from a terminus window that partly covers
    // the destination put the question underneath the window you had just
    // dragged out of, with no way to answer it.
    //
    // A layer at the Overlay level is above every toplevel there is, which
    // is the only placement that cannot be covered. Raising the destination
    // window instead would have been the smaller change and is not
    // available: hyprland's misc:focus_on_activate is off by default, so an
    // xdg-activation request from a client is ignored — as it should be, or
    // any program could pull itself in front of what you were doing.
    term.dropAskRef.show(order);
    return true;
  }
}
