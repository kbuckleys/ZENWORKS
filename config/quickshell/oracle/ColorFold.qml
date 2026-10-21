// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A COLOR ROW, unfolded — Accent color opened (user, 2026-10-20: "a setting
// where i can manually define the accent color, with a color picker").
//
// picasso's ColorPicker (the one the background card and the color maker
// use), the theme's own accent and its other hues as swatches to start
// from, the suite's screen picker (picasso's eyedropper) for any color on
// screen, and the way back to the theme's. A drag paints its own swatch at
// once; the shell takes the color once the hand rests (`settle`), since a
// new accent re-colors every binding in the shell.
//
// Loaded by URL from OracleWindow, not named as a type (see ComputerPanel).

import QtQuick
import "oracle.js" as Ora
import "../morpheus"
import "../morpheus/controls" as Controls
import "../terminus" as Term
import "../picasso" as Pic

Item {
  id: cf
  // the panel's palette, handed in rather than reached for
  property string face: Zenon.face
  property color fgColor: Zenon.white
  property color dimColor: Zenon.accentMuted
  property color highlight: Zenon.cyan
  // the setting it edits
  property string key: "accentColor"

  readonly property string value: (Oracle.revision, String(Oracle.get(cf.key) || ""))
  // what the picker shows: a drag not yet handed on, else what is worn
  property string pending: ""
  readonly property string shown: cf.pending !== "" ? cf.pending
    : cf.value !== "" ? cf.value : Zenon.hex(Zenon.themeAccent)

  function choose(h) {
    cf.pending = Ora.coerce({ type: "color" }, h);
    settle.restart();
  }
  Timer {
    id: settle
    interval: 180
    onTriggered: {
      if (cf.pending !== "") Oracle.set(cf.key, cf.pending);
      cf.pending = "";
    }
  }
  Connections {
    target: Pic.Picasso
    function onColorPicked(into, hex) {
      if (into !== "oracle:" + cf.key) return;
      settle.stop();
      cf.pending = "";
      Oracle.set(cf.key, hex);
    }
  }
  function useTheme() {
    settle.stop();
    cf.pending = "";
    Oracle.reset(cf.key);
  }

  // what is shown is the theme's own accent, set or not
  readonly property bool isTheme: cf.shown.toLowerCase() === Zenon.hex(Zenon.themeAccent).toLowerCase()

  // the theme's own hues, as places to start from: its accent first
  readonly property var swatches: [Zenon.themeAccent, Zenon.blue, Zenon.magenta, Zenon.pink,
                                   Zenon.red, Zenon.yellow, Zenon.sand, Zenon.green]
    .map((c) => Zenon.hex(c)).filter((h, i, a) => a.indexOf(h) === i)

  implicitHeight: frame.height + 24

  // in the list frame, as the other folds' bodies are (user, 2026-10-20),
  // and across it (user: "make use of that extra horizontal space"): the
  // color as a swatch with its starting points and tools on one side, the
  // picker on the other, the pair centered in the frame
  Item {
    id: frame
    x: 24
    y: 6
    width: cf.width - 48
    height: body.height + 36
    Controls.ListFrame { anchors.fill: parent }
  }

  readonly property int pickerH: 250

  Row {
    id: body
    parent: frame
    anchors.horizontalCenter: parent.horizontalCenter
    y: 18
    height: cf.pickerH
    spacing: 28

    // ── the picker ──
    Pic.ColorPicker {
      width: Math.min(520, frame.width - 36 - body.spacing - side.width)
      height: cf.pickerH
      showField: false
      hex: cf.shown
      onEdited: (h) => cf.choose(h)
    }

    // ── the color, and where to start from ──
    // Every line of it as wide as the swatch, so the swatch, the theme's
    // colors and the two buttons share both edges (user capture).
    Column {
      id: side
      width: Math.min(300, (frame.width - 36 - body.spacing) * 0.4)
      height: parent.height
      spacing: 14

      // the swatch: what is worn (or being dragged to), and its hex — the
      // field to type one into
      Rectangle {
        id: big
        width: parent.width
        height: parent.height - starts.height - tools.height - side.spacing * 2
        radius: Zenon.windowRadius
        color: cf.shown
        border.width: 1
        border.color: Zenon.alpha(Zenon.ink, 0.12)
        // the theme's darker or lighter end, whichever reads on it
        readonly property color type: {
          const g = Zenon.ground, k = Zenon.ink;
          const dark = Zenon.lum(g) <= Zenon.lum(k);
          return Zenon.lum(big.color) > 0.35 ? (dark ? g : k) : (dark ? k : g);
        }
        MouseArea { anchors.fill: parent; onClicked: hexField.forceActiveFocus() }
        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: 14
          spacing: 2
          TextInput {
            id: hexField
            width: parent.width
            color: big.type
            selectionColor: Zenon.alpha(big.type, 0.25)
            selectedTextColor: big.type
            font.family: Zenon.faceMono
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(18)
            maximumLength: 7
            selectByMouse: true
            // set, not bound: typing replaces it (see ColorPicker's field)
            Component.onCompleted: hexField.text = cf.shown
            Connections {
              target: cf
              function onShownChanged() { if (!hexField.activeFocus) hexField.text = cf.shown; }
            }
            onTextEdited: {
              const h = Ora.coerce({ type: "color" }, "#" + hexField.text.replace(/^#/, ""));
              if (h !== "") cf.choose(h);
            }
            Keys.onReturnPressed: hexField.focus = false
            Keys.onEnterPressed: hexField.focus = false
            Keys.onEscapePressed: hexField.focus = false
            onActiveFocusChanged: if (!activeFocus) hexField.text = cf.shown
          }
          Text {
            text: cf.value === "" && cf.pending === "" ? "The theme's own" : "Your own"
            color: big.type
            opacity: 0.7
            font.family: cf.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
        }
        Term.HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: hexField.activeFocus }
      }

      // spread edge to edge across the swatch's width
      Row {
        id: starts
        width: parent.width
        height: 26
        spacing: cf.swatches.length > 1
          ? (starts.width - cf.swatches.length * 26) / (cf.swatches.length - 1) : 0
        Repeater {
          model: cf.swatches
          delegate: Rectangle {
            required property string modelData
            required property int index
            width: 26
            height: 26
            radius: 13
            color: modelData
            border.width: 2
            border.color: modelData === cf.shown ? cf.fgColor : Zenon.alpha(Zenon.ink, 0.12)
            scale: swMa.pressed ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
            MouseArea {
              id: swMa
              anchors.fill: parent
              onClicked: index === 0 ? cf.useTheme() : cf.choose(parent.modelData)
            }
          }
        }
      }

      // the two buttons share the swatch's width
      Row {
        id: tools
        width: parent.width
        spacing: 8
        // any color on screen: the suite's own picker (picasso), whose
        // click comes back here rather than to the clipboard
        DialogButton {
          width: (tools.width - tools.spacing) / 2
          label: "\u{F020A}  Picker"
          onClicked: Pic.Picasso.pickFor("oracle:" + cf.key)
        }
        // back to the theme's accent; dimmed while the color already is it
        // (user, 2026-10-21) — a custom hex that happens to match counts too
        DialogButton {
          width: (tools.width - tools.spacing) / 2
          label: "\u{F0450}  Reset"
          ready: !cf.isTheme
          onClicked: if (!cf.isTheme) cf.useTheme()
        }
      }
    }
  }
}
