// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// zeus/sound.js: a volume kept under the ceiling Zeus sets, without pulling
// a device something else put above it back down (2026-10-23: volume up on
// a 120% sink dropped it to 100%).

"use strict";

module.exports = {
  module: "zeus/sound.js",
  cases: (S, t) => {
    t.eq("under the ceiling, as asked", S.clampVolume(0.55, 0.5, 1), 0.55);
    t.eq("up to the ceiling, no further", S.clampVolume(1.05, 0.98, 1), 1);
    t.eq("never below nothing", S.clampVolume(-0.05, 0.02, 1), 0);
    t.eq("above it already: up stays where it is", S.clampVolume(1.25, 1.2, 1), 1.2);
    t.eq("above it already: down goes down", S.clampVolume(1.15, 1.2, 1), 1.15);
  }
};
