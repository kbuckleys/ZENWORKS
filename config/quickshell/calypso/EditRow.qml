// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE FIELD, BEING CHANGED — the editor's row: its label (typed, for a field
// of your own) over terminus' BulkField, its buttons at the end.
//
// A secret is masked until shown. One the window was never given (`known`
// false) is empty: typed over, the new one replaces it; Reveal fetches it
// first. A password's row has the generator's dice and its strength under
// it; a one-time password's has Scan (a QR code off the screen) and Paste.
// Copying out of a secret goes through calypso's own copy (sensitive,
// cleared after), never straight onto the clipboard.

import QtQuick
import "../morpheus"
import "../terminus"

Item {
  id: row
  property var win: null
  property string label: ""
  property bool labelEditable: false
  property string hint: ""
  property bool secret: false
  property bool known: true
  property bool gen: false
  property bool totp: false
  property bool removable: false
  property bool ruled: false
  // a field of your own may be marked hidden (a secret) or not
  property bool hideToggle: false
  property alias text: box.text
  property alias labelText: labelBox.text
  property bool showing: !row.secret
  signal edited(string text)
  signal labelEdited(string text)
  signal revealWanted()
  signal generateWanted()
  signal scanWanted()
  signal removed()
  signal hiddenToggled()
  signal tabbed()

  function claim() { box.claim(); }

  // a password's strength, asked of the daemon as it is typed
  property var strength: null
  Timer {
    id: rate
    interval: 250
    onTriggered: {
      if (!row.gen || box.text === "" || !row.win) { row.strength = null; return; }
      row.win.mgr.call("strength", null, { text: box.text }, (ok, r) => { if (ok) row.strength = r; });
    }
  }

  implicitHeight: col.implicitHeight + 20

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
    anchors.leftMargin: 16
    anchors.right: acts.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 5

    Text {
      visible: !row.labelEditable
      text: row.label
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
    BulkField {
      id: labelBox
      visible: row.labelEditable
      width: Math.min(parent.width, 260)
      textSize: Zenon.px(12)
      ghost: "Label"
      onTextChanged: row.labelEdited(text)
      onTabbed: box.claim()
    }
    BulkField {
      id: box
      width: parent.width
      textSize: Zenon.px(15)
      ghost: !row.known ? "Kept as it is — type to replace it" : row.hint
      masked: row.secret && !row.showing
      mono: row.secret || row.totp
      copyHook: row.secret && row.win ? (t) => row.win.copyText(t, true) : null
      onTextChanged: { row.edited(text); if (row.gen) rate.restart(); }
      onTabbed: row.tabbed()
    }
    // how strong the password typed is
    Row {
      visible: row.gen && !!row.strength && box.text !== ""
      spacing: 10
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 140
        height: 4
        radius: 2
        color: Zenon.wash(0.08)
        Rectangle {
          readonly property var s: row.strength || { score: 0 }
          height: parent.height
          radius: 2
          width: parent.width * (0.12 + s.score * 0.22)
          color: s.score >= 3 ? Zenon.green : s.score >= 2 ? Zenon.yellow : Zenon.red
          Behavior on width { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: row.strength ? row.strength.word : ""
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(11)
      }
    }
  }

  Row {
    id: acts
    anchors.right: parent.right
    anchors.rightMargin: 10
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 10 + (row.gen && !!row.strength && box.text !== "" ? 14 : 0)
    spacing: 2
    FieldAct {
      visible: row.totp
      glyph: "\u{F0433}"
      tip: "Scan a QR code on the screen"
      tips: row.win ? row.win.tipsItem : null
      onClicked: row.scanWanted()
    }
    FieldAct {
      visible: row.gen
      glyph: "\u{F076E}"
      tip: "Generate a password"
      tips: row.win ? row.win.tipsItem : null
      onClicked: row.generateWanted()
    }
    FieldAct {
      visible: row.secret
      glyph: row.showing ? "" : ""
      tip: !row.known ? "Show the one kept" : row.showing ? "Hide" : "Show"
      on: row.showing
      tips: row.win ? row.win.tipsItem : null
      onClicked: { if (!row.known) row.revealWanted(); else row.showing = !row.showing; }
    }
    FieldAct {
      visible: row.hideToggle
      glyph: row.secret ? "" : ""
      tip: row.secret ? "Hidden — click to make it plain" : "Plain — click to hide it"
      on: row.secret
      tips: row.win ? row.win.tipsItem : null
      onClicked: row.hiddenToggled()
    }
    FieldAct {
      visible: row.removable
      glyph: "\u{F0A7A}"
      ink: Zenon.red
      tip: "Remove"
      tips: row.win ? row.win.tipsItem : null
      onClicked: row.removed()
    }
  }
}
