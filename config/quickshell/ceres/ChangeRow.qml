// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One package moving: "name   from → to". The same three inks as the bar's
// tooltip and the toast — the old version grayed, the arrow in the accent,
// the new one plain — so a change reads the same wherever it is shown.

import QtQuick
import "../morpheus"
import "."
import "ceres.js" as Cer

Item {
  id: ch
  // Text size over the panel's: the window reads 2px larger.
  property int grow: 0
  // { name, from, to } — from may be "" for something new
  property var u: null
  property string glyph: ""
  property color glyphInk: Zenon.blue
  // A pending update: marked when paru's minimum release age holds it back
  // (Ceres.held) — a full upgrade leaves it out until then.
  property bool pending: false
  readonly property real heldUntil: ch.pending && ch.u ? (Ceres.heldUntil[ch.u.name] || 0) : 0
  implicitHeight: 28

  Text {
    id: chGlyph
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: ch.glyph !== "" ? 22 : 0
    text: ch.glyph
    color: ch.glyphInk
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13) + ch.grow
  }

  // THE NAME IS WHAT THE ROW IS (user, 2026-10-14): a long version pair —
  // 2.1.1791890110+634daf2-1 → 2.1.1791988261+2a8e017-1 — in a narrow
  // window took the whole row and the name was elided to nothing. The name
  // keeps its own width, up to this share of the row; the versions have the
  // rest, and give way from the left: the old version first, the new one
  // last.
  readonly property real nameShare: 0.45
  Text {
    textFormat: Text.PlainText
    id: chName
    anchors.left: chGlyph.right
    anchors.right: vers.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    text: ch.u ? ch.u.name : ""
    color: Zenon.white
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(15) + ch.grow
  }

  Text {
    id: vers
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(0, Math.min(vers.implicitWidth,
      ch.width - chGlyph.width - 12 - Math.min(chName.implicitWidth, ch.width * ch.nameShare)))
    elide: Text.ElideLeft
    horizontalAlignment: Text.AlignRight
    textFormat: Text.StyledText
    linkColor: Zenon.link   // a link in it is the theme's (Zenon.link)
    // WHAT MOVED, LIT: the new version's part that differs from the old,
    // from the separator before the first difference on, in full white and
    // bold; what stayed the same in the quieter ink. 3.130-1 → 3.131-1 reads
    // as a minor bump at a glance, 2.90.0-1 → 2.90.0-2 as a rebuild.
    readonly property int same: !ch.u || !ch.u.from ? 0 : Cer.versionSplit(ch.u.from, ch.u.to)
    text: !ch.u ? "" : (ch.heldUntil > 0
        ? "<font color='" + Zenon.yellow + "'>held till " + Cer.esc(Qt.formatDateTime(new Date(ch.heldUntil), "ddd d MMM, h:mm ap")) + "</font>  "
        : "") + (ch.u.from
      ? "<font color='" + Ceres.ink.muted + "'>" + Cer.esc(ch.u.from) + "</font>  "
        + "<font color='" + Ceres.ink.arrow + "'>→</font>  "
        + "<font color='" + Zenon.accentKey + "'>" + Cer.esc(ch.u.to.slice(0, vers.same)) + "</font>"
        + "<b>" + Cer.esc(ch.u.to.slice(vers.same)) + "</b>"
      : Cer.esc(ch.u.to || ""))
    color: Zenon.white
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(14) + ch.grow
  }
}
