// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE READING TOOLS in Minerva's head (user, 2026-10-21: "need tools in the
// topbar"): the page you are on, as a field you can type a page into, the
// turn either way, and for a PDF the size — − and + around the percentage,
// and its width or its whole page. An EPUB's place is its chapter; its size
// is the Aa card beside the find.
//
// Loaded by the window by file (see MinervaWindow), and handed the window.

import QtQuick
import "../morpheus"

Row {
  id: tools
  property var win: null
  signal done()

  readonly property var page: tools.win ? tools.win.page : null
  readonly property bool pdf: !!tools.win && tools.win.kind === "pdf"
  readonly property int at: !tools.page ? 0 : tools.pdf ? tools.page.where.page : tools.page.where.chapter
  readonly property int count: tools.page ? tools.page.pageCount : 0

  spacing: 6
  // a page of a PDF, a chapter of an EPUB (its own step is a screenful)
  function turn(d) {
    if (!tools.page) return;
    if (tools.pdf) tools.page.step(d);
    else tools.page.goTo({ chapter: Math.max(0, Math.min(tools.count - 1, tools.at + d)), frac: 0 });
  }

  DialogButton {
    implicitHeight: 30
    glyph: true
    label: "\u{F0141}"
    ready: tools.at > 0
    onClicked: tools.turn(-1)
  }
  // the place: type a number, return goes there
  Rectangle {
    width: placeRow.implicitWidth + 20
    height: 30
    radius: Zenon.radiusControl
    color: Zenon.wash(0.06)
    border.width: 1
    border.color: Zenon.border
    HeldRing { anchors.fill: parent; on: placeField.activeFocus }
    Row {
      id: placeRow
      anchors.centerIn: parent
      spacing: 5
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !tools.pdf
        text: "Chapter"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      TextInput {
        id: placeField
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(contentWidth, tools.countW.width)
        horizontalAlignment: TextInput.AlignRight
        text: String(tools.at + 1)
        color: Zenon.ink
        selectionColor: Zenon.cyan
        selectedTextColor: Zenon.onAccent
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(14)
        validator: IntValidator { bottom: 1; top: Math.max(1, tools.count) }
        cursorDelegate: Caret { field: placeField }
        onActiveFocusChanged: {
          if (placeField.activeFocus) { placeField.selectAll(); return; }
          placeField.text = Qt.binding(() => String(tools.at + 1));
        }
        onAccepted: {
          const n = Math.max(1, Math.min(tools.count, parseInt(placeField.text, 10) || 1)) - 1;
          if (tools.page) tools.page.goTo(tools.pdf ? { page: n } : { chapter: n, frac: 0 });
          tools.done();
        }
        Keys.onEscapePressed: tools.done()
      }
      Text {
        id: countText
        anchors.verticalCenter: parent.verticalCenter
        text: "/ " + tools.count
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
    }
  }
  // the field never narrower than the count it can reach
  readonly property TextMetrics countW: TextMetrics {
    font: placeField.font
    text: String(Math.max(1, tools.count))
  }
  DialogButton {
    implicitHeight: 30
    glyph: true
    label: "\u{F0142}"
    ready: tools.at < tools.count - 1
    onClicked: tools.turn(1)
  }

  // ── the size, for a PDF ──────────────────────────────────────────────
  Item { width: 8; height: 1; visible: tools.pdf }
  DialogButton {
    implicitHeight: 30
    visible: tools.pdf
    glyph: true
    label: "\u{F06EC}"
    onClicked: if (tools.page) tools.page.zoomBy(1 / 1.15)
  }
  // the percentage; a click puts it back to the page's width
  DialogButton {
    implicitHeight: 30
    visible: tools.pdf
    label: tools.page && tools.pdf ? tools.page.zoomPercent + "%" : ""
    onClicked: if (tools.page) tools.page.fit("width")
  }
  DialogButton {
    implicitHeight: 30
    visible: tools.pdf
    glyph: true
    label: "\u{F06ED}"
    onClicked: if (tools.page) tools.page.zoomBy(1.15)
  }
  // width, or the whole page; lit for the one it is fitting
  DialogButton {
    implicitHeight: 30
    visible: tools.pdf
    glyph: true
    label: "\u{F084E}"
    ink: tools.page && tools.page.fitting === "width" ? Zenon.cyan : Zenon.muted
    onClicked: if (tools.page) tools.page.fit("width")
  }
  DialogButton {
    implicitHeight: 30
    visible: tools.pdf
    glyph: true
    label: "\u{F0EF6}"
    ink: tools.page && tools.page.fitting === "page" ? Zenon.cyan : Zenon.muted
    onClicked: if (tools.page) tools.page.fit("page")
  }
}
