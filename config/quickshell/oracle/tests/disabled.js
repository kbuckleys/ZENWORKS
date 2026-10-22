// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE DIM FOR "CANNOT ACT". A control that is off, not ready or has nothing
// to work on fades to Zenon.disabledDim. Seventeen had drifted over five
// values, 0.3 to 0.6, one file at a time (2026-10-22): a Delphi button at
// 0.6 beside a Clio tool at 0.35 read as two different kinds of "no".
//
// What it catches: `opacity: <cond> ? 1 : <number>` where the condition
// reads as availability — enabled, ready, ok, live, can…, available. A dim
// for the selected row, the pressed key or the busiest core is not a
// disabled state and is not matched. A file that means one on purpose gets
// a BUDGET entry here, with why.

"use strict";

const fs = require("fs");
const path = require("path");

const BUDGET = {};

const SKIP_DIR = /^(oracle\/tests|oracle\/qmltests|themes|scripts|plato\/nvim)(\/|$)/;
const DIM = /\bopacity:\s*([^?\n]*)\?\s*1(?:\.0)?\s*:\s*(0?\.[0-9]+)\b/g;
const AVAILABLE = /(\benabled\w*|\bready\b|\bok\b|\blive\b|\bcan[A-Z]\w*|\bavailable\b)/;

function walk(root, d, out) {
  for (const e of fs.readdirSync(path.join(root, d), { withFileTypes: true })) {
    const rel = d ? d + "/" + e.name : e.name;
    if (e.name.startsWith(".") || SKIP_DIR.test(rel)) continue;
    if (e.isDirectory()) walk(root, rel, out);
    else if (e.name.endsWith(".qml")) out.push(rel);
  }
  return out;
}

module.exports = {
  module: "morpheus/themesync.js",
  cases: (_S, t) => {
    const root = path.resolve(__dirname, "../..");
    const over = [];
    for (const f of walk(root, "", [])) {
      const hits = [];
      fs.readFileSync(path.join(root, f), "utf8").split("\n").forEach((line, i) => {
        if (/^\s*\/\//.test(line)) return;
        for (const m of line.matchAll(DIM))
          if (AVAILABLE.test(m[1])) hits.push(f + ":" + (i + 1) + "  " + line.trim().slice(0, 90));
      });
      if (hits.length > (BUDGET[f] || 0))
        over.push(f + " has " + hits.length + " (budget " + (BUDGET[f] || 0) + "):\n      "
          + hits.join("\n      "));
    }
    t.eq("no literal disabled dims — use Zenon.disabledDim", over.join("\n    "), "");
  }
};
