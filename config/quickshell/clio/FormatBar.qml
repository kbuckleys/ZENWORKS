// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// EVERY FORMAT AT ONCE, IN A ROW — the paragraph styles in one switch, the
// lists and the quote, how the lines sit, the marks, indents, the words' own
// typeface and clearing. Lifted out of NotePane's format bar
// (user, 2026-10-25: one bar, no copies) so Delphi's release notes wear the
// same one. Fills its holder, centered, and shrinks to fit a narrow one.
//
//     FormatBar { host: pane; ed: editor; onHover: … }
//
// `ed` is what the buttons act on: a BlockEditor, or anything that answers
// the same — kindHere, marksHere, alignNow, inMono, faceHere, mediaSel, and
// setKind(k), mark(tag), setAlign(a), indent(d), plainText(). `host` is the
// ClioTool's pane (its window's tips and menus). Its buttons never take the
// keyboard: the caret and the selection stay where they were.

import QtQuick
import "../morpheus"
import "../terminus"
import "notes.js" as N

Item {
  id: fb
  property Item host: null
  property var ed: null
  // what this bar offers: the paragraph styles and lists by their kinds in
  // notes.js; alignment, the marks, indents and the typeface by switches
  property var styles: ["title", "heading", "subheading", "body", "mono"]
  property var lists: ["bullet", "dash", "number", "check", "quote"]
  property var marks: ["b", "i", "u", "s"]
  property bool aligns: true
  property bool indents: true
  property bool faces: false
  // the pointer came onto a button, or left one (NotePane's hover hold)
  signal hover()
  // the Font button: the holder opens the font book
  signal faceAsked()
  signal faceCleared()

  anchors.fill: parent

  readonly property var _styleInfo: ({
    title: ["Title", "ctrl shift t", Font.Bold], heading: ["Heading", "ctrl shift h", Font.Bold],
    subheading: ["Subheading", "ctrl shift j", Font.DemiBold], body: ["Body", "ctrl shift b", Font.Normal],
    mono: ["Mono", "ctrl shift m", Font.Normal] })
  readonly property var _listKeys: ({ bullet: "ctrl shift 7", dash: "ctrl shift 8", number: "ctrl shift 9", check: "ctrl shift l", quote: "" })
  readonly property var _markInfo: ({ b: ["\uF032", "Bold", "ctrl b"], i: ["\uF033", "Italic", "ctrl i"],
                                      u: ["\uF0CD", "Underline", "ctrl u"], s: ["\uF0CC", "Strikethrough", "ctrl shift x"] })
  readonly property bool _mono: !!fb.ed && fb.ed.inMono

  component Rule: Item {
    width: 21
    height: fb.height
    Rectangle { anchors.centerIn: parent; width: 1; height: 18; color: Zenon.border }
  }

  // (no Flickable: it filtered the pointer, and the hover over the buttons
  // went stale — the bar jumped, then would not go. A holder too narrow for
  // every format gets the row a little smaller instead.)
  Item {
    id: room
    anchors.fill: parent
    anchors.leftMargin: 4
    anchors.rightMargin: 4
    Row {
      id: row
      readonly property real fit: Math.min(1, room.width / Math.max(1, width))
      scale: fit
      transformOrigin: Item.Center
      x: Math.round((room.width - width) / 2)
      height: parent.height
      spacing: 0
      // the paragraph styles, one switch (user, 2026-10-25: Segments): the
      // one the caret is in lit, none while it is in a list or the quote.
      // Chosen on the release, as a switch is; the caret stays put (a
      // TapHandler takes no keyboard)
      Segments {
        id: styleSeg
        anchors.verticalCenter: parent.verticalCenter
        visible: fb.styles.length > 0
        textSize: Zenon.px(12)
        weight: Font.DemiBold
        pad: 20
        options: fb.styles.map((k) => [k, fb._styleInfo[k][0]])
        current: fb.ed ? fb.ed.kindHere : ""
        readonly property var _tips: fb.host && fb.host.win ? fb.host.win.tipsItem || null : null
        onChose: (v) => { if (fb.ed) fb.ed.setKind(v); }
        onPointed: (v, item, inside) => {
          fb.hover();
          if (!styleSeg._tips) return;
          if (inside) styleSeg._tips.show(item, N.KINDS[v].label, fb._styleInfo[v][1]); else styleSeg._tips.hide(item);
        }
      }
      Rule { visible: fb.lists.length > 0 }
      // lists and the quote
      Repeater {
        model: fb.lists
        delegate: ClioTool {
          required property string modelData
          anchors.verticalCenter: parent.verticalCenter
          pane: fb.host
          onHoveredChanged: fb.hover()
          size: 26
          glyph: N.KINDS[modelData].glyph
          litInk: Zenon.cyan
          lit: !!fb.ed && fb.ed.kindHere === modelData
          tip: N.KINDS[modelData].label
          keys: fb._listKeys[modelData] || ""
          onPressed: fb.ed.setKind(modelData)
        }
      }
      Rule { visible: fb.aligns }
      // how the lines sit
      Repeater {
        model: fb.aligns ? [["", "", "Along the left"], ["center", "", "Centered"], ["right", "", "Along the right"], ["justify", "", "Justified"]] : []
        delegate: ClioTool {
          required property var modelData
          anchors.verticalCenter: parent.verticalCenter
          pane: fb.host
          onHoveredChanged: fb.hover()
          size: 26
          glyph: modelData[1]
          litInk: Zenon.cyan
          enabled: !fb._mono
          lit: enabled && (fb.ed.kindHere !== "" || fb.ed.mediaSel !== "") && fb.ed.alignNow === modelData[0]
          tip: modelData[2]
          onPressed: fb.ed.setAlign(modelData[0])
        }
      }
      Rule { visible: fb.marks.length > 0 }
      // the marks on the words chosen
      Repeater {
        model: fb.marks
        delegate: ClioTool {
          required property string modelData
          anchors.verticalCenter: parent.verticalCenter
          pane: fb.host
          onHoveredChanged: fb.hover()
          size: 26
          glyph: fb._markInfo[modelData][0]
          litInk: Zenon.cyan
          enabled: !fb._mono
          lit: enabled && !!fb.ed && !!fb.ed.marksHere[modelData]
          tip: fb._markInfo[modelData][1]
          keys: fb._markInfo[modelData][2]
          onPressed: fb.ed.mark(modelData)
        }
      }
      Rule { visible: fb.indents }
      ClioTool { visible: fb.indents; anchors.verticalCenter: parent.verticalCenter; pane: fb.host; onHoveredChanged: fb.hover(); size: 26; glyph: "\uF03B"; tip: "Outdent"; keys: "shift tab"; onPressed: fb.ed.indent(-1) }
      ClioTool { visible: fb.indents; anchors.verticalCenter: parent.verticalCenter; pane: fb.host; onHoveredChanged: fb.hover(); size: 26; glyph: "\uF03C"; tip: "Indent"; keys: "tab"; onPressed: fb.ed.indent(1) }
      Rule { visible: fb.indents || fb.faces }
      // the words' own typeface: its name on the bar when one is chosen
      ClioTool {
        anchors.verticalCenter: parent.verticalCenter
        visible: fb.faces
        pane: fb.host
        onHoveredChanged: fb.hover()
        size: 26
        pad: 14
        readonly property string here: fb.ed ? fb.ed.faceHere : ""
        word: here !== "" ? here : "Font"
        wordPx: Zenon.px(13)
        wordWeight: Font.DemiBold
        lit: here !== ""
        litInk: Zenon.cyan
        tip: here !== "" ? "Font for these words — right click for the note's own" : "Font for these words"
        enabled: !fb._mono
        onPressed: fb.faceAsked()
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onClicked: fb.faceCleared() }
      }
      ClioTool { anchors.verticalCenter: parent.verticalCenter; pane: fb.host; onHoveredChanged: fb.hover(); size: 26; glyph: "\u{F0265}"; tip: "Clear formatting"; enabled: !fb._mono; onPressed: fb.ed.plainText() }
    }
  }
}
