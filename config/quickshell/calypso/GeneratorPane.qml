// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE PASSWORD GENERATOR — on a sheet, from the sidebar or from a password
// field's dice. Characters, words or a PIN (terminus' Segments), how long
// (terminus' PrefSlider), what goes in (picasso's Switch); the password
// large in the middle, its strength under it. Made by the daemon
// (calypso/core/generate.py, the OS's randomness), copied the way every
// secret here is (kept out of the clipboard history, cleared after).
//
// `using`: a field asked for it — Use puts the password there.

import QtQuick
import "../morpheus"
import "../terminus"
import "../picasso"
import "../ceres"
import "calypso.js" as C

Item {
  id: gen
  property var win: null
  property bool using: false
  signal used(string value)
  signal closed()

  property var opts: ({ mode: "chars", length: 20, upper: true, lower: true, digits: true, symbols: true,
                        ambiguous: false, words: 4, separator: "-", capitalize: true, number: true })
  property string value: ""
  property real bits: 0
  property string err: ""
  property bool wordsMissing: false
  readonly property var st: gen.bits >= 80 ? { word: "very strong", ink: "green", f: 1 }
    : gen.bits >= 60 ? { word: "strong", ink: "green", f: 0.75 }
    : gen.bits >= 40 ? { word: "fair", ink: "yellow", f: 0.5 }
    : gen.bits >= 28 ? { word: "weak", ink: "yellow", f: 0.3 } : { word: "very weak", ink: "red", f: 0.12 }

  implicitHeight: col.implicitHeight + 40

  function set(k, v) {
    const o = Object.assign({}, gen.opts);
    o[k] = v;
    gen.opts = o;
    gen.make();
  }
  function make() {
    if (!gen.win) return;
    gen.err = "";
    gen.win.mgr.call("generate", null, { opts: gen.opts }, (ok, r, e) => {
      if (ok) { gen.value = r.value; gen.bits = r.bits; gen.wordsMissing = false; return; }
      gen.value = "";
      gen.bits = 0;
      gen.wordsMissing = !!e && e.kind === "words";
      gen.err = gen.wordsMissing ? "" : C.failWords(e);
    });
  }
  function copy() {
    if (gen.value === "") return;
    gen.win.mgr.call("copySecret", null, { text: gen.value, clear: gen.win.mgr.clearAfter }, (ok) => {
      if (ok) gen.win.say("Copied the password" + (gen.win.mgr.clearAfter > 0 ? " — cleared in " + gen.win.mgr.clearAfter + " s" : ""));
    });
  }
  function key(e) {
    if (e.key === Qt.Key_Escape) { gen.closed(); return true; }
    if (e.key === Qt.Key_Space || e.key === Qt.Key_R) { gen.make(); return true; }
    if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_C) { gen.copy(); return true; }
    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
      if (gen.using && gen.value !== "") gen.used(gen.value); else gen.copy();
      return true;
    }
    if (e.key === Qt.Key_Left || e.key === Qt.Key_Right) {
      const k = gen.opts.mode === "words" ? "words" : "length";
      const lo = gen.opts.mode === "words" ? 3 : gen.opts.mode === "pin" ? 4 : 8;
      const hi = gen.opts.mode === "words" ? 10 : gen.opts.mode === "pin" ? 12 : 64;
      gen.set(k, Math.max(lo, Math.min(hi, gen.opts[k] + (e.key === Qt.Key_Left ? -1 : 1))));
      return true;
    }
    return false;
  }
  Component.onCompleted: gen.make()

  Column {
    id: col
    x: 22
    y: 20
    width: parent.width - 44
    spacing: 16

    Row {
      spacing: 12
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F076E}"
        color: Zenon.cyan
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(18)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Password generator"
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(19)
      }
    }

    // the password itself
    Rectangle {
      width: parent.width
      height: Math.max(78, shown.implicitHeight + 34)
      radius: Zenon.windowRadius + 4
      color: Zenon.wash(0.04)
      border.width: 1
      border.color: Zenon.border
      Text {
        id: shown
        anchors.centerIn: parent
        width: parent.width - 40
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WrapAnywhere
        textFormat: Text.StyledText
        // digits and symbols in their own colours, as 1Password sets them
        text: {
          let out = "";
          for (const ch of Array.from(gen.value)) {
            const e = ch.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            out += /[0-9]/.test(ch) ? "<font color='" + Zenon.blue + "'>" + e + "</font>"
              : /[A-Za-z]/.test(ch) ? e : "<font color='" + Zenon.pink + "'>" + e + "</font>";
          }
          return out;
        }
        color: Zenon.ink
        font.family: Zenon.faceMono
        font.weight: Font.DemiBold
        font.pixelSize: Zenon.px(gen.value.length > 40 ? 16 : 21)
      }
      Column {
        anchors.centerIn: parent
        visible: gen.wordsMissing || gen.err !== ""
        spacing: 8
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: gen.wordsMissing ? "Words need a word list — the words package" : gen.err
          color: gen.wordsMissing ? Zenon.muted : Zenon.red
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        BusyButton {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: gen.wordsMissing
          label: "Install words"
          ink: Zenon.cyan
          busy: !!Ceres.installing && Ceres.installing.pkg === "words"
          busyText: "Installing…"
          onClicked: Ceres.install("words", "for calypso's passphrases", (ok) => { if (ok) gen.make(); })
        }
      }
    }
    // how strong
    Item {
      width: parent.width
      height: 16
      Rectangle {
        anchors.left: parent.left
        anchors.right: strengthWord.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 4
        radius: 2
        color: Zenon.wash(0.08)
        Rectangle {
          height: parent.height
          radius: 2
          width: parent.width * gen.st.f
          color: Zenon[gen.st.ink]
          Behavior on width { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        }
      }
      Text {
        id: strengthWord
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: gen.value === "" ? "" : gen.st.word + "  ·  " + Math.round(gen.bits) + " bits"
        color: Zenon[gen.st.ink]
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
    }

    Segments {
      anchors.horizontalCenter: parent.horizontalCenter
      options: [["chars", "Characters"], ["words", "Words"], ["pin", "PIN"]]
      current: gen.opts.mode
      onChose: (v) => gen.set("mode", v)
    }

    PrefSlider {
      width: parent.width
      label: gen.opts.mode === "words" ? "Words" : "Length"
      labelW: 90
      from: gen.opts.mode === "words" ? 3 : gen.opts.mode === "pin" ? 4 : 8
      to: gen.opts.mode === "words" ? 10 : gen.opts.mode === "pin" ? 12 : 64
      value: gen.opts.mode === "words" ? gen.opts.words : gen.opts.length
      wheelStep: 1
      readout: String(Math.round(value))
      onMoved: (v) => gen.set(gen.opts.mode === "words" ? "words" : "length", Math.round(v))
    }

    // what goes in
    Grid {
      visible: gen.opts.mode === "chars"
      width: parent.width
      columns: 2
      rowSpacing: 4
      columnSpacing: 20
      Switch { width: (col.width - 20) / 2; label: "Capital letters"; on: gen.opts.upper; onToggled: gen.set("upper", !gen.opts.upper) }
      Switch { width: (col.width - 20) / 2; label: "Small letters"; on: gen.opts.lower; onToggled: gen.set("lower", !gen.opts.lower) }
      Switch { width: (col.width - 20) / 2; label: "Digits"; on: gen.opts.digits; onToggled: gen.set("digits", !gen.opts.digits) }
      Switch { width: (col.width - 20) / 2; label: "Symbols"; on: gen.opts.symbols; onToggled: gen.set("symbols", !gen.opts.symbols) }
      Switch { width: (col.width - 20) / 2; label: "Look-alikes (l 1 I O 0)"; on: gen.opts.ambiguous; onToggled: gen.set("ambiguous", !gen.opts.ambiguous) }
    }
    Column {
      visible: gen.opts.mode === "words"
      width: parent.width
      spacing: 8
      Grid {
        width: parent.width
        columns: 2
        columnSpacing: 20
        Switch { width: (col.width - 20) / 2; label: "Capitalise"; on: gen.opts.capitalize; onToggled: gen.set("capitalize", !gen.opts.capitalize) }
        Switch { width: (col.width - 20) / 2; label: "A digit in one"; on: gen.opts.number; onToggled: gen.set("number", !gen.opts.number) }
      }
      Row {
        spacing: 12
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Between words"
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        Segments {
          anchors.verticalCenter: parent.verticalCenter
          options: [["-", "‑ hyphen"], [".", ". dot"], ["_", "_ under"], [" ", "space"]]
          current: gen.opts.separator
          textSize: Zenon.px(12)
          onChose: (v) => gen.set("separator", v)
        }
      }
    }

    Row {
      anchors.right: parent.right
      spacing: 8
      DialogButton { label: "Close"; onClicked: gen.closed() }
      DialogButton { label: "New one"; onClicked: gen.make() }
      DialogButton { label: "Copy"; ink: gen.using ? Zenon.muted : Zenon.cyan; primary: !gen.using; ready: gen.value !== ""; onClicked: gen.copy() }
      DialogButton { visible: gen.using; label: "Use it"; ink: Zenon.cyan; primary: true; ready: gen.value !== ""; onClicked: gen.used(gen.value) }
    }
  }
}
