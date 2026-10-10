// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE NEW-DISK CARD'S INSIDES — the heading, a row per disk, and the foot.
// Terminus' plug sheet and the pill's disk panel (terminus/PlugPanel) are the
// same question, so they are the same card: this draws it and the holder
// does the mounting. Rows are disk records as Terminus.parseDisks makes them,
// read live by the holder, so a disk that gets mounted or pulled out changes
// here on its own.
//
// `openVerb`: terminus is already where a mounted disk is looked at, so its
// Mount goes there and needs no second button. The pill is not, so it offers
// Mount (stay here) beside Mount & open (go there in terminus).

import QtQuick
import "../morpheus"
import "terminus.js" as Terminus

Item {
  id: body

  property var rows: []
  property int sel: 0
  // the disk waiting to be mounted and then opened, "" when none
  property string goAfter: ""
  // the disk being mounted and nothing more, "" when none
  property string mounting: ""
  property bool openVerb: false
  // whether the holder has a details card to show on i / right-click
  property bool details: true
  // a refusal from udisks, said in red where the count would be
  property string note: ""
  property real wheelStep: 120
  readonly property int rowH: 58
  readonly property int headH: 50
  readonly property int footH: 52
  readonly property bool many: body.rows.length > 1
  readonly property int waiting: body.rows.filter(d => d.mount === "").length
  readonly property bool busy: body.goAfter !== "" || body.mounting !== ""
  // what the holder sizes its card to
  readonly property int wantH: body.headH
    + Math.min(6, Math.max(1, body.rows.length)) * body.rowH + body.footH + 8

  signal selected(int i)
  signal mountOne(int i)
  signal inspect(int i)
  signal primary()
  signal justMount()
  signal dismissed()

  Item {
    id: head
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: body.headH

    Text {
      id: heading
      anchors.left: parent.left
      anchors.leftMargin: 18
      anchors.verticalCenter: parent.verticalCenter
      text: body.many ? body.rows.length + " disks were plugged in"
                      : "A disk was plugged in"
      color: Zenon.white
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(17)
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: 18
      anchors.left: heading.right
      anchors.leftMargin: 18
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideLeft
      visible: body.note !== "" || body.many
      text: body.note !== "" ? body.note
        : body.waiting === 0 ? "all mounted"
        : body.waiting + " not mounted"
      color: body.note !== "" ? Zenon.red
        : body.waiting === 0 ? Zenon.green : Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
  }

  ListView {
    id: list
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: foot.top
    anchors.bottomMargin: 4
    clip: true
    model: body.rows
    boundsBehavior: Flickable.DragAndOvershootBounds
    boundsMovement: Flickable.FollowBoundsBehavior
    currentIndex: body.sel
    onCurrentIndexChanged: list.positionViewAtIndex(body.sel, ListView.Contain)
    ElasticScroll { view: list; step: body.wheelStep }

    delegate: Item {
      id: row
      required property var modelData
      required property int index
      width: list.width
      height: body.rowH
      readonly property bool mounted: modelData.mount !== ""

      // the row the keyboard is on, only when there is a choice of rows
      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        radius: Zenon.windowRadius
        visible: body.many && body.sel === row.index
        color: Zenon.border
      }

      Text {
        id: glyph
        anchors.left: parent.left
        anchors.leftMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        text: row.modelData.removable || row.modelData.hotplug ? "" : ""
        color: row.mounted ? Zenon.cyan : Zenon.white
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(20)
      }

      Column {
        anchors.left: glyph.right
        anchors.leftMargin: 14
        anchors.right: act.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: row.modelData.name !== "" ? row.modelData.name
            : (row.modelData.model !== "" ? row.modelData.model
               : Terminus.basename(row.modelData.path))
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Medium
          font.pixelSize: Zenon.px(16)
        }
        // what it is and where it went — the facts you decide on
        Text {
          width: parent.width
          elide: Text.ElideMiddle
          text: [row.modelData.size, row.modelData.fstype,
                 [row.modelData.vendor, row.modelData.model].filter(x => x).join(" "),
                 row.mounted ? "at " + row.modelData.mount : ""]
            .filter(x => x).join("  ·  ")
          color: row.mounted ? Zenon.keyInk : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }

      // Each row's own verb, only when there is more than one row — one
      // disk has the foot's buttons and needs nothing else.
      DialogButton {
        id: act
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        visible: body.many
        label: row.mounted ? "Open" : "Mount"
        ink: row.mounted ? Zenon.cyan : Zenon.white
        onClicked: { body.selected(row.index); body.mountOne(row.index); }
      }

      MouseArea {
        anchors.left: parent.left
        anchors.right: act.visible ? act.left : parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
          body.selected(row.index);
          if (m.button === Qt.RightButton) body.inspect(row.index);
        }
        onDoubleClicked: body.mountOne(row.index)
      }
    }
  }

  Rectangle {
    anchors.bottom: foot.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 1
    color: Zenon.border
  }

  Item {
    id: foot
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: body.footH

    readonly property var only: body.rows.length > 0 ? body.rows[0] : null
    readonly property bool onlyMounted: !!foot.only && foot.only.mount !== ""

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 18
      anchors.right: buttons.left
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: (body.many ? "↑↓ choose   m mount" : "")
        + (body.details ? (body.many ? "   " : "") + "i details" : "")
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }

    Row {
      id: buttons
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8
      DialogButton {
        label: (body.many && body.waiting === 0) || foot.onlyMounted ? "Close" : "Not now"
        ink: Zenon.muted
        onClicked: body.dismissed()
      }
      // the pill's plain Mount: mount it and stay where you are
      DialogButton {
        visible: body.openVerb && !body.many && !foot.onlyMounted
        label: body.mounting !== "" ? "Mounting…" : "Mount"
        ink: Zenon.white
        ready: !body.busy
        onClicked: body.justMount()
      }
      DialogButton {
        visible: !(body.many && body.waiting === 0)
        label: body.many ? "Mount all"
          : foot.onlyMounted ? "Open"
          : body.goAfter !== "" ? (body.openVerb ? "Opening…" : "Mounting…")
          : (body.openVerb ? "Mount & open" : "Mount")
        ink: Zenon.cyan
        primary: true
        ready: !body.busy
        onClicked: body.primary()
      }
    }
  }
}
