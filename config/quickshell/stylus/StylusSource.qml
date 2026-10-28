// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE IMAGE, IN STYLUS' WRITE SHEET — one row: what it is (forge.py's
// probe), how big unpacked, its volume label, and whether its sums match,
// with the button that opens another. With none chosen it asks for one; a
// file dropped on the window lands here (`hot` while one is held over it).
//
// Under the sums, who signed it (forge sig: the image's own signature, or
// its checksums'), and when the signer's key is not here, the offer to
// fetch it — only when asked: it adds to your keyring.
//
//     StylusSource { path: …; probe: …; sums: S.sumsOf(…); sig: S.sigWords(…)
//                    hot: drop.over; onOpen: …; onDownload: …; onFetchKey: … }

import QtQuick
import "../morpheus"
import "stylus.js" as S

Rectangle {
  id: src

  property string path: ""
  property var probe: null
  property var sums: ({ state: "none", words: "" })
  property var sig: ({ words: "", level: "", key: "" })
  property bool fetching: false
  property bool hot: false
  property bool locked: false
  signal open()
  signal download()
  signal fetchKey()

  readonly property string glyph: !src.probe ? "\u{F021F}"
    : src.probe.kind === "windows" ? "\u{F05B3}"
    : src.probe.kind === "hybrid" || src.probe.kind === "iso" ? "\u{F05EE}" : "\u{F021F}"

  width: parent ? parent.width : 0
  height: Math.max(76, lines.implicitHeight + 24)
  radius: Zenon.radiusCard
  color: src.hot ? Zenon.alpha(Zenon.cyan, 0.08) : Zenon.wash(0.04)
  border.width: 1
  border.color: src.hot ? Zenon.cyan : Zenon.border

  Text {
    id: glyph
    x: 16
    width: 36
    horizontalAlignment: Text.AlignHCenter
    anchors.verticalCenter: parent.verticalCenter
    text: src.glyph
    color: src.path === "" ? Zenon.muted : Zenon.cyan
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(30)
  }
  Column {
    id: lines
    anchors.left: glyph.right
    anchors.leftMargin: 14
    anchors.right: dlBtn.visible ? dlBtn.left : btn.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 3
    Text {
      textFormat: Text.PlainText
      width: parent.width
      elide: Text.ElideMiddle
      text: src.path === "" ? "Choose an image" : src.path.replace(/.*\//, "")
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Zenon.titleWeight
      font.pixelSize: Zenon.px(15)
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      elide: Text.ElideRight
      text: src.path === "" ? "An ISO or a disk image — or drop one here"
        : src.probe ? [S.sourceLine(src.probe), src.probe.label].filter((x) => x).join("  ·  ") : "Reading…"
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
    // the sums: matched, not, being worked out, or none to check against
    Text {
      textFormat: Text.PlainText
      width: parent.width
      elide: Text.ElideRight
      visible: src.sums.words !== ""
      text: src.sums.words
      color: src.sums.state === "ok" ? Zenon.green : src.sums.state === "bad" ? Zenon.red
        : src.sums.state === "running" ? Zenon.ink : Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
    // who signed it; a key not here, fetched when asked
    Row {
      visible: src.sig.words !== ""
      spacing: 10
      Text {
        textFormat: Text.PlainText
        text: src.sig.words
        color: src.sig.level === "good" ? Zenon.green : src.sig.level === "bad" ? Zenon.red
          : src.sig.level === "warn" ? Zenon.yellow : Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
      Text {
        visible: src.sig.key !== ""
        text: src.fetching ? "fetching its key\u2026" : "fetch its key"
        color: Zenon.link
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(12)
        TapHandler { enabled: !src.fetching; onTapped: src.fetchKey() }
      }
    }
  }
  // a Linux to download, while none is chosen
  DialogButton {
    id: dlBtn
    anchors.right: btn.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    visible: !src.locked && src.path === ""
    label: "Download…"
    ink: Zenon.accentMuted
    onClicked: src.download()
  }
  DialogButton {
    id: btn
    anchors.right: parent.right
    anchors.rightMargin: 16
    anchors.verticalCenter: parent.verticalCenter
    visible: !src.locked
    label: src.path === "" ? "Open…" : "Change…"
    primary: src.path === ""
    ink: src.path === "" ? Zenon.cyan : Zenon.accentMuted
    onClicked: src.open()
  }
}
