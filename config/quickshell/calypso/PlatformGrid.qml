// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHERE YOUR PASSWORDS LIVE — every platform calypso can read, a card each:
// its face, its name, what it is, and whether its tool is here or will be
// installed when it is chosen (through Ceres). The window's welcome when
// there is no account yet, and the body of its Add-an-account sheet.
//
// Pointed at, a card's bubble (terminus' Bubble) says more: the CLI, its
// package and where that comes from, how the platform keeps its session.
//
//   ← → ↑ ↓ choose, return add (the window hands keys to key())

import QtQuick
import "../morpheus"
import "../terminus"
import "calypso.js" as C

Item {
  id: grid
  property var win: null
  property int cols: 3
  property int pick: 0
  readonly property var kinds: C.PLATFORM_ORDER
  signal chosen(string kind)

  implicitHeight: col.implicitHeight

  // ── ONE BUBBLE, HOPPING (user's bubble.mp4, 2026-10-17) ──────────────
  // A bubble per card meant the pointer crossing the grid shut one popup
  // (the compositor fading its ghost out) while the next opened beside it —
  // two cards at once, and the text of the last one under the new. Now the
  // grid has one, as ceres' package peek does: it opens after a short rest,
  // moves straight to the next card the pointer reaches, and goes only once
  // the pointer has been off the cards a moment.
  property Item peekCell: null
  property Item peekShown: null
  // the card it last hung from: held while it goes, so it shuts in place
  // with its words, rather than vanishing with its target
  property Item peekLast: null
  onPeekShownChanged: if (grid.peekShown) grid.peekLast = grid.peekShown
  Timer { id: peekWait; interval: Zenon.hoverWait; onTriggered: grid.peekShown = grid.peekCell }
  Timer { id: peekLeave; interval: Zenon.hoverLeave; onTriggered: if (!grid.peekCell) grid.peekShown = null }
  function peekAt(cell) {
    grid.peekCell = cell && cell.info ? cell : null;
    if (!grid.peekCell) { peekWait.stop(); peekLeave.restart(); return; }
    peekLeave.stop();
    if (grid.peekShown) { peekWait.stop(); grid.peekShown = grid.peekCell; }
    else peekWait.restart();
  }
  onVisibleChanged: if (!visible) { grid.peekCell = null; grid.peekShown = null; }

  function key(e) {
    const n = grid.kinds.length;
    if (e.key === Qt.Key_Right) { grid.pick = (grid.pick + 1) % n; return true; }
    if (e.key === Qt.Key_Left) { grid.pick = (grid.pick + n - 1) % n; return true; }
    if (e.key === Qt.Key_Down) { grid.pick = Math.min(n - 1, grid.pick + grid.cols); return true; }
    if (e.key === Qt.Key_Up) { grid.pick = Math.max(0, grid.pick - grid.cols); return true; }
    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { grid.chosen(grid.kinds[grid.pick]); return true; }
    return false;
  }

  Column {
    id: col
    width: parent.width
    spacing: 14
    Grid {
      id: cells
      width: parent.width
      columns: grid.cols
      columnSpacing: 12
      rowSpacing: 12
      readonly property real cellW: (width - (grid.cols - 1) * columnSpacing) / grid.cols
      Repeater {
        model: grid.kinds
        delegate: Rectangle {
          id: cell
          required property var modelData
          required property int index
          readonly property var p: C.platform(modelData)
          readonly property var info: grid.win ? grid.win.mgr.platformInfo(modelData) : null
          readonly property bool here: grid.pick === index
          readonly property int has: grid.win ? grid.win.mgr.accounts.filter((a) => a.kind === modelData).length : 0
          width: cells.cellW
          height: 124
          radius: Zenon.rad(11)
          color: press.pressed ? Zenon.pressWash(0.12) : cell.here ? Zenon.alpha(Zenon.cyan, 0.1) : Zenon.wash(0.04)
          border.width: 1
          border.color: cell.here ? Zenon.alpha(Zenon.cyan, 0.5) : Zenon.border
          Behavior on color { ColorAnimation { duration: Zenon.fast } }
          Behavior on border.color { ColorAnimation { duration: Zenon.fast } }
          ItemTile {
            id: ptile
            x: 16
            y: 16
            size: 40
            glyph: cell.p.glyph
            ink: cell.p.ink
            lit: cell.here
          }
          // the tool: here, or how it would come
          Text {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: ptile.verticalCenter
            text: !cell.info ? ""
              : grid.win.mgr.installing && grid.win.mgr.installing.pkg === cell.info.pkg ? "installing…"
              : cell.info.installed ? (cell.has > 0 ? cell.has + " added" : " ready")
              : cell.info.aur ? "AUR · installs" : "installs"
            color: cell.info && cell.info.installed ? Zenon.green : Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(11)
          }
          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            anchors.top: ptile.bottom
            anchors.topMargin: 10
            spacing: 2
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: cell.p.name
              color: Zenon.ink
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(16)
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: cell.p.tagline
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
          }
          MouseArea {
            id: press
            anchors.fill: parent
            onClicked: { grid.pick = cell.index; grid.chosen(cell.modelData); }
          }
          // resting on a card: the grid's one bubble hangs from it (below)
          HoverHandler {
            onHoveredChanged: hovered ? grid.peekAt(cell) : grid.peekCell === cell ? grid.peekAt(null) : undefined
          }
        }
      }
    }
    // the ones asked about that cannot be reached
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
      text: "NordPass and Enpass keep no command-line tool, so calypso cannot read them."
      color: Zenon.alpha(Zenon.accentMuted, 0.8)
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
  }

  Bubble {
    id: peek
    readonly property var info: grid.peekLast ? grid.peekLast.info : null
    window: grid.win
    target: grid.peekLast
    shown: !!grid.peekShown && !!peek.info
    cardWidth: 340
    Text {
      width: 300
      wrapMode: Text.Wrap
      text: peek.info ? "<b>" + peek.info.cli + "</b> — from the " + (peek.info.aur ? "AUR" : "Arch repositories")
        + ", package " + peek.info.pkg + (peek.info.installed ? ", installed." : ", installed through Ceres when you choose it.") : ""
      textFormat: Text.StyledText
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
    Text {
      width: 300
      wrapMode: Text.Wrap
      text: peek.info ? peek.info.blurb.charAt(0).toUpperCase() + peek.info.blurb.slice(1) + "." : ""
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
  }
}
