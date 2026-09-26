// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ORACLE's pure half. Everything here is a function of its arguments and
// nothing else — no Quickshell, no QML scope, no singleton reached sideways —
// which is what makes it testable under scripts/tests the way cynosure's and
// howler's helpers are.
//
// The division of labor with Oracle.qml is the one every layer in this shell
// uses: the QML file owns the state and the wires out to the rest of the
// shell, this file owns the arithmetic and the strings.

// A spec that HOLDS something. An action is a button and an info row is a
// readout; neither has a value to store, to default, to reset or to compare,
// and every pass over the schema has to skip both. One predicate rather than
// a growing list of `type !== "action" && type !== "info"` in six places.
function stored(spec) {
  return spec.type !== "action" && spec.type !== "info" && spec.type !== "arrange";
}

// ── numbers ───────────────────────────────────────────────────────────────

function clamp(v, lo, hi) {
  if (typeof lo === "number" && v < lo) return lo;
  if (typeof hi === "number" && v > hi) return hi;
  return v;
}

// Rounded to the spec's own STEP, not merely to the nearest whole number.
//
// Two different things go wrong without this, and the second is the one that
// actually bites. A real with step 0.05 dragged to 0.30000000000000004 is the
// slider's arithmetic showing through, and no setting is meant to carry
// fifteen decimal places into a JSON file — that much is obvious. But an INT
// with a step of 500 has the same problem in a form that looks fine: a drag
// lands on 4321, which is a perfectly good integer and a value the arrows can
// never reach, so the setting can be moved by the mouse into a place the
// keyboard cannot move it out of one press at a time.
//
// Measured FROM THE MINIMUM rather than from zero, so a spec whose minimum is
// not a multiple of its step can still reach its own minimum — which is the
// one value a slider must always be able to hit.
function quantize(spec, v) {
  const st = Number(spec.step) || (spec.type === "real" ? 0.01 : 1);
  const lo = typeof spec.min === "number" ? spec.min : 0;
  const n = Math.round((v - lo) / st) * st + lo;
  // st is a power of ten in every spec here, so this is exact
  const places = Math.max(0, String(st).indexOf(".") < 0
    ? 0 : String(st).length - String(st).indexOf(".") - 1);
  return Number(n.toFixed(places));
}

// What a value must BE before it is stored. A setting read back off disk is
// whatever the file said, and the file is hand-editable — so a string where an
// int belongs, or a number outside the slider's range, has to become the right
// thing here rather than at the point every consumer reads it.
function coerce(spec, v) {
  if (!spec) return v;
  if (spec.type === "bool") return v === true || v === "true" || v === 1;
  if (spec.type === "int") {
    const n = Number(v);
    if (!isFinite(n)) return spec.fallback;
    return Math.round(clamp(quantize(spec, n), spec.min, spec.max));
  }
  if (spec.type === "real") {
    const n = Number(v);
    if (!isFinite(n)) return spec.fallback;
    return quantize(spec, clamp(n, spec.min, spec.max));
  }
  if (spec.type === "enum") {
    // AN OPEN ENUM KEEPS WHAT IT IS GIVEN. Some of these lists are the
    // machine as it is right now — the connected monitors — and a value that
    // is not in the list is not a mistake, it is a monitor that is unplugged.
    // Rejecting it would erase the setting the moment you undocked, and put
    // the bar somewhere else when you plugged back in.
    if (spec.open) return String(v === null || v === undefined ? "" : v);
    const opts = spec.options || [];
    // by spelling too: the ipc hands every value over as a string, and a
    // numeric option (a rotation, a sync mode) would never match "2"
    for (let i = 0; i < opts.length; ++i)
      if (opts[i].value === v || String(opts[i].value) === String(v)) return opts[i].value;
    return spec.fallback;
  }
  if (spec.type === "text") return String(v === null || v === undefined ? "" : v);
  // A SET OF DEVICE NAMES, kept as one string — "auto", "" for none, or the
  // names one per line — so the file, the compare and the reset all go on
  // handling a plain value. A list here would have needed every one of them
  // taught about arrays. Names are trimmed and de-duplicated, blank lines
  // dropped, so a hand-edited file cannot hold two spellings of one choice.
  if (spec.type === "devices") {
    const s = String(v === null || v === undefined ? "" : v).trim();
    if (s === "auto") return "auto";
    const seen = ({});
    const out = [];
    for (const n of s.split("\n")) {
      const t = n.trim();
      if (t === "" || seen[t]) continue;
      seen[t] = true;
      out.push(t);
    }
    return out.join("\n");
  }
  return v;
}

// ── solaar ────────────────────────────────────────────────────────────────
// `solaar show`, read for the devices whose lighting can be dimmed. Solaar
// is not only keyboards — mice, headsets and receivers with things paired
// to them all appear — and the one question the idle timer asks is whether
// the device has BRIGHTNESS CONTROL, the feature `brightness_control` sets.
//
// A device's block starts with its name on a line of its own, at the left
// margin when it is wired, or as "  N: Name" under a receiver. Everything
// indented under it belongs to it until the next such line.
function parseSolaarShow(text) {
  const out = [];
  let cur = null;
  for (const raw of String(text || "").split("\n")) {
    const line = raw.replace(/\s+$/, "");
    if (line === "" || /^solaar version/i.test(line)) continue;
    const paired = /^\s{1,4}\d+: (\S.*)$/.exec(line);
    // A device name is a line with no colon at the left margin. A block's
    // own fields ("Device path  : …") are indented, and a receiver's paired
    // devices use the "N: Name" shape above.
    const top = /^\S/.test(line) && line.indexOf(":") < 0;
    if (paired || top) {
      cur = { name: (paired ? paired[1] : line).trim(), kind: "", dimmable: false };
      out.push(cur);
      continue;
    }
    if (!cur) continue;
    const kind = /^\s+Kind\s*:\s*(\S+)/.exec(line);
    if (kind && cur.kind === "") cur.kind = kind[1];
    if (/BRIGHTNESS CONTROL/.test(line)) cur.dimmable = true;
  }
  return out;
}

// ── the dropdown's rows ──────────────────────────────────────────────────
// "Automatic" first, then a tick per device that has lighting to dim, then
// any chosen device solaar cannot see right now — kept, and said to be
// absent, because unplugging a mouse must not quietly erase the choice —
// and a rescan last. `act` says what a click on the row does.
function deviceRows(value, found, scanning) {
  const v = String(value || "");
  const on = lightDevices(v, found);
  const rows = [{ text: "Automatic", mark: v === "auto", act: "auto" }];
  const dims = (found || []).filter((d) => d.dimmable);
  if (dims.length > 0 || on.length > 0) rows.push({ isSeparator: true });
  const listed = ({});
  for (const d of dims) {
    listed[d.name] = true;
    rows.push({ text: d.name + (d.kind ? "  \u00b7  " + d.kind : ""),
                mark: on.indexOf(d.name) >= 0, act: "toggle", name: d.name });
  }
  for (const n of on) {
    if (listed[n]) continue;
    rows.push({ text: n + "  \u00b7  not connected", mark: true, act: "toggle", name: n });
  }
  rows.push({ isSeparator: true });
  rows.push(scanning ? { text: "Looking for devices\u2026", enabled: false, act: "" }
                     : { text: "Rescan devices", act: "rescan" });
  return rows;
}

// One device ticked or unticked. From "auto" the list starts as what auto
// had resolved to, so the first click changes exactly one thing.
function toggleDevice(value, name, found) {
  const cur = lightDevices(value, found);
  const i = cur.indexOf(name);
  if (i >= 0) cur.splice(i, 1); else cur.push(name);
  return cur.join("\n");
}

// What the chip says.
function displayDevices(value, found, scanned) {
  const v = String(value || "");
  const on = lightDevices(v, found);
  if (v === "auto") {
    if (!scanned) return "Automatic";
    return on.length > 0 ? "Auto \u00b7 " + on[0] : "Auto \u00b7 none found";
  }
  if (on.length === 0) return "None";
  if (on.length === 1) return on[0];
  return on.length + " devices";
}

// What the idle timer should dim: the chosen names, or for "auto" the first
// dimmable device solaar found — which on most desks is the only one.
function lightDevices(value, found) {
  const v = String(value || "");
  if (v === "auto") {
    for (const d of (found || [])) if (d.dimmable) return [d.name];
    return [];
  }
  return v === "" ? [] : v.split("\n");
}

// One step of the keyboard's left/right, or one notch of the wheel. Enums
// wrap, because a ring of three or four options has no far end worth being
// stuck against; numbers clamp, because a slider does.
function nudge(spec, v, dir) {
  if (!spec) return v;
  if (spec.type === "bool") return !v;
  if (spec.type === "enum") {
    const opts = spec.options || [];
    if (opts.length === 0) return v;
    let i = -1;
    for (let k = 0; k < opts.length; ++k) if (opts[k].value === v) i = k;
    // NOT IN THE RING: step to its start, not one past where we pretended to
    // be. This matters for the open enums, whose list is the monitors
    // currently plugged in — from an unplugged one, the first press used to
    // skip "Automatic" entirely and land on the second option, which is the
    // one place a monitor picker must not silently put you.
    if (i < 0) return opts[0].value;
    return opts[(i + dir + opts.length) % opts.length].value;
  }
  if (spec.type === "int" || spec.type === "real") {
    const st = Number(spec.step) || 1;
    return coerce(spec, v + dir * st);
  }
  return v;
}

// Where a value sits between the slider's ends, 0..1. Guarded against a spec
// whose min and max are equal — a degenerate slider should sit at its start
// rather than divide by zero and paint NaN wide.
function fraction(spec, v) {
  const lo = Number(spec.min) || 0;
  const hi = Number(spec.max);
  if (!isFinite(hi) || hi === lo) return 0;
  return clamp((Number(v) - lo) / (hi - lo), 0, 1);
}

function fromFraction(spec, f) {
  const lo = Number(spec.min) || 0;
  const hi = Number(spec.max);
  if (!isFinite(hi)) return lo;
  return coerce(spec, lo + clamp(f, 0, 1) * (hi - lo));
}

// ── strings ───────────────────────────────────────────────────────────────

// The reading beside the slider. A duration is the one thing here nobody reads
// in milliseconds — 4000 is "4s" and 600 seconds is "10m" — so the unit is
// not simply appended, it decides the number too.
function display(spec, v) {
  if (!spec) return String(v);
  if (spec.type === "bool") return v ? "on" : "off";
  if (spec.type === "enum") {
    const opts = spec.options || [];
    for (let i = 0; i < opts.length; ++i)
      if (opts[i].value === v) return opts[i].label;
    // a monitor placed exactly, by the Arrangement view or by hand
    const at = parsePosition(v);
    if (at) return "Arranged \u00b7 " + at.x + ", " + at.y;
    return String(v);
  }
  if (spec.type === "text") return String(v) === "" ? "—" : String(v);
  // Without what solaar found, which only the panel has — see displayDevices.
  if (spec.type === "devices") return displayDevices(v, [], false);
  if (spec.unit === "ms") return v === 0 ? "never" : (v / 1000) + "s";
  if (spec.unit === "s") return duration(v);
  if (spec.unit === "min") return duration(v * 60);
  if (spec.unit === "x") return Number(v).toFixed(2) + "×";
  if (spec.unit) return v + spec.unit;
  return String(v);
}

function duration(secs) {
  const s = Math.round(Number(secs));
  if (s <= 0) return "never";
  if (s < 60) return s + "s";
  const m = Math.round(s / 60);
  if (m < 60) return m + "m";
  const h = m / 60;
  return (h === Math.round(h) ? h : h.toFixed(1)) + "h";
}

// The family a font file names, from `fc-query -f '%{family[0]}\n'`, less the
// cut: "JetBrainsMono Nerd Font Propo" and "… Mono" are both the family
// "JetBrainsMono Nerd Font", which is what the Font setting holds. Nerd Fonts'
// short spellings — "JetBrainsMono NFP", "NFM", "NF" — mean the same thing.
// The first face only: a .ttc lists one line per face, all one family.
function familyOf(text) {
  const first = String(text || "").split("\n").map((l) => l.trim())
    .filter((l) => l !== "")[0] || "";
  return first
    .replace(/\s+NF[MP]?$/, " Nerd Font")
    .replace(/\s+(Propo|Mono)$/, "")
    .trim();
}

// ── the filter ────────────────────────────────────────────────────────────
// Every word has to land somewhere, in any order — the same rule cynosure and
// zeus filter by. A setting is found by its label, by what it says it does,
// and by its key, because the key is what appears in the JSON file and is
// therefore what someone who has been editing that file will type.
function matches(spec, query) {
  const q = String(query || "").trim().toLowerCase();
  if (q === "") return true;
  // `alias` is search-only: the words someone would type that the prose has
  // no natural reason to contain. "Bar opacity" is the pill's TRANSPARENCY
  // control, but writing that noun into the help twice to make it findable
  // would be writing for the filter instead of for the reader.
  const hay = (String(spec.label || "") + " " + String(spec.help || "") + " "
    + String(spec.key || "") + " " + String(spec.section || "") + " "
    + String(spec.alias || "")).toLowerCase();
  const words = q.split(/\s+/);
  for (let i = 0; i < words.length; ++i)
    if (hay.indexOf(words[i]) < 0) return false;
  return true;
}

function filterSchema(schema, section, query) {
  const out = [];
  const q = String(query || "").trim();
  for (let i = 0; i < schema.length; ++i) {
    const s = schema[i];
    // A query searches the WHOLE panel, not the section you happen to be
    // standing in. Looking for a setting is the case where you do not know
    // which section it is filed under — that is why you are typing.
    if (q === "" && s.section !== section) continue;
    if (!matches(s, q)) continue;
    out.push(s);
  }
  return out;
}

// ── the file ──────────────────────────────────────────────────────────────

// Only what has been CHANGED is written. A file holding every default is a
// file that silently pins this shell to today's defaults — change one in the
// source later and no existing install would ever see it. Absent means
// "whatever the shell thinks", and that is the useful meaning.
function serialize(schema, values, defaults) {
  const out = {};
  for (let i = 0; i < schema.length; ++i) {
    const k = schema[i].key;
    if (!stored(schema[i])) continue;
    if (!same(values[k], defaults[k])) out[k] = values[k];
  }
  return JSON.stringify(out, null, 2) + "\n";
}

function same(a, b) {
  if (typeof a === "number" && typeof b === "number")
    return Math.abs(a - b) < 1e-9;
  return a === b;
}

// A half-written or hand-edited file must never take the shell down with it,
// and an unknown key is simply skipped rather than kept: it is either a
// setting that has been removed or a typo, and neither is worth carrying.
function parse(schema, text) {
  let j = null;
  try { j = JSON.parse(String(text || "").trim() || "{}"); } catch (e) { return {}; }
  if (!j || typeof j !== "object") return {};
  const out = {};
  for (let i = 0; i < schema.length; ++i) {
    const s = schema[i];
    if (!stored(s)) continue;
    if (!(s.key in j)) continue;
    out[s.key] = coerce(s, j[s.key]);
  }
  return out;
}

// How many settings in a section are no longer at their default — the count
// the sidebar shows, so a section that has been touched says so without being
// opened.
function changedIn(schema, values, defaults, section) {
  let n = 0;
  for (let i = 0; i < schema.length; ++i) {
    const s = schema[i];
    if (!stored(s)) continue;
    if (section && s.section !== section) continue;
    if (!same(values[s.key], defaults[s.key])) ++n;
  }
  return n;
}

// ── THE CHECKUP ───────────────────────────────────────────────────────────
// scripts/doctor.sh prints `key<TAB>value` lines; this turns them into the
// Health section's rows, each a short line and a level: "ok" reads dim like
// any fact, "warn" yellow, "bad" red. `baselineKb` is the resident size a
// clean restart settles at — see the perf baseline — so memory reads as a
// drift from normal rather than as a raw number nobody remembers.
function readCheckup(text, baselineKb) {
  const f = {};
  for (const line of String(text || "").split("\n")) {
    const i = line.indexOf("\t");
    if (i > 0) f[line.slice(0, i)] = line.slice(i + 1).trim();
  }
  const list = (k) => (f[k] || "").split(",").filter((x) => x !== "");
  const counted = (names) => {
    const n = {};
    for (const x of names) n[x] = (n[x] || 0) + 1;
    return Object.keys(n).sort().map((x) => n[x] > 1 ? x + " ×" + n[x] : x).join(", ");
  };
  const rows = {};

  const failing = list("testfail");
  rows.tests = !f.tests ? { text: "did not run", level: "bad" }
    : failing.length ? { text: f.tests + " — " + failing.join(", "), level: "bad" }
    : /FAILED|not installed/.test(f.tests) ? { text: f.tests, level: "bad" }
    : { text: f.tests, level: "ok" };

  const probes = list("probes");
  rows.probes = probes.length
    ? { text: probes.length + " left in " + probes.join(", "), level: "warn" }
    : { text: "none", level: "ok" };

  const stale = list("stale");
  rows.stale = stale.length
    ? { text: stale.map((p) => p.replace(/.*\//, "")).join(", ") + " \u2014 restart to be sure", level: "warn" }
    : { text: "all current", level: "ok" };

  const kb = parseInt(f.rss, 10);
  if (isNaN(kb)) rows.memory = { text: "unreadable", level: "warn" };
  else {
    const gb = (k) => (k / 1e6).toFixed(2) + " GB";
    const pct = baselineKb > 0 ? Math.round((kb - baselineKb) / baselineKb * 100) : 0;
    rows.memory = {
      text: gb(kb) + (baselineKb > 0 ? " · baseline " + gb(baselineKb) + " (" + (pct >= 0 ? "+" : "") + pct + "%)" : ""),
      // Climbing past +30% is worth a look; past +70% it is the 1.8 GB
      // growth that was chased down once already.
      level: pct > 70 ? "bad" : pct > 30 ? "warn" : "ok",
    };
  }

  const held = list("held"), spawned = list("spawned");
  rows.pollers = {
    text: held.length + " held open" + (spawned.length ? " · spawned in 2s: " + counted(spawned) : " · nothing spawned in 2s"),
    // The known pollers fire once a second or two; five in two seconds is
    // the shape of a timer somebody forced on.
    level: spawned.length > 4 ? "warn" : "ok",
    detail: counted(held),
  };

  const errors = parseInt(f.errors, 10) || 0;
  const warnings = parseInt(f.warnings, 10) || 0;
  rows.log = {
    text: errors + (errors === 1 ? " error" : " errors") + " · " + warnings + (warnings === 1 ? " warning" : " warnings"),
    level: errors > 0 ? "bad" : "ok",
    detail: f.lasterror || "",
  };
  return rows;
}

// ── DISPLAYS ──────────────────────────────────────────────────────────────
// The Display section is the one part of this panel whose values are not
// kept in oracle.json. A monitor rule is hyprland's to hold, so it lives in
// hypr/lua/monitors.lua — the file is the store, read back on every change,
// and editing it by hand is as good as editing it here.
//
// A rule is keyed by the monitor's DESCRIPTION, not its connector: the same
// screen moved from DP-1 to DP-2, or a laptop docked on another day, is still
// the same screen and should still be set up the way it was.

// what a monitor with no rule of its own gets — the catch-all line's values
const DISPLAY_DEFAULTS = {
  enabled: true, mode: "preferred", scale: "auto",
  transform: 0, position: "auto", vrr: 0
};

function displayDefault(field) { return DISPLAY_DEFAULTS[field]; }

// "2560x1440@179.96Hz" → { w, h, rate } — or null for anything else
function parseMode(s) {
  const m = /^(\d+)x(\d+)(?:@([\d.]+))?/.exec(String(s || "").trim());
  if (!m) return null;
  return { w: Number(m[1]), h: Number(m[2]), rate: m[3] ? Number(m[3]) : 0 };
}

// 180 → "180", 59.94 → "59.94"
function rateText(r) {
  return String(Number(Number(r).toFixed(2)));
}

// `hyprctl monitors all -j` → the monitors, disabled ones included (so one
// can be switched back on), each with the modes it can actually run in.
function parseHyprMonitors(text) {
  let j = null;
  try { j = JSON.parse(String(text || "")); } catch (e) { return []; }
  if (!Array.isArray(j)) return [];
  const out = [];
  for (const m of j) {
    if (!m || typeof m.name !== "string") continue;
    const seen = {};
    const modes = [];
    for (const raw of (m.availableModes || [])) {
      const p = parseMode(raw);
      if (!p || !p.rate) continue;
      const value = p.w + "x" + p.h + "@" + rateText(p.rate);
      if (seen[value]) continue;
      seen[value] = true;
      modes.push({ value: value, w: p.w, h: p.h, rate: p.rate,
                   label: p.w + "×" + p.h + " · " + rateText(p.rate) + " Hz" });
    }
    // biggest first, then fastest — the order anyone scans a mode list in
    modes.sort((a, b) => (b.w * b.h - a.w * a.h) || (b.rate - a.rate));
    const desc = String(m.description || "").trim();
    out.push({
      name: m.name,
      desc: desc,
      model: [m.make, m.model].filter((x) => x && x !== "Unknown").join(" ").trim(),
      width: Number(m.width) || 0,
      height: Number(m.height) || 0,
      refresh: Number(m.refreshRate) || 0,
      scale: Number(m.scale) || 1,
      transform: Number(m.transform) || 0,
      x: Number(m.x) || 0,
      y: Number(m.y) || 0,
      disabled: m.disabled === true,
      modes: modes
    });
  }
  return out;
}

function modeOptions(mon) {
  const out = [
    { value: "preferred", label: "Preferred" },
    { value: "highres",   label: "Highest resolution" },
    { value: "highrr",    label: "Highest refresh rate" }
  ];
  for (const m of (mon && mon.modes) || []) out.push({ value: m.value, label: m.label });
  return out;
}

// Only the scales that divide the screen into whole pixels. hyprland takes any
// other number too, and then quietly picks a nearby one and warns about it —
// so offering 1.3 would be offering a setting that does not stick.
const SCALES = [1, 1.2, 1.25, 1.333333, 1.5, 1.6, 1.666667, 1.75, 2, 2.4, 2.5, 3];

function scaleOptions(mon) {
  const out = [{ value: "auto", label: "Automatic" }];
  // the largest mode, not the current one, so the list does not change
  // underneath you as you step through resolutions
  const top = mon && mon.modes && mon.modes.length ? mon.modes[0]
    : { w: mon ? mon.width : 0, h: mon ? mon.height : 0 };
  const whole = (x) => Math.abs(x - Math.round(x)) < 0.01;
  for (const s of SCALES) {
    if (top.w && top.h && !(whole(top.w / s) && whole(top.h / s))) continue;
    out.push({ value: String(s), label: Math.round(s * 100) + "%" });
  }
  return out;
}

const TRANSFORM_OPTIONS = [
  { value: 0, label: "Normal" },
  { value: 1, label: "90°" },
  { value: 2, label: "180°" },
  { value: 3, label: "270°" }
];

const POSITION_OPTIONS = [
  { value: "auto",       label: "Automatic" },
  { value: "auto-left",  label: "Left of the others" },
  { value: "auto-right", label: "Right of the others" },
  { value: "auto-up",    label: "Above the others" },
  { value: "auto-down",  label: "Below the others" }
];

const VRR_OPTIONS = [
  { value: 0, label: "Off" },
  { value: 1, label: "On" },
  { value: 2, label: "Fullscreen only" }
];

// A mode as written by hand ("2560x1440@180") onto the one in the monitor's
// list it means ("2560x1440@180"), so the chip shows its label and not the
// raw string. The keywords and anything unmatched pass through untouched.
function matchMode(value, modes) {
  const p = parseMode(value);
  if (!p) return String(value || "preferred");
  let best = null;
  for (const m of modes || []) {
    if (m.w !== p.w || m.h !== p.h) continue;
    if (!p.rate) { if (!best || m.rate > best.rate) best = m; continue; }
    if (Math.abs(m.rate - p.rate) < 0.5 && (!best ||
        Math.abs(m.rate - p.rate) < Math.abs(best.rate - p.rate))) best = m;
  }
  return best ? best.value : String(value);
}

// "1.333333" and 1.333333 and "1.33" are all the same scale.
function matchScale(value) {
  if (value === undefined || value === null || value === "auto") return "auto";
  const n = Number(value);
  if (!isFinite(n) || n <= 0) return "auto";
  for (const s of SCALES) if (Math.abs(s - n) < 0.005) return String(s);
  return String(n);
}

// ── monitors.lua, read ──
// Every hl.monitor({ … }) that is not commented out, as { output, fields }.
// Only plain values are understood — strings, numbers, booleans — which is
// everything a monitor rule is made of.
function parseMonitorRules(text) {
  const out = [];
  const src = String(text || "").split("\n")
    .map((l) => l.replace(/^\s*--.*$/, "")).join("\n");
  const re = /hl\.monitor\s*\(\s*\{([^}]*)\}\s*\)/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const fields = {};
    const fre = /([A-Za-z_]\w*)\s*=\s*("((?:[^"\\]|\\.)*)"|-?[\d.]+|true|false)/g;
    let f;
    while ((f = fre.exec(m[1])) !== null) {
      const raw = f[2];
      fields[f[1]] = f[3] !== undefined ? f[3].replace(/\\(.)/g, "$1")
        : raw === "true" ? true : raw === "false" ? false : Number(raw);
    }
    if (typeof fields.output !== "string") continue;
    const output = fields.output;
    delete fields.output;
    out.push({ output: output, fields: fields });
  }
  return out;
}

// Does this rule name this monitor? By description, which is what this panel
// writes, or by connector, which is what people write by hand.
function ruleMatches(output, mon) {
  if (!mon || output === "") return false;
  if (output === mon.name) return true;
  if (output.indexOf("desc:") === 0) {
    const d = output.slice(5).trim();
    return d !== "" && mon.desc.indexOf(d) === 0;
  }
  return false;
}

// A rule's fields → the panel's values for one monitor.
function displayValues(rule, mon) {
  const f = (rule && rule.fields) || {};
  return {
    enabled: f.disabled !== true,
    mode: f.mode !== undefined ? matchMode(f.mode, mon ? mon.modes : []) : "preferred",
    // A rule written without a scale is running at whatever hyprland gave
    // it, so that is what it reads as — not "auto", which a save would then
    // write out and quietly change the screen.
    scale: f.scale !== undefined ? matchScale(f.scale)
      : rule && mon ? matchScale(mon.scale) : "auto",
    transform: [0, 1, 2, 3].indexOf(Number(f.transform)) >= 0 ? Number(f.transform) : 0,
    position: typeof f.position === "string" ? f.position : "auto",
    vrr: [0, 1, 2].indexOf(Number(f.vrr)) >= 0 ? Number(f.vrr) : 0
  };
}

function isDefaultDisplay(v) {
  for (const k in DISPLAY_DEFAULTS)
    if (!same(v[k], DISPLAY_DEFAULTS[k])) return false;
  return true;
}

// ── monitors.lua, written ──
function luaString(s) {
  return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
}

function ruleLine(output, fields) {
  const parts = ["output = " + luaString(output)];
  const order = ["disabled", "mode", "position", "scale", "transform", "vrr"];
  const keys = order.filter((k) => k in fields)
    .concat(Object.keys(fields).filter((k) => order.indexOf(k) < 0).sort());
  for (const k of keys) {
    const v = fields[k];
    parts.push(k + " = " + (typeof v === "string" ? luaString(v) : String(v)));
  }
  return "hl.monitor({ " + parts.join(", ") + " })";
}

// `entries` is [{ mon, values }] for the monitors the panel knows about;
// `kept` is the rules for monitors that are not connected right now, carried
// through untouched so that undocking never erases a screen's setup.
function renderMonitorRules(entries, kept) {
  const lines = [
    "-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐",
    "-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐",
    "-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘",
    "-- https://github.com/kbuckleys/",
    "",
    "-- MONITORS",
    "-- Written by oracle's Display section, and read back by it: change a",
    "-- screen there or here, either way works. Rules name a monitor by its",
    "-- description, so a screen keeps its setup whichever port it is in.",
    "",
    "-- Any output without a rule of its own (another machine, a projector) gets",
    "-- its preferred mode rather than being left unconfigured.",
    ruleLine("", { mode: "preferred", position: "auto", scale: "auto" })
  ];
  const rules = [];
  for (const e of entries || []) {
    const v = e.values;
    if (isDefaultDisplay(v)) continue;
    const f = {};
    if (!v.enabled) f.disabled = true;
    f.mode = v.mode;
    f.position = v.position;
    f.scale = v.scale === "auto" ? "auto" : Number(v.scale);
    if (v.transform) f.transform = v.transform;
    if (v.vrr) f.vrr = v.vrr;
    const id = e.mon.desc !== "" ? "desc:" + e.mon.desc : e.mon.name;
    rules.push("-- " + e.mon.name + (e.mon.model ? " · " + e.mon.model : ""));
    rules.push(ruleLine(id, f));
  }
  if (rules.length) {
    lines.push("");
    for (const r of rules) lines.push(r);
  }
  if ((kept || []).length) {
    lines.push("", "-- not connected right now, kept for when they are");
    for (const r of kept) lines.push(ruleLine(r.output, r.fields));
  }
  return lines.join("\n") + "\n";
}

// the fixed lists, as functions: a top-level const is not reliably visible
// through a QML import's namespace, a function always is
function transformOptions() { return TRANSFORM_OPTIONS; }
function positionOptions() { return POSITION_OPTIONS; }
function vrrOptions() { return VRR_OPTIONS; }

// ── ARRANGEMENT ───────────────────────────────────────────────────────────
// The Display section's picture of the desk: every monitor as the rectangle
// it covers on the desktop, dragged about and snapped against the others,
// then written as an exact position for each one.

// "1080x0" → { x, y }, or null for anything that is not an exact position
function parsePosition(v) {
  const m = /^(-?\d+)x(-?\d+)$/.exec(String(v || "").trim());
  return m ? { x: Number(m[1]), y: Number(m[2]) } : null;
}

// What a monitor covers on the desktop: its mode, divided by its scale, and
// turned on its side when it is rotated a quarter.
function logicalSize(mon) {
  const w = (Number(mon.width) || 0) / (Number(mon.scale) || 1);
  const h = (Number(mon.height) || 0) / (Number(mon.scale) || 1);
  return (Number(mon.transform) || 0) % 2 === 1
    ? { w: Math.round(h), h: Math.round(w) } : { w: Math.round(w), h: Math.round(h) };
}

function overlaps(a, b) {
  return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

// Drop rects[i] near (x, y) and let it find its place: touching one of the
// others along a whole edge, never overlapping any, and lined up with the
// one it touches when it is dropped close to lining up. Then the lot is moved
// so the top-left of the whole desk is 0,0, which is how hyprland likes it.
//
// `rects` is [{ name, x, y, w, h }] in desktop pixels; a new array is
// returned and the one given is left alone.
const ALIGN_PULL = 48;

function snapArrangement(rects, i, x, y) {
  const out = rects.map((r) => ({ name: r.name, x: r.x, y: r.y, w: r.w, h: r.h }));
  const d = out[i];
  const others = out.filter((r, k) => k !== i);
  if (others.length === 0) { d.x = 0; d.y = 0; return normalize(out); }

  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const cands = [];
  for (const o of others) {
    for (const cx of [o.x - d.w, o.x + o.w]) {
      cands.push({ x: cx, y: o.y, aligned: true });
      cands.push({ x: cx, y: o.y + o.h - d.h, aligned: true });
      cands.push({ x: cx, y: o.y + (o.h - d.h) / 2, aligned: true });
      cands.push({ x: cx, y: clamp(y, o.y - d.h + 1, o.y + o.h - 1), aligned: false });
    }
    for (const cy of [o.y - d.h, o.y + o.h]) {
      cands.push({ x: o.x, y: cy, aligned: true });
      cands.push({ x: o.x + o.w - d.w, y: cy, aligned: true });
      cands.push({ x: o.x + (o.w - d.w) / 2, y: cy, aligned: true });
      cands.push({ x: clamp(x, o.x - d.w + 1, o.x + o.w - 1), y: cy, aligned: false });
    }
  }
  let best = null, bestScore = Infinity;
  for (const c of cands) {
    const r = { x: Math.round(c.x), y: Math.round(c.y), w: d.w, h: d.h };
    if (others.some((o) => overlaps(r, o))) continue;
    const score = Math.hypot(r.x - x, r.y - y) - (c.aligned ? ALIGN_PULL : 0);
    if (score < bestScore) { bestScore = score; best = r; }
  }
  if (best) { d.x = best.x; d.y = best.y; }
  return normalize(out);
}

function normalize(rects) {
  let mx = Infinity, my = Infinity;
  for (const r of rects) { mx = Math.min(mx, r.x); my = Math.min(my, r.y); }
  if (!isFinite(mx)) return rects;
  for (const r of rects) { r.x -= mx; r.y -= my; }
  return rects;
}

// ── WHERE A SEARCH MATCHED ────────────────────────────────────────────────
// `text` with every word of `query` marked in `ink`, as StyledText — so a row
// that came up for "blur" shows where it said blur. Case-insensitive, like
// the match itself; everything else is escaped so a label can never turn
// into markup. A row that matched only through its alias or key has nothing
// to mark, and comes back as plain (escaped) text.
function markMatch(text, query, ink) {
  const src = String(text || "");
  const esc = (x) => x.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const words = String(query || "").trim().toLowerCase().split(/\s+/).filter((w) => w !== "");
  if (words.length === 0) return esc(src);
  const lower = src.toLowerCase();
  const hit = new Array(src.length).fill(false);
  for (const w of words) {
    let i = 0;
    while ((i = lower.indexOf(w, i)) >= 0) {
      for (let k = i; k < i + w.length; ++k) hit[k] = true;
      i += w.length;
    }
  }
  let out = "", run = "", on = false;
  const flush = () => {
    if (run === "") return;
    out += on ? "<font color='" + ink + "'>" + esc(run) + "</font>" : esc(run);
    run = "";
  };
  for (let k = 0; k < src.length; ++k) {
    if (hit[k] !== on) { flush(); on = hit[k]; }
    run += src[k];
  }
  flush();
  return out;
}
