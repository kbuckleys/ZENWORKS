// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

.pragma library
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file evaluated all of it again (see morpheus/icons.js).

// HOWLER's pure half — what a notification is worth keeping, and what has to
// be thrown away before it is written down. No QML in here; Howler.qml runs
// the server and the panels draw it.

// ── WHAT CANNOT SURVIVE A RESTART ─────────────────────────────────────────
// An image reference is only worth storing if it will still resolve in a
// session that has never met the process which sent it.
//
// A quickshell provider handle is the clearest case: `image://qsimage/13/1`
// is a token for ONE running instance, so the process that could answer it is
// the process that has just exited. It is the least durable thing a
// notification can carry, not an edge case.
//
// A path is volatile for a different reason and the same outcome: an app
// writes its icon to a temporary file, the file goes when the app does, and
// what is left in the history is a row with a dead reference — a failure that
// happens INVISIBLY and LATE, in a warning that names a number rather than
// the notification it came from.
//
// A bare themed name is neither. It is a lookup that works in any session,
// and it is what a cleaned row falls back to.
function localImage(src) {
  const s = String(src === undefined || src === null ? "" : src);
  if (s === "") return false;
  if (s.indexOf("image://") === 0) return true;   // any provider handle
  if (s.indexOf("file://") === 0) return true;    // a url to a path
  if (s.charAt(0) === "/") return true;           // a path
  return false;
}

// One row, cleaned. `image` is the only field inspected — `appIcon` is the
// application's own icon and is as stable as the application is, so a path
// there is left exactly as it came.
function keepable(row) {
  const out = {};
  for (const k in row) if (Object.prototype.hasOwnProperty.call(row, k))
    out[k] = row[k];
  if (localImage(out.image)) out.image = "";
  return out;
}

// WHAT A CAPTURE ROW IS DRAWN AS: its picture, by path. Not `image` — a
// capture's image is a handle into the toast that sent it — but the file the
// capture wrote, which is a screenshot or a recording's frame the user kept.
// It is still a path and can still be gone (moved, deleted, a frame cleaned
// away), so this is a LIST to try in order, and the panel falls back to the
// row's icon once it runs out. A recording's frame is the copy howler kept
// first (Howler.keepFrame), then the recorder's own, which lasts until logout.
function capturePictures(row) {
  if (!row) return [];
  const k = String(row.capture || "");
  const fs = k === "shot" ? [row.captureFile]
    : k === "video" ? [row.captureKept, row.capturePicture] : [];
  const out = [];
  for (let i = 0; i < fs.length; ++i) {
    const f = String(fs[i] || "");
    if (f.charAt(0) === "/") out.push("file://" + f);
  }
  return out;
}

// A body as StyledText may show it. A notification's body is whatever the
// sender put there, and StyledText honors <img src=…> — a remote URL
// included, which is a tracking pixel fetched the moment the toast draws.
// Images come in through the notification's own image field, which the
// sender cannot point anywhere this shell does not already look.
function safeMarkup(s) {
  return String(s ?? "").replace(/<\s*img\b[^>]*>/gi, "");
}

function serialize(rows) {
  const list = Array.isArray(rows) ? rows : [];
  const out = [];
  for (let i = 0; i < list.length; ++i) out.push(keepable(list[i]));
  return JSON.stringify(out);
}

// THE SAME RULE AGAIN ON THE WAY IN, and that is not belt and braces. A
// history written before the rule existed still holds the dead handle, and a
// fix that only ran on write would need the file deleted by hand to take
// effect.
//
// Anything that is not a list of rows is no history at all: empty text,
// nonsense, or a JSON value of the wrong shape all mean the same thing, and
// the panel that reads this should never have to tell them apart.
function parse(text) {
  let j = null;
  try { j = JSON.parse(String(text || "").trim() || "[]"); }
  catch (e) { return []; }
  if (!Array.isArray(j)) return [];
  const out = [];
  for (let i = 0; i < j.length; ++i)
    if (j[i] && typeof j[i] === "object") out.push(keepable(j[i]));
  return out;
}

// ── FOCUS: QUIET WITHOUT BEING ASKED ─────────────────────────────────────
// Do not disturb is the switch you flip; focus is the two times it flips
// itself (2026-10-21): while a chronos timer counts, and in quiet hours.
// A critical notification comes through all three, as it always has.
//
// Quiet hours run from `fromH` to `toH` (whole hours, 0–23) and may cross
// midnight (22 → 7). Equal is "never": a span of no hours, not all day.
function inQuietHours(fromH, toH, minutesOfDay) {
  const f = ((Number(fromH) | 0) % 24 + 24) % 24 * 60;
  const t = ((Number(toH) | 0) % 24 + 24) % 24 * 60;
  const m = ((Number(minutesOfDay) | 0) % 1440 + 1440) % 1440;
  if (f === t) return false;
  return f < t ? m >= f && m < t : m >= f || m < t;
}
function hourWords(h) {
  const v = ((Number(h) | 0) % 24 + 24) % 24;
  return (v < 10 ? "0" : "") + v + ":00";
}
// s: { dnd, timers, timerRunning, hours, fromH, toH, minutesOfDay }
// → { quiet, why } — why in the bell's own words, "" when not quiet
function focus(s) {
  s = s || {};
  if (s.dnd) return { quiet: true, why: "Do not disturb" };
  if (s.timers && s.timerRunning) return { quiet: true, why: "Quiet while a timer runs" };
  if (s.hours && inQuietHours(s.fromH, s.toH, s.minutesOfDay))
    return { quiet: true, why: "Quiet hours, until " + hourWords(s.toH) };
  return { quiet: false, why: "" };
}
