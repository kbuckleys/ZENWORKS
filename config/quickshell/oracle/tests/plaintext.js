// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// OUTSIDE WORDS ARE PLAIN TEXT (audit, 2026-10-28). A Text left in its
// default format guesses at markup, and an <img src=http…> in a window
// title, a notification, a file name or a forge's comment is then FETCHED
// (measured offscreen: AutoText and StyledText both asked a local server
// for it) — a tracking pixel, and Qt's HTTP/2 crash path (nohttp2.js).
// What it catches: a Text or Label with no textFormat whose text is bound
// to something that is not a literal and names outside data (a title, a
// name, a path…). Plain: `textFormat: Text.PlainText`. Markup meant: say
// StyledText and escape the outside parts (Strings.escapeHtml).

"use strict";

const fs = require("fs");
const path = require("path");

const SKIP_DIR = /^(oracle\/tests|oracle\/qmltests|themes|plato\/nvim)(\/|$)/;
const SRC = /\b(title|summary|body|appName|artist|album|track|location|description|message|subject|label|name|path|text|preview|line|comment|author|desc|words|detail|content|snippet)\b/i;

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
      const lines = fs.readFileSync(path.join(root, f), "utf8").split("\n");
      for (let i = 0; i < lines.length; ++i) {
        const m = /^(\s*)(Text|Label)\s*\{\s*$/.exec(lines[i]);
        if (!m) continue;
        const close = new RegExp("^\\s{" + m[1].length + "}\\}");
        let j = i + 1;
        const block = [];
        while (j < lines.length && !close.test(lines[j])) block.push(lines[j++]);
        const b = block.join("\n");
        const tx = /^\s*text:\s*(.+)$/m.exec(b);
        if (tx && !/textFormat/.test(b) && !/^\s*"[^"]*"\s*$/.test(tx[1]) && SRC.test(tx[1]))
          bad.push(f + ":" + (i + 1) + "  " + tx[1].trim().slice(0, 70));
        i = j;
      }
    }
    t.eq("outside words in a Text say their format (Text.PlainText, or StyledText escaped)", bad.join("\n    "), "");
  },
};
