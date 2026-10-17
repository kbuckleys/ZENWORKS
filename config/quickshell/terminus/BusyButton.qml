// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A BUTTON THAT BECOMES THE WORK IT STARTED — the suite's DialogButton,
// which, while `busy`, turns into a pill of the shell's working dots and
// what is going on ("Installing 4 families…", "Saving…"), growing or
// shrinking to fit it: one shape turning into the other, not a swap.
// Alexandria's install button first (2026-10-08); picasso's Apply and Save
// wear it since 2026-10-11 (user: "the same progress indicator").
//
//     BusyButton { label: "Save"; ink: Zenon.cyan; primary: true
//                  busy: win.working; busyText: "Saving…"
//                  onClicked: win.save() }

import QtQuick
import "../morpheus"

Item {
  id: bb
  property string label: ""
  property color ink: Zenon.accentMuted
  property bool primary: false
  property bool ready: true
  property bool busy: false
  property string busyText: ""
  // the pill's color; the button's own ink unless said
  property color busyInk: Zenon.cyan
  signal clicked()

  // The words stay while the pill fades out, so it does not shrink empty.
  property string shownText: ""
  onBusyTextChanged: if (bb.busyText !== "") bb.shownText = bb.busyText
  Component.onCompleted: bb.shownText = bb.busyText

  implicitWidth: bb.busy ? pill.implicitWidth : btn.implicitWidth
  implicitHeight: 28
  width: implicitWidth
  height: implicitHeight
  Behavior on implicitWidth { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }

  DialogButton {
    id: btn
    anchors.right: parent.right
    label: bb.label
    ink: bb.ink
    primary: bb.primary
    ready: bb.ready && !bb.busy
    opacity: bb.busy ? 0 : 1
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
    onClicked: bb.clicked()
  }
  Rectangle {
    id: pill
    anchors.right: parent.right
    implicitWidth: busyRow.implicitWidth + 34
    width: parent.width
    height: 28
    radius: 4
    clip: true
    color: Zenon.alpha(bb.busyInk, 0.08)
    border.width: 1
    border.color: Zenon.alpha(bb.busyInk, 0.4)
    opacity: bb.busy ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
    Row {
      id: busyRow
      anchors.centerIn: parent
      spacing: 10
      Working {
        anchors.verticalCenter: parent.verticalCenter
        running: bb.busy
        ink: bb.busyInk
        dot: 5
        gap: 4
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: bb.shownText
        color: bb.busyInk
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(15)
      }
    }
  }
}
