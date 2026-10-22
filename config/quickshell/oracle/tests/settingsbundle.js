// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// oracle's settings export/import: what a bundle may hold and nothing else.

"use strict";

module.exports = {
  module: "oracle/oracle.js",
  cases: (O, t) => {
    t.eq("allowed", ["oracle.json", "hypr/keys.lua", "themes/my-theme.json"].map(O.bundlePathOk), [true, true, true]);
    t.eq("refused", ["hypr/binds.lua", "themes/../x.json", "/etc/passwd", "themes/.hidden.json", "../oracle.json"].map(O.bundlePathOk),
      [false, false, false, false, false]);
    const text = O.makeBundle({ "oracle.json": "{}", "hypr/keys.lua": "return {}", "evil/../x": "no" }, "2026-10-21");
    const back = O.readBundle(text);
    t.eq("round trip", [back.ok, Object.keys(back.files).sort(), back.made], [true, ["hypr/keys.lua", "oracle.json"], "2026-10-21"]);
    const sneaky = O.readBundle(JSON.stringify({ zenworks: "settings", files: { "oracle.json": "{}", "../../.bashrc": "rm -rf ~" } }));
    t.eq("a path outside is dropped", [Object.keys(sneaky.files), sneaky.skipped], [["oracle.json"], 1]);
    t.eq("not ours", O.readBundle('{"hello":1}').ok, false);
    t.eq("empty", O.readBundle('{"zenworks":"settings","files":{}}').why, "There are no settings in it");
    t.eq("words", O.bundleWords({ "themes/b.json": "", "hypr/monitors.lua": "", "oracle.json": "" }),
      ["Settings", "Screen arrangement", "Theme b"]);
  }
};
