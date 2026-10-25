// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Every dispatch the shell sends (morpheus/hypr.js). The strings the call
// sites wrote by hand before 2026-10-18 are pinned verbatim, so moving them
// here changed nothing Hyprland sees.

"use strict";

module.exports = {
  module: "morpheus/hypr.js",
  cases: (H, t) => {
    t.eq("focus by title, as the managers wrote it", H.focusTitle("ceres"),
      'hl.dsp.focus({ window = "title:^(ceres)$" })');
    t.eq("a dash is not escaped", H.focusTitle("picasso-view"),
      'hl.dsp.focus({ window = "title:^(picasso-view)$" })');
    t.eq("regex characters in a title are", H.byTitle("a.b (c)"), "title:^(a\\.b \\(c\\))$");
    t.eq("focus by a selector", H.focusWindow("address:0x1f"),
      'hl.dsp.focus({ window = "address:0x1f" })');
    t.eq("an address gains its 0x once", H.byAddress("1f"), "address:0x1f");
    t.eq("and keeps the one it has", H.byAddress("0x1f"), "address:0x1f");
    t.eq("a workspace, as the bar wrote it", H.focusWorkspace("3"),
      'hl.dsp.focus({ workspace = "3" })');
    t.eq("fullscreen", H.fullscreen(), "hl.dsp.window.fullscreen()");
    t.eq("close by address", H.closeWindow(H.byAddress("1f")), 'hl.dsp.window.close({ window = "address:0x1f" })');
    t.eq("a relative resize of a named window, as terminus wrote it",
      H.resizeBy(10, 0, "address:0xab"),
      'hl.dsp.window.resize({ x = 10, y = 0, relative = true, window = "address:0xab" })');
    t.eq("and a move", H.moveBy(400, 0, "address:0xab"),
      'hl.dsp.window.move({ x = 400, y = 0, relative = true, window = "address:0xab" })');
    t.eq("no selector, the active window", H.moveBy(-5, 7),
      "hl.dsp.window.move({ x = -5, y = 7, relative = true })");
    t.eq("howler's class focus, verbatim", H.focusWindow(H.byClass("spotify")),
      'hl.dsp.focus({ window = "class:(?i)^(spotify)$" })');
    t.eq("the bar's special toggle, verbatim", H.toggleSpecial("magic"),
      'hl.dsp.workspace.toggle_special("magic")');
    t.eq("dpms on, as socordia wrote it", H.dpms(true), 'hl.dsp.dpms({ action = "enable" })');
    t.eq("dpms off", H.dpms(false), 'hl.dsp.dpms({ action = "disable" })');
    t.eq("a submap", H.submap("oracle-keys"), 'hl.dsp.submap("oracle-keys")');
    t.eq("none is the default one", H.submap(""), 'hl.dsp.submap("reset")');
    t.eq("quotes cannot end the Lua string", H.lua('a"b\\c'), '"a\\"b\\\\c"');
    t.eq("nor can a newline", H.lua("a\nb"), '"a\\nb"');
  }
};
