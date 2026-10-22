// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE CARET, NO EXCEPTIONS (user, 2026-10-22). Every editable text field
// wears morpheus/Caret.qml — the breath stepped at 30 Hz that rests after
// 5 s (see its header for why: a caret animated at the monitor's rate
// redrew a whole full-screen surface 180 times a second). Eight fields had
// slipped through on Qt's own blinking cursor.
//
// What it catches: a TextInput, TextEdit, TextField or TextArea with no
// `cursorDelegate: Caret {`, and any cursorDelegate that is not a Caret.
// Exempt only where Qt draws no cursor at all: `readOnly: true`, or
// `cursorVisible: false`. And a caret drawn by hand: Zenon.breath read
// anywhere but Caret.qml and the few listed in NOT_A_CARET.

"use strict";

const fs = require("fs");
const path = require("path");

const SKIP_DIR = /^(oracle\/tests|oracle\/qmltests|themes|scripts|plato\/nvim)(\/|$)/;
const FIELD = /\b(TextInput|TextEdit|TextField|TextArea)\s*\{/g;

function walk(root, d, out) {
  for (const e of fs.readdirSync(path.join(root, d), { withFileTypes: true })) {
    const rel = d ? d + "/" + e.name : e.name;
    if (e.name.startsWith(".") || SKIP_DIR.test(rel)) continue;
    if (e.isDirectory()) walk(root, rel, out);
    else if (e.name.endsWith(".qml")) out.push(rel);
  }
  return out;
}

// the field's own block, braces counted, with its nested children cut out
// so a child's readOnly or cursorDelegate is not taken for the field's
function ownBlock(s, open) {
  let depth = 0, own = "";
  for (let i = open; i < s.length; i++) {
    const c = s[i];
    if (c === "{") depth++;
    else if (c === "}") { depth--; if (depth === 0) return own; }
    if (depth === 1) own += c;
  }
  return own;
}

module.exports = {
  module: "morpheus/themesync.js",
  cases: (_S, t) => {
    const root = path.resolve(__dirname, "../..");
    const bad = [];
    for (const f of walk(root, "", [])) {
      const s = fs.readFileSync(path.join(root, f), "utf8")
        .replace(/\/\/[^\n]*/g, (m) => " ".repeat(m.length));
      for (const m of s.matchAll(FIELD)) {
        const own = ownBlock(s, m.index + m[0].length - 1);
        const line = s.slice(0, m.index).split("\n").length;
        const delegate = own.match(/cursorDelegate:\s*(\w+)/);
        if (delegate && delegate[1] !== "Caret")
          bad.push(f + ":" + line + "  " + m[1] + " with cursorDelegate " + delegate[1]);
        else if (!delegate && !/readOnly:\s*true\b/.test(own) && !/cursorVisible:\s*false\b/.test(own))
          bad.push(f + ":" + line + "  " + m[1] + " without a Caret");
      }
    }
    t.eq("every editable field wears Caret", bad.join("\n    "), "");

    // A caret drawn by hand (plato's editor and command line, ceres'
    // password field were) breathes on Zenon.breath. Read only by Caret and
    // by what is NOT a caret and breathes only for a moment, listed here
    // with why.
    const NOT_A_CARET = {
      "terminus/SideRow.qml": "a sidebar row's outline while a drop is held over it",
      "clio/ClioShelf.qml": "a shelf row's outline while a drop is held over it",
      "metis/MetisPopup.qml": "the rates dot while the rates refresh",
    };
    const own = [];
    for (const f of walk(root, "", [])) {
      if (f === "morpheus/Caret.qml" || NOT_A_CARET[f]) continue;
      fs.readFileSync(path.join(root, f), "utf8").split("\n").forEach((line, i) => {
        if (!/^\s*\/\//.test(line) && /\bZenon\.breath\b(?!Ease)/.test(line))
          own.push(f + ":" + (i + 1) + "  " + line.trim().slice(0, 90));
      });
    }
    t.eq("no caret breathes but Caret", own.join("\n    "), "");
  }
};
