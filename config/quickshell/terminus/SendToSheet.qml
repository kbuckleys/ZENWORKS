// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── SEND TO: copy or move without going there ─────────────────────────
// "Copy to…" and "Move to…" on the row menu. The point is not having to
// navigate to the destination first — pick it out of a tree and the
// transfer starts from where you are standing.
//
// IT DOES NO FILE WORK OF ITS OWN, and that is the whole design. pasteDest
// already exists for the one gesture that pastes somewhere other than the
// cwd, so this sets the same property and calls the same paste(). Conflict
// resolution, the undo record a move leaves, the job queue, the status
// line and the refresh of the destination all behave exactly as they do
// for an ordinary paste, because they ARE the ordinary paste.
//
// Its own file since 2026-10-08, out of TerminusWindow.qml (the split).
// `term` is the terminus window; window items it uses are read as
// term.<id>Ref (the window's aliases).

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

Rectangle {
  id: sendTo
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  anchors.fill: parent
  z: 11
  // NO DIM. A sheet is a picker, not a warning — and the listing behind
  // it is what the choice is ABOUT, so darkening it hid the thing you
  // were looking at to decide. The card has the menus' shadow to sit
  // against the window on, which is separation enough.
  //
  // The overlay stays, because it is what catches every click that misses
  // the card — see the MouseArea below. It simply paints nothing now.
  // Darkened under the bar only — the bar it hangs from stays lit, as
  // the search's does. Faded in with the card itself.
  color: "transparent"
  Rectangle {
    anchors.fill: parent
    anchors.topMargin: term.tabStripRef.height + term.crumbBarRef.height
    color: Qt.rgba(term.cardScrim.r, term.cardScrim.g, term.cardScrim.b,
                   term.cardScrim.a * sendToCard.opacity)
  }
  // and the sidebar beside the bar, which is not the titlebar: the
  // scrim stops at the bar, not at the sidebar's first heading
  Rectangle {
    width: term.sideRef.width
    height: term.tabStripRef.height + term.crumbBarRef.height
    color: Qt.rgba(term.cardScrim.r, term.cardScrim.g, term.cardScrim.b,
                   term.cardScrim.a * sendToCard.opacity)
  }
  opacity: 1
  // Held up by the sheet rather than by a fade of its own: with nothing
  // to dim there is nothing here to animate, and the card's own fade is
  // what says when the sheet has gone.
  visible: sendTo.open || sendToCard.opacity > 0.01

  // ── HOW WIDE THE WIDEST ROW WANTS TO BE ──────────────────────────
  // The crawl answers with PATHS, and a path is as long as it is — at a
  // fixed width the useful half of every deep hit sat behind an ellipsis,
  // which is the one thing a list of destinations cannot afford. So the
  // sheet measures what it is holding and takes the room.
  //
  // FontMetrics, because advanceWidth is a method a binding can CALL —
  // TextMetrics is an object you set and then read, which is no use
  // inside a loop over a hundred rows.
  //
  // The sum is the delegate's own layout: the indent for its depth, the
  // twisty and the glyph ahead of the name, and the room kept clear at
  // the end for the bookmark mark.
  FontMetrics {
    id: sendToFm
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(15)
  }

  readonly property real wantWidth: {
    let w = 0;
    const rows = sendTo.shown;
    for (let i = 0; i < rows.length; i++) {
      // 18 to the glyph column, 22 across it, 8 to the name — the
      // delegate's own layout, which is why it is spelled out rather than
      // rounded to one number.
      const t = 12 + rows[i].depth * term.treeStep + term.treeArrowW
              + 36 + sendToFm.advanceWidth(rows[i].name) + 34;
      if (t > w) w = t;
    }
    return w;
  }


  property bool open: false
  property string op: "copy"
  // CAPTURED WHEN THE MENU ENTRY IS CHOSEN, not read back when you pick a
  // destination. commitPaste clears the marks, and a picker that asked
  // "which rows?" afterwards would answer with none of them.
  property var paths: []
  property var names: []
  // WHAT IS MOVING, AS THE LISTING DRAWS IT. Taken from the enriched rows
  // at the moment they are captured — the same glyph and the same ink the
  // file wears on its own line — so the header names the thing in the
  // vocabulary you were just reading it in. Several at once have no single
  // icon, so they get Material's file-multiple (U+F12F7).
  property string icon: ""
  property color iconInk: Zenon.white
  // The tree, flattened: every row on screen in order, each carrying the
  // depth it is drawn at. Children are spliced in under their parent and
  // spliced out again when it closes.
  property var nodes: []
  property int sel: 0
  // The one directory being read. One at a time: a tree you are walking
  // fast would otherwise have four reads in flight for branches you have
  // already left, and the answers arrive in whatever order they finish.
  property string loadFor: ""

  // WHETHER THERE IS A VERB TO NAME. Copy and move have to say which
  // they are; `go` has nothing to disambiguate, so it drops the leading
  // glyph and lets the sentence start with the place you are leaving.
  readonly property bool sending: sendTo.op !== "go"

  readonly property string verb: sendTo.op === "go" ? "Go to"
    : sendTo.op === "copy" ? "Copy" : "Move"
  // ── WHAT CANNOT BE A DESTINATION ─────────────────────────────────
  // A directory cannot go inside itself, or inside anything it contains.
  // Pasting could always be asked to do it too, but you had to walk into
  // the directory first and nobody does that by accident — here the child is
  // sitting on screen one keystroke below its own parent, and rsync will
  // copy a directory into its own subdirectory for as long as the disk holds
  // out. Refused at the point of choosing rather than filtered out of the
  // tree: a branch you cannot land on is still a branch you walk THROUGH.
  //
  // Written out rather than calling bans() so the binding actually
  // depends on what it reads — a binding does not re-evaluate on a
  // function call, which this file has paid for more than once.
  readonly property bool blocked: {
    const n = sendTo.current;
    if (!n) return true;
    for (let i = 0; i < sendTo.paths.length; i++) {
      const p = sendTo.paths[i];
      if (n.path === p || n.path.indexOf(p + "/") === 0) return true;
    }
    return false;
  }

  function bans(path) {
    for (let i = 0; i < sendTo.paths.length; i++) {
      const p = sendTo.paths[i];
      if (path === p || path.indexOf(p + "/") === 0) return true;
    }
    return false;
  }

  // ── TYPE AND IT NARROWS ──────────────────────────────────────────
  // No field, no prompt, no slash to start it: the sheet has the keyboard
  // and there is nothing else in it a letter could mean, so a letter
  // filters. Which is exactly why the vim keys are not bound in here —
  // `j` and `l` are letters first in a box you can type into, and a
  // picker that sometimes moved and sometimes typed would be neither.
  // Arrows move; everything printable filters.
  property string query: ""

  // ── A SPACE IS AND ─────────────────────────────────────────────
  // Typing narrows; typing a second word narrows what the first one
  // left. "config" finds every config directory on the disk, and
  // "config buck" keeps the ones under /home/buck — which is how you
  // actually arrive at a destination: you remember the name first and
  // where it lives second.
  //
  // Held as a property rather than split inside the sift, because a
  // binding tracks the properties it READS and this file has paid more
  // than once for dependencies hidden behind a function call.
  readonly property var terms: {
    const out = [];
    const parts = sendTo.query.toLowerCase().split(/\s+/);
    for (let i = 0; i < parts.length; i++)
      if (parts[i] !== "") out.push(parts[i]);
    return out;
  }

  onQueryChanged: {
    sendTo.sel = 0;
    sendTo.hits = [];
    // One letter matches most of a filesystem, so the crawl waits for a
    // second one; the local sift runs from the first keystroke either way.
    if (sendTo.terms.join("").length >= 2) sendToCrawl.restart();
    else { sendToCrawl.stop(); sendToFind.running = false; sendTo.crawling = false; }
  }

  // ── AND IT LOOKS PAST WHAT IS OPEN ───────────────────────────────
  // The sift above can only answer about branches you have already
  // expanded, which makes the filter a way of re-reading the tree rather
  // than a way of finding somewhere. So typing also sends out one search
  // for directories under the places that are worth searching, and what
  // comes back is listed underneath the local matches as flat rows.
  //
  // FLAT, DELIBERATELY. A hit six levels down would otherwise need its
  // whole ancestry synthesised into the tree to be drawn in place, and
  // the result is harder to read than the path itself: the answer to
  // "where?" is the path, so the row is the path.
  property var hits: []
  property bool crawling: false

  // ── THE GLYPH A NODE WEARS ───────────────────────────────────────
  // OFF THE PATH, NEVER OFF THE NAME. A row found by the crawl is drawn
  // as its path — "~/.config/quickshell" is the answer to "where?", which
  // a bare basename is not — and that name went to the icon table, which
  // has no rule for a whole path and handed back the plain directory. So
  // every hit in both sheets was a generic directory while the identical
  // directory two rows up in the tree wore its own glyph.
  //
  // Home by its own name rather than by the user's: the basename of ~ is
  // "buck", which no rule claims, and the tree's root row for it is
  // labelled "Home" for the same reason.
  function glyphOf(n) {
    if (!n) return "";
    return Icons.glyphFor({
      name: n.path === Paths.home() ? "home" : Terminus.basename(n.path),
      isDir: true });
  }

  function pretty(p) {
    const h = Paths.home();
    if (p === h) return "~";
    return p.indexOf(h + "/") === 0 ? "~" + p.slice(h.length) : p;
  }

  Timer {
    id: sendToCrawl
    interval: 220
    onTriggered: {
      if (!sendTo.open || sendTo.query.length < 2) return;
      sendTo.crawling = true;
      sendToFind.running = false;
      sendToFind.command = ["sh", "-c",
        Terminus.dirFindCommand(sendTo.query)];
      sendToFind.running = true;
    }
  }

  Process {
    id: sendToFind
    stdout: StdioCollector {
      id: sendToFound
      waitForEnd: true
      onStreamFinished: {
        sendTo.crawling = false;
        if (!sendTo.open) return;
        const out = [];
        const parts = sendToFound.text.split("\u0000");
        for (let i = 0; i < parts.length; i++) {
          // fd ends a directory with a slash — see dirFindCommand.
          let p = parts[i];
          if (p.length > 1 && p.charAt(p.length - 1) === "/")
            p = p.slice(0, -1);
          if (p !== "") out.push(p);
        }
        sendTo.hits = out;
      }
    }
  }

  // WHAT IS ON SCREEN, which is the whole tree until you type. A match
  // keeps its ANCESTORS too — a hit six levels down with its parents
  // stripped out is a name with no answer to "where?", and the depth
  // indents would be measuring nothing.
  //
  // Only over what has been loaded — the crawl below is what looks
  // further than the branches you have opened.
  // ── THE LISTING'S TREE, GUIDES AND ALL ──────────────────────────
  // The rows are EntryRows now — the listing's own, with its guide lines
  // and its branch markers — rather than a twisty and an indent drawn by
  // hand. A row's guide is the listing's bitmask: one bit per column to
  // its left whose branch carries on below it. Worked out over what is
  // SHOWN, so a filter that hides a sibling also takes its line away.
  function guided(rows) {
    const sib = new Array(rows.length);
    const seen = [];
    for (let i = rows.length - 1; i >= 0; i--) {
      const d = rows[i].depth;
      sib[i] = seen[d] === true;
      seen[d] = true;
      seen.length = d + 1;
    }
    const stack = [];
    const out = [];
    for (let i = 0; i < rows.length; i++) {
      const n = rows[i];
      const d = n.depth;
      const mine = (d > 0 ? (stack[d - 1] || 0) : 0) | (sib[i] ? (1 << d) : 0);
      stack[d] = mine;
      out.push(Object.assign({}, n, { guide: d > 0 ? mine : -1 }));
    }
    return out;
  }

  // An entry for a place the tree did not get from a listing — a root,
  // a crawl hit — enriched the way the listing's own rows are, so it
  // wears the same glyph and ink.
  function entryFor(path, label) {
    const e = term.enrich([{ name: label, path: path, isDir: true,
      isLink: false, broken: false, isExec: false, mode: 0,
      isHidden: false, size: 0, mtime: 0 }])[0];
    e.glyph = sendTo.glyphOf({ path: path });
    return e;
  }

  readonly property var shown: {
    const t = sendTo.terms;
    if (t.length === 0) return sendTo.guided(sendTo.nodes);
    const n = sendTo.nodes;
    const keep = [];
    // AGAINST THE PATH, for the same reason the crawl is — a word like
    // "buck" is never in the directory's own name, it is in where the
    // directory lives. Inlined rather than called: see the note on `terms`.
    for (let i = 0; i < n.length; i++) {
      const hay = n[i].path.toLowerCase();
      let all = true;
      for (let k = 0; k < t.length; k++)
        if (hay.indexOf(t[k]) < 0) { all = false; break; }
      keep.push(all);
    }
    // Backwards, so a kept row can mark the parents above it and those
    // parents are themselves passed over later in the same sweep.
    for (let i = n.length - 1; i >= 0; i--) {
      if (!keep[i]) continue;
      let d = n[i].depth;
      for (let j = i - 1; j >= 0 && d > 0; j--) {
        if (n[j].depth < d) { keep[j] = true; d = n[j].depth; }
      }
    }
    const out = [];
    const have = ({});
    for (let i = 0; i < n.length; i++)
      if (keep[i]) { out.push(n[i]); have[n[i].path] = true; }
    // Then whatever the crawl found that the tree has not already shown.
    for (let i = 0; i < sendTo.hits.length; i++) {
      const p = sendTo.hits[i];
      if (have[p] === true) continue;
      have[p] = true;
      out.push({ path: p, name: sendTo.pretty(p), depth: 0, hit: true,
                 open: false, loaded: false, kids: null,
                 e: sendTo.entryFor(p, sendTo.pretty(p)) });
    }
    return sendTo.guided(out);
  }

  // The cursor indexes what is VISIBLE, not the tree — so filtering does
  // not leave it pointing at a row that has been sifted out. Everything
  // that acts on a row goes back to the tree through its path.
  readonly property var current:
    (sendTo.sel >= 0 && sendTo.sel < sendTo.shown.length)
      ? sendTo.shown[sendTo.sel] : null

  function nodeIndex(path) {
    for (let i = 0; i < sendTo.nodes.length; i++)
      if (sendTo.nodes[i].path === path) return i;
    return -1;
  }

  function ask(op) {
    sendTo.op = op;
    if (op === "go") {
      // PATHS STAYS EMPTY, and that is not an oversight — it is what
      // makes `blocked` answer false for every row, since nothing can be
      // put inside itself when nothing is being put. The header's subject
      // is filled in from `names` alone, which is why it reads that and
      // not the path list.
      sendTo.paths = [];
      // WHERE YOU ARE STANDING, said in the same slot the cargo uses. The
      // header is a sentence — this → that — and the half a journey needs
      // is the half you are leaving. Without it the sheet named a
      // destination with nothing to be a destination FROM.
      sendTo.names = [sendTo.pretty(term.cwd)];
      sendTo.icon = Icons.glyphFor({ name: Terminus.basename(term.cwd),
                                     isDir: true });
      sendTo.iconInk = Zenon.cyan;
    } else {
      const rows = term.acting();
      if (rows.length === 0) return;
      sendTo.paths = rows.map((r) => r.path);
      sendTo.names = rows.map((r) => r.name);
      if (rows.length === 1) {
        sendTo.icon = rows[0].glyph !== undefined ? rows[0].glyph : "";
        sendTo.iconInk = rows[0].ink !== undefined ? rows[0].ink : Zenon.white;
      } else {
        sendTo.icon = "\uDB84\uDEF7";
        sendTo.iconInk = Zenon.white;
      }
    }
    sendTo.nodes = sendTo.roots();
    sendTo.query = "";
    sendTo.hits = [];
    sendTo.sel = 0;
    sendTo.loadFor = "";
    sendTo.open = true;
  }

  function dismiss() {
    sendToFlash.cancel();
    sendTo.pendingDest = "";
    sendTo.pendingTab = false;
    sendTo.open = false;
    sendTo.nodes = [];
    sendTo.query = "";
    sendTo.hits = [];
    sendToCrawl.stop();
    sendToFind.running = false;
    sendTo.crawling = false;
    sendTo.loadFor = "";
  }

  // WHERE A TREE CAN START. The places you already told terminus you care
  // about — bookmarks and disks — plus home, the root, and the other
  // pane's directory, which is the destination often enough to be worth a
  // row of its own. Deduplicated, because a bookmarked home is one place
  // and two entries for it would be two answers to the same question.
  function roots() {
    const out = [];
    const seen = ({});
    function add(p, label, glyph) {
      if (!p || p === "" || seen[p] === true) return;
      seen[p] = true;
      const name = label !== undefined && label !== "" ? label : Terminus.basename(p);
      const e = sendTo.entryFor(p, name);
      if (glyph) e.glyph = glyph;
      out.push({ path: p, name: name, e: e,
                 depth: 0, open: false, loaded: false, kids: null });
    }
    // WHAT YOU CHOSE, PLUS THE TWO WAYS IN. Home, the other pane when
    // there is one, your bookmarks, and the root.
    //
    // Not the current directory: you are already in it, its subdirectories
    // are one keystroke away in the tree and one letter away in the
    // filter, and as a root it only ever restated the window behind it.
    // The mounted disks are back — see below.
    add(Paths.home(), "Home");
    if (term.dual && term.pas) add(term.pas.cwd);
    for (let i = 0; i < term.bookmarks.length; i++) add(term.bookmarks[i]);
    // ── AND THE DISKS, AFTER ALL ──────────────────────────────────
    // Left out once for repeating the root. A drive you plugged in is
    // not something the root says, though — it is somewhere you are
    // very likely sending things TO — so every mounted disk is a place
    // to start from, by its own name and with the sidebar's glyph. The
    // system's own mounts (/, /boot, /efi) still are not.
    for (let i = 0; i < term.disks.length; i++) {
      const d = term.disks[i];
      if (d.mount === "" || Terminus.isSystemMount(d.mount)) continue;
      add(d.mount, d.name !== "" ? d.name : Terminus.basename(d.mount),
          d.removable ? "\uF0A0" : "\uF1C0");
    }
    add("/", "/");
    return out;
  }

  // Children are kept on the node once read, so closing a branch and
  // opening it again is free. A directory that changed under you is the
  // price, and it is the same price the preview cache pays.
  function expand(i) {
    const n = sendTo.nodes[i];
    if (!n || n.open) return;
    if (n.kids !== null) { sendTo.insert(i, n.kids); return; }
    if (sendTo.loadFor !== "") return;
    sendTo.loadFor = n.path;
    sendToProc.running = false;
    sendToProc.command = ["sh", "-c", Terminus.peekCommand(n.path)];
    sendToProc.running = true;
  }

  function insert(i, kids) {
    const n = sendTo.nodes[i];
    if (!n) return;
    const made = [];
    for (let k = 0; k < kids.length; k++)
      made.push({ path: kids[k].path, name: kids[k].name, e: kids[k],
                  depth: n.depth + 1, open: false, loaded: false, kids: null });
    const a = sendTo.nodes.slice();
    a[i] = { path: n.path, name: n.name, e: n.e, depth: n.depth,
             open: true, loaded: true, kids: kids };
    sendTo.nodes = a.slice(0, i + 1).concat(made, a.slice(i + 1));
  }

  function collapse(i) {
    const n = sendTo.nodes[i];
    if (!n || !n.open) return;
    const a = sendTo.nodes.slice();
    let j = i + 1;
    while (j < a.length && a[j].depth > n.depth) j++;
    a[i] = { path: n.path, name: n.name, e: n.e, depth: n.depth,
             open: false, loaded: n.loaded, kids: n.kids };
    sendTo.nodes = a.slice(0, i + 1).concat(a.slice(j));
  }

  function toggle(i) {
    const n = sendTo.nodes[i];
    if (!n) return;
    if (n.open) sendTo.collapse(i); else sendTo.expand(i);
  }

  // The three the keyboard and the mouse actually call: they are handed a
  // row that is on screen and find it in the tree themselves.
  function expandCurrent() {
    const n = sendTo.current;
    if (n) sendTo.expand(sendTo.nodeIndex(n.path));
  }

  function toggleShown(i) {
    const n = sendTo.shown[i];
    if (n) sendTo.toggle(sendTo.nodeIndex(n.path));
  }

  function clamp() {
    sendTo.sel = Math.max(0,
      Math.min(sendTo.sel, sendTo.shown.length - 1));
  }

  // Left on an open branch closes it; left on a closed one goes out to
  // the branch it is in. The same thing `h` does in the listing.
  function outward() {
    const n = sendTo.current;
    if (!n) return;
    if (n.open) {
      sendTo.collapse(sendTo.nodeIndex(n.path));
      sendTo.clamp();
      return;
    }
    // Walked over what is VISIBLE: with a filter on, the parent two rows
    // up in the tree may not be on screen, and the one that is, is the
    // one the indent is drawn against.
    for (let i = sendTo.sel - 1; i >= 0; i--)
      if (sendTo.shown[i].depth < n.depth) { sendTo.sel = i; return; }
  }

  function step(d) {
    if (sendTo.shown.length === 0) return;
    sendTo.sel = Math.max(0,
      Math.min(sendTo.shown.length - 1, sendTo.sel + d));
  }

  // ── THE ROW FLASHES, THEN THE SHEET GOES, THEN IT HAPPENS ────────
  // The same three beats a menu row gives when you click it, and the same
  // numbers — 60ms up, 130ms down, cyan at 0.55 — because it is the same
  // gesture: you have picked a thing and the card is answering before it
  // acts. Return used to send with the sheet vanishing on the keystroke,
  // which leaves you unsure which row you were on at the moment it went.
  property string pendingDest: ""

  RowFlash { id: sendToFlash; onDone: () => sendTo.commit() }

  // Held beside pendingDest and for the same reason: the flash is long
  // enough for a second keystroke, and what was asked for is what was
  // asked for at the moment the key went down.
  property bool pendingTab: false

  function choose(inTab) {
    const n = sendTo.current;
    if (!n || sendToFlash.running) return;
    sendTo.pendingTab = (inTab === true) && sendTo.op === "go";
    if (sendTo.blocked) {
      term.warn(n.path === sendTo.paths[0]
        ? "that is where it already is"
        : "cannot put a directory inside itself");
      return;
    }
    // Held on the sheet rather than read back at the end: the flash is
    // long enough for a second keystroke to move the cursor, and the
    // destination is the one that was lit up.
    if (!sendToFlash.fire(sendTo.sel)) return;
    sendTo.pendingDest = n.path;
  }

  function commit() {
    const dest = sendTo.pendingDest;
    sendTo.pendingDest = "";
    if (dest === "") return;
    sendTo.open = false;
    if (sendTo.op === "go") {
      const tab = sendTo.pendingTab;
      sendTo.pendingTab = false;
      sendTo.nodes = [];
      if (tab) term.openInNewTab(dest);
      else term.goTo(dest);
      return;
    }
    term.setPending({ op: sendTo.op, paths: sendTo.paths,
                      names: sendTo.names });
    term.pasteDest = dest;
    term.pastePending();
    sendTo.nodes = [];
  }

  Process {
    id: sendToProc
    stdout: StdioCollector {
      id: sendToOut
      waitForEnd: true
      onStreamFinished: {
        const p = sendTo.loadFor;
        sendTo.loadFor = "";
        if (p === "" || !sendTo.open) return;
        // Found by PATH, not by the index that asked: the tree can have
        // been collapsed or rebuilt while the read was out.
        let at = -1;
        for (let i = 0; i < sendTo.nodes.length; i++)
          if (sendTo.nodes[i].path === p) { at = i; break; }
        if (at < 0) return;
        // Directories only — this is a destination picker, and the same
        // parse the listing and the preview use, so hidden directories and
        // the sort order match what the window is already showing.
        const all = term.rowsFromListing(sendToOut.text, p);
        const dirs = [];
        for (let i = 0; i < all.length; i++)
          if (all[i].isDir) dirs.push(all[i]);
        sendTo.insert(at, dirs);
      }
    }
  }

  // Clicking off cancels, the way the other cards behave. Under the card,
  // which is declared after it and so takes its own clicks first.
  MouseArea {
    anchors.fill: parent
    onClicked: sendTo.dismiss()
  }

  // ── IT COMES OUT FROM UNDER THE BAR ──────────────────────────────
  // A sheet, the way macOS drops one: it belongs to this window, it hangs
  // off the chrome, and the way in and the way out are the same movement
  // reversed. A card that simply appeared in the corner said nothing
  // about where it came from or what it is attached to.
  //
  // The well is everything BELOW the chrome and it clips, so the sheet is
  // genuinely hidden behind the bar rather than fading out on top of it.
  // The band is the tab strip plus the path bar — chrome is a Column, so
  // those two heights are exactly where the body begins.
  Item {
    id: sendToWell
    // the sidebar sliding moves the well, and the bar's title with it
    onXChanged: term.noteSheet("send", sendToCard.opacity, x + sendToCard.x, sendToCard.width)
    anchors.left: parent.left
    // under the bar it hangs from, which starts where the sidebar ends
    anchors.leftMargin: term.sideRef.width
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: term.tabStripRef.height + term.crumbBarRef.height
    anchors.bottom: parent.bottom
    // clipped, so the sheet is hidden behind the bar rather than fading
    // out on top of it
    clip: true

  // The one every menu on this desktop wears. A sibling, never a child —
  // the card clips, and a card that clips clips its own shadow away.
  // Inside the well, so the part that would fall across the bar is cut
  // off with it: a sheet hanging from the chrome does not cast upwards.
  MenuShadow {
    panel: sendToCard
    cornerRadius: Zenon.dialogRadius
    opacity: sendToCard.opacity
  }

  Rectangle {
    id: sendToCard
    anchors.horizontalCenter: parent.horizontalCenter
    // goes dark on the bar and opens its hairline, as a Sheet does
    onOpacityChanged: term.noteSheet("send", opacity, sendToWell.x + x, width)
    onXChanged: term.noteSheet("send", opacity, sendToWell.x + x, width)
    onWidthChanged: term.noteSheet("send", opacity, sendToWell.x + x, width)
    // AS WIDE AS IT NEEDS, AND NEVER WIDER THAN THE WINDOW. The well is
    // the window's width, so the sheet may reach the frame on either side
    // and stops exactly there. 560 is the floor rather than the size: a
    // tree of short names should not rattle around in a wide card.
    //
    // Animated for the reason the height is — the width changes as you
    // type, and a card that jumped on every keystroke would be the filter
    // shouting rather than answering.
    //
    // The floor is also never NARROWER THAN ITS OWN HINTS. The key row
    // grew a pair and ran off both edges of a 560 card; the footer's
    // margins are 14 a side.
    width: Math.max(
      Math.min(Math.max(560, sendToHints.implicitWidth + 28), sendToWell.width),
      Math.min(sendToWell.width, sendTo.wantWidth))
    Behavior on width {
      NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
    }
    // Grown to what it holds, capped at the well. A picker sized for the
    // deepest tree you might open is mostly empty space when all it has
    // is six bookmarks; one that grows as you open branches is the same
    // gesture continuing. Animated, or the sheet would jump every time a
    // branch loaded.
    // ADDED UP FROM THE PARTS RATHER THAN WRITTEN AS A NUMBER. A guessed
    // constant was seven pixels short and sliced the last row with the
    // bottom rule, on a sheet that had room for it — which reads as a
    // scroll that is not there. This one cannot drift when a font size
    // or a margin changes, because it is made of them.
    //
    // dialogRadius is in it because the card's top is that far above the
    // clip — see the note on `y`. Those pixels are cut away, so the sheet
    // has to be that much taller to hold the same contents.
    // The header is the card's first row (sendToHead), then the list, a
    // rule and the footer.
    // EVERY PIXEL THAT IS NOT A ROW, EACH ONE NAMED. dialogRadius is the
    // list's top margin, and the height the card's top sits above the clip
    // — the same number for the same reason. 12 is the list's bottom
    // margin. The footer is the footer. And 14 is the footer's OWN margin
    // against the bottom of the card, which is written on sendToFoot as
    // `anchors.margins`.
    //
    // That last one reads as slack and is not: taken out, the card came up
    // 14 short and the bottom row was sliced by the frame. Measured, with
    // four roots in the sheet — 106 pixels of list for 120 pixels of rows.
    // The whole point of adding it up from the parts is that every term
    // has to be one of them.
    readonly property real chromeH:
      Zenon.dialogRadius + sendToHead.height + 12 + sendToFoot.height + 14
    // the listing's own row height, now that the rows are its rows
    readonly property int rowH: term.rowH
    // WHAT IS VISIBLE, not what is loaded. Bound to the tree instead, a
    // sheet that had been opened out stayed at full height when a filter
    // cut it to three rows, and the answer sat in the top inch of a lot
    // of empty card.
    // FOURTEEN ROWS TO A PAGE, and the well's height after that. A crawl
    // can answer with a hundred and twenty; a sheet grown to hold them
    // would be the window with a border round it, and everything past the
    // first dozen is something you scroll to rather than read.
    readonly property int pageRows: 14
    // ONE ROW MINIMUM, not two — the same floor every other sheet in this
    // window uses. Two meant a filter narrowed to a single answer drew a
    // second row's worth of empty card under it, which reads as a list
    // that has more in it and has failed to draw the rest. The palette,
    // the disks, the tags and the marks sheets all say Math.max(1, ...)
    // here; this one had drifted, and they are the same object.
    height: Math.min(sendToWell.height - 40,
      sendToCard.chromeH
        + Math.max(1, Math.min(sendToCard.pageRows, sendTo.shown.length))
          * sendToCard.rowH)
    Behavior on height {
      NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
    }

    // AT REST ITS TOP SITS ABOVE THE CLIP by exactly the corner radius,
    // so the rounded top corners are cut away and the sheet reads as
    // hanging FROM the bar rather than floating below it. Rounded at the
    // bottom, square at the top — which is the shape of the thing being
    // imitated.
    // HANGING FROM THE BAR, as the search does: a picker of places is
    // about the listing in front of you, so it comes down out of the bar
    // rather than floating like a dialog. At rest its top sits above the
    // clip by the corner radius, so the top corners are cut away.
    y: sendTo.open ? -Zenon.dialogRadius : -sendToCard.height - 2
    // A SHEET IS SLOWER THAN A MENU. It is a bigger object and it travels
    // further, so the shared durations — sized for a card that appears
    // where the pointer already is — read as a snap here rather than as a
    // slide. Taken as a multiple of the token rather than written as a
    // number, so turning the desktop's motion down still turns this down.
    // The same pair the Sheet component uses, and for the same reason —
    // see the note there on why leaving is much faster than arriving.
    readonly property int slideIn: Zenon.sheetIn
    readonly property int slideOut: Zenon.sheetOut

    // Down on a curve that settles, up on one that accelerates away: a
    // sheet arrives and is dismissed, it does not do the same thing twice.
    Behavior on y {
      NumberAnimation {
        duration: sendTo.open ? sendToCard.slideIn : sendToCard.slideOut
        easing.type: sendTo.open ? Zenon.sheetInEase : Zenon.sheetOutEase
      }
    }

    // AND IT FADES AS IT TRAVELS. The well clips, so a sheet that only
    // slid would be a hard edge crossing the listing; fading the same
    // distance makes it arrive rather than pass by. Same two durations as
    // the slide, so the two halves of one movement cannot drift apart.
    opacity: sendTo.open ? 1 : 0
    Behavior on opacity {
      NumberAnimation {
        duration: sendTo.open ? sendToCard.slideIn : sendToCard.slideOut
        easing.type: sendTo.open ? Zenon.sheetInEase : Zenon.sheetOutEase
      }
    }

    color: Zenon.black
    border.color: Zenon.border
    border.width: 1
    radius: Zenon.dialogRadius
    clip: true

    // ── WHAT IS GOING WHERE, ON THE BAR AGAIN ─────────────────
    // The sentence — this thing → that place — is the bar's while the
    // sheet hangs from it (see barSendHead), as every sheet's title is.
    // The head is kept at no height so the sums below still name it.
    Item {
      id: sendToHead
      anchors.top: parent.top
      anchors.topMargin: Zenon.dialogRadius
      anchors.left: parent.left
      anchors.right: parent.right
      height: 0
      visible: false


      Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Zenon.border
      }
    }

    // Hairlines, the same ink the menu separates with. The list scrolls
    // under both of them, so a row cut in half at the bottom reads as
    // more to come rather than as a row drawn wrong.
    Rectangle {
      anchors.bottom: sendToFoot.top
      anchors.bottomMargin: 10
      anchors.left: parent.left
      anchors.right: parent.right
      height: 1
      color: Zenon.border
    }

    SelectBar {

      host: term
      view: sendToList
      index: sendTo.sel
      rowH: sendToCard.rowH
    }

    ListView {
      id: sendToList
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: sendToFoot.top
      // THE CORNER RADIUS, which is how far the card's top sits above the
      // clip — see the note on `y`. Below that the first row is flush
      // with the bar's own bottom edge, which is where the sheet begins
      // as far as the eye is concerned.
      anchors.topMargin: Zenon.dialogRadius + sendToHead.height
      anchors.bottomMargin: 12
      clip: true
      model: sendTo.shown
      boundsBehavior: Flickable.DragAndOvershootBounds
      boundsMovement: Flickable.FollowBoundsBehavior
      currentIndex: sendTo.sel
      highlightMoveDuration: 0
      // Keeps the cursor on screen without the view chasing it: the same
      // Contain the listing uses.
      onCurrentIndexChanged: sendToList.positionViewAtIndex(
        sendToList.currentIndex, ListView.Contain)
      ElasticScroll { view: sendToList; step: term.wheelStep }

      delegate: Item {
        id: sendToRow
        required property var modelData
        required property int index
        width: sendToList.width
        height: sendToCard.rowH

        readonly property bool on: sendToRow.index === sendTo.sel
        readonly property bool banned: sendTo.bans(sendToRow.modelData.path)
        // Where the branch marker ends, for the click below: a press
        // left of it opens the branch, as the marker itself does.
        readonly property real indent: 12 + sendToRow.modelData.depth * term.treeStep
          + term.treeArrowW

        // THE LISTING'S ROW, drawing only: glyph, ink, guides and the
        // branch marker all come from the same EntryRow the tree view
        // uses. The clicks stay this sheet's — see the MouseArea below.
        EntryRow {
          host: term
          anchors.fill: parent
          // EntryRow draws the bookmark mark itself, as it does in the
          // listing — a second one drawn here put two side by side
          clickable: false
          actionable: false
          showMeta: false
          live: false
          passive: false
          entry: sendToRow.modelData.e
          depth: sendToRow.modelData.depth
          guide: sendToRow.modelData.guide
          inTree: true
          // a crawl hit is a leaf: somewhere to send to, not a branch
          branch: sendToRow.modelData.hit !== true
          expanded: sendToRow.modelData.open
          hollow: sendToRow.modelData.loaded && !!sendToRow.modelData.kids
            && sendToRow.modelData.kids.length === 0
          current: sendToRow.on
          // the directories that only lead to an answer are context
          dim: sendToRow.banned
        }

        FlashOver { flash: sendToFlash; index: sendToRow.index }

        MouseArea {
          anchors.fill: parent
          // The RIGHT button opens and closes a directory from anywhere on
          // its row. The chevron is a sixteen-pixel target at the far end
          // of an indent, and every other row of this sheet is a directory,
          // so the button with no other job here is given this one.
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          enabled: !sendToFlash.running
          onClicked: (m) => {
            sendTo.sel = sendToRow.index;
            if (m.button === Qt.RightButton
                || (sendToRow.modelData.hit !== true && m.x < sendToRow.indent + 6))
              sendTo.toggleShown(sendToRow.index);
          }
          onDoubleClicked: (m) => {
            if (m.button === Qt.LeftButton) sendTo.choose();
          }
        }
      }
    }

    // THE SAME RAIL THE VIEWS USE, so "there is more below" looks here
    // exactly as it looks in the listing. It shows itself only when the
    // results overrun the page — which, with fourteen rows and a crawl
    // that can answer with a hundred and twenty, is most of a filter.
    //
    // After the list, so it draws over the rows rather than under them.
    ScrollRail {
      owner: term
      target: sendToList
      anchors.right: sendToList.right
      anchors.rightMargin: 2
      anchors.top: sendToList.top
      anchors.topMargin: 2
      anchors.bottom: sendToList.bottom
      anchors.bottomMargin: 2
    }

    Column {
      id: sendToFoot
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: 14
      spacing: 4

      // NO PATH ROW. It was here because a tree shows you a leaf and the
      // question is about the whole path — but a crawl result IS its
      // path, so under a filter the line restated the row above it, and
      // the filter is how most destinations get found.
      //
      // THE HINT IS THE FIELD. "type to filter" is an instruction you need
      // once, and the moment you follow it the same line can show what you
      // typed instead — so the sheet gets a filter field without carrying
      // a box for one, in the place your eyes already are while the
      // results move. The second half stays the keys, and says "searching"
      // there while the crawl is out rather than taking the line over: a
      // query that disappeared for a tenth of a second every time you
      // stopped typing would be the one thing you wanted to read.
      // ── THE KEYS ARE DRAWN AS KEYS ────────────────────────────
      // They were one run of text with the glyphs spaced into it, which
      // made this the only list of keys in the window not wearing the
      // chip every other one wears — the context menu and F1 are both
      // KeyCap, and this is the third list. Spelt out as chip-and-word
      // pairs so a key and what it does stay together.
      Row {
        id: sendToHints
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12

        Text {
          anchors.verticalCenter: parent.verticalCenter
          rightPadding: 2
          text: sendTo.blocked && sendTo.current ? "cannot go there"
              : (sendTo.query !== "" ? sendTo.query : "type to filter")
          color: sendTo.query !== "" && !sendTo.blocked
            ? Zenon.sand : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }

        // While the crawl is out this takes the KEYS' place and not the
        // query's: a query that disappeared for a tenth of a second every
        // time you stopped typing would be the one thing you wanted to
        // read.
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: sendTo.crawling && !(sendTo.blocked && sendTo.current)
          text: "searching\u2026"
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }

        Repeater {
          model: {
            if (sendTo.crawling) return [];
            if (sendTo.blocked && sendTo.current) return [];
            const out = [["\u2191\u2193", "move"], ["\u2192", "open"],
                         [term.mouseKey(2), "fold"]];
            // The verb is the op's own, and `go` has a second one.
            out.push(["\u21b5", sendTo.op === "go" ? "go" : "send"]);
            if (sendTo.op === "go") out.push(["\u21e7\u21b5", "new tab"]);
            out.push(["esc", "close"]);
            return out;
          }

          delegate: Row {
            id: hintPair
            required property var modelData
            spacing: 5

            KeyCap {
              anchors.verticalCenter: parent.verticalCenter
              label: hintPair.modelData[0]
              fontSize: 11
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: hintPair.modelData[1]
              color: Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
          }
        }
      }
    }
  }
  }

}
