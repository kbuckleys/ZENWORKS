// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A DROPDOWN THAT IS A PICTURE OF THE SCREEN.
//
// Some settings name a place, and a list of words is the wrong shape for
// one: "Bottom right" has to be read and then turned back into a corner,
// and picking between six of them means comparing six phrases. The screen
// itself, with six cells you click, is the same choice with the reading
// taken out.
//
// It wears CardMenu's card — the same ground, border, radius, arrival and
// shadow — because it opens the same way off the same kind of control, and a
// dropdown that looked like a different species would be a second thing to
// learn. It is not a CardMenu because a menu is a column of rows, and this
// is deliberately not one.
//
//     CornerPicker {
//       open: …; at: Qt.point(x, y)
//       cellRow: 1; cellCol: 2          // which one is lit, -1 for none
//       autoOn: false                   // is the follow row the current pick
//       onPicked: (r, c) => …
//       onPickedAuto: …
//     }

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "../oracle"
import "."

// An xdg-popup, hung off the window that opened it — see CardPopup for why a
// window's card cannot be a layer surface placed in screen coordinates.
PopupWindow {
  id: root

  property bool open: false
  // the window it hangs off, and the card's top-left in that window
  property var window: null
  property point at: Qt.point(0, 0)
  // the shadow's room around the card, as CardPopup's
  readonly property int shadowPad: 36

  // which cell is the current choice, -1 -1 for none
  property int cellRow: -1
  property int cellCol: -1

  // the row under the grid: an answer that is not a place
  property bool autoShown: true
  property bool autoOn: false
  property string autoLabel: "Follow bar"

  signal picked(int row, int col)
  signal pickedAuto()

  readonly property int cols: 3
  readonly property int rows: 2
  readonly property int gap: 3
  readonly property int pad: 10

  // ── CUT TO THE SAME CARD AS EVERY OTHER MENU ─────────────────────────
  // Menu width, row height and separator are the shared menu tokens rather
  // than numbers of its own, so the picker and the list dropdown beside it
  // change together when those settings do. The grid fills whatever width
  // that leaves, and the cells keep a screen's proportions as it grows.
  readonly property int cardW: Math.max(Zenon.menuWidth, 3 * 40 + 2 * root.gap + root.pad * 2)
  readonly property int gridW: root.cardW - root.pad * 2
  readonly property real cellW: (root.gridW - (root.cols - 1) * root.gap) / root.cols
  readonly property int cellH: Math.round(root.cellW * 0.6)
  readonly property int gridH: root.rows * root.cellH + (root.rows - 1) * root.gap
  readonly property int cardH: root.gridH + root.pad * 2
    + (root.autoShown ? Zenon.menuSepHeight + Zenon.menuRowHeight + Zenon.menuCardPad : 0)

  // ── the arrival, as every card on this desktop does it ───────────────
  property real shade: 0
  onOpenChanged: root.shade = root.open ? 1 : 0
  Behavior on shade {
    NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
  }

  visible: root.window !== null && (root.open || root.shade > 0.01)
  color: "transparent"

  implicitWidth: root.cardW + root.shadowPad * 2
  implicitHeight: root.cardH + root.shadowPad * 2

  anchor {
    window: root.window
    rect.x: Math.round(root.at.x) - root.shadowPad
    rect.y: Math.round(root.at.y) - root.shadowPad
    rect.width: 2 * root.shadowPad
    rect.height: 2 * root.shadowPad
    adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
  }

  ClippingRectangle {
    id: bg
    anchors.fill: parent
    anchors.margins: root.shadowPad
    transformOrigin: Item.TopLeft
    scale: Zenon.menuScale(root.shade)
    opacity: root.shade
    color: Zenon.menuBg
    border.color: Zenon.border
    border.width: 1
    radius: Zenon.menuRadius

    // ── the screen ──────────────────────────────────────────────────
    Grid {
      id: grid
      x: root.pad
      y: root.pad
      columns: root.cols
      rows: root.rows
      spacing: root.gap

      Repeater {
        model: root.cols * root.rows

        Rectangle {
          id: cell
          required property int index
          readonly property int r: Math.floor(cell.index / root.cols)
          readonly property int c: cell.index % root.cols
          readonly property bool here: cell.r === root.cellRow && cell.c === root.cellCol
          // Lit only when the AUTO row is not the answer: two things
          // claiming to be the current choice at once is a picker that does
          // not know its own state.
          readonly property bool chosen: !root.autoOn && cell.here
          // Where "follow" currently lands, shown softly — the corner the
          // toasts are actually in, without claiming it was picked.
          readonly property bool followed: root.autoOn && cell.here
          readonly property color ink: cell.chosen ? Zenon.cyan
            : cell.followed ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.55)
            : Qt.rgba(Zenon.muted.r, Zenon.muted.g, Zenon.muted.b, 0.7)

          width: root.cellW
          height: root.cellH
          radius: 3
          color: cell.chosen
            ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.30)
            : (cellMa.containsMouse ? Zenon.wash(0.12)
                                    : Zenon.wash(0.05))
          border.width: 1
          border.color: cell.chosen ? Zenon.cyan
            : cell.followed ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.55)
            : (cellMa.containsMouse ? Zenon.keyInk : Zenon.border)
          Behavior on color {
            ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
          }
          Behavior on border.color {
            ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
          }

          // A toast, drawn where a toast would actually go — in THIS cell's
          // corner, not across its whole width. Full-width, the three cells
          // of a row were the same picture and only their position in the
          // grid told left from right.
          Rectangle {
            width: Math.round(parent.width * 0.45)
            height: 6
            radius: 2
            x: cell.c === 0 ? 5
             : cell.c === 2 ? parent.width - width - 5
             : Math.round((parent.width - width) / 2)
            y: cell.r === 0 ? 5 : parent.height - height - 5
            color: cell.ink
            Behavior on color {
              ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
            }
          }

          MouseArea {
            id: cellMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.picked(cell.r, cell.c)
          }
        }
      }
    }

    // A separator as CardMenu draws one: edge to edge, in the menu's own
    // separator height.
    Item {
      id: rule
      visible: root.autoShown
      anchors.left: parent.left
      anchors.right: parent.right
      y: root.pad * 2 + root.gridH
      height: Zenon.menuSepHeight

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Zenon.border
      }
    }

    // ── the answer that is not a place ──────────────────────────────
    // A CardMenu row in everything but name: the same height, inset, type,
    // hover and tick.
    Item {
      visible: root.autoShown
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Zenon.menuCardPad
      anchors.rightMargin: Zenon.menuCardPad
      anchors.top: rule.bottom
      height: Zenon.menuRowHeight

      Rectangle {
        anchors.fill: parent
        color: autoMa.containsMouse ? Zenon.border : "transparent"
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: autoTick.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: root.autoLabel
        color: Zenon.white
        font.family: Zenon.face
        font.weight: Font.Medium
        font.pixelSize: Zenon.px(16)
      }

      Text {
        id: autoTick
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        horizontalAlignment: Text.AlignHCenter
        visible: root.autoOn
        text: "\uF00C"
        color: Zenon.cyan
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }

      MouseArea {
        id: autoMa
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.pickedAuto()
      }
    }
  }

  MenuShadow {
    panel: bg
    reach: root.shadowPad
    opacity: root.shade
    transformOrigin: Item.TopLeft
    scale: bg.scale
  }
}
