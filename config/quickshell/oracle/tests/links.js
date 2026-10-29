// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A LINK FROM SOMEONE ELSE'S TEXT IS OPENED ONLY WHEN IT IS THE WEB (audit
// 2026-10-26). xdg-open and Qt.openUrlExternally hand file:, a .desktop or
// any scheme handler whatever a PDF, an issue or a store listing names.
// Such links go through Strings.openLink. What it catches: a rich text's
// onLinkActivated that opens its link by any other way, and
// Qt.openUrlExternally on anything but a literal or a reviewed gate.

"use strict";

const fs = require("fs");
const path = require("path");

const SKIP_DIR = /^(oracle\/tests|oracle\/qmltests|themes|plato\/nvim)(\/|$)/;
// reviewed: MinervaBook tests the scheme on the line before; AurPage's is
// built from the AUR's own host
const ALLOWED = ["minerva/MinervaBook.qml", "delphi/AurPage.qml"];

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
    const act = [], ext = [];
    for (const f of walk(root, "", [])) {
      const lines = fs.readFileSync(path.join(root, f), "utf8").split("\n");
      lines.forEach((l, i) => {
        const code = l.replace(/\/\/.*$/, "");
        if (/onLinkActivated:.*(xdg-open|openUrlExternally)/.test(code) || /^\s*\["xdg-open", (url|link)\]/.test(code)) act.push(f + ":" + (i + 1));
        // an address a server or a listing handed over (a forge's .url, a
        // package's link) — audit 2026-10-28b: Delphi's forge pages did this
        if (/"xdg-open",\s*[\w.\[\]]*(\.url\b|\burl\]|modelData\[)/.test(code)) act.push(f + ":" + (i + 1));
        if (/Qt\.openUrlExternally\(\s*[^"'\s]/.test(code) && ALLOWED.indexOf(f) < 0) ext.push(f + ":" + (i + 1));
      });
    }
    t.eq("rich-text links open through Strings.openLink", act.join("\n    "), "");
    t.eq("Qt.openUrlExternally only on a literal or a reviewed gate", ext.join("\n    "), "");
  },
};
