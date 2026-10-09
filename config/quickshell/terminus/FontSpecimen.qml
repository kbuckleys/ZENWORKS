// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// FONT SPECIMEN — a typeface, shown by being set in it. One sheet for every
// place a face is looked at before it is chosen: terminus' preview pane and
// quick look (a font FILE), and oracle's Font button (an installed FAMILY,
// the one the shell wears), so the three answer "what is this face like" the
// same way. Terminus' picker, opened by oracle to change the font, previews
// the candidates with it too.
//
//     FontSpecimen { path: "/usr/share/fonts/…/X.ttf" }      // a file
//     FontSpecimen { family: "JetBrainsMono Nerd Font"; weight: 600 }
//
// What it says, top to bottom: the family as the file declares it (very often
// not what the file is called) and whether it is monospaced; a line large;
// the alphabet, figures and the punctuation code leans on; a line of code,
// where ligatures show; the shell's own icons set in it, since a face without
// them turns every glyph in the shell into a box; and a waterfall of sizes,
// because a face that reads well at 28 px can be mud at 12.
//
// ── A FILE IS LOADED ONLY WHEN IT IS ONE ─────────────────────────────────
// The FontLoader lives in a Loader that is active only for a non-empty path:
// a FontLoader handed "" logs, and one handed a file that is not a font can
// half-register a family that draws every later glyph one codepoint off (see
// lookFaceBox in QuickLook). Callers pass a path only for a font file.

import QtQuick
import "../morpheus"

Column {
  id: spec

  // a font file, or "" — when set, it wins over `family`
  property string path: ""
  // an installed family, when there is no file
  property string family: ""
  property int weight: Font.Normal
  // terminus' zoom, so the specimen grows with the window's text
  property real zoom: 1
  // fewer lines, for a hover card
  property bool compact: false
  property color ink: Zenon.ink
  property color quiet: Zenon.muted

  spacing: Math.round(12 * spec.zoom)

  Loader {
    id: fileFace
    active: spec.path !== ""
    sourceComponent: FontLoader { source: Strings.fileUrl(spec.path) }
  }
  readonly property bool fromFile: spec.path !== ""
  readonly property bool ready: spec.fromFile
    ? (!!fileFace.item && fileFace.item.status === FontLoader.Ready)
    : spec.family !== ""
  readonly property bool failed: spec.fromFile && !!fileFace.item
    && fileFace.item.status === FontLoader.Error
  // The family NAME as the file declares it
  readonly property string face: spec.fromFile
    ? (spec.ready ? fileFace.item.font.family : "") : spec.family
  // the weight a file is in, as its loader read it; a family's as asked
  readonly property int faceWeight: spec.fromFile && spec.ready
    ? fileFace.item.font.weight : spec.weight

  // monospaced, if an i is as wide as a W
  FontMetrics {
    id: probe
    font.family: spec.face
    font.pixelSize: 20
  }
  readonly property bool mono: spec.ready
    && Math.abs(probe.advanceWidth("i") - probe.advanceWidth("W")) < 0.5

  readonly property string weightName: ({
    100: "Thin", 200: "ExtraLight", 300: "Light", 400: "Regular", 500: "Medium",
    600: "SemiBold", 700: "Bold", 800: "ExtraBold", 900: "Black"
  })[Math.round(spec.faceWeight / 100) * 100] || ""

  // ── the name ───────────────────────────────────────────────────────────
  Column {
    width: spec.width
    spacing: 2
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: spec.ready ? spec.face : spec.failed ? "could not read this font" : "…"
      color: spec.ready ? spec.ink : spec.failed ? Zenon.red : spec.quiet
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Math.round(17 * spec.zoom)
    }
    Text {
      visible: spec.ready
      width: parent.width
      elide: Text.ElideRight
      text: [spec.weightName, spec.mono ? "monospaced" : "proportional"]
        .filter((x) => x !== "").join("  ·  ")
      color: spec.quiet
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Math.round(13 * spec.zoom)
    }
  }

  Rectangle {
    visible: spec.ready
    width: spec.width
    height: 1
    color: Zenon.border
  }

  // ── set in it ──────────────────────────────────────────────────────────
  Repeater {
    model: !spec.ready ? [] : spec.compact ? [
      ["Sphinx of black quartz, judge my vow", 26],
      ["ABCDEFGHIJKLM abcdefghijklm 0123456789", 16],
      ["if (a != b && c >= 0) => { x -> y }", 15],
      ["\u{F0024}     \u{F0335}  \u{F057E}  ", 18],
    ] : [
      ["Sphinx of black quartz, judge my vow", 32],
      ["ABCDEFGHIJKLMNOPQRSTUVWXYZ", 20],
      ["abcdefghijklmnopqrstuvwxyz", 20],
      ["0123456789  &@#$%*  .,;:!?  ()[]{}<>  \"'`~^|\\/", 18],
      ["if (a != b && c >= 0) => { x -> y; i++ } // === !== <= ::", 16],
      ["\u{F0024}     \u{F0335}  \u{F057E}    \u{F0E09}", 22],
    ]
    delegate: Text {
      required property var modelData
      width: spec.width
      text: modelData[0]
      wrapMode: Text.Wrap
      color: spec.ink
      font.family: spec.face
      font.weight: spec.faceWeight
      font.pixelSize: Math.round(modelData[1] * spec.zoom)
    }
  }

  // ── the waterfall ──────────────────────────────────────────────────────
  Column {
    visible: spec.ready && !spec.compact
    width: spec.width
    spacing: Math.round(4 * spec.zoom)
    Repeater {
      model: [24, 18, 15, 13, 11]
      delegate: Row {
        required property int modelData
        spacing: 10
        Text {
          width: Math.round(28 * spec.zoom)
          text: modelData
          color: spec.quiet
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Math.round(11 * spec.zoom)
          anchors.baseline: line.baseline
          horizontalAlignment: Text.AlignRight
        }
        Text {
          id: line
          width: spec.width - Math.round(28 * spec.zoom) - 10
          elide: Text.ElideRight
          text: "The quick brown fox jumps over the lazy dog"
          color: spec.ink
          font.family: spec.face
          font.weight: spec.faceWeight
          font.pixelSize: Math.round(modelData * spec.zoom)
        }
      }
    }
  }
}
