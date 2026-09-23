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
// The division of labour with Oracle.qml is the one every layer in this shell
// uses: the QML file owns the state and the wires out to the rest of the
// shell, this file owns the arithmetic and the strings.

// A spec that HOLDS something. An action is a button and an info row is a
// readout; neither has a value to store, to default, to reset or to compare,
// and every pass over the schema has to skip both. One predicate rather than
// a growing list of `type !== "action" && type !== "info"` in six places.
function stored(spec) {
  return spec.type !== "action" && spec.type !== "info";
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
    for (let i = 0; i < opts.length; ++i)
      if (opts[i].value === v) return v;
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
