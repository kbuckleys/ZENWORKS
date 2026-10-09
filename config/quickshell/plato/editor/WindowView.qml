// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One nvim window: a split, or the whole editor when there is only one.
//
// Placed where nvim put it on its grid, and sized in its cells. Its gutter —
// number and sign columns — is nvim's to size and this file's to draw: rows
// start their text `textoff` cells in.
//
// ── ROWS ARE A POOL, AND A SCROLL MOVES THEM ─────────────────────────
// Each row item holds one LINE (one wrapped piece of one, "n:k"), not one
// screen position. When the view scrolls, the lines already drawn keep their
// items and those items only move; the only rows laid out again are the ones
// that came into view, and the ones nvim says changed. The first version tied
// items to positions, so every notch of the wheel re-laid every row on the
// screen — and kept a trail of rows that had scrolled out, rebuilt whole on
// every frame, for the glide to uncover. That was the choppiness.
//
// The pool is three screens deep: the screen, and up to a screen above and
// below of rows that just left it — drawn outside the view while the glide
// finishes, so what it uncovers is the text that was there.
//
// ── SCROLLING IS CONTINUOUS, THOUGH NVIM'S IS NOT ────────────────────
// nvim scrolls in whole rows. There are two positions:
//
//   actual   rows nvim has scrolled, counted off the frames
//   pos      where the content is DRAWN, which closes on `actual` by the
//            shell's one glide (morpheus/scrollfeel.js follow)
//
// The follow only moves where it is heading when a notch lands mid-glide, so
// notch after notch is one motion, however fast they come; the content is drawn
// (actual − pos) rows away from where nvim has it and closes the gap as it
// goes. Keys that scroll (<C-d>, zz, j at the edge) glide the same way. A
// jump of more than a screen is a jump: the drawing lands at once.
//
// AND THE EDGES GIVE. A wheel that asks past the top or the end, where nvim
// has nowhere to go, stretches the content by morpheus' rubber band
// (Elastic.pull, Apple's curve) and lets it settle back over Zenon.elastic —
// the same answer to "there is no more" as every list in the shell.
//
// THE CURRENT LINE is terminus' cursor (terminus/SelectBar.qml): one bar,
// sliding between lines, covering every row of a wrapped one.
//
// THE SCROLLBAR is the shell's one scrollbar (morpheus' ScrollRail). It needs
// a Flickable, and this is not one, so it is given a stand-in that holds the
// file's length and nvim's top line; dragging it tells nvim where to go.

import QtQuick
import "../../morpheus"
import "../../terminus"
import "../../morpheus/scrollfeel.js" as Feel
import "../../morpheus/lagnotes.js" as LagNotes

Item {
  id: win

  required property var modelData
  required property var ed
  required property var client
  required property real cellW
  required property real cellH
  required property font face
  // the settings sheet's "Smooth scrolling": off, the drawing lands at once
  property bool smoothScroll: true
  // "Animate splits and tabs": a split's windows slide to their new places
  property bool animateLayout: true
  // "Changes in the gutter": git's bars, here and on the scrollbar
  property bool gitGutter: true
  // "Jump trail": a jump of a few lines or more leaves a streak behind it
  property bool jumpTrail: true
  // the settings' "Dim the splits you are not in"
  property bool dimInactive: true

  // modelData is the window's id; where it is and how big comes from the
  // layout, so a resize moves this item rather than replacing it
  readonly property var w: win.ed.winOf(win.modelData)
    || { id: win.modelData, row: 0, col: 0, width: 1, height: 1, textoff: 0, current: false }

  x: win.w.col * win.cellW
  y: win.w.row * win.cellH
  // THE RIGHTMOST WINDOW REACHES THE EDITOR'S LIVE EDGE. While the tree
  // slides, the editor's size is held back from nvim (one resize when it
  // lands, not one a frame), so nvim's columns were the OLD width for the
  // whole slide — and then the window, and the current line's bar with it,
  // caught up on a second animation after the slide: the bar's end jumped.
  // A window that ends at the grid's right edge is drawn to the editor's
  // edge as it is NOW (`liveW`), so the bar and the scrollbar travel with
  // the tree; text is drawn from the left and never notices.
  property real liveW: -1
  readonly property bool atRight: win.liveW > 0 && win.w.col + win.w.width >= win.ed.gridCols
  width: win.atRight ? Math.max(win.cellW, win.liveW - win.x) : win.w.width * win.cellW
  height: win.w.height * win.cellH
  clip: true
  Behavior on x { enabled: win.animateLayout; NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
  Behavior on y { enabled: win.animateLayout; NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
  Behavior on width { enabled: win.animateLayout && !win.atRight; NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
  Behavior on height { enabled: win.animateLayout; NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }

  // ── the scroll ─────────────────────────────────────────────────────
  property real actual: 0
  property real pos: 0
  // THE SHELL'S ONE GLIDE (morpheus/scrollfeel.js follow, what Elastic
  // moves every list with): `pos` closes on `actual` exponentially, so a
  // notch landing mid-glide only moves where it is heading. Not while the
  // scrollbar is held: the text follows the hand, as it does on the
  // minimap, rather than gliding behind it.
  function glide() {
    thrown.stop();
    if (!win.smoothScroll || win.byHand) { follow.stop(); win.pos = win.actual; return; }
    if (!follow.running) follow.start();
  }
  // ── how the glide's frames came, for lag.log ──────────────────────
  // Scrolling in a split felt poor (user, 2026-10-09) and nothing offscreen
  // can see a GPU: the glide's own frame intervals are the window's real
  // pacing. One line per glide of any length, split or single.
  property var paceRun: null
  function paceEnd() {
    const r = win.paceRun;
    win.paceRun = null;
    if (!r || r.n < 12) return;
    // a library script can outlive a live reload: until the shell restarts
    // the copy in memory may be the one from before report() existed
    if (typeof LagNotes.report !== "function") return;
    LagNotes.report("plato scroll " + (win.ed.winIds.length > 1 ? "split" : "single") + ": "
      + r.n + " frames, avg " + (r.sum / r.n).toFixed(1) + "ms, worst " + Math.round(r.max)
      + "ms, " + r.late + " over 25ms");
  }
  FrameAnimation {
    id: follow
    onRunningChanged: if (!follow.running) win.paceEnd()
    onTriggered: {
      const ft = follow.frameTime * 1000;
      if (!win.paceRun) win.paceRun = { n: 0, sum: 0, max: 0, late: 0 };
      else {
        const r = win.paceRun;
        r.n++; r.sum += ft; r.max = Math.max(r.max, ft); if (ft > 25) r.late++;
      }
      const h = Math.max(1, win.cellH);
      const px = Feel.follow(win.pos * h, win.actual * h, follow.frameTime * 1000);
      // settled: the edge rows the glide's ghosts were holding off take
      // their places (see place's ONE ROW PER PLACE)
      if (px === win.actual * h) { win.pos = win.actual; follow.stop(); refill.restart(); }
      else win.pos = px / h;
    }
  }
  // The hand is on the bar — and for a moment after it lets go: the last
  // scrollTo is sent 16 ms late and its frame comes back later still, and
  // landing as a glide it slid the text on after the thumb had stopped.
  readonly property bool byHand: rail.dragging || win.mapHeld || handTail.running
  // the thumb is held (EditorView keeps the pointer an arrow meanwhile)
  readonly property bool railDragging: rail.dragging
  Timer { id: handTail; interval: 250 }
  Connections {
    target: rail
    function onDraggingChanged() { if (!rail.dragging) handTail.restart(); }
  }
  // THE MINIMAP IS A HAND TOO: held, it scrolls this window through the
  // bar's own throttle (handTo), one scroll in flight. Sent on every move
  // of the pointer, its scrolls queued in the socket and the text trailed
  // the hand, gliding on after it had stopped.
  property bool mapHeld: false
  onMapHeldChanged: if (!win.mapHeld) handTail.restart()
  function handTo(line) {
    dragTo.line = Math.max(1, line);
    if (!dragTo.running) dragTo.start();
  }
  // with the minimap out, the minimap is the scrollbar: none here
  property bool railShown: true
  // Where the content is drawn: the rows nvim is ahead of the drawing.
  readonly property real lag: (win.actual - win.pos) * win.cellH

  // A JUMP TO AN END ARRIVES WITH ITS MOMENTUM: gg or G scrolls the screen
  // in and carries on past the edge it reached, the way a coast runs into
  // an edge and gives, then settles — one curve (OutBack), not a scroll and
  // then a separate bounce. The overshoot is about a twentieth of the
  // screen, half of what the wheel's band may stretch (Elastic.maxRaw).
  function throwIn() {
    follow.stop();
    thrown.from = win.pos;
    thrown.to = win.actual;
    thrown.restart();
  }
  NumberAnimation {
    id: thrown
    target: win
    property: "pos"
    duration: Zenon.elastic
    easing.type: Easing.OutBack
    easing.overshoot: 1.2
    onFinished: refill.restart()
  }

  // the top line last frame, to tell which way a jump went
  property int lastTopLine: 0

  // the cursor's line, counted as the gutter counts (see EditorRow.ord)
  property int curOrd: 0

  // What the first row showed last frame, to measure a scroll against.
  property var lastTop: null
  // the buffer the rows were last from (see place's ANOTHER FILE)
  property var lastBuf: null
  property var oldRows: null
  function topKey(r) { return r ? r.n + ":" + r.k : ""; }

  // How far the view moved since the last frame, in rows (down positive),
  // 0 for not at all, or null for a jump — further than a screen, or
  // somewhere none of the old rows are.
  function measureScroll(rows) {
    const was = win.lastTop;
    win.lastTop = win.topKey(rows[0]);
    const before = win.oldRows;
    win.oldRows = rows.slice();
    if (was === null || was === win.lastTop) return 0;
    // Where did the old top row go? Down by k: the view scrolled up by k.
    // And where was the new top row? Up by k: the view scrolled down.
    let shift = 0;
    for (let i = 1; i < rows.length; ++i)
      if (win.topKey(rows[i]) === was) { shift = -i; break; }
    if (shift === 0 && before) {
      for (let i = 1; i < before.length; ++i)
        if (win.topKey(before[i]) === win.lastTop) { shift = i; break; }
    }
    if (shift === 0 || Math.abs(shift) >= rows.length) return null;
    return shift;
  }

  function land() {
    follow.stop();
    thrown.stop();
    win.actual = 0;
    win.pos = 0;
  }

  // ── handing lines to rows ───────────────────────────────────────────
  function keyOf(r, i) { return r.n > 0 ? r.n + ":" + r.k : "~" + i; }
  // everything a row draws: a field left out here is a change never drawn
  // (git's bar, `v`, once was — it stayed stale until the text changed)
  function sigOf(r) {
    return r.n + "\u0001" + r.k + "\u0001" + r.t + "\u0001" + JSON.stringify(r.s)
      + "\u0001" + JSON.stringify(r.g || 0) + "\u0001" + r.f + "\u0001" + (r.v || "")
      + "\u0001" + (r.ig ? Array.from(r.ig).join(",") : "")
      + "\u0001" + JSON.stringify([r.m || 0, r.sl || 0, r.vt || 0, r.fc || 0, r.md || 0, r.fo || 0]);
  }
  // ── what a frame's place() cost, for lag.log ──────────────────────
  // Scrolling stalled ~100 ms a few times a second, split or not, with no
  // slow message from nvim beside it (2026-10-09): the cost is in here or
  // in laying out the rows it hands new text. Both are timed; a frame of
  // 30 ms or more is named with how many rows changed.
  property var placeChanged: []
  function place() {
    const lagT0 = Date.now();
    win.placeChanged = [];
    win.placeBody();
    const t1 = Date.now();
    const changed = win.placeChanged;
    win.placeChanged = [];
    for (const it of changed) { try { it.layoutNow(); } catch (e) {} }
    const t2 = Date.now();
    if (t2 - lagT0 >= 30)
      LagNotes.mark("plato place " + changed.length + " rows new (" + (t1 - lagT0) + " ms placing, "
        + (t2 - t1) + " ms laying out)", lagT0);
  }
  function placeBody() {
    const rows = win.ed.rowsOf(win.w.id);
    const h = rows.length;
    if (h === 0) return;
    const ords = win.ed.ordsOf(win.w.id);
    // ── ANOTHER FILE IS NOT A SCROLL ─────────────────────────────────
    // Rows are keyed by line number, so the lines of the file just left
    // matched the new one's and were taken for a scroll: the rows kept past
    // the edges for the glide went on holding the OLD file, and the frost
    // under the tabs and the status line (which draws exactly those) showed
    // it until a scroll replaced them. A change of buffer is a jump. (`buf`
    // comes with the frame; the editor's file stands in for the current
    // window if an older engine does not send it.)
    const sc = win.ed.scrollOf(win.w.id);
    const bufNow = sc.buf !== undefined ? String(sc.buf) : (win.w.current ? win.ed.file : win.lastBuf);
    const swapped = win.lastBuf !== null && bufNow !== win.lastBuf;
    win.lastBuf = bufNow;
    const measured = win.measureScroll(rows);
    let shift = swapped ? null : measured;
    // A JUMP STILL SCROLLS. gg, G, a far search: nvim sends only the screen
    // it landed on, so the lines in between were never there to glide past
    // — and landing at once lost the eye. Taken as a scroll of one screen
    // the way it went: the screen you were on slides out (its rows kept as
    // the glide's ghosts, as any scroll keeps them) and the new one slides
    // in behind it, on the same glide. Not for another file, nor with
    // smooth scrolling off.
    let edgeJump = false;
    if (shift === null && !swapped && win.smoothScroll && win.lastTopLine > 0
        && (sc.top || 0) !== win.lastTopLine) {
      shift = (sc.top > win.lastTopLine ? 1 : -1) * h;
      // ...and one that lands on the first or the last line (gg, G) runs
      // past that edge and back in the SAME motion (see `thrown`)
      const c = win.ed.cursorOf(win.w.id);
      const line = rows[c.row] ? rows[c.row].n : 0;
      edgeJump = win.w.current && line > 0
        && ((line === 1 && sc.top === 1) || (line === sc.lines && rows.some((r) => r.n === sc.lines)));
    }
    // A FOLD OPENED OR CLOSED, and nothing scrolled: the rows already drawn
    // slide to their new places and the rows uncovered fade in (see the
    // pool's delegate). Only then — a row moving because of an edit (o, dd)
    // lands at once, so typing never waits on a slide.
    const folds = rows.filter((r) => r.f).map((r) => r.n).join(",");
    const toggled = win.lastFolds !== null && folds !== win.lastFolds && shift === 0;
    win.lastFolds = folds;
    if (toggled && win.animateLayout) { win.settling = true; settleDone.restart(); }

    const items = [];
    for (let i = 0; i < pool.count; ++i) {
      const it = pool.itemAt(i);
      if (it) items.push(it);
    }

    if (shift === null) {
      // a jump: nothing drawn is anywhere near where it is going
      win.land();
      for (const it of items) { it.key = ""; it.sig = ""; }
    } else if (shift !== 0) {
      for (const it of items) if (it.key !== "") it.pos -= shift;
      win.actual += shift;
      // never further behind than the rows kept to cover it
      if (Math.abs(win.actual - win.pos) > h)
        win.pos = win.actual - Math.sign(win.actual - win.pos) * h;
      if (edgeJump) win.throwIn(); else win.glide();
    }

    // where each row was drawn, sliding included, before this frame
    const wasSlide = {};
    if (win.moveNext) for (const it of items) if (it.key !== "") wasSlide[Math.round(it.pos)] = it.slide;
    // which items were showing a line before this frame (for the fold's
    // arrivals): the rest are new to the screen
    const wasAt = new Set(items.filter((it) => it.key !== "" && it.pos >= 0 && it.pos < h));
    const byKey = {};
    for (const it of items) if (it.key !== "") byKey[it.key] = it;
    const at = new Array(h);
    const taken = new Set();
    for (let i = 0; i < h; ++i) {
      const it = byKey[win.keyOf(rows[i], i)];
      if (it) { at[i] = it; taken.add(it); }
    }
    // Rows no longer on screen: gone, if they should have been on it (an
    // edit took their line away); kept for the glide, if they scrolled out
    // and are within a screen of the edge; let go of beyond that.
    const free = [];
    const ghosts = [];
    for (const it of items) {
      if (taken.has(it)) continue;
      if (it.key === "" || (it.pos >= 0 && it.pos < h) || it.pos < -h || it.pos >= 2 * h) {
        it.key = "";
        it.sig = "";
        free.push(it);
      } else {
        it.ord = -1;
        ghosts.push(it);
      }
    }
    // the farthest ghost goes first when the pool runs short
    ghosts.sort((a, b) => Math.abs(a.pos - h / 2) - Math.abs(b.pos - h / 2));
    for (let i = 0; i < h; ++i) {
      let it = at[i];
      if (!it) {
        it = free.pop() || ghosts.pop();
        if (!it) continue;
        it.key = win.keyOf(rows[i], i);
        at[i] = it;
      }
      // uncovered by a fold: in from nothing
      if (win.settling && it.key !== "" && !wasAt.has(it)) it.arrive();
      it.pos = i;
      it.ord = ords[i];
      // nvim diffs by screen position, so after a scroll it resends rows
      // that only moved: what they say is compared, not which object it is
      if (it.info !== rows[i]) {
        const sig = win.sigOf(rows[i]);
        if (sig !== it.sig) { it.sig = sig; it.info = rows[i]; win.placeChanged.push(it); }
      }
    }
    if (win.moveNext) {
      const mv = win.moveNext;
      win.moveNext = null;
      if (shift !== null && Date.now() - mv.at < 500) win.slideMoved(at, h, mv, shift, wasSlide);
    }
    if (win.igPending) {
      const g = win.igPending;
      win.igPending = null;
      if (shift === 0 && win.animateLayout && Date.now() - g.at < 500) {
        igClose.stop();
        igOpen.stop();
        win.igRow = g.row;
        if (g.open) {
          win.igCol = g.col + g.n;
          win.igNew = g.n;
          win.igW = -g.n * win.cellW;
          igOpen.start();
        } else {
          win.igCol = g.col;
          win.igNew = 0;
          win.igW = g.n * win.cellW;
          igClose.start();
        }
      }
    }
    if (win.gapPending) {
      const g = win.gapPending;
      win.gapPending = null;
      // only a delete that left the view where it was (one at the end of
      // the file that scrolled it is a scroll, and glides as one)
      if (shift === 0 && win.animateLayout && Date.now() - g.at < 500) {
        gapClose.stop();
        gapOpen.stop();
        if (g.open) {
          win.gapRow = g.row + g.n;
          win.gapH = -g.n * win.cellH;
          for (let p = g.row; p < Math.min(h, g.row + g.n); ++p) if (at[p]) at[p].arrive();
          gapOpen.start();
        } else {
          win.gapRow = g.row;
          win.gapH = g.n * win.cellH;
          gapClose.start();
        }
      }
    }
    // ── AND THE ROWS PAST THE EDGES ───────────────────────────────────
    // nvim draws a few lines beyond the window's top and bottom with every
    // frame (view.lua's margin); they go just outside the window — clipped
    // from sight, captured by the frost under the tab strip and the status
    // line, which is then the file as it is now, edits and all, and not
    // only the rows the glide happened to keep.
    const edges = win.ed.edgesOf(win.w.id);
    // ── ONE ROW PER PLACE ───────────────────────────────────────────
    // After a jump the screen just left is kept as ghosts from h on (or
    // above 0), for the glide to slide out — the very places the edge rows
    // go. An edge row took another item and left the ghost where it was, so
    // once the glide settled the two were drawn in one place: the stale line
    // over the live one in the strip above the status line (Buck's capture,
    // 2026-10-08: line 14xx of the file just left, over line 39). While the
    // glide runs the ghost is what should show, and the edge row waits; at
    // rest (follow and `thrown` both call refill) the ghost is let go.
    const gliding = follow.running || thrown.running;
    const edgeAt = (r, p) => {
      const key = win.keyOf(r, -1);
      const occ = ghosts.find((g) => Math.round(g.pos) === p);
      if (occ && occ.key !== key) {
        if (gliding) return;
        occ.key = "";
        occ.sig = "";
        ghosts.splice(ghosts.indexOf(occ), 1);
        free.push(occ);
      }
      let it = byKey[key];
      if (it && (taken.has(it) || it.key !== key)) it = null;
      if (!it) {
        it = free.pop() || ghosts.pop();
        if (!it) return;
        it.key = key;
      }
      taken.add(it);
      it.pos = p;
      it.ord = -1;
      if (it.info !== r) {
        const sig = win.sigOf(r);
        if (sig !== it.sig) { it.sig = sig; it.info = r; win.placeChanged.push(it); }
      }
    };
    for (let i = 0; i < edges.above.length; ++i) edgeAt(edges.above[i], i - edges.above.length);
    for (let i = 0; i < edges.below.length; ++i) edgeAt(edges.below[i], h + i);

    win.curOrd = ords[win.ed.cursorOf(win.w.id).row] || 0;
    // the selection's rows, for the one shape drawn over them
    const parts = [];
    for (let i = 0; i < h; ++i) {
      const sl = rows[i].sl;
      if (sl) parts.push([i, sl[0], sl[1]]);
    }
    const key = JSON.stringify(parts);
    if (key !== selection.key) { selection.key = key; selection.parts = parts; }
    content.seatBar(shift !== 0);
    win.noteJump(rows, shift);
    win.lastTopLine = sc.top || 0;
  }


  // ── THE JUMP TRAIL ─────────────────────────────────────────────────
  // gg, G, n, a definition: the cursor arrives somewhere far off, and the
  // eye has lost it. A jump of JUMP lines or more leaves a streak down the
  // cursor's column from where it was, and a ghost of the cursor there,
  // both fading out. Drawn in the content, so it rides the scroll glide; a
  // jump past the screen streaks in from the edge it came over.
  readonly property int jumpMin: 6
  property int jumpLine: 0
  property int jumpRow: 0
  property int jumpCol: 0
  property string jumpFile: ""
  function noteJump(rows, shift) {
    if (!win.w.current) { win.jumpLine = 0; return; }
    const c = win.ed.cursorOf(win.w.id);
    const r = rows[c.row];
    const n = r ? r.n : 0;
    const same = win.jumpFile === win.ed.file;
    // a cursor carried along by the wheel (scrolloff) moved with the text:
    // only what it moved BEYOND the scroll counts as a jump
    const carried = shift === null ? 0 : shift;
    if (win.jumpTrail && same && win.jumpLine > 0 && n > 0 && Math.abs(n - win.jumpLine - carried) >= win.jumpMin
        && win.ed.modeName !== "insert" && win.ed.modeName !== "command") {
      const h = rows.length;
      const from = shift === null ? (n > win.jumpLine ? -1.5 : h + 0.5) : win.jumpRow - shift;
      trail.fire(from, win.jumpCol, c.row, c.col);
    }
    win.jumpLine = n;
    win.jumpRow = c.row;
    win.jumpCol = c.col;
    win.jumpFile = win.ed.file;
  }

  Connections {
    target: win.ed
    function onFrameChanged() { win.place(); win.syncBar(); win.dragLanded(); }
  }
  // the row pool's size — see THE POOL ONLY GROWS, at the pool
  readonly property int poolWant: Math.max(1, win.w.height) * 3
  onPoolWantChanged: win.growPool()
  function growPool() {
    const n = win.poolWant - poolSlots.count;
    if (n <= 0) return;
    const add = new Array(n);
    for (let i = 0; i < n; ++i) add[i] = { slot: poolSlots.count + i };
    poolSlots.append(add);
  }
  Component.onCompleted: { win.growPool(); win.place(); win.syncBar(); }

  // ── A MOVED LINE SLIDES ────────────────────────────────────────────
  // Alt j/k (mini.move) moves a line, or a selection, past its neighbour.
  // Rows are keyed by line number, so the drawing would only swap text in
  // place: instead the moved rows slide from where they were, and the rows
  // they passed slide the other way to fill the gap. nvim says where the
  // block was and where it is (editing.lua, kind "move"), a frame ahead of
  // the rows that show it — so it waits here for the next place().
  property var moveNext: null
  // `from` and `to` are rows of this window
  function slideNext(from, to, n) { win.moveNext = { from: from, to: to, n: n, at: Date.now() }; }
  function slideMoved(at, h, mv, shift, wasSlide) {
    if (!win.animateLayout) return;
    // a move that scrolled: the old rows, where they are now
    const a = mv.from - shift, b = mv.to, n = mv.n;
    const lo = Math.min(a, b), hi = Math.max(a, b) + n;
    for (let p = Math.max(0, lo); p < Math.min(h, hi); ++p) {
      const it = at[p];
      if (!it) continue;
      // the row this text was drawn on before the move
      const old = p >= b && p < b + n ? p - b + a : (b > a ? p + n : p - n);
      it.slideFrom((old - p) * win.cellH + (wasSlide[old] || 0));
    }
  }

  // ── DELETED LINES LEAVE THEIR ROOM, THEN IT CLOSES ──────────────────
  // dd, 3dd, Vjd: the lines went in one frame and the rows below jumped up
  // at once, so the delete's ghost (Flashes) was drawn over lines that had
  // NOT been deleted. Now the room they took is held — every row from the
  // first deleted one down sits `gapH` lower — while the ghost strikes
  // through in place, then the rows below slide up and the room closes.
  // nvim says which rows went (the linewise "delete" flash), a frame ahead
  // of the rows without them, so it waits here for the next place(), as a
  // move does. The bar and the caret ride the same gap (gapAt).
  property var gapPending: null
  property int gapRow: -1
  property real gapH: 0
  function gapNext(row, n) { win.gapPending = { row: row, n: n, at: Date.now() }; }
  // AND PLAYED FORWARDS, for a paste: the lines below start where they
  // were (gapH negative: n rows up) and slide down, opening the room the
  // new lines fade into (EditorRow.arrive). No hold — nothing to show first.
  function openNext(row, n) { win.gapPending = { row: row, n: n, at: Date.now(), open: true }; }
  SequentialAnimation {
    id: gapOpen
    NumberAnimation { target: win; property: "gapH"; to: 0; duration: 260; easing.type: Easing.OutCubic }
    ScriptAction { script: win.gapRow = -1 }
  }
  function gapAt(row) { return win.gapRow >= 0 && row >= win.gapRow ? win.gapH : 0; }
  SequentialAnimation {
    id: gapClose
    // the ghost's strike-through (Flashes: 110 + 40) first
    PauseAnimation { duration: 150 }
    NumberAnimation { target: win; property: "gapH"; to: 0; duration: 300; easing.type: Easing.InOutCubic }
    ScriptAction { script: win.gapRow = -1 }
  }

  // ── AND ACROSS: AN IN-LINE DELETE ──────────────────────────────────
  // x, dw, diw, d$ on one line: the text after the deleted cells is held
  // where it was (EditorRow's split, at igCol in text cells) while the
  // ghost plays, then slides left — the same hold and slide as the line
  // gap. The caret rides it (gapXAt).
  property var igPending: null
  property int igRow: -1
  property int igCol: -1
  property real igW: 0
  // cells of NEW text just before igCol (a paste), uncovered as the room
  // opens; 0 for a delete
  property int igNew: 0
  function inlineNext(row, col, n) { win.igPending = { row: row, col: col, n: n, at: Date.now() }; }
  // a paste in a line: the text after it starts where it was and slides
  // right, the pasted cells uncovered behind it
  function inlineOpenNext(row, col, n) { win.igPending = { row: row, col: col, n: n, at: Date.now(), open: true }; }
  SequentialAnimation {
    id: igOpen
    NumberAnimation { target: win; property: "igW"; to: 0; duration: 220; easing.type: Easing.OutCubic }
    ScriptAction { script: { win.igRow = -1; win.igCol = -1; win.igNew = 0; } }
  }
  function gapXAt(row, col) { return row === win.igRow && col >= win.igCol ? win.igW : 0; }
  SequentialAnimation {
    id: igClose
    PauseAnimation { duration: 150 }
    NumberAnimation { target: win; property: "igW"; to: 0; duration: 260; easing.type: Easing.InOutCubic }
    ScriptAction { script: { win.igRow = -1; win.igCol = -1; win.igNew = 0; } }
  }

  Timer { id: refill; interval: 0; onTriggered: win.place() }
  property var lastFolds: null
  property bool settling: false
  Timer { id: settleDone; interval: Zenon.normal + 60; onTriggered: win.settling = false }

  // ── the band ───────────────────────────────────────────────────────
  // Called by EditorView when a wheel notch could not scroll this window.
  // `raw` is how far past the edge the wheel has asked to go, in pixels.
  property real raw: 0
  property real bandY: 0
  Elastic { id: rubber }
  function band(delta) {
    settle.stop();
    const d = win.height;
    win.raw = Math.max(-rubber.maxRaw(d), Math.min(rubber.maxRaw(d), win.raw + delta));
    win.bandY = (win.raw < 0 ? -1 : 1) * rubber.pull(Math.abs(win.raw), d);
    letGo.restart();
  }
  Timer {
    id: letGo
    interval: 90
    onTriggered: { win.raw = 0; settle.from = win.bandY; settle.start(); }
  }
  NumberAnimation {
    id: settle
    target: win
    property: "bandY"
    to: 0
    duration: Zenon.elastic
    easing.type: Zenon.travelEase
  }

  // ── the rows (and the current line, and the cursor, which move with them)
  Item {
    id: content
    width: win.width
    height: win.height
    y: win.lag + win.bandY
    // THE SPLITS YOU ARE NOT IN STEP BACK, so where the keys go reads at a
    // glance; the current line's bar alone said it before
    opacity: win.dimInactive && !win.w.current && win.ed.winIds.length > 1 ? 0.55 : 1
    Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

    // The current line: terminus' cursor bar, over every row of it when it
    // wraps. Only in the window the cursor is in.
    //
    // SET IN place(), NOT BOUND. A frame that scrolled moves the bar's row by
    // exactly the rows the text moved, and the text is already gliding — the
    // bar sliding there as well (on the render thread, on its own clock) was
    // a second motion that trailed the line it marks, notch after notch. So
    // place() says whether the frame scrolled first, and the bar only slides
    // when the cursor went to another line in a view that stayed put.
    property int lineFirst: 0
    property int lineRows: 1
    // a bar just made is put on its line, not slid there from the top
    property bool barSnaps: true
    property bool seated: false
    function seatBar(scrolled) {
      // read off the frame itself: place() runs as the frame lands, before
      // bindings on it are sure to have caught up
      const o = win.ed.ordsOf(win.w.id), c = win.ed.cursorOf(win.w.id).row;
      let a = c, b = c;
      while (a > 0 && o[a - 1] === o[c]) a--;
      while (b + 1 < o.length && o[b + 1] === o[c]) b++;
      content.barSnaps = scrolled || !content.seated;
      content.seated = true;
      content.lineFirst = a;
      content.lineRows = b - a + 1;
    }
    Item {
      id: trail
      z: 3
      visible: trail.t < 1
      property real fromRow: 0
      property real fromCol: 0
      property real toRow: 0
      property real toCol: 0
      property real t: 1
      readonly property real x0: (win.w.textoff + trail.toCol) * win.cellW
      // the streak's tail draws in toward the cursor as it fades
      readonly property real yFrom: (trail.fromRow + (trail.toRow - trail.fromRow) * trail.t) * win.cellH
      readonly property real yTo: trail.toRow * win.cellH
      function fire(fr, fc, tr, tc) {
        trail.fromRow = fr; trail.fromCol = fc; trail.toRow = tr; trail.toCol = tc;
        trailRun.restart();
      }
      NumberAnimation on t { id: trailRun; running: false; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
      Rectangle {
        readonly property bool down: trail.yTo > trail.yFrom
        x: trail.x0 + win.cellW / 2 - 1
        y: Math.min(trail.yFrom, trail.yTo) + (down ? 0 : win.cellH)
        width: 2
        height: Math.abs(trail.yTo - trail.yFrom)
        radius: 1
        opacity: 0.7 * (1 - trail.t)
        gradient: Gradient {
          GradientStop { position: 0; color: parent.down ? "transparent" : Zenon.cyan }
          GradientStop { position: 1; color: parent.down ? Zenon.cyan : "transparent" }
        }
      }
      // where it was: the cursor's ghost
      Rectangle {
        visible: trail.fromRow >= 0 && trail.fromRow < win.w.height
        x: (win.w.textoff + trail.fromCol) * win.cellW
        y: trail.fromRow * win.cellH
        width: win.cellW
        height: win.cellH
        radius: 2
        color: "transparent"
        border.width: 1
        border.color: Zenon.cyan
        opacity: 0.8 * (1 - trail.t)
      }
    }

    SelectBar {
      within: content
      rowY: content.lineFirst * win.cellH + win.gapAt(content.lineFirst)
      rowH: Math.max(1, content.lineRows) * win.cellH
      animate: !content.barSnaps
      on: win.w.current && !win.ed.cmdlineShown && !win.ed.inFloat
    }

    // ── THE SELECTION, AS ONE SHAPE ──────────────────────────────────
    // Every row of it joined into one outline with rounded corners —
    // outside corners round out, the steps between rows round in — rather
    // than a square strip a row. view.lua sends each row's part (`sl`);
    // place() gathers them. Under the text, as the wash always was. A
    // selection that was not there a moment ago fades in.
    Selection {
      id: selection
      cellW: win.cellW
      cellH: win.cellH
      textX: win.w.textoff * win.cellW
      ink: Qt.rgba(win.ed.visualInk.r, win.ed.visualInk.g, win.ed.visualInk.b, win.ed.visualAlpha)
    }

    // ── A SEARCH JUMP, FOUND ─────────────────────────────────────────
    // n, N, *, # or a confirmed / land the cursor on a match: an outline
    // closes in on it from a little way out and fades, so the eye finds
    // where the jump went (view.lua's pulse).
    Rectangle {
      id: pulse
      z: 3
      visible: false
      property real gx: 0
      property real gy: 0
      property real gw: 0
      property real grow: 0
      x: pulse.gx - pulse.grow
      y: pulse.gy - pulse.grow
      width: pulse.gw + pulse.grow * 2
      height: win.cellH + pulse.grow * 2
      radius: 4 + pulse.grow / 2
      color: "transparent"
      border.width: 2
      border.color: Zenon.sand
      Connections {
        target: win.ed
        function onPulsed(hit) {
          if (hit.win !== win.w.id) return;
          pulse.gx = (win.w.textoff + hit.col) * win.cellW - 1;
          pulse.gy = hit.row * win.cellH;
          pulse.gw = Math.max(1, hit.len) * win.cellW + 2;
          pulseRun.restart();
        }
      }
      SequentialAnimation {
        id: pulseRun
        PropertyAction { target: pulse; property: "visible"; value: true }
        ParallelAnimation {
          NumberAnimation { target: pulse; property: "grow"; from: 7; to: 0; duration: 180; easing.type: Easing.OutCubic }
          NumberAnimation { target: pulse; property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutQuad }
        }
        PauseAnimation { duration: 260 }
        NumberAnimation { target: pulse; property: "opacity"; to: 0; duration: 420; easing.type: Easing.InOutQuad }
        PropertyAction { target: pulse; property: "visible"; value: false }
      }
    }

    // ── THE POOL ONLY GROWS ───────────────────────────────────────
    // It was `model: height * 3` — a NUMBER, and a Repeater handed a new
    // number destroys every row it has and makes them all again. So each
    // change of height rebuilt ~150 rows: twice on every open (a first
    // frame, then the real size), and again on every resize, split and tree
    // toggle — 55 + 76 ms of the open measured offscreen (2026-10-09). A
    // ListModel that is only ever appended to makes just the rows that are
    // new; rows a smaller window does not use stay free (key "", hidden),
    // which place() already treats as spare.
    ListModel { id: poolSlots }
    Repeater {
      id: pool
      model: poolSlots
      // a pool rebuilt (the window changed height) starts empty: fill it
      // a Timer, not Qt.callLater: it goes with the window, where a deferred
      // call could still run on a window a reload had already torn down
      onCountChanged: refill.restart()
      EditorRow {
        // the line this row holds ("" for none) and where it is, in rows
        // from the top of the view — negative, or past the bottom, while a
        // row that just scrolled out is still being uncovered
        property string key: ""
        property string sig: ""
        property real pos: 0
        visible: key !== ""
        y: pos * win.cellH + slide + win.gapAt(pos)
        // an in-line delete's room, held open (see AND ACROSS)
        gapCol: win.igRow >= 0 && pos === win.igRow ? win.igCol : -1
        gapW: win.igW
        gapNew: win.igRow >= 0 && pos === win.igRow ? win.igNew : 0
        // a moved line sliding to its place (see A MOVED LINE SLIDES)
        property real slide: 0
        NumberAnimation on slide { id: sliding; running: false; to: 0; duration: Zenon.normal; easing.type: Easing.OutCubic }
        function slideFrom(dy) {
          sliding.stop();
          slide = dy;
          if (dy !== 0) { sliding.from = dy; sliding.start(); }
        }
        Behavior on y {
          enabled: win.settling
          NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase }
        }
        // a row a fold uncovered fades in where it lands (EditorRow.enter)
        NumberAnimation on enter { id: arriving; running: false; from: 0; to: 1; duration: Zenon.normal; easing.type: Easing.OutCubic }
        function arrive() { arriving.restart(); }
        ed: win.ed
        cellW: win.cellW
        cellH: win.cellH
        face: win.face
        gutterW: win.w.textoff * win.cellW
        textX: win.w.textoff * win.cellW
        curOrd: win.curOrd
        relative: { win.ed.frame; return win.ed.scrollOf(win.w.id).rnu; }
        gitGutter: win.gitGutter
        // the window draws the selection whole (Selection above)
        ownSelection: false
        eofMark: true
        // the cursor's block: its guide drawn brighter, in this window only
        scope: win.w.current ? win.ed.scope : null
        // zen mode: only the cursor's paragraph at full strength
        dimmed: win.w.current && win.ed.para !== null && key !== ""
          && (info.n < win.ed.para[0] || info.n > win.ed.para[1])
      }
    }
  }
  // the editor's cursor is drawn by EditorView, in content's coordinates:
  // this is where it maps them from
  readonly property alias body: content

  // ── UNDER THE TABS AND THE STATUS LINE ─────────────────────────────
  // The text scrolled off this window's top (or not yet reached at its
  // bottom) carries on, frosted, under the tab strip and the status line —
  // morpheus/ScrollEdge, as every list in the shell has it. The rows are
  // there to capture: the pool keeps a screen of them either side for the
  // glide (see ROWS ARE A POOL), drawn outside this window and clipped.
  //
  // Not a Flickable, so it says what the edge needs: where the viewport
  // sits in `content`, and whether there is more past each end. The edges
  // live in `edgeHost`, a layer the plato window lays under both bars; only
  // a window that touches the bar gets one.
  readonly property Item contentItem: content
  readonly property real contentX: 0
  readonly property real contentY: -(win.lag + win.bandY)
  property Item edgeHost: null
  property Item topBar: null
  property Item bottomBar: null
  // the editor's own place, which moves (the tree sliding) without this
  property var edgeTrack: null
  // MORE PAST AN EDGE: nvim's own answer — rows past it (view.lua's margin).
  // Not the scrollbar's stand-in, which counts LINES: a short file of long
  // wrapped lines (30 lines, 50 rows) fits it, so its position stayed 0 and
  // the top never frosted however far the text had scrolled.
  readonly property bool moreAbove: { win.ed.frame; return win.ed.edgesOf(win.w.id).above.length > 0; }
  readonly property bool moreBelow: { win.ed.frame; return win.ed.edgesOf(win.w.id).below.length > 0; }

  // NO SCRIM OF ITS OWN: one per window stopped at the window's edge, and
  // the editor's inset beside the first column came out a darker sliver
  // under the first tab (user's capture, 2026-10-09). The plato window lays
  // one across each whole bar while any edge is on — see edgesAbove/Below.
  readonly property bool edgeAboveOn: topEdge.on
  readonly property bool edgeBelowOn: footEdge.on
  ScrollEdge {
    id: topEdge
    parent: win.edgeHost
    view: win
    follow: true
    scrim: 0
    bar: win.topBar
    track: win.edgeTrack
    scrolled: win.moreAbove
    visible: !!win.edgeHost && !!win.topBar && win.w.row === 0
  }
  ScrollEdge {
    id: footEdge
    parent: win.edgeHost
    view: win
    scrim: 0
    below: true
    follow: true
    bar: win.bottomBar
    track: win.edgeTrack
    scrolled: win.moreBelow
    visible: !!win.edgeHost && !!win.bottomBar
      && win.w.row + win.w.height >= win.ed.gridRows
  }

  // ── the scrollbar ──────────────────────────────────────────────────
  // A Flickable that is never shown and never flicked, only measured: its
  // content is the file's length in rows, its position nvim's top line. The
  // shell's scrollbar reads it and writes it; a write is a drag, and goes to
  // nvim as the line to show at the top.
  //
  // AS LONG AS THE FILE, NOT LONGER. It used to add a screen below the last
  // line — room for nvim's <C-e> to take the last line to the top — so a file
  // half a screen long had a scrollbar, and the bar led down into nothing.
  // Now there is a bar only when the file does not fit, and it ends with the
  // last line at the bottom.
  Flickable {
    id: proxy
    visible: false
    interactive: false
    width: win.width
    height: win.height
    contentWidth: win.width
    contentHeight: {
      win.ed.frame;
      const s = win.ed.scrollOf(win.w.id);
      return Math.max(win.height, s.lines * win.cellH);
    }
    property bool syncing: false
    // ONLY THE HAND SCROLLS NVIM. Lines deleted at the end (Vjjjc on the
    // last lines) shrink contentHeight, and the Flickable pulls contentY
    // back in bounds on its own: sent on as a drag, that scrolled nvim up,
    // and scrolloff dragged the cursor up off the line it had just made.
    onContentYChanged: {
      if (proxy.syncing || !rail.held) return;
      dragTo.line = Math.round(proxy.contentY / win.cellH) + 1;
      // start, NOT restart: restarting on every move put the send off for
      // as long as the hand kept moving, and the text only followed once
      // the drag paused
      if (!dragTo.running) dragTo.start();
    }
  }
  // One scroll a frame while the bar is dragged, not one per pixel: a
  // THROTTLE. The first move starts the clock; the moves inside the frame
  // only update the line; the frame's end sends the latest. A drag that
  // stops sends its last line the same way.
  Timer {
    id: dragTo
    interval: 16
    property int line: 1
    onTriggered: win.sendDrag()
    // ONE IN FLIGHT. A jump redraws the whole window; sent faster than
    // that takes, the scrolls queued in the socket and the text trailed
    // further behind the hand the longer the drag went on. The next one
    // goes when this one's frame lands — to wherever the bar is by then.
    property bool inFlight: false
    property int sent: 0
  }
  function sendDrag() {
    if (dragTo.inFlight) return;
    dragTo.inFlight = true;
    dragTo.sent = dragTo.line;
    flightCap.restart();
    win.client.scrollTo(win.w.id, dragTo.line);
  }
  function dragLanded() {
    if (!dragTo.inFlight) return;
    dragTo.inFlight = false;
    flightCap.stop();
    if (dragTo.line !== dragTo.sent) win.sendDrag();
  }
  // a frame that never comes (nothing moved, a lost reply) must not stop
  // the drag for good
  Timer { id: flightCap; interval: 150; onTriggered: win.dragLanded() }

  // THE BAR FOLLOWS THE DRAWING, not nvim: set to nvim's top line it jumped
  // there at once while the text was still gliding, and the two visibly
  // disagreed. Minus the glide's lag, they move as one.
  function syncBar() {
    if (rail.dragging) return;
    const s = win.ed.scrollOf(win.w.id);
    proxy.syncing = true;
    proxy.contentY = Math.max(0, Math.min(proxy.contentHeight - proxy.height,
      (s.top - 1) * win.cellH - win.lag));
    proxy.syncing = false;
  }
  onLagChanged: win.syncBar()
  // ── sticky scroll ──────────────────────────────────────────────────
  // The lines that open what the top of the view is inside, pinned over it
  // (see nvim/lua/plato/sticky.lua), in the window the cursor is in. A
  // click goes to that line. A hairline and a soft shadow under them say
  // the text runs on beneath.
  //
  // A BAR ACROSS THE WINDOW, HUNG FROM THE TAB STRIP (user, 2026-10-09: no
  // floating strip inset from the edges and off the tabs). A window that
  // touches the strip lays them in the plato window's stickyHost, from the
  // strip's bottom (stickyTop), from its left (stickyLeft) to the window's right edge, the editor's
  // inset counted in so each line still sits over its own row; the ground
  // is frost over the editor (stickySource). A split lower down keeps them
  // inside itself, frosting its own rows.
  property Item stickyHost: null
  property real stickyTop: 0
  property real stickyLeft: 0
  property Item stickySource: null
  Item {
    id: sticky
    readonly property var lines: win.w.current ? win.ed.context : []
    readonly property bool hung: !!win.stickyHost && win.w.row === 0
    parent: sticky.hung ? win.stickyHost : win
    visible: sticky.lines.length > 0
    // where this window is in the host (the editor moves without it knowing)
    readonly property point at: {
      void [win.x, win.y, win.width, win.height, win.edgeTrack, win.stickyTop, win.stickyLeft];
      return sticky.hung ? win.mapToItem(win.stickyHost, 0, 0) : Qt.point(0, 0);
    }
    x: sticky.hung ? win.stickyLeft : 0
    y: sticky.hung ? win.stickyTop : 0
    // the gap above the first row, which the bar fills down from the strip
    readonly property real lead: sticky.hung ? Math.max(0, sticky.at.y - win.stickyTop) : 0
    // the rows' left, in the bar
    readonly property real rowX: sticky.at.x - sticky.x
    width: sticky.hung ? win.stickyHost.width - win.stickyLeft : win.width
    height: sticky.lead + sticky.lines.length * win.cellH
    z: 5
    // THE ACTIVE TAB'S GLASS, LAYER FOR LAYER (user, 2026-10-09): the
    // strip's thin glass, then the window's ground over it at tabOver, so
    // the two come to the window's own alpha exactly as the tab above does.
    // The plato window leaves its ground out under the bar (stickyHost.band)
    // so nothing doubles it. Hung in a lower split there is no tab to
    // match, and the window's ground is under it: the layer's colour only.
    Rectangle {
      anchors.fill: parent
      visible: sticky.hung
      color: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a))
    }
    Rectangle {
      anchors.fill: parent
      color: sticky.hung ? Zenon.alpha(Zenon.layerBg, Zenon.tabOver(Zenon.layerBg.a)) : Zenon.layerBg
    }
    // and the text running on beneath, frosted on that glass: one light
    // pass, no floor, no scrim, no dimming. Stacked (gain 2) the syntax
    // colours spread into a grey veil and the bar read darker than the tab
    // (user's capture, 2026-10-09).
    Frost {
      anchors.fill: parent
      source: sticky.hung ? win.stickySource : content
      scrim: 0
      brightness: 0
      saturation: 0
      opacity: 0.6
    }
    Column {
      x: sticky.rowX
      y: sticky.lead
      Repeater {
        model: sticky.lines
        Item {
          id: ctxRow
          required property var modelData
          width: win.width
          height: win.cellH
          Text {
            width: win.w.textoff * win.cellW - win.cellW * 2
            height: win.cellH
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            font: win.face
            color: win.ed.lineNrFg
            text: String(ctxRow.modelData.n)
          }
          Row {
            x: win.w.textoff * win.cellW
            height: win.cellH
            Repeater {
              model: ctxRow.modelData.chunks
              Text {
                required property var modelData
                height: win.cellH
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                font.family: win.face.family
                font.pixelSize: win.face.pixelSize
                font.weight: modelData[2] ? Font.Bold : win.face.weight
                color: modelData[1] ? modelData[1] : win.ed.normalFg
                text: modelData[0]
              }
            }
          }
        }
      }
    }
    // a click anywhere on a line's band goes to it, the inset included
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: (m) => {
        const i = Math.floor((m.y - sticky.lead) / win.cellH);
        const l = sticky.lines[Math.max(0, Math.min(sticky.lines.length - 1, i))];
        if (l) win.client.cmd(String(l.n));
      }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
    // THE SHADOW DEEPENS AS THE TEXT GOES UNDER: faint while the block's
    // opener has only just reached the top, full once a few lines of it
    // have scrolled beneath the pinned lines
    readonly property real depth: {
      win.ed.frame;
      if (sticky.lines.length === 0) return 0;
      const top = win.ed.scrollOf(win.w.id).top;
      const lastN = sticky.lines[sticky.lines.length - 1].n;
      return Math.max(0.3, Math.min(1, (top - lastN) / 4));
    }
    property real shade: sticky.depth
    Behavior on shade { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
    Rectangle {
      anchors.top: parent.bottom
      width: parent.width
      height: 6 + 6 * sticky.shade
      gradient: Gradient {
        GradientStop { position: 0; color: Zenon.darken(0.5 * sticky.shade) }
        GradientStop { position: 1; color: "transparent" }
      }
    }
  }

  // ── marks along the scrollbar ──────────────────────────────────────
  // Where the rest of the file has something: errors, warnings, search
  // matches, git's changes (EditorState.marks), as ticks down the right
  // edge, each at its line's share of the file. The editor window's only.
  Item {
    id: ticks
    visible: win.w.current && win.railShown
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 8
    readonly property int lines: { win.ed.frame; return Math.max(1, win.ed.scrollOf(win.w.id).lines); }
    // ONE TICK A PIXEL ROW A SIDE. A search lit across a long file is up to
    // two thousand marks, and every one was an item, made again whenever the
    // marks changed — when most of them land on the same few pixels. Marks
    // sharing a row on a side are one tick, the most urgent of them.
    readonly property var rank: ({ e: 0, w: 1, s: 2, i: 3, h: 4, d: 0, c: 1, a: 2 })
    readonly property var merged: {
      if (!ticks.visible || ticks.height <= 0) return [];
      const best = {};
      const list = win.ed.marks;
      for (let i = 0; i < list.length; ++i) {
        const k = list[i][1];
        const git = k === "a" || k === "c" || k === "d";
        if (git && !win.gitGutter) continue;
        const px = Math.floor(Math.min(ticks.height - 3, (list[i][0] - 1) / ticks.lines * ticks.height));
        const key = (git ? "g" : "o") + px;
        const was = best[key];
        if (!was || ticks.rank[k] < ticks.rank[was[1]]) best[key] = [px, k];
      }
      return Object.keys(best).map((key) => best[key]);
    }
    function ink(k) {
      return k === "e" ? Zenon.red : k === "w" ? Zenon.yellow : k === "i" ? Zenon.blue
        : k === "h" ? Zenon.muted : k === "s" ? Zenon.sand : k === "a" ? Zenon.green
        : k === "c" ? Zenon.yellow : Zenon.red;
    }
    Repeater {
      model: ticks.merged
      Rectangle {
        required property var modelData
        readonly property string k: modelData[1]
        // git along the inner edge, the rest along the outer
        x: k === "a" || k === "c" || k === "d" ? 0 : 4
        width: 4
        height: k === "e" || k === "w" ? 3 : 2
        y: Math.min(ticks.height - height, modelData[0])
        radius: 1
        color: ticks.ink(k)
        opacity: k === "h" || k === "i" ? 0.6 : 0.9
      }
    }
  }

  ScrollRail {
    id: rail
    visible: win.railShown
    enabled: win.railShown
    target: proxy
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
  }
}
