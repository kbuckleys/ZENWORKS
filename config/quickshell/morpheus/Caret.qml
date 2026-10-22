// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CARET — the text cursor every field in this shell wears.
//
//   cursorDelegate: Caret { field: myField }
//
// A cursorDelegate REPLACES the built-in one, so there is exactly one caret
// and this decides how it behaves. It breathes rather than blinking: a hard
// on/off is Qt's default, and in a field that is already asking for your
// attention it reads as a fault.
//
// Only while the field has focus. The breath stops on focus loss but the
// delegate does not go away, so without `visible` a field you had typed in
// kept a caret frozen at whatever opacity the breath had reached. Clio found
// that first; it was one copy of fourteen that knew.
//
// ── WHAT A BREATH COSTS, AND WHY IT IS STEPPED ─────────────────────────
// Qt Quick redraws the WHOLE window for any change, however small, so a
// caret's opacity is a whole-window redraw on every step. As a
// NumberAnimation that was every refresh: 180 a second on DP-1. On a
// full-screen layer (a sticky's board, every LayerPopup) that is the whole
// screen 180 times a second, mostly GPU. A sticky's right-click menu
// crawled at ~10 fps behind it and the bar fell to 4 fps (2026-10-22,
// measured): every window's render thread waits on the same GPU.
//
// So the breath is STEPPED, `stepHz` (30) times a second off a Timer, on
// the same curve (Zenon.breath halves, InOutQuad = Zenon.breathEase), and a
// window redraws 30 times a second for it, not at the monitor's rate. Then
// it RESTS: `restMs` (5 s) with the caret unmoved and it holds at full and
// stops, so an idle field costs nothing. A move, a keystroke or focus
// wakes it. (user, 2026-10-22)
//
// ONE CARET, NO EXCEPTIONS (user, 2026-10-22). A caret a component draws
// for itself is a Caret too, shaped as it likes (plato's block/bar/
// underline, its command line's), waking it with wake(). Every editable
// TextInput and TextEdit says `cursorDelegate: Caret { field: <its id> }`,
// windows and popups alike, hidden helpers too — Qt's own cursor blinks on
// a timer of its own and costs redraws we do not control. Only a readOnly
// field (Qt draws no cursor there) or one with `cursorVisible: false` goes
// without. scripts/lintgate.py fails any other.
//
// Never put an Animation on a caret again, and think twice before any
// infinite animation on a full-screen surface.

import QtQuick
import "."

Rectangle {
  id: caret

  // the TextInput or TextEdit this is the cursor of
  property Item field: null

  // how thick, and how far the breath fades — a page of writing (clio)
  // wants a plainer caret than a one-line field
  property int thick: 2
  property real low: 0.2
  // `steady`: held full while the caret moves (typing, arrows), breathing
  // again only once it rests
  property bool steady: false

  // `breathes`: off, the caret is shown full and still (plato's "Breathing
  // cursor" setting)
  property bool breathes: true
  onBreathesChanged: if (!caret.breathes) caret.opacity = 1

  readonly property int stepHz: 30
  readonly property int restMs: 5000

  width: caret.thick
  color: Zenon.cyan
  // and only while the field is drawn: a hidden key catcher (plato's
  // settings query, opacity 0) has focus all the time, and a caret
  // breathing there redrew the window for nothing
  visible: caret.field !== null && caret.active
    && caret.field.visible && caret.field.opacity > 0
  // when it is shown: the field having the keyboard, unless the owner says
  // otherwise — ceres' filter never takes focus (the window's keys edit
  // it), cynosure's shows only in search with nothing found. Qt makes the
  // delegate only once the field's cursorVisible is true, so an owner that
  // sets this binds cursorVisible to the same.
  property bool active: caret.field !== null && caret.field.activeFocus
  opacity: 1

  // when this breath began, and when the caret last moved
  property double t0: 0
  property double woke: 0
  property bool resting: false

  function wake(restartBreath) {
    const now = Date.now();
    caret.woke = now;
    if (restartBreath || caret.resting) { caret.t0 = now; caret.opacity = 1; }
    caret.resting = false;
  }
  onVisibleChanged: if (caret.visible) caret.wake(true)

  // the breath's opacity `ms` into one cycle: an optional hold at full
  // (steady), down to `low`, back up — InOutQuad, as Zenon.breathEase
  function at(ms) {
    const hold = caret.steady ? 500 : 0;
    const half = Zenon.breath;
    const t = ms % (hold + half * 2);
    if (t < hold) return 1;
    const down = t - hold < half;
    const x = down ? (t - hold) / half : (t - hold - half) / half;
    const e = x < 0.5 ? 2 * x * x : 1 - Math.pow(-2 * x + 2, 2) / 2;
    return down ? 1 - (1 - caret.low) * e : caret.low + (1 - caret.low) * e;
  }

  Timer {
    interval: Math.round(1000 / caret.stepHz)
    repeat: true
    running: caret.visible && caret.breathes && !caret.resting
    onTriggered: {
      const now = Date.now();
      // rest at full, at the top of a breath so it never snaps up
      if (now - caret.woke >= caret.restMs && caret.at(now - caret.t0) > 0.97) {
        caret.opacity = 1;
        caret.resting = true;
        return;
      }
      caret.opacity = caret.at(now - caret.t0);
    }
  }

  Connections {
    target: caret.field
    ignoreUnknownSignals: true
    function onCursorPositionChanged() { caret.wake(caret.steady); }
  }
}
