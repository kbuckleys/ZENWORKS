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
import Quickshell
import Quickshell.Io
import "../morpheus"
import "."

Item {
  id: field
  // Text size over the panel's: the window reads 2px larger.
  property int grow: 0
  // the red wash a wrong password lays behind the field: square and strong
  // by default (ceres' band); rounded and softer for a field that sits in a
  // card or a rounded box of its own (calypso)
  property real washRadius: 0
  // the answer is being checked: the prompt, lock and dots give way to the
  // working dots — nothing to type while it is (user, 2026-10-12: no
  // "input your master password" during the unlock)
  property bool busy: false

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
    // nothing typed in while the last answer is checked
    if (field.busy) return true;
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (field.pw === "") return true;
      const p = field.pw;
      field.pw = "";
      field.submitted(p);
      return true;
    }
    // PASTED, not typed: a token from a password manager, or a long
    // passphrase. Its first line only — a copied line often brings its
    // newline along, and a password never holds one.
    if (event.matches(StandardKey.Paste)) {
      // Quickshell's own read first; on Wayland it can come back empty while
      // another client owns the clipboard (a token copied in the browser,
      // 2026-10-11) — then wl-paste is asked, and its first line appended
      const t = String(Quickshell.clipboardText || "").split(/\r?\n/)[0];
      if (t !== "") { field.failed = false; field.pw += t; }
      else if (!paster.running) paster.running = true;
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

  // Asked when a password is asked for: caps may already be on. The holder
  // says who asks — ceres hands its singleton (`authSource: Ceres`), and its
  // authRequested reads the key; delphi, whose questions come from git and
  // ssh, calls asked() as its card opens. Not named here, so a holder outside
  // ceres does not start ceres just by showing the field.
  property var authSource: null
  function asked() { CapsLock.read(); }
  Connections {
    target: field.authSource
    ignoreUnknownSignals: true
    function onAuthRequested() { CapsLock.read(); }
  }
  // what it says while empty: sudo's password by default; delphi's cards
  // ask for a token, a key's passphrase, a host's password
  property string prompt: "input your password"

  FontMetrics { id: dotFm; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: 15 + field.grow }
  readonly property int maxDots: Math.max(8, Math.floor((field.width - 48) / (dotFm.advanceWidth("\u{F09DE}") + 5)))

  Item {
    id: entry
    width: parent.width
    height: parent.height

    Rectangle {
      anchors.fill: parent
      radius: field.washRadius
      color: field.failed ? Zenon.alpha(Zenon.red, field.washRadius > 0 ? 0.16 : 0.3) : Zenon.alpha(Zenon.red, 0)
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

        Working {
          anchors.verticalCenter: parent.verticalCenter
          visible: field.busy
          running: field.busy && field.visible
          ink: Zenon.pink
          dot: 6
          gap: 5
        }

        Item {
          id: glyphBox
          anchors.verticalCenter: parent.verticalCenter
          visible: field.pw.length === 0 && !field.busy
          implicitWidth: lockGlyph.implicitWidth + 9
          implicitHeight: lockGlyph.implicitHeight
          readonly property bool lit: field.visible && field.pw.length === 0 && !field.busy

          Text {
            id: lockGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: Zenon.red
            font.family: Zenon.face
            font.weight: Zenon.weight
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
          visible: field.pw.length === 0 && !field.busy
          text: field.failed ? "wrong password" : field.prompt
          color: field.failed ? Zenon.red : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: 14 + field.grow
        }

        // As many dots as fit the field, never more: a long passphrase ran
        // its dots out past the field's ends (calypso's lock, 2026-10-12).
        // Past that the row stays full and the caret keeps blinking.
        Repeater {
          model: field.busy ? 0 : Math.min(field.pw.length, field.maxDots)
          delegate: Text {
            anchors.verticalCenter: parent.verticalCenter
            // U+F09DE, past the BMP, written as its surrogate pair
            text: "󰧞"
            color: Zenon.pink
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: 15 + field.grow
          }
        }

        Rectangle {
          id: caret
          readonly property bool on: field.pw.length > 0 && !field.busy
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

      // held inside the field, cut short at its end: a backend's raw error
      // once ran out past both edges (calypso, 2026-10-12)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, field.width - 32)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        visible: field.purpose !== ""
        text: field.purpose
        color: Zenon.keyInk
        font.family: Zenon.face
        font.weight: Zenon.weight
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

  // the clipboard asked of wl-paste, when Quickshell's read had nothing; what
  // it hands back is held only in `pw`, as typed characters are
  Process {
    id: paster
    command: ["wl-paste", "--no-newline", "--type", "text/plain"]
    stdout: StdioCollector {
      id: pasted
      onStreamFinished: {
        const t = String(pasted.text || "").split(/\r?\n/)[0];
        if (t !== "") { field.failed = false; field.pw += t; }
      }
    }
  }
}
