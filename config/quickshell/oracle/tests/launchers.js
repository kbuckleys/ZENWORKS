// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The shipped launchers (share/applications beside config/, installed in
// /usr/share/applications) against the managers' `Desktop.launcher` calls
// they are made from (scripts/launchers.js): a field changed in a manager
// and not regenerated fails here. A tree with no share/ (the shell alone,
// copied somewhere) has nothing to compare and passes.

"use strict";

const fs = require("fs");
const path = require("path");

module.exports = {
  module: "morpheus/themesync.js",
  cases: (_S, t) => {
    const L = require("../../scripts/launchers.js");
    const root = path.join(__dirname, "../..");
    const all = L.launchers(root);
    t.eq("every suite app describes its launcher", all.length >= 14, true);
    t.eq("each one names its program under the package's prefix",
      all.filter((l) => !String(l.fields.Exec).startsWith(L.PREFIX + "/")).map((l) => l.id), []);
    t.eq("ids are unique", new Set(all.map((l) => l.id)).size, all.length);
    t.eq("a list ends with the spec's ;", L.render({ Categories: ["A", "B"] }), "[Desktop Entry]\nCategories=A;B;\n");
    t.eq("a path with a space is quoted", L.execLine("/a b/c", "%F"), "\"/a b/c\" %F");
    const dir = path.join(root, "../../share/applications");
    if (!fs.existsSync(dir)) return;
    const stale = all.filter((l) => {
      const f = path.join(dir, l.id + ".desktop");
      return !fs.existsSync(f) || fs.readFileSync(f, "utf8") !== L.render(l.fields);
    }).map((l) => l.id);
    t.eq("share/applications is what the managers say (node scripts/launchers.js --write ../../share/applications)", stale, []);
    const extra = fs.readdirSync(dir).filter((f) => f.endsWith(".desktop") && !all.some((l) => l.id + ".desktop" === f));
    t.eq("and holds no launcher no manager describes", extra, []);
  }
};
