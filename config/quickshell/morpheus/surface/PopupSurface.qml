// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A POPUP SURFACE, IN PLAIN QT QUICK — what quickshell's PopupWindow is to
// the shell's menus and bubbles (CardPopup, terminus/Bubble), for a suite
// application that is not quickshell (iris: PySide6, its own process). The
// card drawn in it is the suite's own and unchanged — CardBody, BubbleCard,
// JobsCard — and the compositor frosts the surface (hyprland's popup blur),
// so a menu in iris is the shell's menu: its glass, its shadow, its fade.
//
//     PopupSurface {
//       host: myWindow
//       at: Qt.point(x, y)            // the SURFACE's top-left, in the
//                                     // host's contentItem coordinates
//       open: …                       // in: the card's shade eases to it
//       width: card.implicitWidth; height: card.implicitHeight
//       onDismissed: open = false     // a click elsewhere (grab), Escape
//       CardBody { anchors.fill: parent; shade: surface.shade; … }
//     }
//
// An xdg-popup, hung from the host window at `at` (wayland tells a client
// nothing of where its window is on screen, but a popup is placed against
// its parent). Kept up while the card fades out (`shade`), so it closes
// with the card's own animation rather than vanishing.
//
//   grab: true    a menu: it takes the keyboard and the pointer, and a click
//                 anywhere else puts it away (the compositor dismisses the
//                 popup; `dismissed` says so). Escape too.
//   grab: false   a bubble or a list under a field being typed in: never
//                 takes the keyboard (the field keeps it), still clickable.
//
// Lives in its own directory (as clip/RoundClip does): no qmldir line, so a
// live shell reload finds it, and iris' filtered morpheus qmldir is untouched.

import QtQuick
import QtQuick.Window
import ".."

Window {
  id: surf

  property Window host: null
  property point at: Qt.point(0, 0)
  property bool open: false
  property bool grab: true

  // the card's 0 → 1: hand it to the card (CardBody.shade, BubbleCard.shade)
  property real shade: surf.open ? 1 : 0
  Behavior on shade { NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic } }

  signal dismissed()
  // a key the surface has while it holds the keyboard (grab), for the card's
  // holder to walk its rows with; Escape is taken here and dismisses
  signal keyPressed(var event)

  default property alias content: stage.data

  transientParent: surf.host
  flags: surf.grab ? (Qt.Popup | Qt.FramelessWindowHint)
                   : (Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus)
  color: "transparent"
  x: surf.host ? surf.host.x + Math.round(surf.at.x) : 0
  y: surf.host ? surf.host.y + Math.round(surf.at.y) : 0

  visible: !!surf.host && (surf.open || surf.shade > 0.01)
  // put away by the compositor (a click outside a grabbing popup) while the
  // holder still has it open: the holder hears of it, and closes it
  onVisibleChanged: if (!surf.visible && surf.open) surf.dismissed()

  Item {
    id: stage
    anchors.fill: parent
    focus: true
    Keys.onPressed: (e) => {
      if (e.key === Qt.Key_Escape) { e.accepted = true; surf.dismissed(); return; }
      surf.keyPressed(e);
    }
  }
}
