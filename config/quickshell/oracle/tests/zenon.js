// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ZENON'S INPUTS, LISTED ONCE. ZenonBase reads its settings from `cfg` and
// names every key it reads in `cfgKeys`; ThemeSync carries exactly those to
// iris. A read missing from the list would leave iris on that setting's
// default while the shell wore yours — so both directions are checked here.

"use strict";

const fs = require("fs");
const path = require("path");

module.exports = {
  // read as text below; the runner wants a JS module to load
  module: "morpheus/themesync.js",
  cases: (_S, t) => {
    const src = fs.readFileSync(path.resolve(__dirname, "../../morpheus/zenon/ZenonBase.qml"), "utf8");
    const code = src.split("\n").filter((l) => !/^\s*\/\//.test(l)).join("\n");
    const read = [...new Set((code.match(/\bcfg\.([A-Za-z]+)/g) || []).map((s) => s.slice(4)))].sort();
    const m = code.match(/cfgKeys:\s*\[([^\]]*)\]/);
    const listed = m ? [...m[1].matchAll(/"([A-Za-z]+)"/g)].map((x) => x[1]).sort() : [];
    t.eq("every cfg read is in cfgKeys", read.filter((k) => !listed.includes(k)).join(" "), "");
    t.eq("cfgKeys names nothing that is not read", listed.filter((k) => !read.includes(k)).join(" "), "");
    t.eq("ZenonBase imports nothing but QtQuick",
         (code.match(/^import .*$/gm) || []).join(" | "), "import QtQuick");
  }
};
