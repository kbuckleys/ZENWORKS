// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ORACLE's pure half. Everything here is a function of its arguments and
// nothing else — no Quickshell, no QML scope, no singleton reached sideways —
// which is what makes it testable under oracle/tests the way cynosure's and
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
// oracle/doctor.sh prints `key<TAB>value` lines; this turns them into the
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
// Comments out: --[[ block ]] (and --[==[ … ]==]) first, then whole-line --.
// Only the line form was stripped before, so a rule parked inside a block
// comment was read as live.
function stripLuaComments(text) {
  return String(text || "")
    .replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, "")
    .split("\n").map((l) => l.replace(/^\s*--.*$/, "")).join("\n");
}

// Whatever the file says that is NOT a monitor rule — a hand-written
// statement the panel has no field for. Kept, so that "editing it by hand
// works too" stays true: the file used to be rebuilt from the rules alone,
// and anything else in it was gone on the next save from the panel.
function extraStatements(text) {
  return stripLuaComments(text)
    .replace(/hl\.monitor\s*\(\s*\{[^}]*\}\s*\)/g, "")
    .split("\n").map((l) => l.replace(/\s+$/, "")).filter((l) => l.trim() !== "");
}

function parseMonitorRules(text) {
  const out = [];
  const src = stripLuaComments(text);
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
function renderMonitorRules(entries, kept, extra) {
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
  if ((extra || []).length) {
    lines.push("", "-- written by hand, and kept as it was");
    for (const l of extra) lines.push(l);
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

// ── DEFAULT APPLICATIONS ──────────────────────────────────────────────────
// The second section whose values are not in oracle.json. Like the monitors,
// they belong to something else: the binds launch the terminal and the
// browser, so both are in hypr/lua/defaults.lua beside the rest of the
// hyprland config, and every other row there is a kind of file and the
// desktop entry that opens it, handed to `gio mime` so the whole desktop
// agrees rather than only this shell. The file is the store, read back on
// every change, and editing it by hand is as good as editing it here.
//
// A KIND, NOT A TYPE. Nobody wants to set image/png and then image/jpeg and
// then image/webp: they want "pictures open in picasso". A kind is the types
// that matter by name (`types`) plus every type the chosen application itself
// claims under a prefix (`prefixes`), less the ones that belong to another
// kind (`except`) — so choosing a text editor never hands it text/html.
//
// `probe` is the one type asked about to say what the system uses now.
const APP_KINDS = [
  { id: "browser", label: "Web browser", probe: "x-scheme-handler/https",
    alias: "internet web links url http html",
    types: ["x-scheme-handler/http", "x-scheme-handler/https", "text/html",
            "application/xhtml+xml"],
    help: "Links, web pages, and what Super+B opens." },
  { id: "mail", label: "Email", probe: "x-scheme-handler/mailto",
    alias: "mail mailto email client",
    types: ["x-scheme-handler/mailto"],
    help: "What a mailto: link opens." },
  // `preferred`: what the row holds before anybody chooses — this shell's
  // own, where it has one. Every other kind starts at the system's answer.
  { id: "files", label: "Directories", probe: "inode/directory",
    alias: "file manager folder directory terminus",
    types: ["inode/directory"], preferred: "terminus.desktop",
    help: "The file manager: what other applications open a directory with — a browser's Show in folder, for one. This shell's own directories always open in terminus." },
  { id: "text", label: "Text", probe: "text/plain",
    alias: "editor text code notes plain",
    types: ["text/plain", "text/markdown", "application/json", "application/x-shellscript",
            "text/x-python", "text/x-csrc", "text/x-chdr", "text/x-c++src", "text/css",
            "text/x-lua", "application/toml", "application/x-yaml", "application/xml"],
    prefixes: ["text/"],
    except: ["text/html", "text/calendar", "text/vcard", "text/x-vcard"],
    help: "Plain text, code and config files." },
  { id: "images", label: "Images", probe: "image/png",
    alias: "pictures photos viewer image",
    types: ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/tiff",
            "image/svg+xml", "image/avif", "image/heif", "image/jxl", "image/x-icon"],
    prefixes: ["image/"],
    except: ["image/vnd.djvu", "image/vnd.djvu+multipage"] },
  { id: "video", label: "Video", probe: "video/mp4",
    alias: "movies player video",
    types: ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime",
            "video/x-msvideo", "video/mpeg", "video/ogg", "video/x-flv"],
    prefixes: ["video/"] },
  { id: "audio", label: "Music", probe: "audio/mpeg",
    alias: "audio music sound player",
    types: ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-vorbis+ogg", "audio/opus",
            "audio/x-wav", "audio/wav", "audio/mp4", "audio/aac", "audio/x-m4a"],
    prefixes: ["audio/"],
    help: "Audio files — the bar's now playing follows whatever plays them." },
  { id: "documents", label: "PDFs & e-books", probe: "application/pdf",
    alias: "pdf epub djvu document reader viewer book",
    types: ["application/pdf", "application/epub+zip", "image/vnd.djvu",
            "application/postscript", "application/oxps", "application/x-mobipocket-ebook"] },
  { id: "office", label: "Office documents", probe: "application/vnd.oasis.opendocument.text",
    alias: "office word excel spreadsheet presentation docx odt libreoffice",
    types: ["application/vnd.oasis.opendocument.text",
            "application/vnd.oasis.opendocument.spreadsheet",
            "application/vnd.oasis.opendocument.presentation",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "application/msword", "application/vnd.ms-excel",
            "application/vnd.ms-powerpoint", "application/rtf"],
    // not "application/vnd.ms-", which is also asf video and every media
    // player's; and not csv, which every text editor claims
    prefixes: ["application/vnd.oasis.opendocument.",
               "application/vnd.openxmlformats-officedocument."] },
  { id: "archives", label: "Archives", probe: "application/zip",
    alias: "zip tar compressed archive extract",
    types: ["application/zip", "application/x-tar", "application/x-compressed-tar",
            "application/x-xz-compressed-tar", "application/x-zstd-compressed-tar",
            "application/x-bzip2-compressed-tar", "application/x-7z-compressed",
            "application/vnd.rar", "application/x-rar", "application/gzip", "application/zstd"] },
  { id: "torrents", label: "Torrents", probe: "x-scheme-handler/magnet",
    alias: "torrent magnet bittorrent download",
    types: ["x-scheme-handler/magnet", "application/x-bittorrent"] },
  { id: "calendar", label: "Calendar files", probe: "text/calendar",
    alias: "calendar ics event invite",
    types: ["text/calendar", "application/ics", "text/x-vcalendar"],
    help: "An .ics invite, from a mail or a download." },
  { id: "fonts", label: "Fonts", probe: "font/ttf",
    alias: "font typeface ttf otf preview",
    types: ["font/ttf", "font/otf", "font/woff", "font/woff2", "font/collection",
            "application/x-font-ttf", "application/x-font-otf"],
    prefixes: ["font/"] }
];

// as functions, for the reason the display lists are
function appKinds() { return APP_KINDS; }

function appKind(id) {
  for (const k of APP_KINDS) if (k.id === id) return k;
  return null;
}

// every probe, which is what defaults.sh is asked about
function appProbes() { return APP_KINDS.map((k) => k.probe); }

// Does this type belong to this kind?
function inKind(kind, mime) {
  if (!kind) return false;
  if ((kind.except || []).indexOf(mime) >= 0) return false;
  if (kind.types.indexOf(mime) >= 0) return true;
  for (const p of kind.prefixes || []) if (mime.indexOf(p) === 0) return true;
  return false;
}

// defaults.sh's lines → { apps, current: { mime: id }, terminal: id }
function readDefaultsScan(text) {
  const apps = [];
  const current = ({});
  const bins = [];
  let terminal = "";
  for (const line of String(text || "").split("\n")) {
    const f = line.split("\t");
    if (f[0] === "app" && f.length >= 6 && f[1] !== "") {
      apps.push({
        id: f[1], name: f[2] || f[1],
        mime: f[3].split(";").filter((m) => m !== ""),
        cats: f[4].split(";").filter((c) => c !== ""),
        exec: f[5].replace(/.*\//, ""),
        terminal: f[6] === "true"
      });
    } else if (f[0] === "bin" && f.length >= 2 && f[1] !== "") {
      bins.push(f[1]);
    } else if (f[0] === "default" && f.length >= 3) {
      current[f[1]] = f[2].trim();
    } else if (f[0] === "terminal" && f.length >= 2) {
      terminal = f[1].trim();
    }
  }
  return { apps: apps, current: current, terminal: terminal, bins: bins };
}

function appById(apps, id) {
  for (const a of apps || []) if (a.id === id) return a;
  return null;
}

function byName(a, b) {
  const x = a.name.toLowerCase(), y = b.name.toLowerCase();
  return x < y ? -1 : x > y ? 1 : 0;
}

// The applications that claim anything of this kind, by name.
function kindCandidates(kind, apps) {
  return (apps || []).filter((a) => a.mime.some((m) => inKind(kind, m))).sort(byName);
}

// The row's choices: the system's own answer first, named for what it is
// right now, and then everything installed that could do the job. A value
// written by hand for something not installed stays as itself — the row is
// an open enum, the same as a monitor that is unplugged.
function appOptions(kind, apps, currentId) {
  const now = appById(apps, currentId);
  const out = [{ value: "", label: "System · " + (now ? now.name : currentId || "nothing") }];
  for (const a of kindCandidates(kind, apps)) out.push({ value: a.id, label: a.name });
  return out;
}

// The types a choice is written for: everything the application claims that
// belongs to the kind. An application that claims none of them — a hand-
// written id for something not installed — gets the kind's named types.
function typesFor(kind, app) {
  const own = app ? app.mime.filter((m) => inKind(kind, m)) : [];
  if (own.length === 0) return kind.types.slice();
  const seen = ({});
  return own.filter((m) => (seen[m] ? false : (seen[m] = true)));
}

// ── the terminal ──
// Not a mime type: freedesktop names terminals by category, and xdg-terminal-
// exec — which gio uses to open nvim and every other Terminal=true entry —
// reads its choice from xdg-terminals.list. The binds want a COMMAND, so that
// is what is stored; the entry is found again by its Exec.
function terminalCandidates(apps) {
  const seen = ({});
  return (apps || []).filter((a) => a.cats.indexOf("TerminalEmulator") >= 0 && a.exec !== ""
    && (seen[a.exec] ? false : (seen[a.exec] = true))).sort(byName);
}

function terminalOptions(apps) {
  return terminalCandidates(apps).map((a) => ({ value: a.exec, label: a.name }));
}

// "kitty --single-instance" → kitty.desktop, by the command's first word
function terminalEntry(cmd, apps) {
  const w = String(cmd || "").trim().split(/\s+/)[0].replace(/.*\//, "");
  if (w === "") return "";
  for (const a of terminalCandidates(apps)) if (a.exec === w) return a.id;
  return "";
}

// What a machine with no defaults.lua starts with: kitty, which ZENWORKS
// installs, and failing that the first terminal there is.
function terminalFallback(apps) {
  const t = terminalCandidates(apps);
  if (t.length === 0 || t.some((a) => a.exec === "kitty")) return "kitty";
  return t[0].exec;
}

// ── PROGRAMS WITHOUT A MIME TYPE ──
// A system monitor and a terminal editor are found two ways: by a desktop
// entry's category, and by name on PATH — `nano` and `htop` are on most
// machines and half of them ship no entry at all. defaults.sh is asked about
// these names and prints the ones it finds.
const EDITOR_BINS = ["nvim", "vim", "helix", "hx", "micro", "nano", "kak", "emacs", "vi"];
const SYSMON_BINS = ["btop", "htop", "btm", "glances", "atop", "bpytop", "nvtop", "top"];

function knownBins() { return EDITOR_BINS.concat(SYSMON_BINS); }

// A program run in a terminal is stored as its command; one that is its own
// window as its desktop id, which is how the binds tell the two apart.
function programOptions(apps, bins, wanted, category) {
  const out = [];
  const seen = ({});
  const add = (value, label) => {
    if (seen[value]) return;
    seen[value] = true;
    out.push({ value: value, label: label });
  };
  const named = (bin) => {
    for (const a of apps || []) if (a.exec === bin) return a.name;
    return bin;
  };
  for (const b of wanted) if ((bins || []).indexOf(b) >= 0) add(b, named(b));
  const entries = (apps || []).filter((a) => a.cats.indexOf(category) >= 0).sort(byName);
  for (const a of entries) if (a.terminal && a.exec !== "") add(a.exec, a.name);
  return { tui: out, gui: entries.filter((a) => !a.terminal && !seen[a.id]) };
}

// Zeus first: it is this shell's own, and what Super+K already opens.
function sysmonOptions(apps, bins) {
  const p = programOptions(apps, bins, SYSMON_BINS, "Monitor");
  return [{ value: "zeus", label: "Zeus" }].concat(p.tui)
    .concat(p.gui.map((a) => ({ value: a.id, label: a.name })));
}

// Plato first: it is this shell's own, and the one window that can be
// $EDITOR — hypr/lua/base.lua makes it `plato --wait`, so git and sudoedit
// wait for its tab to close. Then the ones that run in a terminal, opened
// inside the terminal git, sudoedit or crontab was run from. Other windowed
// editors are left out: they return at once, and git would read the file
// back before anything was written to it.
function editorOptions(apps, bins) {
  return [{ value: "plato", label: "Plato" }]
    .concat(programOptions(apps, bins, EDITOR_BINS, "TextEditor").tui);
}

function editorFallback(apps, bins) {
  return "plato";
}

// An image EDITOR is not a default for any type — the viewer is — so it is
// offered from inside the viewer instead. What claims images AND says it
// draws: a browser claims pictures too, and a viewer files itself under
// Photography, so the list is opted into by category rather than filtered.
function imageEditorOptions(apps) {
  const img = appKind("images");
  const draws = (a) => ["RasterGraphics", "2DGraphics", "VectorGraphics"]
    .some((c) => a.cats.indexOf(c) >= 0)
    || (a.cats.indexOf("Photography") >= 0 && a.cats.indexOf("Viewer") < 0);
  return [{ value: "", label: "None" }].concat(kindCandidates(img, apps)
    .filter(draws).map((a) => ({ value: a.id, label: a.name })));
}

// ── defaults.lua ──
// the programs first, in this order, then a kind per line
const PROGRAM_KEYS = ["terminal", "browser", "editor", "sysmon", "image_editor"];
const DEFAULTS_KEYS = PROGRAM_KEYS.concat(APP_KINDS.map((k) => k.id).filter((k) => k !== "browser"));

// Every `key = "value"` that is not commented out. Strings only, which is all
// this file holds.
function parseDefaultsLua(text) {
  const out = ({});
  const src = stripLuaComments(text);
  const re = /([A-Za-z_]\w*)\s*=\s*"((?:[^"\\]|\\.)*)"/g;
  let m;
  while ((m = re.exec(src)) !== null) out[m[1]] = m[2].replace(/\\(.)/g, "$1");
  return out;
}

// `values` is key → string for the keys above; anything else in it was
// written by hand and is kept, after them.
function renderDefaultsLua(values) {
  const v = values || ({});
  const pad = (k) => k + " ".repeat(Math.max(0, 12 - k.length));
  const line = (k) => "\t" + pad(k) + " = " + luaString(v[k] === undefined ? "" : v[k]) + ",";
  const lines = [
    "-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐",
    "-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐",
    "-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘",
    "-- https://github.com/kbuckleys/",
    "",
    "-- DEFAULTS",
    "-- Written by oracle's Default Apps section, and read back by it: change",
    "-- one there or here, either way works.",
    "--",
    "-- terminal   the command the binds run; oracle also puts its entry first",
    "--            in xdg-terminals.list, which terminal applications open in",
    "-- browser    a desktop id, for Super+B and $BROWSER",
    "-- editor     a command, for $EDITOR and $VISUAL",
    "-- sysmon     \"zeus\", a command run in the terminal, or a desktop id",
    "-- image_editor  a desktop id, offered in picasso as Edit in …",
    "--",
    "-- Every line after those is a kind of file and the desktop id that opens",
    "-- it; oracle hands it to `gio mime`, so the whole desktop agrees.",
    "-- \"\" leaves that one to the system.",
    "",
    "return {"
  ];
  for (const k of PROGRAM_KEYS) lines.push(line(k));
  lines.push("");
  for (const k of APP_KINDS) if (k.id !== "browser") lines.push(line(k.id));
  const extra = Object.keys(v).filter((k) => DEFAULTS_KEYS.indexOf(k) < 0).sort();
  if (extra.length) {
    lines.push("", "\t-- written by hand, and kept as it was");
    for (const k of extra) lines.push(line(k));
  }
  lines.push("}");
  return lines.join("\n") + "\n";
}

// ── INPUT ──
// The keyboard, the mouse, the touchpad, the touch screen, the tablet: every
// input setting hyprland has, kept in hypr/lua/input.lua for the reason the
// monitors and the default apps are kept in theirs. hyprland reads them when
// it starts, before this shell exists, and a layout that only landed once
// oracle was up would leave the login's first minute typed in the wrong one.
// base.lua hands the table to hl.config; oracle reads it back, so an edit by
// hand shows here too.
//
// One flat table, each key hyprland's own name under input — touchpad_,
// tablet_, tablettool_, touchdevice_ and virtualkeyboard_ for the ones under
// those — so the file reads like the config it feeds. The defaults, ranges
// and choices are hyprland's own (src/config/values/ConfigValues.cpp, 0.56):
// a file with nothing changed is a machine as hyprland ships it, and nobody's
// mouse is set up for them.
//
// `group` is the header a row sits under; a row's options that are facts
// about this machine — the layouts xkb knows, the screens — are filled in
// by the panel (Oracle.inputSpecs).
const INPUT_GROUPS = [
  { id: "keyboard", label: "Keyboard", devices: true,
    help: "Layout and repeat, for every keyboard at once." },
  { id: "mouse", label: "Mouse", devices: true,
    help: "Pointer speed and buttons. These reach a touchpad's pointer too." },
  { id: "scroll", label: "Scrolling",
    help: "The wheel, and scrolling by holding a button." },
  { id: "focus", label: "Focus",
    help: "Which window the keyboard goes to as the pointer moves and windows close." },
  { id: "touchpad", label: "Touchpad", devices: true,
    help: "Taps, drags and two-finger scrolling." },
  { id: "touch", label: "Touch screen", devices: true,
    help: "A screen you can touch." },
  { id: "tablet", label: "Drawing tablet", devices: true,
    help: "Which screen the tablet draws on, and what part of the tablet maps to it." },
  { id: "tablettool", label: "Tablet pen",
    help: "The pen's eraser and pressure." },
  { id: "virtualkeyboard", label: "On-screen keyboard",
    help: "Keyboards made by programs: on-screen keyboards, input methods, wtype." },
];

const MS_FIELD = { type: "int", unit: "ms" };
const XY = "two numbers, x then y, such as 1920 1080";

const INPUT_FIELDS = [
  // keyboard
  { key: "kb_layout", group: "keyboard", def: "us", type: "enum", open: true, chipW: 208, options: "xkbLayouts",
    label: "Layout", alias: "keyboard layout language xkb qwerty azerty qwertz",
    help: "What the keys type. Two or more, such as us,de, are written in the file, with the key that switches between them in Options." },
  { key: "kb_variant", group: "keyboard", def: "", type: "enum", open: true, chipW: 208, options: "xkbVariants",
    label: "Variant", alias: "keyboard variant dvorak colemak intl dead keys xkb",
    help: "Another arrangement of the same layout: Dvorak, Colemak, international with dead keys." },
  { key: "kb_options", group: "keyboard", def: "", type: "text",
    label: "Options", alias: "keyboard options xkb caps lock escape compose switch layout grp",
    help: "xkb's options, comma-separated: caps:escape makes Caps Lock an Escape, grp:alt_shift_toggle switches layouts with Alt+Shift, compose:ralt makes Right Alt a Compose key." },
  { key: "kb_model", group: "keyboard", def: "", type: "text",
    label: "Model", alias: "keyboard model xkb pc105",
    help: "xkb's name for the keyboard itself, such as pc105. Empty lets xkb decide." },
  { key: "kb_rules", group: "keyboard", def: "", type: "text",
    label: "Rules", alias: "keyboard rules xkb evdev",
    help: "xkb's rules file. Empty is evdev, which is right almost everywhere." },
  { key: "kb_file", group: "keyboard", def: "", type: "text",
    label: "Keymap file", alias: "keyboard keymap file xkb custom",
    help: "A whole .xkb keymap of your own, by path. Set, it replaces the layout, variant, options, model and rules." },
  { key: "repeat_delay", group: "keyboard", def: 600, type: "int", min: 0, max: 2000, step: 25, unit: "ms",
    label: "Repeat delay", alias: "keyboard key repeat delay hold",
    help: "How long a key is held before it starts repeating." },
  { key: "repeat_rate", group: "keyboard", def: 25, type: "int", min: 0, max: 200, step: 1, unit: "/s",
    label: "Repeat rate", alias: "keyboard key repeat rate speed",
    help: "How many times a second a held key repeats. 0 never repeats." },
  { key: "numlock_by_default", group: "keyboard", def: false, type: "bool",
    label: "Num Lock on", alias: "keyboard numlock number pad numpad",
    help: "The number pad types numbers from the start." },
  { key: "resolve_binds_by_sym", group: "keyboard", def: false, type: "bool",
    label: "Binds follow the layout", alias: "keyboard binds shortcuts layout symbol",
    help: "With several layouts, a shortcut on a letter follows where that letter is in the layout you are typing in, not where it is on the first one." },

  // mouse
  { key: "accel_profile", group: "mouse", def: "", type: "enum",
    options: [{ value: "", label: "Device default" }, { value: "adaptive", label: "Adaptive" },
              { value: "flat", label: "Flat" }, { value: "custom", label: "Custom" }],
    label: "Acceleration", alias: "mouse pointer acceleration accel profile flat adaptive",
    help: "Adaptive moves the pointer further the faster you move the mouse; Flat moves it the same distance however fast, the way most players want it. Custom takes its curve from Scroll curve." },
  { key: "sensitivity", group: "mouse", def: 0, type: "real", min: -1, max: 1, step: 0.05,
    label: "Pointer speed", alias: "mouse pointer speed sensitivity dpi",
    help: "Slower to the left, faster to the right. 0 leaves the device as it is." },
  { key: "force_no_accel", group: "mouse", def: false, type: "bool",
    label: "Raw movement", alias: "mouse acceleration off raw force no accel",
    help: "Bypasses acceleration altogether, pointer speed included. Flat acceleration is usually the better answer." },
  { key: "left_handed", group: "mouse", def: false, type: "bool",
    label: "Left-handed", alias: "mouse left handed swap buttons",
    help: "Swaps the left and right buttons." },
  { key: "rotation", group: "mouse", def: 0, type: "int", min: 0, max: 359, step: 1, unit: "°",
    label: "Rotation", alias: "mouse trackball rotation angle",
    help: "Turns the device's movement clockwise, for a trackball or a mouse held at an angle." },
  { key: "scroll_points", group: "mouse", def: "", type: "text",
    label: "Scroll curve", alias: "mouse custom acceleration scroll points curve",
    help: "With acceleration set to Custom: libinput's step and then its points, such as 0.2 0.0 0.5 1 1.2 1.5." },

  // scrolling
  { key: "natural_scroll", group: "scroll", def: false, type: "bool",
    label: "Natural scrolling", alias: "mouse wheel scroll natural reverse direction",
    help: "The wheel moves the page rather than the view: down brings the page up." },
  { key: "scroll_factor", group: "scroll", def: 1, type: "real", min: 0, max: 2, step: 0.05, unit: "x",
    label: "Scroll speed", alias: "mouse wheel scroll speed factor",
    help: "How far a turn of the wheel scrolls, against the mouse's own." },
  { key: "scroll_method", group: "scroll", def: "", type: "enum",
    options: [{ value: "", label: "Device default" }, { value: "2fg", label: "Two fingers" },
              { value: "edge", label: "Edge" }, { value: "on_button_down", label: "Holding a button" },
              { value: "no_scroll", label: "Off" }],
    label: "Scroll method", alias: "scroll method button edge two finger trackball",
    help: "How a device without a wheel scrolls. Holding a button turns movement into scrolling while that button is down — the trackball way." },
  { key: "scroll_button", group: "scroll", def: 0, type: "int", min: 0, max: 300, step: 1,
    label: "Scroll button", alias: "scroll button code trackball",
    help: "Which button Holding a button means, as libinput numbers it (274 is the middle button). 0 is the device's own choice." },
  { key: "scroll_button_lock", group: "scroll", def: false, type: "bool",
    label: "Scroll button toggles", alias: "scroll button lock toggle",
    help: "One press starts scrolling and the next stops it, rather than holding it down." },
  { key: "emulate_discrete_scroll", group: "scroll", def: 1, type: "enum",
    options: [{ value: 0, label: "Off" }, { value: 1, label: "Unusual devices" }, { value: 2, label: "Every device" }],
    label: "Wheel steps", alias: "scroll discrete high resolution wheel steps",
    help: "Turns a smooth, high-resolution wheel's motion into the steps older programs expect." },

  // focus
  { key: "follow_mouse", group: "focus", def: 1, type: "enum",
    options: [{ value: 0, label: "Click to focus" }, { value: 1, label: "Follows the pointer" },
              { value: 2, label: "Pointer only" }, { value: 3, label: "Separate" }],
    label: "Focus", alias: "focus follows mouse pointer click hover",
    help: "Follows the pointer: the window under it gets the keyboard. Pointer only: hovering sends the pointer there but the keyboard stays until you click. Separate: the keyboard never follows the pointer at all." },
  { key: "follow_mouse_threshold", group: "focus", def: 0, type: "real", min: 0, max: 200, step: 1, unit: "px",
    label: "Pointer travel before focus", alias: "focus follow mouse threshold distance",
    help: "How far the pointer has to move before the window under it is focused." },
  { key: "follow_mouse_shrink", group: "focus", def: 0, type: "int", min: 0, max: 300, step: 1, unit: "px",
    label: "Focus dead zone", alias: "focus follow mouse shrink gap dead zone",
    help: "Shrinks what counts as over a window, so the gaps between windows change nothing. Only while focus follows the pointer." },
  { key: "mouse_refocus", group: "focus", def: true, type: "bool",
    label: "Refocus on any movement", alias: "focus mouse refocus hover",
    help: "Off, the pointer has to cross into another window to focus it; moving inside the one you are over does nothing." },
  { key: "focus_on_close", group: "focus", def: 0, type: "enum",
    options: [{ value: 0, label: "The next window" }, { value: 1, label: "Under the pointer" },
              { value: 2, label: "The last one used" }],
    label: "After a window closes", alias: "focus close window next mru",
    help: "Which window gets the keyboard when the focused one closes." },
  { key: "float_switch_override_focus", group: "focus", def: 1, type: "enum",
    options: [{ value: 0, label: "Off" }, { value: 1, label: "Tiled ↔ floating" }, { value: 2, label: "And floating ↔ floating" }],
    label: "Focus on float switch", alias: "focus floating tiled switch",
    help: "Moving between a tiled and a floating window hands focus to the one under the pointer." },
  { key: "special_fallthrough", group: "focus", def: false, type: "bool",
    label: "Click through scratchpad", alias: "focus special workspace scratchpad floating fallthrough",
    help: "With only floating windows on a special workspace, the windows behind them can still be focused." },
  { key: "off_window_axis_events", group: "focus", def: 1, type: "enum",
    options: [{ value: 0, label: "Ignore" }, { value: 1, label: "Send" }, { value: 2, label: "Clamp" }, { value: 3, label: "Warp" }],
    label: "Scrolling beside a window", alias: "focus scroll axis outside window",
    help: "What a scroll just outside the focused window does: nothing, go to it anyway, go to it as if at its edge, or move the pointer onto it." },

  // touchpad
  { key: "touchpad_tap_to_click", group: "touchpad", def: true, type: "bool",
    label: "Tap to click", alias: "touchpad trackpad tap click laptop",
    help: "A tap is a click: one finger left, two right, three middle." },
  { key: "touchpad_tap_and_drag", group: "touchpad", def: true, type: "bool",
    label: "Tap and drag", alias: "touchpad trackpad tap drag laptop",
    help: "Tap, then touch again and slide, to drag." },
  { key: "touchpad_drag_lock", group: "touchpad", def: 0, type: "enum",
    options: [{ value: 0, label: "Off" }, { value: 1, label: "For a moment" }, { value: 2, label: "Until tapped" }],
    label: "Drag lock", alias: "touchpad trackpad drag lock lift laptop",
    help: "Lifting the finger mid-drag does not drop what is being dragged: for a moment, or until the next tap." },
  { key: "touchpad_drag_3fg", group: "touchpad", def: 0, type: "enum",
    options: [{ value: 0, label: "Off" }, { value: 1, label: "Three fingers" }, { value: 2, label: "Four fingers" }],
    label: "Finger drag", alias: "touchpad trackpad three four finger drag laptop",
    help: "Drags with three or four fingers down, no click needed." },
  { key: "touchpad_tap_button_map", group: "touchpad", def: "", type: "enum",
    options: [{ value: "", label: "Device default" }, { value: "lrm", label: "Left, right, middle" },
              { value: "lmr", label: "Left, middle, right" }],
    label: "Tap buttons", alias: "touchpad trackpad tap button map fingers laptop",
    help: "Which button a one-, two- and three-finger tap is." },
  { key: "touchpad_clickfinger_behavior", group: "touchpad", def: false, type: "bool",
    label: "Click by finger count", alias: "touchpad trackpad clickfinger click fingers laptop",
    help: "Pressing with one, two or three fingers is left, right and middle, wherever you press — rather than by which corner." },
  { key: "touchpad_middle_button_emulation", group: "touchpad", def: false, type: "bool",
    label: "Middle click from both", alias: "touchpad trackpad middle button emulation laptop",
    help: "Left and right pressed together are a middle click." },
  { key: "touchpad_natural_scroll", group: "touchpad", def: false, type: "bool",
    label: "Natural scrolling", alias: "touchpad trackpad scroll natural reverse direction laptop",
    help: "Two fingers move the page the way they move, as on a phone." },
  { key: "touchpad_scroll_factor", group: "touchpad", def: 1, type: "real", min: 0, max: 2, step: 0.05, unit: "x",
    label: "Scroll speed", alias: "touchpad trackpad scroll speed factor laptop",
    help: "How far two fingers scroll, against the touchpad's own." },
  { key: "touchpad_disable_while_typing", group: "touchpad", def: true, type: "bool",
    label: "Ignore while typing", alias: "touchpad trackpad palm typing disable laptop",
    help: "A palm brushing the touchpad mid-sentence does not move the pointer." },
  { key: "touchpad_flip_x", group: "touchpad", def: false, type: "bool",
    label: "Flip sideways", alias: "touchpad trackpad flip invert horizontal laptop",
    help: "Left on the touchpad moves the pointer right." },
  { key: "touchpad_flip_y", group: "touchpad", def: false, type: "bool",
    label: "Flip up and down", alias: "touchpad trackpad flip invert vertical laptop",
    help: "Up on the touchpad moves the pointer down." },

  // touch screen
  { key: "touchdevice_enabled", group: "touch", def: true, type: "bool",
    label: "Touch input", alias: "touch screen touchscreen enable disable",
    help: "Off, touching the screen does nothing." },
  { key: "touchdevice_output", group: "touch", def: "[[Auto]]", type: "enum", open: true, options: "touchScreens",
    label: "Screen", alias: "touch screen touchscreen monitor output map",
    help: "Which screen touches land on. Automatic asks the device." },
  { key: "touchdevice_transform", group: "touch", def: 0, type: "enum", options: "transforms",
    label: "Rotation", alias: "touch screen touchscreen rotate transform",
    help: "Turns touches to match a screen stood on its side." },

  // tablet
  { key: "tablet_output", group: "tablet", def: "", type: "enum", open: true, options: "tabletScreens",
    label: "Screen", alias: "tablet drawing pen wacom monitor output map",
    help: "Which screen the tablet draws on: all of them, the focused one, or one by name." },
  { key: "tablet_transform", group: "tablet", def: 0, type: "enum", options: "transforms",
    label: "Rotation", alias: "tablet drawing pen wacom rotate transform",
    help: "Turns the tablet's input, for a tablet or screen turned on its side." },
  { key: "tablet_left_handed", group: "tablet", def: false, type: "bool",
    label: "Left-handed", alias: "tablet drawing pen wacom left handed flip",
    help: "The tablet turned half round, buttons on the other side." },
  { key: "tablet_relative_input", group: "tablet", def: false, type: "bool",
    label: "Move like a mouse", alias: "tablet drawing pen wacom relative absolute",
    help: "The pen moves the pointer from where it is, rather than to the spot it points at." },
  { key: "tablet_region_position", group: "tablet", def: "0 0", type: "text",
    label: "Region position", alias: "tablet drawing wacom region position map area",
    help: "Where the area the tablet maps to starts, on its screen — " + XY + "." },
  { key: "tablet_absolute_region_position", group: "tablet", def: false, type: "bool",
    label: "Region position is absolute", alias: "tablet drawing wacom region absolute layout",
    help: "The position is on the whole desk of screens, not on the tablet's screen." },
  { key: "tablet_region_size", group: "tablet", def: "0 0", type: "text",
    label: "Region size", alias: "tablet drawing wacom region size map area",
    help: "How big that area is, in pixels — " + XY + ". 0 0 is the whole screen." },
  { key: "tablet_active_area_size", group: "tablet", def: "0 0", type: "text",
    label: "Active area size", alias: "tablet drawing wacom active area size mm",
    help: "How much of the tablet is used, in millimetres — " + XY + ". 0 0 is all of it." },
  { key: "tablet_active_area_position", group: "tablet", def: "0 0", type: "text",
    label: "Active area position", alias: "tablet drawing wacom active area position mm",
    help: "Where on the tablet that area starts, in millimetres — " + XY + "." },

  // tablet pen
  { key: "tablettool_eraser_button_mode", group: "tablettool", def: 0, type: "int", min: 0, max: 6, step: 1,
    label: "Eraser button mode", alias: "tablet pen stylus eraser button mode",
    help: "0 lets the pen's eraser button erase, as the hardware intends. 1 makes it an ordinary button, the one set below." },
  { key: "tablettool_eraser_button_override", group: "tablettool", def: 0, type: "int", min: 0, max: 1000, step: 1,
    label: "Eraser button", alias: "tablet pen stylus eraser button override code",
    help: "Which button the eraser button becomes in mode 1, by its code (331 is BTN_STYLUS; wev shows them). 0 is the default." },
  { key: "tablettool_pressure_range_min", group: "tablettool", def: -1, type: "real", min: -1, max: 1, step: 0.05,
    label: "Lightest pressure", alias: "tablet pen stylus pressure minimum range",
    help: "The pressure that counts as none. Below 0 is the pen's own, usually 0." },
  { key: "tablettool_pressure_range_max", group: "tablettool", def: -1, type: "real", min: -1, max: 1, step: 0.05,
    label: "Heaviest pressure", alias: "tablet pen stylus pressure maximum range",
    help: "The pressure that counts as full. Below 0 is the pen's own, usually 1." },

  // on-screen keyboard
  { key: "virtualkeyboard_share_states", group: "virtualkeyboard", def: 2, type: "enum",
    options: [{ value: 0, label: "Off" }, { value: 1, label: "On" }, { value: 2, label: "Except input methods" }],
    label: "Share key state", alias: "virtual keyboard share states modifiers ime",
    help: "Whether keys and modifiers held on a program's keyboard count as held on the real ones too." },
  { key: "virtualkeyboard_release_pressed_on_close", group: "virtualkeyboard", def: false, type: "bool",
    label: "Release keys on close", alias: "virtual keyboard release pressed keys close",
    help: "A program's keyboard going away lets go of whatever it was holding down." },
];

// the prefixes that are tables of their own under input, longest first so
// tablettool_ is not read as tablet_
const INPUT_PREFIXES = ["virtualkeyboard", "touchdevice", "tablettool", "touchpad", "tablet"];

function inputGroups() { return INPUT_GROUPS; }
function inputFields() { return INPUT_FIELDS; }
function inputKeys() { return INPUT_FIELDS.map((f) => f.key); }

function inputDefault(key) {
  for (const f of INPUT_FIELDS) if (f.key === key) return f.def;
  return undefined;
}

// key = "text" | number | true | false, comments ignored. Anything else in
// the file is a value this panel does not know, read the same way and kept.
function parseInputLua(text) {
  const out = ({});
  const src = stripLuaComments(text);
  const re = /([A-Za-z_]\w*)\s*=\s*("((?:[^"\\]|\\.)*)"|-?\d+(?:\.\d+)?|true|false)/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const raw = m[2];
    out[m[1]] = m[3] !== undefined ? m[3].replace(/\\(.)/g, "$1")
      : raw === "true" ? true : raw === "false" ? false : Number(raw);
  }
  return out;
}

function luaValue(v) {
  if (typeof v === "boolean") return v ? "true" : "false";
  // 0.30000000000000004 is not a sensitivity anyone chose
  if (typeof v === "number") return String(Math.round(v * 1000) / 1000);
  return luaString(v === undefined || v === null ? "" : v);
}

// `values` is key → value for the fields above; anything else in it was
// written by hand and is kept, after them.
function renderInputLua(values) {
  const v = values || ({});
  const known = inputKeys();
  const width = Math.max.apply(null, known.map((k) => k.length));
  const line = (k, val) => "\t" + k + " ".repeat(Math.max(0, width - k.length)) + " = " + luaValue(val) + ",";
  const lines = [
    "-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐",
    "-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐",
    "-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘",
    "-- https://github.com/kbuckleys/",
    "",
    "-- INPUT",
    "-- Written by oracle's Input section, and read back by it: change one",
    "-- there or here, either way works. base.lua hands these to hyprland's",
    "-- input settings, each under its own name; touchpad_, tablet_,",
    "-- tablettool_, touchdevice_ and virtualkeyboard_ ones go in the table",
    "-- of that name. \"\" leaves a setting to hyprland.",
    "--",
    "-- kb_layout, kb_variant and kb_options are xkb's names: \"us,de\" is two",
    "-- layouts, and kb_options is where the key that switches them goes",
    "-- (grp:alt_shift_toggle).",
    "",
    "return {",
  ];
  INPUT_GROUPS.forEach((g, i) => {
    if (i > 0) lines.push("");
    lines.push("\t-- " + g.label.toLowerCase());
    for (const f of INPUT_FIELDS)
      if (f.group === g.id) lines.push(line(f.key, v[f.key] === undefined ? f.def : v[f.key]));
  });
  const extra = Object.keys(v).filter((k) => known.indexOf(k) < 0).sort();
  if (extra.length) {
    lines.push("", "\t-- written by hand, and kept as it was");
    for (const k of extra) lines.push(line(k, v[k]));
  }
  lines.push("}");
  return lines.join("\n") + "\n";
}

// xkeyboard-config's list of what exists — evdev.lst, which hyprland's own
// xkbcommon reads from — as { layouts: [{value, label}], variants: {us: […]} }.
// The file is sections headed `! layout`, `! variant`, and so on; a variant
// line names its layout before a colon.
function parseXkbList(text) {
  const layouts = [];
  const variants = ({});
  let section = "";
  for (const raw of String(text || "").split("\n")) {
    const head = raw.match(/^!\s*(\w+)/);
    if (head) { section = head[1]; continue; }
    const m = raw.match(/^\s+(\S+)\s+(.+?)\s*$/);
    if (!m) continue;
    // "custom" is xkb's slot for a layout file of your own, not a layout
    if (section === "layout" && m[1] !== "custom") layouts.push({ value: m[1], label: m[2] + " · " + m[1] });
    else if (section === "variant") {
      const v = m[2].match(/^([^:]+):\s*(.*)$/);
      if (!v) continue;
      (variants[v[1]] = variants[v[1]] || []).push({ value: m[1], label: v[2] });
    }
  }
  layouts.sort((a, b) => a.label.localeCompare(b.label));
  return { layouts: layouts, variants: variants };
}

// The variants of the FIRST layout. With two layouts the variant is a list
// too ("intl,"), and that is typed in the file rather than picked here; the
// row keeps whatever it holds.
function variantOptions(xkb, layout) {
  const first = String(layout || "").split(",")[0].trim();
  const own = ((xkb && xkb.variants) || {})[first] || [];
  return [{ value: "", label: "Standard" }].concat(own);
}

// The rows' lists that are facts about this machine, by the name a field
// gives in place of its options.
function inputOptions(name, ctx) {
  const c = ctx || ({});
  const screens = (c.screens || []).map((n) => ({ value: n, label: n }));
  if (name === "xkbLayouts") return (c.xkb && c.xkb.layouts) || [];
  if (name === "xkbVariants") return variantOptions(c.xkb, c.layout);
  // the turns, and the flips hyprland takes for these (it stops at 6)
  if (name === "transforms") return transformOptions().concat([
    { value: 4, label: "Flipped" }, { value: 5, label: "Flipped, 90\u00b0" }, { value: 6, label: "Flipped, 180\u00b0" }]);
  if (name === "touchScreens") return [{ value: "[[Auto]]", label: "Automatic" }].concat(screens);
  if (name === "tabletScreens")
    return [{ value: "", label: "Every screen" }, { value: "current", label: "The focused screen" }].concat(screens);
  return [];
}

// What is plugged in, from `hyprctl devices -j`, by the groups above. A
// mouse reports keyboard and control interfaces of its own and a keyboard
// its media keys, so those are left out, and a name's -1 copy with them:
// the header is to say "your G502 is here", not to list endpoints.
function inputDevices(json) {
  let d = null;
  try { d = JSON.parse(String(json || "")); } catch (e) { d = null; }
  const out = { keyboard: [], mouse: [], touchpad: [], touch: [], tablet: [] };
  if (!d) return out;
  const noise = /keyboard|consumer-control|system-control|power-button|sleep-button|video-bus|-avrcp|headset|adapter/;
  const add = (list, name) => {
    const n = String(name || "").replace(/-\d+$/, "");
    if (n !== "" && list.indexOf(n) < 0) list.push(n);
  };
  const kbs = d.keyboards || [];
  const main = kbs.filter((k) => k.main);
  for (const k of (main.length ? main : kbs)) if (!noise.test(k.name) || main.length) add(out.keyboard, k.name);
  // a keyboard's own pointer interface (a G515's -mouse) is not a mouse
  const ofKeyboard = (n) => kbs.some((k) => !noise.test(k.name) && n.indexOf(k.name + "-") === 0);
  for (const m of d.mice || []) {
    if (/touchpad|trackpad/i.test(m.name)) add(out.touchpad, m.name);
    else if (!noise.test(m.name) && !ofKeyboard(m.name)) add(out.mouse, m.name);
  }
  for (const t of d.touch || []) add(out.touch, t.name);
  for (const t of (d.tablets || []).concat(d.tabletTools || [])) add(out.tablet, t.name || t.type);
  return out;
}

function inputDeviceText(devices, group) {
  const g = INPUT_GROUPS.find((x) => x.id === group);
  if (!g || !g.devices) return "";
  const list = (devices || {})[group] || [];
  return list.length ? list.join(", ") : "none connected";
}

// Whether xkb knows a layout ("us", "us,de") and a variant for it. A layout
// it does not know is not refused by hyprland — the keyboard just stops
// following the file — so the panel refuses it instead. With xkb's list not
// read (yet), everything passes: no list is not a reason to lock you out.
function inputCheck(xkb, field, value, layout) {
  const known = (xkb && xkb.layouts) || [];
  if (known.length === 0) return "";
  const parts = String(value || "").split(",").map((p) => p.trim());
  if (field === "kb_layout") {
    for (const p of parts)
      if (p === "" || !known.some((l) => l.value === p)) return "xkb has no layout called “" + p + "”.";
    return "";
  }
  if (field === "kb_variant") {
    const layouts = String(layout || "").split(",").map((p) => p.trim());
    for (let i = 0; i < parts.length; ++i) {
      if (parts[i] === "") continue;
      const own = (xkb.variants || {})[layouts[i] || layouts[0]] || [];
      if (!own.some((v) => v.value === parts[i]))
        return "“" + (layouts[i] || layouts[0]) + "” has no variant called “" + parts[i] + "”.";
    }
    return "";
  }
  return "";
}
