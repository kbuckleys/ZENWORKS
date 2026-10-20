// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A section's name, small and spaced, over the controls it heads.

import QtQuick
import "../morpheus"

Text {
  color: Zenon.accentSoft
  font.family: Zenon.face
  font.weight: Zenon.titleWeight
  font.pixelSize: Zenon.px(13)
  font.capitalization: Font.AllUppercase
  font.letterSpacing: Zenon.labelSpacing
}
