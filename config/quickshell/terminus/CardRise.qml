// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── a small field on a card ─────────────────────────────────────────────
// The bulk rename card's two pattern boxes. A bare TextInput on a black card
// has no frame to say where it is or that it can be typed into, so two of
// them side by side read as two floating words.
// ── the shield a modal card stands behind ───────────────────────────────
//
// Everything a dialog has to STOP, in one place, because seven dialogs each
// had a bare `MouseArea { anchors.fill: parent }` and each one leaked the
// same three ways.
//
// ACCEPTS EVERY BUTTON. A MouseArea takes the left button only, so a right
// click over the scrim went straight through to the listing and opened the
// actions menu behind the card.
//
// EATS THE WHEEL, which a MouseArea does not see at all — so the rows kept
// scrolling underneath a panel that was describing one of them, and the
// cursor came back to a list that had moved.
//
// And the CARD gets one of its own, below its contents. A card is a plain
// Rectangle: a press on its empty space is not accepted by anything, falls
// through to the scrim behind, and dismissed the dialog you were filling in.
// Declared first inside a card so the buttons and fields above it still get
// their own clicks.
// ── a key, drawn as a key ─────────────────────────────────────────────
// The context menu and the F1 list are both answering the same question —
// what do I press — and they were answering it in two different voices: one
// in a border colour at 30% alpha that barely arrived on screen, the other
// as plain bold text that read as a second label competing with the first.
//
// One shape for both. A chip says "this is a thing you type" without having
// to be loud about it, which is what lets the ink come back up to something
// legible: it is the outline doing the separating now, not the dimness.
// ── A SHEET, WHICH IS WHAT EVERY CARD IN THIS WINDOW IS NOW ────────────
// The send picker proved the shape and the rest of the dialogs were still
// cards appearing in the middle of the screen from nowhere. A sheet says
// where it came from: it hangs off the chrome, it is clipped by a well that
// starts below the bar, and the way in is the way out reversed.
//
// Everything specific to one dialog is passed in — how wide, how tall, and
// whether it is up. Everything that makes it a sheet lives here once, so
// six dialogs cannot drift into six slightly different sheets.
//
// `fromTop` IS PASSED IN rather than read off the chrome. An inline
// component does not see the ids of the file it is declared in, and the
// band above the well is the tab strip plus the path bar — which only the
// caller can measure.
// (Its own file since quick look moved out of TerminusWindow — both use it.)

import QtQuick
import "../morpheus"

Translate {
  required property bool shown
  y: shown ? 0 : 14
  Behavior on y {
    NumberAnimation {
      duration: shown ? Zenon.normal : Zenon.fast
      easing.type: Zenon.travelEase
    }
  }
}
