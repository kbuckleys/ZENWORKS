// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CLIO'S SIDEBAR — where to look: All Notes, Stickies (the desktop's),
// the containers as a tree and a row to make one, the smart containers; the
// tags, as chips to tap; the journals; and the Trash, pinned at the foot.
// Rows are the suite's ShelfRow, the heads its SideHead; a right click is
// the container's (or journal's) menu, and a note dragged from the list lands
// on a container here, or in the Trash (dropAt).

import QtQuick
import "../morpheus"
import "../terminus"
import "notes.js" as N

Item {
  id: side
  property var win: null
  readonly property var mgr: side.win ? side.win.mgr : null
  readonly property var scope: side.win ? side.win.scope : ({})

  // a note carried over the sidebar: the row it would land on
  property string dropHot: ""
  // where a dragged note at (x, y) in this item would go: { shelf, id }
  function dropAt(x, y) {
    for (const r of side.dropRows) {
      if (!r.visible) continue;
      const p = r.mapFromItem(side, x, y);
      if (p.x >= 0 && p.y >= 0 && p.x < r.width && p.y < r.height) return r.drop;
    }
    return null;
  }
  property var dropRows: []
  function register(r) { side.dropRows = side.dropRows.concat([r]); }
  function unregister(r) { side.dropRows = side.dropRows.filter((x) => x !== r); }

  // TERMINUS' AND PLATO'S TWO LAYERS: an inactive tab's glass, the sheet's veil
  Rectangle { anchors.fill: parent; color: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a)) }
  Rectangle { anchors.fill: parent; color: Zenon.ground; opacity: 0.6 }
  Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Zenon.border }

  // the name over it all
  Item {
    id: brand
    width: parent.width
    height: side.win ? side.win.headH : 50
    Row {
      x: 18
      anchors.verticalCenter: parent.verticalCenter
      spacing: 10
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: Zenon.sand
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(20)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Clio"
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(19)
      }
    }
    // settings
    Text {
      id: gear
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      text: "\u{F08BB}"
      color: gearPress.pressed ? Zenon.ink : Zenon.muted
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(16)
      MouseArea {
        id: gearPress
        anchors.fill: parent
        anchors.margins: -6
        onClicked: side.win.setOpen = true
      }
      HoverHandler { onHoveredChanged: hovered ? side.win.tipsItem.show(gear, "Settings", "ctrl ,") : side.win.tipsItem.hide(gear) }
    }
  }

  Flickable {
    id: flick
    anchors.top: brand.bottom
    anchors.bottom: trashFoot.top
    anchors.left: parent.left
    anchors.right: parent.right
    contentHeight: col.implicitHeight + 12
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    interactive: contentHeight > height

    Column {
      id: col
      width: flick.width
      spacing: 1

      SideHead { first: true; ruled: false; label: "Notes" }
      ClioShelf {
        host: side
        glyph: "\u{F11D7}"
        label: "All Notes"
        here: side.scope.shelf === "all"
        count: side.mgr ? String(side.mgr.notes.filter((n) => n.kind === "note" && !n.deleted).length) : ""
        drop: ({ shelf: "folder", id: "" })
        onClicked: side.win.setScope({ shelf: "all" })
      }
      ClioShelf {
        host: side
        glyph: "\u{F178F}"
        glyphInk: Zenon.sand
        label: "Stickies"
        here: side.scope.shelf === "desktop"
        count: side.mgr ? String(side.mgr.stickies.length) : ""
        drop: ({ shelf: "desktop", id: "" })
        onClicked: side.win.setScope({ shelf: "desktop" })
        onMenu: (x, y) => side.win.menuRef.open(x, y, [
          { text: "New sticky", icon: "", run: () => { side.win.setScope({ shelf: "desktop" }); side.win.newNote(); } },
          { text: "Gather onto the main monitor", icon: "\u{F0044}", run: () => { const k = Clio.gather(); side.win.say(k ? k + (k === 1 ? " sticky" : " stickies") + " brought back" : "Every sticky is on a screen already"); } },
          { text: Clio.shown ? "Hide stickies" : "Show stickies", icon: Clio.shown ? "" : "", run: () => Clio.toggle() }])
        // shown or hidden on the desktop, said by its eye
        Text {
          anchors.right: parent.right
          anchors.rightMargin: 46
          anchors.verticalCenter: parent.verticalCenter
          visible: Clio.count > 0
          text: Clio.shown ? "" : ""
          color: Zenon.muted
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(12)
          MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: Clio.toggle() }
        }
      }
      // the containers, as a tree
      Repeater {
        model: side.mgr ? N.folderRows(side.mgr.folders, side.mgr.notes, side.mgr.shut) : []
        delegate: ClioShelf {
          required property var modelData
          host: side
          indent: 18 + modelData.depth * 16
          glyph: ""
          label: modelData.name
          here: side.scope.shelf === "folder" && side.scope.id === modelData.id
          count: String(modelData.count)
          held: side.win.menuHeld === "f:" + modelData.id
          drop: ({ shelf: "folder", id: modelData.id })
          kids: modelData.kids
          shut: modelData.shut
          onToggled: {
            const s = Object.assign({}, side.mgr.shut);
            if (s[modelData.id]) delete s[modelData.id]; else s[modelData.id] = true;
            side.mgr.set("shut", s);
          }
          onClicked: side.win.setScope({ shelf: "folder", id: modelData.id })
          onMenu: (x, y) => side.win.folderMenu(side.mgr.folders.find((f) => f.id === modelData.id), x, y)
        }
      }
      // making one, under the containers (as "New journal" under the journals)
      ClioShelf {
        host: side
        glyph: ""
        label: "New container"
        muted: true
        count: "ctrl shift n"
        onClicked: side.win.askFolder("")
        onMenu: (x, y) => side.win.menuRef.open(x, y, [{ text: "New container…", icon: "\u{F0257}", run: () => side.win.askFolder("") },
                                                      { text: "New smart container…", icon: "\u{F0968}", run: () => side.win.askSmart(null) }])
      }

      SideHead { ruled: false; label: "Smart Containers"; visible: smartRep.count > 0 }
      Repeater {
        id: smartRep
        model: side.mgr ? side.mgr.folders.filter((f) => !!f.query) : []
        delegate: ClioShelf {
          required property var modelData
          host: side
          glyph: "\u{F0968}"
          glyphInk: Zenon.magenta
          label: modelData.name
          here: side.scope.shelf === "smart" && side.scope.id === modelData.id
          count: String(N.shelve(side.mgr.notes, { shelf: "smart", id: modelData.id }, "", "modified", side.mgr.folders).length)
          held: side.win.menuHeld === "f:" + modelData.id
          onClicked: side.win.setScope({ shelf: "smart", id: modelData.id })
          onMenu: (x, y) => side.win.folderMenu(modelData, x, y)
        }
      }

      // the tags: chips, as Apple's tag browser
      SideHead { ruled: false; label: "Tags"; visible: tagFlow.tags.length > 0 }
      Flow {
        id: tagFlow
        readonly property var tags: side.mgr ? N.tagRows(side.mgr.notes.filter((n) => n.kind === "note")) : []
        visible: tags.length > 0
        x: 16
        width: parent.width - 30
        spacing: 6
        bottomPadding: 6
        Repeater {
          model: tagFlow.tags
          delegate: Rectangle {
            required property var modelData
            readonly property bool on: side.scope.shelf === "tag" && side.scope.id === modelData.name
            width: tagText.implicitWidth + 18
            height: 26
            radius: Zenon.windowRadius
            color: on ? side.win.hiFill : Zenon.wash(0.05)
            border.width: 1
            border.color: on ? Zenon.alpha(Zenon.cyan, 0.5) : Zenon.border
            Text {
              id: tagText
              anchors.centerIn: parent
              text: "#" + modelData.name
              color: parent.on ? Zenon.cyan : Zenon.soft
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
            MouseArea {
              anchors.fill: parent
              onClicked: side.win.setScope(parent.on ? { shelf: "all" } : { shelf: "tag", id: modelData.name })
            }
          }
        }
      }

      SideHead { ruled: false; label: "Journal" }
      Repeater {
        model: side.mgr ? side.mgr.journals : []
        delegate: ClioShelf {
          required property var modelData
          host: side
          glyph: modelData.locked ? "" : "\u{F0B64}"
          glyphInk: Zenon[modelData.hue] || Zenon.cyan
          label: modelData.name
          here: side.scope.shelf === "journal" && side.scope.id === modelData.id
          count: String(side.mgr.notes.filter((n) => n.kind === "entry" && n.journal === modelData.id && !n.deleted).length)
          held: side.win.menuHeld === "j:" + modelData.id
          onClicked: side.win.setScope({ shelf: "journal", id: modelData.id })
          onMenu: (x, y) => side.win.journalMenu(modelData, x, y)
        }
      }
      ClioShelf {
        host: side
        glyph: ""
        label: "New journal"
        muted: true
        onClicked: side.win.askJournal(null)
      }
    }
  }
  ElasticScroll { anchors.fill: flick; view: flick }

  // ── THE FOOT: the trash, pinned ──
  // terminus' sidebar foot: the list goes on under it, frosted, and it is
  // as tall as the window's hint strip, so the two seams run as one line
  ScrollEdge {
    view: flick
    below: true
    x: 0
    y: trashFoot.y
    width: flick.width
    height: trashFoot.height
  }
  Item {
    id: trashFoot
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: 1
    anchors.bottom: parent.bottom
    height: side.win ? side.win.footH : 40
    readonly property int count: side.mgr ? side.mgr.notes.filter((n) => n.deleted > 0).length : 0
    ClioShelf {
      id: trashRow
      host: side
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      // full while there is something in it, as terminus' is
      glyph: trashFoot.count > 0 ? "\uF1F8" : "\uF014"
      label: "Trash"
      here: side.scope.shelf === "trash"
      count: trashFoot.count === 0 ? "empty" : String(trashFoot.count)
      // orange (Zenon's yellow) while there is something in it
      countInk: trashFoot.count > 0 ? Zenon.yellow : Zenon.muted
      held: side.win.menuHeld === "trash"
      drop: ({ shelf: "trash", id: "" })
      onClicked: side.win.setScope({ shelf: "trash" })
      onMenu: (x, y) => {
        side.win.menuHeld = "trash";
        const items = [{ text: "Open", icon: "\uF07C", run: () => side.win.setScope({ shelf: "trash" }) }];
        if (trashFoot.count > 0) items.push({ isSeparator: true },
          { text: "Put everything back", icon: "\u{F0A51}", run: () => side.mgr.restoreAll() },
          { text: "Empty Trash…", icon: "\uF1F8", danger: true,
            run: () => side.win.cardsRef.confirm({ question: "Empty the Trash?", glyph: "\uF1F8", ink: Zenon.red,
              detail: "Everything in it goes for good, with its pictures and files.", verb: "Empty Trash", then: () => side.mgr.emptyTrash() }) });
        side.win.menuRef.open(x, y, items);
      }
    }
  }
}
