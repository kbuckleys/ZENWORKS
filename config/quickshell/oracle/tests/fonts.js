// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// NO TEXT THAT IGNORES FONT SIZE (user, 2026-10-22). Oracle's Font size
// scales every text through Zenon.px(n), and a size written as a bare number
// stays put when it moves: Calypso's Large Type and a dozen glyphs had
// drifted that way, one file at a time.
//
// What it catches: `pixelSize: 40`, `font.pointSize: 12`,
// `property int pixelSize: 16`, `pixelSize: big ? 24 : 16` — a number
// standing on its own as the value. A number inside an expression
// (`Math.max(11, face.pixelSize - 2)`, `Zenon.px(big ? 16 : 14)`) is not
// matched.
// A file that means a true size on purpose gets a BUDGET entry here, with
// why.

"use strict";

const fs = require("fs");
const path = require("path");

const BUDGET = {
  // the font book shows a face at its real size: specimens, not chrome
  "alexandria/AlexandriaWindow.qml": 5,
  // a FontMetrics probe that asks whether i is as wide as W; never drawn
  "terminus/FontSpecimen.qml": 1,
};

const SKIP_DIR = /^(oracle\/tests|oracle\/qmltests|themes|scripts|plato\/nvim)(\/|$)/;
const PROP = /\b(?:pixelSize|pointSize)\s*:\s*([^;}\n]*)/g;
const NUM = /(^|[?:]\s*)(\d+(?:\.\d+)?)\s*(?=$|:|\/\/)/g;

// the value with every call's arguments taken out: what is left standing
function bare(v) {
  let s = v.trim(), was;
  do { was = s; s = s.replace(/[\w.]*\([^()]*\)/g, "f"); } while (s !== was);
  // a call still open at the line's end runs on below: all expression
  return s.replace(/[\w.]*\(.*$/, "f");
}

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
      const hits = [];
      fs.readFileSync(path.join(root, f), "utf8").split("\n").forEach((line, i) => {
        if (/^\s*\/\//.test(line)) return;
        for (const p of line.replace(/\/\/.*$/, "").matchAll(PROP))
          if ([...bare(p[1]).matchAll(NUM)].length)
            hits.push(f + ":" + (i + 1) + "  " + line.trim().slice(0, 90));
      });
      if (hits.length > (BUDGET[f] || 0)) bad.push(...hits);
    }
    t.eq("every text size follows Font size — Zenon.px(n), not a bare number",
      bad.join("\n    "), "");
  }
};
