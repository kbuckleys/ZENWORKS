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

// ── DRIVES ───────────────────────────────────────────────────────────────
// core/health.py's numbers, read: whether a drive is fine, and the facts
// worth saying. Used by Hestia's overview and terminus' disk card alike.
// NVMe's critical-warning bits, in words
var NVME_WARN = {
  spare: "Spare blocks nearly used up", temperature: "Too hot", degraded: "Reliability degraded",
  readonly: "Gone read-only", volatile_mem: "Backup memory failed", pmr_readonly: "Memory gone read-only"
};
function kToC(k) { return k > 0 ? Math.round(k - 273.15) : null; }
// { level: good|warn|bad|unknown, words, why: [] }
function diskVerdict(d) {
  if (!d || !d.kind) return { level: "unknown", words: "No health data", why: [] };
  if (d.kind === "ata" && !d.smart) return { level: "unknown", words: "SMART is off", why: [] };
  var bad = [], warn = [];
  if (d.failing) bad.push("The drive predicts it will fail");
  (d.warnings || []).forEach(function (w) { bad.push(NVME_WARN[w] || cap(String(w).replace(/_/g, " "))); });
  if (d.spareLeft >= 0 && d.spareThresh > 0 && d.spareLeft <= d.spareThresh) bad.push("Spare blocks used up");
  if (d.usedPct >= 100) bad.push("Past its rated wear");
  else if (d.usedPct >= 90) warn.push("Nearly worn out (" + d.usedPct + "%)");
  if (d.mediaErrors > 0) warn.push(d.mediaErrors + (d.mediaErrors === 1 ? " media error" : " media errors"));
  if (d.badSectors > 0) warn.push(d.badSectors + (d.badSectors === 1 ? " bad sector" : " bad sectors"));
  if (d.attrsFailing > 0) warn.push(d.attrsFailing + " SMART " + (d.attrsFailing === 1 ? "value" : "values") + " past the limit");
  if (d.wcTempK > 0 && d.tempK >= d.wcTempK && bad.indexOf(NVME_WARN.temperature) < 0) warn.push("Running hot");
  if (bad.length) return { level: "bad", words: bad[0], why: bad.concat(warn) };
  if (warn.length) return { level: "warn", words: warn[0], why: warn };
  return { level: "good", words: "Good", why: [] };
}
function hoursWords(h) {
  if (!(h >= 0)) return "";
  var d = Math.floor(h / 24), y = Math.floor(d / 365);
  var span = y > 0 ? y + (y === 1 ? " year " : " years ") + (d % 365) + " days" : d > 0 ? d + (d === 1 ? " day" : " days") : h + " h";
  return span + " (" + String(h).replace(/\B(?=(\d{3})+(?!\d))/g, ",") + " h)";
}
// decimal, as drives are sold: 53 TB written, not 48 TiB
function driveBytes(n) {
  if (!(n >= 0)) return "";
  var u = ["B", "kB", "MB", "GB", "TB", "PB"], i = 0;
  while (n >= 1000 && i < u.length - 1) { n /= 1000; i++; }
  return (i === 0 ? n : n.toFixed(n < 10 ? 2 : 1)) + " " + u[i];
}
// one line for a list: "Good · 37 °C · 5% worn"
function diskLine(d) {
  var v = diskVerdict(d), c = kToC(d ? d.tempK : 0);
  return [v.words, c !== null ? c + " °C" : "", d && d.usedPct >= 0 ? d.usedPct + "% worn" : ""]
    .filter(function (x) { return x; }).join(" · ");
}
// [label, value, role] rows for a fact list; role "bad"/"warn" inks it
function diskHealthFacts(d) {
  if (!d) return [];
  var v = diskVerdict(d), c = kToC(d.tempK), rows = [];
  rows.push(["Health", v.why.length > 1 ? v.why.join(" · ") : v.words, v.level === "bad" ? "bad" : v.level === "warn" ? "warn" : ""]);
  if (c !== null) rows.push(["Temperature", c + " °C", d.wcTempK > 0 && d.tempK >= d.wcTempK ? "warn" : ""]);
  if (d.usedPct >= 0) rows.push(["Wear", d.usedPct + "% of its rated life" + (d.spareLeft >= 0 ? " · " + d.spareLeft + "% spare left" : ""), ""]);
  if (d.hours >= 0) rows.push(["Powered on", hoursWords(d.hours), ""]);
  if (d.written >= 0) rows.push(["Written", driveBytes(d.written), ""]);
  if (d.read >= 0) rows.push(["Read", driveBytes(d.read), ""]);
  if (d.mediaErrors >= 0) rows.push(["Media errors", String(d.mediaErrors), d.mediaErrors > 0 ? "warn" : ""]);
  if (d.badSectors >= 0) rows.push(["Bad sectors", String(d.badSectors), d.badSectors > 0 ? "warn" : ""]);
  if (d.unsafe >= 0) rows.push(["Unsafe shutdowns", String(d.unsafe), ""]);
  return rows;
}
// THE DRIVE'S OWN SELF-TEST (health.py selftest; stylus starts it): how
// the last one went, or how far the one running is — words that stand
// beside a "Self-test" label, so they do not say it again. udisks passes
// on the controller's word — ATA's and NVMe's differ — and these are the
// same few answers in ours. { running, left, words, level: good|warn|bad|"" }
var SELFTEST_WORDS = {
  success: ["The last one passed", "good"],
  aborted: ["The last one was stopped", ""],
  interrupted: ["The last one was interrupted", "warn"],
  ctrl_reset: ["The last one was cut short by a reset", "warn"],
  ns_removed: ["The last one was cut short", "warn"],
  aborted_format: ["The last one was cut short by a format", "warn"],
  aborted_unknown: ["The last one was cut short", "warn"],
  aborted_sanitize: ["The last one was cut short by a sanitize", "warn"],
  fatal: ["The last one failed", "bad"],
  fatal_error: ["The last one failed", "bad"],
  unknown_seg_fail: ["The last one failed", "bad"],
  known_seg_fail: ["The last one failed", "bad"],
  error_unknown: ["The last one failed", "bad"],
  error_electrical: ["The last one failed: electrical", "bad"],
  error_servo: ["The last one failed: the heads", "bad"],
  error_read: ["The last one failed: reading", "bad"],
  error_handling: ["The last one failed: handling", "bad"]
};
function selftestOf(d) {
  var st = d ? String(d.selftest || "") : "";
  var left = d && d.selftestLeft >= 0 ? d.selftestLeft : -1;
  if (st === "inprogress" || (left > 0 && left < 100 && st === ""))
    return { running: true, left: left, words: "Running" + (left >= 0 ? " \u00b7 " + (100 - left) + "% done" : ""), level: "" };
  var w = SELFTEST_WORDS[st];
  if (!w) return { running: false, left: -1, words: st ? cap(st.replace(/_/g, " ")) : "Not run yet", level: "" };
  return { running: false, left: -1, words: w[0], level: w[1] };
}
// the drive a device (a partition or the disk itself) is on
function driveOf(drives, dev) {
  return (drives || []).find(function (d) { return (d.devs || []).indexOf(dev) >= 0; }) || null;
}
function parseDrives(text) {
  try { var j = JSON.parse(String(text || "")); return Array.isArray(j) ? j : []; } catch (e) { return []; }
}
function parseFirmware(text) {
  try {
    var j = JSON.parse(String(text || ""));
    return { known: true, installed: !!j.installed, devices: Array.isArray(j.devices) ? j.devices : [] };
  } catch (e) { return { known: false, installed: false, devices: [] }; }
}
