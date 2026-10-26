// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A PROPERTY NAMED onX WHERE THE OBJECT ALSO HAS x IS NO PROPERTY (found
// 2026-10-27). QML reads its binding as the handler of x's change, without
// a word: the value stays empty — Check's onInk drew picasso's lit "Span
// across" label black, PicassoDaemon's onScreen (a PanelWindow has
// `screen`) never told the store what was on screen. A literal at least
// fails to load; an expression fails silently. What it catches: an onX
// declared in a file that also declares x, or where x is an Item's own.

"use strict";

const fs = require("fs");
const path = require("path");

const SKIP_DIR = /^(oracle\/tests|oracle\/qmltests|themes|plato\/nvim)(\/|$)/;
// an Item's (and a window's) own, which no file declares
const BUILTIN = ["color", "width", "height", "visible", "enabled", "text", "x", "y",
  "opacity", "parent", "state", "focus", "scale", "rotation", "z", "clip",
  "radius", "font", "data", "children", "border", "anchors", "title"];
// reviewed: the x is another object's in the same file (AppPicker's
// `handler` is a delegate's, not the picker's)
const ALLOWED = ["terminus/AppPicker.qml onHandler"];

function walk(root, d, out) {
  for (const e of fs.readdirSync(path.join(root, d), { withFileTypes: true })) {
    const rel = d ? d + "/" + e.name : e.name;
    if (e.name.startsWith(".") || SKIP_DIR.test(rel)) continue;
    if (e.isDirectory()) walk(root, rel, out);
    else if (/\.qml$/.test(e.name)) out.push(rel);
  }
  return out;
}

module.exports = {
  module: "morpheus/themesync.js",
  cases: (_S, t) => {
    const root = path.resolve(__dirname, "../..");
    const bad = [];
    for (const f of walk(root, "", [])) {
      const src = fs.readFileSync(path.join(root, f), "utf8");
      const declared = new Set();
      for (const m of src.matchAll(/property\s+[\w.<>]+\s+(\w+)/g)) declared.add(m[1]);
      src.split("\n").forEach((l, i) => {
        const m = /property\s+[\w.<>]+\s+on([A-Z]\w*)/.exec(l.replace(/\/\/.*$/, ""));
        if (!m) return;
        const base = m[1][0].toLowerCase() + m[1].slice(1);
        if (ALLOWED.indexOf(f + " on" + m[1]) >= 0) return;
        if (declared.has(base) || BUILTIN.indexOf(base) >= 0) bad.push(f + ":" + (i + 1) + " on" + m[1]);
      });
    }
    t.eq("no onX property beside an x (it turns into x's change handler)", bad.join("\n    "), "");
  },
};
