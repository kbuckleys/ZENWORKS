// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// RENAMING A VOLUME, IN A SHEET — its filesystem label (what a file
// manager shows) and, on a GPT drive, its partition name (what the table
// calls it), both set in place: nothing is formatted, nothing moves.
// forge.py rename does it through udisks.
//
//     Sheet { cardH: body.implicitHeight
//       StylusRename { id: body; width: parent.width; win: sw } }

import QtQuick
import "../morpheus"
import "../terminus"
import "../terminus/terminus.js" as Terminus
import "stylus.js" as S

FocusScope {
  id: body

  property var win: null
  readonly property var drive: body.win ? body.win.drive : null
  readonly property var vol: body.win ? body.win.vol : null
  readonly property bool named: S.canName(body.drive, body.vol)
  readonly property bool labelled: !!body.vol && body.vol.fstype !== ""
  readonly property string label: body.labelled ? Terminus.cleanLabel(body.vol.fstype, labelField.text) : ""
  readonly property string name: S.cleanName(nameField.text)
  // anything to do: a field that differs from what is there
  readonly property bool changed: !!body.vol && ((body.labelled && body.label !== (body.vol.label || ""))
    || (body.named && body.name !== (body.vol.partLabel || "")))

  // the fields as the volume has them, each time the sheet opens
  function reset() {
    labelField.text = body.vol ? (body.vol.label || "") : "";
    nameField.text = body.vol ? (body.vol.partLabel || "") : "";
    Qt.callLater(() => (body.labelled ? labelField : nameField).claim());
  }
  function go() {
    if (!body.changed || !body.win) return;
    body.win.rename(body.labelled && body.label !== (body.vol.label || "") ? body.label : null,
                    body.named && body.name !== (body.vol.partLabel || "") ? body.name : null);
  }

  implicitHeight: col.implicitHeight + 2 * 24

  Column {
    id: col
    x: 24
    y: 24
    width: parent.width - 48
    spacing: 14

    Text {
      text: "Rename " + S.partName(body.vol)
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Zenon.titleWeight
      font.pixelSize: Zenon.px(17)
    }

    Row {
      visible: body.labelled
      spacing: 10
      Text {
        width: 130
        anchors.verticalCenter: parent.verticalCenter
        text: "Label"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      BulkField { id: labelField; width: 260; ghost: "None"; onAccepted: body.named ? nameField.claim() : body.go() }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        // terminus' rule for the filesystem: FAT's capitals, each limit
        text: !body.labelled ? "" : body.label !== labelField.text.trim() && labelField.text.trim() !== ""
          ? "Saved as “" + body.label + "”" : "up to " + (Terminus.formatOf(body.vol.fstype) || { labelMax: 16 }).labelMax
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
    }

    Row {
      visible: body.named
      spacing: 10
      Text {
        width: 130
        anchors.verticalCenter: parent.verticalCenter
        text: "Partition name"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      BulkField { id: nameField; width: 260; ghost: "None"; onAccepted: body.go() }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "up to 36"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: "Set in place — nothing on it is touched." + (body.named ? " The label is what file managers show; the partition name is the table's." : "")
      color: Zenon.accentSoft
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }

    Row {
      anchors.right: parent.right
      spacing: 10
      DialogButton { label: "Cancel"; ink: Zenon.accentMuted; onClicked: body.win.closeRename() }
      DialogButton { label: "Rename"; primary: true; ink: Zenon.cyan; ready: body.changed; onClicked: body.go() }
    }
  }

  Keys.onEscapePressed: body.win.closeRename()
}
