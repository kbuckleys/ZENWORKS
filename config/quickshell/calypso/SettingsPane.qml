// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CALYPSO'S SETTINGS — on a sheet: how soon every account locks by itself,
// and how long a copied secret stays on the clipboard (terminus' Segments,
// one row each). The screen locking always locks calypso too; that is not a
// setting.

import QtQuick
import "../morpheus"
import "../terminus"

Item {
  id: set
  property var win: null
  signal closed()
  implicitHeight: col.implicitHeight + 44

  Column {
    id: col
    x: 22
    y: 20
    width: parent.width - 44
    spacing: 22
    Row {
      spacing: 12
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F08BB}"
        color: Zenon.cyan
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(18)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Settings"
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(19)
      }
    }
    Column {
      width: parent.width
      spacing: 8
      Text {
        text: "Lock every account after"
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.DemiBold
        font.pixelSize: Zenon.px(15)
      }
      Segments {
        options: [["1", "1 min"], ["5", "5 min"], ["10", "10 min"], ["30", "30 min"], ["60", "1 hour"], ["0", "Never"]]
        current: set.win ? String(set.win.mgr.lockAfter) : "10"
        textSize: Zenon.px(13)
        onChose: (v) => set.win.mgr.set("lockAfter", Number(v))
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "With nothing asked of calypso for that long. Locking the screen locks it at once, whatever this says."
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
    }
    Column {
      width: parent.width
      spacing: 8
      Text {
        text: "Clear a copied secret after"
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.DemiBold
        font.pixelSize: Zenon.px(15)
      }
      Segments {
        options: [["15", "15 s"], ["30", "30 s"], ["60", "1 min"], ["90", "90 s"], ["0", "Never"]]
        current: set.win ? String(set.win.mgr.clearAfter) : "30"
        textSize: Zenon.px(13)
        onChose: (v) => set.win.mgr.set("clearAfter", Number(v))
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Passwords, codes and keys copied from calypso are marked sensitive: the clipboard history (Folio, cliphist) never keeps them."
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
    }
    Row {
      anchors.right: parent.right
      DialogButton { label: "Done"; ink: Zenon.cyan; primary: true; onClicked: set.closed() }
    }
  }
}
