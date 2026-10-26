// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┘┴└─┘
// https://github.com/kbuckleys/

.pragma library
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file evaluated all of it again (see morpheus/icons.js).

const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
];

const DAYS = [
  "Monday", "Tuesday", "Wednesday", "Thursday",
  "Friday", "Saturday", "Sunday"
];

// Monday-first, which is what the grid is laid out as
const DAYS_SHORT = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"];

function monthName(m) { return MONTHS[((m % 12) + 12) % 12]; }

function dayShort(i) { return DAYS_SHORT[((i % 7) + 7) % 7]; }

// Monday-first index of a Date, so it lines up with the grid's columns
function weekIndex(d) { return (d.getDay() + 6) % 7; }

// The one-line form the bar's clock hangs off: the weekday (user,
// 2026-10-26: "in clock's tooltip, show the day"), month, day, year.
function oneLine(d) {
  return DAYS[weekIndex(d)] + ", " + monthName(d.getMonth()) + " " + d.getDate() + ", " + d.getFullYear();
}

// "Saturday 29 August" — the footer under the grid. No year: the header above
// it is already showing one, and repeating it is the kind of noise that makes
// a panel feel like a form.
function longDay(d) {
  return DAYS[weekIndex(d)] + " " + d.getDate() + " " + monthName(d.getMonth());
}

// A month as 42 cells, Monday-first, six rows always — so the grid never
// changes height as you page through months, and a calendar does not resize
// under the cursor.
//
// The leading and trailing cells carry the neighboring months' real dates
// rather than blanks: they are drawn dimmed, which keeps the grid a continuous
// run of days instead of a shape with two bites out of it, and means clicking
// anywhere in the grid lands on an actual date.
//
// Each cell is { y, m, d, cur } — a full date, so a caller never has to work
// out which month a dim cell belonged to.
function monthGrid(year, month) {
  // Date normalizes an out-of-range month for us, so month 12 is January of
  // the next year and the "is this cell in the current month" test below can
  // compare against one already-resolved pair.
  const first = new Date(year, month, 1);
  const y = first.getFullYear();
  const m = first.getMonth();
  const offset = weekIndex(first);
  const cells = [];
  for (let i = 0; i < 42; ++i) {
    const d = new Date(y, m, 1 + i - offset);
    cells.push({
      y: d.getFullYear(), m: d.getMonth(), d: d.getDate(),
      cur: d.getMonth() === m && d.getFullYear() === y
    });
  }
  return cells;
}

// YYYY-MM-DD in LOCAL time. Date.toISOString() converts to UTC first, which
// shifts the date by one either side of midnight — and these keys are matched
// against open-meteo's local-timezone daily rows.
function isoDay(y, m, d) {
  const p = (n) => (n < 10 ? "0" + n : String(n));
  return y + "-" + p(m + 1) + "-" + p(d);
}

function isoOf(date) {
  return isoDay(date.getFullYear(), date.getMonth(), date.getDate());
}

// mm:ss, and hh:mm:ss once a timer is long enough to need it
function clock(secs) {
  const s = Math.max(0, Math.floor(secs));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const r = s % 60;
  const pad = (n) => (n < 10 ? "0" + n : String(n));
  return (h > 0 ? pad(h) + ":" : "") + pad(m) + ":" + pad(r);
}

// How the cells in the pomodoro band divide up. Up to three across, and rows
// balanced rather than filled — four timers come out 2+2, not 3+1, because a
// lone cell stretched across a whole row does not read as one of a set.
function bandRows(n, perRow) {
  if (n <= 0) return [];
  const rows = Math.ceil(n / perRow);
  const out = [];
  let left = n;
  for (let r = 0; r < rows; ++r) {
    const take = Math.ceil(left / (rows - r));
    out.push(take);
    left -= take;
  }
  return out;
}

function serialize(timers) {
  // running state is deliberately not persisted: a timer that was counting
  // when the shell restarted did not keep counting, and resurrecting it
  // half-elapsed would be a lie about when it will go off
  return JSON.stringify((timers || []).map((t) => ({
    label: t.label, minutes: t.minutes
  })));
}

function parse(text) {
  try {
    const v = JSON.parse(text || "[]");
    if (!Array.isArray(v)) return [];
    return v.map((t, i) => ({
      label: String(t.label ?? ("Timer " + (i + 1))),
      minutes: Math.max(1, Math.min(600, parseInt(t.minutes, 10) || 25)),
      remaining: 0,
      running: false
    }));
  } catch (e) {
    return [];
  }
}

// ── THE CALENDAR'S EVENTS (khal, 2026-10-21) ────────────────────────────
// chronos/core/cal.py hands back { uid, title, date, start, endDate, end,
// allDay, location, calendar, repeats }: dates ISO, times "HH:MM".

// iso → that day's events, all-day first, then by start
function eventsByDay(events) {
  const out = {};
  for (const e of events || []) {
    if (!e || !e.date) continue;
    (out[e.date] = out[e.date] || []).push(e);
  }
  for (const k in out) out[k].sort((a, b) => (a.allDay === b.allDay ? 0 : a.allDay ? -1 : 1)
    || String(a.start).localeCompare(String(b.start)) || String(a.title).localeCompare(String(b.title)));
  return out;
}
// "14:00 – 15:30", "All day", "From 14:00"
function eventTime(e) {
  if (!e) return "";
  if (e.allDay) return "All day";
  if (e.end && e.endDate === e.date && e.end !== e.start) return e.start + " – " + e.end;
  return e.start;
}

// One line, typed, for a new event on the chosen day:
//   "14:00 Dentist"                 an hour from 14:00
//   "14:00-15:30 Dentist @ Clinic"  that span, and where
//   "9 Standup", "9:30 Standup"     hours alone are fine
//   "Holiday"                       all day
// → { allDay, start, end, title, location } or { error }
function parseQuick(text, iso) {
  let s = String(text || "").trim();
  if (s === "") return { error: "Type what it is" };
  let location = "";
  const at = s.lastIndexOf(" @ ");
  if (at > 0) { location = s.slice(at + 3).trim(); s = s.slice(0, at).trim(); }
  const m = /^(\d{1,2})(?::(\d{2}))?(?:\s*[-–]\s*(\d{1,2})(?::(\d{2}))?)?\s+(.+)$/.exec(s);
  if (!m) return { allDay: true, start: iso, end: "", title: s, location: location };
  const h = Number(m[1]), mi = Number(m[2] || 0);
  if (h > 23 || mi > 59) return { error: "That is not a time of day" };
  const two = (n) => (n < 10 ? "0" : "") + n;
  const start = two(h) + ":" + two(mi);
  let end;
  if (m[3] !== undefined) {
    const h2 = Number(m[3]), m2 = Number(m[4] || 0);
    if (h2 > 23 || m2 > 59) return { error: "That is not a time of day" };
    if (h2 * 60 + m2 <= h * 60 + mi) return { error: "It ends before it starts" };
    end = two(h2) + ":" + two(m2);
  } else {
    const e = Math.min(23 * 60 + 59, h * 60 + mi + 60);
    end = two(Math.floor(e / 60)) + ":" + two(e % 60);
  }
  return { allDay: false, start: iso + " " + start, end: iso + " " + end, title: m[5].trim(), location: location };
}
// cal.py new's arguments for it. An all-day event ends the day it starts,
// said: given a start alone, khal read the title's first word as the end
// when it could be one ("Friday drinks" ran to Friday, titled "drinks").
function newArgs(q, cal) {
  if (q.allDay) return [cal || "", q.start, q.start, q.title, q.location || ""];
  return [cal || "", q.start, q.end, q.title, q.location || ""];
}

// ── REMINDERS ────────────────────────────────────────────────────────────
// An event's moment, as epoch ms (local time)
function eventMs(e) {
  if (!e || !e.date) return NaN;
  const p = e.date.split("-").map(Number);
  const t = e.allDay ? [9, 0] : String(e.start || "00:00").split(":").map(Number);
  return new Date(p[0], p[1] - 1, p[2], t[0] || 0, t[1] || 0).getTime();
}
// The events whose reminder falls in (lastMs, nowMs]: `lead` minutes before
// a timed one, 09:00 on the day for an all-day one. `fired` is the keys
// already said (uid + date + start), so a restart never says one twice.
function remindersDue(events, lastMs, nowMs, leadMin, fired) {
  const out = [];
  if (leadMin < 0) return out;
  for (const e of events || []) {
    const t = eventMs(e);
    if (isNaN(t)) continue;
    const at = e.allDay ? t : t - leadMin * 60000;
    const key = remindKey(e);
    if (at > lastMs && at <= nowMs && !(fired || {})[key]) out.push(e);
  }
  return out;
}
function remindKey(e) { return (e.uid || e.title) + "|" + e.date + "|" + (e.start || ""); }
function remindWords(e, nowMs) {
  if (e.allDay) return "Today";
  const mins = Math.round((eventMs(e) - nowMs) / 60000);
  return mins <= 0 ? "Now" + (e.location ? " · " + e.location : "")
    : "In " + mins + " min, at " + e.start + (e.location ? " · " + e.location : "");
}
