// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT JUST HAPPENED, for LagWatch to write beside a stall.
//
// A stall line on its own says the main thread was busy, not what with. The
// windows built on demand (terminus, picasso, plato, alexandria, oracle,
// ceres) time their own construction and say so here; LagWatch takes what has
// queued up each time it writes a line.
//
// `.pragma library` is the whole point: one copy for the engine, so the
// manager that marks and the LagWatch that reads see the same queue. A plain
// import is a fresh copy per importing component and the notes would go
// nowhere.
.pragma library

var notes = [];

// `label` is what was built, `t0` the Date.now() taken just before building.
// Anything quicker than 30 ms cannot be what a stall is made of and is left
// out, so opening a window does not write a line by itself.
function mark(label, t0) {
  const ms = Date.now() - t0;
  if (ms < 30) return;
  notes.push({ at: Date.now(), text: label + " " + ms + "ms" });
  if (notes.length > 50) notes.splice(0, notes.length - 50);
}

// what queued since `after` (a Date.now()), oldest first — and the queue
// emptied of everything older, read or not
function take(after) {
  const out = notes.filter((n) => n.at >= after).map((n) => n.text);
  notes = [];
  return out;
}

// A LINE OF ITS OWN, stall or not: a measurement worth reading even when
// nothing froze (plato's scroll frame pacing). LagWatch looks every second
// and writes whatever is waiting.
var lines = [];
function report(text) {
  lines.push(text);
  if (lines.length > 20) lines.splice(0, lines.length - 20);
}
function takeLines() {
  const out = lines;
  lines = [];
  return out;
}
