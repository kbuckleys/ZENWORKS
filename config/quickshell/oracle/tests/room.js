// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The room a floating window makes for a panel (morpheus/room.js): terminus'
// split and sidebar, plato's tree, minerva's sidebar.

"use strict";

module.exports = {
  module: "morpheus/room.js",
  cases: (R, t) => {
    const mons = [
      { id: 0, x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 3, reserved: [0, 0, 0, 38] },
      { id: 1, x: 1080, y: 0, width: 2560, height: 1440, scale: 1, transform: 0, reserved: [0, 0, 0, 0] }];
    const fl = (x, w, mon) => ({ floating: true, fullscreen: 0, monitor: mon, at: [x, 100], size: [w, 600] });
    t.eq("a split grows by what it asks",
      R.make(fl(1800, 1000, 1), mons, 1800, 16, 560).dw, 800);
    t.eq("never past the monitor",
      R.make(fl(1100, 1000, 1), mons, 3000, 16, 560).dw, 1528);
    t.eq("a rotated monitor is as narrow as it looks",
      R.make(fl(100, 800, 0), mons, 1600, 16, 560).dw, 1080 - 32 - 800);
    t.eq("tiled is the layout's business", R.make(Object.assign(fl(0, 800, 1), { floating: false }), mons, 1600, 16, 560), null);
    t.eq("so is fullscreen or maximized", R.make(Object.assign(fl(0, 800, 1), { fullscreen: 1 }), mons, 1600, 16, 560), null);
    t.eq("a hand-widened window is not shrunk by a grow",
      R.make(fl(1090, 1200, 0), mons, 2000, 16, 560), null);
    t.eq("an odd ask is evened, so a centered grow lands on whole pixels",
      R.make(fl(1800, 1000, 1), mons, 1271, 16, 560).dw, 270);
    t.eq("and an odd give-back too",
      R.make(fl(1800, 1271, 1), mons, 1000, 16, 560).dw, -270);
    t.eq("unsplitting hands the room back",
      R.make(fl(1400, 1800, 1), mons, 1000, 16, 560).dw, -800);
    // Resized first, always; moved only when the edge it grows from asks for
    // it — never recentered. Both relative, both naming the window.
    const sel = 'window = "address:0xab"';
    const still = R.dispatches("0xab", { dw: 10, dx: 0 });
    t.eq("no dx, no move", still.length, 1);
    t.ok("just the resize", still[0].indexOf("hl.dsp.window.resize(") === 0 && still[0].indexOf("x = 10,") >= 0);
    t.ok("named by address", still[0].indexOf(sel) >= 0);
    const moved = R.dispatches("0xab", { dw: -800, dx: 400 });
    t.eq("dx brings a move", moved.length, 2);
    t.ok("resize, then move", moved[0].indexOf("hl.dsp.window.resize(") === 0 && moved[1].indexOf("hl.dsp.window.move(") === 0);
    t.ok("both relative", moved.every((d) => d.indexOf("relative = true") >= 0));
    t.ok("the offsets are the room's", moved[0].indexOf("x = -800,") >= 0 && moved[1].indexOf("x = 400,") >= 0);
    t.ok("both named by address", moved.every((d) => d.indexOf(sel) >= 0));
    t.ok("nothing is centered", moved.concat(still).every((d) => !/cent(er|re)/.test(d)));
  }
};
