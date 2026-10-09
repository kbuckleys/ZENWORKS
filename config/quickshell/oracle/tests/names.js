// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// NO TYPE NAME FROM TWO PLACES. A QML file sees the types of its own
// directory and of every directory it imports, and when two of them offer
// the same name, the import wins — silently. That broke plato on 2026-10-08:
// terminus grew a `Selection` controller, plato/editor imports terminus and
// has a Selection of its own, and plato's editor stopped being built (only
// noticed when plato was opened: windows are built lazily). The same day a
// terminus `Slide` was shadowed by picasso's.
//
// So for every file: its own directory's names and each imported
// directory's exports (the qmldir when there is one, the files when not)
// must not overlap. A new file with a name already taken fails here.

"use strict";

const fs = require("fs");
const path = require("path");

const SKIP = /^(oracle\/qmltests)(\/|$)/;

function qmlFiles(root, d, out) {
  for (const e of fs.readdirSync(path.join(root, d), { withFileTypes: true })) {
    const rel = d ? d + "/" + e.name : e.name;
    if (e.name.startsWith(".") || SKIP.test(rel)) continue;
    if (e.isDirectory()) qmlFiles(root, rel, out);
    else if (e.name.endsWith(".qml")) out.push(rel);
  }
  return out;
}

function exportsOf(root, d) {
  const q = path.join(root, d, "qmldir");
  if (fs.existsSync(q)) {
    const out = new Set();
    for (const l of fs.readFileSync(q, "utf8").split("\n")) {
      const w = l.trim().split(/\s+/);
      if (!w[0] || /^(module|#|internal|depends|import|plugin|classname|typeinfo)$/.test(w[0])) continue;
      out.add(w[0] === "singleton" ? w[1] : w[0]);
    }
    return out;
  }
  return ownNames(root, d);
}

function ownNames(root, d) {
  const dir = path.join(root, d);
  if (!fs.existsSync(dir)) return new Set();
  return new Set(fs.readdirSync(dir).filter((f) => /^[A-Z]\w*\.qml$/.test(f)).map((f) => f.slice(0, -4)));
}

module.exports = {
  module: "morpheus/themesync.js",
  cases: (_S, t) => {
    const root = path.resolve(__dirname, "../..");
    const clashes = [];
    for (const f of qmlFiles(root, "", [])) {
      const d = path.dirname(f) === "." ? "" : path.dirname(f);
      const src = fs.readFileSync(path.join(root, f), "utf8");
      const sources = [["its own directory", ownNames(root, d)]];
      for (const m of src.matchAll(/^import "([^"]+)"\s*$/gm)) {
        if (m[1].endsWith(".js") || m[1] === ".") continue;
        const imp = path.normalize(path.join(d, m[1]));
        if (fs.existsSync(path.join(root, imp)) && fs.statSync(path.join(root, imp)).isDirectory())
          sources.push([imp, exportsOf(root, imp)]);
      }
      const seen = new Map();
      for (const [from, names] of sources)
        for (const n of names) seen.set(n, (seen.get(n) || new Set()).add(from));
      for (const [n, from] of seen)
        if (from.size > 1) clashes.push(f + ": " + n + " from " + [...from].join(" and "));
    }
    t.eq("no QML type name is offered by two places a file can see", clashes.join("\n    "), "");
  }
};
