// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Minerva's library: every book you have opened (and every one found in a
// watched directory) — its cover (an EPUB's own, a PDF's first page), its
// title and author, how far through you are, and when you last read it.
// Typing filters it.
//
// 2026-10-21: a strip over the covers chooses which — All, Reading, Unread,
// Finished, with how many — and a shelf, and the order; the book read last
// stands over the rest, ready to go on with (the hero); a finished book is
// ticked, a new one says so; a right click is the book's menu (the
// window's: shelves, finished, Terminus, Info, remove).
//
// MANY AT ONCE, AS TERMINUS (user, 2026-10-21): ctrl click marks a book,
// shift click the run from the cursor, and a drag on the grid draws
// terminus' box over the covers it takes in (worked out from the grid's
// geometry, as terminus' applyBand does, so covers scrolled out count too).
// The menu and delete then act on all of them.

import QtQuick
import "../morpheus"
import "../morpheus/gridnav.js" as Nav
import "../terminus"
import "minerva.js" as M

Item {
  id: lib

  property var mgr: null
  property var win: null
  property string query: ""
  property int sel: 0
  // the books marked: path → true (terminus' `marked`)
  property var marked: ({})
  readonly property int markedCount: Object.keys(lib.marked).length
  signal chosen(string path)
  signal menuAsked(var book, real x, real y)

  // the marked books in the order shown; the cursor's alone when none are
  function chosenBooks() {
    const m = lib.shown.filter((b) => lib.marked[b.path]);
    return m.length > 0 ? m : (lib.current() ? [lib.current()] : []);
  }
  function clearMarks() { if (lib.markedCount > 0) lib.marked = ({}); }
  function markAll() { const n = {}; for (const b of lib.shown) n[b.path] = true; lib.marked = n; }
  // a click on cell i, with what was held
  function clickAt(i, mods) {
    const b = lib.shown[i];
    if (!b) return;
    if (mods & Qt.ShiftModifier) {
      const n = (mods & Qt.ControlModifier) ? Object.assign({}, lib.marked) : {};
      for (let k = Math.min(lib.sel, i); k <= Math.max(lib.sel, i); ++k) if (lib.shown[k]) n[lib.shown[k].path] = true;
      lib.marked = n;
    } else if (mods & Qt.ControlModifier) {
      const n = Object.assign({}, lib.marked);
      // the cursor's book joins the first ctrl click, as a file manager's does
      if (lib.markedCount === 0 && lib.current() && lib.sel !== i) n[lib.current().path] = true;
      if (n[b.path]) delete n[b.path]; else n[b.path] = true;
      lib.marked = n;
    } else lib.clearMarks();
    lib.sel = i;
  }
  // the books no longer shown are no longer marked (a filter, a shelf)
  onShownChanged: {
    if (lib.sel >= lib.shown.length) lib.sel = Math.max(0, lib.shown.length - 1);
    if (lib.markedCount === 0) return;
    const n = {};
    for (const b of lib.shown) if (lib.marked[b.path]) n[b.path] = true;
    if (Object.keys(n).length !== lib.markedCount) lib.marked = n;
  }

  // ── THE BOX (terminus' rubber band) ────────────────────────────────────
  // which covers a box in this item's coordinates takes in: rows and
  // columns from the grid's own geometry, the hero's height above them
  function applyBand(x1, y1, x2, y2, base) {
    const next = Object.assign({}, base);
    const a = lib.mapToItem(grid.contentItem, x1, y1), b = lib.mapToItem(grid.contentItem, x2, y2);
    const top = grid.headerItem ? grid.headerItem.y + grid.headerItem.height : 0;
    const r1 = Math.floor((a.y - top) / grid.cellHeight), r2 = Math.floor((b.y - top) / grid.cellHeight);
    const c1 = Math.floor(a.x / grid.cellWidth), c2 = Math.floor(b.x / grid.cellWidth);
    for (let r = Math.max(0, r1); r <= r2; ++r)
      for (let c = Math.max(0, c1); c <= Math.min(lib.cols - 1, c2); ++c) {
        const i = r * lib.cols + c;
        if (i >= 0 && i < lib.shown.length) next[lib.shown[i].path] = true;
      }
    lib.marked = next;
  }

  readonly property var settings: lib.mgr ? lib.mgr.settings : M.defaults()
  readonly property var all: lib.mgr ? lib.mgr.books : []
  readonly property var shown: M.sortBooks(M.filterBooks(lib.all, lib.settings.view, lib.settings.shelf, lib.query), lib.settings.sort)
  function countOf(view) { return M.filterBooks(lib.all, view, lib.settings.shelf, "").length; }

  // the book to go on with: read last, not finished — over the grid, while
  // nothing is typed and the view could hold it
  readonly property var hero: {
    if (lib.query !== "" || lib.settings.view === "unread" || lib.settings.view === "finished") return null;
    const r = M.sortBooks(M.filterBooks(lib.all, "reading", lib.settings.shelf, ""), "recent");
    return r.length > 0 ? r[0] : null;
  }

  readonly property int cellW: 188
  // THE CELL IS AS TALL AS WHAT IT HOLDS (user, 2026-10-21: the cursor did
  // not reach the labels): the cover grows with the column's width, so a
  // fixed 320 let the three lines under a wide one hang out of the cell
  FontMetrics { id: titleFm; font.family: Zenon.face; font.weight: Zenon.titleWeight; font.pixelSize: Zenon.px(14) }
  FontMetrics { id: smallFm; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(12) }
  readonly property int cellH: 16 + Math.round((Math.floor(grid.width / lib.cols) - 36) * 1.42)
    + 10 + Math.ceil(titleFm.height + 2 * smallFm.height) + 4 + 18
  readonly property int cols: Math.max(1, Math.floor((grid.width) / lib.cellW))
  function move(dx, dy) {
    const n = lib.shown.length;
    if (n === 0) return;
    lib.sel = Math.max(0, Math.min(n - 1, lib.sel + dx + dy * lib.cols));
    grid.positionViewAtIndex(lib.sel, GridView.Contain);
  }
  function current() { return lib.shown[lib.sel] || null; }
  // a book chosen flashes in its cell, then opens (the grids' flash,
  // morpheus/ChosenFlash — user, 2026-10-21); by click or by return
  function choose(i) {
    const b = lib.shown[i];
    if (b) Nav.fireCell(grid.itemAtIndex(i), () => lib.chosen(b.path));
  }
  function goOn() { if (lib.hero) heroFlash.flashThen(0, () => lib.chosen(lib.hero.path)); }

  readonly property var viewNames: ({ all: "All", reading: "Reading", unread: "Unread", finished: "Finished" })
  readonly property var sortNames: ({ recent: "Recently read", title: "Title", author: "Author", progress: "Progress", added: "Recently added" })

  // ── THE STRIP: which, on what shelf, in what order ─────────────────────
  // ── WHAT SCROLLS GOES UNDER THE BARS, FROSTED (terminus', hestia's) ──
  // up under this strip and the window's head (chromeTop: the head's top,
  // here), down under the hint bar
  ScrollEdge { view: grid; follow: true; chromeTop: -lib.y; z: 1 }
  ScrollEdge { view: grid; below: true; follow: true; bar: lib.win ? lib.win.footItem : null; z: 1 }
  Item {
    id: strip
    z: 2
    width: parent.width
    height: 52
    // the toolbar's own ground over the rows going under it (hestia's)
    Rectangle { anchors.fill: parent; color: Zenon.headBg }
    Segments {
      anchors.left: parent.left
      anchors.leftMargin: 24
      anchors.verticalCenter: parent.verticalCenter
      options: M.VIEWS.map((v) => [v, lib.viewNames[v] + "  " + lib.countOf(v)])
      current: lib.settings.view
      onChose: (v) => { lib.mgr.setSetting("view", v); lib.sel = 0; }
    }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: 20
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8
      DialogButton {
        id: shelfBtn
        implicitHeight: 30
        label: (lib.settings.shelf !== "" ? "\u{F125F}  " + lib.settings.shelf : "\u{F125F}  All shelves")
        ink: lib.settings.shelf !== "" ? Zenon.cyan : Zenon.muted
        held: !!lib.win && lib.win.heldBy(shelfBtn)
        onClicked: lib.win.shelfMenu(shelfBtn)
      }
      DialogButton {
        id: sortBtn
        implicitHeight: 30
        label: "\u{F04BA}  " + lib.sortNames[lib.settings.sort]
        held: !!lib.win && lib.win.heldBy(sortBtn)
        onClicked: lib.win.openMenu(sortBtn, M.SORTS.map((k) => ({
          text: lib.sortNames[k], mark: k === lib.settings.sort ? "✓" : "",
          run: () => lib.mgr.setSetting("sort", k)
        })))
      }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.alpha(Zenon.border, 0.6) }
  }

  EmptyState {
    anchors.centerIn: parent
    width: Math.min(parent.width - 80, 520)
    visible: lib.shown.length === 0
    text: lib.query !== "" ? "Nothing in the library matches “" + lib.query + "”"
      : lib.all.length > 0 ? "No " + lib.viewNames[lib.settings.view].toLowerCase() + " books"
          + (lib.settings.shelf !== "" ? " on " + lib.settings.shelf : "")
      : "No books yet — Open… (ctrl o) picks a PDF, an EPUB, a comic or a text, anything opened from Terminus lands here, and Watch… brings in a whole directory"
  }

  RowFlash { id: heroFlash }
  GridView {
    id: grid
    anchors.top: strip.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: 24
    anchors.rightMargin: 12
    clip: true
    topMargin: 16
    cellWidth: Math.floor(width / lib.cols)
    cellHeight: lib.cellH
    // by count: the library is a new array whenever a place is saved
    model: lib.shown.length
    ElasticScroll { view: grid }
    CursorBand { follows: grid; index: lib.sel; radius: Zenon.radiusCard; insetX: 6; insetY: 6 }

    // ── THE HERO: the book to go on with ─────────────────────────────────
    header: Item {
      width: grid.width - 12
      height: lib.hero ? 236 : 0
      visible: !!lib.hero
      Rectangle {
        id: heroCard
        x: 6
        width: parent.width - 12
        height: 212
        radius: Zenon.radiusCard
        color: heroPress.pressed ? Zenon.pressFill : Zenon.wash(0.05)
        border.width: 1
        border.color: Zenon.border
        clip: true
        FlashOver { flash: heroFlash; index: 0; radius: parent.radius }
        // its cover, large, blurred behind — the book's own colour over the card
        Image {
          anchors.fill: parent
          source: lib.hero ? lib.hero.cover : ""
          fillMode: Image.PreserveAspectCrop
          opacity: 0.10
          sourceSize.width: 64
          smooth: true
        }
        Rectangle {
          id: heroCover
          x: 18
          y: 18
          width: Math.round(height / 1.42)
          height: parent.height - 36
          radius: Zenon.radiusControl
          color: Zenon.wash(0.08)
          border.width: 1
          border.color: Zenon.border
          clip: true
          Image {
            anchors.fill: parent
            source: lib.hero ? lib.hero.cover : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 240
          }
          // no cover of its own: its kind, as the grid's plain board has it
          Text {
            anchors.centerIn: parent
            visible: !!lib.hero && !lib.hero.cover
            text: !lib.hero ? "" : ({ pdf: "\u{F0226}", epub: "\u{F05DA}", comic: "\u{F02F9}", text: "\u{F09ED}" })[lib.hero.kind] || "\u{F05DA}"
            color: Zenon.accentMuted
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(34)
          }
        }
        Column {
          anchors.left: heroCover.right
          anchors.leftMargin: 22
          anchors.right: parent.right
          anchors.rightMargin: 22
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          SectionLabel { text: "Continue reading" }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: lib.hero ? lib.hero.title : ""
            color: Zenon.ink
            font.family: lib.mgr ? lib.mgr.serifFace : Zenon.face
            font.pixelSize: Zenon.px(26)
            font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            visible: text !== ""
            text: lib.hero ? lib.hero.author : ""
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
          Item { width: 1; height: 6 }
          // how far, as a bar and in words
          Rectangle {
            width: Math.min(parent.width, 420)
            height: 6
            radius: 3
            color: Zenon.wash(0.10)
            Rectangle {
              width: parent.width * (lib.hero ? lib.hero.progress : 0)
              height: parent.height
              radius: 3
              color: Zenon.cyan
            }
          }
          Text {
            text: !lib.hero ? "" : [M.percentWords(lib.hero.progress) + " read",
              M.whereWords(lib.hero.kind, lib.hero.pos, []).replace(/ · \d+%$/, ""),
              M.timeLeft(lib.hero) > 0 ? M.spanWords(M.timeLeft(lib.hero)) + " left" : "",
              M.openedWords(lib.hero.opened)].filter((x) => x).join("  ·  ")
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
          Item { width: 1; height: 8 }
          DialogButton {
            label: "Continue"
            ink: Zenon.cyan
            primary: true
            implicitHeight: 32
            onClicked: lib.goOn()
          }
        }
        MouseArea {
          id: heroPress
          anchors.fill: parent
          z: -1
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: (m) => { if (m.button === Qt.RightButton) { const p = mapToItem(lib, m.x, m.y); lib.menuAsked(lib.hero, p.x, p.y); } }
          onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) lib.goOn(); }
        }
      }
    }

    delegate: Item {
      id: cell
      required property int index
      readonly property var book: lib.shown[index] || null
      readonly property string state_: M.stateOf(cell.book)
      width: grid.cellWidth
      height: grid.cellHeight
      // in the cursor's own box (its inset and corners)
      readonly property alias flash: cellFlash
      readonly property bool isMarked: !!cell.book && !!lib.marked[cell.book.path]
      // marked: terminus' marked rows' wash and ring, in the cursor's box
      Rectangle {
        anchors.fill: parent
        anchors.margins: 6
        radius: Zenon.radiusCard
        visible: cell.isMarked
        color: Zenon.alpha(Zenon.cyan, 0.12)
        border.width: 1
        border.color: Zenon.alpha(Zenon.cyan, 0.6)
      }
      ChosenFlash { id: cellFlash; anchors.margins: 6; radius: Zenon.radiusCard }

      // the cover: its own, or the title set on a plain board — lifted a
      // little under the pointer
      Rectangle {
        id: coverBox
        anchors.horizontalCenter: parent.horizontalCenter
        y: 16 - (hover.hovered ? 4 : 0)
        Behavior on y { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
        width: grid.cellWidth - 36
        height: Math.round(width * 1.42)
        radius: Zenon.radiusControl
        color: Zenon.wash(0.06)
        border.width: 1
        border.color: hover.hovered ? Zenon.alpha(Zenon.cyan, 0.55) : Zenon.border
        clip: true
        property string src: ""
        Component.onCompleted: coverBox.fetch()
        Connections { target: cell; function onBookChanged() { coverBox.fetch(); } }
        function fetch() {
          const b = cell.book;
          coverBox.src = "";
          if (!b) return;
          if (b.cover) coverBox.src = b.cover;
          else if (b.kind === "pdf" && lib.mgr) {
            const path = b.path;
            lib.mgr.pdfCover(path, (url) => {
              if (cell.book && cell.book.path === path) { coverBox.src = url; lib.mgr.change(path, { cover: url }); }
            });
          }
        }
        Image {
          anchors.fill: parent
          source: coverBox.src
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize.width: 360
          visible: status === Image.Ready
        }
        Column {
          anchors.centerIn: parent
          width: parent.width - 24
          spacing: 8
          visible: coverBox.src === ""
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !cell.book ? "" : ({ pdf: "\u{F0226}", epub: "\u{F05DA}", comic: "\u{F02F9}", text: "\u{F09ED}" })[cell.book.kind] || "\u{F05DA}"
            color: Zenon.accentMuted
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(30)
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 4
            elide: Text.ElideRight
            text: cell.book ? cell.book.title : ""
            color: Zenon.ink
            font.family: lib.mgr ? lib.mgr.serifFace : Zenon.face
            font.pixelSize: Zenon.px(15)
          }
        }
        // how far through: a band along the cover's foot
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width * (cell.book ? cell.book.progress : 0)
          height: 4
          color: Zenon.cyan
          visible: !!cell.book && cell.book.progress > 0 && cell.state_ !== "finished"
        }
        // finished: a tick in the corner; never opened: "New"
        Rectangle {
          visible: cell.state_ !== "reading"
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.margins: 8
          width: cell.state_ === "finished" ? 26 : badge.implicitWidth + 14
          height: 22
          radius: 11
          color: cell.state_ === "finished" ? Zenon.green : Zenon.cyan
          Text {
            id: badge
            anchors.centerIn: parent
            text: cell.state_ === "finished" ? "\u{F012C}" : "New"
            color: Zenon.onAccent
            font.family: cell.state_ === "finished" ? Zenon.glyphFace : Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(cell.state_ === "finished" ? 14 : 11)
          }
        }
      }
      Column {
        anchors.top: coverBox.bottom
        anchors.topMargin: 10 + (hover.hovered ? 4 : 0)
        anchors.horizontalCenter: parent.horizontalCenter
        width: coverBox.width
        spacing: 2
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: cell.book ? cell.book.title : ""
          color: cell.index === lib.sel ? Zenon.ink : Zenon.white
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(14)
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: !cell.book ? "" : [cell.book.author, M.KINDS[cell.book.kind]].filter((x) => x).join("  ·  ")
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: !cell.book ? "" : cell.state_ === "finished" ? "Finished  ·  " + M.openedWords(cell.book.finished)
            : cell.state_ === "unread" ? "New  ·  added " + M.openedWords(cell.book.added).toLowerCase()
            : M.percentWords(cell.book.progress) + "  ·  " + M.openedWords(cell.book.opened)
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      HoverHandler { id: hover }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // a click chooses, a double click opens (user, 2026-10-21); ctrl
        // and shift mark, as terminus' rows do
        onClicked: (m) => {
          if (!cell.book) return;
          if (m.button === Qt.RightButton) {
            // a right click off the marked ones is about that book alone
            if (!cell.isMarked) lib.clickAt(cell.index, 0);
            const p = mapToItem(lib, m.x, m.y);
            lib.menuAsked(cell.book, p.x, p.y);
            return;
          }
          lib.clickAt(cell.index, m.modifiers);
        }
        onDoubleClicked: (m) => { if (m.button === Qt.LeftButton && cell.book) lib.choose(cell.index); }
      }
    }
  }
  Scrollbar { flick: grid; anchors.right: parent.right; anchors.top: grid.top; anchors.bottom: grid.bottom }

  // a click on no cover clears the marks (under the cells: theirs first)
  TapHandler {
    target: null
    onTapped: (ev) => {
      const p = lib.mapToItem(grid, ev.position.x, ev.position.y);
      if (p.y >= 0 && grid.indexAt(p.x + grid.contentX, p.y + grid.contentY) < 0) lib.clearMarks();
    }
  }
  DragHandler {
    id: band
    target: null
    acceptedButtons: Qt.LeftButton
    // a press may become the box from anywhere on the grid: a book has no
    // drag of its own to lose (terminus' CanTakeOverFromAnything)
    grabPermissions: PointerHandler.CanTakeOverFromAnything
    enabled: lib.visible && lib.shown.length > 0
    readonly property real x1: Math.max(grid.x, Math.min(centroid.pressPosition.x, centroid.position.x))
    readonly property real y1: Math.max(grid.y, Math.min(centroid.pressPosition.y, centroid.position.y))
    readonly property real x2: Math.min(grid.x + grid.width, Math.max(centroid.pressPosition.x, centroid.position.x))
    readonly property real y2: Math.min(grid.y + grid.height, Math.max(centroid.pressPosition.y, centroid.position.y))
    property var base: ({})
    property rect held: Qt.rect(0, 0, 0, 0)
    onActiveChanged: if (band.active) {
      // ctrl adds to what is marked; a plain drag starts afresh
      band.base = (band.centroid.modifiers & Qt.ControlModifier) ? Object.assign({}, lib.marked) : ({});
      band.held = Qt.rect(band.x1, band.y1, 0, 0);
    }
    onCentroidChanged: {
      if (!band.active) return;
      const w = band.x2 - band.x1, h = band.y2 - band.y1;
      if (w > 2 && h > 2) band.held = Qt.rect(band.x1, band.y1, w, h);
      lib.applyBand(band.x1, band.y1, band.x2, band.y2, band.base);
    }
  }
  // drawn from the held box, so it fades out where it was (terminus')
  Rectangle {
    z: 5
    visible: opacity > 0.01 && band.held.width > 2 && band.held.height > 2
    opacity: band.active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Zenon.ms(260); easing.type: Easing.OutCubic } }
    x: band.held.x
    y: band.held.y
    width: band.held.width
    height: band.held.height
    radius: Zenon.windowRadius
    color: Zenon.alpha(Zenon.cyan, 0.12)
    border.width: 1
    border.color: Zenon.border
  }
}
