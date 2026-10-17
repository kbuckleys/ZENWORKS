// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT A ROW OF CLIO'S LIST SAYS — Apple's three lines: the title; the
// first words; when it was last edited, in full; the container it is in.
// Every row has all four, not just the selected one, and the snippet carries
// no time of its own — the third line is the time (user, 2026-10-17). A pin,
// a lock, a checklist's progress; a picture's thumbnail at the end. A sticky
// wears its color.

import QtQuick
import Quickshell.Widgets
import "../morpheus"
import "notes.js" as N

Item {
  id: rb
  property var win: null
  property var note: null
  property bool here: false
  readonly property var mgr: rb.win ? rb.win.mgr : null
  readonly property var d: rb.note && rb.note.d ? rb.note.d : ({ title: "", preview: "", images: [], checks: 0, done: 0 })
  readonly property bool sticky: !!rb.note && rb.note.kind === "sticky"
  // the third line's time: when deleted in the Trash, else by the sort
  readonly property real stamp: !rb.note || rb.sticky ? 0 : rb.note.deleted ? rb.note.deleted
    : rb.mgr && rb.mgr.sort === "created" ? rb.note.created : rb.note.modified

  // a sticky's color
  Rectangle {
    visible: rb.sticky
    x: 18
    anchors.verticalCenter: parent.verticalCenter
    width: 10
    height: 10
    radius: 5
    color: rb.sticky ? Clio.ink(rb.note.hue) : "transparent"
  }

  Column {
    anchors.left: parent.left
    anchors.leftMargin: rb.sticky ? 38 : 20
    anchors.right: thumb.visible ? thumb.left : parent.right
    anchors.rightMargin: thumb.visible ? 10 : 18
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    Row {
      width: parent.width
      spacing: 6
      Text {
        visible: !!rb.note && !!rb.note.sealed
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: Zenon.yellow
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(12)
      }
      Text {
        width: parent.width - (pin.visible ? pin.width + 6 : 0) - (rb.note && rb.note.sealed ? 18 : 0)
        elide: Text.ElideRight
        text: rb.note ? N.titleOf(rb.note) : ""
        color: rb.here ? Zenon.ink : Zenon.accentSoft
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(15)
      }
      Text {
        id: pin
        visible: !!rb.note && !!rb.note.pinned && rb.win.query !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F0403}"
        color: Zenon.sand
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(11)
      }
    }
    Row {
      width: parent.width
      spacing: 8
      Text {
        width: parent.width - (checks.visible ? checks.width + 8 : 0)
        elide: Text.ElideRight
        text: !rb.note ? "" : rb.note.sealed ? "Locked" : rb.d.preview !== "" ? rb.d.preview : "No additional text"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      Text {
        id: checks
        visible: rb.d.checks > 0
        text: "\u{F0C52} " + rb.d.done + "/" + rb.d.checks
        color: rb.d.done === rb.d.checks ? Zenon.green : Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
        font.features: { "tnum": 1 }
      }
    }
    // when: in full (a sticky has no dates — where it is instead)
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: !rb.note ? "" : rb.sticky ? (Clio.shown ? "On the desktop" : "On the desktop · hidden")
        : rb.stamp ? (rb.note.deleted ? "Deleted " : "") + N.dateTime(rb.stamp) : "No date"
      color: rb.note && rb.note.deleted ? Zenon.red : Zenon.accentMuted
      font.features: { "tnum": 1 }
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
    // where it is, and what it holds besides words
    Row {
      width: parent.width
      spacing: 10
      Text {
        width: Math.min(implicitWidth, parent.width - (rowMarks.visible ? rowMarks.width + 10 : 0))
        elide: Text.ElideRight
        text: "  " + (rb.win ? rb.win.folderName(rb.note ? rb.note.folder : "") : "")
        color: Zenon.accentMuted
        opacity: 0.8
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
      ContentMarks {
        id: rowMarks
        visible: items.length > 0 && !(rb.note && rb.note.sealed)
        d: rb.d
        shownPics: thumb.visible ? 1 : 0
        noChecks: true
      }
    }
  }

  ClippingRectangle {
    id: thumb
    visible: rb.d.images.length > 0 && !(rb.note && rb.note.sealed)
    anchors.right: parent.right
    anchors.rightMargin: 18
    anchors.verticalCenter: parent.verticalCenter
    width: 46
    height: 46
    radius: 6
    color: Zenon.wash(0.05)
    Image {
      anchors.fill: parent
      source: thumb.visible && rb.mgr ? "file://" + rb.mgr.base + "/" + rb.d.images[0] : ""
      sourceSize.width: 120
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      // faded in as it arrives, not popped in (2026-10-17)
      opacity: status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }
  }
}
