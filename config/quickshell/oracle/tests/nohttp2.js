// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// QT NEVER OPENS HTTP/2 (2026-10-26). Qt 6.12's HTTP/2 crashed the shell,
// and Hyprland after it, on 2026-10-20 (a cover fetched by an Image). Every
// request goes through curl instead: morpheus/Net.qml for text,
// NowPlaying.art() for pictures. What it catches: an XMLHttpRequest
// anywhere, and an Image or AnimatedImage whose source is an http(s)
// literal.

"use strict";

const fs = require("fs");
const path = require("path");

const SKIP_DIR = /^(oracle\/tests|oracle\/qmltests|themes|plato\/nvim)(\/|$)/;

function walk(root, d, out) {
  for (const e of fs.readdirSync(path.join(root, d), { withFileTypes: true })) {
    const rel = d ? d + "/" + e.name : e.name;
    if (e.name.startsWith(".") || SKIP_DIR.test(rel)) continue;
    if (e.isDirectory()) walk(root, rel, out);
    else if (/\.(qml|js)$/.test(e.name)) out.push(rel);
  }
  return out;
}

module.exports = {
  module: "morpheus/themesync.js",
  cases: (_S, t) => {
    const root = path.resolve(__dirname, "../..");
    const xhr = [], img = [];
    for (const f of walk(root, "", [])) {
      const lines = fs.readFileSync(path.join(root, f), "utf8").split("\n");
      lines.forEach((l, i) => {
        const code = l.replace(/\/\/.*$/, "");
        if (/\bnew\s+XMLHttpRequest\b/.test(code)) xhr.push(f + ":" + (i + 1));
        if (/^\s*source:\s*["'`]https?:/.test(code)) img.push(f + ":" + (i + 1));
      });
    }
    t.eq("no XMLHttpRequest: requests go through morpheus/Net (curl)", xhr.join("\n    "), "");
    t.eq("no Image loads an http(s) source", img.join("\n    "), "");
  },
};
