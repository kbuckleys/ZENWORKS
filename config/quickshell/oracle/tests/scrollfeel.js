// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The scroll feel's curves (morpheus/scrollfeel.js): a calm wheel moves a
// step a notch, a spun one more; the follow closes and lands; a finger's
// speed is its last moments'; the coast decays as UIScrollView's does and
// stops.

"use strict";

module.exports = {
  module: "morpheus/scrollfeel.js",
  cases: (F, t) => {
    // ── the wheel ─────────────────────────────────────────────────────────
    let st = F.makeRate();
    let r = 0;
    for (let i = 0; i < 5; ++i) r = F.rateAdd(st, i * 250, -1);
    t.eq("a notch every 250 ms is calm: one step a notch", F.wheelGain(r), 1);

    st = F.makeRate();
    for (let i = 0; i < 12; ++i) r = F.rateAdd(st, i * 20, -1);
    t.ok("a spun wheel (50 notches/s) is worth several steps a notch", F.wheelGain(r) > 3, r);
    t.ok("but never more than the cap", F.wheelGain(1e6) === F.GAIN_MAX);

    st = F.makeRate();
    let whole = 0, eighths = 0;
    for (let i = 0; i < 6; ++i) whole = F.rateAdd(st, i * 30, 1);
    st = F.makeRate();
    for (let i = 0; i < 48; ++i) eighths = F.rateAdd(st, i * 30 / 8, 0.125);
    t.ok("a high-resolution wheel counts as the notches it adds up to",
      Math.abs(whole - eighths) < whole * 0.25, whole + " vs " + eighths);

    st = F.makeRate();
    for (let i = 0; i < 10; ++i) F.rateAdd(st, i * 20, 1);
    r = F.rateAdd(st, 200, -1);
    t.eq("turning back starts over, calm", F.wheelGain(r), 1);

    st = F.makeRate();
    for (let i = 0; i < 10; ++i) F.rateAdd(st, i * 20, 1);
    r = F.rateAdd(st, 2000, 1);
    t.eq("a notch after a pause is calm again", F.wheelGain(r), 1);

    // the gain rises with the speed
    t.ok("faster is never worth less", F.wheelGain(12) <= F.wheelGain(20) && F.wheelGain(20) <= F.wheelGain(30));

    // ── the follow ────────────────────────────────────────────────────────
    let y = 0;
    for (let i = 0; i < 4; ++i) y = F.follow(y, 100, 16);
    t.ok("most of the way in four frames", y > 70 && y < 100, y);
    for (let i = 0; i < 60; ++i) y = F.follow(y, 100, 16);
    t.eq("and lands exactly", y, 100);
    t.eq("no time, no move", F.follow(10, 100, 0), 10);
    t.ok("one long frame does not overshoot", F.follow(0, 100, 1000) === 100);

    // ── the finger ────────────────────────────────────────────────────────
    const tr = F.makeTrack();
    for (let i = 0; i < 20; ++i) F.trackAdd(tr, i * 10, 20);
    t.ok("a steady 20 px every 10 ms reads as about 2 px/ms",
      Math.abs(F.trackVelocity(tr, 190) - 2) < 0.3, F.trackVelocity(tr, 190));
    t.eq("a finger that stopped before lifting has no speed", F.trackVelocity(tr, 600), 0);
    const one = F.makeTrack();
    F.trackAdd(one, 0, 30);
    t.ok("one event is not an enormous speed", F.trackVelocity(one, 0) <= 30 / 16);

    // ── the coast ─────────────────────────────────────────────────────────
    let v = 2, d = 0, frames = 0;
    while (v !== 0 && frames < 5000) { const s = F.coastStep(v, 16); d += s.d; v = s.v; frames++; }
    t.ok("a coast stops", v === 0 && frames < 5000, frames);
    t.ok("and goes about as far as the decay says",
      Math.abs(d - F.coastDistance(2)) < F.coastDistance(2) * 0.05, d + " vs " + F.coastDistance(2));
    t.ok("2 px/ms carries on for most of a screen", d > 600 && d < 1200, d);
    let a = 0, b = 0, va = 1.5, vb = 1.5;
    for (let i = 0; i < 30; ++i) { const s = F.coastStep(va, 16); a += s.d; va = s.v; }
    for (let i = 0; i < 15; ++i) { const s = F.coastStep(vb, 32); b += s.d; vb = s.v; }
    t.ok("the frame rate does not change where it goes", Math.abs(a - b) < 0.5, a + " vs " + b);
    t.ok("backwards goes backwards", F.coastStep(-2, 16).d < 0);
    t.eq("a fling past any real speed is clamped", F.clampVelocity(40), F.VMAX);

    // ── the edge ──────────────────────────────────────────────────────────
    t.ok("a faster arrival bounces further", F.bounceFor(2, 100) > F.bounceFor(0.5, 100));
    t.eq("never past the band's reach", F.bounceFor(50, 80), 80);
  }
};
