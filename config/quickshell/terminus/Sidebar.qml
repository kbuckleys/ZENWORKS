// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
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
  id: side
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  // while Hyprland resizes the window for it, the sidebar is whatever
  // the window has gained (see sideKeepW); otherwise it slides on its own
  width: term.sideKeepW >= 0
    ? Math.max(0, Math.min(term.sidebarWidth, term.width - term.sideKeepW))
    : term.sidebar ? term.sidebarWidth : 0
  // ── THE WHOLE HEIGHT OF THE WINDOW ───────────────────────
  // A column of its own down the left edge, from the top of the
  // window to the bottom — Finder's arrangement. The tabs, the path
  // bar and the heading strip are about the LISTING, so they start
  // where the sidebar ends (chrome is inset by this width) rather
  // than running over the top of it. It used to live inside the
  // body under all three, reaching up through the heading strip to
  // hide that it was being pushed down by it.
  anchors.top: parent.top
  anchors.bottom: parent.bottom
  anchors.left: parent.left
  visible: width > 0

  clip: true
  color: term.sidebarBg
  // ── IT SLIDES OUT, AS PLATO'S TREE DOES ──────────────────
  // The same motion, a little quicker: this box's width eases over
  // 1.4x the normal duration while the column inside keeps its full
  // width (see sideFlick), so the sidebar is UNCOVERED rather than
  // squeezed, and fades with the slide. Not while it is being dragged:
  // easing every frame of a drag makes the edge lag the pointer.
  Behavior on width {
    enabled: !term.sideGripRef.pressed && !term.sideFollowing
    NumberAnimation { duration: Math.round(Zenon.normal * 1.4); easing.type: Zenon.travelEase }
  }

  Rectangle {
    anchors.right: parent.right
    width: 1
    height: parent.height
    color: term.sideGripRef.pressed || term.sideGripRef.containsMouse
      ? Zenon.cyan : Zenon.border
  }

  // ── DROPPED ON THE SIDEBAR, NOT ON A DIRECTORY IN IT ─────────
  // means "keep this here": the directories that were carried become
  // bookmarks, at the end of the list. Declared BEFORE the rows'
  // scroller, so a bookmark or a disk — which takes drops of its own
  // — is still what a drop onto it means; this answers everywhere
  // else, headings and empty space included.
  DropArea {
    id: sideDrop
    anchors.fill: parent
    onDropped: (d) => term.bookmarkDropped(term.urlsFrom(d))
  }

  // lit like a pane about to take a drop, and saying what it will do
  Rectangle {
    anchors.fill: parent
    anchors.rightMargin: 1
    // stops at the trash foot, which takes its own drops
    anchors.bottomMargin: sideFoot.height
    visible: sideDrop.containsDrag
    color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.07)
    border.width: 1
    border.color: Zenon.border

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 14
      text: "drop to bookmark"
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
  }

  Flickable {
    id: sideFlick
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: sideFoot.top
    // ── THE TOP FADES, while there is more above it ──────────────
    // There is no bar over the sidebar's top for rows to go under, so
    // they dissolve into the window's edge instead (metis' ChipStrip
    // does the same sideways). No layer at all while at the top.
    layer.enabled: sideFlick.contentY > 0.5
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: sideFade
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }
    // its full width whatever the box is doing — see the slide above
    width: term.sidebarWidth - 1
    // faint while it is barely out, whole once it is: plato's curve
    opacity: Math.pow(Math.min(1, side.width / Math.max(1, term.sidebarWidth)), 1.5)
    contentHeight: sideCol.implicitHeight
    clip: true
    // NOT DRAGGABLE. A press held on a row and moved was scrolling
    // the column under it, which is a touchscreen's gesture on a
    // desktop list — and it fought every drag that starts on a row.
    // The wheel and the touchpad still scroll it: ElasticScroll
    // moves contentY itself, and a Flickable that is not interactive
    // ignores only the pointer, not being moved.
    interactive: false
    ElasticScroll { view: sideFlick }

    // ── THE CURSOR, AS ONE BAR THAT MOVES ───────────────────
    // The list sheets get theirs from a view and the panes from an
    // index; this column has neither. Its rows come from two Repeaters
    // with headings between them and they are not all the same height,
    // so the bar is placed against the row itself — the settings
    // panel's answer, for the same reason.
    //
    // A SIBLING OF THE COLUMN, inside the same scroller: mapped into
    // this coordinate space the position already includes wherever the
    // list has been scrolled to, so nothing here has to watch contentY.
    Rectangle {
      id: sideBar
      // null, never undefined, while a background build (TerminusManager
      // .prebuild) has not handed term its own properties yet
      readonly property var cur: term && term.sideAt ? term.sideAt : null
      visible: !!sideBar.cur && sideBar.cur.visible
      color: Zenon.border

      // mapToItem is a function call over geometry, not a property
      // read, so it is given the things that move to watch — the
      // column's own size, which settles when the rows are laid out
      // and changes again whenever a disk appears or the sidebar is
      // dragged wider.
      //
      // THE ROW'S OWN y AND ITS DRAG ARE WATCHED TOO. A rebuilt row is
      // born at 0 and only then placed by the Column, and the column's
      // size does not change when that happens — so the bar read the
      // row once, at birth, and sat on the heading from then on. And
      // a row being carried moves by its transform, which mapToItem
      // does include but nothing asked it again for, so the bar stayed
      // on the empty slot while the row it marks was somewhere else.
      readonly property var spot: (sideBar.cur
          && sideCol.height >= 0 && sideCol.width >= 0
          && sideBar.cur.y > -1e9 && sideBar.cur.dragY > -1e9
          && sideBar.cur.shift > -1e9 && sideBar.cur.settleY > -1e9)
        ? sideBar.cur.mapToItem(sideBar.parent, 0, 0) : null

      // ── IT STAYS WHERE IT WAS WHILE NOBODY HOLDS IT ─────────
      // Bound straight to the spot, an empty hand meant y = 0 — and
      // choosing another row is very often the old one letting go
      // BEFORE the new one claims, so the slide set off from the top
      // of the sidebar every time rather than from the row you left.
      // Written only when there is a row to be at; between owners it
      // is simply invisible, still standing on the last one.
      onSpotChanged: {
        if (!sideBar.spot) return;
        sideBar.x = sideBar.spot.x;
        sideBar.y = sideBar.spot.y;
        sideBar.width = sideBar.cur.width;
        sideBar.height = sideBar.cur.height;
      }
      Connections {
        target: sideBar.cur
        ignoreUnknownSignals: true
        function onWidthChanged() { sideBar.width = sideBar.cur.width; }
        function onHeightChanged() { sideBar.height = sideBar.cur.height; }
      }

      // Only the travel eases. A bookmark row is 32 and a gauged disk
      // is 46, and easing fourteen pixels of height is a stretch
      // rather than a movement.
      Behavior on y {
        enabled: term.cursorSlide && term.sideSlide
        NumberAnimation {
          duration: Zenon.fast; easing.type: Zenon.travelEase
        }
      }
    }

    Column {
      id: sideCol
      width: term.sidebarWidth - 1

      // The gap under the breadcrumb, and it is the SAME in every
      // view now. It used to make up whatever colHeads was not
      // supplying, because that strip pushed the sidebar down in
      // list view and not in the others — see the note on `side`,
      // which no longer lets it. A constant, so nothing in the
      // sidebar moves when the view changes.
      //
      // 4, not 10. The leading heading carries its own airIn above
      // the word now, so this spacer is no longer the whole of the
      // gap under the bar — it was being paid twice and the first
      // category sat noticeably lower than the rules under it.
      Item {
        width: 1
        // The first heading's words share a centre line with the path
        // bar beside them: the bar's inside is headH less its hairline,
        // and a heading's text sits airIn (7) below this spacer and is
        // about 17px tall.
        // 0 now: the leading heading is the bar's own height and sets its
        // words and its rule by it — see SideHead's `first`
        height: 0
      }

      // ── EMPTY SECTIONS ARE NOT SECTIONS ───────────────────
      // A heading over nothing is a promise the panel does not
      // keep. The other three already hid themselves; bookmarks
      // never did, so a fresh profile opened on the word
      // BOOKMARKS and a gap.
      //
      // `first` is whichever one is actually showing, not whichever
      // is written first — the leading heading wants no room above
      // it, and that is a different heading depending on what you
      // have.
      SideHead { term: side.term
        label: "BOOKMARKS"
        visible: !!term && term.bookmarks.length > 0
        first: true
      }

      Repeater {
        model: term.bookmarks

        delegate: SideRow { term: side.term
          required property var modelData
          required property int index
          slot: index
          width: sideCol.width
          label: Terminus.basename(modelData)
          // THE GLYPH THE DIRECTORY WEARS EVERYWHERE ELSE. Every row
          // here used to be the same bookmark tag, which said "this
          // is a bookmark" — a thing the panel it is sitting in had
          // already said — and threw away the one piece of
          // information the icon could have carried. Downloads,
          // .config and a git checkout are told apart at a glance in
          // the listing and in the send sheet; this is the third
          // place they are drawn and it is the same table.
          //
          // Home by its own name rather than by the user's: the
          // basename of ~ is "buck", which no rule claims, while the
          // sheet's roots already label it "Home" for exactly this.
          glyph: Icons.glyphFor({
            name: modelData === Paths.home()
              ? "home" : Terminus.basename(modelData),
            isDir: true })
          // ── ONLY WHEN THE DIRECTORY IS WHAT IS SHOWN ────
          // cwd does not change when a collection or a search is
          // opened — the page is drawn OVER the listing — so this
          // stayed lit the whole time you were somewhere else, and
          // the collection's own row lit beside it.
          //
          // Worse than cosmetic: the cursor bar is CLAIMED on the
          // change, so a row that never went inactive cannot take
          // it back when the collection releases it. Open Recents
          // from home, come back to home, and the bar marked
          // nothing at all — which is what Buck's capture shows.
          // Guarded, the flip back to true is a change, and the
          // change is the claim.
          active: term.searchMode === "" && modelData === term.cwd
          showRemove: true
          dropPath: modelData
          onChosen: term.goTo(modelData)
          onTabbed: term.openInNewTab(modelData)
          onRemoved: term.removeBookmark(modelData)
        }
      }

      Item {
        width: 1
        height: term.bookmarks.length === 0 ? 0 : 8
      }

      // ── TAGS ──────────────────────────────────────────────
      // Only the ones that are actually ON something. A tag that
      // has been made but not yet used is real — it is in the
      // picker, with its colour — but a sidebar entry that lists
      // nothing is a place you can go to find an empty room, and
      // the count beside each row is the promise this keeps.
      SideHead { term: side.term
        label: "TAGS"
        visible: !!term && term.sideTags.length > 0
        first: !!term && term.bookmarks.length === 0
      }

      Repeater {
        model: term.sideTags

        delegate: SideRow { term: side.term
          required property var modelData
          width: sideCol.width
          // No drag reorder: bookmarks carry an order that lives in
          // their file, and tags are sorted by name. slot -1 is how
          // SideRow is told it is not reorderable.
          slot: -1
          label: modelData.name
          detail: String(modelData.count)
          glyph: "\uF02B"
          ink: modelData.ink
          active: term.openTagName === modelData.name
          onChosen: term.openTag(modelData.name)
          onTabbed: term.openRealmInNewTab(() => term.openTag(modelData.name))
          // Off the sidebar means off every file that wears it — a
          // tag is listed here exactly while something carries it.
          showRemove: true
          onRemoved: term.clearTag(modelData.name)
        }
      }

      Item {
        width: 1
        height: term.sideTags.length === 0 ? 0 : 8
      }

      // ── SMART DIRECTORIES ─────────────────────────────────────
      // Listed whether or not they currently match anything: unlike
      // a tag, a collection exists because you wrote it, and one
      // that happens to be empty today is still the question you
      // asked. Hiding it would make "no results" look like "no
      // directory".
      // Never empty now: Recents is built in and always here, so
      // unlike the sections above this one has no hidden state —
      // see allCollections.
      SideHead { term: side.term
        label: "COLLECTIONS"
        visible: !!term && term.sideCollections.length > 0
        first: !!term && term.bookmarks.length === 0 && term.sideTags.length === 0
      }

      Repeater {
        model: term.sideCollections

        delegate: SideRow { term: side.term
          required property var modelData
          width: sideCol.width
          slot: -1
          label: modelData.name
          glyph: "\uEC78"
          ink: Zenon[modelData.ink] || Zenon.cyan
          // ── LIT ONLY WHILE A COLLECTION IS WHAT IS SHOWN ──
          // collOpenId is a stored value: written when a collection
          // opens and cleared only by Escape back to a directory.
          // Opening a TAG from a collection writes neither, so the
          // collection's row stayed lit underneath the tag's — two
          // sidebar entries both claiming to be the page you are on.
          //
          // Guarded on the mode, which is how openTagName has always
          // done it: that one is derived from searchMode and so
          // cannot go stale. This makes the pair symmetrical instead
          // of clearing collOpenId from each new realm and hoping
          // none is ever added without the line.
          active: term.searchMode === "collection"
            && term.collOpenId === modelData.id
          // A built-in has no record to delete or rules to edit, so
          // its cross takes it off the sidebar instead — Settings
          // brings it back ("Recents in sidebar").
          showRemove: true
          editable: !modelData.builtin
          onChosen: term.goToCollection(modelData.id)
          onTabbed: term.openRealmInNewTab(() => term.goToCollection(modelData.id))
          onRemoved: {
            if (modelData.builtin) { term.recentsShown = false; term.viewSaveRef.restart(); }
            else term.dropCollection(modelData.id);
          }
          onEdited: term.collEditRef.ask(modelData.id)
        }
      }

      Item { width: 1; height: term.sideCollections.length === 0 ? 0 : 8 }

      SideHead { term: side.term
        label: "DISKS"
        visible: !!term && term.disks.length > 0
        first: !!term && term.bookmarks.length === 0 && term.sideTags.length === 0
          && term.sideCollections.length === 0
      }

      Repeater {
        model: term.disks

        delegate: SideRow { term: side.term
          id: diskSide
          required property var modelData
          width: sideCol.width
          hasMenu: true
          onMenuAsked: (x, y) => term.diskMenu(diskSide, x, y, diskSide.modelData)
          label: modelData.name !== "" ? modelData.name
            : Terminus.basename(modelData.path)
          // Free space when it is mounted, total size when it is not.
          // "412G free" is the number you actually want before copying
          // to a disk; the capacity only matters when you cannot yet
          // see inside it. lsblk supplies both, so neither costs a
          // process.
          readonly property var live: term.diskLive(modelData)
          detail: live.mount !== "" && live.avail !== ""
            ? live.avail + " free" : live.size
          used: Terminus.usedFraction(live.avail, live.fsSize)
          glyph: modelData.removable ? "\uF0A0" : "\uF1C0"
          // At most one disk, and only when no bookmark is a
          // better answer — see root.sideDisk.
          active: modelData.mount !== ""
            && modelData.mount === term.sideDisk
          // a mounted disk is a place; an unmounted one is a button
          mounted: modelData.mount !== ""
          // no eject on the mounts the system is standing on
          showMount: !Terminus.isSystemMount(modelData.mount)
          // a place to drop into only while it is mounted
          dropPath: modelData.mount
          onChosen: {
            if (modelData.mount !== "") term.goTo(modelData.mount);
            else term.mountDisk(modelData);
          }
          onTabbed: if (modelData.mount !== "") term.openInNewTab(modelData.mount)
          onToggledMount: term.mountDisk(modelData)
        }
      }

      // room to scroll the last disk clear of the foot's frost
      Item { width: 1; height: 6 }
    }
  }

  // the top fade's mask: clear at the edge, solid a row down
  Rectangle {
    id: sideFade
    width: sideFlick.width
    height: sideFlick.height
    visible: false
    layer.enabled: true
    readonly property real ramp: Math.min(0.5, 28 / Math.max(1, sideFlick.height))
    gradient: Gradient {
      GradientStop { position: 0.0; color: "#00000000" }
      GradientStop { position: sideFade.ramp; color: "#ff000000" }
      GradientStop { position: 1.0; color: "#ff000000" }
    }
  }

  // ── THE FOOT: the trash, pinned ─────────────────────────────────
  // A bar along the sidebar's bottom, and the list goes under it as
  // every list in the shell goes under its bars: frosted
  // (morpheus/ScrollEdge, turned over). Declared first, so the foot's
  // own tint lies over the ghosts.
  ScrollEdge {
    view: sideFlick
    below: true
    x: 0
    y: sideFoot.y
    width: sideFlick.width
    height: sideFoot.height
    opacity: sideFlick.opacity
  }
  Rectangle {
    id: sideFoot
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    width: term.sidebarWidth - 1
    height: 41
    opacity: sideFlick.opacity
    color: term.sidebarBg   // the body, as the sidebar is
    Rectangle { width: parent.width; height: 1; color: Zenon.border }

    // lit while you are in it, as the list's own rows are by the
    // sliding bar (which belongs to the list, so cannot come down here)
    Rectangle {
      anchors.fill: trashRow
      visible: !!term && term.inTrash && term.searchMode === ""
      color: Zenon.border
    }
    SideRow { term: side.term
      id: trashRow
      y: 5
      width: parent.width
      slot: -1
      label: "Trash"
      glyph: term.trashCount > 0 ? "\uF1F8" : "\uF014"
      ink: term.inTrash && term.searchMode === "" ? Zenon.cyan : "transparent"
      detail: term.trashCount === 0 ? "empty"
        : term.trashCount + (term.trashSize !== "" ? " · " + term.trashSize : "")
      trashDrop: true
      onChosen: term.goTo(Terminus.trashFilesDir())
      onTabbed: term.openInNewTab(Terminus.trashFilesDir())
    }
  }
}
