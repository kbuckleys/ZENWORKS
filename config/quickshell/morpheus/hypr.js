// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
.pragma library
// ONE COPY FOR THE WHOLE SHELL (see morpheus/icons.js).
//
// HYPR — every dispatch the shell sends Hyprland, written in ONE place.
//
// This Hyprland runs its config in Lua (0.56), and a dispatch is a Lua call:
// `hl.dsp.focus({ window = "title:^(ceres)$" })`. The old string form
// ("focuswindow title:…") is refused there — a whole round of "raise does
// nothing" before anyone noticed. The syntax has changed once already, so
// the shell builds no dispatch string of its own any more: it asks here,
// and the next change in Hyprland's API is one edit in this file.
//
//   Hyprland.dispatch(Hypr.focusTitle("ceres"))
//   ["hyprctl", "dispatch", Hypr.dpms(true)]
//
// Pure strings — no Hyprland import, so oracle/tests/hypr.js can pin every
// one of them, and a .js that builds dispatches (terminus.js) can use it.

// a Lua string literal: what goes between the quotes, escaped
function lua(s) {
  return '"' + String(s ?? "").replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"';
}

// a window selector by exact title: "title:^(ceres)$"
function byTitle(title) {
  return "title:^(" + String(title ?? "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")$";
}

// by class, any case: "class:(?i)^(spotify)$" — `cls` is taken as written,
// so a caller strips what it does not trust (howler keeps [A-Za-z0-9._-])
function byClass(cls) {
  return "class:(?i)^(" + String(cls ?? "") + ")$";
}

// by address, with or without its 0x
function byAddress(address) {
  const a = String(address ?? "").replace(/^0x/, "");
  return "address:0x" + a;
}

// ── focus ─────────────────────────────────────────────────────────────────
function focusWindow(selector) { return "hl.dsp.focus({ window = " + lua(selector) + " })"; }
function focusTitle(title) { return focusWindow(byTitle(title)); }
function focusWorkspace(name) { return "hl.dsp.focus({ workspace = " + lua(name) + " })"; }
// to the front of its workspace, over the floating windows focus alone
// leaves on top of it (the window switcher, 2026-10-26)
function raiseWindow(selector) { return "hl.dsp.window.alter_zorder({ mode = \"top\", window = " + lua(selector) + " })"; }

// ── workspaces ────────────────────────────────────────────────────────────
// a special workspace by its bare name ("magic", not "special:magic")
function toggleSpecial(name) { return "hl.dsp.workspace.toggle_special(" + lua(name) + ")"; }

// ── the active window, or the one a selector names ──────────────────────
function fullscreen() { return "hl.dsp.window.fullscreen()"; }
// closed as its own close button would (not killed): the app may ask first
function closeWindow(selector) { return "hl.dsp.window.close({ window = " + lua(selector) + " })"; }

function moveOrResize_(verb, dx, dy, selector) {
  return "hl.dsp.window." + verb + "({ x = " + Number(dx || 0) + ", y = " + Number(dy || 0)
    + ", relative = true" + (selector ? ", window = " + lua(selector) : "") + " })";
}
function resizeBy(dx, dy, selector) { return moveOrResize_("resize", dx, dy, selector); }
function moveBy(dx, dy, selector) { return moveOrResize_("move", dx, dy, selector); }

// ── submaps ───────────────────────────────────────────────────────────────
// "reset" is the default one. Oracle's Shortcuts holds hyprland in
// "oracle-keys" (binds.lua: next to no binds) while it waits for a chord.
function submap(name) { return "hl.dsp.submap(" + lua(name || "reset") + ")"; }

// ── screens ───────────────────────────────────────────────────────────────
// `hyprctl dispatch dpms on` is a Lua syntax error on this Hyprland; this is
// the form that answers "ok"
function dpms(on) { return "hl.dsp.dpms({ action = " + lua(on ? "enable" : "disable") + " })"; }
