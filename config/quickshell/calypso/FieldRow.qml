// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE FIELD OF AN ITEM — its label small over its value, its buttons at the
// row's end: Copy always; Reveal for a secret; Open for a website. A click
// on the value copies it (1Password's habit), a right click is its menu
// (win.fieldMenu), outlined while that menu is up (terminus' HeldRing).
//
// A secret shows as dots, as many as it has characters, until revealed. A
// one-time password shows the code, live, beside its TotpRing.

import QtQuick
import "../morpheus"
import "../terminus"
import "calypso.js" as C

Item {
  id: row
  property var win: null
  property var field: null
  property bool ruled: false
  readonly property bool secret: !!row.field && row.field.secret && row.field.kind !== "totp"
  readonly property bool isTotp: !!row.field && row.field.kind === "totp"
  readonly property string shown: !row.win || !row.field ? ""
    : row.isTotp ? (row.win.code ? C.codeShown(row.win.code.code) : "••• •••")
    : row.secret ? (row.win.revealed[row.field.ref] !== undefined ? row.win.revealed[row.field.ref] : C.dots(row.field.length))
    : row.field.value
  readonly property bool open: !!row.win && !!row.field && row.win.revealed[row.field.ref] !== undefined
  readonly property bool justCopied: !!row.win && !!row.field && row.win.copiedRef === row.field.ref

  implicitHeight: col.implicitHeight + 22

  Rectangle {
    visible: row.ruled
    x: 16
    width: parent.width - 32
    height: 1
    color: Zenon.border
  }

  Column {
    id: col
    anchors.left: parent.left
    anchors.leftMargin: 18
    anchors.right: acts.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 3
    Text {
      text: row.field ? row.field.label : ""
      color: row.justCopied ? Zenon.cyan : Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
      Behavior on color { ColorAnimation { duration: Zenon.fast } }
    }
    Row {
      spacing: 10
      width: parent.width
      Text {
        id: value
        width: Math.min(implicitWidth, parent.width - (ring.visible ? ring.width + 10 : 0))
        anchors.verticalCenter: parent.verticalCenter
        text: row.shown
        elide: row.field && row.field.kind === "url" ? Text.ElideMiddle : Text.ElideRight
        wrapMode: row.open && row.field && row.field.value === "" && row.shown.indexOf("\n") >= 0 ? Text.WrapAnywhere : Text.NoWrap
        maximumLineCount: 12
        color: row.isTotp ? Zenon.cyan
          : row.field && row.field.kind === "url" ? Zenon.blue
          : row.secret && !row.open ? Zenon.accentSoft : Zenon.ink
        font.family: row.secret || row.isTotp ? Zenon.faceMono : Zenon.face
        font.weight: row.isTotp ? Font.Bold : Zenon.weight
        font.pixelSize: row.isTotp ? Zenon.px(20) : Zenon.px(15)
        font.letterSpacing: row.isTotp ? 1.5 : row.secret && !row.open ? 1 : 0
        font.features: { "tnum": 1 }
      }
      TotpRing {
        id: ring
        visible: row.isTotp && !!row.win && !!row.win.code
        anchors.verticalCenter: parent.verticalCenter
        period: row.win && row.win.code ? row.win.code.period : 30
        running: visible
        size: 18
        onRolled: if (row.win) row.win.loadCode()
      }
    }
  }

  // the value copies on a click; a right click is the field's menu
  MouseArea {
    anchors.fill: col
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: (m) => {
      if (m.button === Qt.RightButton) {
        const p = mapToItem(row.win.stageItem, m.x, m.y);
        row.win.fieldMenu(row.field, p.x, p.y);
      } else row.win.copyField(row.field);
    }
  }

  Row {
    id: acts
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    FieldAct {
      visible: !!row.field && row.field.kind === "url"
      glyph: ""
      tip: "Open in the browser"
      tips: row.win ? row.win.tipsItem : null
      onClicked: row.win.openUrl(row.field.value)
    }
    FieldAct {
      visible: row.secret
      glyph: row.open ? "" : ""
      tip: row.open ? "Hide" : "Reveal"
      on: row.open
      tips: row.win ? row.win.tipsItem : null
      onClicked: row.win.revealField(row.field)
    }
    FieldAct {
      glyph: row.justCopied ? "" : "\u{F018F}"
      tip: row.secret || row.isTotp ? "Copy — cleared from the clipboard in 30 s" : "Copy"
      on: row.justCopied
      tips: row.win ? row.win.tipsItem : null
      onClicked: row.win.copyField(row.field)
    }
  }

  HeldRing { anchors.fill: parent; anchors.margins: 3; radius: Zenon.windowRadius; on: !!row.win && !!row.field && row.win.menuHeld === "f:" + row.field.ref }
}
