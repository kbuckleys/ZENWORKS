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
    const fx = (s, a) => O.parseEffectsLua(O.renderEffectsLua({ shadows: s, animations: a }));
    t.eq("round trip", [fx(false, true), fx(true, false)],
      [{ shadows: false, animations: true }, { shadows: true, animations: false }]);
    t.eq("no file is both on", O.parseEffectsLua(""), { shadows: true, animations: true });
    t.eq("a comment is not a choice", O.parseEffectsLua("-- shadows = false\nreturn {}").shadows, true);
    t.eq("in a bundle", [O.bundlePathOk("hypr/effects.lua"), O.bundleWords({ "hypr/effects.lua": "" })],
      [true, ["Window shadows and animations"]]);
  }
};
