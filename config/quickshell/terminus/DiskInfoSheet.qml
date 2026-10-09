// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── WHAT A DISK IS ────────────────────────────────────────────────────
// A disk's properties, from its menu in the sidebar or from the new-disk
// question: what it is, how it is connected, how full, and the
// identifiers you would otherwise go to lsblk for. A value is copied by
// clicking it — a UUID is read in order to be pasted somewhere.
//
// Read live from root.disks by path, so mounting it from here updates
// the card rather than leaving it describing the disk as it was.
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
  id: diskInfo
  // the terminus window (`term`, never `root` — see terminus-split notes)
  property var term: null
  anchors.fill: parent
  z: 14
  visible: opacity > 0.01
  opacity: diskInfo.open ? 1 : 0
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
      duration: diskInfo.open ? diskInfoSheet.slideIn : diskInfoSheet.slideOut
      easing.type: Zenon.ease
    }
  }

  property bool open: false
  property string path: ""

  readonly property var cur: {
    for (const d of term.disks) if (d.path === diskInfo.path) return term.diskLive(d);
    return null;
  }
  // The disk's LABEL — what you called it — before anything the
  // hardware says: then the partition's label, the model, and the device
  // name only when there is nothing better. This is the sheet's title.
  readonly property string title: {
    const d = diskInfo.cur;
    if (!d) return "";
    if (d.label) return d.label;
    if (d.partLabel) return d.partLabel;
    if (d.model) return d.model;
    return Terminus.basename(d.path);
  }
  readonly property var facts: Terminus.diskFacts(diskInfo.cur)
  readonly property real used: diskInfo.cur
    ? Terminus.usedFraction(diskInfo.cur.avail, diskInfo.cur.fsSize) : -1
  readonly property bool system: !!diskInfo.cur && Terminus.isSystemMount(diskInfo.cur.mount)

  function ask(d) {
    diskInfo.path = d.path;
    diskInfo.open = true;
  }
  function dismiss() {
    diskInfo.open = false;
    if (!term.plugRef.open) term.contentRef.forceActiveFocus();
  }
  // Return: go there, mounting first if it has to be
  function enter() {
    const d = diskInfo.cur;
    if (!d) return;
    if (d.mount === "") { term.mountDisk(d); return; }
    diskInfo.dismiss();
    if (term.plugRef.open) term.plugRef.dismiss();
    term.goTo(d.mount);
  }
  function toggle() {
    const d = diskInfo.cur;
    if (!d) return;
    if (diskInfo.system) { term.warn("the system is standing on " + d.mount); return; }
    term.mountDisk(d);
  }

  // a disk pulled out while you were reading about it
  onCurChanged: if (diskInfo.open && !diskInfo.cur) diskInfo.dismiss()

  InputShield { keepTop: term.tabStripRef.height + term.crumbBarRef.height; onClicked: diskInfo.dismiss() }

  Sheet {
    backdrop: term.chromeRef   // frosted over it — see morpheus/Sheet
    splice: true
    onCardInkChanged: term.noteSheet("s5", cardInk, drawnX, drawnW)
    onDrawnXChanged: term.noteSheet("s5", cardInk, drawnX, drawnW)
    onDrawnWChanged: term.noteSheet("s5", cardInk, drawnX, drawnW)
    id: diskInfoSheet
    leftInset: term.sideRef.width
    floating: false   // hangs from the bar, which carries its title — see barTitle
    title: term.sheetTitle
    glyph: term.sheetGlyph
    titleInk: term.sheetTitleInk
    glyphInk: term.sheetGlyphInk
    shown: diskInfo.open
    fromTop: term.tabStripRef.height + term.crumbBarRef.height
    // As wide as the footer needs: the hint and up to four buttons
    // share one row, and at a fixed 560 the buttons ran over the hint.
    cardW: Math.max(560, diskInfoHint.implicitWidth + diskInfoBtns.implicitWidth + 20 + 14 + 24)
    readonly property int factH: 28
    cardH: diskInfoHead.height + diskInfo.facts.length * diskInfoSheet.factH
      + 16 + diskInfoFoot.height

    // ── HOW FULL ─────────────────────────────────────────────────
    // The sidebar's own gauge, at the card's width: the same UsageBar a
    // disk row in the sidebar wears, with what is free written inside it,
    // so the card and the row it was opened from read as one instrument.
    // The exact used and total figures sit under it.
    //
    // NO NAME HERE: the bar above names the disk, the way every other
    // sheet is named on the bar (see sheetTitle), so a second title on the
    // card was saying it twice. Unmounted, there is nothing to measure
    // and the card starts with its facts.
    Item {
      id: diskInfoHead
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: diskInfo.used >= 0 ? 78 : 0
      visible: height > 0

      readonly property color ink: diskInfo.used > 0.95 ? Zenon.red
        : (diskInfo.used > 0.85 ? Zenon.yellow : Zenon.cyan)

      UsageBar {
        id: diskInfoGauge
        visible: diskInfo.used >= 0
        anchors.left: parent.left
        anchors.leftMargin: 20
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.top: parent.top
        anchors.topMargin: 16
        height: 22
        frac: Math.max(0, diskInfo.used)
        accent: diskInfoHead.ink
        label: diskInfo.cur ? diskInfo.cur.avail + " free" : ""
        ink: diskInfo.used > 0.85 ? diskInfoHead.ink : Zenon.white
        fontSize: 14
      }

      Text {
        visible: diskInfo.used >= 0
        anchors.left: diskInfoGauge.left
        anchors.top: diskInfoGauge.bottom
        anchors.topMargin: 8
        text: diskInfo.cur
          ? diskInfo.cur.fsUsed + " of " + diskInfo.cur.fsSize + " used"
          : ""
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      Text {
        visible: diskInfo.used >= 0
        anchors.right: diskInfoGauge.right
        anchors.top: diskInfoGauge.bottom
        anchors.topMargin: 8
        text: Math.round(diskInfo.used * 100) + "%"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }

      Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Zenon.border
      }
    }

    Column {
      anchors.top: diskInfoHead.bottom
      anchors.topMargin: 8
      anchors.left: parent.left
      anchors.right: parent.right

      Repeater {
        model: diskInfo.facts
        delegate: Item {
          id: factRow
          required property var modelData
          width: parent.width
          height: diskInfoSheet.factH
          Text {
            id: factKey
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            width: 130
            text: factRow.modelData[0]
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
          Text {
            anchors.left: factKey.right
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideMiddle
            text: factRow.modelData[1]
            color: factMa.containsMouse ? Zenon.cyan : Zenon.white
            font.family: Zenon.faceMono
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
            MouseArea {
              id: factMa
              anchors.fill: parent
              hoverEnabled: true
              onClicked: term.copyText(factRow.modelData[1],
                                       "copied " + factRow.modelData[0])
            }
          }
        }
      }
    }

    Item {
      id: diskInfoFoot
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: 52
      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Zenon.border
      }
      Text {
        id: diskInfoHint
        anchors.left: parent.left
        anchors.leftMargin: 20
        // and if the window is too narrow for the card to grow, the hint
        // gives way rather than sitting under the buttons
        anchors.right: diskInfoBtns.left
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: "click a value to copy it"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      Row {
        id: diskInfoBtns
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        DialogButton {
          visible: Terminus.ejectable(diskInfo.cur)
          label: "Safely remove"
          ink: Zenon.muted
          onClicked: { term.ejectDisk(diskInfo.cur); diskInfo.dismiss(); }
        }
        DialogButton {
          visible: !!diskInfo.cur && !diskInfo.system
          label: diskInfo.cur && diskInfo.cur.mount !== "" ? "Unmount" : "Mount"
          ink: Zenon.muted
          onClicked: diskInfo.toggle()
        }
        DialogButton {
          visible: !!diskInfo.cur && diskInfo.cur.mount !== ""
          label: "Open"
          ink: Zenon.cyan
          primary: true
          onClicked: diskInfo.enter()
        }
        DialogButton {
          label: "Close"
          ink: Zenon.muted
          onClicked: diskInfo.dismiss()
        }
      }
    }
  }
}
