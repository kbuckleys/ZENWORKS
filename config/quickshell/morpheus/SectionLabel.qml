// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SECTIONLABEL — a section's name, small and spaced, over what it heads.
//
//     SectionLabel { text: "Notes" }
//
// Capitals by the font, not by the caller, so the text can be written the
// way it is said. One look for every app (2026-10-20): picasso's Head and
// delphi's GroupHead read the same tokens (labelSpacing, titleWeight).

import QtQuick
import "."

Text {
  color: Zenon.accentMuted
  font.family: Zenon.face
  font.weight: Zenon.titleWeight
  font.pixelSize: Zenon.px(Zenon.labelPx)
  font.capitalization: Font.AllUppercase
  font.letterSpacing: Zenon.labelSpacing
}
