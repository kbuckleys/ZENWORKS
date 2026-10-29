// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// hypr/lua/hyprland.lua: the rest of hyprland's settings, by hyprland's own
// names, that Oracle's Windows, Tiling, Workspaces, Window effects, Motion,
// Keyboard & mouse and Display pages write (2026-10-29).

"use strict";

module.exports = {
  module: "oracle/oracle.js",
  cases: (O, t) => {
    const fields = O.hyprFields();
    const defs = {};
    for (const f of fields) defs[f.key] = f.def;
    t.eq("keys are unique", new Set(O.hyprKeys()).size, fields.length);
    t.eq("no file is every default", O.parseHyprLua(O.renderHyprLua({})), defs);
    t.eq("a default fits its own row", fields.filter((f) => !O.same(O.coerce(O.hyprSpec(f, []), f.def), f.def)).map((f) => f.key), []);
    t.eq("every row has a label and a help line, or is a workspace after the first",
      fields.filter((f) => !f.label || (!f.help && !/^zen:ws:([2-9]|10):/.test(f.key))).map((f) => f.key), []);
    const some = Object.assign({}, defs, { "misc:vrr": 2, "decoration:blur:noise": 0.0117, "misc:swallow_regex": "^(kitty|foot)$",
      "decoration:shadow:offset": "0 10", "zen:gesture:3:up": "special", "zen:ws:2:monitor": "DP-1" });
    t.eq("round trip, four places kept", O.parseHyprLua(O.renderHyprLua(some)), some);
    t.eq("a hand-written key is kept", O.parseHyprLua(O.renderHyprLua({ "debug:overlay": true }))["debug:overlay"], true);
    t.eq("a comment is not a choice", O.parseHyprLua('-- ["misc:vrr"] = 1\nreturn {}')["misc:vrr"], undefined);
    t.eq("a row is hl:<name>, its choices filled in",
      [O.hyprSpec(fields.find((f) => f.key === "zen:gesture:3:up"), []).key, O.hyprSpec(fields.find((f) => f.key === "zen:gesture:3:up"), []).options.length,
       O.hyprSpec(fields.find((f) => f.key === "zen:ws:1:monitor"), ["DP-1"]).options.map((o) => o.value)],
      ["hl:zen:gesture:3:up", 8, ["", "DP-1"]]);
    // an import: only the fields, each the kind it should be
    const imp = O.parseHyprLua(O.sanitizeBundleFile("hypr/hyprland.lua",
      'return { ["misc:vrr"] = 9, ["decoration:blur:passes"] = 99, ["os.execute"] = "rm", ["master:orientation"] = "sideways" }', []));
    t.eq("an import keeps only known fields, coerced",
      [imp["misc:vrr"], imp["decoration:blur:passes"], imp["os.execute"], imp["master:orientation"]], [0, 6, undefined, "left"]);
    t.eq("in a bundle", [O.bundlePathOk("hypr/hyprland.lua"), O.bundleWords({ "hypr/hyprland.lua": "" })], [true, ["Hyprland settings"]]);
  }
};
