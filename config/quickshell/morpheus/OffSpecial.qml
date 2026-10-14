// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SPECIAL WORKSPACE OPENS WHEN YOU OPEN IT, NOT WHEN A POPUP CLOSES.
// Launching a zenworks app (from Icarus, most visibly) with the special
// put away brought the special back up for a moment and the app mapped
// into it (user, 2026-10-15). Fixed here, for the whole shell, and not in
// the hypr config (the user's call: no special.lua) — the shell hands
// Hyprland a hook at runtime.
//
// WHY IT OPENED (found with a Lua probe on Hyprland's events, 0.56.2).
// Hidden over an empty workspace, the special leaves Hyprland's focused
// window inside it: nothing on the workspace can take focus, and the
// pointer refocus finds icarus-desktop rather than nothing, so focus is
// never cleared. Any zenworks popup ending its keyboard grab then makes
// Hyprland refocus that window (InputManager refocusLastWindow), and
// focusing a window in a hidden special SHOWS the special — the flash, and
// the app mapping into it a moment later.
//
// SO: a special that opens with no hand on it — SUPER not held (the
// SUPER+GRAVE bind), no shell toggle asking (offspecial.js wanted: the
// bar's toggle, a notification raising its app) — is put away again IN THE
// SAME CALLBACK, before a frame is drawn; the app then maps onto the
// workspace you are on. Not on a timer: a 1 ms timer still let the special
// start its slide in for a frame (user: "a flicker at the bottom of the
// screen"). Safe to re-enter: special_active is emitted on the last line of
// CMonitor::setSpecialWorkspace, and its callers (changeWorkspace,
// FocusState, toggleSpecial) only return or read a reference they hold
// afterwards (0.56.2); Hyprland also suppresses a callback re-entering
// itself, so the hide this causes does not come back here.
//
// WHAT IT LEAVES ALONE (user, 2026-10-15): with the special open and you in
// it, an app launched there opens IN the special and the special stays.
// Nothing here moves windows; an earlier version did (a window rule and a
// move after `openwindow`) and kicked those apps out — gone.
//
// Registered by `hyprctl eval` when the shell loads, and again after a
// config reload. A global holds the last hook, so a shell reload replaces
// it instead of stacking another.
//
// Loaded by shell.qml through a Loader.

import QtQuick
import Quickshell
import Quickshell.Hyprland

Item {
  id: off

  readonly property string install:
      "local z = rawget(_G, 'zenOffSpecial')\n"
    + "if z and z.sub2 then pcall(function() z.sub2:remove() end) end\n"
    + "z = { wanted = false, hiding = false }\n"
    // a show the shell asked for: offspecial.js wanted() calls this in the
    // same eval as its dispatch
    + "z.want = function()\n"
    + "  z.wanted = true\n"
    + "  hl.timer(function() z.wanted = false end, { timeout = 400, type = 'oneshot' })\n"
    + "end\n"
    // never an error on screen (Hyprland shows a callback's error as an
    // overlay): a surprise is let go
    + "local function guarded(fn) return function(...)\n"
    + "  if not pcall(fn, ...) then z.hiding = false end\n"
    + "end end\n"
    + "z.sub2 = hl.on('workspace.special_active', guarded(function(ws, m)\n"
    // put away comes as a workspace with no name, not as nil
    + "  local wsName = ws and ws.name\n"
    + "  if not wsName or wsName == '' then return end\n"
    + "  local super = hl.is_key_down('Super_L') or hl.is_key_down('Super_R')\n"
    + "  if super or z.wanted or z.hiding then return end\n"
    + "  z.hiding = true\n"
    + "  local name = (wsName:gsub('^special:', ''))\n"
    + "  hl.dispatch(hl.dsp.workspace.toggle_special(name))\n"
    + "  z.hiding = false\n"
    + "end))\n"
    + "_G.zenOffSpecial = z\n"

  function arm() { Quickshell.execDetached(["hyprctl", "-q", "eval", off.install]); }
  Component.onCompleted: off.arm()

  Connections {
    target: Hyprland
    // a config reload may drop runtime hooks
    function onRawEvent(ev) { if (ev.name === "configreloaded") off.arm(); }
  }
}
