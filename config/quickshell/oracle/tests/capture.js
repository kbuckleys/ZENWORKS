// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PICASSO'S CAPTURE: the names a screenshot is saved under, the region's
// geometry, and every color scheme the picker speaks.

"use strict";

module.exports = {
  module: "picasso/capture.js",
  cases: (C, t) => {
    const d = new Date(2026, 8, 26, 13, 46, 42);
    t.eq("the stamp hyprshot wrote", C.stamp(d), "2026-09-26-134642");
    t.eq("a screen is named for its monitor", C.fileName(d, "screen", "DP-1"), "2026-09-26-134642-DP-1.png");
    t.eq("a region says so", C.fileName(d, "region"), "2026-09-26-134642_region.png");
    t.eq("an annotated copy is marked", C.annotatedName("/a/b/shot.png"), "shot-annotated.png");

    t.eq("corners in any order", C.rectOf(50, 80, 10, 20, 100, 100), { x: 10, y: 20, w: 40, h: 60 });
    t.eq("clamped to the screen", C.rectOf(-5, -5, 500, 50, 100, 100), { x: 0, y: 0, w: 100, h: 50 });
    t.eq("a move stays on screen", C.moveRect({ x: 90, y: 0, w: 20, h: 10 }, 50, 0, 100, 100),
      { x: 80, y: 0, w: 20, h: 10 });
    t.eq("a corner drag", C.resizeRect({ x: 10, y: 10, w: 20, h: 20 }, "br", 5, 10, 100, 100),
      { x: 10, y: 10, w: 25, h: 30 });
    t.eq("dragged past the far edge flips", C.resizeRect({ x: 10, y: 10, w: 20, h: 20 }, "l", 30, 0, 100, 100),
      { x: 30, y: 10, w: 10, h: 20 });

    const wins = [{ x: 0, y: 0, w: 100, h: 100 }, { x: 20, y: 20, w: 30, h: 30 }];
    t.eq("the smallest window under the point", C.windowAt(wins, 25, 25), wins[1]);
    t.eq("none under a gap", C.windowAt(wins, 200, 200), null);
    const cl = [{ mapped: true, hidden: false, workspace: { id: 1 }, at: [1080, 10], size: [300, 200], title: "a" },
                { mapped: true, hidden: false, workspace: { id: 2 }, at: [0, 0], size: [5, 5], title: "b" }];
    t.eq("windows on this monitor, in its coordinates",
      C.windowsOn(cl, { x: 1080, y: 0 }, [1]), [{ x: 0, y: 10, w: 300, h: 200, title: "a" }]);

    // the window's shadow, from hyprland's getoption answers
    const opts = [{ option: "decoration:rounding", int: 5, set: true },
                  { option: "decoration:shadow:enabled", int: 1, set: true },
                  { option: "decoration:shadow:range", int: 70, set: true },
                  { option: "decoration:shadow:render_power", int: 2, set: true },
                  { option: "decoration:shadow:offset", vec2: [0, 10], set: true },
                  { option: "decoration:shadow:color", gradient: "7a000000 0deg", set: true }];
    const spec = C.shadowSpec(opts, 1, false, false);
    t.eq("the shadow as hyprland draws it", [spec.rounding, spec.range, spec.power, spec.ox, spec.oy],
      [5, 70, 2, 0, 10]);
    t.eq("its color, AARRGGBB", Math.round(spec.color.a * 255), 0x7a);
    t.eq("in the capture's pixels", C.shadowSpec(opts, 2, false, false).range, 140);
    t.eq("plain: rounded, no shadow", [C.shadowSpec(opts, 1, true, false).rounding,
      C.shadowSpec(opts, 1, true, false).range], [5, 0]);
    t.eq("fullscreen: neither", [C.shadowSpec(opts, 1, false, true).rounding,
      C.shadowSpec(opts, 1, false, true).range], [0, 0]);
    t.eq("shadows off in hyprland", C.shadowSpec(opts.concat([{ option: "decoration:shadow:enabled", int: 0 }]),
      1, false, false).range, 0);
    t.eq("a color that will not parse falls back", C.argbOf("rgba(oops)").a, 0x7a / 255);
    t.eq("the canvas fits the shadow pushed down", C.shadowLayout(spec, 100, 50),
      { wx: 70, wy: 60, sx: 0, sy: 0, cw: 240, ch: 190 });
    t.eq("no shadow, no margin", C.shadowLayout(C.shadowSpec(opts, 1, true, false), 100, 50),
      { wx: 0, wy: 0, sx: 0, sy: 0, cw: 100, ch: 50 });
    const sc = C.shadowCommand(spec, 100, 50);
    t.has("the tile is the rounded window and its shadow", sc, "-size 152x152 ");
    t.has("the edge strips stretch to the window less its corners", sc, "-scale 90x75!");
    t.has("the canvas", sc, "-size 240x190 xc:none");
    t.eq("plain is the rounding alone", C.shadowCommand(C.shadowSpec(opts, 1, true, false), 100, 50).indexOf("mpr:tile"), -1);
    const wc = C.windowShotCommand({ dir: "/s", file: "/s/a b.png", raw: "/r/raw.png", helper: "/h/toplevel.py",
      address: "0x1", geo: "1,1 100x50", spec: spec, w: 100, h: 50 });
    t.has("its own buffer first", wc, "grim -T \"$id\" '/r/raw.png'");
    t.has("the screen's rectangle if not", wc, "|| grim -g '1,1 100x50' '/r/raw.png'");
    t.has("the raw capture gone either way", wc, "; s=$?; rm -f '/r/raw.png'; exit $s");

    t.eq("hex", C.format(255, 128, 0, "hex"), "#ff8000");
    t.eq("rgb", C.format(255, 128, 0, "rgb"), "rgb(255, 128, 0)");
    t.eq("hsl", C.format(255, 128, 0, "hsl"), "hsl(30, 100%, 50%)");
    t.eq("hsv", C.format(255, 128, 0, "hsv"), "hsv(30, 100%, 100%)");
    t.eq("cmyk", C.format(255, 128, 0, "cmyk"), "cmyk(0%, 50%, 100%, 0%)");
    t.eq("oklch of white", C.format(255, 255, 255, "oklch"), "oklch(100% 0 0)");
    t.has("oklch of red", C.format(255, 0, 0, "oklch"), "oklch(62.8% 0.258 29.2)");
    t.eq("black in cmyk", C.format(0, 0, 0, "cmyk"), "cmyk(0%, 0%, 0%, 100%)");
    t.eq("the wheel walks the schemes", C.stepScheme("hex", 1), "rgb");
    t.eq("and wraps", C.stepScheme("hex", -1), "cmyk");
    t.eq("ink on white is black", C.inkOn(255, 255, 255), "#000000");
  }
};
