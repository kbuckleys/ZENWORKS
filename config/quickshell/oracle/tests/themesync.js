// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE THEME FOR KITTY, HYPRLAND, GTK AND QT: what ThemeSync writes. Zenon must write
// nothing that overrides anything, and a theme must reach every line.

"use strict";

const LATTE = {
  name: "Catppuccin Latte", ground: "#eff1f5", surface: "#ccd0da", ink: "#4c4f69",
  muted: "#7c7f93", soft: "#6c6f85", keyInk: "#5c5f77", dim: "#acb0be",
  red: "#d20f39", green: "#40a02b", yellow: "#fe640b", blue: "#1e66f5",
  magenta: "#8839ef", cyan: "#179299", pink: "#ea76cb", sand: "#df8e1d",
  border: "#9ca0b0", onAccent: "#eff1f5", card: "#e6e9ef"
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
    t.match("light: color 0 is a dark gray, not the ground", lk, /^color0\s+#5c5f77$/m);
    t.match("light: color 7 is a light gray, not the ink", lk, /^color7\s+#acb0be$/m);
    const dk = S.renderKitty(LATTE, false);
    t.match("dark: color 0 is the ground", dk, /^color0\s+#eff1f5$/m);
    t.ok("all sixteen colors are written", [...Array(16).keys()]
      .every((i) => new RegExp("^color" + i + "\\s+#[0-9a-f]{6}$", "m").test(lk)));
    t.ok("no slot came out undefined", !/undefined|NaN/.test(lk));

    const comment = (txt) => txt.replace(/\/\*[\s\S]*?\*\//g, "").trim();
    t.ok("zenon overrides nothing in GTK 4", comment(S.renderGtk4(null, false)) === "");
    t.ok("zenon overrides nothing in GTK 3", comment(S.renderGtk3(null, false)) === "");
    const g4 = S.renderGtk4(LATTE, true);
    t.match("gtk4: the window is the ground", g4, /^@define-color window_bg_color #eff1f5;$/m);
    t.match("gtk4: libadwaita's variable too", g4, /^  --window-bg-color: #eff1f5;$/m);
    t.match("gtk4: the accent is cyan", g4, /^  --accent-bg-color: #179299;$/m);
    t.match("gtk4: type on the accent is onAccent", g4, /^  --accent-fg-color: #eff1f5;$/m);
    t.match("gtk4: bars are the card", g4, /^  --headerbar-bg-color: #e6e9ef;$/m);
    t.match("gtk4: popovers are the card", g4, /^@define-color popover_bg_color #e6e9ef;$/m);
    t.match("gtk4: errors are red", g4, /^  --error-bg-color: #d20f39;$/m);
    t.match("gtk4: success is green", g4, /^  --success-bg-color: #40a02b;$/m);
    t.match("gtk4: warnings are yellow", g4, /^  --warning-bg-color: #fe640b;$/m);
    t.match("gtk4: sidebars keep the hairline", g4, /^  --sidebar-border-color: #9ca0b0;$/m);
    t.ok("gtk4: --accent-color is left to libadwaita", !/--accent-color:/.test(g4));
    t.ok("gtk4: every name has its variable", (g4.match(/^@define-color /mg) || []).length ===
      (g4.match(/^  --[a-z-]+: /mg) || []).length);
    t.ok("gtk4: no slot came out undefined", !/undefined|NaN/.test(g4));
    t.ok("gtk4: braces balance", (g4.match(/\{/g) || []).length === (g4.match(/\}/g) || []).length);
    t.match("gtk4: dark shades are deeper", S.renderGtk4(LATTE, false),
      /^  --headerbar-shade-color: rgba\(0, 0, 0, 0\.36\);$/m);
    const g3 = S.renderGtk3(LATTE, true);
    t.match("gtk3: libadwaita names for adw-gtk3", g3, /^@define-color view_bg_color #eff1f5;$/m);
    t.match("gtk3: the accent as text too", g3, /^@define-color accent_color #179299;$/m);
    t.match("gtk3: the old theme_ names", g3, /^@define-color theme_selected_bg_color #179299;$/m);
    t.ok("gtk3: no variables (GTK 3 has none)", !/--[a-z]/.test(comment(g3)));
    t.ok("gtk3: no slot came out undefined", !/undefined|NaN/.test(g3));
    t.ok("gtk3: every line is a definition", comment(g3).split("\n")
      .every((l) => l === "" || /^@define-color [a-z_]+ (#[0-9a-f]{6}|rgba\([0-9., ]+\));$/.test(l)));
    t.ok("gtk4: every definition is well formed", g4.split("\n").filter((l) => l.startsWith("@define"))
      .every((l) => /^@define-color [a-z_]+ (#[0-9a-f]{6}|rgba\([0-9., ]+\));$/.test(l)));
    t.ok("light asks GTK for light", S.colorScheme(true) === "prefer-light");
    t.ok("dark asks GTK for dark", S.colorScheme(false) === "prefer-dark");

    const qc = S.renderQtColors(LATTE, true);
    const roles = (txt, group) => (txt.match(new RegExp("^" + group + "_colors=(.*)$", "m")) || [, ""])[1].split(", ");
    t.ok("qt: three groups", ["active", "inactive", "disabled"].every((g) => roles(qc, g).length === 22));
    t.ok("qt: every role is #aarrggbb", ["active", "inactive", "disabled"]
      .every((g) => roles(qc, g).every((r) => /^#ff[0-9a-f]{6}$/.test(r))));
    t.match("qt: the scheme is a qt6ct ColorScheme", qc, /^\[ColorScheme\]$/m);
    const qa = roles(qc, "active");
    t.eq("qt: window text is the ink", qa[0], "#ff4c4f69");
    t.eq("qt: windows are the ground", qa[10], "#ffeff1f5");
    t.eq("qt: fields are the card", qa[9], "#ffe6e9ef");
    t.eq("qt: the selection is the accent", qa[12], "#ff179299");
    t.eq("qt: type on it is onAccent", qa[13], "#ffeff1f5");
    t.eq("qt: placeholders are muted", qa[20], "#ff7c7f93");
    t.eq("qt: Accent is the accent", qa[21], "#ff179299");
    t.eq("qt: disabled type is muted", roles(qc, "disabled")[6], "#ff7c7f93");
    t.ok("qt: inactive is active", roles(qc, "inactive").join() === qa.join());
    t.ok("qt: dark differs from light", S.renderQtColors(LATTE, false) !== qc);
    t.ok("qt: no slot came out undefined", !/undefined|NaN/.test(qc));
    t.ok("qt: an alpha-carrying border still gives a color", /^#ff[0-9a-f]{6}$/.test(roles(S.renderQtColors(
      Object.assign({}, LATTE, { border: "#4d45505c" }), false), "active")[5]));
    const q6 = S.renderQt6ct("/h/.config/qt6ct/colors/zenworks.conf");
    t.match("qt6ct: points at the scheme", q6, /^color_scheme_path=\/h\/.config\/qt6ct\/colors\/zenworks\.conf$/m);
    t.match("qt6ct: the palette is used", q6, /^custom_palette=true$/m);
    t.ok("qt6ct: fonts and icons are left to Qt", !/^\[Fonts\]|^icon_theme=/m.test(q6));

    const zh = S.renderHyprTheme(null);
    t.match("zenon hands hyprland an empty table", zh, /^return \{\}$/m);
    const lh = S.renderHyprTheme(LATTE);
    t.match("the resting border is the hairline at 30%", lh, /inactive_border\s+= "#9ca0b04d"/);
    t.match("the focused border at 65%", lh, /\bactive_border\s+= "#9ca0b0a6"/);
    t.match("the groupbar's text is the ink on an accent", lh, /groupbar_text\s+= "#eff1f5"/);
    t.ok("no slot came out undefined", !/undefined|NaN/.test(lh));
    t.ok("the lua parses", (() => {
      try {
        require("child_process").execFileSync("luac", ["-p", "-"], { input: lh });
        return true;
      } catch (e) { return e.code === "ENOENT"; }
    })());
    // 8-digit #aarrggbb (Zenon's border slot) still gives the color
    t.match("an alpha-carrying hex is read for its color", S.renderHyprTheme(
      Object.assign({}, LATTE, { border: "#4d45505c" })), /inactive_border\s+= "#45505c4d"/);

    const f = S.renderHyprFont("SF Pro Text", "600", 14);
    t.match("the groupbar's size is a number", f, /groupbar_size\s+= 14,/);
    t.eq("pango: weight word and points", S.pangoFont("SF Pro Text", 500, 16), "SF Pro Text Medium 12");
    t.eq("pango: regular has no word", S.pangoFont("SF Mono", 400, 15), "SF Mono 11.25");
    const fc = S.renderFontconfig("A&B", "SF Mono");
    t.match("fontconfig: sans-serif prefers the face, escaped", fc, /sans-serif<\/family>\n\s*<prefer><family>A&amp;B</);
    t.match("fontconfig: monospace prefers the mono face", fc, /monospace<\/family>\n\s*<prefer><family>SF Mono</);
    t.match("misc's family carries the weight in its name", f, /^\tfamily\s+= "SF Pro Text SemiBold",$/m);
    t.match("the groupbar's family is the face alone", f, /groupbar_family\s+= "SF Pro Text",/);
    t.match("the resting tabs wear the shell's weight", f, /groupbar_weight\s+= "semibold",/);
    t.match("the focused tab two steps heavier", f, /groupbar_weight_active\s+= "ultrabold",/);
    t.match("regular adds no word", S.renderHyprFont("Inter", "400"), /^\tfamily\s+= "Inter",$/m);
    t.match("heaviest stops at heavy", S.renderHyprFont("Inter", "700"), /groupbar_weight_active\s+= "heavy",/);
    t.match("a Nerd Font's Propo cut", S.renderHyprFont("JetBrainsMono Nerd Font Propo", "500"),
      /^\tfamily\s+= "JetBrainsMono Nerd Font Propo Medium",$/m);
    t.match("a quote in a name is escaped", S.renderHyprFont("A\"B", "500"), /"A\\"B Medium"/);
    t.match("no face is an empty table", S.renderHyprFont("", "500"), /^return \{\}$/m);
    const kc = S.renderKittyConf("/usr/share/zenworks/kitty");
    t.eq("kitty: font, shipped, zenon, theme, then yours", kc.split("\n").filter((l) => /^(glob)?include /.test(l)),
      ["globinclude font.conf", "include /usr/share/zenworks/kitty/kitty.conf", "include /usr/share/zenworks/kitty/zenon.conf",
       "globinclude theme.conf", "globinclude custom.conf"]);
    t.match("corner: the number, in a table", S.renderCornerLua(12), /^return \{ rounding = 12 \}$/m);
    t.match("corner: 0 is square", S.renderCornerLua(0), /rounding = 0 \}/);
    t.match("corner: no number is 0, a fraction rounded", S.renderCornerLua("x") + S.renderCornerLua(4.6), /rounding = 0 \}[\s\S]*rounding = 5 \}/);
    const fk = { face: "SF Pro Text", mono: "SF Mono", large: 10, small: 4,
                 px: { text: 16, small: 13, h3: 17, h2: 20, h1: 25 } };
    const hk = S.renderHyprtoolkit(LATTE, true, fk);
    t.match("toolkit: the background is the ground", hk, /^background\s+= 0xffeff1f5$/m);
    t.match("toolkit: buttons are the card", hk, /^base\s+= 0xffe6e9ef$/m);
    t.match("toolkit: the accent is cyan", hk, /^accent\s+= 0xff179299$/m);
    t.match("toolkit: light: bright text is the ground", hk, /^bright_text\s+= 0xffeff1f5$/m);
    t.match("toolkit: dark: bright text is the ink", S.renderHyprtoolkit(LATTE, false, fk),
      /^bright_text\s+= 0xff4c4f69$/m);
    t.match("toolkit: sizes are whole points", hk, /^font_size\s+= 12$/m);
    t.match("toolkit: h1 at points too", hk, /^h1_size\s+= 19$/m);
    t.match("toolkit: the dialog corner", hk, /^rounding_large\s+= 10$/m);
    t.match("toolkit: the face alone", hk, /^font_family\s+= SF Pro Text$/m);
    t.ok("toolkit: every line is a comment or key = value", hk.split("\n")
      .every((l) => l === "" || l.startsWith("#") || /^[a-z0-9_]+ += \S/.test(l)));
    t.ok("toolkit: no slot came out undefined", !/undefined|NaN/.test(hk));
    t.ok("the font lua parses", (() => {
      try {
        require("child_process").execFileSync("luac", ["-p", "-"], { input: f });
        return true;
      } catch (e) { return e.code === "ENOENT"; }
    })());
  }
};
