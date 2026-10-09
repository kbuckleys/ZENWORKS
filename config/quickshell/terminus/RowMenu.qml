// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── THE SURFACE THE RIGHT-CLICK MENU LIVES ON ────────────────────────
// An xdg-popup, which is the one kind of surface a Wayland client may put
// OUTSIDE its own window. That is the whole reason it exists here: the
// menu used to be an item inside the window, clamped to it, so a card
// taller than a short terminus was simply cut off at the bottom edge.
//
// The compositor places it, and it is the only party that can: a client is
// never told where its own window sits on screen, so nothing in here could
// work out whether the card was about to run off the display. `anchor`
// hands it the pointer in WINDOW coordinates, which a popup is allowed to
// be positioned by, and PopupAdjustment.All lets it flip and slide the
// card back on screen by itself.
//
// The surface is exactly the card — see the note on `pad` below for why it
// carries nothing around it.
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

PopupWindow {
  id: menuPop
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  readonly property alias menu: menu
  readonly property alias menuCard: menuCard
  readonly property alias subCard: subCard
  readonly property alias subPop: subPop
  visible: menu.shade > 0.01
  color: "transparent"

  // ── NO ROOM FOR A SHADOW, AND THE SHADOW IS GONE WITH IT ──────────
  // A shadow needs translucent pixels around the card, and on a popup
  // surface those cost twice over:
  //
  //   hyprland blurs them. decoration:blur:popups is on and
  //   popups_ignorealpha is 0.2, so the falloff sat above the threshold and
  //   the backdrop was blurred THROUGH the shadow — a pale halo where a
  //   dark one belonged. It was never a problem before because the menu was
  //   an item inside the window, and only became a surface of its own
  //   today.
  //
  //   and the compositor fits the SURFACE, not the card. 80px of padding
  //   on every side made the thing being placed 160px taller than the menu
  //   anyone can see, so a right click near the bottom of the window had
  //   the whole card shoved up the screen to make room for padding.
  //
  // So the surface is exactly the card. The card is opaque, carries its own
  // border and sits over a backdrop hyprland is already blurring, which is
  // the separation the shadow was drawn for.
  // ── ROOM FOR A SHADOW, AND ONLY AS MUCH AS IT NEEDS ───────────────
  // A surface is a hard edge, so a shadow has to be paid for in padding.
  // The catch is that the compositor fits the SURFACE, not the card, so
  // every pixel of padding is a pixel the card can be shoved by when it
  // opens near the edge of a screen.
  //
  // menuShadowPad is 80, which is right for a card inside a window and far
  // too much to pay here — it moved menus by 160px. This is a third of it:
  // a shadow you can see, and an error small enough that a menu still
  // arrives where the pointer is. MenuShadow.reach is set to match, so
  // nothing is drawn outside the room reserved for it.
  readonly property int pad: 36
  // ── THIS SURFACE NEVER CHANGES SIZE WHILE IT IS OPEN ──────────────
  // It used to grow to hold the submenu, and that fed back on itself: a
  // card opened near the right of the screen has no room for the extra
  // width, so the compositor slid the whole surface left to fit — which
  // dragged the card out from under the pointer, unhovered the row, closed
  // the submenu, shrank the surface and slid it back. Measured off a 60fps
  // capture: the submenu appeared for exactly one frame at a time, over and
  // over.
  //
  // The submenu has its own surface now, so this one is the card and
  // nothing else, and the card stays where it was put.
  implicitWidth: Math.ceil(2 * menuPop.pad + menuCard.width)
  implicitHeight: Math.ceil(2 * menuPop.pad + menuCard.height)

  anchor {
    window: term
    // the CARD lands on the pointer, so the surface starts a shadow
    // further up and to the left of it
    rect.x: Math.round(menu.mx) - menuPop.pad
    rect.y: Math.round(menu.my) - menuPop.pad
    // ── THE PADDING HAS TO BE PAID BACK ON A FLIP ─────────────────
    // A 1x1 rect here is a point, and a point has the same top and
    // bottom — so a flip put the SURFACE's bottom edge on it. The card
    // sits `pad` inside that edge, and the rect had already been moved
    // `pad` up to make room for the shadow, so a menu that opened
    // upwards came to rest 2 * pad above the pointer: measured off a
    // 60fps capture at 73px, the cursor tip at y=1050 and the card's
    // bottom border at y=976. Downwards it was exact, which is what
    // made it read as the bottom rows having menus of their own.
    //
    // A rect the size of the padding box instead. The compositor
    // anchors to its top-left going down and to its bottom-right
    // coming back, so the shadow's room is subtracted on the way out
    // and added again on the way back, and the card's leading edge
    // lands on the pointer whichever way it went.
    rect.width: 2 * menuPop.pad
    rect.height: 2 * menuPop.pad
    // Flip and slide, but never Resize: a menu that fits by having rows
    // cut off its bottom is not fitting.
    adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
  }

  Item {
    id: menu
    anchors.fill: parent
    z: 9
    // Kept alive through the fade OUT, which is the whole reason a menu
    // needs an opacity rather than just a visible: a card that vanishes on
    // the frame you click it never shows you which row you clicked.
    visible: menu.shade > 0.01
    opacity: menu.shade

    // 0 closed, 1 open. Everything about the card's arrival — its opacity,
    // its scale, the shade behind it — is a function of this one number, so
    // there is one animation to tune rather than four to keep in step.
    property real shade: 0
    Behavior on shade {
      NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
    }
    onOpenChanged: {
      menu.shade = menu.open ? 1 : 0;
      // whatever sidebar row asked for it stops being outlined
      if (!menu.open && term) term.sideMenuAt = null;
    }
    // Once the card is actually gone, and not before. Guarded on `open` as
    // well as on the shade so that a menu reopened mid-fade keeps the list
    // it was just given.
    onShadeChanged: if (!menu.open && menu.shade <= 0.01) {
      menu.customItems = null;
      menu.centered = false;
    }

    property bool open: false
    property real mx: 0
    property real my: 0

    // ONLY WHILE IT IS SHOWING. Bound to the cursor always, the closed menu
    // rebuilt its whole card for every row the cursor passed — `items`, then
    // the Repeater's rows with their key caps, hovers and animations — about
    // 140 items a step, nobody looking: 5.8 s of 6.9 s of a profiled minute of
    // arrowing through a directory (qmlprofiler, 2026-10-09). Opening sets
    // `open` before it reads anything, so the card is built once, for the
    // row it opens on, and follows the cursor while it is up or fading.
    readonly property var target: menu.open || menu.shade > 0.01 ? term.currentRow() : null
    readonly property bool isImage:
      !!menu.target && !menu.target.isDir && Terminus.isImage(menu.target.name)

    // on a row: everything applies to it
    function openAt(item, mouse) {
      const p = item.mapToItem(null, mouse.x, mouse.y);
      menu.mx = p.x;
      menu.my = p.y;
      menu.here = false;
      // Said outright rather than left to the last close(), which may still
      // be fading and no longer clears these on the way out.
      menu.customItems = null;
      menu.centered = false;
      menu.subAt = -1;
      menu.subSel = -1;
      term.sideMenuAt = null;
      menu.open = true;
      // after `open`, so `items` has been rebuilt for this target
      menu.at = menu.step(menu.items, -1, 1);
      // asked now rather than on every selection change: it is a process,
      // and almost every right-click is not about opening with something
      const t = menu.target;
      term.findApps(t && !t.isDir ? t.path : "");
    }

    // on empty space: only the things that are about the DIRECTORY, because
    // there is no row under the pointer to be about
    function openHere(item, mouse) {
      const p = item.mapToItem(null, mouse.x, mouse.y);
      menu.mx = p.x;
      menu.my = p.y;
      menu.here = true;
      // Said outright rather than left to the last close(), which may still
      // be fading and no longer clears these on the way out.
      menu.customItems = null;
      menu.centered = false;
      menu.subAt = -1;
      menu.subSel = -1;
      term.sideMenuAt = null;
      menu.open = true;
      menu.at = menu.step(menu.items, -1, 1);
    }

    property bool here: false

    // The sort options, as the submenu the `,` sequence already spells out.
    // One list feeding both would be ideal; these are three lines and the
    // sequence table's entries carry hint text this menu has no room for.
    // One row per format, described rather than just named: ".tar.zst" is
    // not self-explanatory to anyone who has not met zstd.
    readonly property var formatItems: {
      const out = [];
      for (const f of term.archiveFormats) {
        const ext = f[0];
        out.push({ label: ext, hint: f[1],
                   act: () => term.beginArchive(ext) });
      }
      return out;
    }

    // The formats worth turning a picture into: one lossless, one
    // small and universal, one small and modern. Not a list of
    // everything magick can write, which is hundreds.
    // the targets are terminus.js' — picasso's viewer offers the same
    readonly property var convertItems: Terminus.convertTargets().map((t) =>
      ({ label: t.ext, hint: t.hint, act: () => term.convertLook(t.ext) }))

    readonly property var viewItems: [
      { label: "List",    key: "V", act: () => term.setView("list") },
      { label: "Grid",    act: () => term.setView("grid") },
      { label: "Columns", act: () => term.setView("columns") }
    ]

    // ── THE WINDOW'S OWN MENU ─────────────────────────────────────
    // What the hamburger opens. It used to open the settings panel and
    // nothing else, which made it a second key for one sheet sitting in
    // the most reachable corner of the window.
    //
    // Deliberately NOT the empty-space menu: right-clicking the listing
    // already gives you that, and it is about the DIRECTORY — paste,
    // new file, bookmark this one, its properties. This is about the
    // WINDOW, and it is the only home for a set of things that until
    // now lived exclusively in the palette and in keys you had to know
    // already. Settings is still here; it is an item rather than the
    // whole menu.
    readonly property var windowItems: [
      { label: "View", sub: menu.viewItems },
      { label: "Sort by", key: ",", sub: menu.sortItems },
      { sep: true },
      // Hidden files only. Disk usage, git status and the group
      // headings are all in the Sort submenu already — they are ways
      // of READING the listing, which is what that menu is — and a
      // toggle you can reach from two rows of the same card is a
      // toggle that looks like two different settings.
      { label: term.showHidden ? "Hide hidden files" : "Hidden files",
        key: ".", act: () => { term.showHidden = !term.showHidden; } },
      { sep: true },
      { label: "New tab", key: "t", act: () => term.newTab() },
      { label: "Close tab", key: "ctrl c", act: () => term.closeTab() },
      { label: term.dual ? "Close second pane" : "Split view",
        key: "\\", act: () => term.toggleDual() },
      { label: term.sidebar ? "Hide sidebar" : "Sidebar",
        key: "|", act: () => { term.toggleSidebar(); } },
      { sep: true },
      { label: "Bookmarks", key: "g b", act: () => marks.ask() },
      { label: "Tags", key: "c t", act: () => tagPick.ask() },
      { label: "New collection", key: "c s", act: () => collEdit.ask(-1) },
      { label: "Reindex tags", act: () => term.rebuildTagIndex() },
      { sep: true },
      { label: "Settings", act: () => { prefs.open = true; } },
      { label: "Keys & commands", key: "F1", act: () => cmdPalette.ask() }
    ]

    readonly property var sortItems: [
      { label: "Name", act: () => term.setSort("name") },
      { label: "Size", act: () => term.setSort("size") },
      { label: "Modified", act: () => term.setSort("time") },
      { label: "Kind", act: () => term.setSort("kind") },
      // Same gate the sort ring in the settings panel uses: an order
      // that cannot tell any two rows apart is a row that does nothing.
      ...(term.anyTagged
          ? [{ label: "Tag", key: ", t", act: () => term.setSort("tag") }]
          : []),
      { sep: true },
      // Not an order — a way of reading whichever order is in force.
      // Under the rule rather than beside the columns for that reason.
      // Muted outside list view, as the settings panel's switch is: the
      // headings are a list-view thing (see root.grouped).
      { label: term.grouped ? "Hide group headings" : "Group headings",
        key: ", h", act: () => term.toggleGrouped(),
        off: term.viewMode !== "list" },
      { sep: true },
      // A mode rather than an order, which is why it says what it will do
      // rather than naming a column.
      { label: term.usage ? "Leave disk usage" : "Disk usage",
        key: ", u", act: () => term.toggleUsage() },
      { label: term.git ? "Leave git status" : "Git status",
        key: ", g", act: () => term.toggleGit() },
      { sep: true },
      { label: term.sortDesc ? "Ascending" : "Descending",
        act: () => term.sortDesc = !term.sortDesc }
    ]

    // Filled by the process findApps starts when the menu opens. Empty until
    // it answers, which is why it says so rather than showing nothing.
    // Only entries that can actually be launched. It used to fall back to a
    // "(no applications)" row, which is a submenu whose one item is an
    // apology — you opened a card, walked into a second card, and were told
    // there was nothing there. The parent row says it instead, by being dim.
    readonly property var appItems: {
      const t = menu.target;
      if (!t) return [];
      const apps = term.openWithApps;
      const out = [];
      for (let i = 0; i < apps.length; ++i) {
        // the ID, captured per iteration. Not the scanned file: that is the
        // first one found, which may be a stale user override — see
        // openWithCommand. An entry the scan could not locate at all still
        // has nothing to run.
        const id = apps[i].id;
        if (!id || !apps[i].file) continue;
        // the app's own glyph, from the map icarus and the launcher read
        out.push({ label: apps[i].name, glyph: Icons.appGlyph([id, apps[i].name]),
                   act: () => term.openWith(id, t.path) });
      }
      return out;
    }

    // The submenu itself: what already handles this file, and then a way out
    // of that list.
    //
    // A type CAN have a handler and still not have the one you want — a
    // .conf that opens in the wrong editor, an image that opens in a viewer
    // when you meant to edit it — and the picker was only reachable from a
    // file nothing claimed at all. So the same card hangs off the bottom of
    // the populated submenu, behind a rule: everything above it is one
    // click, this one opens something.
    readonly property var appMenu: {
      const t = menu.target;
      if (!t) return [];
      const out = menu.appItems.slice();
      if (out.length > 0) out.push({ sep: true });
      out.push({ label: "Choose Program",
                 act: () => term.beginOpenWith(t.path) });
      return out;
    }

    // which item's submenu is showing, or -1
    property int subAt: -1

    // ── as wide as its longest entry ────────────────────────────────
    // 240 was a guess, and the entries that outgrew it were elided — so the
    // menu hid the ends of exactly the labels that needed the room, and
    // "Paste as hard link" or a long "Open with" name became a shrug. The
    // card measures its own contents instead, with the same fonts the rows
    // draw with and the same paddings they are laid out by. Still bounded:
    // a menu the width of the window would be its own problem.
    FontMetrics {
      id: menuLabelFm
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(16)
    }
    FontMetrics {
      id: menuKeyFm
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }

    function rowWidth(it, labelFm, keyFm) {
      if (it.sep) return 0;
      // 12 in from the left, then the label, then the gap before the key —
      // the same 22 the row is laid out with, or the card measures itself
      // narrower than it draws and the labels elide again.
      let w = 12 + Math.ceil(labelFm.advanceWidth(String(it.label || ""))) + 22;
      // the chip's own text plus the padding KeyCap adds around it
      if (it.key) w += Math.ceil(keyFm.advanceWidth(String(it.key))) + 14;
      // the chevron needs more room on the right than a plain row does
      w += it.sub ? 26 : 12;
      // AND THE CROSS. A row that can be struck out carries a 14px ×,
      // 10 in from the edge, beside its chip — none of which was
      // measured, so exactly the rows with both ("mpv Media Player",
      // default, ×) came out short by the width of the cross and
      // elided.
      if (it.strike) w += 30;
      // AND A COUPLE OF PIXELS OF SLACK. advanceWidth is the sum of the
      // glyph advances; Text lays the same string out with shaping and its
      // own rounding and comes out a little wider, which is the difference
      // between a label that fits and "Propertie…".
      return w + 6;
    }

    readonly property real cardWidth: {
      let w = 0;
      for (const it of menu.items)
        w = Math.max(w, menu.rowWidth(it, menuLabelFm, menuKeyFm));
      return Math.round(Math.max(200, Math.min(460, w)));
    }

    // ── the keyboard's place in the card ────────────────────────────
    // The menu was mouse-only: every key but Escape was dropped while it was
    // up, so the Menu key could open a card you then had to reach for the
    // mouse to use. `at` is the cursor in the parent card and `subSel` the
    // one in the submenu, with -1 meaning "the keyboard is not in there".
    property int at: -1
    property int subSel: -1

    // The next selectable row in a direction, wrapping, skipping separators
    // — a separator is a line, not a place you can be. Returns -1 for a list
    // with nothing selectable in it at all.
    function step(list, from, dir) {
      const n = list ? list.length : 0;
      if (n === 0) return -1;
      let i = from;
      for (let k = 0; k < n; ++k) {
        i = (i + dir + n) % n;
        // The swatch strip is skipped for the same reason a separator
        // is: there is no single thing on it to land on. c t opens the
        // full picker, which is the keyboard's way in.
        // and an entry marked `off` (muted where it means nothing, as
        // group headings outside list view) for the same reason again
        if (!list[i].sep && !list[i].swatch && !list[i].off) return i;
      }
      return -1;
    }

    // ── THE SUBMENU'S STATE LIVES OUT HERE, NOT ON THE CARD ──────────
    // subPop's visibility and size cannot be read off subCard, because
    // subCard IS subPop's content: a window that is not visible has not
    // built its contentItem, so subCard does not exist to be asked, and the
    // popup could never become visible in the first place. It opened
    // exactly never.
    //
    // So everything the surface needs to know is computed here, from the
    // items alone, and is true whether or not anything has been built yet.
    readonly property bool subWanted:
      menu.subAt >= 0 && menu.subItems.length > 0
    property real subShade: 0
    onSubWantedChanged: menu.subShade = menu.subWanted ? 1 : 0
    Behavior on subShade {
      NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
    }

    // A submenu of applications (Open with) wears a glyph column. Kept for
    // a row the map does not know, as icarus' app list keeps it, so the
    // names stay in one line down the card.
    readonly property bool subGlyphs: {
      for (const it of menu.subItems) if (it.glyph !== undefined) return true;
      return false;
    }
    readonly property real subGlyphW: menu.subGlyphs ? 16 + Zenon.menuIconGap : 0

    // the widest row it holds, plus the description column those rows carry
    readonly property real subCardW: {
      let w = 0;
      for (const it of menu.subItems) {
        let x = menu.rowWidth(it, menuLabelFm, menuKeyFm) + menu.subGlyphW;
        if (it.hint) x += 16 + menuKeyFm.advanceWidth(String(it.hint));
        w = Math.max(w, x);
      }
      return Math.round(Math.max(200, Math.min(460, w)));
    }

    // what subCol will come to: its rows, and the padding it puts above and
    // below them
    readonly property real subCardH: {
      let h = 2 * Zenon.menuCardPad;
      for (const it of menu.subItems)
        h += it.sep ? Zenon.menuSepHeight : Zenon.menuRowHeight;
      return h;
    }

    // how far down the parent card the row it hangs off sits
    // ── WHERE THE SUBMENU HANGS, HELD THROUGH ITS FADE ───────────
    // Closing sets subAt to -1 at once, and the row and the rows under
    // it were both read from subAt — so a submenu still fading out
    // jumped to the top of the card and emptied to a line on its way
    // out. subShown follows subAt to every row it opens on and keeps
    // the last one until the fade is over.
    property int subShown: -1
    onSubAtChanged: if (menu.subAt >= 0) menu.subShown = menu.subAt
    onSubShadeChanged: if (menu.subShade <= 0.01 && menu.subAt < 0) menu.subShown = -1

    readonly property real subRowTop: {
      let y = Zenon.menuCardPad;
      for (let i = 0; i < menu.subShown && i < menu.items.length; ++i)
        y += menu.items[i].sep ? Zenon.menuSepHeight : Zenon.menuRowHeight;
      return y;
    }

    readonly property var subItems: {
      if (menu.subShown < 0) return [];
      const it = menu.items[menu.subShown];
      return (it && it.sub) ? it.sub : [];
    }

    // THE ACTION IS READ BEFORE THE MENU CLOSES, for the reason spelled out
    // on the rows themselves: close() empties the Repeater's model, an
    // emptied Repeater destroys its delegates, and modelData goes with them.
    function run(act) {
      menu.close();
      if (act) act();
    }

    function activateAt() {
      const it = menu.items[menu.at];
      if (!it || it.sep || it.off) return;
      // a parent row opens its children rather than doing anything
      if (it.sub) { menu.subAt = menu.at; menu.subSel = menu.step(it.sub, -1, 1); return; }
      menu.run(it.act);
    }

    function activateSub() {
      const it = menu.subItems[menu.subSel];
      if (!it || it.sep || it.off) return;
      menu.run(it.act);
    }

    // Down and up, in whichever card the keyboard is actually in.
    function move(dir) {
      if (menu.subSel >= 0) menu.subSel = menu.step(menu.subItems, menu.subSel, dir);
      else menu.at = menu.step(menu.items, menu.at, dir);
    }

    function close() {
      menu.open = false;
      // customItems is NOT cleared here, and that is the whole fix for the
      // flash: the card is deliberately kept alive through its fade out, so
      // clearing the handed-in list on the closing frame let `items` fall
      // back to the row menu — and the last thing you saw of the drop menu
      // was the full context menu wearing its shape for 150ms. It is
      // cleared when the fade has finished instead, below.
      menu.subAt = -1;
      menu.at = -1;
      menu.subSel = -1;
      // Whatever opened it, it is shut — see the hamburger.
      term.burgerOn = false;
      term.contentRef.forceActiveFocus();
    }

    // anything that misses the card puts it away
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onClicked: menu.close()
    }

    // ── a list handed in from outside ───────────────────────────────
    // For the questions that are about a PLACE rather than about a row:
    // what to do with something just dropped. Answering those in a dialog
    // put the choice in the middle of the screen, a long way from the
    // pointer that had just arrived somewhere specific — so the menu takes
    // an explicit list and opens where the drop happened.
    property var customItems: null
    // Centred entries, for the handed-in menus only. A row menu is a column
    // of verbs you read down the left edge, and it has keys along the right
    // to line up against; the drop menu is three short answers to one
    // question with nothing in the right-hand column, and left-aligning
    // those leaves them hanging off the side of a card sized for them.
    property bool centered: false

    // `center` is optional and defaults to the drop menu's behaviour, which
    // is what every earlier caller wanted. A list with a submenu in it
    // wants the other one: centred labels leave the parent row's arrow
    // floating away from the text it belongs to.
    // `right` hangs the card's RIGHT edge on the point instead of its
    // left. A menu dropped from a button in the corner of the window
    // has nowhere to go: opening rightward, it reaches past the window
    // onto the desktop, and the compositor is happy to leave it there
    // because a popup surface is not clipped by its parent. Nothing is
    // lost, and it still reads as a card that missed.
    //
    // cardWidth is asked for AFTER customItems is set, because it is
    // measured off menu.items and items is customItems once there is
    // one — read a moment earlier and it sizes the menu that is not
    // being opened.
    function openCustom(item, mouse, list, center, right) {
      const p = item.mapToItem(null, mouse.x, mouse.y);
      // a menu of someone else's replaces the disk's; diskMenu sets it after
      term.sideMenuAt = null;
      menu.here = false;
      menu.subAt = -1;
      menu.subSel = -1;
      menu.customItems = list;
      menu.mx = right === true ? p.x - menu.cardWidth : p.x;
      menu.my = p.y;
      menu.centered = center === undefined ? true : !!center;
      menu.open = true;
      menu.at = menu.step(menu.items, -1, 1);
    }

    readonly property var items: {
      if (menu.customItems) return menu.customItems;
      if (menu.here) {
        const out = [];
        // Always offered: `p` pastes what was copied last ANYWHERE, and
        // whether the clipboard holds files is only known by asking it.
        // The links are made from Terminus's own list, so they need one.
        out.push({ label: "Paste here", key: "p", act: () => term.paste() });
        if (term.pending) {
          out.push({ label: "Paste as symlink", act: () => term.pasteLink(true) });
          out.push({ label: "Paste as hard link", act: () => term.pasteLink(false) });
        }
        out.push({ sep: true });
        out.push({ label: "New directory", key: "a /", act: () => term.beginMkdir() });
        out.push({ label: "New file", key: "a", act: () => term.beginCreate() });
        out.push({ sep: true });
        out.push({ label: "Sort by", key: ",", sub: menu.sortItems });
        if (term.undoStack.length > 0)
          out.push({ label: term.undoLabel, key: "u", act: () => term.undo() });
        out.push({ sep: true });
        out.push({ label: term.isBookmarked(term.cwd)
            ? "Remove bookmark" : "Bookmark this directory",
          key: "b a",
          act: () => term.toggleBookmark() });
        if (term.inTrash)
          out.push({ label: "Empty the trash", danger: true,
                     act: () => term.emptyTrash() });
        out.push({ label: "Open shell here", key: ";", act: () => term.openShell() });
        out.push({ label: term.dual ? "Close second pane" : "Second pane",
                   key: "\\", act: () => term.toggleDual() });
        out.push({ label: term.sidebar ? "Hide sidebar" : "Sidebar",
                   key: "|", act: () => { term.toggleSidebar(); } });
        // Braced. Both of these are about the SECOND PANE and both were
        // meant to be behind `root.dual` — but only the first was, so a
        // one-pane window offered to swap sides with a pane that was not
        // there. The indentation had said what was intended all along.
        if (term.dual) {
          out.push({ label: "Step into other pane", key: "tab", act: () => term.stepOver() });
          out.push({ label: "Swap sides", act: () => term.swapSides() });
        }
        out.push({ label: "Select all", key: "ctrl a", act: () => term.selectAll() });
        out.push({ sep: true });
        // THIS directory, not whatever the cursor is resting on. Last, where
        // every other file manager puts it.
        out.push({ label: "Properties",
                   act: () => term.propsRef.askPath(term.cwd) });
        return out;
      }
      const t = menu.target;
      if (!t) return [];
      // the cheap counter, so labels stay right without depending on the
      // whole selection array
      const n = term.markedCount > 0 ? term.markedCount : 1;
      const many = n > 1 ? " (" + n + ")" : "";
      const out = [
        { label: t.isDir ? "Open directory" : "Open", key: "return", act: () => term.activate() }
      ];
      // Directly under Open, because it is the other way to open this — and
      // only for a directory, which is the only thing with a listing to give
      // a tab. The same gesture is on the middle mouse button.
      if (t.isDir)
        out.push({ label: "Open in new tab", key: "shift return",
                   act: () => term.openInNewTab(t.path) });
      // The third way into a directory, and the one that does not leave
      // where you are. Only in the list: see pane.tree for why the
      // other views have no branches.
      if (t.isDir && term.viewMode === "list" && term.searchMode === "")
        out.push({ label: term.act.isOpen(t.path)
                     ? "Collapse" : "Expand in place",
                   key: term.act.isOpen(t.path) ? "h" : "l",
                   act: () => term.act.toggleOpen(t.path) });
      // ── AND THE WAY OUT OF A LIST THAT IS NOT A DIRECTORY ───────
      // Under the ways to open it, which is where Finder puts its own.
      // Only when it would go somewhere: on a plain listing every row
      // already lives in the directory you are standing in, and an
      // entry that cannot move is an entry to read past. A results
      // page always qualifies, and so does a row inside an expanded
      // branch — the tree shows you a file three levels down without
      // ever having gone there.
      if (term.searchMode !== ""
          || Terminus.dirname(t.path) !== term.cwd)
        out.push({ label: "Go to containing directory", key: "g r",
                   act: () => term.reveal() });
      // Opening is one kind of thing and moving is another; the rule below
      // holds them apart. Cut first: the pair is ordered by how much of a
      // commitment it is, and the one that takes the file away is the one
      // you want to have to read past to reach.
      out.push({ sep: true });
      out.push(
        { label: "Cut" + many, key: "x x", act: () => term.yank("move") },
        { label: "Copy" + many, key: "y y", act: () => term.yank("copy") },
        // The path is another thing you can take from the row, so it belongs
        // with the two above rather than down among the dialogs.
        { label: "Copy path", key: "c c", act: () => term.copyPath() });
      // The other half of cut-and-paste, for when you know where it is
      // going and do not want to go there first — see sendTo.
      out.push(
        { label: "Copy to" + many + "…", key: "y t",
          act: () => sendTo.ask("copy") },
        { label: "Move to" + many + "…", key: "x t",
          act: () => sendTo.ask("move") },
        { label: "Duplicate" + many, key: "y d",
          act: () => term.duplicate() },
        // Among the verbs that make a new thing out of the selection
        // rather than among the ones that move it: nothing leaves this
        // directory, it just gains a level.
        { label: "New directory with selection" + many, key: "c g",
          act: () => term.gatherIntoFolder() },
        { label: "Make symlink" + many, key: "y l",
          act: () => term.linkHere() });
      out.push({ sep: true });
      // always — see the empty-space menu
      out.push({ label: "Paste here", key: "p", act: () => term.paste() });
      if (term.pending) {
        out.push({ label: "Paste as symlink", act: () => term.pasteLink(true) });
        out.push({ label: "Paste as hard link", act: () => term.pasteLink(false) });
      }
      // Closing the block rather than opening one: the paste entries are
      // about what is on the clipboard, everything under them is about the
      // row, and with nothing between them the menu grew by three rows in
      // the middle and read as one long list of unrelated verbs.
      out.push({ sep: true });
      // Only where it can do something: an Extract on a text file and a
      // Restore outside the trash are entries that exist to be greyed out.
      if (t.isDir)
        out.push({ label: "Calculate size" + many, key: "z",
                   act: () => term.measureDirs() });
      if (term.dual && term.otherCwd !== "" && term.otherCwd !== term.cwd) {
        out.push({ label: "Copy to other pane" + many, key: "f5",
                   act: () => term.sendToOther("copy") });
        out.push({ label: "Move to other pane" + many, key: "f6",
                   act: () => term.sendToOther("move") });
      }
      if (!t.isDir && Terminus.isVideo(t.name))
        out.push({ label: "Extract audio" + many, key: "e",
                   act: () => term.extractAudio() });
      if (Terminus.isArchive(t.name) && !t.isDir)
        out.push({ label: "Extract here" + many, key: "c x",
                   act: () => term.extractSelected() });
      // into ~/.local/share/fonts, through alexandria — see installFonts
      if (!t.isDir && Terminus.isFont(t.name))
        out.push({ label: "Install font" + many,
                   act: () => term.installFonts() });
      out.push({ label: "Archive" + many, key: "c a", sub: menu.formatItems });
      if (term.inTrash) {
        out.push({ label: "Restore" + many, act: () => term.restoreSelected() });
        out.push({ label: "Empty the trash", danger: true,
                   act: () => term.emptyTrash() });
      }
      if (!t.isDir) {
        // A submenu when something already handles this type, and a CARD
        // when nothing does.
        //
        // The old fallback was a submenu holding one row that said "(no
        // applications)" — you opened a card, walked right into a second
        // card, and were told there was nothing in it. Worse, it was a dead
        // end: the answer to "nothing opens this" is to pick something, and
        // the menu had nowhere to do that from.
        //
        // So the entry becomes an action instead, and the card it opens
        // lists everything installed. What you choose is REGISTERED for the
        // type on its way to running it, which is what turns this row back
        // into a submenu the next time you open it — see adoptAppCommand.
        // The same card is reachable from the bottom of the populated
        // submenu, because "it has a handler" and "it has the one you want"
        // are not the same claim — see appMenu.
        //
        // Only once the scan has actually answered. While it is still out
        // there is no news yet, and flipping the row from one shape to the
        // other under the pointer would be inventing some.
        if (menu.appItems.length === 0 && term.appsScanned)
          out.push({ label: "Open with", key: "shift return",
                     act: () => term.beginOpenWith(t.path) });
        else
          out.push({ label: "Open with", key: "shift return",
                     sub: menu.appMenu });
      }
      // Beside the two verbs that open things, because it is the one that
      // opens nothing — see root.quickLook.
      //
      // OUTSIDE the !isDir block, which is where it used to sit. It was
      // grouped with "Open with" because both are about opening a file,
      // but a directory has a quick look too — it lists what is inside,
      // and says "Empty" when there is nothing — so the one view that
      // works on everything was the one verb the menu only offered on
      // half of it. The key was bound for directories the whole time,
      // which made the omission a menu that disagreed with the keyboard.
      out.push({ label: "Quick look", key: "space",
                 act: () => term.quickLook() });
      out.push({ label: "Sort by", key: ",", sub: menu.sortItems });
      // Renaming sits under the sort, not up among cut and copy: those act
      // on the row and hand you straight back to it, and this one opens a
      // field and waits. It is the first of the verbs that ask a question.
      // Whichever one the selection means, and only that one. Offering both
      // asked you to choose between renaming the row under the cursor and
      // renaming the nine you had ticked — which is not a choice anybody
      // wants to make on a menu, and the first answer is almost never it.
      // JUST "Rename", with the count saying how many. "Bulk rename (9)"
      // named a mechanism; the row above it already says Rename for one,
      // and the only thing that changes with nine is the number.
      if (n > 1)
        out.push({ label: "Rename" + many, key: "r",
                   act: () => term.beginBulkRename() });
      else
        out.push({ label: "Rename", key: "r", act: () => term.beginRename() });
      if (t.isDir)
        out.push({ label: term.isBookmarked(t.path)
            ? "Remove bookmark" : "Bookmark",
          key: "b b",
          act: () => term.toggleBookmarkFor(t.path) });
      // The two that open a card of their own, together at the bottom behind
      // a rule — everything above acts on the row and returns you to it.
      out.push({ sep: true });
      // ── THE TAGS THEMSELVES, NOT A DOOR TO THEM ──────────────
      // A row saying "Tags" that opens a card is two gestures for the
      // commonest one there is. Finder puts the colours in the menu
      // and so does this: one click, one tag, menu closed.
      //
      // The seven that come with a colour only — an arbitrary tag has
      // no swatch to show and the picker is where those live, which
      // the row underneath still reaches.
      out.push({ swatch: true });
      out.push({ label: "Manage tags" + many, key: "c t",
                 act: () => tagPick.ask() });
      // No Permissions row. It is a tab inside Properties now, and two
      // menu entries opening the same card one tab apart is the menu
      // being longer to say the same thing. c m still goes straight to
      // that tab for anyone who reaches for it.
      out.push({ label: "Properties", key: "alt return", act: () => term.propsRef.ask() });
      if (menu.isImage) {
        out.push({ sep: true });
        // ── THE QUICK ACTIONS ────────────────────────────────
        // The same three the viewer offers, for when you already
        // know which file needs turning and do not need to look at
        // it first. Rotation writes over the original — see
        // rotateCommand — so it is worded as the correction it is
        // rather than as "make a rotated copy".
        // Picasso's annotation window, on this picture — the same one a
        // screenshot's toast opens.
        out.push({ label: "Annotate",
                   act: () => { const r = term.currentRow();
                                if (r && !r.isDir) Picasso.annotate(r.path); } });
        out.push({ label: "Rotate left",  key: "[",
                   act: () => term.rotateLook(-90) });
        out.push({ label: "Rotate right", key: "]",
                   act: () => term.rotateLook(90) });
        out.push({ label: "Convert to" + many, sub: menu.convertItems });
        out.push({ sep: true });
        out.push({ label: "Set as background",
                   act: () => term.setWallpaper(null) });
        const screens = Quickshell.screens;
        if (screens.length > 1) {
          for (let i = 0; i < screens.length; ++i) {
            const nm = screens[i].name;
            out.push({ label: "Background on " + nm,
                       act: () => term.setWallpaper(nm) });
          }
        }
      }
      out.push({ sep: true });
      out.push({ label: "Trash" + many, key: "d", danger: true, act: () => term.trash() });
      return out;
    }

    // icarus' shadow, worn here. The menu this window opens and the menu
    // the desktop opens are the same gesture, and the one that cast a
    // different shadow read as a different piece of software.
    //
    // It rides the card's own arrival — same scale, same origin — so it
    // grows out of the pointer with it rather than sitting at full size
    // under a card that is still unfolding.
    // Back, now that the surface leaves room — see menuPop.pad. Same
    // component icarus and the tray wear, so the three menus on this
    // desktop cast one shadow rather than three opinions about one.
    MenuShadow {
      panel: menuCard
      // ── THE FALLOFF HAS TO FIT THE ROOM, or it is not a falloff ─────
      // The defaults are sized for menuShadowPad: 20 spread + 50 blur +
      // 10 offset, 80 in total. Given 36px of surface to live in, the
      // gradient was simply cut off partway down — a hard-edged dark
      // rectangle around the card rather than a shadow fading out.
      //
      // Scaled to the padding instead, so the three add up to exactly the
      // room available and the last of the blur lands on the last pixel
      // of it. Change `pad` and the shadow follows.
      reach: menuPop.pad
      grow: Math.round(menuPop.pad * 0.20)
      softness: Math.round(menuPop.pad * 0.62)
      drop: Math.round(menuPop.pad * 0.18)
      cornerRadius: Zenon.menuRadius
      transformOrigin: Item.TopLeft
      scale: menuCard.scale
    }

    ClippingRectangle {
      id: menuCard
      // Grows out of the pointer rather than appearing at full size. The
      // origin is the corner the pointer is at, so the card unfolds FROM the
      // click instead of expanding around its own middle.
      transformOrigin: Item.TopLeft
      scale: Zenon.menuScale(menu.shade)

      // kept inside the window: a menu opened near the right edge that
      // hangs off it is a menu with items you cannot reach
      // Rounded. The position comes from a pointer, which lands on
      // fractions of a pixel, and an item on a half pixel renders its text
      // through a filter — which is what "blurry" was.
      // THE POINTER NO LONGER COMES INTO THIS. The card is pinned at the
      // shadow's inset inside its own surface, and that surface is placed at
      // the pointer by the compositor — which is also the only thing that
      // knows where the screen ends. Clamping here as well would be a second
      // opinion about a question already answered, in the wrong coordinates.
      x: menuPop.pad
      y: menuPop.pad
      width: menu.cardWidth
      // EXACTLY the column, which already carries 4px of padding at each
      // end. The extra 8 here was a second bottom padding — the column sits
      // at the card's top, so every pixel of it landed underneath the last
      // row and nowhere else.
      height: menuCol.implicitHeight
      // FROSTED, like quick look. It was solid because it was an item
      // inside the window, over terminus' own rows, which nothing can
      // blur. It is its own popup surface now (menuPop), and hyprland
      // blurs popups — so the reason for solid went with the move.
      color: Zenon.frostBg
      border.color: Zenon.border
      border.width: 1
      // ROUND ON EVERY CORNER. The two cards used to square off the edge
      // where they met, because they met — they were one surface with a
      // rule down it. They are two surfaces since the submenu got its own,
      // each casting its own shadow into the gap, and a squared edge with a
      // shadow beside it reads as a card with a corner missing.
      radius: Zenon.menuRadius

      Column {
        id: menuCol
        width: parent.width
        topPadding: Zenon.menuCardPad
        bottomPadding: Zenon.menuCardPad

        Repeater {
          model: menu.items

          delegate: Item {
            id: menuRow
            required property var modelData
            width: menuCol.width
            height: modelData.sep ? Zenon.menuSepHeight
              : (modelData.swatch ? Math.round(Zenon.menuRowHeight * 1.15)
                                  : Zenon.menuRowHeight)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: parent.right
              // edge to edge, as every menu's separator — see CardMenu
              height: 1
              visible: !!modelData.sep
              color: Zenon.border
            }

            required property int index

            // ── THE SEVEN, IN A LINE ──────────────────────────────
            // Each toggles across the whole selection by the same rule
            // every other verb here follows — see Tags.toggleAcross for
            // why a mixed selection fills in rather than flipping.
            //
            // The ring is the state: a tag already on everything
            // selected wears one, and clicking it takes it off. It is
            // the only way to show a toggle on a thing whose whole job
            // is to be a colour, and it is what Finder does.
            Row {
              // Above the row's own MouseArea, which fills the whole row
              // and is declared after this — the same reason menuX
              // carries a z. Disabling that one over a swatch row is
              // what actually frees the clicks; this makes the stacking
              // say so too rather than depending on it.
              z: 2
              anchors.centerIn: parent
              visible: !!modelData.swatch
              spacing: Math.round(Zenon.menuRowHeight * 0.30)

              Repeater {
                model: !!menuRow.modelData.swatch ? Tags.PRESETS : []

                delegate: Item {
                  id: swatch
                  required property var modelData
                  readonly property real d:
                    Math.round(Zenon.menuRowHeight * 0.82)
                  width: swatch.d
                  height: swatch.d

                  // Whether EVERY selected row already carries it, which
                  // is what decides which way a click goes.
                  readonly property bool on: {
                    const rows = term.acting();
                    if (rows.length === 0) return false;
                    for (let i = 0; i < rows.length; ++i)
                      if (!Tags.hasTag(term.tagMarks[rows[i].path],
                                       swatch.modelData.name)) return false;
                    return true;
                  }

                  Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: swatchHov.hovered
                      ? Zenon.wash(0.10) : "transparent"
                    // the chosen tag's ring, in its own colour — a
                    // special case of the one-border rule, see Zenon.border
                    border.width: swatch.on ? 2 : 0
                    border.color: Zenon[swatch.modelData.ink] || Zenon.cyan
                  }

                  Text {
                    anchors.centerIn: parent
                    text: "\uF02B"
                    color: Zenon[swatch.modelData.ink] || Zenon.cyan
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Math.round(Zenon.menuRowHeight * 0.50)
                  }

                  HoverHandler { id: swatchHov }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: {
                      term.toggleTagHere(swatch.modelData.name);
                      menu.open = false;
                    }
                  }
                }
              }
            }

            Rectangle {
              anchors.fill: parent
              visible: !modelData.sep && !modelData.swatch
              // icarus' menu highlight, worn here too — the two are the same
              // gesture on the same desktop, and a context menu that lit its
              // rows a different colour from the desktop menu read as a
              // different piece of software.
              // The keyboard's row counts as highlighted only while the
              // keyboard is in THIS card — with a submenu open the cursor
              // has moved into it and the parent row keeps its subAt tint
              color: itemHov.hovered || menu.subAt === index
                     || (menu.subSel < 0 && menu.at === index)
                ? Zenon.border : "transparent"
            }
            HoverHandler {
              id: itemHov
              enabled: !modelData.sep && !modelData.swatch
              // Hovering a row with children opens them and hovering one
              // without closes whatever was open — so moving down the card
              // never leaves an orphaned second card beside an unrelated row.
              onHoveredChanged: if (hovered) {
                menu.subAt = modelData.sub ? index : -1;
                // so a keystroke after a hover carries on from the row under
                // the pointer rather than from wherever the keyboard was
                menu.at = index;
                menu.subSel = -1;
              }
            }

            // BOUNDED ON THE RIGHT by whatever is over there, which is what
            // it was missing: a left-anchored Text with no right edge is as
            // wide as its string, so "Open in new tab" simply drew straight
            // through the "middle click" beside it and the two were printed
            // on top of each other. Now it stops short and elides.
            Text {
              id: menuLabel
              anchors.left: parent.left
              anchors.leftMargin: 12
              anchors.right: menuKey.visible ? menuKey.left
                           : (menuChev.visible ? menuChev.left
                             : (menuX.visible ? menuX.left : parent.right))
              // The label and its key are two different statements — what
              // this does, and what performs it — and at 10px they read as
              // one run of text with a box at the end of it. Centred, the
              // gap has to match the left inset or the middle is not the
              // middle.
              anchors.rightMargin: menu.centered ? 12 : 22
              horizontalAlignment: menu.centered ? Text.AlignHCenter
                                                 : Text.AlignLeft
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              visible: !modelData.sep && !modelData.swatch
              text: modelData.label || ""
              color: modelData.danger ? Zenon.red : Zenon.white
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(16)
            }

            // The key that does the same thing, so the menu teaches the
            // keyboard rather than competing with it. A footnote to the
            // entry, not a second label — but it was drawn in msgBorder,
            // which is a BORDER colour carrying 30% alpha, so it came out
            // barely there. keyInk is the palette's name for exactly this:
            // dimmer than the label, still meant to be read.
            KeyCap {
              id: menuKey
              anchors.right: menuChev.visible ? menuChev.left
                           : (menuX.visible ? menuX.left : parent.right)
              anchors.rightMargin: modelData.sub ? 8 : 12
              anchors.verticalCenter: parent.verticalCenter
              visible: !modelData.sep && !modelData.swatch && !!modelData.key
              label: modelData.key || ""
            }

            // ── A ROW THAT CAN BE TAKEN AWAY SAYS SO ON ITSELF ────
            // An entry carrying `strike` gets a cross at its right edge
            // that removes the thing the row names, while the row itself
            // still does what it says. It replaced a "Remove" submenu: one
            // list of handlers where you either choose one or cross one
            // out is a smaller idea than two lists of the same names that
            // do different things depending on which you walked into.
            //
            // Above the row's own MouseArea — that one fills the whole row
            // and is declared after this, so without a z it would take
            // every click including the ones aimed here.
            Text {
              id: menuX
              z: 2
              anchors.right: parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              visible: !modelData.sep && !modelData.swatch && !!modelData.strike
              text: "\uf00d"   // nf-fa-times
              color: strikeHov.hovered ? Zenon.red : Zenon.muted
              font.family: Zenon.faceMono
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)

              HoverHandler { id: strikeHov }
              MouseArea {
                anchors.fill: parent
                // a target you can hit without aiming — the glyph is 14px
                anchors.margins: -7
                enabled: !chosenAnim.running
                onClicked: {
                  menuRow.pending = modelData.strike;
                  chosenAnim.restart();
                }
              }
            }

            // the chevron that says there is more to the right
            Text {
              id: menuChev
              anchors.right: menuX.visible ? menuX.left : parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              visible: !!modelData.sub
              text: "\uf105"   // nf-fa-angle_right
              // See CardMenu's tail: a chevron is punctuation on the
              // label, not a dimmed thing of its own.
              color: Zenon.white
              font.family: Zenon.faceMono
              font.weight: Zenon.weight
              // matching menuLabel, which is 16
              font.pixelSize: Zenon.px(16)
            }

            // The row FLASHES, then the card closes, then the thing happens.
            //
            // A menu that disappears on mouse-down leaves you unsure which
            // row you hit — and for the destructive entries that is a bad
            // moment to be unsure in. The delay is long enough to see and
            // short enough that it is not a wait.
            property real chosen: 0
            SequentialAnimation {
              id: chosenAnim
              NumberAnimation { target: menuRow; property: "chosen"; to: 1;
                                duration: 60; easing.type: Easing.OutQuad }
              NumberAnimation { target: menuRow; property: "chosen"; to: 0;
                                duration: 130; easing.type: Easing.InQuad }
              ScriptAction {
                script: {
                  const act = menuRow.pending;
                  menuRow.pending = null;
                  menu.close();
                  if (act) act();
                }
              }
            }
            property var pending: null

            Rectangle {
              anchors.fill: parent
              visible: menuRow.chosen > 0
              color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b,
                             0.55 * menuRow.chosen)
            }

            MouseArea {
              anchors.fill: parent
              // AND NOT OVER THE SWATCH STRIP. This one fills the whole
              // row and is declared after it, so it was taking every
              // click meant for a colour — the strip drew correctly and
              // could not be used.
              enabled: !modelData.sep && !modelData.swatch
                       && !chosenAnim.running
            // No hand cursor. This is a file manager, not a page of links:
            // a row you can click is the normal state of everything here, so
            // pointing at one is not news and the pointer should not change
            // to say so.
              onClicked: {
                // a parent row opens its children rather than doing anything
                if (modelData.sub) { menu.subAt = index; return; }
                menuRow.pending = modelData.act;
                chosenAnim.restart();
              }
            }
          }
        }
      }
    }

    // ── the submenu ───────────────────────────────────────────────
    // A second card beside the first, for the entries that are a CHOICE
    // rather than an action — how to sort, which application to open with.
    // Those would each be four or five more rows on a menu that is already
    // long, and they are all answers to one question, which is what a
    // submenu is for.
    //
    // Its y is computed from the rows above it rather than measured off the
    // delegate: the rows are a fixed 30 and separators 7, so the arithmetic
    // is exact and nothing has to be mapped between items.
  // ── AND THE SUBMENU GETS ITS OWN ───────────────────────────────────
  // A popup may parent a popup, which is how real menus are built and the
  // reason they do not have the bug this one had: the parent card is a
  // fixed surface, and only THIS one is moved around by the compositor to
  // stay on screen. Nothing the submenu does can shift the card under the
  // pointer any more.
  //
  // Anchored to the card's right edge at the parent row, growing right and
  // down. The rect is the card's full width rather than a point so that
  // FlipX mirrors the submenu to the card's LEFT when there is no room —
  // from a point it would mirror about the right edge and land on top of
  // the card it belongs to.
  PopupWindow {
    id: subPop
    visible: menu.subWanted || menu.subShade > 0.01
    color: "transparent"
    readonly property int pad: menuPop.pad
    implicitWidth: Math.ceil(menu.subCardW + 2 * subPop.pad)
    implicitHeight: Math.ceil(menu.subCardH + 2 * subPop.pad)
    anchor {
      window: menuPop
      // Both shifted back by this surface's own inset, so the CARD lands
      // flush against the parent card rather than a shadow's width away
      // from it — the anchor places the surface, and the card sits `pad`
      // inside it.
      rect.x: menuCard.x - subPop.pad
      rect.y: menuCard.y + menu.subRowTop - subPop.pad
      rect.width: menuCard.width
      rect.height: 1
      edges: Edges.Right | Edges.Top
      gravity: Edges.Right | Edges.Bottom
      adjustment: PopupAdjustment.FlipX | PopupAdjustment.SlideY
    }

      MenuShadow {
        panel: subCard
        // the same proportions as the parent card's — see the note there
        reach: subPop.pad
        grow: Math.round(subPop.pad * 0.20)
        softness: Math.round(subPop.pad * 0.62)
        drop: Math.round(subPop.pad * 0.18)
        cornerRadius: Zenon.menuRadius
        visible: subCard.visible
        opacity: subCard.shade
        transformOrigin: Item.TopLeft
        scale: subCard.scale
      }

      ClippingRectangle {
        id: subCard
        // The same arrival the card it hangs off has, and every other menu on
        // this desktop. It used to simply appear, which next to a parent that
        // unfolds read as two different pieces of software.
        // See menu.subWanted — the state is out there now, and this card
        // wears it. It fills its surface, so it has no visibility of its
        // own to work out; the surface is mapped only while it is wanted.
        readonly property bool wanted: menu.subWanted
        readonly property real shade: menu.subShade
        transformOrigin: Item.TopLeft
        scale: Zenon.menuScale(subCard.shade)
        opacity: subCard.shade

        readonly property var items: menu.subItems

        readonly property real rowTop: menu.subRowTop

        // Both measured on menu, so the surface can size itself before this
        // card exists — see the note there.
        width: menu.subCardW
        height: menu.subCardH
        // Flipped to the left of the parent card when there is no room on the
        // right, for the same reason the parent card is clamped to the window.
        // Asked ONCE, as a property, because the corners below have to agree
        // with the placement — a card that squares the wrong edge is worse
        // than one that squares neither.
        // ALWAYS the right, now that the surface grows to hold it: the old
        // test asked whether the card plus the submenu still fit inside the
        // WINDOW, and the window has stopped being the boundary. The surface
        // is made wide enough for both, and if that puts it off the edge of
        // the screen the compositor slides the whole thing back — one answer,
        // from the only party that can see the screen.
        readonly property bool onRight: true

        // Flush against the parent, with the gap taken out. The two cards are
        // one surface with a rule down it, the way icarus' menus read, and two
        // pixels of window showing between them is what stopped them being it.
        x: subPop.pad
        // No clamp against menu.height: the surface's height is computed FROM
        // this, so reading it back here is a binding loop. The surface is made
        // tall enough instead.
        y: subPop.pad
        color: Zenon.frostBg   // the submenu is a popup of its own too — see menuCard
        border.color: Zenon.border
        border.width: 1
        radius: Zenon.menuRadius
        // ── SQUARED WHERE IT MEETS THE CARD IT HANGS OFF ─────────────
        // As icarus' submenus are (see CardMenu's `hinged`): the edge that
        // faces the parent is square, so the two read as one piece folded
        // out rather than two cards set side by side. Which edge that is
        // depends on where the compositor put this popup — to the right,
        // or flipped to the left at a screen edge — and Qt knows both
        // windows' positions once they are placed, so it is asked, not
        // assumed.
        readonly property bool onLeft: {
          const sw = subPop.visible ? subPop.contentItem.Window.window : null;
          const mw = menuPop.visible ? menuPop.contentItem.Window.window : null;
          return !!sw && !!mw && sw.x < mw.x;
        }
        topLeftRadius: onLeft ? Zenon.menuRadius : 0
        bottomLeftRadius: onLeft ? Zenon.menuRadius : 0
        topRightRadius: onLeft ? 0 : Zenon.menuRadius
        bottomRightRadius: onLeft ? 0 : Zenon.menuRadius
        // Square where it meets the parent, round everywhere else.
        // See the parent card: two surfaces, so both are fully rounded.

        Column {
          id: subCol
          width: parent.width
          topPadding: Zenon.menuCardPad
          bottomPadding: Zenon.menuCardPad

          Repeater {
            model: subCard.items

            delegate: Item {
              id: subRow
              required property var modelData
              // needed by the keyboard cursor's highlight below; the parent
              // card's rows have always declared it
              required property int index
              width: subCol.width
              height: modelData.sep ? Zenon.menuSepHeight : Zenon.menuRowHeight

              // The action is READ BEFORE THE MENU CLOSES, and that ordering is
              // the whole reason these rows do anything at all.
              //
              // close() sets subAt back to -1, which makes subCard.items answer
              // with an empty list, which empties this Repeater's model — and an
              // emptied Repeater destroys its delegates. `modelData` belongs to
              // the delegate, so calling modelData.act() after close() is a call
              // on something that no longer exists. Every entry under Archive,
              // Open with and Sort by was silently dead for exactly that reason.
              //
              // Holding it in `pending` also buys the same flash the parent
              // card's rows get, so a choice in a submenu confirms itself the
              // same way a choice in the menu does.
              property real chosen: 0
              property var pending: null
              SequentialAnimation {
                id: subChosenAnim
                NumberAnimation { target: subRow; property: "chosen"; to: 1;
                                  duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { target: subRow; property: "chosen"; to: 0;
                                  duration: 130; easing.type: Easing.InQuad }
                ScriptAction {
                  script: {
                    const act = subRow.pending;
                    subRow.pending = null;
                    menu.close();
                    if (act) act();
                  }
                }
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                // edge to edge, as every menu's separator
                height: 1
                visible: !!modelData.sep
                color: Zenon.border
              }

              // muted: greyed, no highlight, no click (see step's `off`)
              opacity: modelData.off ? 0.45 : 1

              Rectangle {
                anchors.fill: parent
                visible: !modelData.sep && !modelData.off
                // the same highlight the parent card wears, from icarus
                color: subHov.hovered || menu.subSel === subRow.index
                  ? Zenon.border : "transparent"
              }
              HoverHandler { id: subHov; enabled: !modelData.sep }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                visible: menu.subGlyphs && !modelData.sep
                text: modelData.glyph || ""
                horizontalAlignment: Text.AlignHCenter
                color: Zenon.white
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }

              Text {
                id: subLabel
                anchors.left: parent.left
                anchors.leftMargin: 12 + menu.subGlyphW
                anchors.verticalCenter: parent.verticalCenter
                visible: !modelData.sep
                text: modelData.label || ""
                color: Zenon.white
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(16)
              }

              // what the format actually is, for the rows that carry one
              Text {
                anchors.left: subLabel.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: !!modelData.hint
                text: modelData.hint || ""
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                color: Zenon.muted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(13)
              }

              Rectangle {
                anchors.fill: parent
                visible: subRow.chosen > 0
                color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b,
                               0.55 * subRow.chosen)
              }

              MouseArea {
                anchors.fill: parent
                enabled: !modelData.sep && !modelData.off && !subChosenAnim.running
              // No hand cursor. This is a file manager, not a page of links:
              // a row you can click is the normal state of everything here, so
              // pointing at one is not news and the pointer should not change
              // to say so.
                onClicked: {
                  if (!modelData.act) return;
                  subRow.pending = modelData.act;
                  subChosenAnim.restart();
                }
              }
            }
          }
        }
      }
  }


  }
}
