// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// NO NEW HARDCODED COLOURS. Every theming bug of 2026-10-08 was one: a
// black floor written as Qt.rgba(0,0,0,a), a hex in a JS file, a colour
// copied onto a row, a darken-towards-black — each right for Zenon and
// wrong for every other theme, found weeks later as a dark slab in Latte.
//
// So every file has a BUDGET: how many raw colour literals it holds — a
// uniform white or black Qt.rgba, or a "#hex" string — counted when the
// themes went in. The ones there are deliberate (drawn over pictures, alpha
// masks, a shadow that is black in every theme, content colours). Fewer is
// fine; MORE fails, naming the lines. Reach for Zenon instead: floor/wash/
// shade/darken/hud/alpha/mix, or a theme slot. If a new literal really is
// one of the deliberate kind, raise its file's number here, on purpose.
//
// Zenon itself, the palette generators, the themes and the tests are not
// counted: colours are what they are made of.

"use strict";

const fs = require("fs");
const path = require("path");

const BUDGET = {
  "terminus/Sidebar.qml": 3,
  "terminus/Chrome.qml": 11,
  "artemis/artemis.js": 1,
  "cerberus/CerberusLock.qml": 2,
  "metis/ChipStrip.qml": 6,
  "morpheus/Frost.qml": 6,
  "morpheus/ScrollEdge.qml": 5,
  "picasso/Annotator.qml": 10,
  "picasso/ColorPicker.qml": 15,
  "picasso/FocusCard.qml": 7,
  "picasso/LookEditor.qml": 9,
  "picasso/Loupe.qml": 1,
  "picasso/MapView.qml": 1,
  "picasso/PicassoCapture.qml": 1,
  "picasso/PicassoPicker.qml": 3,
  "picasso/PicassoPopup.qml": 1,
  "picasso/Scene.qml": 4,
  "picasso/ViewerWindow.qml": 21,
  "picasso/Vignette.qml": 2,
  "picasso/capture.js": 2,
  "picasso/picasso.js": 31,
  "picasso/viewer.js": 2,
  "plato/core/EditorState.qml": 5,
  "plato/editor/SettingsSheet.qml": 1,
  "terminus/TerminusWindow.qml": 0,
  "zeus/ZeusPopup.qml": 2
};

const SKIP_DIR = /^(oracle\/tests|oracle\/qmltests|themes|scripts|plato\/nvim)(\/|$)/;
const SKIP_FILE = new Set(["morpheus/Zenon.qml", "morpheus/wallpalette.js",
                           "morpheus/themesync.js", "oracle/test.js"]);
const RGBA = /Qt\.rgba\(\s*([01])\s*,\s*\1\s*,\s*\1\s*,/g;
const HEX = /["']#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})["']/g;

function walk(root, d, out) {
  for (const e of fs.readdirSync(path.join(root, d), { withFileTypes: true })) {
    const rel = d ? d + "/" + e.name : e.name;
    if (e.name.startsWith(".") || SKIP_DIR.test(rel)) continue;
    if (e.isDirectory()) walk(root, rel, out);
    else if (/\.(qml|js)$/.test(e.name) && !SKIP_FILE.has(rel)) out.push(rel);
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
        const n = (line.match(RGBA) || []).length + (line.match(HEX) || []).length;
        for (let k = 0; k < n; ++k) hits.push(f + ":" + (i + 1) + "  " + line.trim().slice(0, 90));
      });
      if (hits.length > (BUDGET[f] || 0))
        over.push(f + " has " + hits.length + " (budget " + (BUDGET[f] || 0) + "):\n      "
          + hits.join("\n      "));
    }
    t.eq("no file holds more raw colour literals than its budget — use Zenon", over.join("\n    "), "");
  }
};
