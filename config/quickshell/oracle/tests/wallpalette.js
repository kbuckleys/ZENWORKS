// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// FOLLOW BACKGROUND'S PALETTE. Whatever the background, the theme it makes
// must read: the sweep below throws hundreds of random pictures at it in
// both modes and every vividness, and holds each slot to its contrast.

"use strict";

const HIST = [
  "      4210: (23,41,60) #17293C srgb(23,41,60)",
  "       812: (200,120,40) #C87828 srgb(200,120,40)",
  "        33: (250,250,250) #FAFAFA srgb(250,250,250)",
  "garbage line",
].join("\n");

function rnd(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

module.exports = {
  module: "morpheus/wallpalette.js",
  cases: (W, t) => {
    const h = W.parseHistogram(HIST);
    t.eq("three colours read, the junk line skipped", h.length, 3);
    t.eq("count and colour", JSON.stringify(h[0]), JSON.stringify({ hex: "#17293c", n: 4210 }));
    t.eq("nothing to go on is null", W.palette([], {}), null);

    // an orange picture: the shell's accent turns orange
    const orange = W.palette([{ hex: "#1a1a1a", n: 50 }, { hex: "#e07020", n: 40 }], { mode: "dark" });
    const hc = W.rgbToOklch(W.hexToRgb(orange.colors.cyan)).h;
    t.ok("the accent takes the wallpaper's hue", hc > 30 && hc < 80);
    t.eq("asked for dark, dark", orange.mode, "dark");

    // a grey picture: a neutral theme
    const grey = W.palette([{ hex: "#808080", n: 10 }, { hex: "#303030", n: 10 }], { mode: "dark" });
    t.ok("grey gives an all but neutral ground",
      W.rgbToOklch(W.hexToRgb(grey.colors.ground)).C < 0.01);

    // auto: a bright picture is a light theme, a dark one dark
    t.eq("auto on a bright picture", W.palette([{ hex: "#f0eee8", n: 9 }, { hex: "#88aacc", n: 1 }], { mode: "auto" }).mode, "light");
    t.eq("auto on a dark picture", W.palette([{ hex: "#101418", n: 9 }, { hex: "#4060a0", n: 1 }], { mode: "auto" }).mode, "dark");

    // the sweep
    const r = rnd(7);
    const hexOf = () => "#" + [0, 0, 0].map(() => Math.floor(r() * 256).toString(16).padStart(2, "0")).join("");
    const need = { ink: 7, keyInk: 4.5, soft: 3.5, muted: 2.6, red: 3, yellow: 3, sand: 3,
                   green: 3, cyan: 3, blue: 3, magenta: 3, pink: 3 };
    let fails = [], shapes = 0;
    for (let i = 0; i < 300; ++i) {
      const cols = [...Array(1 + Math.floor(r() * 10))].map(() => ({ hex: hexOf(), n: 1 + Math.floor(r() * 1000) }));
      for (const mode of ["dark", "light"]) for (const vivid of [0, 0.5, 1]) {
        const p = W.palette(cols, { mode: mode, vivid: vivid });
        for (const k in need) {
          const cr = W.contrast(p.colors[k], p.colors.ground);
          if (cr < need[k] - 0.01) fails.push(mode + " v" + vivid + " " + k + " " + p.colors[k] + " on " + p.colors.ground + " " + cr.toFixed(2));
        }
        for (const k in p.colors) if (!/^#([0-9a-f]{6}|[0-9a-f]{8})$/.test(p.colors[k])) shapes++;
      }
    }
    t.eq("every slot reads on its ground, 1800 palettes", fails.slice(0, 3).join(" | "), "");
    t.eq("every colour is a hex Zenon takes", shapes, 0);

    // a rose background: red must not become the accent
    const rose = W.palette([{ hex: "#1c080e", n: 60 }, { hex: "#e0607f", n: 30 }], { mode: "dark" });
    const hue = (x) => W.rgbToOklch(W.hexToRgb(x)).h;
    const apart = Math.abs(((hue(rose.colors.red) - hue(rose.colors.cyan) + 540) % 360) - 180);
    t.ok("red stays clear of a reddish accent (" + apart.toFixed(0) + " degrees)", apart >= 30);

  }
};
