// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE PASSWORD FIELD — one, for the panel and the window alike.
//
// Calypso's field, glyph for glyph: the red lock breathing in its glow while
// the field waits, pink dots for what has been typed (the COUNT is the model,
// the characters never reach the scene graph), the caret after them, a red
// wash and a shake when sudo says no. A password prompt that looked different
// in two places would be two prompts.
//
// It draws; it does not listen. Whoever holds keyboard focus hands key
// events to `key()`, which is the one place typing is understood.

import QtQuick
import "../morpheus"
import "."

Item {
  id: field
  // Text size over the panel's: the window reads 2px larger.
  property int grow: 0

  property string pw: ""
  // sudo refused the last one. Cleared by the first key typed after it.
  property bool failed: false
  // What the password is for, under the message — never ask for a password
  // without saying what it will do.
  property string purpose: ""
  signal submitted(string password)
  signal cancelled()

  implicitHeight: 64

  // Everything a key can mean here. Returns whether it was taken.
  function key(event) {
    const k = event.key;
    if (k === Qt.Key_CapsLock) { CapsLock.read(); return true; }
    if (k === Qt.Key_Escape) { field.pw = ""; field.cancelled(); return true; }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (field.pw === "") return true;
      const p = field.pw;
      field.pw = "";
      field.submitted(p);
      return true;
    }
    if (k === Qt.Key_Backspace) {
      // Array.from: a codepoint past the BMP is two UTF-16 units
      const c = Array.from(field.pw); c.pop(); field.pw = c.join("");
      return true;
    }
    if (event.text && event.text.length > 0
        && !(event.modifiers & Qt.ControlModifier)
        && !(event.modifiers & Qt.MetaModifier)) {
      field.failed = false;
      field.pw += event.text;
      return true;
    }
    return false;
  }

  // The release, which the surfaces hand on as they hand on the press:
  // Caps Lock turning OFF only lands on the release — see morpheus/CapsLock.
  function keyUp(event) {
    if (event.key === Qt.Key_CapsLock) { CapsLock.read(); return true; }
    return false;
  }

  // Asked when a password is asked for: caps may already be on.
  Connections {
    target: Ceres
    function onAuthRequested() { CapsLock.read(); }
  }

  Item {
    id: entry
    width: parent.width
    height: parent.height

    Rectangle {
      anchors.fill: parent
      color: field.failed ? "#4de78284" : "transparent"
      Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
    }

    Column {
      id: pwCol
      anchors.centerIn: parent
      spacing: 4

      Row {
        id: pwRow
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 5

        Item {
          id: glyphBox
          anchors.verticalCenter: parent.verticalCenter
          visible: field.pw.length === 0
          implicitWidth: lockGlyph.implicitWidth + 9
          implicitHeight: lockGlyph.implicitHeight
          readonly property bool lit: field.visible && field.pw.length === 0

          Text {
            id: lockGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: Zenon.red
            font.family: Zenon.face
            font.pixelSize: fieldMsg.font.pixelSize
          }

          Glow {
            z: -1
            anchors.centerIn: lockGlyph
            width: lockGlyph.implicitHeight * 4.2
            height: width
            ink: Zenon.red
            sourceW: lockGlyph.implicitHeight * 1.09
            sourceH: lockGlyph.implicitHeight * 1.09
            soft: 48
            visible: glyphBox.lit
            opacity: glyphBox.glowPulse
          }

          property real glowPulse: 0.40
          SequentialAnimation on glowPulse {
            running: glyphBox.lit
            loops: Animation.Infinite
            NumberAnimation { to: 1.0; duration: 1300; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.40; duration: 1300; easing.type: Easing.InOutSine }
          }
        }

        Text {
          id: fieldMsg
          anchors.verticalCenter: parent.verticalCenter
          visible: field.pw.length === 0
          text: field.failed ? "wrong password" : "input your password"
          color: field.failed ? Zenon.red : Zenon.muted
          font.family: Zenon.face
          font.pixelSize: 14 + field.grow
        }

        Repeater {
          model: field.pw.length
          delegate: Text {
            anchors.verticalCenter: parent.verticalCenter
            // U+F09DE, past the BMP, written as its surrogate pair
            text: "󰧞"
            color: Zenon.pink
            font.family: Zenon.face
            font.pixelSize: 15 + field.grow
          }
        }

        Rectangle {
          id: caret
          readonly property bool on: field.pw.length > 0
          anchors.verticalCenter: parent.verticalCenter
          width: 3
          height: 20
          radius: 1
          color: Zenon.pink
          opacity: 0.25
          visible: caret.on
          SequentialAnimation on opacity {
            running: caret.on
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 550; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.25; duration: 550; easing.type: Easing.InOutSine }
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: field.purpose !== ""
        text: field.purpose
        color: Zenon.keyInk
        font.family: Zenon.face
        font.pixelSize: 12 + field.grow
      }
    }

    // Just past the dots, clear of the centred row so it never shifts it.
    // Plain x/y rather than anchors — see the layer-window anchor note.
    CapsGlyph {
      shown: field.visible
      size: 15 + field.grow
      x: (entry.width + pwRow.width) / 2 + 10
      y: pwCol.y + pwRow.y + (pwRow.height - height) / 2
    }

    SequentialAnimation {
      running: field.failed
      NumberAnimation { target: entry; property: "x"; to:  9; duration: 55 }
      NumberAnimation { target: entry; property: "x"; to: -7; duration: 90 }
      NumberAnimation { target: entry; property: "x"; to:  4; duration: 80 }
      NumberAnimation { target: entry; property: "x"; to:  0; duration: 70 }
    }
  }
}
