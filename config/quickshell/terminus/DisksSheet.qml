// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── EVERY DISK, MOUNTED OR NOT ──────────────────────────────────────
// The sidebar has shown these for a while, but only while it is open and
// only as a strip down the edge — too narrow for the numbers that matter
// when you are deciding where something will fit. This is the same list
// with room to read it, reachable without the sidebar being up at all.
//
// It reads root.disks, which the four-second lsblk poll already fills for
// the sidebar, so the sheet costs no process of its own and a stick
// plugged in while it is open appears in it.
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
  id: disks
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  anchors.fill: parent
  z: 13
  visible: opacity > 0.01
  opacity: disks.open ? 1 : 0
  // THE SCRIM STOPS AT THE BAR: the bar is this sheet's titlebar,
  // and a scrim laid over it dimmed the title — as the send picker's is.
  color: "transparent"
  Rectangle {
    anchors.fill: parent
    anchors.topMargin: term.tabStripRef.height + term.crumbBarRef.height
    color: term.cardScrim
  }
  // and the sidebar beside the bar, which is not the titlebar: the
  // scrim stops at the bar, not at the sidebar's first heading
  Rectangle {
    width: term.sideRef.width
    height: term.tabStripRef.height + term.crumbBarRef.height
    color: term.cardScrim
  }
  Behavior on opacity {
    NumberAnimation {
      duration: disks.open ? disksSheet.slideIn : disksSheet.slideOut
      easing.type: Zenon.ease
    }
  }

  property bool open: false
  property int sel: 0

  // Mounted first, then the rest — the ones you can go to are the ones you
  // are usually here for, and an unmounted disk is a button rather than a
  // place. Within each half lsblk's own order is kept, which follows the
  // hardware rather than the alphabet and puts partitions of one device
  // together.
  readonly property var rows: {
    const on = [], off = [];
    for (const d of term.disks) (d.mount !== "" ? on : off).push(d);
    return on.concat(off);
  }

  readonly property var cur: disks.rows[disks.sel] || null

  function ask() {
    disks.sel = 0;
    disks.open = true;
  }

  function dismiss() {
    disks.open = false;
    term.contentRef.forceActiveFocus();
  }

  function step(d) {
    const n = disks.rows.length;
    if (n === 0) return;
    disks.sel = (disks.sel + d + n) % n;
    disksList.positionViewAtIndex(disks.sel, ListView.Contain);
  }

  // RETURN IS "TAKE ME THERE", which for something not yet mounted means
  // mounting it first — the same thing the sidebar's rows do, so the two
  // cannot answer the same gesture differently. The card stays open on a
  // mount, because the disk is not somewhere to go until it has one.
  function enter() {
    const d = disks.cur;
    if (!d) return;
    if (d.mount !== "") { disks.dismiss(); term.goTo(d.mount); return; }
    term.mountDisk(d);
  }

  // And `m` is the other half of it: the verb on its own, so a mounted
  // disk can be ejected from here without going to it first.
  function toggle() {
    const d = disks.cur;
    if (!d) return;
    if (Terminus.isSystemMount(d.mount)) {
      term.warn("the system is standing on " + d.mount);
      return;
    }
    term.mountDisk(d);
  }

  InputShield { keepTop: term.tabStripRef.height + term.crumbBarRef.height; onClicked: disks.dismiss() }

  Sheet {
    backdrop: term.chromeRef   // frosted over it — see morpheus/Sheet
    splice: true
    onCardInkChanged: term.noteSheet("s6", cardInk, drawnX, drawnW)
    onDrawnXChanged: term.noteSheet("s6", cardInk, drawnX, drawnW)
    onDrawnWChanged: term.noteSheet("s6", cardInk, drawnX, drawnW)
    id: disksSheet
    leftInset: term.sideRef.width
    floating: false   // hangs from the bar, which carries its title — see barTitle
    title: term.sheetTitle
    glyph: term.sheetGlyph
    titleInk: term.sheetTitleInk
    glyphInk: term.sheetGlyphInk
    shown: disks.open
    fromTop: term.tabStripRef.height + term.crumbBarRef.height
    cardW: 820
    readonly property int rowH: 38
    readonly property int pageRows: 12
    cardH: 12 + Math.max(1, Math.min(disksSheet.pageRows,
                                     disks.rows.length))
                * disksSheet.rowH + disksFoot.height

    SelectBar {

      host: term
      view: disksList
      index: disks.sel
      rowH: disksSheet.rowH
      on: disks.rows.length > 0
    }

    ListView {
      id: disksList
      anchors.top: parent.top
      anchors.topMargin: 6
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: disksFoot.top
      clip: true
      model: disks.rows
      boundsBehavior: Flickable.DragAndOvershootBounds
      boundsMovement: Flickable.FollowBoundsBehavior
      ElasticScroll { view: disksList; step: term.wheelStep }

      delegate: Item {
        id: diskRow
        required property var modelData
        required property int index
        width: disksList.width
        height: disksSheet.rowH

        readonly property bool mounted: modelData.mount !== ""
        readonly property var live: term.diskLive(modelData)
        readonly property real used:
          Terminus.usedFraction(diskRow.live.avail, diskRow.live.fsSize)

        // ── MOUNTED SAYS SO DOWN THE EDGE ─────────────────────────
        // The same 3px cyan bar the sidebar puts against the row you are
        // standing in. Saying it with the glyph's colour alone made two
        // states of one mark, which is a difference you have to know to
        // look for; a bar is either there or it is not.
        Rectangle {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: 3
          height: parent.height - 12
          radius: 1
          color: Zenon.cyan
          visible: diskRow.mounted
        }

        Text {
          id: diskGlyph
          anchors.left: parent.left
          anchors.leftMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          text: diskRow.modelData.removable ? "\uF0A0" : "\uF1C0"
          color: diskRow.mounted ? Zenon.cyan : Zenon.muted
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }

        Text {
          id: diskName
          anchors.left: diskGlyph.right
          anchors.leftMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          width: 210
          elide: Text.ElideRight
          text: diskRow.modelData.name !== ""
            ? diskRow.modelData.name
            : Terminus.basename(diskRow.modelData.path)
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }

        // WHERE IT IS, which is the whole question for a disk. Unmounted
        // says so in words rather than leaving the column blank — blank
        // reads as "not loaded yet".
        Text {
          id: diskWhere
          anchors.left: diskName.right
          anchors.leftMargin: 12
          anchors.right: diskFree.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideMiddle
          text: diskRow.mounted ? diskRow.modelData.mount : "not mounted"
          color: diskRow.mounted ? Zenon.keyInk : Zenon.muted
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }

        // Free space once it is mounted, capacity before — the same pair
        // the sidebar shows, and for the same reason: "412G free" is what
        // you want before copying, and the capacity is all there is to say
        // about a disk you cannot see inside yet.
        Text {
          id: diskFree
          anchors.right: diskUse.visible ? diskUse.left : diskFs.left
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          text: diskRow.mounted && diskRow.live.avail !== ""
            ? diskRow.live.avail + " free"
            : diskRow.modelData.size
          color: Zenon.white
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }

        // HOW FULL IT IS, which only a mounted disk knows — lsblk can
        // report a size for an unmounted one but never a free figure, so
        // the meter's absence is itself part of the answer.
        Meter {
          id: diskUse
          anchors.right: diskFs.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          visible: diskRow.mounted && diskRow.used >= 0
          vertical: false
          value: diskRow.used
          accent: diskRow.used > 0.9 ? Zenon.red : Zenon.cyan
          thickness: 5
          segLength: 4
          segGap: 2
          segCount: 12
          deadZone: 0
        }

        Text {
          id: diskFs
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          width: 62
          horizontalAlignment: Text.AlignRight
          text: diskRow.modelData.fstype
          color: Zenon.muted
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }

        MouseArea {
          anchors.fill: parent
          onClicked: { disks.sel = diskRow.index; disks.enter(); }
        }
      }
    }

    Rectangle {
      anchors.bottom: disksFoot.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: 1
      color: Zenon.border
    }

    Item {
      id: disksFoot
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: 34

      Row {
        anchors.centerIn: parent
        spacing: 12

        Text {
          anchors.verticalCenter: parent.verticalCenter
          rightPadding: 2
          text: disks.rows.length === 0 ? "no disks" : ""
          visible: disks.rows.length === 0
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }

        Repeater {
          model: [["\u2191\u2193", "move"], ["\u21b5", "go"],
                  ["m", "mount / eject"], ["esc", "close"]]

          delegate: Row {
            id: dfPair
            required property var modelData
            spacing: 5

            KeyCap {
              anchors.verticalCenter: parent.verticalCenter
              label: dfPair.modelData[0]
              fontSize: 11
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: dfPair.modelData[1]
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
