// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// hypr/lua/effects.lua: hyprland's shadows and animations, on unless false.

"use strict";

module.exports = {
  module: "oracle/oracle.js",
  cases: (O, t) => {
    const fx = (s, a) => { const r = O.parseEffectsLua(O.renderEffectsLua({ shadows: s, animations: a }));
      return { shadows: r.shadows, animations: r.animations }; };
    t.eq("round trip", [fx(false, true), fx(true, false)],
      [{ shadows: false, animations: true }, { shadows: true, animations: false }]);
    t.eq("no file is every default", O.parseEffectsLua(""), { shadows: true, animations: true, gaps_out: 8, gaps_in: 2, special_gaps: 30,
      border_size: 1, layout: "dwindle", resize_on_border: false, dim_inactive: 0, inactive_opacity: 1 });
    const all = { shadows: false, animations: true, gaps_out: 12, gaps_in: 0, special_gaps: 60, border_size: 2, layout: "scrolling",
                  resize_on_border: true, dim_inactive: 0.2, inactive_opacity: 0.85 };
    t.eq("every field round trips", O.parseEffectsLua(O.renderEffectsLua(all)), all);
    t.eq("numbers kept in range, layouts known", [O.parseEffectsLua("return { gaps_out = 900, inactive_opacity = 0.1 }").gaps_out,
      O.parseEffectsLua("return { inactive_opacity = 0.1 }").inactive_opacity, O.parseEffectsLua('return { layout = "bogus" }').layout],
      [40, 0.5, "dwindle"]);
    t.eq("an older file (two fields) keeps the rest at defaults",
      O.parseEffectsLua("return {\n\tshadows = false,\n\tanimations = true,\n}").gaps_out, 8);
    t.eq("a comment is not a choice", O.parseEffectsLua("-- shadows = false\nreturn {}").shadows, true);
    t.eq("in a bundle", [O.bundlePathOk("hypr/effects.lua"), O.bundleWords({ "hypr/effects.lua": "" })],
      [true, ["Window shadows and animations"]]);
  }
};
