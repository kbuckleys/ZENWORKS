// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// OVER A NOTE'S FIRST LINE — what Apple draws there. A note: nothing (when
// it was last edited is on its row in the list). A journal entry: the reflection it
// answers, then its day (click: another day), its mood (click: how it
// felt), its bookmark. A sticky: that it is on the desktop.

import QtQuick
import "../morpheus"
import "notes.js" as N

Column {
  id: nh
  property var pane: null
  readonly property var n: nh.pane ? nh.pane.note : null
  readonly property bool entry: !!nh.n && nh.n.kind === "entry"
  spacing: 10
  bottomPadding: 10

  // a note's date is not here: it is the selected row's fourth line in
  // the list (NoteRowBody; user, 2026-10-15)
  Text {
    visible: !!nh.n && nh.n.kind === "sticky"
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    text: Clio.shown ? "On the desktop" : "On the desktop · hidden"
    color: Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(12)
  }

  // ── a journal entry's head ──
  // the reflection it answers
  Rectangle {
    visible: nh.entry && nh.n.prompt !== ""
    width: parent.width
    height: promptText.implicitHeight + 24
    radius: Zenon.rad(7)
    color: Zenon.alpha(Zenon.magenta, 0.08)
    border.width: 1
    border.color: Zenon.alpha(Zenon.magenta, 0.3)
    Text {
      id: promptText
      x: 14
      y: 12
      width: parent.width - 28
      wrapMode: Text.Wrap
      text: "\u{F0336}  " + (nh.entry ? nh.n.prompt : "")
      color: Zenon.accentSoft
      font.family: Zenon.face
      font.weight: Font.DemiBold
      font.italic: true
      font.pixelSize: Zenon.px(15)
    }
  }
  Row {
    visible: nh.entry
    spacing: 10
    // the day it is about
    Rectangle {
      id: dateChip
      height: 30
      width: dateText.implicitWidth + 24
      radius: Zenon.windowRadius
      color: datePress.pressed ? Zenon.pressWash(0.12) : Zenon.wash(0.05)
      border.width: 1
      border.color: Zenon.border
      Text {
        id: dateText
        anchors.centerIn: parent
        text: nh.entry ? "  " + N.dateLong(nh.n.date) : ""
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.DemiBold
        font.pixelSize: Zenon.px(13)
      }
      MouseArea { id: datePress; anchors.fill: parent; enabled: !nh.n || !nh.n.deleted; onClicked: nh.pane.win.dateOpen = true }
    }
    // how it felt
    Rectangle {
      height: 30
      width: moodText.implicitWidth + 24
      radius: Zenon.windowRadius
      readonly property var mood: nh.entry && nh.n.mood ? N.moodOf(nh.n.mood.v) : null
      color: moodPress.pressed ? Zenon.pressWash(0.12) : mood ? Zenon.alpha(Zenon[mood.ink] || Zenon.accentMuted, 0.14) : Zenon.wash(0.05)
      border.width: 1
      border.color: mood ? Zenon.alpha(Zenon[mood.ink] || Zenon.accentMuted, 0.5) : Zenon.border
      Text {
        id: moodText
        anchors.centerIn: parent
        text: parent.mood ? "\u{F01F5}  " + parent.mood.label + (nh.n.mood.words.length ? " · " + nh.n.mood.words.slice(0, 3).join(", ") : "")
          : "\u{F01F5}  How did it feel?"
        color: parent.mood ? Zenon.ink : Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Font.DemiBold
        font.pixelSize: Zenon.px(13)
      }
      MouseArea { id: moodPress; anchors.fill: parent; enabled: !nh.n || !nh.n.deleted; onClicked: nh.pane.win.moodOpen = true }
    }
    // kept
    Rectangle {
      height: 30
      width: 34
      radius: Zenon.windowRadius
      readonly property bool on: nh.entry && !!nh.n.bookmark
      color: on ? Zenon.alpha(Zenon.sand, 0.16) : Zenon.wash(0.05)
      border.width: 1
      border.color: on ? Zenon.alpha(Zenon.sand, 0.6) : Zenon.border
      Text {
        anchors.centerIn: parent
        text: parent.on ? "" : ""
        color: parent.on ? Zenon.sand : Zenon.accentMuted
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(14)
      }
      MouseArea { anchors.fill: parent; onClicked: nh.pane.mgr.setField(nh.n.id, "bookmark", !nh.n.bookmark, false) }
    }
  }
}
