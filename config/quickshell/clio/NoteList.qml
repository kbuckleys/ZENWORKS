// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CLIO'S LIST — the notes in view, as Apple's: the title, then the date and
// the first words after it, a picture's thumbnail at the end; pinned ones
// first, the rest under their date headings. Or as a gallery of cards
// (ctrl+2). A row is chosen with a click, asked about with a right click,
// and carried by a drag onto a container in the sidebar (or onto the Trash,
// or Stickies).

import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import "../morpheus"
import "../terminus"
import "notes.js" as N

Item {
  id: nl
  property var win: null
  readonly property var mgr: nl.win ? nl.win.mgr : null
  readonly property alias listView: list
  readonly property alias gridView: grid
  readonly property bool gallery: !!nl.mgr && nl.mgr.view === "gallery" && !nl.win.onDesktop

  // the row at index `i` brought into view (the arrows)
  function seat(i) {
    if (nl.gallery) grid.positionViewAtIndex(i, GridView.Contain);
    else list.positionViewAtIndex(i, ListView.Contain);
  }

  // ── THE BAR: WHAT THIS IS, HOW MANY, HOW SHOWN ─────────────────────────
  Item {
    id: bar
    width: parent.width
    height: 44
    Text {
      id: scopeName
      x: 16
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width - tools.width - 40)
      elide: Text.ElideRight
      text: {
        if (!nl.win) return "";
        const s = nl.win.scope;
        if (s.shelf === "desktop") return "Stickies";
        if (s.shelf === "trash") return "Trash";
        if (s.shelf === "tag") return "#" + s.id;
        if (s.shelf === "folder" || s.shelf === "smart") return (nl.mgr.folders.find((f) => f.id === s.id) || { name: "Notes" }).name;
        return "All Notes";
      }
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(17)
    }
    Text {
      anchors.left: scopeName.right
      anchors.leftMargin: 8
      anchors.baseline: scopeName.baseline
      text: nl.win ? nl.win.shown.length + (nl.win.onDesktop ? (nl.win.shown.length === 1 ? " sticky" : " stickies") : nl.win.shown.length === 1 ? " note" : " notes") : ""
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
      font.features: { "tnum": 1 }
    }
    Row {
      id: tools
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6
      visible: !nl.win.onDesktop
      Segments {
        anchors.verticalCenter: parent.verticalCenter
        options: [["list", ""], ["gallery", "\u{F0570}"]]
        current: nl.mgr ? nl.mgr.view : "list"
        textSize: Zenon.px(12)
        onChose: (v) => nl.mgr.set("view", v)
      }
      DialogButton {
        id: sortBtn
        anchors.verticalCenter: parent.verticalCenter
        glyph: true
        label: "\u{F04BA}"
        onClicked: {
          const p = sortBtn.mapToItem(nl.win.stageItem, 0, sortBtn.height + 4);
          const on = (v) => nl.mgr.sort === v ? "" : "";
          nl.win.menuRef.open(p.x, p.y, [
            { text: "Date edited", icon: on("modified"), run: () => nl.mgr.set("sort", "modified") },
            { text: "Date created", icon: on("created"), run: () => nl.mgr.set("sort", "created") },
            { text: "Title", icon: on("title"), run: () => nl.mgr.set("sort", "title") },
            { isSeparator: true },
            { text: "Group by date", icon: nl.mgr.groupByDate ? "" : "", run: () => nl.mgr.set("groupByDate", !nl.mgr.groupByDate) }]);
        }
        HoverHandler { onHoveredChanged: hovered ? nl.win.tipsItem.show(sortBtn, "Sort and group") : nl.win.tipsItem.hide(sortBtn) }
      }
    }
  }

  // ── THE ROWS ───────────────────────────────────────────────────────────
  // keyed by id and kept in place (calypso's lesson: a new array model
  // starts the list from its top)
  ListModel { id: rowModel }
  readonly property var rows: nl.win ? nl.win.rows : []
  onRowsChanged: nl.sync()
  function sync() {
    const r = nl.rows;
    let same = rowModel.count === r.length;
    for (let i = 0; same && i < r.length; i++) same = rowModel.get(i).key === r[i].n.id;
    if (same) {
      for (let i = 0; i < r.length; i++) if (rowModel.get(i).head !== r[i].head) rowModel.setProperty(i, "head", r[i].head);
      return;
    }
    rowModel.clear();
    for (const x of r) rowModel.append({ key: x.n.id, head: x.head });
  }
  function noteAt(i) { return nl.rows[i] ? nl.rows[i].n : null; }

  readonly property int rowH: 66 + Zenon.px(4)
  readonly property int secH: 34

  // ── CARRYING ONE ── the window's (win.carry / win.land), shared with the
  // journal's cards
  function carry(n, from, m) { nl.win.carry(n, from, m); }
  function land(from, m) { nl.win.land(from, m); }

  Component {
    id: rowDelegate
    Item {
      id: row
      required property string key
      required property string head
      required property int index
      readonly property var n: nl.noteAt(index) || ({ id: "", d: { title: "", preview: "", images: [], checks: 0, done: 0 } })
      readonly property bool here: nl.win && row.n.id === nl.win.selId
      width: ListView.view ? ListView.view.width : 300
      height: nl.rowH + (row.head !== "" ? nl.secH : 0)
      Text {
        visible: row.head !== ""
        x: 18
        height: nl.secH
        verticalAlignment: Text.AlignBottom
        bottomPadding: 7
        text: row.head
        color: row.head === "Pinned" ? Zenon.sand : Zenon.muted
        font.family: Zenon.face
        font.weight: Font.DemiBold
        font.pixelSize: Zenon.px(12)
        font.letterSpacing: 0.6
      }
      Item {
        id: body
        y: row.head !== "" ? nl.secH : 0
        width: parent.width
        height: nl.rowH
        NoteRowBody { anchors.fill: parent; win: nl.win; note: row.n; here: row.here }
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          property point at
          property bool moving: false
          onPressed: (m) => { at = Qt.point(m.x, m.y); moving = false; }
          onPositionChanged: (m) => {
            if (!pressed || m.buttons !== Qt.LeftButton) return;
            if (!moving && Math.abs(m.x - at.x) + Math.abs(m.y - at.y) > 8) moving = true;
            if (moving) nl.carry(row.n, this, m);
          }
          onReleased: (m) => { if (moving) nl.land(this, m); moving = false; }
          onClicked: (m) => {
            if (moving) return;
            if (m.button === Qt.RightButton) {
              const p = mapToItem(nl.win.stageItem, m.x, m.y);
              nl.win.noteMenu(row.n, p.x, p.y);
              return;
            }
            nl.win.choose(row.n.id);
            nl.win.refocus();
          }
          onDoubleClicked: { nl.win.choose(row.n.id); nl.win.paneRef.focusEditor(false); }
        }
        HeldRing { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; anchors.topMargin: 1; anchors.bottomMargin: 1
                   radius: Zenon.windowRadius; on: nl.win.menuRef.isOpen && nl.win.menuHeld === row.n.id }
      }
    }
  }

  ListView {
    id: list
    visible: !nl.gallery
    anchors.top: bar.bottom
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    clip: true
    bottomMargin: 10
    boundsBehavior: Flickable.StopAtBounds
    model: rowModel
    // every row built: two heights (with a heading, without) — see calypso
    cacheBuffer: Math.min(60000, nl.rows.length * (nl.rowH + 10)) + 600
    delegate: rowDelegate
    SelectBar {
      view: list
      host: nl.win
      index: nl.win ? nl.win.selIndex : -1
      rowH: nl.rowH
      // summed from the rows, not read off the delegate: a new sort rebuilds
      // every delegate, and one asked for before it is laid out left -1 —
      // index × rowH, blind to the date headings above it
      rowY: {
        const i = nl.win ? nl.win.selIndex : -1;
        const r = nl.rows;
        if (i < 0 || i >= r.length) return -1;
        let y = 0;
        for (let k = 0; k < i; k++) y += nl.rowH + (r[k].head !== "" ? nl.secH : 0);
        return y + (r[i].head !== "" ? nl.secH : 0);
      }
      on: nl.win && nl.win.selIndex >= 0
      color: nl.win ? nl.win.hiFill : "transparent"
      radius: Zenon.windowRadius
      inset: 8
    }
    EmptyMark {
      anchors.centerIn: parent
      visible: list.count === 0 && !!nl.mgr && nl.mgr.loaded
      filtered: !!nl.win && nl.win.query !== ""
      word: !nl.win || nl.win.query !== "" ? "" : nl.win.onDesktop ? "No stickies" : nl.win.inTrash ? "Nothing deleted" : "No notes"
    }
    Working { anchors.centerIn: parent; running: !!nl.mgr && nl.mgr.loading; visible: running }
  }
  ElasticScroll { anchors.fill: list; view: list; visible: list.visible }
  Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom; visible: list.visible }

  // ── THE GALLERY ────────────────────────────────────────────────────────
  GridView {
    id: grid
    visible: nl.gallery
    anchors.top: bar.bottom
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: 10
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    readonly property int across: Math.max(1, Math.floor(width / 170))
    cellWidth: Math.floor(width / across)
    cellHeight: Math.round(cellWidth * 1.15) + 46
    model: nl.gallery ? rowModel : null
    delegate: Item {
      id: tile
      required property int index
      readonly property var n: nl.noteAt(index) || ({ id: "", d: { title: "", preview: "", images: [] } })
      readonly property bool here: nl.win && tile.n.id === nl.win.selId
      width: grid.cellWidth
      height: grid.cellHeight
      ClippingRectangle {
        id: card
        x: 6
        y: 8
        width: parent.width - 12
        height: Math.round(width * 1.15) - 8
        radius: Zenon.windowRadius + 2
        color: Zenon.wash(0.05)
        border.width: tile.here ? 2 : 1
        border.color: tile.here ? Zenon.sand : Zenon.border
        Image {
          anchors.fill: parent
          visible: tile.n.d.images.length > 0 && !tile.n.sealed
          source: visible ? "file://" + nl.mgr.base + "/" + tile.n.d.images[0] : ""
          sourceSize.width: 360
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
        }
        Text {
          visible: tile.n.d.images.length === 0 || !!tile.n.sealed
          x: 12
          y: 10
          width: parent.width - 24
          height: parent.height - 20
          wrapMode: Text.Wrap
          elide: Text.ElideRight
          text: tile.n.sealed ? "" : (tile.n.d.preview || tile.n.d.title)
          color: Zenon.soft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(11)
          lineHeight: 1.1
        }
        Text {
          visible: !!tile.n.sealed
          anchors.centerIn: parent
          text: ""
          color: Zenon.muted
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(28)
        }
      }
      Column {
        anchors.top: card.bottom
        anchors.topMargin: 6
        x: 8
        width: parent.width - 16
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: (tile.n.pinned ? "\u{F0403} " : "") + N.titleOf(tile.n)
          color: tile.here ? Zenon.ink : Zenon.soft
          font.family: Zenon.face
          font.weight: Font.DemiBold
          font.pixelSize: Zenon.px(13)
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: N.dateShort(nl.mgr && nl.mgr.sort === "created" ? tile.n.created : tile.n.modified, Date.now())
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(11)
        }
      }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property point at
        property bool moving: false
        onPressed: (m) => { at = Qt.point(m.x, m.y); moving = false; }
        onPositionChanged: (m) => {
          if (!pressed || m.buttons !== Qt.LeftButton) return;
          if (!moving && Math.abs(m.x - at.x) + Math.abs(m.y - at.y) > 8) moving = true;
          if (moving) nl.carry(tile.n, this, m);
        }
        onReleased: (m) => { if (moving) nl.land(this, m); moving = false; }
        onClicked: (m) => {
          if (moving) return;
          if (m.button === Qt.RightButton) { const p = mapToItem(nl.win.stageItem, m.x, m.y); nl.win.noteMenu(tile.n, p.x, p.y); return; }
          nl.win.choose(tile.n.id);
          nl.win.refocus();
        }
        onDoubleClicked: { nl.win.choose(tile.n.id); nl.win.paneRef.focusEditor(false); }
      }
      HeldRing { anchors.fill: card; radius: card.radius; on: nl.win.menuRef.isOpen && nl.win.menuHeld === tile.n.id }
    }
  }
  ElasticScroll { anchors.fill: grid; view: grid; visible: grid.visible }
}
