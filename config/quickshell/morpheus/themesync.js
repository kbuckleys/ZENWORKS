// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

.pragma library
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file evaluated all of it again (see morpheus/icons.js).

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
    ["bell_border_color", h("red")], ["visual_bell_color", h("red")],
    // kitty.conf writes these two as Zenon's literals (2026-10-20, user:
    // nothing may keep Zenon's colors under another theme)
    ["cursor_trail_color", h("magenta")],
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
// slate Zenon calls `border` — at 30% resting and 65% on the focused
// window (it was 80%; user, 2026-10-19: "a little more faint"); floating, zoomed, pinned,
// grouped and no-group windows take the theme's hues (below). Written for
// Zenon too, so base.lua's own literals are only a first boot's. Hyprland
// takes #RRGGBBAA. Shadows are not here: a shadow is black in every theme.
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
  // EVERY STATE A WINDOW CAN BE IN, in the theme's own colors (user,
  // 2026-10-19). A tiled window keeps the hairline; the others take a hue,
  // full-ish on the focused window and faint on the rest, so which window
  // has the keys still reads at a glance whatever it is:
  //   floating   the accent (cyan)      zoomed     blue (maximized)
  //   pinned     sand (on every desk)   grouped    pink, red once locked
  //   no-group   magenta (a window that will not join a group)
  // The per-state pairs are "<focused> <unfocused>": base.lua hands them to
  // window rules (border_color), which take exactly that.
  const pair = (h, on, off) => hypr(h, on) + " " + hypr(h, off);
  const t = [
    ["inactive_border", hypr(c.border, 0.3)],
    ["active_border", hypr(c.border, 0.65)],
    ["float_border", hypr(c.cyan, 0.45) + " " + hypr(c.border, 0.3)],
    ["zoom_border", pair(c.blue, 0.55, 0.3)],
    ["pin_border", pair(c.sand, 0.55, 0.3)],
    ["nogroup_border_active", hypr(c.magenta, 0.55)],
    ["nogroup_border", hypr(c.magenta, 0.3)],
    ["group_border_locked", hypr(c.red)],
    ["group_border_locked_inactive", hypr(c.red, 0.45)],
    ["group_border", hypr(c.pink)],
    ["group_border_inactive", hypr(c.pink, 0.45)],
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

// ── kitty's own config ─────────────────────────────────────────────────
// ~/.config/zenworks/kitty/kitty.conf, where KITTY_CONFIG_DIRECTORY points
// (hypr/hyprland.lua): the shipped kitty.conf and zenon.conf, by their
// paths beside the shell, around the two files the shell writes beside
// this one — and custom.conf last, which is yours and never written.
function renderKittyConf(shipped) {
  const out = HEAD.map((l) => "# " + l);
  out.push("", "# KITTY", "# Written by the shell (morpheus/ThemeSync.qml). Edits here are",
           "# overwritten: your own lines go in custom.conf, read last.", "",
           "globinclude font.conf",
           "include " + shipped + "/kitty.conf",
           "include " + shipped + "/zenon.conf",
           "globinclude theme.conf",
           "globinclude custom.conf", "");
  return out.join("\n");
}

// ── hyprland's window corner ───────────────────────────────────────────
// lua/corner.lua, read by base.lua like font.lua: Oracle's Corner rounding
// for hyprland's windows. A file of its own since 2026-10-25 — it used to be
// base.lua's own `rounding = N` line rewritten in place, but base.lua ships
// with the shell and may be read-only in /usr/share/zenworks.
function renderCornerLua(n) {
  const v = Math.max(0, Math.round(Number(n) || 0));
  const out = HEAD.map((l) => "-- " + l);
  out.push("", "-- CORNER", "-- Written by the shell (morpheus/ThemeSync.qml) from oracle's Corner",
           "-- rounding; base.lua reads it. Edits here are overwritten.", "",
           "return { rounding = " + v + " }", "");
  return out.join("\n");
}

// ── hyprtoolkit ────────────────────────────────────────────────────────
// hypr/hyprtoolkit.conf, read by every hyprtoolkit app — hyprshutdown's
// "Shutting down" screen, hyprpolkitagent — as it starts, and again on any
// write (it watches the file). Written for Zenon too: hyprtoolkit's own is a
// mint-on-gray of its own, not Zenon.
//
// The ladder is the GTK one: background the ground (hyprshutdown lays it
// over the screen, translucent), base the card (buttons), alternate_base the
// surface (a resting button's border). bright_text is the type on an accent
// button too dark for the background to read on it, so it is always the
// light end: the ink on a dark theme, the ground on a light one. Hyprlang
// takes 0xAARRGGBB; the sizes are points, each an oracle px scaled with Font
// size (`f.px`), and the font is a family alone — no weight word.
function renderHyprtoolkit(c, light, f) {
  const k = (s) => "0xff" + rgb(c[s]);
  const n = (v, d) => Math.max(1, Math.round(Number(v) || d));
  const out = HEAD.map((l) => "# " + l);
  out.push("", "# Written by the shell (morpheus/ThemeSync.qml) whenever its theme or",
           "# oracle's Font changes. Edits here are overwritten.",
           "# " + (c.name || "theme"), "");
  const t = [
    ["background", k("ground")], ["base", k("card")], ["alternate_base", k("surface")],
    ["text", k("ink")], ["bright_text", light ? k("ground") : k("ink")],
    ["link_text", k("blue")], ["accent", k("cyan")], ["accent_secondary", k("magenta")],
    ["rounding_large", Math.max(0, Math.round(Number(f.large) || 0))],
    ["rounding_small", Math.max(0, Math.round(Number(f.small) || 0))],
    ["h1_size", n(pt(f.px.h1), 19)], ["h2_size", n(pt(f.px.h2), 15)],
    ["h3_size", n(pt(f.px.h3), 13)], ["font_size", n(pt(f.px.text), 11)],
    ["small_font_size", n(pt(f.px.small), 10)],
  ];
  if (f.face) t.push(["font_family", String(f.face).replace(/\n/g, " ")]);
  if (f.mono) t.push(["font_family_monospace", String(f.mono).replace(/\n/g, " ")]);
  const w = Math.max.apply(null, t.map((l) => l[0].length));
  for (const l of t) out.push(l[0] + " ".repeat(w - l[0].length) + " = " + l[1]);
  out.push("");
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

// ── GTK ────────────────────────────────────────────────────────────────
// gtk-4.0/colors.css and gtk-3.0/colors.css, which each directory's
// gtk.css @imports. A user gtk.css is read over the theme, so these win.
//
// libadwaita (1.6 on) paints with CSS variables — `--window-bg-color` —
// that its own :root sets from its named colors, resolved inside its own
// stylesheet: a user @define-color alone no longer reaches them. So GTK 4
// gets both, the variables for libadwaita and the names for anything that
// still looks them up. GTK 3 has no variables; adw-gtk3 (the libadwaita
// look ported to GTK 3) reads the same names, and the old theme_* names
// are for the rest. `--accent-color` is left to libadwaita: it derives it
// from the accent's background, darker on a light theme so it still reads
// as text.
//
// The ladder is the theme's own: ground (views, the window) under card
// (bars, sidebars, popovers, cards) under surface (thumbnails). Shades
// are black in every theme, like the shell's own shadows.
function gtkColors(c, light) {
  const h = (k) => "#" + rgb(c[k]);
  const shade = (a) => "rgba(0, 0, 0, " + a + ")";
  return [
    ["window_bg_color", h("ground")], ["window_fg_color", h("ink")],
    ["view_bg_color", h("ground")], ["view_fg_color", h("ink")],
    ["headerbar_bg_color", h("card")], ["headerbar_fg_color", h("ink")],
    ["headerbar_border_color", h("ink")], ["headerbar_backdrop_color", h("ground")],
    ["headerbar_shade_color", shade(light ? 0.12 : 0.36)],
    ["headerbar_darker_shade_color", shade(light ? 0.12 : 0.9)],
    ["sidebar_bg_color", h("card")], ["sidebar_fg_color", h("ink")],
    ["sidebar_backdrop_color", h("ground")], ["sidebar_border_color", h("border")],
    ["sidebar_shade_color", shade(light ? 0.07 : 0.25)],
    ["secondary_sidebar_bg_color", h("card")], ["secondary_sidebar_fg_color", h("ink")],
    ["secondary_sidebar_backdrop_color", h("ground")],
    ["secondary_sidebar_border_color", h("border")],
    ["secondary_sidebar_shade_color", shade(light ? 0.07 : 0.25)],
    ["card_bg_color", h("card")], ["card_fg_color", h("ink")],
    ["card_shade_color", shade(light ? 0.07 : 0.36)],
    ["dialog_bg_color", h("card")], ["dialog_fg_color", h("ink")],
    ["popover_bg_color", h("card")], ["popover_fg_color", h("ink")],
    ["popover_shade_color", shade(light ? 0.07 : 0.25)],
    ["thumbnail_bg_color", h("surface")], ["thumbnail_fg_color", h("ink")],
    ["overview_bg_color", h("card")], ["overview_fg_color", h("ink")],
    ["shade_color", shade(light ? 0.07 : 0.25)],
    ["scrollbar_outline_color", light ? "#ffffff" : shade(0.5)],
    ["accent_bg_color", h("cyan")], ["accent_fg_color", h("onAccent")],
    ["destructive_bg_color", h("red")], ["destructive_fg_color", h("onAccent")],
    ["success_bg_color", h("green")], ["success_fg_color", h("onAccent")],
    ["warning_bg_color", h("yellow")], ["warning_fg_color", h("onAccent")],
    ["error_bg_color", h("red")], ["error_fg_color", h("onAccent")],
  ];
}

function gtkHead(file) {
  const out = HEAD.map((l) => "/* " + l + " */");
  out.push("", "/* Written by the shell (morpheus/ThemeSync.qml) whenever its theme",
           " * changes; " + file + " @imports it. Edits here are overwritten. */", "");
  return out;
}

function renderGtk4(c, light) {
  const out = gtkHead("gtk-4.0/gtk.css");
  if (!c) {
    out.push("/* Zenon is worn: nothing to override. */", "");
    return out.join("\n");
  }
  const t = gtkColors(c, light);
  out.push("/* " + (c.name || "theme") + " */", "");
  for (const l of t) out.push("@define-color " + l[0] + " " + l[1] + ";");
  out.push("", ":root {");
  for (const l of t) out.push("  --" + l[0].replace(/_/g, "-") + ": " + l[1] + ";");
  out.push("}", "");
  return out.join("\n");
}

function renderGtk3(c, light) {
  const out = gtkHead("gtk-3.0/gtk.css");
  if (!c) {
    out.push("/* Zenon is worn: nothing to override. */", "");
    return out.join("\n");
  }
  const h = (k) => "#" + rgb(c[k]);
  const t = gtkColors(c, light).filter((l) => !/^overview_/.test(l[0])).concat([
    ["accent_color", h("cyan")],
    ["destructive_color", h("red")], ["success_color", h("green")],
    ["warning_color", h("yellow")], ["error_color", h("red")],
    // the names GTK 3's own themes (and old apps) look up
    ["theme_bg_color", h("ground")], ["theme_fg_color", h("ink")],
    ["theme_base_color", h("ground")], ["theme_text_color", h("ink")],
    ["theme_selected_bg_color", h("cyan")], ["theme_selected_fg_color", h("onAccent")],
    ["theme_unfocused_bg_color", h("ground")], ["theme_unfocused_fg_color", h("ink")],
    ["theme_unfocused_base_color", h("ground")], ["theme_unfocused_text_color", h("ink")],
    ["theme_unfocused_selected_bg_color", h("cyan")],
    ["theme_unfocused_selected_fg_color", h("onAccent")],
    ["borders", h("border")], ["unfocused_borders", h("border")],
  ]);
  out.push("/* " + (c.name || "theme") + " */", "");
  for (const l of t) out.push("@define-color " + l[0] + " " + l[1] + ";");
  out.push("");
  return out.join("\n");
}

// gsettings' color-scheme, which libadwaita reads through the portal
function colorScheme(light) { return light ? "prefer-light" : "prefer-dark"; }

// ── Qt ─────────────────────────────────────────────────────────────────
// qt6ct/colors/zenworks.conf, a qt6ct color scheme, and qt6ct/qt6ct.conf,
// which points qt6ct at it. base.lua sets QT_QPA_PLATFORMTHEME=qt6ct, so
// every Qt app Hyprland starts — the screen-share picker, the polkit agent —
// paints with this palette. Written for Zenon too: Qt has no Zenon of its
// own, only Fusion's stock grays.
//
// A scheme is QPalette's roles in Qt's own order, one #aarrggbb each, for
// each of the three groups. Qt 6.6 added Accent at the end; a qt6ct that
// reads fewer roles leaves the rest at Fusion's.
//
// The ladder is the GTK one: windows are the ground, views and fields
// (Base) the card, alternate rows the surface. Fusion draws bevels from
// Light/Midlight/Mid/Dark/Shadow, so those are steps around the card.
function mix(a, b, t) {
  const x = parseInt(rgb(a), 16), y = parseInt(rgb(b), 16);
  const ch = (v, s) => (v >> s) & 255;
  let out = "";
  for (const s of [16, 8, 0])
    out += Math.round(ch(x, s) + (ch(y, s) - ch(x, s)) * t).toString(16).padStart(2, "0");
  return out;
}

const QT_ROLES = ["WindowText", "Button", "Light", "Midlight", "Dark", "Mid", "Text",
                  "BrightText", "ButtonText", "Base", "Window", "Shadow", "Highlight",
                  "HighlightedText", "Link", "LinkVisited", "AlternateBase", "NoRole",
                  "ToolTipBase", "ToolTipText", "PlaceholderText", "Accent"];

function qtPalette(c, light) {
  const k = (s) => rgb(c[s]);
  const active = {
    WindowText: k("ink"), Button: k("card"), Light: light ? "ffffff" : k("surface"),
    Midlight: light ? mix(c.card, "#ffffff", 0.5) : mix(c.card, c.surface, 0.5),
    Dark: light ? k("border") : mix(c.ground, "#000000", 0.3),
    Mid: light ? mix(c.card, c.border, 0.5) : k("border"),
    Text: k("ink"), BrightText: k("red"), ButtonText: k("ink"),
    Base: k("card"), Window: k("ground"), Shadow: "000000",
    Highlight: k("cyan"), HighlightedText: k("onAccent"),
    Link: k("blue"), LinkVisited: k("magenta"), AlternateBase: k("surface"),
    NoRole: "000000", ToolTipBase: k("card"), ToolTipText: k("ink"),
    PlaceholderText: k("muted"), Accent: k("cyan"),
  };
  // disabled: the type goes muted and a selection loses its color
  const disabled = Object.assign({}, active, {
    WindowText: k("muted"), Text: k("muted"), ButtonText: k("muted"),
    BrightText: k("muted"), Highlight: k("surface"), HighlightedText: k("muted"),
    PlaceholderText: mix(c.muted, c.card, 0.4), Accent: k("surface"),
  });
  const row = (p) => QT_ROLES.map((r) => "#ff" + p[r]).join(", ");
  // inactive (a window without the keys) is active: Fusion's own does that
  return { active: row(active), inactive: row(active), disabled: row(disabled) };
}

function renderQtColors(c, light) {
  const p = qtPalette(c, light);
  const out = HEAD.map((l) => "# " + l);
  out.push("", "# Written by the shell (morpheus/ThemeSync.qml) whenever its theme",
           "# changes; qt6ct.conf points here. Edits here are overwritten.",
           "# " + (c.name || "theme"), "",
           "[ColorScheme]",
           "active_colors=" + p.active,
           "disabled_colors=" + p.disabled,
           "inactive_colors=" + p.inactive, "");
  return out.join("\n");
}

// qt6ct.conf. Fonts and the icon theme are left out: qt6ct then falls back
// to the desktop's font, which is oracle's Font as fontsync.sh hands it to
// GTK (measured 2026-10-20: "SF Pro Text" 12 under qt6ct, Qt's stock "Sans
// Serif" 9 without).
//
// QUICKSHELL READS THIS TOO: it is started by Hyprland, so it has the
// variable, and everything it launches inherits it from it (which is why
// it is not stripped there). Measured 2026-10-20, it changes nothing the
// shell draws: no color comes from the palette (every TextArea/TextInput
// selection color is set), and only hidden TextInputs/TextEdits keep the
// default font. A visible Text with no font.pixelSize would now be 16px,
// not 12.
function renderQt6ct(schemePath) {
  const out = HEAD.map((l) => "# " + l);
  out.push("", "# Written by the shell (morpheus/ThemeSync.qml). Edits here are overwritten.", "",
           "[Appearance]",
           "color_scheme_path=" + schemePath,
           "custom_palette=true",
           "standard_dialogs=default",
           "style=Fusion", "");
  return out.join("\n");
}

// ── fcitx5's candidate list ─────────────────────────────────────────────
// Written as the user's theme named "default", which shadows fcitx5's own
// of that name: no classicui.conf to edit, and a theme picked in its
// configtool still wins. Only while oracle's Input methods is on
// (ThemeSync). The card, its border and the menu cursor's tint, as the
// shell's own menus have them; the text is fontconfig's Sans, which is
// oracle's Font (renderFontconfig).
function renderFcitxTheme(c) {
  const k = (s) => "#" + rgb(c[s]);
  const hi = "#" + mix(c.card, c.cyan, 0.16);
  const margin = (n) => ["Left=" + n, "Right=" + n, "Top=" + n, "Bottom=" + n];
  const sec = (name, lines) => ["[" + name + "]"].concat(lines, [""]);
  return HEAD.map((l) => "# " + l).concat(
    ["", "# Written by the shell (morpheus/ThemeSync.qml) whenever its theme",
     "# changes, while Input methods is on. Edits here are overwritten.",
     "# " + (c.name || "theme"), ""],
    sec("Metadata", ["Name=Zenworks", "Version=1", "Author=Zenworks",
                     "Description=The shell's theme", "ScaleWithDPI=True"]),
    sec("InputPanel", ["NormalColor=" + k("ink"), "HighlightCandidateColor=" + k("ink"),
                       "HighlightColor=" + k("ink"), "HighlightBackgroundColor=" + hi,
                       "Spacing=4", "EnableBlur=False", "FullWidthHighlight=True"]),
    sec("InputPanel/TextMargin", margin(6)),
    sec("InputPanel/Background", ["Color=" + k("card"), "BorderColor=" + k("border"), "BorderWidth=1"]),
    sec("InputPanel/Background/Margin", margin(2)),
    sec("InputPanel/Highlight", ["Color=" + hi]),
    sec("InputPanel/Highlight/Margin", margin(6)),
    sec("Menu", ["NormalColor=" + k("ink"), "HighlightCandidateColor=" + k("ink"), "Spacing=3"]),
    sec("Menu/Background", ["Color=" + k("card"), "BorderColor=" + k("border"), "BorderWidth=1"]),
    sec("Menu/Highlight", ["Color=" + hi]),
    sec("Menu/Separator", ["Color=" + k("border")]),
    sec("Menu/ContentMargin", margin(2)),
    sec("Menu/TextMargin", margin(6))).join("\n");
}
