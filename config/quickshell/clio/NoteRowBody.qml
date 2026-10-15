// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT A ROW OF CLIO'S LIST SAYS — Apple's three lines: the title; the
// date and the first words after it; the container it is in (in All Notes, a
// tag, a search). The selected row has a fourth, before the container: when
// it was last edited, in full — once over the open note (user, 2026-10-15). A pin, a lock, a checklist's progress; a picture's
// thumbnail at the end. A sticky wears its colour.

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
  readonly property bool showFolder: !!rb.win && !rb.sticky && rb.note && rb.note.kind === "note"
    && (rb.win.scope.shelf === "all" || rb.win.scope.shelf === "tag" || rb.win.scope.shelf === "smart" || rb.win.query !== "")

  // whether the selected row says when it was last edited (NoteList grows
  // the row for it: hereH)
  readonly property bool edited: !!rb.note && !rb.sticky && !rb.note.deleted && !!rb.note.modified

  // a sticky's colour
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
        id: when
        visible: !rb.sticky
        text: !rb.note ? "" : rb.note.deleted ? N.dateShort(rb.note.deleted, Date.now())
          : N.dateShort(rb.mgr && rb.mgr.sort === "created" ? rb.note.created : rb.note.modified, Date.now())
        color: rb.note && rb.note.deleted ? Zenon.red : Zenon.ink
        opacity: 0.85
        font.family: Zenon.face
        font.weight: Font.DemiBold
        font.pixelSize: Zenon.px(13)
        font.features: { "tnum": 1 }
      }
      Text {
        width: parent.width - (when.visible ? when.width + 8 : 0) - (checks.visible ? checks.width + 8 : 0)
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
    // selected: when it was last edited, in full
    Text {
      visible: rb.here && rb.edited
      width: parent.width
      elide: Text.ElideRight
      text: rb.edited ? N.dateTime(rb.note.modified) : ""
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
    // where it is, and what it holds besides words
    Row {
      visible: rb.showFolder || rowMarks.visible
      width: parent.width
      spacing: 10
      Text {
        visible: rb.showFolder
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
    }
  }
}
