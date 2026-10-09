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
  // How far in from the left the well starts — terminus' sidebar runs the
  // full height of its window, and a sheet hangs from the bar BESIDE it, so it
  // is centred under that bar rather than across the whole window.
  property real leftInset: 0

  // ── OR RISING FROM THE FOOT ──────────────────────────────────────────
  // The same card turned over: it hangs from the BOTTOM of the well — the
  // top of a status bar `toBottom` px tall, or the window's foot — square
  // below, rounded above, and comes up out of that edge and goes back down
  // into it. For the cards about the keys being typed (plato's leader menu
  // and its key hints), which belong down by the command line, not up by
  // the tabs. Off, nothing here changes.
  property bool fromBottom: false
  // Set around a change of END on a hidden sheet (see PlatoSheet.setEnd):
  // the card's y jumps to the new end instead of travelling there, so a
  // sheet that last came from the top and now rises from the bottom does
  // not fly down the window on its way up.
  property bool noGlide: false
  property real toBottom: 0

  // ── OR FLOATING, WITH A TITLE OF ITS OWN ─────────────────────────────
  // Off by default, which is the sheet hanging from the bar exactly as
  // before. On, the card is DETACHED: every corner rounded, standing a
  // in the middle of the window rather than coming out from under the bar, arriving
  // with a fade and a short settle — and because it no longer touches the
  // bar it cannot borrow the bar for its name, so it carries a header row
  // of its own: the glyph and the title. (Terminus' sheets hang instead, and
  // its bar wears their title — see barTitle there.)
  property bool floating: false
  // ── SPLICED OUT OF THE BAR ────────────────────────────────────────────
  // A floating sheet (its own title on the card) that hangs from the chrome
  // instead of floating below it: flush to the bar's bottom edge, top
  // corners hidden in the cut, sliding down out of it — and, frosted, its
  // glass fades in from the seam, so the bar and the card read as one piece
  // (the host opens its hairline over `drawnX`/`drawnW` and goes black on
  // `cardInk`).
  property bool splice: false
  readonly property bool hangs: !sheet.floating || sheet.splice
  property string title: ""
  property string glyph: ""
  property color titleInk: Zenon.white
  property color glyphInk: Zenon.cyan
  // The least a floating card stands below the bar, when the window is too
  // short to centre it.
  property real gap: 18
  // LATCHED while the card is up: a caller's title is usually derived from
  // whichever sheet is open, and it empties the moment the sheet is told to
  // go — which would blank the header for the whole of the fade out.
  property string heldTitle: ""
  property string heldGlyph: ""
  //
  // ONLY A NAME REPLACES A NAME while it is up. The caller's title empties
  // in the same tick `shown` goes false, and which of the two Qt delivers
  // first is not ours to choose: when the title went first, this latched the
  // empty string with the card still up, and the header vanished on the
  // first frame of the fade — taking its 36px with it, so the whole card
  // jumped. Opening takes the title as it is, empty or not.
  function latch() {
    if (!sheet.shown) return;
    sheet.heldTitle = sheet.title;
    sheet.heldGlyph = sheet.glyph;
  }
  onShownChanged: sheet.latch()
  onTitleChanged: { if (sheet.title !== "") sheet.latch(); }
  onGlyphChanged: { if (sheet.glyph !== "") sheet.latch(); }

  // ── SIZE MOVES ONLY ONCE THE CARD HAS ARRIVED ──────────────────────
  // A card keeps the size it had the last time it was up, so on opening the
  // new content's size was ANIMATED to from the old one — the card visibly
  // grew while it faded in. And on the way out anything that changed in
  // the content resized a card that was leaving. So the size snaps until
  // the arrival is over, and from then on a change in content eases.
  property bool settled: false
  Timer {
    id: settleTimer
    interval: sheet.slideIn
    onTriggered: sheet.settled = sheet.shown
  }
  Connections {
    target: sheet
    function onShownChanged() {
      sheet.settled = false;
      if (sheet.shown) settleTimer.restart(); else settleTimer.stop();
    }
  }
  readonly property real headH: sheet.floating && sheet.heldTitle !== "" ? 36 : 0
  // What the CONTENT wants. The corner radius is added on top, because the
  // card's top sits that far above the clip and those pixels are cut away.
  // ── FROSTED GLASS ─────────────────────────────────────────────────────
  // What the card lies over, frosted through it (morpheus/Frost) instead of
  // a black card standing on it — the window's content, never an item the
  // sheet itself is inside (a capture of itself would feed back). Unset,
  // the card is the solid black it always was. `glass` is how much black is
  // left over the frost, so what is written on the card stays legible.
  property Item backdrop: null
  // over a black floor now (Frost.base); a touch darker than the bars
  // ask, so the card reads as a card
  property real glass: 0.8
  // how soft the frost is: a host whose content is thin text (an editor)
  // blurs less, or there is no shape left to see
  property int blur: 32
  // and how many times that frost is stacked to bring thin content back up
  // (Frost.gain; plato's sheets use 3, and splice from its bars too).
  property int gain: 1
  readonly property bool frosted: !!sheet.backdrop

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

  // WHERE IT MEETS THE BAR, in the sheet's own frame — the well's inset
  // counted in, so a sheet hung beside a sidebar still answers in the
  // window's terms — which is what the bar needs to open a gap in its
  // bottom edge exactly this wide, exactly here.
  readonly property real drawnX: well.x + sheetCard.x
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
  readonly property real cut: sheet.hangs ? Zenon.dialogRadius : 0

  // The well is everything BELOW the chrome and it clips, so the sheet is
  // genuinely hidden behind the bar rather than fading out on top of it.
  Item {
    id: well
    anchors.left: parent.left
    // Only a sheet hanging from the bar is inset to sit under it. A floating
    // card is centred on the WHOLE window — a sidebar that is out is part of
    // the window, and centring on the listing beside it put the card off to
    // one side.
    anchors.leftMargin: sheet.floating ? 0 : sheet.leftInset
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: sheet.fromTop
    anchors.bottom: parent.bottom
    anchors.bottomMargin: sheet.fromBottom ? sheet.toBottom : 0
    // a floating card is not hidden behind the bar, it fades in front of it
    clip: sheet.hangs

    // Inside the well, so the part that would fall across the bar is cut
    // off with it: a sheet hanging from the chrome does not cast upwards.
    MenuShadow {
      panel: sheetCard
      cornerRadius: Zenon.dialogRadius
      opacity: sheetCard.opacity
    }

    // ── THE FROST, UNDER THE CARD, NOT IN IT ─────────────────────────────
    // A ClippingRectangle renders no MultiEffect inside it, so the glass is
    // laid here and follows the card — place, size, scale, fade — with its
    // own rounded corners (Frost.radius).
    Frost {
      id: cardFrost
      x: sheetCard.x
      y: sheetCard.y
      width: sheetCard.width
      height: sheetCard.height
      scale: sheetCard.scale
      opacity: sheetCard.opacity
      radius: Zenon.dialogRadius
      // solid under the blur: a listing's text is no cover for itself
      base: Zenon.black
      // hanging from a bar: the blur comes in below the seam (the cut is
      // hidden above the well's top, so it is counted in)
      fadeTop: sheet.hangs && !sheet.fromBottom ? sheet.cut + 28 : 0
      fadeBottom: sheet.hangs && sheet.fromBottom ? sheet.cut + 28 : 0
      // softer than a bar's: thin text blurred at 64 is no shape at all
      blurMax: sheet.blur
      gain: sheet.gain
      visible: sheet.frosted
      source: sheet.backdrop
      active: sheet.frosted && sheetCard.opacity > 0.01
      scrim: 0
      track: [well.x, well.y]
    }

    ClippingRectangle {
      id: sheetCard
      // ── ON WHOLE PIXELS ─────────────────────────────────────────────
      // Centring is a halving, and half of an odd number is half a pixel:
      // a card at x.5 or y.5 has every glyph in it resampled across two
      // pixel columns, which is exactly what blurry text in a card is.
      // Position and size are rounded so the content lands on the grid.
      x: Math.round((well.width - sheetCard.width) / 2)
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
      width: Math.round(Math.min(sheet.cardW + 2 * sheetCard.border.width,
                      well.width - 40))
      height: Math.round(Math.min(sheet.cardH + sheet.cut + sheet.headH + 2 * sheetCard.border.width,
                       well.height - 40 - (sheet.hangs ? 0 : sheet.gap)))
      Behavior on width {
        enabled: sheet.settled
        NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
      }
      Behavior on height {
        enabled: sheet.settled
        NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
      }

      // AT REST ITS TOP SITS ABOVE THE CLIP by exactly the corner radius,
      // so the rounded top corners are cut away and the sheet reads as
      // hanging FROM the bar rather than floating below it. Rounded at the
      // bottom, square at the top.
      // floating: centred on the whole window, the bar included — the well
      // starts under the bar, so its own middle would sit low — and never
      // closer to the bar than `gap`. It rises the last few pixels in.
      readonly property real restY: Math.round(Math.max(sheet.gap,
        (well.height + sheet.fromTop - sheetCard.height) / 2 - sheet.fromTop))
      // ── THE RISE IS AN OFFSET, NOT A DESTINATION ──────────────────
      // restY is a centring, so it moves whenever the card's height does —
      // and a Behavior on y aimed at it was retargeted mid-flight every time
      // the content settled, which is a hitch in the middle of the rise.
      // The centre is followed exactly; only the 12px lift animates.
      property real lift: sheet.shown ? 0 : 12
      Behavior on lift {
        NumberAnimation {
          duration: sheet.shown ? sheet.slideIn : sheet.slideOut
          easing.type: sheet.shown ? Zenon.sheetInEase : Zenon.sheetOutEase
        }
      }
      y: !sheet.hangs ? sheetCard.restY + sheetCard.lift
        : sheet.fromBottom
          ? (sheet.shown ? well.height - sheetCard.height + Zenon.dialogRadius : well.height + 2)
          : (sheet.shown ? -Zenon.dialogRadius : -sheetCard.height - 2)
      scale: !sheet.hangs ? (sheet.shown ? 1 : 0.97) : 1
      Behavior on scale {
        NumberAnimation {
          duration: sheet.shown ? sheet.slideIn : sheet.slideOut
          easing.type: sheet.shown ? Zenon.sheetInEase : Zenon.sheetOutEase
        }
      }

      // Down on a curve that settles, up on one that accelerates away: a
      // sheet arrives and is dismissed, it does not do the same thing twice.
      Behavior on y {
        enabled: sheet.hangs && !sheet.noGlide
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

      color: sheet.frosted ? "transparent" : Zenon.black
      border.color: Zenon.border
      border.width: 1
      radius: Zenon.dialogRadius

      // the black over the frost (which is under the card — see cardFrost);
      // first, so everything on the card draws over it
      Rectangle {
        anchors.fill: parent
        visible: sheet.frosted
        color: Zenon.floor(Zenon.glass(sheet.glass))
      }

      // The card keeps its own clicks, so a press on its empty space does
      // not fall through to the scrim behind and dismiss what you are
      // filling in.
      InputShield {}

      // Below the cut. Everything a caller puts in the sheet lands here, so
      // no caller has to know that the top of the card is not the top of
      // the sheet.
      // the floating card's own name — see `floating`
      Item {
        id: sheetHead
        visible: sheet.headH > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        // below the cut, which a spliced sheet keeps hidden above the bar
        anchors.topMargin: sheet.fromBottom ? 0 : sheet.cut
        height: sheet.headH

        Row {
          anchors.centerIn: parent
          spacing: 8
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: sheet.heldGlyph !== ""
            text: sheet.heldGlyph
            color: sheet.glyphInk
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(16)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, sheetHead.width - 80)
            elide: Text.ElideMiddle
            text: sheet.heldTitle
            color: sheet.titleInk
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(16)
          }
        }
        Rectangle {
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: Zenon.border
        }
      }

      Item {
        id: sheetBody
        anchors.fill: parent
        // from the foot, the cut corners are the bottom ones
        anchors.topMargin: (sheet.fromBottom ? 0 : sheet.cut) + sheet.headH
        anchors.bottomMargin: sheet.fromBottom ? sheet.cut : 0
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
