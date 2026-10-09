// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// COLORPICKER — a square to drag saturation and brightness in, a bar for the
// hue under it, and the hex beside a swatch of the result, which you can
// also type into. Used twice: the picker's colour tab makes a background with
// it, and the card's look tab makes a tint or a backdrop with it.
//
//     ColorPicker { hex: "#9bbfbf"; onEdited: (h) => … }
//
// `hex` in, `edited` out. Writing `hex` from outside moves the knobs and does
// not emit — only a hand on the control does, so a caller can bind the value
// in without it echoing back.

import QtQuick
import Quickshell.Widgets
import "../morpheus"
import "picasso.js" as Art

Item {
  id: picker

  property string hex: "#9bbfbf"
  property int textSize: 14
  signal edited(string hex)
  // return or escape in the hex field: the caller decides what "done" means
  signal accepted()
  signal cancelled()

  implicitWidth: 260
  implicitHeight: 220

  // Held separately from `hex` because a colour at zero saturation or zero
  // brightness has no hue of its own, and deriving the knobs from the hex
  // alone would throw the hue away the moment you dragged through grey.
  property real h: 0
  property real s: 0
  property real v: 0

  function pull(x) {
    const c = Art.hexToHsv(x);
    // keep the hue where it was when the colour cannot say what it is
    if (c.s > 0 && c.v > 0) picker.h = c.h;
    picker.s = c.s;
    picker.v = c.v;
  }
  onHexChanged: if (Art.hsvToHex(picker.h, picker.s, picker.v) !== Art.normHex(picker.hex)) pull(picker.hex)
  Component.onCompleted: pull(picker.hex)

  // WHAT THE KNOBS SAY NOW, which is what everything in here draws. `hex`
  // is the caller's — an input, bound by whoever holds the colour — and it is
  // never written from inside: assigning it replaced that binding, so after a
  // single drag the card could switch between tint and backdrop and this
  // went on showing the colour it was last dragged to.
  readonly property string shown: Art.hsvToHex(picker.h, picker.s, picker.v)
  // and the field follows it whenever you are not typing in it
  onShownChanged: if (!field.activeFocus) field.text = picker.shown

  function push() {
    picker.edited(picker.shown);
  }

  readonly property int barH: 14
  readonly property int rowH: 30
  readonly property int gap: 10

  // ── saturation across, brightness down ────────────────────────────────
  ClippingRectangle {
    id: sv
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: parent.height - picker.barH - picker.rowH - picker.gap * 2
    radius: 6
    color: Qt.hsva(picker.h, 1, 1, 1)

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "#ffffffff" }
        GradientStop { position: 1; color: "#00ffffff" }
      }
    }
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: "#00000000" }
        GradientStop { position: 1; color: "#ff000000" }
      }
    }

    Rectangle {
      x: picker.s * sv.width - width / 2
      y: (1 - picker.v) * sv.height - height / 2
      width: 14
      height: 14
      radius: 7
      color: picker.shown
      border.width: 2
      border.color: picker.v > 0.55 && picker.s < 0.5 ? "#000000" : "#ffffff"
    }

    MouseArea {
      anchors.fill: parent
      preventStealing: true
      function set(m) {
        picker.s = Math.max(0, Math.min(1, m.x / sv.width));
        picker.v = Math.max(0, Math.min(1, 1 - m.y / sv.height));
        picker.push();
      }
      onPressed: (m) => set(m)
      onPositionChanged: (m) => { if (pressed) set(m); }
    }
  }

  // ── hue ───────────────────────────────────────────────────────────────
  Rectangle {
    id: hue
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: sv.bottom
    anchors.topMargin: picker.gap
    height: picker.barH
    radius: picker.barH / 2
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0 / 6; color: "#ff0000" }
      GradientStop { position: 1 / 6; color: "#ffff00" }
      GradientStop { position: 2 / 6; color: "#00ff00" }
      GradientStop { position: 3 / 6; color: "#00ffff" }
      GradientStop { position: 4 / 6; color: "#0000ff" }
      GradientStop { position: 5 / 6; color: "#ff00ff" }
      GradientStop { position: 6 / 6; color: "#ff0000" }
    }

    Rectangle {
      x: picker.h * hue.width - width / 2
      anchors.verticalCenter: parent.verticalCenter
      width: 16
      height: 16
      radius: 8
      color: Qt.hsva(picker.h, 1, 1, 1)
      border.width: 2
      border.color: "#ffffff"
    }

    MouseArea {
      anchors.fill: parent
      anchors.margins: -4
      preventStealing: true
      function set(m) {
        picker.h = Math.max(0, Math.min(0.9999, (m.x - 4) / hue.width));
        picker.push();
      }
      onPressed: (m) => set(m)
      onPositionChanged: (m) => { if (pressed) set(m); }
    }
  }

  // ── the result, and its name ──────────────────────────────────────────
  Row {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    height: picker.rowH
    spacing: 10

    Rectangle {
      width: picker.rowH
      height: picker.rowH
      radius: 5
      color: picker.shown
      border.width: 1
      border.color: Zenon.border
    }

    Rectangle {
      width: 110
      height: picker.rowH
      radius: 5
      color: Zenon.wash(0.05)
      border.width: 1
      border.color: field.activeFocus ? Zenon.cyan : Zenon.border

      TextInput {
        id: field
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        // set, not bound: typing replaces it, and a binding that typing
        // replaced stopped following the drags after the first Return
        Component.onCompleted: field.text = picker.shown
        color: Zenon.white
        selectionColor: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.4)
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: picker.textSize
        maximumLength: 7
        selectByMouse: true
        onTextEdited: {
          const h = Art.normHex(field.text);
          if (h !== "" && field.text.replace(/^#/, "").length === 6) {
            picker.pull(h);
            picker.edited(h);
          }
        }
        Keys.onReturnPressed: { field.text = picker.shown; picker.accepted(); }
        Keys.onEnterPressed: { field.text = picker.shown; picker.accepted(); }
        Keys.onEscapePressed: { field.text = picker.shown; picker.cancelled(); }
        onActiveFocusChanged: if (!activeFocus) field.text = picker.shown
      }
    }
  }
}
