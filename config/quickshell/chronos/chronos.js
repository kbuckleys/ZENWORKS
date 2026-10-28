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
// ── AN EVENT IN PLAIN WORDS (Quick Access, 2026-10-28) ─────────────────
// "Lunch with Sam tomorrow 1pm @ Luigi's", "Dentist fri 14:30-15:15",
// "Standup every day 9:15 for 15 min" (no: repeats are the sheet's),
// "Holiday nov 3", "Call mum in 2 days at 6pm for 30 min", "Gym today".
// The day: today, tomorrow, a weekday (the next one; "next" a week on),
// "in N days|weeks", a month and day either way round, an ISO date — else
// `iso`, the day in view. The time: "9", "9am", "14:30", "2-4pm",
// "14:00-15:30", with "at"/"from…to" or bare; "for 90 min|2h" a length;
// none is all day. " @ place" is where. What is left is the title.
// → { allDay, start, end, title, location, iso } or { error }
const WEEKDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
const MONTH_WORDS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
function parseNatural(text, iso, now) {
  let s = " " + String(text || "").trim() + " ";
  if (s.trim() === "") return { error: "Type what it is" };
  const base = dateOf(iso) || new Date();
  const today = now ? new Date(now.getFullYear(), now.getMonth(), now.getDate()) : (() => { const n = new Date(); return new Date(n.getFullYear(), n.getMonth(), n.getDate()); })();
  let location = "";
  const at = s.lastIndexOf(" @ ");
  if (at >= 0) { location = s.slice(at + 3).trim(); s = s.slice(0, at) + " "; }
  let day = null;
  const take = (re, fn) => { const m = re.exec(s); if (!m) return false; const r = fn(m); if (r === false) return false; s = s.slice(0, m.index) + " " + s.slice(m.index + m[0].length); return true; };
  // the day
  take(/\s(\d{4})-(\d{1,2})-(\d{1,2})(?=\s)/, (m) => { day = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])); })
  || take(/\s(?:on\s+)?today(?=\s)/i, () => { day = today; })
  || take(/\s(?:on\s+)?(?:tomorrow|tmrw|tmr)(?=\s)/i, () => { day = addDays(today, 1); })
  || take(/\sin\s+(\d{1,3})\s*(days?|d|weeks?|w)(?=\s)/i, (m) => { day = addDays(today, Number(m[1]) * (/^w/i.test(m[2]) ? 7 : 1)); })
  || take(/\s(?:on\s+)?(next\s+)?(sun|mon|tue|wed|thu|fri|sat)[a-z]*(?=\s)/i, (m) => {
       const want = WEEKDAYS.findIndex((w) => w.startsWith(m[2].toLowerCase()));
       let d = (want - today.getDay() + 7) % 7;
       if (d === 0) d = 7;
       if (m[1]) d += d < 7 ? 7 : 0;
       day = addDays(today, d);
     })
  || take(/\s(?:on\s+)?([a-z]{3})[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?=\s)/i, (m) => {
       const mo = MONTH_WORDS.indexOf(m[1].toLowerCase());
       if (mo < 0) return false;
       day = new Date(today.getFullYear(), mo, Number(m[2]));
       if (day < today) day = new Date(today.getFullYear() + 1, mo, Number(m[2]));
     })
  || take(/\s(?:on\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]{3})[a-z]*\.?(?=\s)/i, (m) => {
       const mo = MONTH_WORDS.indexOf(m[2].toLowerCase());
       if (mo < 0) return false;
       day = new Date(today.getFullYear(), mo, Number(m[1]));
       if (day < today) day = new Date(today.getFullYear() + 1, mo, Number(m[1]));
     });
  // a length
  let len = -1;
  take(/\sfor\s+(\d+(?:\.\d+)?)\s*(h|hrs?|hours?|m|mins?|minutes?)(?=\s)/i, (m) => { len = Math.round(Number(m[1]) * (/^h/i.test(m[2]) ? 60 : 1)); });
  // the time
  const clock = (h, mi, ap, apOther) => {
    let H = Number(h);
    const M = Number(mi || 0), a = (ap || apOther || "").toLowerCase();
    if (a) { if (H < 1 || H > 12) return -1; H = H % 12 + (a === "pm" ? 12 : 0); }
    return H > 23 || M > 59 ? -1 : H * 60 + M;
  };
  let t0 = -1, t1 = -1;
  const T = "(\\d{1,2})(?:[:.](\\d{2}))?\\s*(am|pm)?";
  take(new RegExp("\\s(?:at\\s+|from\\s+)?" + T + "\\s*(?:-|–|to|until|till)\\s*" + T + "(?=\\s)", "i"), (m) => {
    t0 = clock(m[1], m[2], m[3], m[6]); t1 = clock(m[4], m[5], m[6], "");
    if (t0 < 0 || t1 < 0) return false;
    if (t1 <= t0 && !m[6] && t1 + 720 > t0) t1 += 720;
  })
  || take(new RegExp("\\s(?:at|@)\\s+" + T + "(?=\\s)", "i"), (m) => { t0 = clock(m[1], m[2], m[3], ""); if (t0 < 0) return false; })
  || take(/\s(\d{1,2})[:.](\d{2})\s*(am|pm)?(?=\s)/i, (m) => { t0 = clock(m[1], m[2], m[3], ""); if (t0 < 0) return false; })
  || take(/\s(\d{1,2})\s*(am|pm)(?=\s)/i, (m) => { t0 = clock(m[1], "0", m[2], ""); if (t0 < 0) return false; });
  const allDay = /\sall[\s-]day(?=\s)/i.test(s) || t0 < 0;
  s = s.replace(/\sall[\s-]day(?=\s)/i, " ");
  const title = s.replace(/\s+/g, " ").replace(/\s+(on|at)$/i, "").trim();
  if (title === "") return { error: "Say what it is, not only when" };
  const d = isoOf(day || base);
  if (allDay) return { allDay: true, start: d, end: d, title: title, location: location, iso: d };
  if (t1 < 0) t1 = Math.min(24 * 60 - 1, t0 + (len > 0 ? len : 60));
  if (t1 <= t0) return { error: "It ends before it starts" };
  return { allDay: false, start: d + " " + hhmm(t0), end: d + " " + hhmm(t1), title: title, location: location, iso: d };
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

// ── THE CALENDAR WINDOW (2026-10-28) ────────────────────────────────────
function addDays(date, n) { return new Date(date.getFullYear(), date.getMonth(), date.getDate() + n); }
function dateOf(iso) {
  const m = /^(\d{4})-(\d\d)-(\d\d)/.exec(String(iso || ""));
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : null;
}
// the Monday a week starts on
function weekStart(date) { return addDays(date, -weekIndex(date)); }
// "HH:MM" → minutes into the day; "" → -1
function minutesOf(t) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(t || "").trim());
  return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
}
function hhmm(mins) {
  const m = Math.max(0, Math.min(24 * 60 - 1, Math.round(mins)));
  const two = (n) => (n < 10 ? "0" : "") + n;
  return two(Math.floor(m / 60)) + ":" + two(m % 60);
}
// a time typed loosely → "HH:MM", or "" when it is not one:
// "9" "930" "9:30" "21.30" "9pm" "9:30 am"
function normTime(text) {
  const s = String(text || "").trim().toLowerCase().replace(".", ":");
  const m = /^(\d{1,2})(?::?(\d{2}))?\s*(am|pm)?$/.exec(s);
  if (!m) return "";
  let h = Number(m[1]);
  const mi = Number(m[2] || 0);
  if (m[3]) { if (h < 1 || h > 12) return ""; h = h % 12 + (m[3] === "pm" ? 12 : 0); }
  return h > 23 || mi > 59 ? "" : hhmm(h * 60 + mi);
}
// a date typed: "2026-11-02" (and "2026-11-2") → ISO, or ""
function normDate(text) {
  const m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(String(text || "").trim());
  if (!m) return "";
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return d.getMonth() === Number(m[2]) - 1 ? isoOf(d) : "";
}
// The part of a timed event on day `iso`, in minutes: from its start (or
// midnight, when it began before) to its end (or midnight, when it goes on).
function spanOn(e, iso) {
  const s = e.date === iso ? Math.max(0, minutesOf(e.start)) : 0;
  let en = e.endDate && e.endDate !== iso ? 24 * 60 : minutesOf(e.end);
  if (en <= s) en = Math.min(24 * 60, s + 30);
  return { s: s, e: en };
}
// A day's timed events side by side where they overlap: each { ev, s, e,
// col, cols }, cols being how many share its cluster.
function layoutDay(events, iso) {
  const items = (events || []).filter((e) => !e.allDay)
    .map((e) => Object.assign({ ev: e, col: 0, cols: 1 }, spanOn(e, iso)))
    .sort((a, b) => a.s - b.s || b.e - a.e);
  let cluster = [], ends = [], clusterEnd = -1;
  const close = () => { for (const it of cluster) it.cols = ends.length; cluster = []; ends = []; };
  for (const it of items) {
    if (it.s >= clusterEnd) { close(); clusterEnd = -1; }
    let c = ends.findIndex((x) => x <= it.s);
    if (c < 0) { c = ends.length; ends.push(it.e); } else ends[c] = it.e;
    it.col = c;
    cluster.push(it);
    clusterEnd = Math.max(clusterEnd, it.e);
  }
  close();
  return items;
}
// what the window's head says for where it is
function rangeTitle(view, date) {
  if (view === "year") return String(date.getFullYear());
  if (view === "day") return longDay(date) + " " + date.getFullYear();
  if (view === "week") {
    const a = weekStart(date), b = addDays(a, 6);
    return a.getMonth() === b.getMonth()
      ? monthName(a.getMonth()) + " " + a.getDate() + " – " + b.getDate() + ", " + b.getFullYear()
      : monthName(a.getMonth()).slice(0, 3) + " " + a.getDate() + " – " + monthName(b.getMonth()).slice(0, 3) + " " + b.getDate() + ", " + b.getFullYear();
  }
  return monthName(date.getMonth()) + " " + date.getFullYear();
}
// the days a view lists events for: [from, to) as ISO
function rangeOf(view, date) {
  if (view === "year") return [isoDay(date.getFullYear(), 0, 1), isoDay(date.getFullYear() + 1, 0, 1)];
  if (view === "day") return [isoOf(date), isoOf(addDays(date, 1))];
  if (view === "week") { const a = weekStart(date); return [isoOf(a), isoOf(addDays(a, 7))]; }
  const g = monthGrid(date.getFullYear(), date.getMonth());
  return [isoDay(g[0].y, g[0].m, g[0].d), isoOf(addDays(new Date(g[41].y, g[41].m, g[41].d), 1))];
}
// a step back or on, by the view's own size
function stepDate(view, date, n) {
  if (view === "year") return new Date(date.getFullYear() + n, date.getMonth(), 1);
  if (view === "day") return addDays(date, n);
  if (view === "week") return addDays(date, 7 * n);
  return new Date(date.getFullYear(), date.getMonth() + n, 1);
}
// ── COLORS (2026-10-28): the stickies' own ─────────────────────────────
// Events and calendars wear Clio's seven hues (user, 2026-10-28: "like
// stickies colors, also theme-adherent"), drawn by Clio.ink in the theme's
// own inks. Stored for other calendar apps: an event's as RFC 7986's COLOR
// (a CSS name — sand is "tan"), a calendar's as vdir's hex (core/cal.py
// CAL_COLORS), read back to the hue here. [hue, label]
const COLORS = [["sand", "Sand"], ["yellow", "Yellow"], ["green", "Green"], ["cyan", "Cyan"],
                ["blue", "Blue"], ["magenta", "Magenta"], ["pink", "Pink"]];
const COLOR_HEX = { "#c8b48c": "sand", "#e8c547": "yellow", "#7fb069": "green", "#5fb3b3": "cyan",
                    "#5b8fd9": "blue", "#b07cc6": "magenta", "#e48aa5": "pink" };
// other apps' and khal's words for them
const COLOR_WORDS = { tan: "sand", brown: "sand", orange: "sand", gray: "sand", grey: "sand", white: "sand", black: "sand",
                      gold: "yellow", teal: "cyan", turquoise: "cyan", purple: "magenta", violet: "magenta",
                      red: "pink", lime: "green", navy: "blue" };
const CAL_SLOTS = ["blue", "green", "magenta", "sand", "cyan", "pink", "yellow"];
// a calendar's or an event's color (khal's word, "dark cyan", a CSS name,
// a hex) → a hue, or a hex none is near; unnamed ones take the slots in turn
function calColor(c, i) {
  const s = String(c || "").trim().toLowerCase();
  const hex = /^#[0-9a-f]{6}([0-9a-f]{2})?$/.exec(s);
  if (hex) return COLOR_HEX[s.slice(0, 7)] || s.slice(0, 7);
  const word = s.replace(/^(dark|light)\s*/, "");
  if (COLOR_WORDS[word]) return COLOR_WORDS[word];
  if (COLORS.some((x) => x[0] === word)) return word;
  return CAL_SLOTS[((i || 0) % CAL_SLOTS.length + CAL_SLOTS.length) % CAL_SLOTS.length];
}
function isColor(name) { return COLORS.some((x) => x[0] === name); }

// ── DRAGGING (2026-10-28) ───────────────────────────────────────────────
// pixels down the hours → minutes, to the quarter hour
function snapMinutes(px, hourH, step) {
  const st = step || 15;
  return Math.round(px / hourH * 60 / st) * st;
}
// what a drag did to an event: { ds, de } in minutes (days for an all-day
// one), from the days across and the minutes down; a resize moves the end
// alone and never past the start
function dragShift(ev, days, mins, resize, lenMins) {
  if (ev && ev.allDay) return { ds: resize ? 0 : days, de: days };
  if (resize) return { ds: 0, de: Math.max(15 - (lenMins || 0), mins) };
  return { ds: days * 1440 + mins, de: days * 1440 + mins };
}
// whole days from one ISO day to another
function daysBetween(a, b) {
  const x = dateOf(a), y = dateOf(b);
  return x && y ? Math.round((y.getTime() - x.getTime()) / 86400000) : 0;
}
// the steps undo keeps, and what undoes each:
//   { kind: "shift", uid, ds, de }           shifted back
//   { kind: "save", before, after }          before saved again (none: after deleted)
//   { kind: "delete", before }               saved again, under its uid
function inverse(step) {
  if (step.kind === "shift") return { kind: "shift", uid: step.uid, ds: -step.ds, de: -step.de };
  if (step.kind === "save") return step.before ? { kind: "save", before: step.after, after: step.before } : { kind: "delete", before: step.after };
  if (step.kind === "delete") return { kind: "save", before: null, after: step.before };
  return null;
}

// a new event's form, on `iso` (at `mins` into it, or all day when < 0)
function draft(iso, mins, cal) {
  if (mins < 0) return { uid: "", calendar: cal || "", title: "", allDay: true, start: iso, end: iso,
                         location: "", description: "", repeat: "", alert: null };
  const s = Math.max(0, Math.min(23 * 60, Math.round(mins / 30) * 30));
  return { uid: "", calendar: cal || "", title: "", allDay: false, start: iso + " " + hhmm(s),
           end: iso + " " + hhmm(Math.min(24 * 60 - 1, s + 60)), location: "", description: "", repeat: "", alert: 15 };
}
// Apple's title: the month (or the day) in bold, the year after it plain
// → [bold, plain]
function titleParts(view, date) {
  if (view === "year") return [String(date.getFullYear()), ""];
  if (view === "day") return [DAYS[weekIndex(date)] + ", " + monthName(date.getMonth()) + " " + date.getDate(), String(date.getFullYear())];
  if (view === "week") {
    const a = weekStart(date), b = addDays(a, 6);
    return a.getMonth() === b.getMonth() ? [monthName(a.getMonth()), String(a.getFullYear())]
      : [monthName(a.getMonth()).slice(0, 3) + " – " + monthName(b.getMonth()).slice(0, 3), String(b.getFullYear())];
  }
  return [monthName(date.getMonth()), String(date.getFullYear())];
}
// a calendar's group in the sidebar: the account its directory is under,
// or "" for one on this computer
function groupOf(cal, accounts) {
  const p = String(cal && cal.path || "");
  for (const a of accounts || []) if (p.indexOf("/vdirsyncer/calendars/" + a.name + "/") >= 0) return a.name;
  return "";
}
