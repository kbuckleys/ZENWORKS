// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

.pragma library
// ONE COPY FOR THE WHOLE SHELL (see morpheus/icons.js).
//
// HESTIA'S PURE HALF: what a unit's state means and how it is drawn, which
// of the list to show, what can be done to a unit and the systemctl line
// that does it, the journal's lines read, and the words for sizes, times
// and durations — checked by oracle/tests/hestia.js.

var SECTIONS = [
  { id: "overview", label: "Overview", glyph: "\u{F0A07}" },
  { id: "system", label: "Services", glyph: "\u{F08D6}" },
  { id: "user", label: "My services", glyph: "\u{F1370}" },
  { id: "timers", label: "Timers", glyph: "\u{F00F0}" },
  { id: "journal", label: "Journal", glyph: "\u{F09EE}" }
];
// the list's chips
var SHOWS = [
  { id: "running", label: "Running" },
  { id: "failed", label: "Failed" },
  { id: "enabled", label: "At boot" },
  { id: "all", label: "All" }
];

// ── A UNIT'S STATE ───────────────────────────────────────────────────────
// "ok" running · "busy" starting or stopping · "bad" failed · "off" not
// running · "done" ran and exited (a oneshot) — the window inks each
function stateRole(u) {
  if (!u) return "off";
  if (u.active === "failed") return "bad";
  if (u.active === "activating" || u.active === "deactivating" || u.active === "reloading") return "busy";
  if (u.active === "active") return u.sub === "exited" ? "done" : "ok";
  return "off";
}
function stateWords(u) {
  if (!u) return "";
  var r = stateRole(u);
  if (r === "bad") return "Failed";
  if (r === "busy") return u.active.charAt(0).toUpperCase() + u.active.slice(1) + "…";
  if (r === "done") return "Done";
  if (r === "ok") return u.sub === "running" ? "Running" : (u.sub ? cap(u.sub) : "Active");
  return "Stopped";
}
// whether it starts at boot, in words
function bootWords(file) {
  return {
    enabled: "At boot", "enabled-runtime": "At boot (until reboot)", disabled: "Not at boot",
    static: "Started by others", indirect: "Started by others", masked: "Masked",
    generated: "Generated", alias: "Alias", transient: "Transient", linked: "Linked"
  }[file] || (file ? cap(file) : "");
}
function cap(s) { s = String(s || ""); return s.charAt(0).toUpperCase() + s.slice(1); }

// restarted this often, it is crash-looping: worth saying on the overview
var LOOPING = 20;
function looping(u) { return !!u && (u.restarts || 0) >= LOOPING; }

// ── WHICH OF THE LIST ────────────────────────────────────────────────────
function shows(u, chip) {
  if (chip === "running") return u.active === "active" || u.active === "activating" || u.active === "reloading";
  if (chip === "failed") return u.active === "failed";
  if (chip === "enabled") return u.file === "enabled" || u.file === "enabled-runtime";
  return true;
}
function filterUnits(list, query, chip) {
  var q = String(query || "").trim().toLowerCase();
  return (list || []).filter(function (u) {
    if (!shows(u, chip)) return false;
    if (q === "") return true;
    return (u.unit + " " + (u.desc || "")).toLowerCase().indexOf(q) >= 0;
  });
}
// failed first, then the rest by name — what wants looking at, on top
function sortUnits(list) {
  return (list || []).slice().sort(function (a, b) {
    var fa = a.active === "failed" ? 0 : 1, fb = b.active === "failed" ? 0 : 1;
    if (fa !== fb) return fa - fb;
    return a.unit.localeCompare(b.unit);
  });
}
function counts(list) {
  var c = { running: 0, failed: 0, enabled: 0, all: 0, looping: 0 };
  (list || []).forEach(function (u) {
    c.all++;
    if (shows(u, "running")) c.running++;
    if (u.active === "failed") c.failed++;
    if (shows(u, "enabled")) c.enabled++;
    if (looping(u)) c.looping++;
  });
  return c;
}
function shortName(unit) { return String(unit || "").replace(/\.service$/, ""); }

// ── WHAT CAN BE DONE TO IT ───────────────────────────────────────────────
// [{ verb, label, ink }] for the detail pane's buttons
function actions(u) {
  if (!u) return [];
  var out = [];
  var on = u.active === "active" || u.active === "activating" || u.active === "reloading";
  if (u.file === "masked") return [{ verb: "unmask", label: "Unmask", ink: "yellow" }];
  if (on) {
    out.push({ verb: "stop", label: "Stop", ink: "red" });
    out.push({ verb: "restart", label: "Restart", ink: "cyan" });
  } else {
    out.push({ verb: "start", label: "Start", ink: "green" });
  }
  if (u.file === "enabled") out.push({ verb: "disable", label: "Don't start at boot", ink: "muted" });
  else if (u.file === "disabled") out.push({ verb: "enable", label: "Start at boot", ink: "muted" });
  if (u.active === "failed") out.push({ verb: "reset-failed", label: "Clear failure", ink: "muted" });
  return out;
}
// the systemctl line for it: system units through polkit (its agent asks
// for the password), user units as you
function actionArgs(scope, verb, unit) {
  var base = scope === "user" ? ["systemctl", "--user"] : ["systemctl"];
  if (verb === "enable" || verb === "disable") return base.concat([verb, "--now", unit]);
  return base.concat([verb, unit]);
}
function verbWords(verb, unit) {
  var n = shortName(unit);
  return {
    start: "Started " + n, stop: "Stopped " + n, restart: "Restarted " + n,
    enable: n + " starts at boot now", disable: n + " no longer starts at boot",
    "reset-failed": "Cleared " + n + "'s failure", unmask: "Unmasked " + n
  }[verb] || n;
}

// ── THE JOURNAL ──────────────────────────────────────────────────────────
// journalctl -o json's line (one object) → the row the window draws
function journalRow(j) {
  if (!j || typeof j !== "object") return null;
  var msg = j.MESSAGE;
  if (Array.isArray(msg)) {
    try { msg = String.fromCharCode.apply(null, msg); } catch (e) { msg = ""; }
  }
  // a terminal's colour codes, written into the journal by some services
  msg = String(msg || "").replace(/\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07/g, "");
  var t = Math.floor(Number(j.__REALTIME_TIMESTAMP || 0) / 1000);
  var p = Number(j.PRIORITY);
  return {
    t: t, prio: isNaN(p) ? 6 : p,
    ident: j.SYSLOG_IDENTIFIER || j._COMM || "",
    unit: j._SYSTEMD_UNIT || j._SYSTEMD_USER_UNIT || j.UNIT || "",
    pid: j._PID || "", msg: String(msg || "").replace(/\s+$/, "")
  };
}
function parseJournalLine(line) {
  try { return journalRow(JSON.parse(line)); } catch (e) { return null; }
}
// 0 emerg … 3 err → "bad"; 4 warning → "warn"; 5 notice → "note"; the rest plain
function prioRole(p) { return p <= 3 ? "bad" : p === 4 ? "warn" : p === 5 ? "note" : "plain"; }
var PRIOS = [
  { id: "", label: "Everything" },
  { id: "5", label: "Notices" },
  { id: "4", label: "Warnings" },
  { id: "3", label: "Errors" }
];
var BOOTS = [
  { id: "0", label: "This boot" },
  { id: "-1", label: "The boot before" },
  { id: "", label: "All boots" }
];
// the window's filters → hestia.py logs' arguments (and journalctl -f's,
// for following: `follow` gives journalctl's own instead)
function logArgs(f, follow) {
  f = f || {};
  if (follow) {
    var a = ["journalctl", "-f", "-o", "json", "-n", "0", "--no-pager"];
    if (f.user) a.push("--user");
    if (f.unit) a = a.concat([f.user ? "--user-unit" : "--unit", f.unit]);
    if (f.prio) a = a.concat(["-p", f.prio]);
    if (f.grep) a = a.concat(["--grep", f.grep, "--case-sensitive=false"]);
    return a;
  }
  var b = [];
  if (f.user) b.push("--user");
  if (f.unit) b = b.concat(["--unit", f.unit]);
  if (f.prio) b = b.concat(["--prio", f.prio]);
  if (f.boot !== undefined && f.boot !== "") b = b.concat(["--boot", f.boot]);
  if (f.grep) b = b.concat(["--grep", f.grep]);
  b = b.concat(["-n", String(f.n || 400)]);
  return b;
}
// keep the newest `max` rows
function capRows(rows, max) {
  var m = max || 2000;
  return rows.length > m ? rows.slice(rows.length - m) : rows;
}

// ── WORDS FOR NUMBERS ────────────────────────────────────────────────────
function bytes(n) {
  var v = Number(n);
  if (!(v >= 0)) return "";
  var u = ["B", "KB", "MB", "GB", "TB"], i = 0;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return (i === 0 ? String(Math.round(v)) : v >= 100 ? v.toFixed(0) : v.toFixed(1)) + " " + u[i];
}
// CPU time, nanoseconds → "1.2 s", "4 min 10 s"
function cpuTime(ns) {
  var s = Number(ns) / 1e9;
  if (!(s >= 0)) return "";
  if (s < 1) return Math.round(s * 1000) + " ms";
  if (s < 60) return s.toFixed(1) + " s";
  var m = Math.floor(s / 60);
  if (m < 60) return m + " min " + Math.round(s % 60) + " s";
  return Math.floor(m / 60) + " h " + (m % 60) + " min";
}
// "in 4 h", "2 days ago", from microseconds since the epoch
function relUs(us, nowMs) {
  if (!us) return "";
  var d = (Number(us) / 1000 - (nowMs || Date.now())) / 1000;
  var a = Math.abs(d), w;
  if (a < 60) w = Math.round(a) + " s";
  else if (a < 3600) w = Math.round(a / 60) + " min";
  else if (a < 86400) w = Math.round(a / 3600) + " h";
  else w = Math.round(a / 86400) + (Math.round(a / 86400) === 1 ? " day" : " days");
  return d >= 0 ? "in " + w : w + " ago";
}
// the journal's clock: "03:02:30", with the day when it is not today
function clock(ms, nowMs) {
  var d = new Date(ms), n = new Date(nowMs || Date.now());
  var two = function (x) { return (x < 10 ? "0" : "") + x; };
  var time = two(d.getHours()) + ":" + two(d.getMinutes()) + ":" + two(d.getSeconds());
  if (d.toDateString() === n.toDateString()) return time;
  return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate()) + " " + time;
}
