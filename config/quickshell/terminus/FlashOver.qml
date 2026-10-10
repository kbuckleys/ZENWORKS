// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// FLASHOVER — the row RowFlash lights. See RowFlash.qml.

import QtQuick
import "../morpheus"

// The lit row itself. Over everything else on it, so the whole row lights
// rather than the gaps between a glyph, a label and a key chip.
Rectangle {
  property var flash: null
  property int index: -1
  anchors.fill: parent
  z: 3
  visible: !!flash && index === flash.at && flash.ink > 0
  color: flash
    ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.55 * flash.ink)
    : "transparent"
}
