// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE THEME, WRITTEN OUT FOR WHAT IS NOT THIS SHELL. kitty and hyprland
// cannot read Zenon, so ThemeSync hands them a file each, made here.
//
// `c` is the shell's resolved palette — Zenon's slot names, as #rrggbb —
// or null for Zenon itself. Null writes a file that says nothing, so
// kitty's zenon.conf and base.lua's own colors stay the answer: Zenon is
// never generated, only ever left alone.

const HEAD = ["┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐", "┌─┘├┤ │││││││ │├┬┘├┴┐└─┐",
              "└─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘", "https://github.com/kbuckleys/"];

function rgb(h) { return String(h || "#000000").replace(/^#/, "").slice(-6).toLowerCase(); }

// ── kitty ──────────────────────────────────────────────────────────────
// Included after zenon.conf (kitty.conf's globinclude), so every line here
// overrides Zenon's and a missing or empty file changes nothing.
//
// The ANSI slots follow the convention the terminal apps were written for:
// color 0 is "black" and 7 "white" whatever the ground is. On a dark
// theme 0 is the ground and 7 the ink; on a light one 0 is a dark gray and
// 7 a light one — Catppuccin Latte's own kitty theme does exactly this.
function renderKitty(c, light) {
  const out = HEAD.map((l) => "# " + l);
  out.push("", "# Written by the shell (morpheus/ThemeSync.qml) whenever its theme",
           "# changes. Edits here are overwritten; zenon.conf is Zenon.");
  if (!c) {
    out.push("# Zenon is worn: nothing to override.", "");
    return out.join("\n");
  }
  const h = (k) => "#" + rgb(c[k]);
  const lines = [
    ["foreground", h("ink")], ["background", h("ground")],
    ["color0", light ? h("keyInk") : h("ground")], ["color1", h("red")],
    ["color2", h("green")], ["color3", h("yellow")], ["color4", h("blue")],
    ["color5", h("magenta")], ["color6", h("cyan")],
    ["color7", light ? h("dim") : h("ink")],
    ["color8", light ? h("soft") : h("muted")], ["color9", h("pink")],
    ["color10", h("green")], ["color11", h("sand")], ["color12", h("blue")],
    ["color13", h("magenta")], ["color14", h("cyan")],
    ["color15", light ? h("surface") : h("ink")],
    ["selection_foreground", h("onAccent")], ["selection_background", h("magenta")],
    ["url_color", h("blue")],
    ["active_border_color", h("muted")], ["inactive_border_color", h("surface")],
    ["bell_border_color", h("red")],
    ["active_tab_foreground", h("ink")], ["active_tab_background", h("ground")],
    ["inactive_tab_foreground", h("muted")], ["inactive_tab_background", h("surface")],
    ["tab_bar_background", h("surface")],
    ["mark1_foreground", h("onAccent")], ["mark1_background", h("green")],
    ["mark2_foreground", h("onAccent")], ["mark2_background", h("yellow")],
    ["mark3_foreground", h("onAccent")], ["mark3_background", h("cyan")],
  ];
  const w = Math.max.apply(null, lines.map((l) => l[0].length));
  out.push("# " + (c.name || "theme"), "");
  for (const l of lines) out.push(l[0] + " ".repeat(w - l[0].length + 2) + l[1]);
  out.push("");
  return out.join("\n");
}

// ── hyprland ───────────────────────────────────────────────────────────
// lua/theme.lua, read by base.lua (pcall, like defaults.lua): the window
// borders and the groupbar. The border is the shell's own hairline — the
// slate Zenon calls `border` — at 30% resting and 80% on the focused
// window, the two alphas base.lua has always used. Hyprland takes
// #RRGGBBAA. Shadows are not here: a shadow is black in every theme.
function hypr(h, a) {
  return "#" + rgb(h) + (a === undefined ? "" : Math.round(a * 255).toString(16).padStart(2, "0"));
}

function renderHyprTheme(c) {
  const out = HEAD.map((l) => "-- " + l);
  out.push("", "-- THEME", "-- Written by the shell (morpheus/ThemeSync.qml) whenever its theme",
           "-- changes; base.lua lays it over its own colors. Empty is Zenon.", "");
  if (!c) {
    out.push("return {}", "");
    return out.join("\n");
  }
  const t = [
    ["inactive_border", hypr(c.border, 0.3)],
    ["active_border", hypr(c.border, 0.8)],
    ["group_border_locked", hypr(c.red)],
    ["group_border", hypr(c.pink)],
    ["groupbar_text", hypr(c.onAccent)],
    ["groupbar_text_inactive", hypr(c.ink)],
    ["groupbar_locked_active", hypr(c.red)],
    ["groupbar_active", hypr(c.pink)],
    ["groupbar_inactive", hypr(c.surface)],
  ];
  const w = Math.max.apply(null, t.map((l) => l[0].length));
  out.push("return {");
  for (const l of t) out.push("\t" + l[0] + " ".repeat(w - l[0].length) + " = \"" + l[1] + "\",");
  out.push("}", "");
  return out.join("\n");
}

// ── hyprland's font ────────────────────────────────────────────────────
// lua/font.lua, read by base.lua like theme.lua: oracle's Font and its
// weight, for the two places hyprland sets text — misc (its own notices)
// and the groupbar. Unlike the theme, always written: base.lua's literals
// are only what a machine that has never run the shell gets.
//
// Hyprland hands these to Pango, which reads a trailing weight word off a
// family ("SF Pro Text SemiBold"); misc has no weight of its own, so its
// weight rides in the name. The groupbar has two: the resting tabs wear
// the shell's weight, the focused one two steps heavier so it still reads
// as the one in front. `face` is Zenon's — a Nerd Font's Propo cut. The
// groupbar's size is its own 14 scaled with oracle's Font size (Zenon.px).
const PANGO_WEIGHT = { 100: "thin", 200: "ultralight", 300: "light", 400: "normal",
                       500: "medium", 600: "semibold", 700: "bold", 800: "ultrabold",
                       900: "heavy" };
const WEIGHT_WORD = { 300: "Light", 500: "Medium", 600: "SemiBold", 700: "Bold" };

function luaStr(s) { return "\"" + String(s).replace(/[\\"]/g, "\\$&").replace(/\n/g, " ") + "\""; }

function renderHyprFont(face, weight, size) {
  const w = Math.max(100, Math.min(900, Math.round((Number(weight) || 500) / 100) * 100));
  const out = HEAD.map((l) => "-- " + l);
  out.push("", "-- FONT", "-- Written by the shell (morpheus/ThemeSync.qml) whenever oracle's Font",
           "-- changes; base.lua lays it over its own. Edits here are overwritten.", "");
  if (!face) {
    out.push("return {}", "");
    return out.join("\n");
  }
  const t = [
    ["family", (face + (WEIGHT_WORD[w] ? " " + WEIGHT_WORD[w] : ""))],
    ["groupbar_family", face],
    ["groupbar_weight", PANGO_WEIGHT[w]],
    ["groupbar_weight_active", PANGO_WEIGHT[Math.min(900, w + 200)]],
    ["groupbar_size", Math.max(6, Math.round(Number(size) || 14))],
  ];
  const n = Math.max.apply(null, t.map((l) => l[0].length));
  out.push("return {");
  for (const l of t) out.push("\t" + l[0] + " ".repeat(n - l[0].length) + " = " + (typeof l[1] === "number" ? l[1] : luaStr(l[1])) + ",");
  out.push("}", "");
  return out.join("\n");
}

// ── everything else's font ─────────────────────────────────────────────
// GTK, gsettings (and so the portal, and every app asking it) and
// fontconfig's generic families take the shell's two faces too; written by
// scripts/fontsync.sh, which ThemeSync runs with these. Sizes are oracle's
// px; GTK and kitty read points, three quarters of one.
function pt(px) { return Math.round((Number(px) || 16) * 0.75 * 100) / 100; }

// A Pango description, "SF Pro Text Medium 12": a trailing weight word and
// a size, which Pango reads off the family. Regular adds no word.
function pangoFont(face, weight, px) {
  const w = Math.max(100, Math.min(900, Math.round((Number(weight) || 500) / 100) * 100));
  return face + (WEIGHT_WORD[w] ? " " + WEIGHT_WORD[w] : "") + " " + pt(px);
}

function xmlEsc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// conf.d/50-oracle-fonts.conf: sans-serif (and system-ui) is the shell's
// face, monospace the Monospace font — what an app gets that asks for a
// kind of face rather than a name. Prepended, so the rest of fontconfig's
// list still stands behind for glyphs these lack.
function renderFontconfig(face, mono) {
  const alias = (fam, want) => [
    "  <alias binding=\"strong\">",
    "    <family>" + fam + "</family>",
    "    <prefer><family>" + xmlEsc(want) + "</family></prefer>",
    "  </alias>"];
  return ["<?xml version=\"1.0\"?>",
    "<!DOCTYPE fontconfig SYSTEM \"urn:fontconfig:fonts.dtd\">",
    "<!-- Written by quickshell (morpheus/ThemeSync.qml) from oracle's Font and",
    "     Monospace font. Edits here are overwritten. -->",
    "<fontconfig>"]
    .concat(alias("sans-serif", face), alias("system-ui", face), alias("monospace", mono))
    .concat(["</fontconfig>", ""]).join("\n");
}
