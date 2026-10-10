// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE THEME FOR KITTY AND HYPRLAND: what ThemeSync writes. Zenon must write
// nothing that overrides anything, and a theme must reach every line.

"use strict";

const LATTE = {
  name: "Catppuccin Latte", ground: "#eff1f5", surface: "#ccd0da", ink: "#4c4f69",
  muted: "#7c7f93", soft: "#6c6f85", keyInk: "#5c5f77", dim: "#acb0be",
  red: "#d20f39", green: "#40a02b", yellow: "#fe640b", blue: "#1e66f5",
  magenta: "#8839ef", cyan: "#179299", pink: "#ea76cb", sand: "#df8e1d",
  border: "#9ca0b0", onAccent: "#eff1f5"
};

module.exports = {
  module: "morpheus/themesync.js",
  cases: (S, t) => {
    const zk = S.renderKitty(null, false);
    t.ok("zenon overrides nothing in kitty",
      zk.split("\n").every((l) => l === "" || l.startsWith("#")));
    const lk = S.renderKitty(LATTE, true);
    t.match("the ground is the background", lk, /^background\s+#eff1f5$/m);
    t.match("the ink is the foreground", lk, /^foreground\s+#4c4f69$/m);
    t.match("light: colour 0 is a dark grey, not the ground", lk, /^color0\s+#5c5f77$/m);
    t.match("light: colour 7 is a light grey, not the ink", lk, /^color7\s+#acb0be$/m);
    const dk = S.renderKitty(LATTE, false);
    t.match("dark: colour 0 is the ground", dk, /^color0\s+#eff1f5$/m);
    t.ok("all sixteen colours are written", [...Array(16).keys()]
      .every((i) => new RegExp("^color" + i + "\\s+#[0-9a-f]{6}$", "m").test(lk)));
    t.ok("no slot came out undefined", !/undefined|NaN/.test(lk));

    const zh = S.renderHyprTheme(null);
    t.match("zenon hands hyprland an empty table", zh, /^return \{\}$/m);
    const lh = S.renderHyprTheme(LATTE);
    t.match("the resting border is the hairline at 30%", lh, /inactive_border\s+= "#9ca0b04d"/);
    t.match("the focused border at 80%", lh, /\bactive_border\s+= "#9ca0b0cc"/);
    t.match("the groupbar's text is the ink on an accent", lh, /groupbar_text\s+= "#eff1f5"/);
    t.ok("no slot came out undefined", !/undefined|NaN/.test(lh));
    t.ok("the lua parses", (() => {
      try {
        require("child_process").execFileSync("luac", ["-p", "-"], { input: lh });
        return true;
      } catch (e) { return e.code === "ENOENT"; }
    })());
    // 8-digit #aarrggbb (Zenon's border slot) still gives the colour
    t.match("an alpha-carrying hex is read for its colour", S.renderHyprTheme(
      Object.assign({}, LATTE, { border: "#4d45505c" })), /inactive_border\s+= "#45505c4d"/);
  }
};
