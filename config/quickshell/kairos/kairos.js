// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// KAIROS — screen time, the arithmetic. No QML in here: oracle/tests/kairos.js
// runs it under node.
//
// A month is one file, { v: 1, days: { "2026-10-21": DAY } }, and a day is
//   { apps: { key: seconds }, hours: [24 × seconds] }
// where a key is what the window was: its class, lower case, or for one of
// this shell's own windows (class org.quickshell) the app its title names
// ("hestia", "terminus-picker" → "terminus", "picasso-view" → "picasso").

.pragma library

const QS_CLASS = "org.quickshell";

// this shell's own windows, by the first word of their titles, and what each
// is called where its UI name is not its id
const OWN = ["alexandria", "argus", "calypso", "ceres", "clio", "delphi", "hermes", "hestia",
  "hygieia", "kairos", "minerva", "oracle", "picasso", "plato", "terminus"];
const OWN_NAMES = { hermes: "Control Hub", hestia: "System Journal", hygieia: "Tidy", kairos: "Screen Time",
  oracle: "Settings", zenworks: "Zenworks" };

function pad2(n) { return (n < 10 ? "0" : "") + n; }
function dayKey(d) { return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()); }
function monthKey(d) { return d.getFullYear() + "-" + pad2(d.getMonth() + 1); }
function dateOf(key) {
  const m = /^(\d{4})-(\d\d)-(\d\d)$/.exec(String(key || ""));
  return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null;
}
function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n); }

// what a focused window counts as; "" for none (no window, the desktop)
// one of this shell's own (named by kairos, not looked up in .desktop files)
function isOwn(key) { return key === "zenworks" || OWN.indexOf(key) >= 0; }

function appKey(cls, title, ownIds) {
  ownIds = ownIds || OWN;
  const c = String(cls || "").trim().toLowerCase();
  if (c === "") return "";
  if (c === QS_CLASS) {
    const t = String(title || "").trim().toLowerCase().split(/[\s-]/)[0] || "";
    return ownIds && ownIds.indexOf(t) >= 0 ? t : "zenworks";
  }
  return c;
}

function emptyMonth() { return { v: 1, days: {} }; }
function emptyDay() { return { apps: {}, hours: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] }; }

// a month file's text, read forgivingly: anything broken is an empty month
function parseMonth(text) {
  try {
    const j = JSON.parse(text);
    if (j && typeof j === "object" && j.days && typeof j.days === "object") return j;
  } catch (e) {}
  return emptyMonth();
}

// `secs` of `key` ending at `at` (a Date), split across the hours (and the
// midnight) it spans; returns the months touched, by month key, so the
// caller knows what to write. `months` is { "2026-10": MONTH }.
function addTime(months, key, secs, at) {
  const touched = {};
  if (!key || !(secs > 0)) return touched;
  let end = at.getTime();
  let left = secs * 1000;
  while (left > 0) {
    const e = new Date(end);
    const hourStart = new Date(e.getFullYear(), e.getMonth(), e.getDate(), e.getHours()).getTime();
    // an `end` exactly on the hour belongs to the hour before
    const from = end === hourStart ? hourStart - 3600000 : hourStart;
    const take = Math.min(left, end - from);
    const d = new Date(end - 1);
    const mk = monthKey(d);
    const dk = dayKey(d);
    const m = months[mk] || (months[mk] = emptyMonth());
    const day = m.days[dk] || (m.days[dk] = emptyDay());
    const s = take / 1000;
    day.apps[key] = Math.round(((day.apps[key] || 0) + s) * 10) / 10;
    day.hours[d.getHours()] = Math.round((day.hours[d.getHours()] + s) * 10) / 10;
    touched[mk] = true;
    left -= take;
    end -= take;
  }
  return touched;
}

function dayOf(months, key) {
  const d = dateOf(key);
  if (!d) return null;
  const m = months[monthKey(d)];
  return m && m.days[key] ? m.days[key] : null;
}
function total(day) {
  if (!day) return 0;
  let n = 0;
  for (const k in day.apps) n += day.apps[k];
  return n;
}

// the days `from` to `to` (Dates) summed into one day
function sumDays(months, from, to) {
  const out = emptyDay();
  for (let d = from; d.getTime() <= to.getTime(); d = addDays(d, 1)) {
    const day = dayOf(months, dayKey(d));
    if (!day) continue;
    for (const k in day.apps) out.apps[k] = (out.apps[k] || 0) + day.apps[k];
    for (let h = 0; h < 24; ++h) out.hours[h] += day.hours[h] || 0;
  }
  return out;
}

// the seven days ending on `end`: [{ key, date, total }]
function week(months, end) {
  const out = [];
  for (let i = 6; i >= 0; --i) {
    const d = addDays(end, -i);
    const k = dayKey(d);
    out.push({ key: k, date: d, total: total(dayOf(months, k)) });
  }
  return out;
}

// most used first: [{ key, secs, share }], share of the biggest (0..1)
function topApps(day, n) {
  if (!day) return [];
  const rows = Object.keys(day.apps).map((k) => ({ key: k, secs: day.apps[k] }))
    .filter((r) => r.secs >= 1)
    .sort((a, b) => b.secs - a.secs || (a.key < b.key ? -1 : 1));
  const top = rows.length ? rows[0].secs : 1;
  for (const r of rows) r.share = r.secs / top;
  return n > 0 ? rows.slice(0, n) : rows;
}

// "2h 05m", "14m", "45s", "0m"
function fmt(secs) {
  const s = Math.max(0, Math.round(secs || 0));
  if (s < 60) return s > 0 ? s + "s" : "0m";
  const m = Math.floor(s / 60);
  if (m < 60) return m + "m";
  return Math.floor(m / 60) + "h " + pad2(m % 60) + "m";
}

// ── THE LAST FEW HOURS, TICK BY TICK ──
// For a timer's summary: [{ at (ms), key, secs }], kept for `keepMs`.
function pushTick(ticks, at, key, secs, keepMs) {
  const out = ticks.filter((t) => at - t.at <= keepMs);
  if (key && secs > 0) out.push({ at: at, key: key, secs: secs });
  return out;
}
// what the time since `since` (ms) went to, most first: [{ key, secs }]
function since(ticks, sinceMs) {
  const by = {};
  for (const t of ticks) if (t.at > sinceMs) by[t.key] = (by[t.key] || 0) + t.secs;
  return Object.keys(by).map((k) => ({ key: k, secs: by[k] })).sort((a, b) => b.secs - a.secs);
}
// "Plato 14m, kitty 8m, Terminus 2m" — the three biggest, a minute or more
function summaryLine(rows, nameOf) {
  return rows.filter((r) => r.secs >= 60).slice(0, 3)
    .map((r) => (nameOf ? nameOf(r.key) : r.key) + " " + fmt(r.secs)).join(", ");
}

// a key, as a person would call it, when nothing better (a .desktop Name)
// is known: "org.gnome.Nautilus" → "Nautilus", "brave-browser" → "Brave browser"
function prettyKey(key) {
  let k = String(key || "");
  if (OWN_NAMES[k]) return OWN_NAMES[k];
  if (/^[a-z0-9-]+(\.[a-z0-9-]+){2,}$/i.test(k)) k = k.split(".").pop();
  k = k.replace(/[-_]+/g, " ").trim();
  return k.charAt(0).toUpperCase() + k.slice(1);
}

// ── LIMITS AND BREAKS ────────────────────────────────────────────────────
// A daily limit per app (minutes; none is 0), said once a day when it is
// reached; and a break, said after this long at the screen without one
// (idle past Oracle's screenTimeIdleMins, or the lock, is a break).
// Kept in $XDG_STATE_HOME/quickshell/kairos.json:
//   { limits: { key: minutes }, told: { day: "2026-10-22", keys: { key: true } } }
var LIMIT_CHOICES = [0, 15, 30, 60, 120, 180, 240];
function emptyLimits() { return { limits: {}, told: { day: "", keys: {} } }; }
function parseLimits(text) {
  const d = emptyLimits();
  let j;
  try { j = JSON.parse(String(text || "")); } catch (e) { return d; }
  if (!j || typeof j !== "object") return d;
  if (j.limits && typeof j.limits === "object")
    for (const k in j.limits) { const m = Math.round(Number(j.limits[k])); if (m > 0) d.limits[k] = m; }
  if (j.told && typeof j.told.day === "string" && j.told.keys && typeof j.told.keys === "object") {
    d.told.day = j.told.day;
    for (const k in j.told.keys) if (j.told.keys[k]) d.told.keys[k] = true;
  }
  return d;
}
function serializeLimits(s) { return JSON.stringify({ limits: s.limits || {}, told: s.told || { day: "", keys: {} } }, null, 2) + "\n"; }
// the limits with one changed (0 takes it off)
function withLimit(limits, key, mins) {
  const out = Object.assign({}, limits || {});
  if (mins > 0) out[key] = Math.round(mins); else delete out[key];
  return out;
}
// reached today and not yet said today
function limitDue(limits, told, day, key, secsToday) {
  const m = (limits || {})[key] || 0;
  if (m <= 0 || secsToday < m * 60) return false;
  return !(told && told.day === day && told.keys[key]);
}
// said: a new day starts the list again
function markTold(told, day, key) {
  const keys = told && told.day === day ? Object.assign({}, told.keys) : {};
  keys[key] = true;
  return { day: day, keys: keys };
}
function limitWords(mins) {
  if (!(mins > 0)) return "No limit";
  return mins % 60 === 0 ? (mins / 60) + " h" : mins > 60 ? Math.floor(mins / 60) + " h " + (mins % 60) + " min" : mins + " min";
}
// time against a limit: "1h 05m of 1 h"
function againstLimit(secs, mins) { return fmt(secs) + (mins > 0 ? " of " + limitWords(mins) : ""); }
function breakDue(stretchSecs, everyMins) { return everyMins > 0 && stretchSecs >= everyMins * 60; }
