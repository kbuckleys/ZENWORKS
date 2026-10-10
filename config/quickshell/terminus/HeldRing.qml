// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HELDRING — the thing a menu was asked of, outlined while that menu is
// open. Not the cursor: a right click is a question about a row, so which
// row the card is about has to be seen at a glance, beside wherever the
// cursor happens to be. It began on terminus' disk rows (SideRow) and the
// user asked for it everywhere a right click opens a menu (2026-10-09):
// terminus' rows and tiles, picasso's gallery, icarus' entries, clio's notes.
//
//     HeldRing { anchors.fill: parent; anchors.margins: 4; on: menuAt === row }
//
// Laid over the row as a sibling of what it draws, so it reads on top of the
// row's own fill and cursor bar. Placement is the caller's.

import QtQuick
import "../morpheus"

Rectangle {
  id: held
  property bool on: false

  radius: 4
  // hollow: only the ring (user, 2026-10-09 — no tint inside it)
  color: "transparent"
  border.width: 2   // user, 2026-10-09
  border.color: Zenon.alpha(Zenon.cyan, 0.6)

  opacity: held.on ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Easing.OutCubic } }
}
