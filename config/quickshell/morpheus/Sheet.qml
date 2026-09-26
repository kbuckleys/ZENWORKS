// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TERMINUS' SHEET, SHARED — a card that hangs from a window's chrome, drops
// in, and goes back the way it came. It was an inline component of
// TerminusWindow; ceres' password prompt wanted the same one, so it lives
// here and both use this file. See the notes inside for why each part is the
// way it is; they came with it.

import QtQuick
import Quickshell.Widgets
import "."

Item {
  id: sheet
  anchors.fill: parent

  property bool shown: false
  property real fromTop: 0
  // What the CONTENT wants. The corner radius is added on top, because the
  // card's top sits that far above the clip and those pixels are cut away.
  property real cardW: 560
  property real cardH: 200
  default property alias body: sheetBody.data

  // A SHEET IS SLOWER THAN A MENU. It is a bigger object and it travels
  // further, so the shared durations — sized for a card that appears where
  // the pointer already is — read as a snap here. Multiples of the token,
  // so turning the desktop's motion down turns these down too.
  //
  // On the sheet's root rather than on the card, because the scrim and the
  // blur behind it have to move at the same speed: a window that went soft
  // before the sheet had left the bar was two events where there is one.
  //
  // LEAVING IS FASTER THAN ARRIVING, and by more than it was. A sheet
  // arriving is the event — it is worth the travel, and 2.0 is what makes it
  // read as one object moving rather than a card appearing. Dismissing one
  // is not an event, it is getting out of the way, and 1.3 left you watching
  // it go. Same asymmetry every card in this window follows, just further
  // apart: 340ms in, 128ms out.
  readonly property int slideIn: Zenon.sheetIn
  readonly property int slideOut: Zenon.sheetOut

  // HOW FAR ALONG THE ARRIVAL IS, for anything outside the sheet that has
  // to move with it — the bar's own header, and the blur behind. Read off
  // the card rather than the overlay, which never fades.
  readonly property real cardInk: sheetCard.opacity

  // WHERE IT MEETS THE BAR. The well spans the window, so the card's own x
  // is already the window's — which is what the bar needs to open a gap in
  // its bottom edge exactly this wide, exactly here.
  readonly property real drawnX: sheetCard.x
  readonly property real drawnW: sheetCard.width

  // WHAT IS NOT CONTENT: the corner radius, which is cut away above the
  // clip, and nothing else.
  //
  // NO AIR OF ITS OWN, and that is the whole of the rule. Every card's
  // first row already carries its own — a field centred in a 46px row
  // leaves 11 above it, a line of text with a 12px margin leaves 12 — which
  // is what put the air under the caption band when there was one. Adding
  // more here does not replace that, it stacks on it: measured at 23px of
  // nothing between the bar and the first field of the rename card, which
  // is this 12 plus that 11.
  readonly property real cut: Zenon.dialogRadius

  // The well is everything BELOW the chrome and it clips, so the sheet is
  // genuinely hidden behind the bar rather than fading out on top of it.
  Item {
    id: well
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: sheet.fromTop
    anchors.bottom: parent.bottom
    clip: true

    // Inside the well, so the part that would fall across the bar is cut
    // off with it: a sheet hanging from the chrome does not cast upwards.
    MenuShadow {
      panel: sheetCard
      cornerRadius: Zenon.dialogRadius
      opacity: sheetCard.opacity
    }

    ClippingRectangle {
      id: sheetCard
      anchors.horizontalCenter: parent.horizontalCenter
      // THE BORDER IS NOT PART OF THE ROOM. A ClippingRectangle insets what
      // it holds by its own border on every side, so a card built to hold
      // exactly cardH gave its contents cardH LESS TWO — measured: a 466
      // card handing its body 464, and a palette that asks for fourteen
      // 30px rows getting 418 pixels and slicing the fourteenth.
      //
      // Added to the card rather than subtracted from the caller, because
      // cardW and cardH are what the CONTENT wants and no caller should have
      // to know what the frame around it costs.
      //
      // BOTH AXES. The height was fixed when a sheet sliced a row; the width
      // was left because nothing depended on it being exact — which is only
      // true until something does, and then it is two pixels nobody can
      // find. The well's cap is left alone: that is a ceiling against the
      // window, not a request.
      width: Math.min(sheet.cardW + 2 * sheetCard.border.width,
                      well.width - 40)
      height: Math.min(sheet.cardH + sheet.cut + 2 * sheetCard.border.width,
                       well.height - 40)
      Behavior on width {
        NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
      }
      Behavior on height {
        NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
      }

      // AT REST ITS TOP SITS ABOVE THE CLIP by exactly the corner radius,
      // so the rounded top corners are cut away and the sheet reads as
      // hanging FROM the bar rather than floating below it. Rounded at the
      // bottom, square at the top.
      y: sheet.shown ? -Zenon.dialogRadius : -sheetCard.height - 2

      // Down on a curve that settles, up on one that accelerates away: a
      // sheet arrives and is dismissed, it does not do the same thing twice.
      Behavior on y {
        NumberAnimation {
          duration: sheet.shown ? sheet.slideIn : sheet.slideOut
          easing.type: sheet.shown ? Zenon.sheetInEase : Zenon.sheetOutEase
        }
      }
      opacity: sheet.shown ? 1 : 0
      Behavior on opacity {
        NumberAnimation {
          duration: sheet.shown ? sheet.slideIn : sheet.slideOut
          easing.type: sheet.shown ? Zenon.sheetInEase : Zenon.sheetOutEase
        }
      }

      color: Zenon.black
      border.color: Zenon.border
      border.width: 1
      radius: Zenon.dialogRadius

      // The card keeps its own clicks, so a press on its empty space does
      // not fall through to the scrim behind and dismiss what you are
      // filling in.
      InputShield {}

      // Below the cut. Everything a caller puts in the sheet lands here, so
      // no caller has to know that the top of the card is not the top of
      // the sheet.
      Item {
        id: sheetBody
        anchors.fill: parent
        anchors.topMargin: sheet.cut
      }
    }
  }
}

// ── HOW A CARD ARRIVES, AND LEAVES THE SAME WAY ────────────────────────
// Seven cards carried `Translate { y: (1 - card.opacity) * 10 }`, which is
// not an animation but a side effect of one: the travel was a FUNCTION of
// the fade, so the two could never have different curves, different
// durations, or different shapes, and ten pixels of drift welded to an
// opacity ramp is what "static" looks like.
//
// Driven by `shown` instead, so the motion is its own animation with its
// own easing — travelEase, the curve the columns and the sheet move on,
// rather than the fade's. And ASYMMETRIC: arriving takes the full normal,
// leaving takes fast, which is the rule the send sheet already follows. The
// duration binding is read when the animation starts, by which time `shown`
// is already the value being animated TO, so one expression gives both.
