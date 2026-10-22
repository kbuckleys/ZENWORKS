// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SHARE — the suite's one "Share" menu, the arithmetic (oracle/tests/
// share.js). Which ways a set of files can go out, and the commands that
// take them; the running is morpheus/Share.qml's. Not terminus' Send to,
// which copies or moves to another directory: this sends to something else.

.pragma library

// The ways out for these files, in menu order: [{ id, label, glyph }].
// `anyDir`: one of them is a directory, which nothing here can carry.
// `canMail`: a mail app answers mailto: — without one, xdg-email has
// nowhere to go, so Email is not offered at all (2026-10-22). Copy file
// was dropped 2026-10-22: the hosts' own Copy already does it.
function targets(count, anyDir, canMail) {
  if (!(count > 0) || anyDir) return [];
  const out = [];
  if (canMail) out.push({ id: "email", label: "Email…", glyph: "\u{F01F0}" });
  out.push({ id: "clio", label: "New note in Clio", glyph: "" });
  return out;
}

function emailArgs(paths) {
  const out = ["xdg-email"];
  for (const p of paths) out.push("--attach", p);
  return out;
}

