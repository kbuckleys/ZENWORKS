// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT A NOTE HOLDS BESIDES ITS WORDS — a row of small marks for a list row
// or a journal card: its pictures (past the ones shown), files, a table, a
// sketch, a checklist (done of all), links to other notes. `d` is a note's
// derived summary (notes.js derive); `shownPics` the pictures already drawn
// beside it, so only the rest are counted.

import QtQuick
import "../morpheus"

Row {
  id: marks
  property var d: null
  property int shownPics: 0
  // the checklist left out, where its count is already said
  property bool noChecks: false
  property real textSize: Zenon.px(11)
  spacing: 10
  readonly property var items: {
    const d = marks.d;
    if (!d) return [];
    const out = [];
    const pics = (d.images || []).length - marks.shownPics;
    if (pics > 0) out.push({ g: "\u{F02F9}", t: marks.shownPics > 0 ? "+" + pics : String(pics), ink: Zenon.cyan });
    if (d.files > 0) out.push({ g: "\u{F03E2}", t: String(d.files), ink: Zenon.blue });
    if (d.table) out.push({ g: "\u{F04EB}", t: "Table", ink: Zenon.green });
    if (d.sketch) out.push({ g: "\u{F0F49}", t: "Sketch", ink: Zenon.magenta });
    if (d.checks > 0 && !marks.noChecks) out.push({ g: "\u{F0C52}", t: d.done + "/" + d.checks, ink: d.done === d.checks ? Zenon.green : Zenon.accentMuted });
    if ((d.links || []).length > 0) out.push({ g: "\u{F0339}", t: String(d.links.length), ink: Zenon.yellow });
    return out;
  }
  visible: marks.items.length > 0
  Repeater {
    model: marks.items
    delegate: Row {
      required property var modelData
      spacing: 4
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.g
        color: modelData.ink
        font.family: Zenon.glyphFace
        font.pixelSize: marks.textSize + 1
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.t
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Font.DemiBold
        font.pixelSize: marks.textSize
        font.features: { "tnum": 1 }
      }
    }
  }
}
