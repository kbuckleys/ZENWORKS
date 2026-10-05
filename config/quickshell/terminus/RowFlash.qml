// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ROWFLASH — a row lights up before it acts. Paired with FlashOver.qml, which
// is the lit row itself.
//
// An inline component of TerminusWindow until the open-with card (AppPicker)
// left that file and took its flash with it: artemis draws the same card.

import QtQuick

// ── A ROW LIGHTS UP BEFORE IT ACTS ──────────────────────────────────────
// Return used to act with the sheet vanishing on the keystroke, which leaves
// you unsure which row you were on at the moment it went. Sixty milliseconds
// up, a hundred and thirty down, and the verb runs on the tail of it.
//
// SHARED, because four sheets wore it and each carried its own copy of the
// same four things: an index, an ink, a SequentialAnimation and an overlay
// rectangle. Twenty-four references to one idea — which is why two of the
// three sheets written most recently shipped without it and had to be told.
// A sheet gets this by asking for it now, not by remembering it.
//
// WHAT RUNS ON THE TAIL is handed in as `onDone` rather than hard-wired,
// because what each sheet does at the end of the flash is the one part of
// this that genuinely differs: go somewhere, run a verb, launch an
// application.
Item {
  id: flash
  property int at: -1
  property real ink: 0
  property var onDone: null
  readonly property bool running: flashRun.running

  // Returns whether it took, so a caller can hold its own pending state only
  // when there is going to be a tail to spend it on.
  function fire(index) {
    if (flashRun.running) return false;
    flash.at = index;
    flashRun.restart();
    return true;
  }

  // Stopped, so the ScriptAction on the end never runs: leaving is a
  // decision not to, and a flash still in flight would have acted a tenth of
  // a second later.
  function cancel() {
    flashRun.stop();
    flash.ink = 0;
    flash.at = -1;
  }

  SequentialAnimation {
    id: flashRun
    NumberAnimation { target: flash; property: "ink"; to: 1;
                      duration: 60; easing.type: Easing.OutQuad }
    NumberAnimation { target: flash; property: "ink"; to: 0;
                      duration: 130; easing.type: Easing.InQuad }
    ScriptAction {
      script: {
        const f = flash.onDone;
        flash.at = -1;
        if (f) f();
      }
    }
  }
}

