// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TASKS — every checklist item not yet ticked, from every note and entry,
// in one place: Overdue, Today, This week, Later, then the ones with no
// date (N.tasks). The box ticks it where it is (mgr.tickTask); the words
// open the note at it (win.openAt). A filter narrows them. Locked notes
// keep theirs to themselves, as with Highlights.

import QtQuick
import "../morpheus"
import "../terminus"
import "notes.js" as N

Item {
  id: tb
  property var win: null
  property bool shown: false
  signal closed()
  property string filter: ""
  // re-read on every change to the notebook (mgr.notes) and each minute, so
  // "Today" turns into "Overdue" while it is open
  property real now: Date.now()
  Timer { interval: 60000; repeat: true; running: tb.shown; onTriggered: tb.now = Date.now() }
  readonly property var all: tb.shown && tb.win ? N.tasks(tb.win.mgr.notes, tb.now) : []
  readonly property var rows: tb.all.filter((t) => tb.filter === ""
    || (t.h + " " + t.title).toLowerCase().indexOf(tb.filter.toLowerCase()) >= 0)
  onShownChanged: if (tb.shown) { tb.filter = ""; tb.now = Date.now(); }

  Row {
    x: 20
    y: 16
    spacing: 12
    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{F0756}"; color: Zenon.cyan; font.family: Zenon.glyphFace; font.pixelSize: Zenon.px(18) }
    Text { anchors.verticalCenter: parent.verticalCenter; text: "Tasks"; color: Zenon.ink; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: Zenon.px(19) }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: tb.all.length === 0 ? "" : tb.all.length + " open"
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
  }
  DialogButton { anchors.right: parent.right; anchors.rightMargin: 20; y: 16; label: "Close"; onClicked: tb.closed() }

  Rectangle {
    anchors.right: parent.right
    anchors.rightMargin: 20
    y: 56
    width: 220
    height: 30
    radius: Zenon.windowRadius
    color: Zenon.wash(0.06)
    border.width: 1
    border.color: Zenon.border
    TextInput {
      id: field
      anchors.fill: parent
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      color: Zenon.ink
      font.family: Zenon.face
      font.pixelSize: Zenon.px(14)
      cursorDelegate: Caret { field: field }
      onTextChanged: tb.filter = text
      Text { visible: field.text === ""; anchors.verticalCenter: parent.verticalCenter; text: "Filter"; color: Zenon.accentMuted; font: field.font }
    }
    HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: field.activeFocus }
  }
  Text {
    x: 20
    y: 62
    text: "Due dates are set from an item's menu in the note"
    color: Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(12)
  }

  Flickable {
    id: taskFlick
    anchors.fill: parent
    anchors.topMargin: 100
    anchors.leftMargin: 18
    anchors.rightMargin: 18
    anchors.bottomMargin: 18
    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: col
      width: taskFlick.width
      spacing: 4
      Item { width: 1; height: 30; visible: tb.rows.length === 0 }
      EmptyState {
        visible: tb.rows.length === 0
        width: parent.width
        filtered: tb.filter !== ""
        text: tb.all.length === 0 ? "Nothing to do — every checklist item is ticked" : "Nothing matches “" + tb.filter + "”"
      }
      Repeater {
        model: tb.rows
        delegate: Column {
          id: one
          required property var modelData
          required property int index
          width: col.width
          // a group's heading over its first item
          readonly property bool first: one.index === 0 || tb.rows[one.index - 1].group !== one.modelData.group
          SectionLabel {
            visible: one.first
            topPadding: one.index === 0 ? 0 : 12
            bottomPadding: 4
            text: (N.TASK_GROUPS.find((g) => g.id === one.modelData.group) || {}).label || ""
            color: one.modelData.group === "overdue" ? Zenon.yellow : Zenon.accentMuted
          }
          Rectangle {
            width: parent.width
            height: Math.max(44, what.implicitHeight + where.implicitHeight + 18)
            radius: Zenon.windowRadius
            color: press.pressed ? Zenon.pressWash(0.12) : press.containsMouse ? Zenon.wash(0.06) : Zenon.wash(0.03)
            // the box: ticks it where it is
            Text {
              id: box
              x: 12
              anchors.verticalCenter: parent.verticalCenter
              text: boxPress.containsMouse ? "\u{F0134}" : "\u{F0130}"
              color: boxPress.containsMouse ? Zenon.green : Zenon.accentMuted
              font.family: Zenon.glyphFace
              font.pixelSize: Zenon.px(20)
              MouseArea {
                id: boxPress
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                onClicked: if (tb.win.mgr.tickTask(one.modelData)) tb.win.say("Ticked “" + one.modelData.h + "”")
              }
            }
            Text {
              id: what
              anchors.left: box.right
              anchors.leftMargin: 12
              anchors.right: when.left
              anchors.rightMargin: 12
              y: 9
              wrapMode: Text.Wrap
              maximumLineCount: 3
              elide: Text.ElideRight
              text: one.modelData.h
              color: Zenon.ink
              font.family: Zenon.face
              font.weight: Font.DemiBold
              font.pixelSize: Zenon.px(15)
            }
            Text {
              textFormat: Text.PlainText
              id: where
              anchors.left: what.left
              anchors.right: what.right
              anchors.top: what.bottom
              anchors.topMargin: 2
              elide: Text.ElideRight
              text: (one.modelData.kind === "entry" ? "\u{F0B64}  " : "\u{F09ED}  ") + one.modelData.title
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
            Text {
              id: when
              anchors.right: parent.right
              anchors.rightMargin: 14
              anchors.verticalCenter: parent.verticalCenter
              text: one.modelData.due ? N.dueText(one.modelData.due, tb.now) : ""
              color: one.modelData.group === "overdue" ? Zenon.yellow : Zenon.cyan
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
            // the rest of the row: the note, opened at the item
            MouseArea {
              id: press
              anchors.fill: parent
              anchors.leftMargin: box.x + box.width + 6
              hoverEnabled: true
              onClicked: { tb.closed(); tb.win.openAt(one.modelData.id, one.modelData.h); }
            }
          }
        }
      }
    }
  }
  ElasticScroll { anchors.fill: taskFlick; view: taskFlick }
  Scrollbar { flick: taskFlick; anchors.right: parent.right; anchors.top: taskFlick.top; anchors.bottom: taskFlick.bottom }
}
