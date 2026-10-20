// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// NO NEW LITERAL DURATIONS. A `duration: 550` written in place is a number
// nobody else shares: the launchers' carets had drifted to 550 on one curve
// while morpheus/Caret breathed at 620 on another, and the hover peeks to
// four different waits (2026-10-20). Reach for Zenon instead — fast/normal/
// slow/brisk for motion, breath/beacon/spin/sweep/glow for loops, ms(n) for
// a one-off that should still follow Animation speed.
//
// As colours.js does, every file has a BUDGET: the literals it holds on
// purpose. Fewer is fine; MORE fails, naming the lines. A PauseAnimation's
// hold and `duration: 0` are not counted.

"use strict";

const fs = require("fs");
const path = require("path");

const BUDGET = {
  "chronos/ChronosPopup.qml": 2,   // a bar tracking the 1 s tick: Linear, the tick's own length
  "morpheus/Workspaces.qml": 8,    // the urgent double flash: an alert's pattern, not motion
  "morpheus/Elastic.qml": 1        // the rubber band's bounce, tuned with scrollfeel.js
};

const SKIP_DIR = /^(oracle\/tests|oracle\/qmltests|themes|scripts|plato\/nvim)(\/|$)/;
const LIT = /\bduration:\s*([0-9]+)\b/g;

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
        if (/^\s*\/\//.test(line) || /PauseAnimation/.test(line)) return;
        for (const m of line.matchAll(LIT))
          if (m[1] !== "0") hits.push(f + ":" + (i + 1) + "  " + line.trim().slice(0, 90));
      });
      if (hits.length > (BUDGET[f] || 0))
        over.push(f + " has " + hits.length + " (budget " + (BUDGET[f] || 0) + "):\n      "
          + hits.join("\n      "));
    }
    t.eq("no file holds more literal durations than its budget — use Zenon", over.join("\n    "), "");
  }
};
