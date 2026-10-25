// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// morpheus/AtomicWriter's shell line, read out of the QML and run as it
// ships: a write that lands says 0 — into a directory not made yet too
// (2026-10-25, a fresh ~/.config/zenworks) — and one that cannot (2026-10-23:
// a failed write came back 0, rm's own answer) says it failed and leaves no
// temp file behind.

"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

module.exports = {
  module: "morpheus/themesync.js",
  cases: (_S, t) => {
    const qml = fs.readFileSync(path.join(__dirname, "../../morpheus/AtomicWriter.qml"), "utf8");
    const m = /"sh", "-c",\s*("mkdir -p (?:[^"\\]|\\.)*")/.exec(qml);
    t.eq("the line is found", !!m, true);
    if (!m) return;
    const script = JSON.parse(m[1]);
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "atomicwriter-"));
    const run = (p) => cp.spawnSync("sh", ["-c", script, "t", p], { input: "body\n" }).status;
    try {
      const ok = path.join(dir, "f.json");
      t.eq("a write lands", [run(ok), fs.readFileSync(ok, "utf8")], [0, "body\n"]);
      const deep = path.join(dir, "new", "dir", "f.json");
      t.eq("a directory not there yet is made", [run(deep), fs.readFileSync(deep, "utf8")], [0, "body\n"]);
      // a "directory" that is a file: neither made nor written
      t.eq("a write that cannot says so", run(path.join(ok, "f.json")), 1);
      t.eq("and leaves no temp file", fs.readdirSync(dir).sort(), ["f.json", "new"]);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  }
};
