// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE FOLDER OF THE HOME CASCADE. Icarus' Home row used to open a single card
// that REPLACED itself as you walked: click a folder and the card redrew as
// that folder, and the only way back was a `..` row with nothing on it. Now a
// folder opens beside the one it is in when you point at it, the way every
// menu's submenu does, and a click still walks the base card into it.
//
// Level 0 is the base card. It carries the things only it needs — the path
// you are in as crumbs, the places above the listing — and every level below
// it is just a listing. The OWNER (IcarusPopup) holds the stack, the
// selection and every action; a card reads its folder, draws it, and reports
// what happened to its rows.

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import "../morpheus"
import "../oracle"
import "icarus.js" as Icarus
import "../morpheus/icons.js" as Icons

PanelWindow {
  id: card
  WlrLayershell.layer: WlrLayer.Overlay

  required property var owner
  required property int level
  // the card this one hangs off — the root menu's card for level 0
  property var parentCard: null

  // ── LEAVING IS A STATE, NOT AN INSTANT ─────────────────────────────
  // A card is put away by cutting the stack short, and for a few frames
  // after that it still existed with no entry of its own and, often, no
  // parent — its folder went blank, its position fell back to the screen's
  // left edge, and it flashed there before it was destroyed. The owner now
  // keeps a leaving card alive through its fade (see setTrail), and the card
  // HOLDS what it was: its entry below, and its place through the Bindings
  // further down.
  readonly property var live: card.owner.homeTrail[card.level] || null
  readonly property bool alive: card.live !== null
  property var step: null
  Binding on step { value: card.live; when: card.alive; restoreMode: Binding.RestoreNone }
  readonly property string dir: card.step ? card.step.dir : ""
  // the row of the parent card that opened this one
  readonly property int from: card.step ? card.step.from : -1

  readonly property int cardW: 300
  // A card of thousands of rows is thousands of delegates built before it can
  // draw; past this the rest are one row that opens terminus.
  readonly property int cap: 250

  // ── the arrival ───────────────────────────────────────────────────────
  // A level below 0 is created already wanted, so onWantedChanged never runs
  // for it; the shade is set on the way in as well.
  property bool wanted: card.alive && card.owner.shown && card.owner.childMenu === "file"
  property real shade: 0
  onWantedChanged: card.shade = card.wanted ? 1 : 0
  Component.onCompleted: {
    card.shade = card.wanted ? 1 : 0;
    card.refresh();
  }
  Behavior on shade {
    NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
  }
  visible: card.wanted || card.shade > 0.01
  focusable: false
  aboveWindows: true
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  // the card's rectangle, not the card — see the note on appsMenu's mask
  mask: Region { x: bg.x; y: bg.y; width: bg.width; height: bg.height }
  anchors { top: true; left: true }
  screen: card.owner.screen

  // ── THE FOLDER ────────────────────────────────────────────────────────
  // `listing` is "loading" until the first answer. A re-listing of a folder
  // keeps the rows it had until the new ones arrive, so a card does not
  // collapse to nothing and spring back on every refresh.
  property string listing: "loading"
  property var raw: []
  property var counts: ({})
  property string askedDir: ""
  // the folder the rows on screen are OF — the last answer taken, which is
  // not `dir` for the moment between walking somewhere and its listing
  property string shownDir: ""
  property bool stale: false

  readonly property var shownRows: Icarus.visibleRows(card.raw, Oracle.menuShowHidden, card.cap)

  // The card's rows, as one list the delegate, the keyboard and the owner all
  // index the same way. `kind` is place, entry, note, more or sep.
  readonly property var rows: {
    const out = [];
    const pl = card.level === 0 && Oracle.menuHomePlaces ? card.owner.placeRows : [];
    for (const p of pl)
      out.push({ kind: "place", name: p.label, path: p.path, isDir: true, glyph: p.glyph });
    if (pl.length > 0) out.push({ kind: "sep" });

    // SAID, not left blank. An empty folder, one you may not read and one that
    // is gone used to be three identical empty cards.
    if (card.listing === "denied")
      out.push({ kind: "note", name: "Permission denied", glyph: "" });
    else if (card.listing === "missing")
      out.push({ kind: "note", name: "Not found", glyph: "" });
    else if (card.listing === "ok" && card.shownRows.rows.length === 0)
      out.push(card.raw.length > 0
        ? { kind: "note", name: "Only hidden files", glyph: "" }
        : { kind: "note", name: "Empty", glyph: "" });

    for (const r of card.shownRows.rows) {
      const e = Object.assign({ kind: "entry" }, r);
      e.glyph = Icons.glyphFor(r);
      out.push(e);
    }
    if (card.shownRows.more > 0)
      out.push({ kind: "more", name: card.shownRows.more + " more in Terminus",
                 path: card.dir, glyph: "" });
    return out;
  }

  // A row that opens a card beside this one. A folder known to be empty does
  // not: its card would say "Empty" and nothing else, and its chevron was a
  // promise of something to walk into.
  function isBranch(i) {
    const r = card.rows[i];
    if (!r) return false;
    if (r.kind === "place") return true;
    return r.kind === "entry" && r.isDir && card.counts[r.path] !== 0;
  }

  function selectable(i) {
    const r = card.rows[i];
    return !!r && (r.kind === "entry" || r.kind === "place" || r.kind === "more");
  }
  function firstSelectable() {
    for (let i = 0; i < card.rows.length; ++i) if (card.selectable(i)) return i;
    return -1;
  }
  // The next selectable row `by` steps away, stopping at either end rather
  // than wrapping — a long folder you are paging through should not jump.
  function nextSelectable(from, by) {
    const dir = by < 0 ? -1 : 1;
    let left = Math.abs(by);
    let best = from;
    for (let i = from + dir; i >= 0 && i < card.rows.length && left > 0; i += dir) {
      if (!card.selectable(i)) continue;
      best = i;
      left--;
    }
    if (best < 0) return card.firstSelectable();
    return best;
  }
  function lastSelectable() {
    for (let i = card.rows.length - 1; i >= 0; --i) if (card.selectable(i)) return i;
    return -1;
  }
  // How many rows a page is, for PageUp/PageDown.
  readonly property int pageRows: Math.max(1, Math.floor(listWrap.height / Zenon.menuRowHeight) - 1)

  // When the keyboard walked into this card before its rows had arrived, the
  // first row is selected as soon as they do.
  onRowsChanged: card.owner.homeRowsArrived(card)

  function refresh() {
    if (card.dir === "") return;
    if (listProc.running) { card.stale = true; return; }
    card.askedDir = card.dir;
    listProc.command = ["sh", "-c", Icarus.listCommand(card.dir)];
    listProc.running = true;
  }
  onDirChanged: {
    // a different folder starts at its top
    flick.contentY = 0;
    card.refresh();
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // an answer for a folder this card has since left is thrown away;
        // onRunningChanged asks again for the one it is in now
        if (card.askedDir !== card.dir) { card.stale = true; return; }
        const got = Icarus.parseListing(text, card.dir);
        card.shownDir = card.dir;
        card.listing = got.state;
        card.raw = got.rows;
        card.countFolders();
        // A remembered folder that has since gone: back home rather than a
        // card that says "Not found" every time the menu opens.
        if (card.level === 0 && got.state === "missing")
          card.owner.homeFolderGone(card.dir);
      }
    }
    onRunningChanged: if (!listProc.running && card.stale) {
      card.stale = false;
      card.refresh();
    }
  }

  // ── the number beside each folder ─────────────────────────────────────
  // Asked after the listing has drawn, never before: the rows are what you
  // came for, and a count is a detail that may arrive a moment later.
  readonly property bool hiddenShown: Oracle.menuShowHidden
  onHiddenShownChanged: card.countFolders()

  function countFolders() {
    const dirs = card.shownRows.rows.filter((r) => r.isDir).map((r) => r.path);
    if (dirs.length === 0) { card.counts = ({}); return; }
    // One count at a time, parsed against the list IT was asked about. The
    // list used to be replaced while a count was still out: the restart was a
    // no-op, the old output was read against the new folders, every one of
    // them defaulted to 0 and lost its chevron, and nothing counted them
    // again.
    if (countProc.running) { countProc.again = true; return; }
    countProc.countFor = dirs;
    countProc.command = Icarus.countArgv(dirs, card.hiddenShown);
    countProc.running = true;
  }

  Process {
    id: countProc
    property var countFor: []
    property bool again: false
    onExited: if (countProc.again) { countProc.again = false; Qt.callLater(card.countFolders); }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (countProc.again) return;   // overtaken; the fresh count follows
        card.counts = Icarus.parseCounts(text, countProc.countFor);
      }
    }
  }

  // ── WHERE IT GOES ─────────────────────────────────────────────────────
  // Beside the parent card, top level with the row that opened it, as every
  // submenu here is. Level 0 hangs off the root menu's Home row, through the
  // same submenuTop every other branch uses.
  readonly property int headerH: card.level === 0 ? Zenon.menuRowHeight + Zenon.menuSepHeight : 0

  function rowHeight(r) {
    return r && r.kind === "sep" ? Zenon.menuSepHeight : Zenon.menuRowHeight;
  }
  function rowY(i) {
    let y = 0;
    for (let k = 0; k < i && k < card.rows.length; ++k) y += card.rowHeight(card.rows[k]);
    return y;
  }
  readonly property int listH: {
    let h = 0;
    for (let k = 0; k < card.rows.length; ++k) h += card.rowHeight(card.rows[k]);
    return h;
  }
  readonly property int maxListH: card.screen
    ? card.screen.height - Zenon.padScreen * 2 - Zenon.menuCardPad * 2 - card.headerH
    : 500
  readonly property int bgH: Zenon.menuCardPad * 2 + card.headerH
    + Math.max(Zenon.menuRowHeight, Math.min(card.listH, card.maxListH))

  // A row's top, in screen coordinates — for the card a folder opens, and for
  // the right-click menu the keyboard opens.
  function rowScreenTop(i) {
    return card.cardY + Zenon.menuCardPad + card.headerH + card.rowY(i) - flick.contentY;
  }

  readonly property real parentX: card.parentCard ? card.parentCard.cardX : 0
  readonly property real parentW: card.parentCard ? card.parentCard.cardW : Zenon.menuWidth
  readonly property bool parentGoingLeft: card.level > 0 && card.parentCard
    ? card.parentCard.goingLeft : false

  readonly property real liveX: {
    if (!card.screen || !card.parentCard) return 0;
    return Math.round(Icarus.cascadeX(card.parentX, card.parentW, card.cardW,
      card.screen.width, Zenon.padScreen, card.parentGoingLeft));
  }
  readonly property bool goingLeft: card.cardX < card.parentX
  readonly property real liveY: {
    if (!card.screen) return 0;
    if (card.level === 0)
      return card.owner.submenuTop("file", card.bgH) + Zenon.menuShadowPad;
    const gap = Zenon.padScreen;
    let y = card.parentCard ? card.parentCard.rowScreenTop(card.from) : 0;
    if (y + card.bgH > card.screen.height - gap) y = card.screen.height - card.bgH - gap;
    return Math.max(gap, y);
  }

  // Where it is: where it should be while it is alive, and where it last was
  // once it is leaving — so it fades out in place instead of being thrown
  // across the screen by a parent that is already gone.
  property real cardX: 0
  property real cardY: 0
  Binding on cardX {
    value: card.liveX
    when: card.alive && !!card.parentCard
    restoreMode: Binding.RestoreNone
  }
  Binding on cardY {
    value: card.liveY
    when: card.alive && (card.level === 0 || !!card.parentCard)
    restoreMode: Binding.RestoreNone
  }

  implicitWidth: card.cardW + Zenon.menuShadowPad * 2
  implicitHeight: card.bgH + Zenon.menuShadowPad * 2
  margins.left: card.cardX - Zenon.menuShadowPad
  margins.top: card.cardY - Zenon.menuShadowPad

  // The row whose card is open beside this one stays lit.
  readonly property int openIndex: {
    const next = card.owner.homeTrail[card.level + 1];
    return next ? next.from : -1;
  }

  // Scrolled so row `i` is in view, for the keyboard.
  function ensureVisible(i) {
    if (i < 0) return;
    const top = card.rowY(i);
    const bottom = top + card.rowHeight(card.rows[i]);
    if (top < flick.contentY) flick.contentY = top;
    else if (bottom > flick.contentY + listWrap.height)
      flick.contentY = bottom - listWrap.height;
  }

  // The flash of row `i`, then `act` — for the keyboard's Enter, which has
  // no mouse to flash the row it chose.
  function flashRow(i, act) {
    const d = rowRepeater.itemAt(i);
    if (d) d.fire(act);
    else act();
  }

  // The point on screen a window-local point in `item` is at.
  function toScreen(item, x, y) {
    const p = item.mapToItem(bg, x, y);
    return Qt.point(card.cardX + p.x, card.cardY + p.y);
  }

  ClippingRectangle {
    id: bg
    anchors.fill: parent
    anchors.margins: Zenon.menuShadowPad
    transformOrigin: Item.TopLeft
    scale: Zenon.menuScale(card.shade)
    opacity: card.shade
    color: Zenon.frostBg   // quick look's ground — see Zenon.frostBg
    border.color: Zenon.border
    border.width: 1
    radius: Zenon.menuRadius
    // square on the side it meets its parent, as a hinged CardMenu is
    readonly property bool againstLeft: !card.goingLeft
    topLeftRadius: bg.againstLeft ? 0 : bg.radius
    bottomLeftRadius: bg.againstLeft ? 0 : bg.radius
    topRightRadius: bg.againstLeft ? bg.radius : 0
    bottomRightRadius: bg.againstLeft ? bg.radius : 0

    Column {
      anchors.fill: parent
      anchors.margins: Zenon.menuCardPad
      spacing: 0

      // ── THE PATH YOU ARE IN ──────────────────────────────────────────
      // Where the blank `..` row was. Every crumb is somewhere to go — the
      // base card walks there — so this is the way up as well as the label,
      // and the folder button on its right opens the folder in terminus.
      Item {
        id: header
        visible: card.level === 0
        width: parent.width
        height: card.level === 0 ? Zenon.menuRowHeight : 0

        FontMetrics {
          id: crumbMetrics
          font.family: Zenon.face
          font.weight: Font.Medium
          font.pixelSize: 15
        }

        readonly property real sepW: 18
        readonly property var crumbs: Icarus.fitCrumbs(
          card.owner.homeCrumbs(card.dir), crumbRow.availW,
          (s) => crumbMetrics.advanceWidth(s), header.sepW)

        // right-click anywhere on the header is a question about this folder
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.RightButton | Qt.MiddleButton
          onClicked: (m) => {
            if (m.button === Qt.MiddleButton) {
              card.owner.openInTerminus(card.dir);
              card.owner.closeAll();
              return;
            }
            card.owner.homeHeaderMenu(card, card.toScreen(header, m.x, m.y));
          }
        }

        Row {
          id: crumbRow
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          readonly property real availW: header.width - 12 - openBtn.width - 16
          spacing: 0

          Repeater {
            model: header.crumbs
            delegate: Row {
              id: crumb
              required property var modelData
              required property int index
              readonly property bool last: crumb.index === header.crumbs.length - 1

              Text {
                visible: crumb.index > 0
                width: header.sepW
                height: Zenon.menuRowHeight
                text: ""
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }

              Text {
                id: crumbLabel
                height: Zenon.menuRowHeight
                width: crumb.last ? Math.min(implicitWidth, crumbRow.availW) : implicitWidth
                elide: Text.ElideMiddle
                text: crumb.modelData.label
                color: crumb.last || crumbHover.containsMouse ? Zenon.white : Zenon.muted
                font.family: Zenon.face
                font.weight: Font.Medium
                font.pixelSize: 15
                verticalAlignment: Text.AlignVCenter

                MouseArea {
                  id: crumbHover
                  anchors.fill: parent
                  hoverEnabled: !crumb.last
                  enabled: !crumb.last
                  cursorShape: Qt.PointingHandCursor
                  onClicked: card.owner.homeReroot(crumb.modelData.path)
                }
              }
            }
          }
        }

        // Open this folder in terminus — the button the menu never had; a
        // folder could only be walked through, never handed over.
        Item {
          id: openBtn
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 30
          Rectangle {
            anchors.fill: parent
            color: openHover.containsMouse ? Zenon.border : "transparent"
          }
          Text {
            anchors.centerIn: parent
            text: ""
            color: Zenon.white
            font.family: Zenon.face
            font.pixelSize: 15
          }
          ChosenFlash { id: openFlash }
          MouseArea {
            id: openHover
            anchors.fill: parent
            hoverEnabled: true
            enabled: !openFlash.running
            onClicked: openFlash.fire(() => {
              card.owner.openInTerminus(card.dir);
              card.owner.closeAll();
            })
          }
        }
      }

      Item {
        visible: card.level === 0
        width: parent.width
        height: card.level === 0 ? Zenon.menuSepHeight : 0
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: -Zenon.menuCardPad
          anchors.rightMargin: -Zenon.menuCardPad
          height: 1
          color: Zenon.border
        }
      }

      // ── the listing ─────────────────────────────────────────────────
      // The wheel is an overlay MouseArea for the reason the appsMenu note
      // gives: a WheelHandler inside a Flickable never fires.
      Item {
        id: listWrap
        width: parent.width
        height: Math.max(Zenon.menuRowHeight, Math.min(card.listH, card.maxListH))

        Flickable {
          id: flick
          ElasticScroll { view: flick }
          anchors.fill: parent
          clip: false
          contentWidth: width
          contentHeight: card.listH
          boundsBehavior: Flickable.StopAtBounds
          flickDeceleration: 1800
          maximumFlickVelocity: 2800

          Column {
            id: rowHolder
            width: parent.width
            spacing: 0

            Repeater {
              id: rowRepeater
              model: card.rows

              delegate: Item {
                id: entry
                required property var modelData
                required property int index
                width: rowHolder.width
                height: card.rowHeight(entry.modelData)

                readonly property string kind: entry.modelData.kind
                readonly property bool isSep: entry.kind === "sep"
                readonly property bool isNote: entry.kind === "note"
                readonly property bool pickable: card.selectable(entry.index)
                readonly property bool lit: entry.pickable
                  && ((card.owner.selLevel === card.level && card.owner.selIndex === entry.index)
                      || card.openIndex === entry.index
                      || card.owner.isCtxRow(card.level, entry.index))
                readonly property bool branch: card.isBranch(entry.index)

                function fire(act) { entryFlash.fire(act); }

                // drag a file or folder out — see dragPicture in the owner
                Drag.active: false
                Drag.source: entry
                Drag.keys: ["text/uri-list"]
                Drag.mimeData: {"text/uri-list": "file://" + encodeURI(entry.modelData.path || "") + "\r\n"}
                Drag.supportedActions: Qt.CopyAction
                Drag.dragType: Drag.Automatic
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2
                Drag.onDragFinished: function(dropAction) {
                  entry.Drag.active = false;
                  if (dropAction === Qt.CopyAction) card.owner.closeAll();
                }

                Rectangle {
                  anchors.fill: parent
                  color: entry.lit ? Zenon.border : "transparent"
                }

                Rectangle {
                  visible: entry.isSep
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: -Zenon.menuCardPad
                  anchors.rightMargin: -Zenon.menuCardPad
                  height: 1
                  color: Zenon.border
                }

                Item {
                  visible: !entry.isSep
                  anchors.fill: parent
                  anchors.leftMargin: 12
                  anchors.rightMargin: 10

                  Text {
                    id: glyph
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    // the shared map, as terminus draws the same entry
                    text: entry.modelData.glyph || ""
                    color: entry.isNote ? Zenon.muted : Zenon.white
                    font.family: Zenon.face
                    font.pixelSize: 15
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Text {
                    anchors.left: glyph.right
                    anchors.leftMargin: 8
                    anchors.right: detail.left
                    anchors.rightMargin: detail.text !== "" ? 8 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.modelData.name || ""
                    elide: Text.ElideMiddle
                    // hidden entries a shade down, so the eye finds the rest
                    color: entry.isNote || (entry.modelData.isHidden || false)
                      ? Zenon.muted : Zenon.white
                    font.family: Zenon.face
                    font.weight: Font.Medium
                    font.italic: entry.isNote
                    font.pixelSize: 16
                  }

                  // What is in a folder, or how big a file is — muted and in
                  // the margin, where the eye reaches for it only if it wants.
                  Text {
                    id: detail
                    anchors.right: arrow.left
                    anchors.rightMargin: arrow.visible ? 6 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                      const m = entry.modelData;
                      if (entry.kind !== "entry") return "";
                      if (m.isDir) {
                        const n = card.counts[m.path];
                        return n === undefined ? "" : String(n);
                      }
                      return m.broken ? "" : Icarus.shortSize(m.size);
                    }
                    color: Zenon.muted
                    font.family: Zenon.face
                    font.pixelSize: 12
                  }

                  Text {
                    id: arrow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? 16 : 0
                    height: 16
                    visible: entry.branch
                    text: ""
                    color: Zenon.white
                    font.family: Zenon.face
                    font.pixelSize: 16
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                  }
                }

                DragHandler {
                  enabled: entry.kind === "entry" || entry.kind === "place"
                  target: null
                  onActiveChanged: {
                    if (!active) return;
                    // the picture is made BEFORE the drag is offered — see the
                    // note where the old file card did this
                    card.owner.dragPicture(entry.modelData.name, glyph.text,
                                           Zenon.white, function(url) {
                      entry.Drag.imageSource = url;
                      entry.Drag.active = true;
                    });
                  }
                }

                ChosenFlash { id: entryFlash }

                MouseArea {
                  id: hover
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                  enabled: !entry.isSep && !entryFlash.running
                  onEntered: card.owner.homeHovered(card, entry.index)
                  onExited: if (hover.enabled) card.owner.homeUnhovered(card, entry.index)
                  onClicked: (m) => card.owner.homeClicked(card, entry.index, m.button,
                    card.toScreen(entry, m.x, m.y))
                }
              }
            }
          }
        }

      }
    }
  }

  MenuShadow {
    panel: bg
    opacity: card.shade
    transformOrigin: Item.TopLeft
    scale: bg.scale
  }
}
