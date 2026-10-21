// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// terminus' space map layout: every tile inside the box, areas in
// proportion, nothing overlapping, near square, and the long tail folded.

"use strict";

module.exports = {
  module: "terminus/treemap.js",
  cases: (T, t) => {
    const W = 600, H = 400;
    const vals = [500, 300, 120, 60, 10, 5, 3, 1, 0, -4];
    const r = T.squarify(vals, 0, 0, W, H);
    t.eq("a tile for every positive value", r.length, 8);
    t.eq("none for zero or less", r.some((q) => vals[q.i] <= 0), false);
    const eps = 1e-6;
    t.eq("every tile inside the box", r.every((q) => q.x >= -eps && q.y >= -eps && q.x + q.w <= W + eps && q.y + q.h <= H + eps), true);
    const total = vals.filter((v) => v > 0).reduce((a, b) => a + b, 0);
    t.eq("areas in proportion", r.every((q) => Math.abs(q.w * q.h - vals[q.i] / total * W * H) < 1e-3), true);
    t.eq("the box filled", Math.round(r.reduce((a, q) => a + q.w * q.h, 0)), W * H);
    let overlap = false;
    for (let a = 0; a < r.length; ++a) for (let b = a + 1; b < r.length; ++b) {
      const A = r[a], B = r[b];
      if (A.x + eps < B.x + B.w && B.x + eps < A.x + A.w && A.y + eps < B.y + B.h && B.y + eps < A.y + A.h) overlap = true;
    }
    t.eq("no overlaps", overlap, false);
    const big = r.find((q) => q.i === 0);
    t.ok("the biggest is near square", Math.max(big.w / big.h, big.h / big.w) < 2.5);
    t.eq("nothing in nothing", T.squarify([], 0, 0, W, H), []);
    t.eq("no room, no tiles", T.squarify([1, 2], 0, 0, 0, H), []);
    t.eq("one value is the whole box", T.squarify([7], 10, 20, 100, 50), [{ i: 0, x: 10, y: 20, w: 100, h: 50 }]);

    // the long tail
    const items = [];
    for (let i = 0; i < 100; ++i) items.push({ key: "f" + i, value: 100 - i });
    const c = T.capItems(items, 10);
    t.eq("capped", c.length, 10);
    t.eq("the biggest kept", c[0].key, "f0");
    t.eq("the rest folded", [c[9].rest, c[9].count], [true, 91]);
    t.eq("the rest's size is theirs", c[9].value, items.slice(9).reduce((a, b) => a + b.value, 0));
    t.eq("under the cap, untouched", T.capItems(items.slice(0, 3), 10).length, 3);
    t.eq("labels", [T.labelFit(100, 50), T.labelFit(50, 25), T.labelFit(20, 20)], [2, 1, 0]);
  }
};
