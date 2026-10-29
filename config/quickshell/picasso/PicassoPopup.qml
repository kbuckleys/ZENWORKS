// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The setter. Pick a background in the grid and it lifts out into a card of
// its own: a large look at it, the monitors drawn to scale as they sit on
// the desk, how it is fitted, and one button that puts it there.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../morpheus/gridnav.js" as Nav
import "../terminus" as Term
import "../morpheus/controls" as Controls
import "../morpheus/undo"
import "../morpheus/icons.js" as Icons
import "../terminus/terminus.js" as Terminus
import "picasso.js" as Art

LayerPopup {
  id: popup

  readonly property color bgColor: Zenon.layerBg
  readonly property color fgColor: Zenon.white
  readonly property color headColor: Zenon.cyan
  readonly property color dimColor: Zenon.accentMuted
  // WHAT YOU ARE TOUCHING, and what has been CHANGED, are two different
  // facts and now wear two different colors.
  //
  // Everything interactive used to light up in the pink — a focused field, an
  // open dropdown, a pressed button, a grabbed knob — and against the dark
  // panel that reads as a red alert rather than as "this one is live". Cyan
  // is the accent the rest of the shell already uses for the thing in hand:
  // the section you are standing in, a slider's filled track, the lit cell in
  // the corner picker.
  //
  // The pink is kept for the one job it is good at: marking something that is
  // no longer at its default, or already in use. That is a STATE, it wants to
  // be told apart from the cyan at a glance, and it appears in very few
  // places — the sidebar's count, the dot on a changed row, and picasso's
  // tick on a background that is currently up.
  readonly property color highlight: Zenon.cyan
  readonly property color entryColor: Zenon.pink

  property string query: ""
  property int sel: 0

  // ── what the grid shows ──────────────────────────────────────────────
  // Two kinds of background, two tabs in the strip: pictures from the
  // background directory, and plain colors. A color is assigned exactly like a
  // picture (see picasso.js isColor), so everything past choosing one — the
  // card, the monitors, the tick on what is in use — is the same machinery.
  property string view: "backgrounds"
  property int colorSel: 0
  // the color being made in the color tab's picker
  property string pickHex: "#7a8cff"

  // ── the focus card ───────────────────────────────────────────────────
  // A click LIFTS a background into a card — see FocusCard.qml. What the
  // card is about lives here, because the grid is what moves it: `focusPath`
  // is held rather than read off the selection, so a rescan reordering the
  // grid under the card cannot quietly change its subject.
  property string focusPath: ""
  property bool focusOpen: false
  // THE CARD ALONE — the viewer's "Set as background". The setter is what was
  // asked for, not the background grid, so the panel stays out of sight, the
  // card sits in the middle of the screen, and putting the card away puts
  // the whole surface away. Cleared by every ordinary open.
  property bool cardOnly: false
  // where the card grows out of — the clicked cell, in surface coordinates
  property point focusFrom: Qt.point(0, 0)

  // BY DIRECTORY (user, 2026-10-25): the grid is one directory at a time —
  // its directories first (a cover and a count; a click or Return goes in,
  // Backspace or Esc comes back out), then its own pictures. Typing searches
  // every picture under the backgrounds directory at once, flat, as before.
  // `sub` is where you are, relative to Picasso.dir; "" is the top.
  property string sub: ""
  // Filter first, then order: the sort only has to touch what survived, and
  // the two are separate questions the user changes independently.
  // A SEARCH LOOKS WHERE YOU ARE (user, 2026-10-28: the crumbs shrank to
  // the first step while searching): this directory and everything under
  // it, Finder's "this folder" — from the top, that is every background
  readonly property var searchPool: popup.sub === "" ? Picasso.files
    : Picasso.files.filter((f) => String(f.path).indexOf(popup.absOf(popup.sub) + "/") === 0)
  readonly property var filtered: Picasso.everything
    ? Art.sortRows(Art.filter(Picasso.files, popup.query, Picasso.dir), Picasso.sortMode, Picasso.dir)
    : popup.query !== ""
    ? Art.sortRows(Art.filter(popup.searchPool, popup.query, Picasso.dir), Picasso.sortMode, Picasso.dir)
    : Art.level(Art.sortRows(Picasso.files, Picasso.sortMode, Picasso.dir), Picasso.dir, popup.sub, Picasso.sortMode)
  // the pictures alone, what the card steps through
  readonly property var pictures: popup.filtered.filter((r) => !r.dir)
  readonly property int dirCount: popup.filtered.length - popup.pictures.length

  function enterDir(row) { popup.goSub(row.sub); }
  // back out of a directory, the one just left selected
  function upDir() {
    if (popup.sub === "") return false;
    popup.goSub(Art.up(popup.sub));
    return true;
  }
  // anywhere along the trail (the crumbs): back out lands on the directory
  // it came out of, down lands at the top
  function goSub(to, keep) {
    if (to === popup.sub) return;
    const was = popup.sub;
    if (!keep) trail.record(was);
    popup.stagger();
    popup.sub = to;
    // the step below `to` on the way back to where you were
    const pre = to === "" ? "" : to + "/";
    const left = was.indexOf(pre) === 0 ? pre + was.slice(pre.length).split("/")[0] : "";
    const i = left === "" ? -1 : popup.filtered.findIndex((r) => r.dir && r.sub === left);
    popup.sel = Math.max(0, i);
    popup.followSelection();
  }

  // ── BACK AND FORWARD ────────────────────────────────────────────────
  // The places walked through, as terminus' window keeps them: a step
  // anywhere new forgets the way forward. The strip's chip, mouse 4/5 and
  // alt+←/→ take them. morpheus' UndoStack holds them (audit, 2026-10-27:
  // a pair of lists of its own was that stack again): a place left is
  // recorded, back is an undo, forward a redo.
  UndoStack { id: trail }
  function back() {
    const to = trail.undo(popup.sub);
    if (to !== undefined) popup.goSub(to, true);
  }
  function forward() {
    const to = trail.redo(popup.sub);
    if (to !== undefined) popup.goSub(to, true);
  }
  function forgetHistory() { trail.clear(); }

  // A DIRECTORY ARRIVED IN: its tiles come up one after another, top to
  // bottom — terminus' TileRise, as its grid and picasso's gallery do it.
  property bool staggering: false
  Timer { id: staggerOff; interval: 500; onTriggered: popup.staggering = false }
  function stagger() {
    popup.staggering = true;
    staggerOff.restart();
  }

  // ── THE CRUMBS ──────────────────────────────────────────────────────
  // Where you are, from the backgrounds directory down, as terminus' crumb
  // bar draws it (terminus/Segments) — and past it, faint, the way back down
  // to the deepest place you came up out of, as terminus keeps it.
  property string deep: ""
  // kept while you are somewhere along it, cut to here once you leave it;
  // and remembered, for the next open (Picasso.place) — only while open:
  // the resets a hidden panel takes (the backgrounds directory settling at
  // startup) are not somewhere you went
  onSubChanged: {
    if (popup.shown) Picasso.setPlace(popup.sub);
    const pre = popup.sub === "" ? "" : popup.sub + "/";
    if (popup.deep !== popup.sub && popup.deep.indexOf(pre) !== 0) popup.deep = popup.sub;
  }
  function absOf(s) { return Picasso.dir + (s === "" ? "" : "/" + s); }
  readonly property var crumbList: {
    const out = [{ label: Terminus.basename(Picasso.dir) || Picasso.dir, path: popup.absOf(""), sub: "" }];
    const flat = Picasso.everything;
    const trail = flat ? "" : popup.deep;
    let at = "";
    for (const part of trail.split("/")) {
      if (part === "") continue;
      at = at === "" ? part : at + "/" + part;
      out.push({ label: part, path: popup.absOf(at), sub: at,
                 ghost: !(popup.sub === at || popup.sub.indexOf(at + "/") === 0) });
    }
    return out;
  }

  // The presets, then the ones made here. Shaped like a file row — a path
  // and nothing else — so the card can browse them the way it browses files.
  readonly property var colorItems: {
    const out = [];
    for (const c of Art.presetColors)
      out.push({ path: Art.colorPath(c.hex), hex: c.hex, name: c.name, custom: false });
    for (const hex of Picasso.colors)
      out.push({ path: Art.colorPath(hex), hex: hex, name: "Custom", custom: true });
    return out;
  }

  function colorName(hex) {
    for (const c of Art.presetColors) if (c.hex === hex) return c.name;
    return "Custom color";
  }

  // what the card browses: whichever list its subject came from
  readonly property var focusList:
    Art.isColor(popup.focusPath) ? popup.colorItems : popup.pictures

  // Every connected output, by name. Built from the live list, so plugging a
  // monitor in puts it on the map with no edit.
  readonly property var screenNames: {
    const out = [];
    const screens = Quickshell.screens;
    for (let i = 0; i < screens.length; ++i) out.push(screens[i].name);
    return out;
  }

  // path -> cached thumbnail, so a monitor on the map can draw what is on it
  // without decoding an 8MB original into a box 150 pixels wide
  readonly property var thumbOf: {
    const m = {};
    const f = Picasso.files;
    for (let i = 0; i < f.length; ++i) m[f[i].path] = f[i].thumb;
    return m;
  }

  readonly property var focusRow: {
    const f = Picasso.files;
    for (let i = 0; i < f.length; ++i)
      if (f[i].path === popup.focusPath) return f[i];
    return null;
  }

  readonly property int focusIndex: {
    const f = popup.focusList;
    for (let i = 0; i < f.length; ++i)
      if (f[i].path === popup.focusPath) return i;
    return -1;
  }

  // The monitors the focused background is ALREADY on — said on the card, so
  // "is this the one I have" does not need the map to answer it.
  readonly property var focusOn: {
    const out = [];
    for (let i = 0; i < popup.screenNames.length; ++i)
      if (Picasso.wallpaperFor(popup.screenNames[i]) === popup.focusPath)
        out.push(popup.screenNames[i]);
    return out;
  }

  readonly property Item panelItem: panel

  readonly property int cols: 4
  readonly property int colorCols: 5
  readonly property int colorCellH: 110
  readonly property int visibleRows: 3
  // The GRID's own width over the columns, not one constant over another: the
  // panel follows Zenon.layerWidth, and a fixed 1000/4 left the last column
  // hanging off the edge as soon as that was not what it used to be. (It
  // used to have the scrollbar's strip taken off it as well, before the bar
  // was floated over the pictures.)
  // and FEWER than the columns share the row between them (user,
  // 2026-10-25): three pictures in a directory took three quarters of it
  // and left the fourth empty
  readonly property int cellW:
    Math.max(80, Math.floor(grid.width / Math.max(1, Math.min(popup.cols, popup.filtered.length))))
  readonly property int cellH: 150

  function gridHeight() {
    // the color tab is always full height: its picker needs the room
    if (popup.view === "colors") return popup.visibleRows * popup.cellH;
    if (popup.filtered.length === 0) return 90;
    const rows = Math.ceil(popup.filtered.length / popup.cols);
    return Math.max(1, Math.min(rows, popup.visibleRows)) * popup.cellH;
  }

  // One line, and always the same one. The hint strip that used to sit under
  // this taught a set of chords — type, alt s, alt f, return, esc — and every
  // one of them is now a thing on screen you can point at: the two rings are
  // words you click, and a thumbnail opens a card. A strip explaining the
  // keyboard equivalents of visible controls is a strip teaching you the
  // slower way to do what you were about to do anyway.
  //
  // It no longer changes height either. The monitor row that used to replace
  // it is a card floating over the grid, so the panel underneath stays
  // exactly the size it was — which is the other half of a menu not being a
  // mode.
  //
  // The keys all still work. They are simply no longer the interface.
  function stripHeight() { return 34; }

  // THE SEARCH LINE, while there is something typed (user, 2026-10-28:
  // "just like artemis"): the filter in a line of its own over the
  // pictures, not in the bottom bar; the panel grows by it
  readonly property int inputH: popup.view === "backgrounds" && popup.query.length > 0 ? 36 : 0
  function calcHeight() {
    return popup.inputH + popup.gridHeight() + popup.stripHeight();
  }

  // Nothing typed, nothing scanning — the line is free to report state rather
  // than to carry a message.
  // Which monitor this picker is on, which is the subject of its own fit
  // ring. A PanelWindow always has a screen; the fallback is only for the
  // frame before one is assigned.
  readonly property string screenName:
    popup.screen ? popup.screen.name : Picasso.fallbackKey

  readonly property bool restingStatus: popup.query === "" && !Picasso.scanning

  // One piece of cycling state. Set apart by the row's spacing, not by a
  // separator glyph of its own — the chip's border already says where it
  // starts and ends.
  //
  // DRAWN AS A CHIP, not as a word. These were plain text the same weight and
  // color as the count beside them, so the two things that can be clicked in
  // this strip looked exactly like the one thing that cannot — the only hint
  // was the cursor changing, and the cursor does not change here any more. A
  // bordered chip says "press me" without a hint bar having to say it.
  component Ring: Item {
    id: ring
    property string label: ""
    property var act: null

    implicitWidth: chip.width
    implicitHeight: 22

    Rectangle {
      id: chip
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: ringWord.implicitWidth + 18
      height: 22
      radius: Zenon.radiusControl
      color: ringMa.pressed
        ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.26)
        : (Zenon.wash(0.06))
      border.width: 1
      border.color: ringMa.pressed ? popup.highlight : Zenon.border
      Behavior on color {
        ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
      }
      Behavior on border.color {
        ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
      }

      Text {
        textFormat: Text.PlainText
        id: ringWord
        anchors.centerIn: parent
        text: ring.label
        color: popup.headColor
        font.family: Zenon.face
        font.weight: 600
        font.pixelSize: Zenon.px(14)
      }

      MouseArea {
        id: ringMa
        anchors.fill: parent
        hoverEnabled: true
        onClicked: ring.act()
      }
    }
  }

  focusable: true

  // A DRAG OWNS THE POINTER UNTIL IT IS RELEASED; that is what a drag IS.
  //
  // The scrollbar overlays the grid and its strip is a few pixels from the
  // panel's right edge, so a drag down the bar very easily wanders off the
  // panel, off this output, or ends with the button coming up over the
  // desktop. Each of those is "input somewhere else" to everything that
  // dismisses this popup — the compositor takes the focus grab away, and the
  // backdrop area is sitting there waiting for a click. The list would stop
  // dead halfway down with the picker gone.
  // and while the screen picker is choosing the card's accent: its overlay
  // takes the focus, and the card must still be there when it hands back
  // (or the maker's color)
  readonly property bool capturing: gridScroll.dragging || Picasso.pickInto === "card:accent"
                                    || Picasso.pickInto === "popup:maker"
  Connections {
    target: Picasso
    function onColorPicked(into, hex) { if (into === "popup:maker") popup.pickHex = hex; }
    // another backgrounds directory, or this level gone from it (moved,
    // deleted, rescanned): back to the top, never an empty level
    function onDirChanged() { popup.sub = ""; popup.deep = ""; popup.sel = 0; popup.forgetHistory(); }
    function onFilesChanged() {
      if (popup.sub !== "" && popup.filtered.length === 0) {
        popup.sub = ""; popup.deep = ""; popup.sel = 0; popup.forgetHistory();
      }
    }
  }

  // A clear that arrived mid-gesture was SWALLOWED, and a swallowed grab is
  // still a lost one: it has to be taken again when the gesture ends, or
  // clicking away would never close the picker for the rest of its life.
  property bool regrab: false
  onCapturingChanged: if (!popup.capturing) popup.regrab = false

  HyprlandFocusGrab {
    id: grab
    windows: [popup]
    active: popup.shown && !popup.regrab
    onCleared: {
      if (popup.capturing) { popup.regrab = true; return; }
      popup.closePopup();
    }
  }

  IpcHandler {
    target: "Picasso"

    function toggle() { popup.toggle(); }
    function rescan(): string { Picasso.scan(); return "scanning"; }
    // capture: `shot screen`, `shot window`, `shot window-plain` (no
    // shadow), `shot region`
    function shot(mode: string): string {
      if (["screen", "window", "window-plain", "region"].indexOf(mode) < 0)
        return "shot screen|window|window-plain|region";
      Picasso.shoot(mode);
      return mode;
    }
    function pick(): string { Picasso.pick(); return "picking"; }
    function measure(): string { Picasso.measure(); return "measuring"; }
    // for argus' recordings: the region overlay, the rectangle written to
    // `reply` ("X,Y WxH", empty when aborted) rather than captured. The
    // call itself answers at once; the file is the answer. `pickRegion` draws
    // a box, `pickWindow` clicks a window.
    function pickRegion(reply: string): string { Picasso.pickGeometry("region", reply); return "picking"; }
    function pickWindow(reply: string): string { Picasso.pickGeometry("window", reply); return "picking"; }
    // the slideshow, from a keybind: `next`, `stop`
    function next(): string { Picasso.nextSlide(); return Picasso.slideshow ? "next" : "no slideshow"; }
    function stop(): string { Picasso.stopSlideshow(); return "stopped"; }
    function annotate(path: string): string { Picasso.annotate(path); return path; }
    // the viewer: one path, or several separated by newlines; "" for the
    // pictures directory
    function view(paths: string): string { Picasso.view(paths); return paths; }
    function status(): string {
      return "dir=" + Picasso.dir + " files=" + Picasso.files.length
        + " assignment=" + JSON.stringify(Picasso.assignment);
    }
  }

  // ---------------------------------------------------------- actions --

  function openPopup() {
    popup.cardOnly = false;
    popup.shown = true;
    popup.collapsing = false;
    popup.regrab = false;
    popup.query = "";
    // back where it was left (Picasso.place), not at the top — unless that
    // directory has no pictures any more (onFilesChanged takes it up)
    popup.sub = Picasso.placeSub();
    popup.sel = 0;
    popup.focusOpen = false;
    popup.focusPath = "";
    popup.view = "backgrounds";
    Picasso.scan();
    popup.playOpen();
    popup.syncFocus();
  }

  function closePopup() {
    popup.collapsing = true;
    popup.playClose();
  }

  function toggle() {
    if (popup.shown) popup.closePopup();
    else popup.openPopup();
  }

  function syncFocus() {
    Qt.callLater(() => {
      if (!popup.shown) return;
      bgRoot.forceActiveFocus();
    });
  }

  function clampSel() {
    popup.sel = Nav.clamp(popup.sel, popup.filtered.length);
    followSelection();
  }

  function moveSel(delta) {
    const len = popup.filtered.length;
    if (len === 0) return;
    popup.sel = Nav.clamp(popup.sel + delta, len);
    followSelection();
  }

  function followSelection() {
    Qt.callLater(() => grid.positionViewAtIndex(popup.sel, GridView.Contain));
  }

  // `from` is where the card grows out of, in the surface's own coordinates
  // — the card lives in this surface, so no screen origin is involved.
  function openFocus(list, index, from) {
    if (index < 0 || index >= list.length) return;
    if (list === popup.colorItems) popup.colorSel = index;
    else popup.sel = index;
    popup.focusPath = list[index].path;
    popup.focusFrom = from;
    focusCard.reset();
    popup.focusOpen = true;
  }

  // FROM OUTSIDE THE PICKER — the viewer's "Set as background". The picture
  // need not be in the background directory: the card only needs a path, and
  // one that is not in the grid simply has nothing to browse to either side.
  // The viewer's look arrives staged, so what was dialed there is what the
  // card shows and what Apply sets.
  //
  // A SCRATCH PICTURE, KEPT ONLY IF IT IS USED. The viewer's selection is
  // rendered to a png in the runtime directory and handed over with `adopt`
  // ({ dir, name }): Apply writes it into that directory under a free name and
  // sets that (FocusCard.apply); the card closed any other way deletes it,
  // and nothing was saved.
  property var focusAdopt: null
  function dropAdopt() {
    const ad = popup.focusAdopt;
    if (!ad) return;
    popup.focusAdopt = null;
    Quickshell.execDetached(["rm", "-f", ad.tmp]);
  }
  onFocusOpenChanged: if (!popup.focusOpen) popup.dropAdopt()
  function focusFor(path, look, adopt) {
    popup.dropAdopt();
    popup.focusAdopt = adopt ? Object.assign({ tmp: path }, adopt) : null;
    // an open picker keeps its grid under the card; a closed one opens as
    // the card and nothing else
    if (!popup.shown) { popup.openPopup(); popup.cardOnly = true; }
    popup.view = "backgrounds";
    popup.focusPath = path;
    focusCard.reset();
    if (look && Object.keys(look).length > 0) focusCard.stageLook = Object.assign({}, look);
    // NOT YET — only once the surface knows its size. Opened from nothing,
    // this runs before the compositor has told the layer how big it is, and
    // the card's grow played out against a surface 0 pixels wide: it came
    // out of the top-left corner and had finished by the time anything was
    // drawn. So the card is asked for when there is somewhere to put it.
    popup.pendingFocus = true;
    popup.settleFocus();
  }
  property bool pendingFocus: false
  function settleFocus() {
    if (!popup.pendingFocus || popup.width <= 0 || popup.height <= 0) return;
    popup.pendingFocus = false;
    popup.focusFrom = Qt.point(popup.width / 2, popup.height / 2);
    popup.focusOpen = true;
  }
  onWidthChanged: popup.settleFocus()
  onHeightChanged: popup.settleFocus()

  Connections {
    target: Picasso
    function onSetterRequested(path, look, adopt) { popup.focusFor(path, look, adopt); }
  }

  // Opened from the keyboard, which has no pointer to grow it from: it comes
  // out of the selected cell instead, which is where you were looking.
  function openFocusAtSelection() {
    const colors = popup.view === "colors";
    const list = colors ? popup.colorItems : popup.filtered;
    if (list.length === 0) return;
    const i = Math.min(colors ? popup.colorSel : popup.sel, list.length - 1);
    if (!colors && list[i].dir) { popup.enterDir(list[i]); return; }
    popup.openFocus(list, i, popup.cellCentre(i));
  }

  // the middle of a cell's picture, in surface coordinates, for the card to
  // grow out of or go back into
  function cellCentre(i) {
    const colors = Art.isColor(popup.focusPath) || popup.view === "colors";
    const item = colors ? colorGrid.itemAtIndex(i) : grid.itemAtIndex(i);
    if (!item) return Qt.point(popup.width / 2, popup.height / 2);
    return item.mapToItem(null, item.width * 0.5,
                          colors ? item.height * 0.4 : 12 + (popup.cellH - 52) * 0.5);
  }

  // Back into whichever cell the card ended on, which is not the one it came
  // out of if you browsed.
  function closeFocus() {
    if (popup.cardOnly) { popup.focusOpen = false; popup.closePopup(); return; }
    if (popup.focusIndex >= 0)
      popup.focusFrom = popup.cellCentre(popup.focusIndex + (Art.isColor(popup.focusPath) ? 0 : popup.dirCount));
    popup.focusOpen = false;
    popup.syncFocus();
  }

  // The card BROWSES. Stepping to the neighbor keeps everything staged —
  // you are comparing backgrounds under one set of answers, not starting the
  // card over — and moves the grid's selection behind it, so closing the
  // card leaves you where you ended up.
  function stepFocus(delta) {
    const list = popup.focusList;
    // a picture from outside the list (the viewer's Set as background, a
    // scratch selection) has no neighbors: a step landed on list[1], an
    // unrelated background (audit 2026-10-28d; the arrows already hide)
    if (list.length === 0 || popup.focusIndex < 0) return;
    const from = popup.focusIndex;
    const to = Math.max(0, Math.min(from + delta, list.length - 1));
    if (to === popup.focusIndex) return;
    popup.focusPath = list[to].path;
    if (Art.isColor(popup.focusPath)) {
      popup.colorSel = to;
      Qt.callLater(() => colorGrid.positionViewAtIndex(to, GridView.Contain));
    } else {
      // the grid has the directories ahead of the pictures
      popup.sel = to + popup.dirCount;
      popup.followSelection();
    }
  }

  function moveColorSel(delta) {
    const len = popup.colorItems.length;
    if (len === 0) return;
    popup.colorSel = Math.max(0, Math.min(popup.colorSel + delta, len - 1));
    Qt.callLater(() => colorGrid.positionViewAtIndex(popup.colorSel, GridView.Contain));
  }

  function setView(v) {
    if (popup.view === v) return;
    popup.view = v;
    popup.syncFocus();
  }

  // ------------------------------------------------------------ panel --

  // The surface outside the panel. (While the card is up its scrim covers
  // all of this, so a click out here only ever means the picker.)
  MouseArea {
    anchors.fill: parent
    z: 0
    onClicked: {
      // not while the scrollbar has the pointer: a drag released out here is
      // the end of a gesture, not a click at the desktop
      if (popup.capturing) return;
      popup.closePopup();
    }
  }

  LayerPanel {
    id: panel
    host: popup
    ground: bgRoot
    shadowRadius: bgRoot.radius
    width: Zenon.layerWidth(1000)
    height: popup.calcHeight()
    // Out of sight while the card is shown alone — opacity rather than
    // visible, because the keys are the panel's (bgRoot holds the focus) and
    // an invisible item cannot hold it.
    opacity: popup.cardOnly ? 0 : popup.contentFade

    PanelGround {
      id: bgRoot
      color: popup.bgColor

      Keys.onEscapePressed: (event) => {
        event.accepted = true;
        // innermost first, the cascade every layer here uses: the card (which
        // may have a color open inside it), then the filter, and only then
        // the panel
        if (popup.focusOpen) { if (!focusCard.cancel()) popup.closeFocus(); }
        else if (popup.query !== "") popup.query = "";
        else if (!popup.upDir()) popup.closePopup();
      }

      Keys.onPressed: (event) => {
        // The card is modal over the grid and the keys are ITS while it is
        // up: the arrows walk its own controls, not the grid behind it. See
        // FocusCard.handleKey. Escape is handled above.
        if (popup.focusOpen) {
          if (focusCard.handleKey(event)) event.accepted = true;
          return;
        }

        // tab flips between pictures and colors
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          event.accepted = true;
          popup.setView(popup.view === "colors" ? "backgrounds" : "colors");
          return;
        }

        // The color tab has no filter to type into; the arrows walk the
        // swatches and return lifts one into the card.
        if (popup.view === "colors") {
          const k = event.key;
          if (k === Qt.Key_Left) popup.moveColorSel(-1);
          else if (k === Qt.Key_Right) popup.moveColorSel(1);
          else if (k === Qt.Key_Up) popup.moveColorSel(-popup.colorCols);
          else if (k === Qt.Key_Down) popup.moveColorSel(popup.colorCols);
          else if (k === Qt.Key_Return || k === Qt.Key_Enter) popup.openFocusAtSelection();
          else return;
          event.accepted = true;
          return;
        }

        if (event.key === Qt.Key_S && (event.modifiers & Qt.AltModifier)) {
          event.accepted = true;
          Picasso.cycleSort();
          // the row under the cursor is meaningless once the order changes
          popup.sel = 0;
          popup.followSelection();
        } else if (event.key === Qt.Key_F && (event.modifiers & Qt.AltModifier)) {
          // How the image is fitted to a monitor that is not its shape:
          // cropped, fitted, stretched, centered, tiled. Alt, and beside the
          // sort, because it is the same kind of thing — a ring you step
          // through that changes how the list you are looking at is applied
          // rather than which images are in it.
          //
          // The selection is NOT reset the way the sort resets it: the order
          // has not changed, so the row under the cursor is still the row you
          // were on, and the background already on screen re-fits underneath
          // the picker as you step. That is the point — you are watching it.
          event.accepted = true;
          Picasso.cycleFitFor(popup.screenName);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          event.accepted = true;
          popup.openFocusAtSelection();
        } else if (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier)) {
          event.accepted = true; popup.back();
        } else if (event.key === Qt.Key_Right && (event.modifiers & Qt.AltModifier)) {
          event.accepted = true; popup.forward();
        } else if (event.key === Qt.Key_Left) {
          event.accepted = true; popup.moveSel(-1);
        } else if (event.key === Qt.Key_Right) {
          event.accepted = true; popup.moveSel(1);
        } else if (event.key === Qt.Key_Up) {
          event.accepted = true; popup.moveSel(-popup.cols);
        } else if (event.key === Qt.Key_Down) {
          event.accepted = true; popup.moveSel(popup.cols);
        } else if (event.key === Qt.Key_PageUp) {
          event.accepted = true; popup.moveSel(-popup.cols * popup.visibleRows);
        } else if (event.key === Qt.Key_PageDown) {
          event.accepted = true; popup.moveSel(popup.cols * popup.visibleRows);
        } else if (event.key === Qt.Key_Backspace) {
          event.accepted = true;
          if (popup.query.length > 0) {
            const chars = Array.from(popup.query);
            chars.pop();
            popup.query = chars.join("");
            popup.clampSel();
          } else popup.upDir();
        } else if (event.text && event.text.length > 0 &&
                   !(event.modifiers & Qt.ControlModifier) &&
                   !(event.modifiers & Qt.AltModifier) &&
                   !(event.modifiers & Qt.MetaModifier) &&
                   event.key !== Qt.Key_Escape && event.key !== Qt.Key_Tab) {
          event.accepted = true;
          popup.query += event.text;
          popup.clampSel();
        }
      }

      // the pictures (or colors) still below rise out of the bottom strip,
      // frosted — see morpheus/ScrollEdge. Before the column, so the strip
      // draws over them; follow runs each from its grid's bottom edge down.
      Repeater {
        model: [grid, colorGrid]
        delegate: ScrollEdge {
          required property var modelData
          view: modelData
          below: true
          follow: true
          bar: pickStrip
          visible: modelData.visible
        }
      }

      Column {
        anchors.fill: parent

        // ------------------------------------------- the search line --
        // Artemis' (ArtemisPopup inputBar): the lens and what you typed,
        // unfolding with the panel; a click on the × empties it
        Item {
          id: inputBar
          width: parent.width
          height: popup.inputH
          visible: height > 0.5
          clip: true
          Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
          Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: queryClear.left
            anchors.rightMargin: 8
            height: parent.height
            opacity: inputBar.height / 36
            Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
            Text {
              width: 30
              height: parent.height
              text: "\uf002"
              color: popup.highlight
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(18)
              verticalAlignment: Text.AlignVCenter
            }
            Text {
              width: parent.width - 30
              height: parent.height
              elide: Text.ElideLeft
              text: popup.query
              color: Zenon.ink
              font.family: Zenon.face
              font.weight: 600
              font.pixelSize: Zenon.px(18)
              verticalAlignment: Text.AlignVCenter
            }
          }
          ClearChip {
            id: queryClear
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            size: Zenon.px(15)
            opacity: inputBar.height / 36
            onClicked: popup.query = ""
          }
        }

        // ------------------------------------------------- the grid --
        Item {
          width: parent.width
          height: popup.gridHeight()

          Text {
            anchors.centerIn: parent
            visible: popup.view === "backgrounds" && popup.filtered.length === 0 && !Picasso.scanning
            text: Picasso.files.length === 0
              ? "No backgrounds in " + Picasso.dir : popup.query !== "" ? "Nothing matches \u201C" + popup.query + "\u201D" : "Nothing here"
            color: popup.dimColor
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(16)
          }

          // The grid is empty because the walk is still out, which is a
          // different thing from it being empty, and worth showing in the
          // middle of the space the rows will arrive into.
          Working {
            anchors.centerIn: parent
            running: popup.view === "backgrounds" && Picasso.scanning && popup.filtered.length === 0
            ink: popup.dimColor
            dot: 5
            gap: 7
          }

          // Three rows of thumbnails at a time and no other sign that there
          // are more below them — the grid is scrolled with a wheel now, so
          // it says how far down it goes and offers something to drag.
          Scrollbar {
            id: gridScroll
            flick: grid
            on: popup.view === "backgrounds"
            // OVER THE THUMBNAILS, not beside them. The grid is four fixed
            // columns of pictures and the bar is the only thing in the panel
            // that is furniture, so it is the one that gives way: it floats
            // on top and the pictures get the full width.
            //
            // z, because a sibling declared first is painted first — without
            // it the grid would cover the bar and swallow every press aimed
            // at it. Its own hit area only exists while the grid overflows
            // (enabled and visible both follow scrollable), so on a short
            // list nothing is stolen from the last column.
            z: 1
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            // one row per notch over the bar too, so it does not matter
            // which half of the strip the pointer happens to be over
            wheelStep: popup.cellH
          }

          GridView {
            id: grid
            // the chosen one slides (morpheus/CursorBand), rather than each row lighting
            CursorBand { follows: grid; index: popup.sel; insetX: 6; insetY: 6; radius: Zenon.menuRadius }
            // Finder's rubber band and the smooth wheel notch, one rule for
            // the whole shell — see morpheus/Elastic.qml. Inside the view
            // rather than over it: it pins itself to the viewport.
            //
            // ONE ROW PER NOTCH. Elastic's default is a tenth of the view,
            // which is 48px of a 450px grid — under a third of a 150px row,
            // so three notches moved the pictures by one and every rest
            // position cut a row in half. A grid of tiles has an obvious
            // unit and this is it.
            ElasticScroll { view: grid; step: popup.cellH }
            // mouse 4/5: back and forward, as in terminus
            TapHandler {
              acceptedButtons: Qt.BackButton | Qt.ForwardButton
              onTapped: (pt, button) => button === Qt.BackButton ? popup.back() : popup.forward()
            }
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            // THE FULL WIDTH. This used to stop at gridScroll.left to keep
            // width out of its own definition — width decides cellWidth
            // decides contentHeight decides whether it scrolls decides
            // width — but the circle was never closed here anyway: cols is
            // fixed at four, so row count is ceil(count / 4) and contentHeight
            // does not depend on how wide this is. The bar overlays instead
            // and the gutter is gone.
            anchors.right: parent.right
            clip: true
            visible: popup.view === "backgrounds" && popup.filtered.length > 0
            model: popup.filtered
            cellWidth: popup.cellW
            cellHeight: popup.cellH
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              id: cell
              required property var modelData
              required property int index
              width: popup.cellW
              height: popup.cellH

              readonly property bool selected: cell.index === popup.sel

              // a directory arrived in comes up a tile after a tile
              Term.TileRise { id: rise }
              Component.onCompleted: if (popup.staggering) { rise.hide(); rise.start(grid, cell.index); }

              Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: Zenon.windowRadius
                color: "transparent"
              }

              Thumb {
                id: thumbBox
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: popup.cellW - 28
                height: popup.cellH - 52
                // a directory is drawn as its pictures (dirCover); until
                // those are in, or with none of its own, its first picture
                // further down
                visible: !dirCover.shown
                path: cell.modelData.dir ? cell.modelData.cover : cell.modelData.path
                thumb: cell.modelData.thumb ?? ""
              }
              // terminus' directory cover, as its grid and picasso's gallery
              // draw one — see terminus/FolderCover.qml — cut to the
              // pictures' own box, so the row stays one row
              Term.FolderCover {
                id: dirCover
                anchors.fill: thumbBox
                aspect: thumbBox.width / Math.max(1, thumbBox.height)
                live: cell.modelData.dir === true
                path: cell.modelData.dir ? cell.modelData.path : ""
                stamp: cell.modelData.stamp || 0
                glyph: "\uF07B"
              }

              // a directory: how many pictures are in it, on a chip in the
              // cover's corner — with its mark too while the cover is a
              // single picture (FolderCover wears the mark on its own badge,
              // bottom-left, so the count steps over to the right)
              Rectangle {
                visible: cell.modelData.dir === true
                anchors.left: dirCover.shown ? undefined : thumbBox.left
                anchors.right: dirCover.shown ? thumbBox.right : undefined
                anchors.bottom: thumbBox.bottom
                anchors.margins: 6
                width: dirChip.implicitWidth + 14
                height: dirChip.implicitHeight + 6
                radius: Zenon.radiusControl
                color: Zenon.hud(0.75)
                Text {
                  id: dirChip
                  anchors.centerIn: parent
                  text: (dirCover.shown ? "" : "\uF07B  ") + (cell.modelData.count || 0)
                  color: Zenon.ink
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(12)
                }
              }

              // a corner tick on whatever is currently on a monitor, so the
              // grid says what is already in use without being opened twice
              Rectangle {
                anchors.right: thumbBox.right
                anchors.top: thumbBox.top
                anchors.margins: 4
                width: 18
                height: 18
                radius: height / 2
                visible: popup.inUse(cell.modelData.path)
                color: popup.entryColor
                Text {
                  anchors.centerIn: parent
                  text: ""
                  color: Zenon.onAccent
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(11)
                }
              }

              Text {
                textFormat: Text.PlainText
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: popup.cellW - 28
                text: cell.modelData.dir ? cell.modelData.name : Art.label(cell.modelData.path)
                color: cell.selected ? popup.highlight : popup.dimColor
                font.family: Zenon.face
                font.weight: cell.selected ? Font.Bold : Font.Normal
                font.pixelSize: Zenon.px(13)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
              }

              MouseArea {
                id: cellMa
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                // NO HOVER. The selection used to follow the pointer across
                // the grid, which meant it was never reporting a choice — it
                // was reporting where the mouse happened to be, and it moved
                // under the card the moment you reached for one. It is a
                // choice now: a click puts it somewhere and it stays there,
                // which is also what makes the keyboard's arrows and the
                // pointer agree about what is selected.
                // A DOUBLE CLICK OPENS (user, 2026-10-27), as in terminus and
                // the gallery: one click only selects. A directory goes in; a
                // picture lifts into the card, which grows out of the
                // thumbnail itself, so it reads as the picture coming forward
                // rather than a dialog arriving from nowhere. The right
                // button still opens at once — it used to open the menu the
                // card replaces, and a hand that has learned to right-click a
                // background should still get somewhere.
                function open() {
                  if (cell.modelData.dir) { popup.enterDir(cell.modelData); return; }
                  const p = thumbBox.mapToItem(null, thumbBox.width / 2,
                                               thumbBox.height / 2);
                  popup.openFocus(popup.filtered, cell.index, p);
                }
                onClicked: (mouse) => {
                  if (mouse.button === Qt.RightButton) cellMa.open();
                  else popup.sel = cell.index;
                }
                onDoubleClicked: (mouse) => { if (mouse.button === Qt.LeftButton) cellMa.open(); }
              }
            }
          }

          // ── the color tab ────────────────────────────────────────────
          // The swatches on the left, the maker on the right. A swatch lifts
          // into the card like a picture does; the maker can either use what
          // it has made straight away or keep it as a swatch of its own.
          Item {
            id: colorView
            anchors.fill: parent
            visible: popup.view === "colors"

            readonly property int makerW: 300

            GridView {
              id: colorGrid
              ElasticScroll { view: colorGrid; step: popup.colorCellH }
              // the chosen one slides (morpheus/CursorBand), rather than each row lighting
              CursorBand { follows: colorGrid; index: popup.colorSel; insetX: 4; insetY: 4; radius: Zenon.menuRadius }
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.right: maker.left
              anchors.leftMargin: 8
              anchors.topMargin: 8
              clip: true
              model: popup.colorItems
              cellWidth: Math.floor(colorGrid.width / popup.colorCols)
              cellHeight: popup.colorCellH
              boundsBehavior: Flickable.StopAtBounds

              delegate: Item {
                id: swCell
                required property var modelData
                required property int index
                width: colorGrid.cellWidth
                height: colorGrid.cellHeight
                readonly property bool selected: swCell.index === popup.colorSel

                Rectangle {
                  anchors.fill: parent
                  anchors.margins: 4
                  radius: Zenon.windowRadius
                  color: "transparent"
                }

                Rectangle {
                  id: chip
                  anchors.top: parent.top
                  anchors.topMargin: 10
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: parent.width - 24
                  height: parent.height - 44
                  radius: Zenon.windowRadius
                  color: swCell.modelData.hex
                  border.width: 1
                  border.color: swMa.pressed ? Zenon.wash(0.5) : Zenon.wash(0.12)
                }

                // in use, the same pink tick the pictures wear
                Rectangle {
                  anchors.right: chip.right
                  anchors.top: chip.top
                  anchors.margins: 4
                  width: 18
                  height: 18
                  radius: height / 2
                  visible: popup.inUse(swCell.modelData.path)
                  color: popup.entryColor
                  Text {
                    anchors.centerIn: parent
                    text: ""
                    color: Zenon.onAccent
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(11)
                  }
                }

                // a made color can be thrown away again; a preset cannot
                Rectangle {
                  anchors.left: chip.left
                  anchors.top: chip.top
                  anchors.margins: 4
                  width: 18
                  height: 18
                  radius: height / 2
                  visible: swCell.modelData.custom && swMa.containsMouse
                  color: delMa.pressed ? Zenon.red : Zenon.hud(0.65)
                  Text {
                    anchors.centerIn: parent
                    text: ""
                    color: delMa.pressed ? Zenon.onAccent : Zenon.ink
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(10)
                  }
                  MouseArea {
                    id: delMa
                    anchors.fill: parent
                    anchors.margins: -3
                    hoverEnabled: true
                    onClicked: Picasso.removeColor(swCell.modelData.hex)
                  }
                  z: 2
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: 10
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: parent.width - 16
                  horizontalAlignment: Text.AlignHCenter
                  text: swCell.modelData.custom ? swCell.modelData.hex : swCell.modelData.name
                  color: swCell.selected ? popup.highlight : popup.dimColor
                  font.family: Zenon.face
                  font.weight: swCell.selected ? Font.Bold : Font.Normal
                  font.pixelSize: Zenon.px(13)
                  elide: Text.ElideRight
                }

                MouseArea {
                  id: swMa
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: {
                    const p = chip.mapToItem(null, chip.width / 2, chip.height / 2);
                    popup.openFocus(popup.colorItems, swCell.index, p);
                  }
                }
              }
            }
            Scrollbar { flick: colorGrid; visible: colorGrid.visible; anchors.right: colorGrid.right; anchors.top: colorGrid.top; anchors.bottom: colorGrid.bottom }

            Rectangle {
              id: maker
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: colorView.makerW
              color: Zenon.wash(0.025)

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Zenon.border
              }

              Text {
                id: makerHead
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 18
                text: "Make a color"
                color: popup.dimColor
                font.family: Zenon.face
                font.weight: Zenon.titleWeight
                font.pixelSize: Zenon.px(12)
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Zenon.labelSpacing
              }

              ColorPicker {
                id: makerPicker
                anchors.top: makerHead.bottom
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                height: 300
                hex: popup.pickHex
                onEdited: (h) => popup.pickHex = h
                onAccepted: popup.syncFocus()
                onCancelled: popup.syncFocus()
              }

              Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 18
                spacing: 8

                // any color on screen into the maker: the suite's picker,
                // as oracle's Accent color has it (user, 2026-10-24)
                DialogButton {
                  glyph: true
                  label: "\u{F020A}"
                  onClicked: Picasso.pickFor("popup:maker")
                }
                // keep it as a swatch of its own
                DialogButton {
                  label: Picasso.colors.indexOf(popup.pickHex) >= 0 ? "Saved" : "Save"
                  ink: popup.dimColor
                  ready: Picasso.colors.indexOf(popup.pickHex) < 0
                  onClicked: Picasso.addColor(popup.pickHex)
                }
                // straight into the card, without keeping it
                DialogButton {
                  label: "Use"
                  ink: popup.highlight
                  primary: true
                  onClicked: {
                    const items = popup.colorItems;
                    let i = -1;
                    for (let k = 0; k < items.length; ++k)
                      if (items[k].hex === popup.pickHex) { i = k; break; }
                    const from = makerPicker.mapToItem(null, makerPicker.width / 2,
                                                       makerPicker.height / 2);
                    if (i >= 0) { popup.openFocus(items, i, from); return; }
                    // not a swatch yet: the card browses a list of one
                    popup.focusPath = Art.colorPath(popup.pickHex);
                    popup.focusFrom = from;
                    focusCard.reset();
                    popup.focusOpen = true;
                  }
                }
              }
            }
          }
        }

        // --------------------------------------------- bottom strip --
        Rectangle {
          id: pickStrip
          width: parent.width
          height: popup.stripHeight()
          // Zenon.hintBg, which is black, and not the translucent headBg this
          // used to draw. Every other footer in the shell — folio, artemis,
          // ideo, lexi — is the black strip, and a picker whose footer was a
          // shade of the panel instead was the only one where the line did
          // not read as its own ground. See-through since the grid rises out
          // of it (the ScrollEdges before the column), on the frosted floor.
          color: Zenon.hintFrostBg
          Behavior on height { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Zenon.border
          }

          // ── BACK AND FORWARD, then the crumbs, at the strip's left ────
          // terminus' own pill for them (BarChip, as its Chrome sets it):
          // unlit when there is nowhere to go.
          Term.BarChip {
            id: navChip
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            z: 2
            visible: popup.view === "backgrounds"
            height: crumbSegs.height
            partW: 28
            parts: [{ glyph: "\uF053", ok: trail.canUndo, size: Zenon.px(13), heavy: true },
                    { glyph: "\uF054", ok: trail.canRedo, size: Zenon.px(13), heavy: true }]
            onClicked: (i) => i === 0 ? popup.back() : popup.forward()
          }

          // terminus' crumb bar (terminus/Segments, as its Chrome sets it):
          // a step goes there, the one you are in lit. Longer than the room
          // it has, the trail keeps its end in sight — that is where you are.
          // The pictures only: the colors have no directories.
          Item {
            id: crumbBox
            anchors.left: navChip.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            z: 2
            visible: popup.view === "backgrounds"
            width: visible ? Math.max(0, Math.min(crumbSegs.implicitWidth,
              stripRight.x - crumbBox.x - 16 - stripMid.implicitWidth - 16)) : 0
            height: crumbSegs.height
            clip: true

            Term.Segments {
              id: crumbSegs
              x: Math.min(0, crumbBox.width - width)
              textSize: Zenon.px(13)
              weight: Zenon.titleWeight
              glyphWeight: Zenon.titleWeight
              pad: 22
              ink: Zenon.accentMuted
              options: popup.crumbList.map((c) => [c.path, c.label])
              glyphOf: (v) => {
                const c = popup.crumbList.find((k) => k.path === v);
                return Terminus.dirGlyph(v, Icons, c ? c.label : "");
              }
              // where you are, searching or not (a search looks there, under it)
              current: Picasso.everything ? popup.absOf("") : popup.absOf(popup.sub)
              faint: popup.crumbList.filter((c) => c.ghost === true).map((c) => c.path)
              onChose: (v) => {
                const c = popup.crumbList.find((k) => k.path === v);
                if (!c) return;
                // a step out of Everything is a step back into the
                // directories; a search keeps going, looking there instead
                if (Picasso.everything) Picasso.everything = false;
                popup.goSub(c.sub);
              }
            }
          }

          // THE STRIP'S RIGHT EDGE: what is running, the two rings that
          // decide how the grid is ordered and how it is fitted, and last
          // the view switch — the crumbs at the other end, and the filter's
          // hint between them.
          Row {
            id: stripRight
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            z: 2
            spacing: 8

            // A slideshow is running: say so, and offer the way to stop it,
            // from the one place you would go looking for it.
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              visible: Picasso.slideshow !== null
              width: ssRow.implicitWidth + 16
              height: 22
              radius: Zenon.radiusControl
              color: Qt.rgba(popup.entryColor.r, popup.entryColor.g, popup.entryColor.b, 0.12)
              border.width: 1
              border.color: Qt.rgba(popup.entryColor.r, popup.entryColor.g, popup.entryColor.b, 0.45)
              Row {
                id: ssRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                  text: "  every " + (Picasso.slideshow
                    ? (Picasso.slideshow.minutes >= 60 ? Picasso.slideshow.minutes / 60 + "h"
                                                       : Picasso.slideshow.minutes + "m") : "")
                  color: popup.entryColor
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(13)
                }
                Text {
                  text: ""
                  color: nextMa.pressed ? popup.highlight : popup.fgColor
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(13)
                  MouseArea { id: nextMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: Picasso.nextSlide() }
                }
                Text {
                  text: ""
                  color: stopMa.pressed ? Zenon.red : popup.fgColor
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(13)
                  MouseArea { id: stopMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: Picasso.stopSlideshow() }
                }
              }
            }

            // Neither ring is shown while you are typing or while the scan
            // is running: the line is carrying one message at a time, and
            // that message is what you typed or what it is doing.
            // every picture at once instead of a directory at a time
            Controls.Check {
              visible: popup.restingStatus && popup.view === "backgrounds"
              anchors.verticalCenter: parent.verticalCenter
              label: "Everything"
              lit: Picasso.everything
              // the accent, as the chips beside it speak
              ink: popup.headColor
              offInk: Zenon.alpha(popup.headColor, 0.7)
              litInk: popup.headColor
              textSize: Zenon.px(14)
              onToggled: {
                Picasso.everything = !Picasso.everything;
                popup.sub = "";
                popup.sel = 0;
                popup.followSelection();
              }
            }

            Ring {
              visible: popup.restingStatus && popup.view === "backgrounds"
              anchors.verticalCenter: parent.verticalCenter
              label: Picasso.sortMode
              act: () => {
                Picasso.cycleSort();
                // the row under the cursor is meaningless once the order
                // changes — the same reset alt+s does
                popup.sel = 0;
                popup.followSelection();
              }
            }

            // THIS MONITOR'S FIT, not every monitor's. It used to step
            // the default and clear the overrides with it, so setting one
            // screen to tile from the context menu and then touching the
            // ring on the other silently undid it. A ring in a panel that
            // is ITSELF on a monitor has an obvious subject.
            //
            // The name rides along when there is more than one screen,
            // because then "crop" alone is a claim about which.
            Ring {
              visible: popup.restingStatus && popup.view === "backgrounds"
              anchors.verticalCenter: parent.verticalCenter
              label: Picasso.fitLabelFor(popup.screenName)
                + (Quickshell.screens.length > 1 ? "  " + popup.screenName : "")
              act: () => Picasso.cycleFitFor(popup.screenName)
            }

            // PICTURES OR COLORS: terminus' Segments, as picasso's card
            // switches its tabs (user, 2026-10-12) — tab flips between them
            // too. At the right end since the crumbs took the left
            // (user, 2026-10-27).
            Term.Segments {
              anchors.verticalCenter: parent.verticalCenter
              textSize: Zenon.px(13)
              options: [["backgrounds", "Pictures"], ["colors", "Colors"]]
              current: popup.view
              onChose: (v) => popup.setView(v)
            }
          }

          Item {
            anchors.fill: parent

            // What you typed, after the crumbs. NO COUNT and no hint (user,
            // 2026-10-27): how many pictures and directories was a fact about
            // the grid you are already looking at.
            Row {
              id: stripMid
              anchors.left: parent.left
              anchors.leftMargin: crumbBox.visible ? crumbBox.x + crumbBox.width + 16 : 12
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Item {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Picasso.scanning
                  ? scanDots.implicitWidth : countText.implicitWidth
                implicitHeight: countText.implicitHeight

                // ── 3 · THE WORD BECOMES A MARK ───────────────────────
                // "scanning…" sat where the count sits and was read once.
                // See morpheus/Working.qml for why it is dots.
                Working {
                  id: scanDots
                  anchors.centerIn: parent
                  running: Picasso.scanning
                  ink: popup.dimColor
                }

                Text {
                  id: countText
                  // what you type is the search line's now (inputBar), not
                  // this one's (user, 2026-10-28)
                  visible: !Picasso.scanning
                  text: ""
                  color: clearMa.pressed ? popup.highlight : popup.headColor
                  font.bold: true
                  font.family: Zenon.face
                  font.weight: 600
                  font.pixelSize: Zenon.px(15)
                  Behavior on color {
                    ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                  }
                }

                // Escape empties the filter, and escape was on the strip that
                // is gone. Clicking what you typed empties it too, so there
                // is a way back out of a search that does not need a key.
                MouseArea {
                  id: clearMa
                  anchors.fill: parent
                  anchors.margins: -4
                  enabled: false
                  hoverEnabled: true
                  onClicked: popup.query = ""
                }
              }

            }

          }
        }
      }
    }
  }

  // is this file currently painted on any monitor. Asked per CONNECTED
  // monitor, not of every value in the assignment: the "*" fallback outlives
  // the moment every monitor got an override of its own, and an unplugged
  // monitor's key stays too — both used to mark old backgrounds as current.
  function inUse(path) {
    for (let i = 0; i < popup.screenNames.length; ++i)
      if (Picasso.wallpaperFor(popup.screenNames[i]) === path) return true;
    return false;
  }

  // ── the card ──────────────────────────────────────────────────────────
  // In THIS surface rather than a window of its own, which is what lets it
  // grow out of the very cell that was clicked — and what keeps the focus
  // grab a list of one.
  FocusCard {
    id: focusCard
    anchors.fill: parent
    z: 3
    picker: popup
    panel: popup.panelItem
  }
}
