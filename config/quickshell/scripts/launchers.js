#!/usr/bin/env node
// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SUITE'S LAUNCHERS, SHIPPED — every app's .desktop entry, made from the
// one place it is described: the `Desktop.launcher("id", { … })` in its
// manager. The package installs them in /usr/share/applications (pacman
// owns them, so they go when Zenworks goes), each naming its program under
// /usr/share/zenworks. A working copy needs no entries of its own: every
// program here only says `qs ipc call …`, which QS_CONFIG_PATH (bin/zen)
// sends to whichever shell is running.
//
//   node scripts/launchers.js --write DIR   (re)write DIR/<id>.desktop
//   node scripts/launchers.js --check DIR   say what differs; status 1 if any
//
// oracle/tests/launchers.js runs the check against the working copy's
// share/applications, so a field changed in a manager and not here fails.

"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const ROOT = path.resolve(__dirname, "..");
// where the package puts the shell
const PREFIX = "/usr/share/zenworks/quickshell";

// An Exec value for a program by its absolute path: quoted per the
// desktop-entry spec only when it has to be, then the field code. The same
// rule as morpheus/Desktop.qml's execLine, which the managers call.
function execLine(p, code) {
  const q = /[\s"'\\$`]/.test(p) ? "\"" + p.replace(/(["`$\\])/g, "\\$1") + "\"" : p;
  return code ? q + " " + code : q;
}

// `launcher: Desktop.launcher(` … `)` in a manager's text (the property, not
// a comment naming it): its argument list, found by counting brackets past
// strings and comments
function callsIn(text) {
  const out = [];
  const key = "launcher: Desktop.launcher(";
  let at = text.indexOf(key);
  while (at >= 0) {
    let i = at + key.length, depth = 1, q = "";
    for (; i < text.length && depth > 0; i++) {
      const c = text[i];
      if (q) { if (c === "\\") i++; else if (c === q) q = ""; continue; }
      if (c === "\"" || c === "'" || c === "`") q = c;
      else if (c === "/" && text[i + 1] === "/") i = text.indexOf("\n", i);
      else if (c === "(" || c === "[" || c === "{") depth++;
      else if (c === ")" || c === "]" || c === "}") depth--;
    }
    out.push(text.slice(at + key.length, i - 1));
    at = text.indexOf(key, i);
  }
  return out;
}

// a manager's `readonly property var NAME: [ … ]` lists, for the fields that
// name one (MimeType: mgr.mimes)
function listsIn(text) {
  const out = {};
  const re = /property var (\w+):\s*(\[[\s\S]*?\])\s*\n/g;
  let m;
  while ((m = re.exec(text))) {
    try { out[m[1]] = vm.runInNewContext(m[2]); } catch (e) {}
  }
  return out;
}

// every launcher the managers describe: [{ id, file, fields }]
function launchers(root) {
  const found = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (e.name.startsWith(".") || e.name === "node_modules") continue;
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith(".qml") && !p.includes("/oracle/tests/")) {
        const text = fs.readFileSync(p, "utf8");
        const calls = callsIn(text);
        if (calls.length === 0) continue;
        const lists = listsIn(text);
        for (const args of calls) {
          const ctx = {
            Desktop: { execLine, launcher: (id, fields) => ({ id, fields }) },
            Quickshell: { shellDir: PREFIX },
            mgr: lists, root: lists, viewer: lists,
          };
          const r = vm.runInNewContext("Desktop.launcher(" + args + ")", ctx);
          found.push({ id: r.id, file: path.relative(root, p), fields: r.fields });
        }
      }
    }
  };
  walk(root);
  return found.sort((a, b) => a.id < b.id ? -1 : 1);
}

// the entry as a file: fields in the order written, lists joined with ";"
// and given the trailing one the spec wants
function render(fields) {
  const lines = ["[Desktop Entry]"];
  for (const k in fields) {
    const v = fields[k];
    lines.push(k + "=" + (Array.isArray(v) ? v.join(";") + ";" : String(v)));
  }
  return lines.join("\n") + "\n";
}

function main() {
  const [mode, dir] = process.argv.slice(2);
  if (!["--write", "--check"].includes(mode) || !dir) {
    console.error("usage: launchers.js --write DIR | --check DIR");
    process.exit(2);
  }
  const all = launchers(ROOT);
  let bad = 0;
  const want = new Set();
  for (const l of all) {
    const f = path.join(dir, l.id + ".desktop");
    want.add(l.id + ".desktop");
    const text = render(l.fields);
    if (mode === "--write") { fs.mkdirSync(dir, { recursive: true }); fs.writeFileSync(f, text); continue; }
    const have = fs.existsSync(f) ? fs.readFileSync(f, "utf8") : null;
    if (have !== text) { console.log((have === null ? "missing  " : "differs  ") + l.id + ".desktop  (" + l.file + ")"); bad++; }
  }
  if (fs.existsSync(dir))
    for (const f of fs.readdirSync(dir))
      if (f.endsWith(".desktop") && !want.has(f)) {
        if (mode === "--write") fs.unlinkSync(path.join(dir, f));
        else { console.log("extra    " + f + "  (no manager describes it)"); bad++; }
      }
  if (mode === "--write") console.log("wrote " + all.length + " launchers to " + dir);
  process.exit(bad ? 1 : 0);
}

module.exports = { launchers, render, execLine, callsIn, PREFIX };
if (require.main === module) main();
