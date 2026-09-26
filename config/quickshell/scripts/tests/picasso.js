// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PICASSO'S STORE: colours as assignments, the look a monitor wears, the
// geometry of a turned or spanned picture, the slideshow's next pick, and the
// state file across all three of its versions.

"use strict";

module.exports = {
  module: "picasso/picasso.js",
  cases: (A, t) => {
    t.eq("a colour is not a path", A.isColor("color:#112233"), true);
    t.eq("a path is not a colour", A.isColor("/home/a/color:x.png"), false);
    t.eq("short hex widens", A.normHex("ABC"), "#aabbcc");
    t.eq("junk is refused", A.normHex("#12345"), "");
    t.eq("colour round trip", A.colorOf(A.colorPath("#FF8800")), "#ff8800");

    for (const hex of ["#000000", "#ffffff", "#9bbfbf", "#e78284", "#1b2a44"]) {
      const c = A.hexToHsv(hex);
      t.eq("hsv round trip " + hex, A.hsvToHex(c.h, c.s, c.v), hex);
    }

    t.eq("an empty look is the defaults", A.lookOf({}).align, "c");
    t.eq("a bad rotation falls back", A.lookOf({ rotate: 45 }).rotate, 0);
    t.eq("only changes are kept", A.lookDiff({ rotate: 90, dim: 0 }), { rotate: 90 });
    t.eq("a plain look needs no effect", A.lookNeedsFx({ dim: 0.4, rotate: 90 }), false);
    t.eq("nor does a vignette — it is drawn on top", A.lookNeedsFx({ vignette: 0.6 }), false);
    t.eq("a vignette is kept", A.lookDiff({ vignette: 0.5 }), { vignette: 0.5 });
    t.eq("a tint needs one", A.lookNeedsFx({ tint: "#ff0000" }), true);
    t.eq("top left", A.alignFlags("tl"), [1, 32]);
    t.eq("bottom right", A.alignFlags("br"), [2, 64]);
    t.eq("centre", A.alignFlags("nonsense"), [4, 128]);

    t.eq("unturned keeps its place", A.alignInFrame("t", 0, false), "t");
    t.eq("mirrored left is the frame's right", A.alignInFrame("l", 0, true), "r");
    t.eq("turned 90, the screen's bottom is the frame's right", A.alignInFrame("b", 90, false), "r");
    t.eq("turned 180, top left is bottom right", A.alignInFrame("tl", 180, false), "br");
    t.eq("turned 270, the screen's top is the frame's right", A.alignInFrame("t", 270, false), "r");

    const mon = { x: 0, y: 0, w: 2560, h: 1440 };
    t.eq("unturned is the target", A.frameRect(mon, 0), { x: 0, y: 0, w: 2560, h: 1440 });
    t.eq("a quarter turn swaps and centres", A.frameRect(mon, 90),
      { x: 560, y: -560, w: 1440, h: 2560 });
    t.eq("the desk", A.boundsOf([{ x: 0, y: 0, w: 1080, h: 1920 }, { x: 1080, y: 0, w: 2560, h: 1440 }]),
      { x: 0, y: 0, w: 3640, h: 1920 });

    const pool = ["a", "b", "c"];
    t.eq("in order", A.nextSlide(pool, "b", false), "c");
    t.eq("wraps", A.nextSlide(pool, "c", false), "a");
    t.eq("from nothing", A.nextSlide(pool, "zzz", false), "a");
    t.eq("shuffle skips the current", A.nextSlide(pool, "a", true, () => 0), "b");
    t.eq("shuffle reaches the end", A.nextSlide(pool, "a", true, () => 0.99), "c");

    const v1 = A.parseState('{"*":"/w/a.png"}');
    t.eq("v1 loads", v1.assignment, { "*": "/w/a.png" });
    t.eq("v1 has no looks", v1.looks, {});
    const v2 = A.parseState('{"v":2,"assignment":{"DP-1":"/x"},"fits":{"DP-1":"pad"}}');
    t.eq("v2 keeps its fits", v2.fits, { "DP-1": "pad" });
    t.eq("v2 has no span", v2.span, null);
    const st = { assignment: { "*": "color:#000000" }, fits: {}, looks: { "HDMI-A-1": { rotate: 90 } },
                 span: { path: "/p", screens: ["A", "B"] }, colors: ["#123456"],
                 slideshow: { minutes: 15, shuffle: true, query: "", screens: [], span: false } };
    t.eq("v3 round trip", A.parseState(A.serializeState(st)), st);
    t.eq("bad saved colours dropped", A.parseState('{"v":3,"colors":["#12","#abcdef"]}').colors, ["#abcdef"]);
  }
};
