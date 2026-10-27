// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PROPERTIES of a file or directory in plato's tree: terminus' own card
// A COLOR, CHOSEN (user, 2026-10-27): the #hex under the cursor opened in
// picasso's ColorPicker — the one the background card, the color maker and
// oracle's accent use — with the suite's screen eyedropper beside it. Use
// it writes the color back over the one it opened on, keeping an
// #rrggbbaa's alpha (bridge colorAt/setColor). Only ever opened on a color.

import QtQuick
import "../../morpheus"
import "../../picasso" as Pic

PlatoSheet {
  id: sheet
  property var client: null
  // what openFor sets it to; the theme's accent until then
  property string hex: Zenon.hex(Zenon.cyan)
  // where the color came from: { buf, line, s, e, hex, alpha }
  property var at: null
  // a window's own key for the eyedropper's answer
  readonly property string pickKey: "plato:" + sheet.uid
  property string uid: Math.random().toString(36).slice(2, 10)
  signal closed()

  modal: true
  title: "Color"
  glyph: "\u{F03D8}"
  cardW: 520
  cardH: 236
  hints: [["return", "use it"], ["esc", "cancel"]]
  onDismissed: sheet.close()

  function openFor(found) {
    sheet.at = found;
    sheet.hex = "#" + String(found.hex).replace(/^#/, "").slice(0, 6);
    sheet.shown = true;
    keyCatch.forceActiveFocus();
  }
  function close() { sheet.shown = false; sheet.closed(); }
  function use() {
    if (!sheet.client || !sheet.at) { sheet.close(); return; }
    const out = sheet.hex + (sheet.at.alpha || "");
    sheet.client.request("setColor", Object.assign({}, sheet.at, { hex: out }));
    sheet.close();
  }

  Connections {
    target: Pic.Picasso
    function onColorPicked(into, hex) { if (into === sheet.pickKey) sheet.hex = hex; }
  }

  Item {
    id: keyCatch
    anchors.fill: parent
    focus: true
    Keys.onReturnPressed: sheet.use()
    Keys.onEnterPressed: sheet.use()
    Keys.onEscapePressed: sheet.close()

    Row {
      x: 18
      y: 14
      spacing: 22
      Pic.ColorPicker {
        width: 300
        height: 200
        hex: sheet.hex
        onEdited: (h) => { sheet.hex = h; }
        onAccepted: sheet.use()
        onCancelled: sheet.close()
      }
      // the picker shows the color and its hex itself: here only what to do
      // with it, at the foot, level with its field
      Column {
        width: sheet.cardW - 36 - 300 - 22
        height: 200
        spacing: 12
        Item { width: 1; height: parent.height - 2 * 28 - parent.spacing * 2 }
        DialogButton {
          width: parent.width
          label: "Pick from screen"
          onClicked: Pic.Picasso.pickFor(sheet.pickKey)
        }
        DialogButton {
          width: parent.width
          label: "Use it"
          ink: Zenon.cyan
          primary: true
          onClicked: sheet.use()
        }
      }
    }
  }
}
