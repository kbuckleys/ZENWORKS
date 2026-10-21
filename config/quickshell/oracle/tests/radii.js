// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// NO CORNER THAT IGNORES CORNER ROUNDING (user, 2026-10-21). Oracle has one
// setting for every rounded corner, and a corner written as a bare number
// stays put when it moves. So a radius in QML is a Zenon token
// (radiusControl, windowRadius, radiusCard, dialogRadius, menuRadius,
// pillRadius), Zenon.rad(n) for a size the scale has no name for, or one
// of what is not a corner:
//   0                     square on purpose
//   1.5 or less           a fine mark — a caret, a hairline, a 3px rule
//   half the element      a capsule or a circle: `width: 6; height: 6;
//                         radius: 3`, `height: 4 … radius: 2`, written
//                         as `height / 2` or as the number
//   `// shape`            on the line: a shape the user draws or picks
//                         (picasso's rounded-rectangle tool), not chrome

"use strict";

const fs = require("fs");
const path = require("path");

const SKIP_DIR = /^(oracle\/tests|oracle\/qmltests|themes|scripts|plato\/nvim)(\/|$)/;
// the setting's own default
const SKIP_FILE = new Set(["oracle/Oracle.qml"]);
// a radius property, then a number standing on its own: `radius: 4`,
// `topLeftRadius: index === 0 ? 3 : 0`
const PROP = /\b[a-zA-Z]*[rR]adius\s*:\s*([^;}\n]*)/g;
const NUM = /(^|[?:]\s*)(\d+(?:\.\d+)?)\s*(?=$|:|\/\/)/g;
const SIZE = /\b(?:implicit)?(?:[wW]idth|[hH]eight)\s*:\s*(\d+(?:\.\d+)?)\s*(?:$|;|\}|\/\/)/g;

function walk(root, d, out) {
  for (const e of fs.readdirSync(path.join(root, d), { withFileTypes: true })) {
    const rel = d ? d + "/" + e.name : e.name;
    if (e.name.startsWith(".") || SKIP_DIR.test(rel)) continue;
    if (e.isDirectory()) walk(root, rel, out);
    else if (/\.qml$/.test(e.name) && !SKIP_FILE.has(rel)) out.push(rel);
  }
  return out;
}

module.exports = {
  module: "morpheus/themesync.js",
  cases: (_S, t) => {
    const root = path.resolve(__dirname, "../..");
    const bad = [];
    for (const f of walk(root, "", [])) {
      const lines = fs.readFileSync(path.join(root, f), "utf8").split("\n");
      lines.forEach((line, i) => {
        if (/^\s*\/\//.test(line) || /\/\/\s*shape\b/.test(line)) return;
        // the sizes written near it: the element's own, above it or on the line
        const sizes = new Set();
        for (const l of lines.slice(Math.max(0, i - 12), i + 4))
          for (const m of l.matchAll(SIZE)) sizes.add(Number(m[1]));
        for (const p of line.replace(/\/\/.*$/, "").matchAll(PROP)) {
          for (const m of p[1].trim().matchAll(NUM)) {
            const n = Number(m[2]);
            if (n <= 1.5 || sizes.has(n * 2) || sizes.has(n * 2 + 1)) continue;
            bad.push(f + ":" + (i + 1) + "  " + line.trim().slice(0, 90));
          }
        }
      });
    }
    t.eq("every corner follows Corner rounding — a Zenon radius token or Zenon.rad(n)",
      bad.join("\n    "), "");
  }
};
