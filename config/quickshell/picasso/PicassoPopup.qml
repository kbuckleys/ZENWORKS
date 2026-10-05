// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The setter. Pick a wallpaper in the grid and it lifts out into a card of
// its own: a large look at it, the monitors drawn to scale as they sit on
// the desk, how it is fitted, and one button that puts it there.

import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "../morpheus"
import "picasso.js" as Art

LayerPopup {
  id: popup

  readonly property color bgColor: Zenon.layerBg
  readonly property color fgColor: Zenon.white
  readonly property color headColor: Zenon.cyan
  readonly property color dimColor: Zenon.muted
  // WHAT YOU ARE TOUCHING, and what has been CHANGED, are two different
  // facts and now wear two different colours.
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
  // wallpaper folder, and plain colours. A colour is assigned exactly like a
  // picture (see picasso.js isColor), so everything past choosing one — the
  // card, the monitors, the tick on what is in use — is the same machinery.
  property string view: "backgrounds"
  property int colorSel: 0
  // the colour being made in the colour tab's picker
  property string pickHex: "#7a8cff"

  // ── the focus card ───────────────────────────────────────────────────
  // A click LIFTS a background into a card — see FocusCard.qml. What the
  // card is about lives here, because the grid is what moves it: `focusPath`
  // is held rather than read off the selection, so a rescan reordering the
  // grid under the card cannot quietly change its subject.
  property string focusPath: ""
  property bool focusOpen: false
  // THE CARD ALONE — the viewer's "Set as background". The setter is what was
  // asked for, not the wallpaper grid, so the panel stays out of sight, the
  // card sits in the middle of the screen, and putting the card away puts
  // the whole surface away. Cleared by every ordinary open.
  property bool cardOnly: false
  // where the card grows out of — the clicked cell, in surface coordinates
  property point focusFrom: Qt.point(0, 0)

  // Filter first, then order: the sort only has to touch what survived, and
  // the two are separate questions the user changes independently.
  readonly property var filtered: Art.sortRows(
    Art.filter(Picasso.files, popup.query, Picasso.dir),
    Picasso.sortMode, Picasso.dir)

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
    return "Custom colour";
  }

  // what the card browses: whichever list its subject came from
  readonly property var focusList:
    Art.isColor(popup.focusPath) ? popup.colorItems : popup.filtered

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
  readonly property int cellW:
    Math.max(80, Math.floor(grid.width / popup.cols))
  readonly property int cellH: 150

  function gridHeight() {
    // the colour tab is always full height: its picker needs the room
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

  function calcHeight() {
    return popup.gridHeight() + popup.stripHeight();
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
  // colour as the count beside them, so the two things that can be clicked in
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
      radius: 4
      color: ringMa.pressed
        ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.26)
        : (ringMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
      border.width: 1
      border.color: ringMa.containsMouse ? popup.highlight : Zenon.border
      Behavior on color {
        ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
      }
      Behavior on border.color {
        ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
      }

      Text {
        id: ringWord
        anchors.centerIn: parent
        text: ring.label
        color: popup.headColor
        font.family: Zenon.face
        font.weight: 600
        font.pixelSize: 14
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
  readonly property bool capturing: gridScroll.dragging

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
    // capture: `shot screen`, `shot window`, `shot region`
    function shot(mode: string): string {
      if (["screen", "window", "region"].indexOf(mode) < 0) return "shot screen|window|region";
      Picasso.shoot(mode);
      return mode;
    }
    function pick(): string { Picasso.pick(); return "picking"; }
    // the slideshow, from a keybind: `next`, `stop`
    function next(): string { Picasso.nextSlide(); return Picasso.slideshow ? "next" : "no slideshow"; }
    function stop(): string { Picasso.stopSlideshow(); return "stopped"; }
    function annotate(path: string): string { Picasso.annotate(path); return path; }
    // the viewer: one path, or several separated by newlines; "" for the
    // pictures folder
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
    const len = popup.filtered.length;
    if (len === 0) popup.sel = 0;
    else popup.sel = Math.max(0, Math.min(popup.sel, len - 1));
    followSelection();
  }

  function moveSel(delta) {
    const len = popup.filtered.length;
    if (len === 0) return;
    popup.sel = Math.max(0, Math.min(popup.sel + delta, len - 1));
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
  // need not be in the wallpaper folder: the card only needs a path, and
  // one that is not in the grid simply has nothing to browse to either side.
  // The viewer's look arrives staged, so what was dialled there is what the
  // card shows and what Apply sets.
  //
  // A SCRATCH PICTURE, KEPT ONLY IF IT IS USED. The viewer's selection is
  // rendered to a png in the runtime directory and handed over with `adopt`
  // ({ dir, name }): Apply writes it into that folder under a free name and
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
    if (popup.focusIndex >= 0) popup.focusFrom = popup.cellCentre(popup.focusIndex);
    popup.focusOpen = false;
    popup.syncFocus();
  }

  // The card BROWSES. Stepping to the neighbour keeps everything staged —
  // you are comparing backgrounds under one set of answers, not starting the
  // card over — and moves the grid's selection behind it, so closing the
  // card leaves you where you ended up.
  function stepFocus(delta) {
    const list = popup.focusList;
    if (list.length === 0) return;
    const from = popup.focusIndex < 0 ? 0 : popup.focusIndex;
    const to = Math.max(0, Math.min(from + delta, list.length - 1));
    if (to === popup.focusIndex) return;
    popup.focusPath = list[to].path;
    if (Art.isColor(popup.focusPath)) {
      popup.colorSel = to;
      Qt.callLater(() => colorGrid.positionViewAtIndex(to, GridView.Contain));
    } else {
      popup.sel = to;
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

  Item {
    id: panel
    width: Zenon.layerWidth(1000)
    height: popup.calcHeight()
    Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
    // Either edge. A layer opens out of the pill, so it has to be on the
    // same one, off whichever it is by the same lift. Placed by y, NOT by a
    // top/bottom anchor pair: flipping two anchors at runtime updates one
    // before the other, for that instant both apply and stretch the panel to
    // the screen, and that stretch overwrites — and so unbinds — `height`.
    // The panel then stayed screen-tall until the shell was restarted.
    anchors.horizontalCenter: parent.horizontalCenter
    y: Zenon.barTop ? Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
      : parent.height - height - Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
    z: 1
    // Out of sight while the card is shown alone — opacity rather than
    // visible, because the keys are the panel's (bgRoot holds the focus) and
    // an invisible item cannot hold it.
    opacity: popup.cardOnly ? 0 : popup.contentFade
    transform: Scale {
      origin.x: panel.width / 2
      // grows out of the edge the bar is on, which is the edge it came from
      origin.y: Zenon.barTop ? 0 : panel.height
      xScale: popup.panelX
      yScale: popup.panelY
    }

    // Swallows what no control wanted, so a press on bare panel is not a
    // press on the desktop behind it.
    MouseArea {
      anchors.fill: parent
    }

    LayerShadow {
      panel: bgRoot
      cornerRadius: bgRoot.radius
      morphed: popup.morphMode
    }

    // ClippingRectangle, not Rectangle + clip: true. Qt's own clip is
    // RECTANGULAR — it clips to the bounding box and knows nothing about the
    // radius — so every square child painted to the panel's edge (the bottom
    // strip most visibly) filled in the rounded corners behind it. This one
    // clips to the rounded shape itself.
    ClippingRectangle {
      id: bgRoot
      anchors.fill: parent
      // Grown by its own border: a ClippingRectangle insets its children by
      // border.width on every side, so the content box came out 2px smaller
      // than the panel and any layout measured against the panel's size fell
      // one row or one column short. This hands the content its full box back.
      anchors.margins: -bgRoot.border.width
      color: popup.bgColor
      radius: Zenon.pillRadius
      border.color: Zenon.border
      border.width: 1
      focus: true

      Keys.onEscapePressed: (event) => {
        event.accepted = true;
        // innermost first, the cascade every layer here uses: the card (which
        // may have a colour open inside it), then the filter, and only then
        // the panel
        if (popup.focusOpen) { if (!focusCard.cancel()) popup.closeFocus(); }
        else if (popup.query !== "") popup.query = "";
        else popup.closePopup();
      }

      Keys.onPressed: (event) => {
        // The card is modal over the grid and the keys are ITS while it is
        // up: the arrows walk its own controls, not the grid behind it. See
        // FocusCard.handleKey. Escape is handled above.
        if (popup.focusOpen) {
          if (focusCard.handleKey(event)) event.accepted = true;
          return;
        }

        // tab flips between pictures and colours
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          event.accepted = true;
          popup.setView(popup.view === "colors" ? "backgrounds" : "colors");
          return;
        }

        // The colour tab has no filter to type into; the arrows walk the
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
          // cropped, fitted, stretched, centred, tiled. Alt, and beside the
          // sort, because it is the same kind of thing — a ring you step
          // through that changes how the list you are looking at is applied
          // rather than which images are in it.
          //
          // The selection is NOT reset the way the sort resets it: the order
          // has not changed, so the row under the cursor is still the row you
          // were on, and the wallpaper already on screen re-fits underneath
          // the picker as you step. That is the point — you are watching it.
          event.accepted = true;
          Picasso.cycleFitFor(popup.screenName);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          event.accepted = true;
          popup.openFocusAtSelection();
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
          }
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

      // the pictures (or colours) still below rise out of the bottom strip,
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

        // ------------------------------------------------- the grid --
        Item {
          width: parent.width
          height: popup.gridHeight()

          Text {
            anchors.centerIn: parent
            visible: popup.view === "backgrounds" && popup.filtered.length === 0 && !Picasso.scanning
            text: Picasso.files.length === 0
              ? "no backgrounds in " + Picasso.dir : "no match"
            color: popup.dimColor
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 16
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

              Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: 6
                color: cell.selected ? Zenon.border : "transparent"
              }

              Thumb {
                id: thumbBox
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: popup.cellW - 28
                height: popup.cellH - 52
                path: cell.modelData.path
                thumb: cell.modelData.thumb ?? ""
              }

              // a corner tick on whatever is currently on a monitor, so the
              // grid says what is already in use without being opened twice
              Rectangle {
                anchors.right: thumbBox.right
                anchors.top: thumbBox.top
                anchors.margins: 4
                width: 18
                height: 18
                radius: 9
                visible: popup.inUse(cell.modelData.path)
                color: popup.entryColor
                Text {
                  anchors.centerIn: parent
                  text: ""
                  color: "#000000"
                  font.family: Zenon.face
                  font.pixelSize: 11
                }
              }

              Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: popup.cellW - 28
                text: Art.label(cell.modelData.path)
                color: cell.selected ? popup.highlight : popup.dimColor
                font.family: Zenon.face
                font.weight: cell.selected ? Font.Bold : Font.Normal
                font.pixelSize: 13
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
                // Either button lifts it into the card. The right one used
                // to open the menu the card replaces, and a hand that has
                // learned to right-click a wallpaper should still get
                // somewhere. The card grows out of the thumbnail itself, so
                // it reads as the picture coming forward rather than a
                // dialog arriving from nowhere.
                onClicked: {
                  const p = thumbBox.mapToItem(null, thumbBox.width / 2,
                                               thumbBox.height / 2);
                  popup.openFocus(popup.filtered, cell.index, p);
                }
              }
            }
          }

          // ── the colour tab ────────────────────────────────────────────
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
                  radius: 6
                  color: swCell.selected ? Zenon.border : "transparent"
                }

                Rectangle {
                  id: chip
                  anchors.top: parent.top
                  anchors.topMargin: 10
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: parent.width - 24
                  height: parent.height - 44
                  radius: 6
                  color: swCell.modelData.hex
                  border.width: 1
                  border.color: swMa.containsMouse ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(1, 1, 1, 0.12)
                }

                // in use, the same pink tick the pictures wear
                Rectangle {
                  anchors.right: chip.right
                  anchors.top: chip.top
                  anchors.margins: 4
                  width: 18
                  height: 18
                  radius: 9
                  visible: popup.inUse(swCell.modelData.path)
                  color: popup.entryColor
                  Text {
                    anchors.centerIn: parent
                    text: ""
                    color: "#000000"
                    font.family: Zenon.face
                    font.pixelSize: 11
                  }
                }

                // a made colour can be thrown away again; a preset cannot
                Rectangle {
                  anchors.left: chip.left
                  anchors.top: chip.top
                  anchors.margins: 4
                  width: 18
                  height: 18
                  radius: 9
                  visible: swCell.modelData.custom && swMa.containsMouse
                  color: delMa.containsMouse ? Zenon.red : Qt.rgba(0, 0, 0, 0.65)
                  Text {
                    anchors.centerIn: parent
                    text: ""
                    color: delMa.containsMouse ? "#000000" : "#ffffff"
                    font.family: Zenon.face
                    font.pixelSize: 10
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
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: 10
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: parent.width - 16
                  horizontalAlignment: Text.AlignHCenter
                  text: swCell.modelData.custom ? swCell.modelData.hex : swCell.modelData.name
                  color: swCell.selected ? popup.highlight : popup.dimColor
                  font.family: Zenon.face
                  font.weight: swCell.selected ? Font.Bold : Font.Normal
                  font.pixelSize: 13
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

            Rectangle {
              id: maker
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: colorView.makerW
              color: Qt.rgba(1, 1, 1, 0.025)

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
                text: "Make a colour"
                color: popup.dimColor
                font.family: Zenon.face
                font.weight: 600
                font.pixelSize: 12
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2
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

          // PICTURES OR COLOURS. Two words at the strip's left edge, the
          // one you are in lit — tab flips between them too.
          Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            z: 2
            spacing: 2
            Repeater {
              model: [{ k: "backgrounds", t: "Pictures" }, { k: "colors", t: "Colours" }]
              delegate: Rectangle {
                id: vBtn
                required property var modelData
                readonly property bool on: popup.view === vBtn.modelData.k
                width: vText.implicitWidth + 18
                height: 22
                radius: 4
                color: vBtn.on ? Qt.rgba(1, 1, 1, 0.1)
                  : (vMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                Text {
                  id: vText
                  anchors.centerIn: parent
                  text: vBtn.modelData.t
                  color: vBtn.on ? popup.headColor : (vMa.containsMouse ? popup.fgColor : popup.dimColor)
                  font.family: Zenon.face
                  font.weight: 600
                  font.pixelSize: 13
                }
                MouseArea {
                  id: vMa
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: popup.setView(vBtn.modelData.k)
                }
              }
            }
          }

          // THE STRIP'S RIGHT EDGE: what is running, then the two rings that
          // decide how the grid is ordered and how it is fitted — controls
          // at one end, the view switch at the other, and the count and its
          // hint in the middle where the eye lands.
          Row {
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
              radius: 11
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
                  font.pixelSize: 13
                }
                Text {
                  text: ""
                  color: nextMa.containsMouse ? popup.highlight : popup.fgColor
                  font.family: Zenon.face
                  font.pixelSize: 13
                  MouseArea { id: nextMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: Picasso.nextSlide() }
                }
                Text {
                  text: ""
                  color: stopMa.containsMouse ? Zenon.red : popup.fgColor
                  font.family: Zenon.face
                  font.pixelSize: 13
                  MouseArea { id: stopMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: Picasso.stopSlideshow() }
                }
              }
            }

            // Neither ring is shown while you are typing or while the scan
            // is running: the line is carrying one message at a time, and
            // that message is what you typed or what it is doing.
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
          }

          Column {
            anchors.fill: parent
            topPadding: 6
            bottomPadding: 6
            spacing: -2

            // The count, and beside it the hint for the one thing it also
            // is: the filter you type into.
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
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
                  // Doubles as the input, since there is no field — the same
                  // shape howler uses. What you type lands here.
                  visible: !Picasso.scanning
                  text: popup.view === "colors"
                    ? popup.colorItems.length + " Colours"
                    : popup.query !== "" ? popup.query
                    : popup.filtered.length + (popup.filtered.length === 1
                        ? " Background" : " Backgrounds")
                  // MUTED WHEN IT IS A COUNT, bright when it is your query.
                  // The count is a fact about the grid you are already
                  // looking at; the query is the only thing on this line you
                  // put there, and the two were the same colour.
                  color: popup.query === "" ? popup.dimColor
                    : (clearMa.containsMouse ? popup.highlight : popup.headColor)
                  font.bold: true
                  font.family: Zenon.face
                  font.weight: 600
                  font.pixelSize: 15
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
                  enabled: popup.query !== ""
                  hoverEnabled: true
                  onClicked: popup.query = ""
                }
              }

              // The one thing on the old strip that was not an explanation of
              // a visible control: filtering has nothing on screen to point
              // at, because it IS the line above. So it keeps its hint, and
              // only while there is nothing typed.
              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: popup.restingStatus
                text: popup.view === "colors" ? "   tab for pictures" : "   type to filter"
                color: Qt.rgba(popup.dimColor.r, popup.dimColor.g,
                               popup.dimColor.b, 0.7)
                font.family: Zenon.face
                font.pixelSize: 13
              }
            }

          }
        }
      }
    }
  }

  // is this file currently painted on any monitor
  function inUse(path) {
    const a = Picasso.assignment;
    for (const k in a) if (a[k] === path) return true;
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
