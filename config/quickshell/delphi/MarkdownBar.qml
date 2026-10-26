// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE MARKDOWN BAR — a release's notes are Markdown, so they are written as
// Markdown, under a bar made for it, as GitHub's release editor has (user,
// 2026-10-25: Clio's rich-text bar was the wrong tool). Each button writes
// the syntax round the words chosen, through clio/MarkdownTarget, so ctrl z
// takes it back; a button is lit while the caret stands in what it writes.
//
//   Heading · Bold · Italic · Quote · Code · Link  |  Numbered · Bulleted ·
//   Task list  |  Divider
//
// The keys, GitHub's: ctrl b, ctrl i, ctrl e (code), ctrl k (link),
// ctrl shift . (quote), ctrl shift 7 / 8 (numbered / bulleted). `key(e)`
// answers them for the well the notes are typed in.
//
//     MarkdownBar { target: someMarkdownTarget; host: toolPane; onLinkAsked: … }

import QtQuick
import "../morpheus"
import "../clio"
import "../clio/notes.js" as N

Row {
  id: bar
  // the MarkdownTarget it writes through, and the ClioTools' pane (tips)
  property var target: null
  property var host: null
  // a link wants its address asked for; the holder asks
  signal linkAsked()
  // a picture or a video from this computer; the holder picks it
  // (absent where no holder answers: `media` false)
  signal mediaAsked()
  property bool media: false
  // a little air between the buttons (user, 2026-10-25)
  spacing: 6

  readonly property string kindNow: bar.target ? bar.target.kindHere : ""
  readonly property var marksNow: bar.target ? bar.target.marksHere : ({})

  // [glyph, tip, keys, lit, run]; "|" a rule between groups
  readonly property var tools: [
    ["", "Heading", "", bar.kindNow === "heading", () => bar.target.setKind("heading")],
    ["", "Bold", "ctrl b", !!bar.marksNow.b, () => bar.target.mark("b")],
    ["", "Italic", "ctrl i", !!bar.marksNow.i, () => bar.target.mark("i")],
    ["", "Quote", "ctrl shift .", bar.kindNow === "quote", () => bar.target.setKind("quote")],
    ["", "Code", "ctrl e", !!bar.marksNow.c || bar.kindNow === "mono", () => bar.target.code()],
    ["", "Link", "ctrl k", false, () => bar.linkAsked()],
    "|",
    ["", "Numbered list", "ctrl shift 7", bar.kindNow === "number", () => bar.target.setKind("number")],
    ["", "Bulleted list", "ctrl shift 8", bar.kindNow === "bullet", () => bar.target.setKind("bullet")],
    ["", "Task list", "", bar.kindNow === "check", () => bar.target.setKind("check")],
    "|",
    [N.KINDS.rule.glyph, "Divider", "", false, () => bar.target.rule()],
  ].concat(bar.media ? [["\u{F02E9}", "Picture or video", "", false, () => bar.mediaAsked()]] : [])

  function key(e) {
    if (!bar.target || !(e.modifiers & Qt.ControlModifier)) return false;
    const shift = e.modifiers & Qt.ShiftModifier, k = e.key;
    if (!shift && k === Qt.Key_B) { bar.target.mark("b"); return true; }
    if (!shift && k === Qt.Key_I) { bar.target.mark("i"); return true; }
    if (!shift && k === Qt.Key_E) { bar.target.code(); return true; }
    if (!shift && k === Qt.Key_K) { bar.linkAsked(); return true; }
    // shifted, the key's own character comes in: > for ., & for 7, * for 8
    if (shift && (k === Qt.Key_Greater || k === Qt.Key_Period)) { bar.target.setKind("quote"); return true; }
    if (shift && (k === Qt.Key_Ampersand || k === Qt.Key_7)) { bar.target.setKind("number"); return true; }
    if (shift && (k === Qt.Key_Asterisk || k === Qt.Key_8)) { bar.target.setKind("bullet"); return true; }
    return false;
  }

  Repeater {
    model: bar.tools
    delegate: Item {
      id: slot
      required property var modelData
      readonly property bool gap: slot.modelData === "|"
      width: slot.gap ? 13 : tool.width
      height: 26
      anchors.verticalCenter: parent ? parent.verticalCenter : undefined
      Rectangle {
        visible: slot.gap
        anchors.centerIn: parent
        width: 1
        height: 18
        color: Zenon.border
      }
      ClioTool {
        id: tool
        visible: !slot.gap
        anchors.verticalCenter: parent.verticalCenter
        pane: bar.host
        size: 26
        glyph: slot.gap ? "" : slot.modelData[0]
        tip: slot.gap ? "" : slot.modelData[1]
        keys: slot.gap ? "" : slot.modelData[2]
        lit: !slot.gap && slot.modelData[3]
        litInk: Zenon.cyan
        enabled: !!bar.target
        onPressed: if (!slot.gap) slot.modelData[4]()
      }
    }
  }
}
