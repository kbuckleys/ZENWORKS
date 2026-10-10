// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── HOW A SCROLL FEELS, IN NUMBERS ──────────────────────────────────────
// The macOS feel, as pure functions: Elastic (and plato's editor, and
// picasso's strip, which cannot be an Elastic) do the moving; this says how
// far and how fast. Kept apart so the curves are tested without a window
// (oracle/tests/scrollfeel.js) and so there is one copy of each number.
//
// FOUR THINGS make a Mac's scrolling feel the way it does, and none of them
// is the direction:
//
//   1. A WHEEL ACCELERATES. A notch on its own moves a step; notches coming
//      fast move several steps each, more the faster they come. Reading a
//      long file is a flick of the wheel, and stopping on a line is still a
//      single click. Speed is counted in notches a second over the last
//      moment, so a high-resolution wheel sending eighths of a notch counts
//      the same as one sending whole ones.
//   2. IT EASES THERE. Each notch moves the target; the view closes on it
//      exponentially, so a notch added mid-flight continues the motion
//      rather than starting a new one (an ease restarted per notch lurches
//      every notch).
//   3. A FINGER IS FOLLOWED EXACTLY, and when it lifts the content keeps
//      going at the speed it had and slows — UIScrollView's "normal"
//      deceleration, 0.998 of the speed kept per millisecond.
//   4. THE EDGES GIVE (Elastic's rubber band, which already had Apple's
//      curve); momentum that runs into one bounces off it.

// ── 1. the wheel's acceleration ─────────────────────────────────────────
// How far back a burst of notches is remembered, in ms.
var RATE_WINDOW = 160;
// Up to this many notches a second, a notch is one step.
var RATE_CALM = 7;
// Most one notch can be worth, however hard the wheel is spun.
var GAIN_MAX = 5;

function makeRate() { return { at: [], n: [], dir: 0 }; }

// A notch (or a fraction of one, signed) at time `t` ms. Returns the speed,
// in notches a second, counting this one. A turn the other way starts over:
// reversing is stopping, not a faster scroll.
function rateAdd(st, t, notches) {
  var dir = notches > 0 ? 1 : notches < 0 ? -1 : 0;
  if (dir !== 0 && dir !== st.dir) { st.at = []; st.n = []; st.dir = dir; }
  st.at.push(t);
  st.n.push(Math.abs(notches));
  while (st.at.length > 0 && t - st.at[0] > RATE_WINDOW) { st.at.shift(); st.n.shift(); }
  var sum = 0;
  for (var i = 0; i < st.n.length; ++i) sum += st.n[i];
  return sum * 1000 / RATE_WINDOW;
}

// What one notch is worth at that speed, in steps: 1 when calm, rising on
// a square past it, capped.
function wheelGain(rate) {
  if (!(rate > RATE_CALM)) return 1;
  var x = (rate - RATE_CALM) / 10;
  return Math.min(GAIN_MAX, 1 + 2 * x * x);
}

// ── 2. the eased follow ─────────────────────────────────────────────────
// The time constant: 63% of the way in this many ms, all but a pixel in
// about five of them.
var FOLLOW_TAU = 42;

// Where `y` is `dt` ms later, closing on `goal`. Within half a pixel it
// lands, so the follow ends rather than creeping for ever.
function follow(y, goal, dt, tau) {
  var k = 1 - Math.exp(-Math.max(0, dt) / (tau || FOLLOW_TAU));
  var next = y + (goal - y) * k;
  return Math.abs(goal - next) < 0.5 ? goal : next;
}

// ── 3. the finger, and the coast after it ───────────────────────────────
// The finger's speed is taken over its last moments only: the start of a
// long drag says nothing about how it was let go.
var VELOCITY_WINDOW = 90;

function makeTrack() { return { at: [], d: [] }; }
// a finger's move of `d` px at time `t` ms
function trackAdd(tr, t, d) {
  tr.at.push(t);
  tr.d.push(d);
  while (tr.at.length > 0 && t - tr.at[0] > VELOCITY_WINDOW) { tr.at.shift(); tr.d.shift(); }
}
// px/ms at time `t`; 0 when the finger had stopped before lifting
function trackVelocity(tr, t) {
  var sum = 0, first = -1;
  for (var i = 0; i < tr.at.length; ++i) {
    if (t - tr.at[i] > VELOCITY_WINDOW) continue;
    if (first < 0) first = tr.at[i];
    sum += tr.d[i];
  }
  if (first < 0) return 0;
  // the span the moves were made over: at least a frame, or one quick
  // event would read as an enormous speed
  var span = Math.max(16, t - first);
  return sum / span;
}

// UIScrollView's normal deceleration: the speed kept per ms.
var DECEL = 0.998;
// Slower than this (px/ms, 30 px/s) and it has stopped.
var REST = 0.03;
// Faster than this out of a finger is a measuring error, not a fling.
var VMAX = 8;

function clampVelocity(v) { return Math.max(-VMAX, Math.min(VMAX, v)); }

// One frame of the coast: how far it goes in `dt` ms at speed `v`, and the
// speed after. The distance is the exact integral of the decay over the
// frame, so a slow frame does not overshoot.
function coastStep(v, dt) {
  var k = Math.pow(DECEL, dt);
  var lnd = Math.log(DECEL);
  return { d: v * (k - 1) / lnd, v: Math.abs(v * k) < REST ? 0 : v * k };
}
// how far a coast at `v` goes in all (for the tests, and for a caller that
// wants to know where it will land)
function coastDistance(v) { return -v / Math.log(DECEL); }

// ── 4. momentum into an edge ────────────────────────────────────────────
// How far past the edge a coast at speed `v` carries the content before the
// band brings it back: the speed's worth of 40 ms, never more than the
// band's own reach (`most`, Elastic's cap for the view).
function bounceFor(v, most) {
  return Math.min(most, Math.abs(v) * 40);
}
