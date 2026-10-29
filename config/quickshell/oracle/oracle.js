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
.pragma library
// ONE COPY FOR THE WHOLE SHELL: without the pragma every component that
// imports this file evaluated all 1,700 lines of it again — 30 ms of each
// oracle page change (qmlprofiler, 2026-10-09). It needs nothing of QML's.

function stored(spec) {
  return spec.type !== "action" && spec.type !== "info" && spec.type !== "arrange" && spec.type !== "sample";
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
  // a color: "#rrggbb", lower case, or "" for none of its own (the theme's)
  if (spec.type === "color") {
    const c = String(v === null || v === undefined ? "" : v).trim().toLowerCase();
    return /^#[0-9a-f]{6}$/.test(c) ? c : "";
  }
  // a key chord, spelled one way: see normChord
  if (spec.type === "chord") return normChord(v);
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

// ── themes ────────────────────────────────────────────────────────────────
// What oracle's Theme row offers, from one line per file in themes/: the
// file's stem, a tab, the file itself flattened onto the line. Zenon first
// and always, because it is the shell's own and is not a file. A file that
// is not JSON is still offered under its stem — Zenon fills in for it when
// worn, and leaving it out would hide the theme you are trying to fix.
// Follow Background second: not a file either, but a theme made from the
// background (picasso/FollowBackground), marked with its glyph (U+F0E09,
// Buck's pick).
const FOLLOW = { value: "follow", label: "Follow Background  \u{F0E09}" };
// Follow Daytime third: the Day theme by daylight, the Night theme after
// dark (Zenon.daylight, chronos/SunClock)
const SUN = { value: "sun", label: "Follow Daytime  \u{F522}" };

// A theme's swatch: [ground, ink, accent] from its colors, "" where a slot
// is missing or not a color; null when it has none of the three.
function themeSwatch(colors) {
  const ok = (v) => typeof v === "string" && /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v) ? v : "";
  if (!colors || typeof colors !== "object") return null;
  const sw = [ok(colors.ground), ok(colors.ink), ok(colors.cyan)];
  return sw.some((v) => v !== "") ? sw : null;
}

function themeOptions(text) {
  const out = [{ value: "zenon", label: "Zenon" }, FOLLOW, SUN];
  for (const line of String(text || "").split("\n")) {
    const tab = line.indexOf("\t");
    if (tab <= 0) continue;
    const stem = line.slice(0, tab);
    if (stem === "zenon" || stem === "follow" || stem === "sun") continue;
    let label = stem;
    let custom = false;
    let swatch = null;
    try {
      const t = JSON.parse(line.slice(tab + 1));
      if (t && typeof t.name === "string" && t.name.trim() !== "") label = t.name.trim();
      custom = !!(t && t.custom === true);
      // one you made yourself is marked with U+F2C0 (Buck's pick,
      // 2026-10-12) — and keeps its light mark beside it: what it was
      // made as is still worth knowing
      if (custom) label += "  \uF2C0";
      // a light theme is marked with a glyph (U+F19E2, Buck's pick), not spelled out
      if (t && t.mode === "light") label += "  \u{F19E2}";
      // its ground, ink and accent, for the swatch the menu draws beside
      // it (user, 2026-10-27: dark from light at a glance); a color the
      // file leaves out is Zenon's, filled in where it is drawn
      swatch = themeSwatch(t && t.colors);
    } catch (e) {
      label = stem + " \u00b7 broken";
    }
    // `custom`: saved here (Follow Background's Save), and so the only kind
    // Delete may remove from the list — never a shipped theme
    const o = custom ? { value: stem, label: label, custom: true } : { value: stem, label: label };
    if (swatch) o.swatch = swatch;
    out.push(o);
  }
  // Zenon's light side straight under Zenon, ahead of the two Follows
  const rank = (o) => o.value === "zenon" ? 0 : o.value === "zenon-light" ? 0.5
    : o.value === "follow" ? 1 : o.value === "sun" ? 2 : 3;
  out.sort((x, y) => rank(x) - rank(y) || x.label.localeCompare(y.label));
  return out;
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
  // nothing to step through: a color is picked, not nudged
  if (spec.type === "color") return v;
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
    // nothing chosen yet (a region picked, no city in it): what to do
    if (v === "" && spec.emptyLabel) return spec.emptyLabel;
    // a monitor placed exactly, by the Arrangement view or by hand
    const at = parsePosition(v);
    if (at) return "Arranged \u00b7 " + at.x + ", " + at.y;
    return String(v);
  }
  if (spec.type === "text") return String(v) === "" ? "—" : String(v);
  if (spec.type === "color") return String(v) === "" ? (spec.none || "none") : String(v);
  if (spec.type === "chord") return normChord(v) === "" ? "off" : chordCaps(v).join(" ");
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
// Any other family is kept whole: " Mono" is part of most monospaced names.
function familyOf(text) {
  const first = String(text || "").split("\n").map((l) => l.trim())
    .filter((l) => l !== "")[0] || "";
  const long = first.replace(/\s+NF[MP]?$/, " Nerd Font");
  return /Nerd Font/.test(long) ? long.replace(/\s+(Propo|Mono)$/, "").trim() : long.trim();
}

// The Font dropdown's families: `fc-list : family` (one face a line, its
// names comma-separated), every family — each by its first name, a Nerd
// Font's without its Propo/Mono cut (familyOf), once, in order. Any face
// will do: the icons are JetBrainsMono Nerd Font's whatever the text is set
// in (morpheus/GlyphFallback writes the fontconfig rule that does it).
function fontFamilies(text) {
  const seen = {};
  const out = [];
  for (const line of String(text || "").split("\n")) {
    const first = line.split(",")[0].trim();
    if (first === "") continue;
    const fam = familyOf(first);
    if (seen[fam]) continue;
    seen[fam] = true;
    out.push(fam);
  }
  return out.sort((a, b) => a.toLowerCase() < b.toLowerCase() ? -1 : a.toLowerCase() > b.toLowerCase() ? 1 : 0);
}

// The CSS weight of a font file, from fontconfig's own scale (`fc-query -f
// '%{weight}'`: Light 50, Regular 80, Medium 100, SemiBold 180, Bold 200),
// snapped to the five oracle offers. "" when it cannot tell.
function cssWeightOf(text) {
  const w = parseFloat(String(text || "").split("\n").map((l) => l.trim()).filter((l) => l !== "")[0]);
  if (isNaN(w)) return "";
  if (w < 65) return "300";
  if (w < 90) return "400";
  if (w < 140) return "500";
  if (w < 190) return "600";
  return "700";
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
  // no natural reason to contain. The bar's "Opacity" is the pill's TRANSPARENCY
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

// The settings drawn inside a row beside its own (`also`: one key or a
// list — the Font row's weight and size), as a list of keys.
function alsoKeys(spec) {
  if (!spec || !spec.also) return [];
  return (Array.isArray(spec.also) ? spec.also : [spec.also]).filter((k) => typeof k === "string" && k !== "");
}

// Whether an `also` setting is drawn: one with `onlyWhen` [key, value]
// only while that key holds that value (the theme's Follow Background tone).
function alsoShown(spec, get) {
  if (!spec) return false;
  const w = spec.onlyWhen;
  if (!w || w.length !== 2) return true;
  return String(get(w[0])) === String(w[1]);
}

// ── A LONG PAGE, IN PARTS (user, 2026-10-27: "oracle feels chaotic, we
// should organize relevant items together") ─────────────────────────────
// For each page laid out here, its headings in order and the settings under
// each. filterSchema puts the rows in this order with `head` on the first of
// each part, which the panel draws as a small heading above it. Only on the
// page itself: a search lists matches as they come, with no headings. A
// setting a page has that is not listed here keeps its place at the end
// (oracle/tests/oracle.js checks there is none).
const PAGES = {
  notify: [
    ["Timing", ["notifTimeout", "notifTimeoutLow", "notifCriticalSticky"]],
    ["Place and size", ["notifPosition", "notifMaxVisible", "notifWidth", "notifMaxWidth", "notifMinHeight",
                        "notifMaxHeight", "notifCaptureWidth", "notifLift", "notifSpacing", "notifPadding"]],
    ["Look", ["notifIcons", "notifIconSize", "notifFontSize", "notifTextAlign", "notifMarkup", "notifBgOpacity",
              "notifTitleInk", "notifBodyInk", "notifAccent", "notifGlow", "notifGlowReach"]],
    ["Arrival", ["notifAnimStyle", "notifSlide", "notifAnimSpeed"]],
    ["Quiet", ["notifSilent", "notifFocusTimers", "notifQuietFullscreen", "notifQuietHours", "notifQuietFrom", "notifQuietTo"]],
    ["History", ["notifHistoryCap", "notifTrackMusic", "notifBellAlways"]]
  ],
  bar: [
    ["Place", ["barPosition", "barMonitor", "barReserveSpace", "barAutohide", "barWindowGap"]],
    ["Size", ["barSlot", "barTextSize", "barGap", "barPadBar", "barPadModule"]],
    ["Look", ["barOpacity", "barBlur", "barTooltips"]],
    ["Modules", ["showWorkspaces", "showClock", "showNotifications", "showUpdates", "showNetwork", "showCpu",
                 "showGpu", "showMemory", "showVolume", "showNowPlaying", "showStatus", "showHermes", "showTray"]]
  ],
  menu: [
    ["Size", ["menuWidth", "menuRowHeight"]],
    ["Entries", ["menuShowFiles", "menuShowPackages", "menuShowApps", "menuShowTrash", "menuShowBackground",
                 "menuShowDisplay", "menuShowNote"]],
    ["Home", ["menuShowHome", "menuShowHidden", "menuHomePlaces", "menuHomeRemember"]],
    ["Recent places", ["menuShowRecent", "menuRecentCount"]]
  ],
  idle: [
    ["Away", ["idleEnabled", "idleLockSecs", "idleKeyboardSecs", "idleLightDevices", "idleInhibitPlayback"]],
    ["Lock screen", ["lockHideCursor", "lockShade", "lockFrost", "lockFailLimit", "lockWidgetMonitor",
                     "lockClockSize", "lockDateSize", "lockFieldWidth"]]
  ],
  // hyprland's own rows (HYPR_FIELDS, "hl:<name>") are added to their
  // parts by hyprPlace, after what is listed here
  windows: [
    ["Gaps and borders", ["hyprGapsOut", "hyprGapsIn", "hyprSpecialGaps", "hyprBorder"]],
    ["Resizing", ["hyprResizeBorder"]],
    ["Snapping", []],
    // Keyboard & mouse's Window focus here too (its alsoIn), with what
    // the windows it leaves look like
    ["Focus", ["input:follow_mouse", "hyprDimInactive", "hyprInactiveOpacity"]],
    ["Terminal swallowing", []],
    ["Apps not responding", []],
    ["Rules and startup", ["infoWindowRules", "infoStartup"]]
  ],
  // the Windows page's tiling, and every layout's own (2026-10-29)
  tiling: [
    ["Layout", ["hyprLayout"]],
    ["Dwindle", []],
    ["Master", []],
    ["Scrolling", []],
    ["Window groups", []],
    ["Tabs", []]
  ],
  workspaces: [
    ["Switching", ["workspaceStrip"]],
    ["Screens", []],
    ["Layouts", []]
  ],
  wineffects: [
    ["Blur", []],
    ["Glass", []],
    ["Shadow", []],
    ["Glow", []],
    ["Corners", []],
    ["Motion blur", []]
  ],
  // the map first, under no heading (WorldMap.qml)
  datetime: [
    ["", ["timeMap"]],
    ["Time zone", ["tz:region", "infoTimeNow"]],
    ["Clock", ["clock24h", "clockSeconds"]],
    ["Setting the clock", ["tz:ntp", "tz:localRtc"]]
  ],
  time: [
    ["Weather", ["weatherEnabled", "weatherFahrenheit", "weatherRefreshMins", "weatherStaleMins"]],
    ["Calendar", ["calRemindLead", "calSyncMins"]]
  ],
  motion: [
    ["Animations", ["motionScale", "hyprAnimations", "hyprWobble", "cursorSlide"]],
    ["Scrolling", ["elasticScroll", "scrollbarAutohide"]],
    ["Arrival", ["arrivalEnabled", "arrivalDuration", "arrivalDeadline"]]
  ],
  surfaces: [
    // the sample of them all first, under no heading (OracleWindow's SurfaceSample)
    ["", ["surfacesSample"]],
    ["Shape", ["cornerRadius", "barMaxWidth", "barScreenPad"]],
    ["Opacity", ["panelOpacity", "menuOpacity", "scrollFrost", "frostStyle"]],
    ["Shadows", ["shadowStrength", "menuShadows", "hyprShadows"]]
  ]
};

// a page's parts, or null for a page with none (the tests read it)
function pageLayout(section) { return PAGES[section] || null; }

// rows of one page in its PAGES order, the first of each part carrying
// `head` (a copy: the schema's own entries are left alone)
function laidOut(rows, page) {
  const at = {}, heads = {};
  let n = 0;
  for (const [head, keys] of page) {
    keys.forEach((k, i) => { at[k] = n++; if (i === 0) heads[k] = head; });
  }
  const placed = rows.map((r, i) => ({ r: r, o: r.key in at ? at[r.key] : n + i }));
  placed.sort((a, b) => a.o - b.o);
  const out = [];
  const seen = {};
  for (const p of placed) {
    const h = heads[p.r.key];
    // a head only once, on the first of its part that is here
    out.push(h && !seen[h] ? Object.assign({}, p.r, { head: h }) : p.r);
    if (h) seen[h] = true;
  }
  return out;
}

function filterSchema(schema, section, query) {
  const out = [];
  const q = String(query || "").trim();
  // `alsoIn`: a second section shows the same row (Accent color, under
  // Theme and again under Background) — one setting, counted in its own.
  // There it stands after the row `alsoAfter` names, or last.
  const guests = [];
  for (let i = 0; i < schema.length; ++i) {
    const s = schema[i];
    if (q === "" && s.section !== section && s.alsoIn === section && !s.within) {
      guests.push(s);
      continue;
    }
    // A query searches the WHOLE panel, not the section you happen to be
    // standing in. Looking for a setting is the case where you do not know
    // which section it is filed under — that is why you are typing.
    if (q === "" && s.section !== section) continue;
    // drawn inside another row (the Font row's weight): never a row itself
    if (s.within) continue;
    if (!matches(s, q)) continue;
    out.push(s);
  }
  for (const g of guests) {
    const at = out.findIndex((r) => r.key === g.alsoAfter);
    if (at < 0) out.push(g); else out.splice(at + 1, 0, g);
  }
  return q === "" && PAGES[section] ? laidOut(out, PAGES[section]) : out;
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
// Whether the settings file can be read at all: empty is fine (nothing set
// yet), a JSON object is; anything else — a hand edit's stray comma — is
// not, and must not be taken for "everything at its default" (audit,
// 2026-10-27: Reload then reset every setting, and the next save wrote the
// defaults over the file).
function parses(text) {
  const t = String(text || "").trim();
  if (t === "") return true;
  try { const j = JSON.parse(t); return !!j && typeof j === "object" && !Array.isArray(j); } catch (e) { return false; }
}

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

// ── THE TOOLS THE SHELL CALLS OUT TO ──────────────────────────────────────
// Health's Tools row, and its fold-out. CORE: missing, something you use
// every day breaks (red). The rest are one feature each, or installed the
// first time a feature asks (calypso's backends, picasso's Make, ceres'
// flatpak) — listed, never red. `pkg` is the Arch package; `aur` marks one
// pacman cannot install. oracle/doctor.sh only answers which are on PATH.
//
// PREBUILT, ALWAYS (user, 2026-10-18: "speed and convenience are key"):
// the official repos, or an AUR package that repacks an upstream binary
// (-bin, 1password-cli). The one exception is paru itself: its author's own
// package builds from source, and paru-bin (another maintainer) lags it and
// was flagged out of date (2026-10-18) — a stale binary against a newer
// libalpm is a broken package manager. Building realesrgan and rembg's dependencies took
// far too long, so picasso's cut-out is its own (picasso/bin/cutout.py) on the
// repos' onnxruntime. `builds` says why a tool has no prebuilt package at all
// — none now, and the panel says so before one is ticked. `module` is a
// python module, not a command: doctor.sh asks python3 to import it.
// `installed` is a package with no command at all (a Proton build lands in
// steam's compatibility tools): doctor.sh asks pacman whether it is there.
const TOOLS = [
  { name: "hyprctl", pkg: "hyprland", core: true, why: "the compositor: windows, monitors, dispatches" },
  { name: "fd", pkg: "fd", core: true, why: "artemis' index, plato's finder" },
  { name: "fzf", pkg: "fzf", core: true, why: "artemis and plato search" },
  { name: "rg", pkg: "ripgrep", core: true, why: "content search" },
  { name: "jq", pkg: "jq", core: true, why: "JSON from helper scripts" },
  { name: "qalc", pkg: "libqalculate", core: true, why: "metis, the calculator" },
  { name: "magick", pkg: "imagemagick", core: true, why: "picasso edits, thumbnails, window shots" },
  { name: "grim", pkg: "grim", core: true, why: "screenshots" },
  { name: "slurp", pkg: "slurp", core: true, why: "picking a region to capture" },
  { name: "wl-copy", pkg: "wl-clipboard", core: true, why: "copying" },
  { name: "wl-paste", pkg: "wl-clipboard", core: true, why: "pasting" },
  { name: "cliphist", pkg: "cliphist", core: true, why: "folio, the clipboard history" },
  { name: "inotifywait", pkg: "inotify-tools", core: true, why: "watching files and directories" },
  { name: "playerctl", pkg: "playerctl", core: true, why: "media keys and now playing" },
  { name: "pactl", pkg: "libpulse", core: true, why: "volume and audio devices" },
  { name: "wpctl", pkg: "wireplumber", core: true, why: "audio streams" },
  { name: "python3", pkg: "python", core: true, why: "helper scripts, delphi and calypso backends" },
  { name: "nvim", pkg: "neovim", core: true, why: "plato's editor" },
  // core since 2026-10-18 (user: "make this run out of the box"); the
  // installer also fetches its model
  { name: "onnxruntime", pkg: "python-onnxruntime-cpu", module: true, core: true, why: "picasso: cut out the subject" },
  { name: "kitty", pkg: "kitty", core: true, why: "the terminal everything opens in" },
  { name: "git", pkg: "git", core: true, why: "delphi" },
  { name: "fc-list", pkg: "fontconfig", core: true, why: "alexandria and the font pickers" },
  { name: "gio", pkg: "glib2", core: true, why: "opening files, the trash" },
  { name: "udisksctl", pkg: "udisks2", core: true, why: "mounting disks in terminus" },
  { name: "paru", pkg: "paru", aur: true, why: "ceres: AUR packages and updates" },
  { name: "flatpak", pkg: "flatpak", why: "ceres' store, once opted in" },
  { name: "node", pkg: "nodejs", why: "the test suite (Health's Tests row)" },
  { name: "exiftool", pkg: "perl-image-exiftool", why: "picture details in picasso" },
  { name: "ffprobe", pkg: "ffmpeg", why: "video details" },
  { name: "ffmpeg", pkg: "ffmpeg", why: "video frames and covers" },
  { name: "tesseract", pkg: "tesseract", why: "copying text out of a picture" },
  { name: "gh", pkg: "github-cli", why: "delphi's GitHub sign-in" },
  { name: "bw", pkg: "bitwarden-cli", why: "calypso's Bitwarden backend" },
  { name: "op", pkg: "1password-cli", aur: true, why: "calypso's 1Password backend" },
  { name: "realesrgan-ncnn-vulkan", pkg: "realesrgan-ncnn-vulkan-bin", aur: true, why: "picasso: upscale" },
  { name: "bandwhich", pkg: "bandwhich", why: "zeus' network view" },
  { name: "pkexec", pkg: "polkit", why: "anything that asks for your password" },
  // no command: a theme. GTK 3 takes the shell's colors only through it
  // (morpheus/ThemeSync, scripts/gtkscheme.sh)
  { name: "adw-gtk-theme", pkg: "adw-gtk-theme", installed: true, why: "GTK 3 apps in the shell's colors" },
  // qt6ct's platform theme is how Qt apps (the screen-share picker, the
  // polkit agent) wear the shell's colors: ThemeSync writes its scheme,
  // base.lua sets QT_QPA_PLATFORMTHEME
  { name: "qt6ct", pkg: "qt6ct", why: "Qt apps in the shell's colors" },
  { name: "proton-wineland-bin", pkg: "proton-wineland-bin", installed: true, aur: true, why: "Proton for Steam, with Wayland" },
];

// doctor.sh's list: a module as py:NAME, a package as pkg:NAME, answered
// as NAME
function toolNames() { return TOOLS.map((t) => (t.module ? "py:" : t.installed ? "pkg:" : "") + t.name).join(" "); }

// The tools as PACKAGES, one each: wl-copy and wl-paste are one
// wl-clipboard, ffmpeg and ffprobe one ffmpeg — a box to tick per package,
// never two for the same install. Needed if any of its tools is; there if
// all of them are. In the order the tools come.
function toolPackages(tools) {
  const out = [], at = {};
  for (const t of tools || []) {
    let p = at[t.pkg];
    if (!p) {
      p = at[t.pkg] = { pkg: t.pkg, aur: !!t.aur, builds: t.builds || "", core: false, have: true, names: [], whys: [] };
      out.push(p);
    }
    p.core = p.core || !!t.core;
    p.have = p.have && t.have !== false;
    p.names.push(t.name);
    if (p.whys.indexOf(t.why) < 0) p.whys.push(t.why);
  }
  for (const p of out) { p.why = p.whys.join("; "); delete p.whys; }
  return out;
}

// the commands that install what is missing, one per line. With paru there,
// one line: it takes repo and AUR packages alike. Without it, pacman for the
// repo ones, then paru itself (it is in the AUR, so makepkg), then the rest.
function installLines(missing) {
  const uniq = (ts) => ts.map((t) => t.pkg).filter((p, i, a) => a.indexOf(p) === i);
  const ms = missing || [];
  if (!ms.length) return [];
  if (!ms.some((t) => t.name === "paru")) return ["paru -S " + uniq(ms).join(" ")];
  const repo = uniq(ms.filter((t) => !t.aur)), aur = uniq(ms.filter((t) => t.aur && t.name !== "paru"));
  const out = [];
  if (repo.length) out.push("sudo pacman -S " + repo.join(" "));
  out.push("git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si");
  if (aur.length) out.push("paru -S " + aur.join(" "));
  return out;
}

// ── THE CHECKUP ───────────────────────────────────────────────────────────
// oracle/doctor.sh prints `key<TAB>value` lines; this turns them into the
// Health section's rows, each a short line and a level: "ok" reads green,
// "warn" yellow, "bad" red. `baselineKb` is the resident size a
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

  // ── AND WHAT TO DO ABOUT IT (user, 2026-10-27: "Health that offers
  // fixes") — `fix` on a reading that wants one: the button's word and what
  // it does (OracleWindow.healthFix). Missing tools have theirs in the fold.
  const RESTART = { label: "Restart", act: "restart" };
  const probes = list("probes");
  rows.probes = probes.length
    ? { text: probes.length + " left in " + probes.join(", "), level: "warn",
        fix: { label: "Show", act: "open", files: probes } }
    : { text: "none", level: "ok" };

  const stale = list("stale");
  rows.stale = stale.length
    ? { text: stale.map((p) => p.replace(/.*\//, "")).join(", ") + " \u2014 restart to be sure", level: "warn", fix: RESTART }
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
    // grown: a fresh start gives it back
    if (rows.memory.level !== "ok") rows.memory.fix = RESTART;
  }

  const held = list("held"), spawned = list("spawned");
  rows.pollers = {
    text: held.length + " held open" + (spawned.length ? " · spawned in 2s: " + counted(spawned) : " · nothing spawned in 2s"),
    // The known pollers fire once a second or two; five in two seconds is
    // the shape of a timer somebody forced on.
    level: spawned.length > 4 ? "warn" : "ok",
    detail: counted(held),
  };

  // Qt, quickshell and Hyprland as they are now, against the stamp the last
  // clean preflight left (scripts/stack.sh). An update is when this shell
  // breaks — a Qt from [testing] ahead of quickshell, Hyprland's Lua — so a
  // change since the stamp asks for a preflight before anything is opened.
  const parts = (k) => (f[k] || "").split(",").map((x) => x.trim()).filter((x) => x !== "");
  const now = parts("stack"), then = parts("stamp");
  const short = (p) => p.replace(/^(\S+) (?:\d+:)?([^-\s]+).*$/, "$1 $2");
  if (!now.length) rows.stack = { text: "unreadable", level: "warn" };
  else if (!then.length) rows.stack = { text: "no clean preflight on record \u2014 run scripts/preflight.sh", level: "warn",
                                        fix: { label: "Run preflight", act: "preflight" } };
  else {
    const was = {};
    for (const p of then) was[p.split(" ")[0]] = p;
    const moved = now.filter((p) => was[p.split(" ")[0]] !== p)
      .map((p) => { const o = was[p.split(" ")[0]]; return (o ? short(o) : p.split(" ")[0] + " (new)") + " \u2192 " + short(p).split(" ")[1]; });
    rows.stack = moved.length
      ? { text: "updated since the last clean preflight: " + moved.join(", ") + " \u2014 run scripts/preflight.sh", level: "warn",
          fix: { label: "Run preflight", act: "preflight" } }
      : { text: now.filter((p) => /^(quickshell|qt6-base|hyprland) /.test(p)).map(short).join(" \u00b7 ") + " \u00b7 preflight passed on these", level: "ok" };
  }

  // Hyprland's config errors and deprecations (doctor.sh hyprerr/hyprdep,
  // JSON arrays of strings). An empty configerrors still answers [""].
  const strings = (k) => {
    try { const a = JSON.parse(f[k] || "[]"); return Array.isArray(a) ? a.map(String).filter((x) => x.trim() !== "") : []; }
    catch (e) { return null; }
  };
  const hErr = strings("hyprerr"), hDep = strings("hyprdep");
  if (hErr === null || hDep === null) rows.hypr = { text: "unreadable", level: "warn" };
  else if (hErr.length) rows.hypr = { text: hErr.length + (hErr.length === 1 ? " config error" : " config errors"), level: "bad",
                                      detail: hErr.concat(hDep).join("\n") };
  else if (hDep.length) rows.hypr = { text: hDep.length + " deprecated \u2014 works now, gone in a later Hyprland", level: "warn",
                                      detail: hDep.join("\n") };
  else rows.hypr = { text: "no config errors \u00b7 nothing deprecated", level: "ok" };

  // name:1/0 per tool, in TOOLS' order; the row carries the whole list for
  // its fold-out (ToolsPanel), missing ones first
  const have = {};
  for (const x of list("tools")) { const k = x.lastIndexOf(":"); if (k > 0) have[x.slice(0, k)] = x.slice(k + 1) === "1"; }
  if (!Object.keys(have).length) rows.tools = { text: "not checked", level: "warn", list: [] };
  else {
    const all = TOOLS.filter((t) => t.name in have).map((t) => Object.assign({ have: have[t.name] }, t));
    const gone = all.filter((t) => t.core && !t.have), extras = all.filter((t) => !t.core && !t.have);
    const core = all.filter((t) => t.core).length;
    rows.tools = {
      text: gone.length ? "missing: " + gone.map((t) => t.name).join(", ")
        : "All " + core + " present" + (extras.length ? " \u00b7 " + extras.length + " optional not installed" : ""),
      level: gone.length ? "bad" : "ok",
      list: gone.concat(extras, all.filter((t) => t.have)),
      install: installLines(gone.concat(extras)),
    };
  }

  const errors = parseInt(f.errors, 10) || 0;
  const warnings = parseInt(f.warnings, 10) || 0;
  rows.log = {
    text: errors + (errors === 1 ? " error" : " errors") + " · " + warnings + (warnings === 1 ? " warning" : " warnings"),
    level: errors > 0 ? "bad" : "ok",
    detail: f.lasterror || "",
  };
  if (errors > 0) rows.log.fix = { label: "Open the log", act: "log" };
  return rows;
}

// What the checkup reads memory against: the median of the sizes fresh
// starts settled at (morpheus/LagWatch writes settle.json two minutes after
// a start with nothing of the shell's own opened), or `fallback` until there
// is one. The median, so one start that happened to load a big font or a
// background change does not move the line.
function settledBaseline(text, fallback) {
  let list = [];
  try { list = JSON.parse(String(text || "")).kb || []; } catch (e) { return fallback; }
  const kb = list.map((e) => Number(e && e.kb)).filter((n) => n > 0).sort((a, b) => a - b);
  if (!kb.length) return fallback;
  const mid = kb.length >> 1;
  return kb.length % 2 ? kb[mid] : Math.round((kb[mid - 1] + kb[mid]) / 2);
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
// a line break escaped too: raw inside "…" it is a Lua syntax error, and the
// whole file (an imported one, say) failed to load
function luaString(s) {
  return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
    .replace(/\n/g, "\\n").replace(/\r/g, "\\r") + "\"";
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
  // `preferred` (optional): what the row holds before anybody chooses,
  // pinned, when it is installed. Since 2026-10-11 (user) every kind starts
  // at System — for directories, archives, text, images and fonts the
  // system's answer is this shell's own: terminus, plato, picasso and
  // alexandria write .desktop entries claiming those types. Video is the
  // one exception (2026-10-21, user): argus claims video too, so it could
  // be the system's answer, and it is an editor, not a player — mpv is.
  { id: "files", label: "Directories", probe: "inode/directory",
    alias: "file manager folder directory terminus",
    types: ["inode/directory"],
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
    alias: "movies player video mpv", preferred: "mpv.desktop",
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

// ZENWORKS' VERSION, as About says it (user, 2026-10-25): the reader
// (Oracle's versionProc) prints "pkg <pacman's version>" for the installed
// one, or "git <git describe --tags --long --dirty>" for a working copy.
//   pkg 0.0.7-2                  → "0.0.7-2"
//   git 0.0.7-0-g528ee7b         → "0.0.7 (working copy)"
//   git 0.0.7-3-g1a2b3c4-dirty   → "0.0.7 + 3 commits, changed (working copy)"
// "" when nothing could be said.
function versionText(out) {
  var s = String(out || "").trim();
  var m = /^pkg\s+(\S+)$/.exec(s);
  if (m) return m[1];
  m = /^git\s+(.+?)-(\d+)-g[0-9a-f]+(-dirty)?$/.exec(s);
  if (!m) return "";
  var n = Number(m[2]), more = [];
  if (n > 0) more.push(n + (n === 1 ? " commit" : " commits"));
  var tail = (more.length ? " + " + more.join("") : "") + (m[3] ? (more.length ? ", changed" : " + changes") : "");
  return m[1] + tail + " (working copy)";
}

// What a machine with no defaults.lua starts with: kitty, which Zenworks
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
    "-- Written by oracle's Default apps section, and read back by it: change",
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
// and choices are hyprland's own (src/config/values/ConfigValues.cpp, 0.56),
// except five defaults that are the user's own settings (user, 2026-10-17):
// repeat delay 200 and rate 35, a flat mouse at -0.6, and focus on close
// going back to the last window used.
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
  { key: "repeat_delay", group: "keyboard", def: 200, type: "int", min: 0, max: 2000, step: 25, unit: "ms",
    label: "Repeat delay", alias: "keyboard key repeat delay hold",
    help: "How long a key is held before it starts repeating." },
  { key: "repeat_rate", group: "keyboard", def: 35, type: "int", min: 0, max: 200, step: 1, unit: "/s",
    label: "Repeat rate", alias: "keyboard key repeat rate speed",
    help: "How many times a second a held key repeats. 0 never repeats." },
  { key: "numlock_by_default", group: "keyboard", def: false, type: "bool",
    label: "Num Lock on", alias: "keyboard numlock number pad numpad",
    help: "The number pad types numbers from the start." },
  { key: "resolve_binds_by_sym", group: "keyboard", def: false, type: "bool",
    label: "Binds follow the layout", alias: "keyboard binds shortcuts layout symbol",
    help: "With several layouts, a shortcut on a letter follows where that letter is in the layout you are typing in, not where it is on the first one." },

  // mouse
  { key: "accel_profile", group: "mouse", def: "flat", type: "enum", segments: true, art: "accel",
    options: [{ value: "", label: "Device default" }, { value: "adaptive", label: "Adaptive" },
              { value: "flat", label: "Flat" }, { value: "custom", label: "Custom" }],
    label: "Acceleration", alias: "mouse pointer acceleration accel profile flat adaptive",
    help: "Adaptive moves the pointer further the faster you move the mouse; Flat moves it the same distance however fast, the way most players want it. Custom takes its curve from Scroll curve." },
  { key: "sensitivity", group: "mouse", def: -0.6, type: "real", min: -1, max: 1, step: 0.05,
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
  { key: "scroll_factor", group: "scroll", def: 1, type: "real", min: 0, max: 5, step: 0.05, unit: "x",
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
  // Click to focus by default (user, 2026-10-27: "disable focus on
  // hover"), and shown under Windows as well (alsoIn: one setting, two pages)
  { key: "follow_mouse", group: "focus", def: 0, type: "enum", segments: true, alsoIn: "windows",
    options: [{ value: 0, label: "Click" }, { value: 1, label: "Follow pointer" },
              { value: 2, label: "Pointer only" }, { value: 3, label: "Separate" }],
    label: "Window focus", alias: "window keyboard focus follows mouse pointer click hover",
    help: "Click: a window is focused when you click it. Follow pointer: the window under the pointer gets the keyboard. Pointer only: hovering sends the pointer there but the keyboard stays until you click. Separate: the keyboard never follows the pointer at all." },
  { key: "follow_mouse_threshold", group: "focus", def: 0, type: "real", min: 0, max: 200, step: 1, unit: "px",
    label: "Pointer travel before focus", alias: "focus follow mouse threshold distance",
    help: "How far the pointer has to move before the window under it is focused." },
  { key: "follow_mouse_shrink", group: "focus", def: 0, type: "int", min: 0, max: 300, step: 1, unit: "px",
    label: "Focus dead zone", alias: "focus follow mouse shrink gap dead zone",
    help: "Shrinks what counts as over a window, so the gaps between windows change nothing. Only while focus follows the pointer." },
  { key: "mouse_refocus", group: "focus", def: true, type: "bool",
    label: "Refocus on any movement", alias: "focus mouse refocus hover",
    help: "Off, the pointer has to cross into another window to focus it; moving inside the one you are over does nothing." },
  { key: "focus_on_close", group: "focus", def: 2, type: "enum",
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
  { key: "touchpad_scroll_factor", group: "touchpad", def: 1, type: "real", min: 0, max: 5, step: 0.05, unit: "x",
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
    if (HYPR_RETIRED.indexOf(m[1]) >= 0) continue;
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

// ── ABOUT THIS COMPUTER ───────────────────────────────────────────────────
// oracle/machine.py's JSON, read into the About section's fold-out: the
// sections as it gives them ({ name, rows: [{ k, v, frac?, note? }] }),
// the distro's logo glyph, a line for the row itself (`summary`) and the
// model under the title. `qs` is the first line of `qs --version`, which
// goes into Desktop ahead of Qt. machine.py replaced fastfetch 2026-10-25.

// Nerd Font logos (nf-linux-*), by os-release ID — and ID_LIKE after it, so
// an Arch derivative without a logo of its own wears Arch's
const DISTRO_GLYPHS = {
  arch: "", archarm: "", artix: "", endeavouros: "",
  manjaro: "", garuda: "", cachyos: "", debian: "",
  ubuntu: "", linuxmint: "", pop: "", elementary: "",
  fedora: "", rhel: "", centos: "", rocky: "",
  almalinux: "", opensuse: "", "opensuse-tumbleweed": "",
  "opensuse-leap": "", gentoo: "", nixos: "", void: "",
  alpine: "", slackware: "", kali: "", zorin: ""
};

function readComputer(json, qsVersion) {
  let d = null;
  try { d = JSON.parse(String(json || "")); } catch (e) { d = null; }
  if (!d || typeof d !== "object" || !Array.isArray(d.sections)) return { ok: false, sections: [], rows: [] };
  const sections = d.sections
    .filter((s) => s && s.name && Array.isArray(s.rows))
    .map((s) => ({ name: String(s.name), rows: s.rows.filter((r) => r && r.k && String(r.v || "").trim() !== "") }))
    .filter((s) => s.rows.length > 0);
  const qs = String(qsVersion || "").replace(/^Quickshell\s+/, "").replace(/\s*\(.*$/, "").trim();
  if (qs) {
    let desk = sections.find((s) => s.name === "Desktop");
    if (!desk) { desk = { name: "Desktop", rows: [] }; sections.splice(Math.min(1, sections.length), 0, desk); }
    const at = desk.rows.findIndex((r) => r.k === "Qt");
    desk.rows.splice(at < 0 ? desk.rows.length : at, 0, { k: "Quickshell", v: qs });
  }
  const os = d.os || {};
  const ids = [os.id].concat(String(os.idLike || "").split(/\s+/)).filter((x) => !!x);
  let glyph = "";
  for (const id of ids) if (DISTRO_GLYPHS[id]) { glyph = DISTRO_GLYPHS[id]; break; }
  const rows = [];
  for (const s of sections) for (const r of s.rows) rows.push(r);
  return {
    ok: rows.length > 0,
    glyph: glyph,
    title: os.name || "",
    model: String(d.model || ""),
    sections: sections,
    rows: rows,
    summary: String(d.summary || "")
  };
}

// the lot as plain text, for Copy: what a bug report or a forum post wants
function computerText(c) {
  if (!c || !c.ok) return "";
  const out = [c.title + (c.model ? " \u2014 " + c.model : "")];
  for (const s of c.sections) {
    out.push("", s.name);
    for (const r of s.rows) out.push("  " + r.k + ": " + r.v + (r.note ? " (" + r.note + ")" : ""));
  }
  return out.join("\n");
}

// ── SHORTCUTS ─────────────────────────────────────────────────────────────
// hypr/lua/binds.lua is the list: one `bind(id, keys, label, action, opts)` a
// line, under `-- NAME` headings, the keys written there being each one's
// default. hypr/lua/keys.lua — written here, read back — names only the ones
// moved off their default (`id = "SUPER + K"`), "" for one turned off; it
// reads like defaults.lua, so parseDefaultsLua reads it.

// the binds, in the file's order: { id, chord, label, group }
function parseBindsLua(text) {
  const out = [];
  let group = "";
  const re = /^\s*bind\(\s*"([A-Za-z_]\w*)"\s*,\s*"([^"]*)"\s*,\s*"((?:[^"\\]|\\.)*)"/;
  for (const line of String(text || "").split("\n")) {
    const h = /^--\s*([A-Z][A-Z &]+)\s*$/.exec(line);
    if (h) { group = h[1].trim(); continue; }
    const m = re.exec(line);
    if (m) out.push({ id: m[1], chord: normChord(m[2]), label: m[3].replace(/\\(.)/g, "$1"), group: group });
  }
  return out;
}

// "MISC" → "Misc", "QS" stays an initialism
function bindGroupLabel(g) {
  const named = { QS: "Shell", MISC: "General" };
  if (named[g]) return named[g];
  return g.charAt(0) + g.slice(1).toLowerCase();
}

// ── WAKE ──
// What brings screens turned off back: hypr/lua/wake.lua, `wake = "key"`
// (any key) or "mouse" (a mouse move too): Display's "Wake by" (user,
// 2026-10-20), for idle and binds.lua's screensOff alike. base.lua reads
// it, so it holds from login; socordia follows it; key wake is always on.
// "mouse" unless the file says "key" (the default since 2026-10-21).
function parseWakeLua(text) {
  return parseDefaultsLua(text).wake === "key" ? "key" : "mouse";
}
function renderWakeLua(by) {
  return [
    "-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐",
    "-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐",
    "-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘",
    "-- https://github.com/kbuckleys/",
    "",
    "-- WAKE",
    "-- Written by oracle's Display section (Wake by), and read back by it.",
    "-- What turns screens that were turned off, idle or by a bind, back on:",
    "-- \"key\" any key press, \"mouse\" a mouse move or a key press.",
    "",
    "return {",
    "\twake = " + luaString(by === "key" ? "key" : "mouse") + ",",
    "}",
    "",
  ].join("\n");
}

// ── INPUT METHODS ──
// fcitx5, for the languages a keyboard layout cannot type: Input's "Input
// methods" (user, 2026-10-26). hypr/lua/inputmethod.lua `on = true` is
// read by base.lua (the environment apps need) and autostart.lua (fcitx5
// at login); off unless the file says true. Which languages and the switch
// key are fcitx5's own files, ~/.config/fcitx5/profile and config, so its
// configtool and these rows read the same thing.
//
// Never GTK_IM_MODULE or QT_IM_MODULE: on Wayland both push apps off the
// text-input protocol (oracle/tests/inputmethod.js keeps them out).
var IM_BASE = ["fcitx5", "fcitx5-qt", "fcitx5-gtk", "fcitx5-configtool"];
// `im` is fcitx5's name for it, `pkg` what brings it. A row each is too
// many (user, 2026-10-27: "a lot more non-latin languages out there"):
// Input lists the ones you added, and "Add a language" offers the rest.
// m17n's are "m17n_<language>_<method>", from m17n-db's .mim files.
var IM_ENGINES = [
  { im: "pinyin",                  label: "Chinese · Pinyin",            pkg: "fcitx5-chinese-addons" },
  { im: "shuangpin",               label: "Chinese · Shuangpin",         pkg: "fcitx5-chinese-addons" },
  { im: "wbx",                     label: "Chinese · Wubi",              pkg: "fcitx5-chinese-addons" },
  { im: "cangjie",                 label: "Chinese · Cangjie",           pkg: "fcitx5-chinese-addons" },
  { im: "rime",                    label: "Chinese · Rime",              pkg: "fcitx5-rime" },
  { im: "chewing",                 label: "Chinese · Zhuyin",            pkg: "fcitx5-chewing" },
  { im: "jyutping-table",          label: "Cantonese · Jyutping",        pkg: "fcitx5-table-extra" },
  { im: "mozc",                    label: "Japanese · Mozc",             pkg: "fcitx5-mozc" },
  { im: "anthy",                   label: "Japanese · Anthy",            pkg: "fcitx5-anthy" },
  { im: "skk",                     label: "Japanese · SKK",              pkg: "fcitx5-skk" },
  { im: "hangul",                  label: "Korean",                      pkg: "fcitx5-hangul" },
  { im: "unikey",                  label: "Vietnamese · Unikey",         pkg: "fcitx5-unikey" },
  { im: "bamboo",                  label: "Vietnamese · Bamboo",         pkg: "fcitx5-bamboo" },
  { im: "libthai",                 label: "Thai",                        pkg: "fcitx5-libthai" },
  { im: "sayura",                  label: "Sinhala",                     pkg: "fcitx5-sayura" },
  { im: "m17n_am_sera",            label: "Amharic",                     pkg: "fcitx5-m17n" },
  { im: "m17n_ar_translit",        label: "Arabic · Transliteration",    pkg: "fcitx5-m17n" },
  { im: "m17n_hy_kbd",             label: "Armenian",                    pkg: "fcitx5-m17n" },
  { im: "m17n_as_inscript2",       label: "Assamese",                    pkg: "fcitx5-m17n" },
  { im: "m17n_bn_inscript2",       label: "Bengali · InScript",          pkg: "fcitx5-m17n" },
  { im: "m17n_bn_probhat",         label: "Bengali · Probhat",           pkg: "fcitx5-m17n" },
  { im: "m17n_my_kbd",             label: "Burmese",                     pkg: "fcitx5-m17n" },
  { im: "m17n_dv_phonetic",        label: "Dhivehi",                     pkg: "fcitx5-m17n" },
  { im: "m17n_ka_kbd",             label: "Georgian",                    pkg: "fcitx5-m17n" },
  { im: "m17n_gu_inscript2",       label: "Gujarati",                    pkg: "fcitx5-m17n" },
  { im: "m17n_hi_inscript2",       label: "Hindi · InScript",            pkg: "fcitx5-m17n" },
  { im: "m17n_hi_phonetic",        label: "Hindi · Phonetic",            pkg: "fcitx5-m17n" },
  { im: "m17n_iu_phonetic",        label: "Inuktitut",                   pkg: "fcitx5-m17n" },
  { im: "m17n_kn_inscript2",       label: "Kannada",                     pkg: "fcitx5-m17n" },
  { im: "m17n_kk_kbd",             label: "Kazakh",                      pkg: "fcitx5-m17n" },
  { im: "m17n_km_yannis",          label: "Khmer",                       pkg: "fcitx5-m17n" },
  { im: "m17n_lo_kbd",             label: "Lao",                         pkg: "fcitx5-m17n" },
  { im: "m17n_ml_inscript2",       label: "Malayalam · InScript",        pkg: "fcitx5-m17n" },
  { im: "m17n_ml_mozhi",           label: "Malayalam · Mozhi",           pkg: "fcitx5-m17n" },
  { im: "m17n_mr_inscript2",       label: "Marathi",                     pkg: "fcitx5-m17n" },
  { im: "m17n_ne_rom",             label: "Nepali",                      pkg: "fcitx5-m17n" },
  { im: "m17n_or_inscript2",       label: "Odia",                        pkg: "fcitx5-m17n" },
  { im: "m17n_ps_phonetic",        label: "Pashto",                      pkg: "fcitx5-m17n" },
  { im: "m17n_fa_isiri",           label: "Persian",                     pkg: "fcitx5-m17n" },
  { im: "m17n_pa_inscript2-guru",  label: "Punjabi",                     pkg: "fcitx5-m17n" },
  { im: "m17n_sa_inscript2",       label: "Sanskrit",                    pkg: "fcitx5-m17n" },
  { im: "m17n_syrc_phonetic",      label: "Syriac",                      pkg: "fcitx5-m17n" },
  { im: "m17n_ta_tamil99",         label: "Tamil · Tamil99",             pkg: "fcitx5-m17n" },
  { im: "m17n_ta_phonetic",        label: "Tamil · Phonetic",            pkg: "fcitx5-m17n" },
  { im: "m17n_te_inscript2",       label: "Telugu",                      pkg: "fcitx5-m17n" },
  { im: "m17n_bo_ewts",            label: "Tibetan",                     pkg: "fcitx5-m17n" },
  { im: "m17n_ug_kbd",             label: "Uyghur",                      pkg: "fcitx5-m17n" },
  { im: "m17n_ur_phonetic",        label: "Urdu",                        pkg: "fcitx5-m17n" },
  { im: "m17n_ii_phonetic",        label: "Yi",                          pkg: "fcitx5-m17n" },
];

// what "Add a language" offers: every language not added yet, by name
function imAddable(added) {
  const have = added || [];
  return [{ value: "", label: "Choose\u2026" }].concat(IM_ENGINES
    .filter((e) => have.indexOf(e.im) < 0)
    .slice().sort((a, b) => a.label.localeCompare(b.label))
    .map((e) => ({ value: e.im, label: e.label })));
}

// fcitx5's key names. Not Super+Space: that is Cynosure's, and a bind the
// compositor holds never reaches fcitx5.
var IM_KEYS = [
  { value: "Control+space",       label: "Ctrl+Space" },
  { value: "Control+Shift+space", label: "Ctrl+Shift+Space" },
  { value: "Super+Shift+space",   label: "Super+Shift+Space" },
];
var IM_KEY_DEFAULT = "Control+space";

function parseImLua(text) {
  return /\bon\s*=\s*true\b/.test(stripLuaComments(String(text || "")));
}
function renderImLua(on) {
  return [
    "-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐",
    "-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐",
    "-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘",
    "-- https://github.com/kbuckleys/",
    "",
    "-- INPUT METHODS",
    "-- Written by oracle's Input section (Input methods), and read back by it.",
    "-- true: fcitx5 starts at login and apps are told to use it. Which",
    "-- languages it offers is fcitx5's own ~/.config/fcitx5/profile.",
    "",
    "return {",
    "\ton = " + (on ? "true" : "false") + ",",
    "}",
    "",
  ].join("\n");
}

// fcitx5's files are ini: [Section] then key=value. Read as sections in
// file order, each { name, lines } with the lines kept as written, so a
// file written back keeps what these rows do not know about.
function parseIni(text) {
  const out = [{ name: "", lines: [] }];
  for (const raw of String(text || "").split("\n")) {
    const m = /^\s*\[(.*)\]\s*$/.exec(raw);
    if (m) out.push({ name: m[1], lines: [] });
    else out[out.length - 1].lines.push(raw);
  }
  return out;
}
function iniValue(lines, key) {
  for (const l of lines) {
    const m = /^\s*([^#=][^=]*?)\s*=(.*)$/.exec(l);
    if (m && m[1] === key) return m[2].trim();
  }
  return null;
}
function renderIni(sections) {
  const parts = [];
  for (const s of sections) {
    // blank lines at a section's end are its spacing; one is put back
    const body = s.lines.slice();
    while (body.length && body[body.length - 1].trim() === "") body.pop();
    if (s.name === "") { if (body.length) parts.push(body.join("\n")); continue; }
    parts.push("[" + s.name + "]" + (body.length ? "\n" + body.join("\n") : ""));
  }
  return parts.join("\n\n") + "\n";
}

// The keyboard fcitx5 types plain letters with, from input.lua's first
// layout and variant: "us", "de-nodeadkeys"
function imLayout(kbLayout, kbVariant) {
  const l = String(kbLayout || "").split(",")[0].trim() || "us";
  const v = String(kbVariant || "").split(",")[0].trim();
  return v ? l + "-" + v : l;
}

// profile's first group: { layout, items } — items are fcitx5's input
// method names in order, "keyboard-us" first
function parseImProfile(text) {
  const secs = parseIni(text);
  const out = { layout: "", items: [] };
  const g = secs.find((s) => s.name === "Groups/0");
  if (g) out.layout = iniValue(g.lines, "Default Layout") || "";
  const items = secs
    .map((s) => ({ m: /^Groups\/0\/Items\/(\d+)$/.exec(s.name), s: s }))
    .filter((x) => x.m)
    .sort((a, b) => Number(a.m[1]) - Number(b.m[1]));
  for (const x of items) {
    const n = iniValue(x.s.lines, "Name");
    if (n) out.items.push(n);
  }
  return out;
}

// The items with `im` turned on or off. The keyboard comes first, always
// — it is what fcitx5 types with when no language is switched on — and is
// the layout's; any other the configtool added stays where it is.
function imItems(items, layout, im, on) {
  const kb = "keyboard-" + layout;
  const rest = (items || []).filter((n) => !/^keyboard-/.test(n) && n !== im);
  if (on && im) rest.push(im);
  return [kb].concat(rest);
}

function renderImProfile(layout, items) {
  const its = items && items.length ? items : ["keyboard-" + layout];
  const lines = [
    "[Groups/0]",
    "Name=Default",
    "Default Layout=" + layout,
    "DefaultIM=" + its[its.length - 1],
    "",
  ];
  its.forEach((n, i) => lines.push("[Groups/0/Items/" + i + "]", "Name=" + n, "Layout=", ""));
  lines.push("[GroupOrder]", "0=Default", "");
  return lines.join("\n");
}

// The switch key: config's [Hotkey/TriggerKeys] first entry
function parseImKey(text) {
  const s = parseIni(text).find((x) => x.name === "Hotkey/TriggerKeys");
  const v = s ? iniValue(s.lines, "0") : null;
  return v || IM_KEY_DEFAULT;
}
// config with the switch key set and everything else as it was
function setImKey(text, key) {
  const secs = parseIni(text);
  let s = secs.find((x) => x.name === "Hotkey/TriggerKeys");
  if (!s) { s = { name: "Hotkey/TriggerKeys", lines: [] }; secs.push(s); }
  s.lines = ["0=" + key];
  return renderIni(secs);
}

// One key set in an ini, the rest as it was; section "" is the top, before
// any [Section] (where classicui.conf keeps everything)
function setIniKey(text, section, key, value) {
  const secs = parseIni(text);
  let s = secs.find((x) => x.name === section);
  if (!s) { s = { name: section, lines: [] }; secs.push(s); }
  const at = s.lines.findIndex((l) => { const m = /^\s*([^#=][^=]*?)\s*=/.exec(l); return m && m[1] === key; });
  if (at >= 0) s.lines[at] = key + "=" + value;
  else {
    let end = s.lines.length;
    while (end > 0 && s.lines[end - 1].trim() === "") --end;
    s.lines.splice(end, 0, key + "=" + value);
  }
  return renderIni(secs);
}

// fcitx5's tray icon as its own drawn text ("en", "拼") rather than a theme
// icon by name: it asks for input-keyboard-symbolic and the like, which the
// shell has no icon theme for (2026-10-26), and the tray's ink tint reads
// the text's white as ink and its dark rim as faint
function imClassicUi(text) {
  return setIniKey(text, "", "PreferTextIcon", "True");
}

// ── EFFECTS ──
// hyprland's window shadows and animations: hypr/lua/effects.lua,
// `shadows = false` / `animations = false`, Look's "Window shadows" and
// Motion's "Window animations" (user, 2026-10-22). base.lua reads it, so it
// holds from login. Both on unless the file says false: no file, or a broken
// one, leaves hyprland as base.lua sets it.
// Every field, its default, in the order the file lists them: shadows
// and animations (Look, Motion), and the windows' own (Windows, 2026-10-25:
// gaps 8 outside and 2 between, the user's defaults). `fx` on a setting's
// spec names its field here. A field missing from the file, or not the
// kind it should be, is its default.
var EFFECTS = [
  { fx: "shadows",          def: true },
  { fx: "animations",       def: true },
  { fx: "wobble",           def: false },
  { fx: "gaps_out",         def: 8, min: 0, max: 40 },
  { fx: "gaps_in",          def: 2, min: 0, max: 20 },
  { fx: "special_gaps",     def: 30, min: 0, max: 120 },
  { fx: "border_size",      def: 1, min: 0, max: 5 },
  { fx: "layout",           def: "dwindle", options: ["dwindle", "master", "scrolling"] },
  { fx: "resize_on_border", def: false },
  { fx: "dim_inactive",     def: 0, min: 0, max: 0.5 },
  { fx: "inactive_opacity", def: 1, min: 0.5, max: 1 },
];
function effectsDefaults() {
  const out = {};
  for (const e of EFFECTS) out[e.fx] = e.def;
  return out;
}
function parseEffectsLua(text) {
  const src = stripLuaComments(String(text || ""));
  const out = {};
  for (const e of EFFECTS) {
    const at = "\\b" + e.fx + "\\s*=\\s*";
    let m;
    if (typeof e.def === "boolean")
      out[e.fx] = (m = new RegExp(at + "(true|false)\\b").exec(src)) ? m[1] === "true" : e.def;
    else if (typeof e.def === "number")
      out[e.fx] = (m = new RegExp(at + "(-?\\d+(?:\\.\\d+)?)").exec(src))
        ? Math.min(e.max, Math.max(e.min, Number(m[1]))) : e.def;
    else
      out[e.fx] = (m = new RegExp(at + "\"([a-z]+)\"").exec(src)) && e.options.indexOf(m[1]) >= 0 ? m[1] : e.def;
  }
  return out;
}
function renderEffectsLua(fx) {
  const f = Object.assign(effectsDefaults(), fx || {});
  const pad = Math.max.apply(null, EFFECTS.map((e) => e.fx.length));
  const val = (v) => typeof v === "boolean" ? (v ? "true" : "false")
    : typeof v === "number" ? String(v) : JSON.stringify(String(v));
  return [
    "-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐",
    "-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐",
    "-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘",
    "-- https://github.com/kbuckleys/",
    "",
    "-- EFFECTS",
    "-- Written by oracle (Look's Window shadows, Motion's Window animations,",
    "-- the window rows under Windows), and read back by it; base.lua lays",
    "-- it over its own. Gaps and border in pixels; dim_inactive 0 is off.",
    "",
    "return {",
  ].concat(EFFECTS.map((e) => "\t" + (e.fx + " ".repeat(pad)).slice(0, pad) + " = " + val(f[e.fx]) + ","))
   .concat(["}", ""]).join("\n");
}

// ── HYPRLAND ──
// The rest of hyprland's own settings (user, 2026-10-29: "hyprland is an
// integral part of the shell"): hypr/lua/hyprland.lua, one flat table of
// `["section:key"] = value` by hyprland's own names, which base.lua lays
// over everything it sets, each in its own call. Names, ranges and choices
// are 0.57's (`hyprctl descriptions`); a default is base.lua's value where
// it sets one, hyprland's where it does not, so a file of defaults changes
// nothing. "" leaves a setting to hyprland.
//
// Two kinds are not hyprland settings but the shell's, and base.lua turns
// them into calls: "zen:gesture:<fingers>:<direction>" is a touchpad
// gesture (hl.gesture), "zen:ws:<n>:<field>" a workspace's rule
// (hl.workspace_rule).
//
// `section` is the page, `part` the heading on it: a page laid out in PAGES
// has the heading there (hyprPlace fills it in), and the others (input,
// display) get a header row of their own (Oracle.hyprSpecs).
const OPEN_FS = [{ value: 0, label: "Off" }, { value: 1, label: "On" }, { value: 2, label: "Forced" }];
const AUTO3 = [{ value: 0, label: "Off" }, { value: 1, label: "On" }, { value: 2, label: "Automatic" }];

const HYPR_FIELDS = [
  // ── Windows ──
  { key: "general:float_gaps", section: "windows", part: "Gaps and borders", def: 0, type: "int", min: 0, max: 40, step: 1, unit: "px",
    label: "Floating gaps", alias: "floating window gaps edge margin",
    help: "How far floating windows keep from the screen's edges. 0 lets them touch." },
  { key: "general:gaps_workspaces", section: "windows", part: "Gaps and borders", def: 0, type: "int", min: 0, max: 100, step: 5, unit: "px",
    label: "Gap between workspaces", alias: "workspace gap slide animation space",
    help: "The space between one workspace and the next as they slide past each other." },
  { key: "general:extend_border_grab_area", section: "windows", part: "Resizing", def: 15, type: "int", min: 0, max: 50, step: 1, unit: "px",
    label: "Grab area", alias: "resize border grab edge area width",
    help: "How far outside a window's edge a drag still resizes it, with Resize from edges on." },
  { key: "general:hover_icon_on_border", section: "windows", part: "Resizing", def: true, type: "bool",
    label: "Resize pointer on edges", alias: "resize cursor icon border hover",
    help: "The pointer turns into a resize arrow over a window's edge, with Resize from edges on." },
  { key: "general:resize_corner", section: "windows", part: "Resizing", def: 0, type: "enum", chipW: 208,
    options: [{ value: 0, label: "Nearest" }, { value: 1, label: "Top left" }, { value: 2, label: "Top right" },
              { value: 3, label: "Bottom right" }, { value: 4, label: "Bottom left" }],
    label: "Floating resize corner", alias: "resize corner floating window super drag",
    help: "Which corner of a floating window moves when you resize it with Super and the right button. Nearest is the one under the pointer." },
  { key: "general:snap:enabled", section: "windows", part: "Snapping", def: true, type: "bool",
    label: "Snap floating windows", alias: "snap magnet floating window edge align",
    help: "A floating window dragged near another window or the screen's edge jumps flush against it." },
  { key: "general:snap:window_gap", section: "windows", part: "Snapping", def: 10, type: "int", min: 0, max: 100, step: 1, unit: "px",
    label: "Snap to windows from", alias: "snap distance window gap",
    help: "How close to another window it has to come before it snaps." },
  { key: "general:snap:monitor_gap", section: "windows", part: "Snapping", def: 10, type: "int", min: 0, max: 100, step: 1, unit: "px",
    label: "Snap to edges from", alias: "snap distance screen edge monitor gap",
    help: "How close to the screen's edge it has to come before it snaps." },
  { key: "general:snap:border_overlap", section: "windows", part: "Snapping", def: true, type: "bool",
    label: "Share one border", alias: "snap border overlap",
    help: "Snapped windows overlap by a border, so one line stands between them, not two." },
  { key: "general:snap:respect_gaps", section: "windows", part: "Snapping", def: false, type: "bool",
    label: "Keep the gaps", alias: "snap respect gaps",
    help: "Snapped windows stand the inner and outer gaps apart, as tiled ones do." },
  { key: "decoration:active_opacity", section: "windows", part: "Focus", def: 1, type: "real", min: 0.5, max: 1, step: 0.05,
    label: "Focused opacity", alias: "opacity transparent active focused window",
    help: "How see-through the window you are in is. 1 is solid." },
  { key: "decoration:fullscreen_opacity", section: "windows", part: "Focus", def: 1, type: "real", min: 0.5, max: 1, step: 0.05,
    label: "Fullscreen opacity", alias: "opacity transparent fullscreen window",
    help: "How see-through a fullscreen window is. 1 is solid." },
  { key: "decoration:dim_special", section: "windows", part: "Focus", def: 0.8, type: "real", min: 0, max: 1, step: 0.05,
    label: "Dim behind special workspace", alias: "dim special workspace scratchpad darken",
    help: "How dark the rest of the screen goes while the special workspace is shown. 0 leaves it as it is." },
  { key: "decoration:dim_modal", section: "windows", part: "Focus", def: true, type: "bool",
    label: "Dim behind dialogs", alias: "dim modal dialog parent darken",
    help: "A window waiting on one of its own dialogs is dimmed until the dialog closes." },
  { key: "misc:focus_on_activate", section: "windows", part: "Focus", def: false, type: "bool",
    label: "Apps may take focus", alias: "focus activate steal request app raise",
    help: "An app that asks to be brought forward (a link opened in a browser behind) is focused at once. Off, it only asks." },
  { key: "general:no_focus_fallback", section: "windows", part: "Focus", def: false, type: "bool",
    label: "Stop at the last window", alias: "focus fallback direction edge move focus",
    help: "Moving focus toward an edge with no window that way stays put, instead of going to the nearest window." },
  { key: "misc:on_focus_under_fullscreen", section: "windows", part: "Focus", def: 2, type: "enum", chipW: 208,
    options: [{ value: 0, label: "Stay behind" }, { value: 1, label: "Take over" }, { value: 2, label: "Leave fullscreen" }],
    label: "Opening under fullscreen", alias: "fullscreen maximized new window focus under",
    help: "What a new tiled window does while another fills the screen: wait behind it, take the fullscreen over, or end the fullscreen." },
  { key: "misc:exit_window_retains_fullscreen", section: "windows", part: "Focus", def: 0, type: "enum", chipW: 208,
    options: [{ value: 0, label: "No" }, { value: 1, label: "Yes" }, { value: 2, label: "Only in a group" }, { value: 3, label: "Only outside a group" }],
    label: "Fullscreen passes on", alias: "fullscreen close next window retain",
    help: "Closing a fullscreen window makes the window that gets the focus fullscreen too." },
  { key: "misc:enable_swallow", section: "windows", part: "Terminal swallowing", def: false, type: "bool",
    label: "Swallow from the terminal", alias: "swallow terminal hide launch window replace",
    help: "A window started from a terminal takes the terminal's place, and the terminal comes back when it closes." },
  { key: "misc:swallow_regex", section: "windows", part: "Terminal swallowing", def: "^(kitty)$", type: "text",
    label: "Terminals", alias: "swallow regex terminal class",
    help: "Which windows swallow, by app class, as a regular expression." },
  { key: "misc:swallow_exception_regex", section: "windows", part: "Terminal swallowing", def: "", type: "text",
    label: "Never swallowed", alias: "swallow exception regex title",
    help: "Terminal titles that never swallow, as a regular expression: a terminal running an editor, say." },
  { key: "misc:enable_anr_dialog", section: "windows", part: "Apps not responding", def: true, type: "bool",
    label: "Ask about a frozen app", alias: "anr not responding hang frozen dialog kill",
    help: "When an app stops answering, hyprland offers to wait or close it." },
  { key: "misc:anr_missed_pings", section: "windows", part: "Apps not responding", def: 5, type: "int", min: 1, max: 20, step: 1,
    label: "Ask after", unit: " pings", alias: "anr missed pings timeout",
    help: "How many checks an app may miss before hyprland asks. Each is about a second." },

  // ── Tiling ──
  { key: "layout:single_window_aspect_ratio", section: "tiling", part: "Layout", def: "0 0", type: "enum", chipW: 208,
    options: [{ value: "0 0", label: "Fill the screen" }, { value: "16 9", label: "16:9" }, { value: "16 10", label: "16:10" },
              { value: "4 3", label: "4:3" }, { value: "1 1", label: "Square" }],
    label: "A lone window's shape", alias: "single window aspect ratio ultrawide center lone",
    help: "A workspace with one tiled window keeps it to this shape, centered, instead of stretching it edge to edge. For a wide screen." },
  { key: "dwindle:preserve_split", section: "tiling", part: "Dwindle", def: true, type: "bool",
    label: "Keep the split", alias: "dwindle preserve split direction",
    help: "A split stays side by side or stacked as you resize, rather than turning with the space's shape." },
  { key: "dwindle:smart_split", section: "tiling", part: "Dwindle", def: false, type: "bool",
    label: "Split where the pointer is", alias: "dwindle smart split pointer mouse",
    help: "A new window opens on the side of the focused one the pointer is nearest." },
  { key: "dwindle:force_split", section: "tiling", part: "Dwindle", def: 0, type: "enum", segments: true,
    options: [{ value: 0, label: "Follow pointer" }, { value: 1, label: "Left or top" }, { value: 2, label: "Right or bottom" }],
    label: "New window goes", alias: "dwindle force split side new window",
    help: "Which side of the split a new window takes." },
  { key: "dwindle:default_split_ratio", section: "tiling", part: "Dwindle", def: 1, type: "real", min: 0.1, max: 1.9, step: 0.05,
    label: "Split ratio", alias: "dwindle default split ratio size",
    help: "How a split shares its space at first. 1 is half each; more gives the first window more." },
  { key: "dwindle:split_width_multiplier", section: "tiling", part: "Dwindle", def: 1, type: "real", min: 0.1, max: 3, step: 0.1,
    label: "Side-by-side bias", alias: "dwindle split width multiplier",
    help: "Above 1, spaces split side by side more often; below, stacked more often." },
  { key: "dwindle:smart_resizing", section: "tiling", part: "Dwindle", def: true, type: "bool",
    label: "Resize toward the pointer", alias: "dwindle smart resizing mouse",
    help: "Resizing with the mouse moves the edge nearest the pointer." },
  // dwindle:special_scale_factor left out: deprecated in 0.57 ("use
  // workspace rules"); HYPR_RETIRED drops it from older files
  { key: "master:mfact", section: "tiling", part: "Master", def: 0.55, type: "real", min: 0.1, max: 0.9, step: 0.05,
    label: "Master size", alias: "master mfact size ratio",
    help: "How much of the screen the master window takes." },
  { key: "master:orientation", section: "tiling", part: "Master", def: "left", type: "enum", chipW: 208,
    options: [{ value: "left", label: "Left" }, { value: "right", label: "Right" }, { value: "top", label: "Top" },
              { value: "bottom", label: "Bottom" }, { value: "center", label: "Center" }],
    label: "Master side", alias: "master orientation side center",
    help: "Where the master window sits; Center puts the stack on both sides of it." },
  { key: "master:new_status", section: "tiling", part: "Master", def: "slave", type: "enum", segments: true,
    options: [{ value: "slave", label: "Stack" }, { value: "master", label: "Master" }, { value: "inherit", label: "Like focused" }],
    label: "New windows join", alias: "master new status stack",
    help: "Whether a new window joins the stack, becomes the master, or goes where the focused window is." },
  { key: "master:new_on_top", section: "tiling", part: "Master", def: false, type: "bool",
    label: "New on top of the stack", alias: "master new on top",
    help: "A new window goes to the top of the stack instead of the bottom." },
  { key: "master:new_on_active", section: "tiling", part: "Master", def: "none", type: "enum", segments: true,
    options: [{ value: "none", label: "Off" }, { value: "before", label: "Before" }, { value: "after", label: "After" }],
    label: "Next to the focused", alias: "master new on active before after",
    help: "A new window goes just before or after the focused one, not at the end." },
  { key: "master:slave_count_for_center_master", section: "tiling", part: "Master", def: 2, type: "int", min: 0, max: 10, step: 1,
    label: "Center from", unit: " windows", alias: "master center slave count",
    help: "With Center, how many stacked windows there must be before the master moves to the middle." },
  { key: "master:focus_master_on_close", section: "tiling", part: "Master", def: false, type: "bool",
    label: "Focus the master on close", alias: "master focus close",
    help: "Closing a window focuses the master." },
  { key: "master:always_keep_position", section: "tiling", part: "Master", def: false, type: "bool",
    label: "Master keeps its place", alias: "master keep position alone",
    help: "A master with no stack beside it stays where Master side puts it, instead of filling the screen." },
  { key: "scrolling:column_width", section: "tiling", part: "Scrolling", def: 0.95, type: "real", min: 0.1, max: 1, step: 0.05,
    label: "Column width", alias: "scrolling column width size",
    help: "How much of the screen a new column takes." },
  { key: "scrolling:focus_fit_method", section: "tiling", part: "Scrolling", def: 0, type: "enum", segments: true,
    options: [{ value: 0, label: "Center" }, { value: 1, label: "Just fit" }],
    label: "Bring into view", alias: "scrolling focus fit center",
    help: "A column focused off screen scrolls to the middle, or only far enough to fit." },
  { key: "scrolling:follow_focus", section: "tiling", part: "Scrolling", def: 1, type: "enum", segments: true,
    options: [{ value: 0, label: "Stay put" }, { value: 1, label: "Follow" }],
    label: "Follow the focus", alias: "scrolling follow focus",
    help: "The strip scrolls to whichever window gets the focus." },
  { key: "scrolling:direction", section: "tiling", part: "Scrolling", def: "right", type: "enum", segments: true,
    options: [{ value: "right", label: "Right" }, { value: "left", label: "Left" }, { value: "down", label: "Down" }, { value: "up", label: "Up" }],
    label: "New columns go", alias: "scrolling direction",
    help: "The way the strip grows as windows open." },
  { key: "scrolling:fullscreen_on_one_column", section: "tiling", part: "Scrolling", def: true, type: "bool",
    label: "One column fills the screen", alias: "scrolling single column fullscreen",
    help: "A workspace with one column spreads it across the whole screen." },
  { key: "scrolling:wrap_focus", section: "tiling", part: "Scrolling", def: true, type: "bool",
    label: "Wrap around", alias: "scrolling wrap focus",
    help: "Moving focus past the last column comes round to the first." },
  { key: "scrolling:explicit_column_widths", section: "tiling", part: "Scrolling", def: "0.333, 0.5, 0.667, 1.0", type: "text",
    label: "Column width steps", alias: "scrolling explicit column widths resize presets",
    help: "The widths the column resize binds step through, as fractions of the screen, comma-separated." },
  { key: "group:auto_group", section: "tiling", part: "Window groups", def: true, type: "bool",
    label: "New windows join the group", alias: "group tabbed auto",
    help: "A window opened while a group is focused becomes a tab in it." },
  { key: "group:insert_after_current", section: "tiling", part: "Window groups", def: true, type: "bool",
    label: "Next to the current tab", alias: "group insert after current",
    help: "A new tab opens beside the one you are in, not at the end." },
  { key: "group:focus_removed_window", section: "tiling", part: "Window groups", def: true, type: "bool",
    label: "Follow a tab taken out", alias: "group focus removed window",
    help: "A window moved out of its group keeps the focus." },
  { key: "group:drag_into_group", section: "tiling", part: "Window groups", def: 1, type: "enum", segments: true,
    options: [{ value: 0, label: "Never" }, { value: 1, label: "Anywhere" }, { value: 2, label: "On the tabs" }],
    label: "Drop into a group", alias: "group drag drop merge",
    help: "Where a window dragged onto a group has to land to join it." },
  { key: "group:group_on_movetoworkspace", section: "tiling", part: "Window groups", def: false, type: "bool",
    label: "Join on moving", alias: "group move to workspace merge",
    help: "A window sent to a workspace with a group joins that group." },
  { key: "group:groupbar:enabled", section: "tiling", part: "Tabs", def: true, type: "bool",
    label: "Show the tabs", alias: "groupbar tabs bar",
    help: "A strip of tabs above a group, one for each window in it." },
  { key: "group:groupbar:disable_when_only", section: "tiling", part: "Tabs", def: false, type: "bool",
    label: "Hide with one tab", alias: "groupbar single hide",
    help: "A group of one window shows no tab." },
  { key: "group:groupbar:height", section: "tiling", part: "Tabs", def: 24, type: "int", min: 8, max: 48, step: 1, unit: "px",
    label: "Tab height", alias: "groupbar height size",
    help: "How tall the tabs are." },
  { key: "group:groupbar:render_titles", section: "tiling", part: "Tabs", def: true, type: "bool",
    label: "Titles on tabs", alias: "groupbar titles text",
    help: "Each tab shows its window's title." },
  { key: "group:groupbar:stacked", section: "tiling", part: "Tabs", def: false, type: "bool",
    label: "Stack the tabs", alias: "groupbar stacked vertical",
    help: "The tabs sit one above another instead of side by side." },
  { key: "group:groupbar:gradients", section: "tiling", part: "Tabs", def: true, type: "bool",
    label: "Filled tabs", alias: "groupbar gradients fill",
    help: "Each tab is filled with the theme's color. Off, only the titles show." },
  { key: "group:groupbar:blur", section: "tiling", part: "Tabs", def: false, type: "bool",
    label: "Frost the tabs", alias: "groupbar blur frost",
    help: "What is behind the tabs is blurred." },
  { key: "group:groupbar:scrolling", section: "tiling", part: "Tabs", def: true, type: "bool",
    label: "Scroll to switch", alias: "groupbar scroll switch",
    help: "Scrolling over the tabs moves to the next or previous one." },
  { key: "group:groupbar:middle_click_close", section: "tiling", part: "Tabs", def: true, type: "bool",
    label: "Middle-click closes", alias: "groupbar middle click close",
    help: "A middle click on a tab closes its window." },

  // ── Workspaces ──
  { key: "binds:workspace_back_and_forth", section: "workspaces", part: "Switching", def: 0, type: "enum", segments: true,
    options: [{ value: 0, label: "Off" }, { value: 1, label: "On" }, { value: 2, label: "Per screen" }],
    label: "Back and forth", alias: "workspace back and forth previous toggle",
    help: "Asking for the workspace you are on goes back to the one before it." },
  { key: "binds:allow_workspace_cycles", section: "workspaces", part: "Switching", def: false, type: "bool",
    label: "Remember the way back", alias: "workspace cycles previous history",
    help: "Going back to the previous workspace keeps going back, one step at a time, instead of toggling between two." },
  { key: "binds:hide_special_on_workspace_change", section: "workspaces", part: "Switching", def: true, type: "bool",
    label: "Hide special on switch", alias: "special workspace hide switch",
    help: "Switching workspace puts the special workspace away." },
  { key: "misc:close_special_on_empty", section: "workspaces", part: "Switching", def: true, type: "bool",
    label: "Close special when empty", alias: "special workspace close empty",
    help: "The special workspace goes away when its last window closes." },
  { key: "misc:initial_workspace_tracking", section: "workspaces", part: "Switching", def: 0, type: "enum", segments: true,
    options: [{ value: 0, label: "Off" }, { value: 1, label: "First window" }, { value: 2, label: "Every window" }],
    label: "Open where started", alias: "initial workspace tracking launch open",
    help: "An app started on one workspace opens there, even if you have moved on by the time it shows." },

  // ── Window effects ──
  { key: "decoration:blur:enabled", section: "wineffects", part: "Blur", def: true, type: "bool",
    label: "Blur", alias: "blur frost background behind window",
    help: "What is behind a see-through window, panel or menu is blurred. Off, it shows through sharp." },
  { key: "decoration:blur:size", section: "wineffects", part: "Blur", def: 8, type: "int", min: 1, max: 30, step: 1,
    label: "Blur size", alias: "blur size radius strength",
    help: "How far each pass spreads. More is softer." },
  { key: "decoration:blur:passes", section: "wineffects", part: "Blur", def: 2, type: "int", min: 1, max: 6, step: 1,
    label: "Blur passes", alias: "blur passes quality",
    help: "How many times the blur is run. More is smoother and costs the graphics card more." },
  { key: "decoration:blur:noise", section: "wineffects", part: "Blur", def: 0.0117, type: "real", min: 0, max: 0.2, step: 0.0001,
    label: "Grain", alias: "blur noise grain",
    help: "A fine grain over the blur, so it does not band." },
  { key: "decoration:blur:contrast", section: "wineffects", part: "Blur", def: 0.8916, type: "real", min: 0, max: 2, step: 0.0001,
    label: "Contrast", alias: "blur contrast",
    help: "The blur's contrast. 1 leaves it as it is." },
  { key: "decoration:blur:brightness", section: "wineffects", part: "Blur", def: 1, type: "real", min: 0, max: 2, step: 0.05,
    label: "Brightness", alias: "blur brightness",
    help: "The blur's brightness. 1 leaves it as it is." },
  { key: "decoration:blur:vibrancy", section: "wineffects", part: "Blur", def: 0.1696, type: "real", min: 0, max: 1, step: 0.0001,
    label: "Vibrancy", alias: "blur vibrancy saturation color",
    help: "How much richer the colors behind come through." },
  { key: "decoration:blur:vibrancy_darkness", section: "wineffects", part: "Blur", def: 0, type: "real", min: 0, max: 1, step: 0.05,
    label: "Vibrancy in the dark", alias: "blur vibrancy darkness",
    help: "How much of the vibrancy reaches dark colors." },
  { key: "decoration:blur:xray", section: "wineffects", part: "Blur", def: false, type: "bool",
    label: "See through to the background", alias: "blur xray floating",
    help: "Floating windows blur only the background, not the tiled windows under them." },
  { key: "decoration:blur:ignore_opacity", section: "wineffects", part: "Blur", def: true, type: "bool",
    label: "Full blur under see-through", alias: "blur ignore opacity",
    help: "A see-through window gets the whole blur however see-through it is. Off, the blur thins with it." },
  { key: "decoration:blur:special", section: "wineffects", part: "Blur", def: true, type: "bool",
    label: "Blur behind special workspace", alias: "blur special workspace",
    help: "The screen behind the special workspace is blurred. Costs the graphics card." },
  { key: "decoration:blur:popups", section: "wineffects", part: "Blur", def: true, type: "bool",
    label: "Blur under app menus", alias: "blur popups menus right-click",
    help: "The right-click menus and dropdowns of apps are frosted too." },
  { key: "decoration:blur:input_methods", section: "wineffects", part: "Blur", def: false, type: "bool",
    label: "Blur under input methods", alias: "blur input method fcitx candidate",
    help: "The input method's box of candidates (fcitx5) is frosted too." },
  { key: "decoration:blur:glass:refraction", section: "wineffects", part: "Glass", def: 20, type: "int", min: 0, max: 20, step: 1, unit: "px",
    label: "Refraction", alias: "glass refraction bend",
    help: "How far the glass styles of Frost style bend what is behind them." },
  { key: "decoration:blur:glass:size", section: "wineffects", part: "Glass", def: 40, type: "int", min: 4, max: 512, step: 4, unit: "px",
    label: "Pattern size", alias: "glass pattern size",
    help: "How large the glass's pattern is." },
  { key: "decoration:blur:glass:roughness", section: "wineffects", part: "Glass", def: 1, type: "real", min: 0, max: 1, step: 0.05,
    label: "Roughness", alias: "glass roughness relief",
    help: "How strongly the glass's relief is shaded." },
  { key: "decoration:shadow:range", section: "wineffects", part: "Shadow", def: 70, type: "int", min: 0, max: 100, step: 1, unit: "px",
    label: "Shadow reach", alias: "shadow range size",
    help: "How far a window's shadow spreads, with Window shadows on." },
  { key: "decoration:shadow:render_power", section: "wineffects", part: "Shadow", def: 2, type: "int", min: 1, max: 4, step: 1,
    label: "Shadow falloff", alias: "shadow render power falloff",
    help: "How quickly the shadow fades. More is tighter." },
  { key: "decoration:shadow:sharp", section: "wineffects", part: "Shadow", def: false, type: "bool",
    label: "Hard shadow", alias: "shadow sharp hard",
    help: "The shadow has a hard edge instead of fading." },
  { key: "decoration:shadow:offset", section: "wineffects", part: "Shadow", def: "0 10", type: "text",
    label: "Shadow offset", alias: "shadow offset position",
    help: "How far the shadow is moved, in pixels: across then down, such as 0 10." },
  { key: "decoration:shadow:scale", section: "wineffects", part: "Shadow", def: 1, type: "real", min: 0.5, max: 1.5, step: 0.05,
    label: "Shadow scale", alias: "shadow scale size",
    help: "The shadow's size against its window's." },
  { key: "decoration:glow:enabled", section: "wineffects", part: "Glow", def: false, type: "bool",
    label: "Inner glow", alias: "glow inner light edge",
    help: "A soft light along the inside of every window's edge." },
  { key: "decoration:glow:range", section: "wineffects", part: "Glow", def: 10, type: "int", min: 0, max: 100, step: 1, unit: "px",
    label: "Glow reach", alias: "glow range size",
    help: "How far in from the edge the glow reaches." },
  { key: "decoration:glow:render_power", section: "wineffects", part: "Glow", def: 3, type: "int", min: 1, max: 4, step: 1,
    label: "Glow falloff", alias: "glow render power falloff",
    help: "How quickly the glow fades. More is tighter." },
  { key: "decoration:glow:color", section: "wineffects", part: "Glow", def: "", type: "color",
    label: "Glow color", alias: "glow color",
    help: "The glow's color. Unset, hyprland's own cyan." },
  { key: "decoration:rounding_power", section: "wineffects", part: "Corners", def: 2, type: "real", min: 1, max: 10, step: 0.5,
    label: "Corner shape", alias: "rounding power squircle corner shape",
    help: "2 rounds a window's corners as circles; more gives the smoother squircle macOS uses. Corner rounding sets how big they are." },
  { key: "decoration:border_part_of_window", section: "wineffects", part: "Corners", def: true, type: "bool",
    label: "Border inside the window", alias: "border part of window",
    help: "The border counts as part of the window, so rounding and the shadow go round it." },
  { key: "decoration:motion_blur:enabled", section: "wineffects", part: "Motion blur", def: false, type: "bool",
    label: "Motion blur", alias: "motion blur moving window drag",
    help: "A window being moved or resized smears a little behind it. Costs the graphics card." },
  { key: "decoration:motion_blur:samples", section: "wineffects", part: "Motion blur", def: 7, type: "int", min: 1, max: 32, step: 1,
    label: "Motion blur quality", alias: "motion blur samples",
    help: "How many steps the smear is drawn in. More is smoother and costs more." },

  // ── Motion ──
  { key: "animations:workspace_wraparound", section: "motion", part: "Animations", def: false, type: "bool",
    label: "Wrap the workspace slide", alias: "workspace wraparound slide first last",
    help: "Going from the last workspace to the first slides on the same way, instead of back across them all." },
  { key: "misc:animate_manual_resizes", section: "motion", part: "Animations", def: false, type: "bool",
    label: "Animate resizing", alias: "animate manual resize",
    help: "A window resized by hand eases to its new size instead of following at once." },
  { key: "misc:animate_mouse_windowdragging", section: "motion", part: "Animations", def: false, type: "bool",
    label: "Animate dragging", alias: "animate mouse window dragging",
    help: "A window dragged with the mouse trails a little behind the pointer." },

  // ── Keyboard & mouse: the pointer and gestures ──
  { key: "cursor:inactive_timeout", section: "input", part: "Pointer", def: 0, type: "int", min: 0, max: 20, step: 1, unit: "s",
    label: "Hide when still", alias: "cursor hide inactive timeout idle pointer",
    help: "The pointer hides after this long without moving. 0 never hides it." },
  { key: "cursor:hide_on_key_press", section: "input", part: "Pointer", def: false, type: "bool",
    label: "Hide while typing", alias: "cursor hide key press typing",
    help: "The pointer hides on a key press and comes back when the mouse moves." },
  { key: "cursor:hide_on_touch", section: "input", part: "Pointer", def: true, type: "bool",
    label: "Hide on touch", alias: "cursor hide touch screen",
    help: "The pointer hides while you use a touch screen." },
  { key: "cursor:hide_on_tablet", section: "input", part: "Pointer", def: false, type: "bool",
    label: "Hide on the pen", alias: "cursor hide tablet pen",
    help: "The pointer hides while you use a drawing tablet." },
  { key: "cursor:no_warps", section: "input", part: "Pointer", def: false, type: "bool",
    label: "Never move the pointer", alias: "cursor no warps jump move",
    help: "Hyprland never moves the pointer for you, whatever the settings below say." },
  { key: "cursor:warp_on_change_workspace", section: "input", part: "Pointer", def: 0, type: "enum", segments: true, options: OPEN_FS,
    label: "Jump on workspace switch", alias: "cursor warp workspace change",
    help: "The pointer jumps to the focused window when the workspace changes. Forced does it even over a window that does not move." },
  { key: "cursor:warp_on_toggle_special", section: "input", part: "Pointer", def: 0, type: "enum", segments: true, options: OPEN_FS,
    label: "Jump on special workspace", alias: "cursor warp special toggle",
    help: "The pointer jumps to the focused window when the special workspace is shown or put away." },
  { key: "cursor:persistent_warps", section: "input", part: "Pointer", def: false, type: "bool",
    label: "Back where it was", alias: "cursor persistent warps",
    help: "A jump to a window puts the pointer back where it last was in it, not in its middle." },
  { key: "misc:mouse_move_focuses_monitor", section: "input", part: "Pointer", def: true, type: "bool",
    label: "Pointer picks the screen", alias: "mouse move focus monitor screen",
    help: "Moving the pointer onto another screen makes it the focused one." },
  { key: "misc:middle_click_paste", section: "input", part: "Pointer", def: false, type: "bool",
    label: "Middle-click paste", alias: "middle click paste primary selection",
    help: "Selecting text copies it to a second clipboard, and a middle click pastes it, as on older Linux desktops." },
  { key: "zen:gesture:3:horizontal", section: "input", part: "Gestures", def: "workspace", type: "enum", chipW: 208, options: "gestures",
    label: "Three fingers sideways", alias: "gesture swipe three fingers horizontal touchpad",
    help: "What a three-finger swipe left or right does on a touchpad." },
  { key: "zen:gesture:3:up", section: "input", part: "Gestures", def: "", type: "enum", chipW: 208, options: "gestures",
    label: "Three fingers up", alias: "gesture swipe three fingers up touchpad", help: "What a three-finger swipe up does." },
  { key: "zen:gesture:3:down", section: "input", part: "Gestures", def: "", type: "enum", chipW: 208, options: "gestures",
    label: "Three fingers down", alias: "gesture swipe three fingers down touchpad", help: "What a three-finger swipe down does." },
  { key: "zen:gesture:4:horizontal", section: "input", part: "Gestures", def: "", type: "enum", chipW: 208, options: "gestures",
    label: "Four fingers sideways", alias: "gesture swipe four fingers horizontal touchpad", help: "What a four-finger swipe left or right does." },
  { key: "zen:gesture:4:up", section: "input", part: "Gestures", def: "", type: "enum", chipW: 208, options: "gestures",
    label: "Four fingers up", alias: "gesture swipe four fingers up touchpad", help: "What a four-finger swipe up does." },
  { key: "zen:gesture:4:down", section: "input", part: "Gestures", def: "", type: "enum", chipW: 208, options: "gestures",
    label: "Four fingers down", alias: "gesture swipe four fingers down touchpad", help: "What a four-finger swipe down does." },
  { key: "zen:gesture:3:pinchin", section: "input", part: "Gestures", def: "", type: "enum", chipW: 208, options: "gestures",
    label: "Three-finger pinch in", alias: "gesture pinch in three fingers touchpad", help: "What pinching three fingers together does." },
  { key: "zen:gesture:3:pinchout", section: "input", part: "Gestures", def: "", type: "enum", chipW: 208, options: "gestures",
    label: "Three-finger pinch out", alias: "gesture pinch out three fingers touchpad", help: "What spreading three fingers apart does." },
  { key: "gestures:workspace_swipe_distance", section: "input", part: "Gestures", def: 300, type: "int", min: 50, max: 2000, step: 50, unit: "px",
    label: "Swipe length", alias: "gesture workspace swipe distance",
    help: "How far a workspace swipe travels for one whole workspace." },
  { key: "gestures:workspace_swipe_invert", section: "input", part: "Gestures", def: true, type: "bool",
    label: "Content follows the fingers", alias: "gesture workspace swipe invert natural",
    help: "The workspaces move with your fingers, as on macOS. Off, they move against them." },
  { key: "gestures:workspace_swipe_cancel_ratio", section: "input", part: "Gestures", def: 0.5, type: "real", min: 0.1, max: 0.9, step: 0.05,
    label: "Swipe must go", alias: "gesture swipe cancel ratio",
    help: "How much of the way a slow swipe has to go before it switches, rather than springing back." },
  { key: "gestures:workspace_swipe_create_new", section: "input", part: "Gestures", def: true, type: "bool",
    label: "Swipe past the last for a new one", alias: "gesture swipe create new workspace",
    help: "Swiping on from the last workspace opens an empty one." },
  { key: "gestures:workspace_swipe_forever", section: "input", part: "Gestures", def: false, type: "bool",
    label: "Swipe across many", alias: "gesture swipe forever",
    help: "One long swipe carries on past the next workspace, instead of stopping at it." },
  { key: "gestures:workspace_swipe_touch", section: "input", part: "Gestures", def: false, type: "bool",
    label: "Swipe from a touch screen's edge", alias: "gesture touch screen edge swipe",
    help: "A swipe in from the edge of a touch screen switches workspace too." },

  // ── Display ──
  { key: "misc:vrr", section: "display", part: "Smoothness", def: 0, type: "enum", chipW: 208,
    options: [{ value: 0, label: "Off" }, { value: 1, label: "Always" }, { value: 2, label: "Fullscreen" }, { value: 3, label: "Fullscreen games" }],
    label: "Adaptive sync", alias: "vrr adaptive sync freesync gsync variable refresh",
    help: "The screen's refresh follows what is drawn (FreeSync, G-Sync), for smoother games and video. Only on a screen that has it; some flicker with it always on." },
  { key: "general:allow_tearing", section: "display", part: "Smoothness", def: false, type: "bool",
    label: "Allow tearing", alias: "tearing immediate games latency",
    help: "Games that ask for it may draw straight to the screen, for less lag at the cost of torn frames. A window rule picks which (Immediate)." },
  { key: "render:direct_scanout", section: "display", part: "Smoothness", def: 0, type: "enum", segments: true, options: AUTO3.slice(0, 2).concat([{ value: 2, label: "Games" }]),
    label: "Direct scanout", alias: "direct scanout fullscreen latency",
    help: "A fullscreen window goes to the screen without being drawn again, for less lag. Some apps glitch with it." },
  { key: "misc:render_unfocused_fps", section: "display", part: "Smoothness", def: 15, type: "int", min: 1, max: 120, step: 1, unit: " fps",
    label: "Hidden windows draw at", alias: "render unfocused fps background",
    help: "How often a window kept drawing while out of sight (a window rule) is drawn." },
  { key: "render:cm_enabled", section: "display", part: "Color", def: true, type: "bool",
    label: "Color management", alias: "color management cm hdr wide gamut",
    help: "Hyprland handles colors for wide-gamut and HDR screens. Counts fully from the next login." },
  { key: "render:cm_auto_hdr", section: "display", part: "Color", def: 1, type: "enum", segments: true,
    options: [{ value: 0, label: "Off" }, { value: 1, label: "HDR" }, { value: 2, label: "HDR, screen's own" }],
    label: "HDR for fullscreen", alias: "hdr auto fullscreen game video",
    help: "A fullscreen app showing HDR switches the screen into HDR while it is up." },
  { key: "xwayland:force_zero_scaling", section: "display", part: "Older apps", def: false, type: "bool",
    label: "Sharp X apps on scaled screens", alias: "xwayland zero scaling blurry",
    help: "Apps under XWayland are drawn at the screen's real size instead of stretched, so they are sharp but small." },
  { key: "xwayland:use_nearest_neighbor", section: "display", part: "Older apps", def: false, type: "bool",
    label: "Pixelated stretching", alias: "xwayland nearest neighbor pixelated",
    help: "X apps stretched for a scaled screen keep hard pixels instead of going soft." },
];

// a gesture slot's actions (hl.gesture's own names; "" none)
const GESTURE_ACTIONS = [
  { value: "", label: "Nothing" }, { value: "workspace", label: "Switch workspace" },
  { value: "special", label: "Special workspace" }, { value: "move", label: "Move the window" },
  { value: "resize", label: "Resize the window" }, { value: "close", label: "Close the window" },
  { value: "fullscreen", label: "Fullscreen" }, { value: "float", label: "Float or tile" },
];

// a workspace's own rule, for workspaces 1–10: its screen and its layout
const WS_COUNT = 10;
for (let n = 1; n <= WS_COUNT; ++n) {
  HYPR_FIELDS.push({ key: "zen:ws:" + n + ":monitor", section: "workspaces", part: "Screens", def: "", type: "enum",
    open: true, segments: true, options: "wsScreens", label: "Workspace " + n,
    alias: "workspace " + n + " monitor screen output bind",
    help: n === 1 ? "The screen each workspace lives on. Any lets it open wherever you are." : "" });
}
for (let n = 1; n <= WS_COUNT; ++n) {
  HYPR_FIELDS.push({ key: "zen:ws:" + n + ":layout", section: "workspaces", part: "Layouts", def: "", type: "enum",
    segments: true, art: "layout", label: "Workspace " + n, alias: "workspace " + n + " layout tiling dwindle master scrolling",
    options: [{ value: "", label: "Same as Tiling" }, { value: "dwindle", label: "Dwindle" },
              { value: "master", label: "Master" }, { value: "scrolling", label: "Scrolling" }],
    help: n === 1 ? "A layout of a workspace's own. The empty screen is the same as Tiling's layout." : "" });
}

function hyprFields() { return HYPR_FIELDS; }
function hyprKeys() { return HYPR_FIELDS.map((f) => f.key); }
function hyprDefault(key) {
  for (const f of HYPR_FIELDS) if (f.key === key) return f.def;
  return undefined;
}
function hyprOptions(name, screens) {
  if (name === "gestures") return GESTURE_ACTIONS;
  if (name === "wsScreens") return [{ value: "", label: "Any" }].concat((screens || []).map((n) => ({ value: n, label: n })));
  return [];
}

// Each field's key into its page's part in PAGES, in HYPR_FIELDS' order
// after the part's own; a part PAGES does not name is a mistake the tests
// catch (it would be the end of the page, unheaded). Returns the misses.
function hyprPlace(pages) {
  const miss = [];
  for (const f of HYPR_FIELDS) {
    const page = pages[f.section];
    if (!page) continue;
    const part = page.find((p) => p[0] === f.part);
    const k = "hl:" + f.key;
    if (!part) miss.push(k);
    else if (part[1].indexOf(k) < 0) part[1].push(k);
  }
  return miss;
}

// a field as a row's spec: its choices filled in, its default the fallback
function hyprSpec(f, screens) {
  const c = ({});
  for (const k in f) if (["key", "part", "def"].indexOf(k) < 0) c[k] = f[k];
  c.key = "hl:" + f.key;
  c.hl = f.key;
  c.fallback = f.def;
  if (typeof f.options === "string") c.options = hyprOptions(f.options, screens);
  return c;
}
// what a file says, each known field the kind it should be, the rest left out
function hyprSanitize(raw) {
  const out = ({});
  for (const f of HYPR_FIELDS)
    if (raw && f.key in raw) out[f.key] = coerce(hyprSpec(f, []), raw[f.key]);
  return out;
}

// settings hyprland has retired, which an older oracle wrote: never kept as
// "written by hand" (base.lua skips them as well)
const HYPR_RETIRED = ["dwindle:special_scale_factor"];

// ["a:b"] = "text" | number | true | false, comments ignored; anything this
// list does not know is kept as it was, but for what hyprland has retired
function parseHyprLua(text) {
  const out = ({});
  const src = stripLuaComments(String(text || ""));
  const re = /\[\s*"([A-Za-z0-9_:.\-]+)"\s*\]\s*=\s*("((?:[^"\\]|\\.)*)"|-?\d+(?:\.\d+)?|true|false)/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const raw = m[2];
    if (HYPR_RETIRED.indexOf(m[1]) >= 0) continue;
    out[m[1]] = m[3] !== undefined ? m[3].replace(/\\(.)/g, "$1")
      : raw === "true" ? true : raw === "false" ? false : Number(raw);
  }
  return out;
}

// every field, under its page's name, then what was written by hand; with
// `known` only the fields (an import: nothing the list does not know)
function renderHyprLua(values, known) {
  const v = values || ({});
  const keys = hyprKeys();
  const width = Math.max.apply(null, keys.map((k) => k.length + 4));
  const line = (k, val) => {
    const lhs = "[\"" + k + "\"]";
    // four places: blur's noise and contrast are hyprland's to four
    const r = typeof val === "number" ? String(Math.round(val * 10000) / 10000) : luaValue(val);
    return "\t" + lhs + " ".repeat(Math.max(0, width - lhs.length)) + " = " + r + ",";
  };
  const lines = [
    "-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐",
    "-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐",
    "-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘",
    "-- https://github.com/kbuckleys/",
    "",
    "-- HYPRLAND",
    "-- Written by oracle, and read back by it: change one there or here,",
    "-- either way works. Each is hyprland's own setting by its own name",
    "-- (`hyprctl descriptions`), and base.lua lays them over its own, one call",
    "-- each. \"\" leaves a setting to hyprland; two numbers in a string, such",
    "-- as \"0 10\", are a pair. zen:gesture:<fingers>:<direction> is a touchpad",
    "-- gesture, and zen:ws:<n>:monitor / :layout a workspace's own rule.",
    "",
    "return {",
  ];
  let section = null;
  for (const f of HYPR_FIELDS) {
    if (f.section !== section) {
      if (section !== null) lines.push("");
      lines.push("\t-- " + f.section);
      section = f.section;
    }
    lines.push(line(f.key, v[f.key] === undefined ? f.def : v[f.key]));
  }
  const extra = known ? [] : Object.keys(v).filter((k) => keys.indexOf(k) < 0).sort();
  if (extra.length) {
    lines.push("", "\t-- written by hand, and kept as it was");
    for (const k of extra) lines.push(line(k, v[k]));
  }
  lines.push("}");
  return lines.join("\n") + "\n";
}

// the pages laid out in PAGES get their parts' hyprland rows
hyprPlace(PAGES);

// ── RECORDS ──
// windows.lua and startup.lua are each a list of flat tables — strings,
// numbers, true/false, nothing nested — so they read like the config they
// feed and a hand edit shows here too. A table that will not read is left
// out rather than guessed at.
function parseLuaRecords(text) {
  const src = stripLuaComments(String(text || ""));
  const at = src.search(/\breturn\s*\{/);
  if (at < 0) return [];
  const body = src.slice(src.indexOf("{", at) + 1);
  const out = [];
  // a table's braces counted outside its strings only: a command's
  // `{1..3}` or a title's "{draft}" is text, not a table (it used to end
  // the record there, and the entry was gone on the next save)
  const tables = [];
  let depth = 0, start = -1;
  for (let i = 0; i < body.length; i++) {
    const ch = body[i];
    if (ch === "\"") {
      for (i++; i < body.length && body[i] !== "\""; i++) if (body[i] === "\\") i++;
    } else if (ch === "{") {
      if (depth++ === 0) start = i + 1;
    } else if (ch === "}") {
      if (depth === 0) break;          // the list's own closing brace
      if (--depth === 0) tables.push(body.slice(start, i));
    }
  }
  for (const t of tables) {
    const rec = {};
    // a bare string is matched (and skipped) whole, so `on=false` inside a
    // command is never read as the field
    const fre = /"(?:[^"\\]|\\.)*"|([A-Za-z_]\w*)\s*=\s*("(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?|true|false)/g;
    let f;
    while ((f = fre.exec(t)) !== null) {
      if (f[1] === undefined) continue;
      const v = f[2];
      rec[f[1]] = v === "true" ? true : v === "false" ? false
        : v[0] === "\"" ? v.slice(1, -1).replace(/\\(.)/g, "$1") : Number(v);
    }
    out.push(rec);
  }
  return out;
}
function luaRecord(rec, order) {
  const parts = [];
  for (const k of order) {
    const v = rec[k];
    if (v === undefined || v === null) continue;
    parts.push(k + " = " + (typeof v === "string" ? luaString(v) : typeof v === "boolean" ? String(v) : String(Number(v) || 0)));
  }
  return "\t{ " + parts.join(", ") + " },";
}
function luaRecordsFile(head, records, order) {
  return head.concat(["", "return {"], records.map((r) => luaRecord(r, order)), ["}", ""]).join("\n");
}
const ZEN_HEAD = [
  "-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐",
  "-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐",
  "-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘",
  "-- https://github.com/kbuckleys/",
  "",
];

// ── WINDOW RULES ──
// Windows' "Window rules" (2026-10-22): how an app's windows open — float,
// size, centered, workspace, opacity, pinned, no blur, keep awake, open
// maximized or full screen, without focus; remember size (hyprland's
// persistent_size, 2026-10-23: a floating window reopens at the size you
// last left it). hypr/lua/windows.lua, one table a
// rule; rules.lua turns each into an hl.window_rule after the suite's own,
// so yours win. `class` is the app's window class as it is (rules.lua
// escapes it: hyprland matches the WHOLE class as a regex), `title` a piece
// of the title, or "" for every window of the app.
const RULE_ORDER = ["name", "class", "title", "on", "float", "size", "center", "workspace", "silent",
                    "opacity", "pin", "no_blur", "idle_inhibit", "open", "no_initial_focus",
                    "persistent_size", "border", "shipped"];
// A class some apps make new at every launch — transmission-gtk's is
// "com.transmissionbt.transmission_<pid>_<random>" — kept without that
// tail, or the rule would only ever match the one window it was picked
// from; rules.lua lets any such tail match again.
function stableClass(cls) { return String(cls || "").replace(/_\d+_\d+$/, ""); }
function blankWindowRule(cls, name, title) {
  return { name: String(name || cls || ""), class: stableClass(cls), title: String(title || ""), on: true,
           float: false, size: "", center: false, workspace: "", silent: false, opacity: 100,
           pin: false, no_blur: false, idle_inhibit: "", open: "", no_initial_focus: false,
           persistent_size: false, border: "", shipped: "" };
}
// The suite's own windows all share quickshell's class and differ only by
// title ("terminus", "plato", "picasso-view" — each Window's title:), so the
// picker lists them a window each and a rule picked from one carries its
// title; rules.lua matches that title whole, so "terminus" is not
// "terminus-picker". Any other app is one row, title left out: its titles
// change (a browser's tab, a file's name), its class does not.
const SHELL_CLASS = "org.quickshell";
// hyprctl clients -j → [{ cls, title, name }] by name; `shipped` names the
// suite's windows (its rule for that title), nameOf(cls) the rest
function windowPickRows(clients, shipped, nameOf) {
  const seen = {}, out = [];
  for (const c of (clients || [])) {
    const cls = stableClass(c.class || c.initialClass || "");
    if (!cls) continue;
    const shell = cls === SHELL_CLASS;
    const title = String((shell ? c.initialTitle || c.title : c.title) || "");
    const key = shell ? cls + "\n" + title : cls;
    if (seen[key]) continue;
    seen[key] = true;
    let name = nameOf ? nameOf(cls) : cls;
    if (shell && title) {
      const own = (shipped || []).find((d) => d.class === SHELL_CLASS && d.title === title);
      name = own && own.name ? own.name : title.charAt(0).toUpperCase() + title.slice(1);
    }
    out.push({ cls: cls, title: title, pin: shell ? title : "", name: name });
  }
  return out.sort((a, b) => a.name.localeCompare(b.name));
}
// a rule's Border: one of the theme's hues (theme.lua's rule_<hue>), or ""
// for the usual one. Never red: red is the urgent flash.
var RULE_BORDERS = ["", "accent", "blue", "green", "yellow", "magenta"];
// a rule as read, with every field there and in range
function normWindowRule(r) {
  const b = blankWindowRule();
  const o = {};
  for (const k of RULE_ORDER) o[k] = (r && r[k] !== undefined && typeof r[k] === typeof b[k]) ? r[k] : b[k];
  const raw = o.class;
  o.class = stableClass(raw);
  if (o.name === raw) o.name = o.class;
  o.opacity = Math.max(10, Math.min(100, Math.round(o.opacity)));
  if (!/^\d+ \d+$/.test(o.size)) o.size = "";
  if (["", "focus", "fullscreen", "always"].indexOf(o.idle_inhibit) < 0) o.idle_inhibit = "";
  if (["", "maximize", "fullscreen"].indexOf(o.open) < 0) o.open = "";
  if (RULE_BORDERS.indexOf(o.border) < 0) o.border = "";
  if (!/^(\d+|special(:\w+)?|name:\S+)?$/.test(o.workspace)) o.workspace = "";
  return o;
}
function parseWindowsLua(text) {
  return parseLuaRecords(text).filter((r) => typeof r.class === "string" && r.class !== "").map(normWindowRule);
}
function renderWindowsLua(rules) {
  return luaRecordsFile(ZEN_HEAD.concat([
    "-- WINDOWS",
    "-- Written by oracle's Windows section (Window rules), and read back by it.",
    "-- A rule a line; rules.lua hands each to hl.window_rule after its own.",
    "-- class    the app's window class, as it is",
    "-- title    a piece of the window's title, or \"\" for all its windows",
    "-- size     \"width height\" (floating only), opacity 10-100",
    "-- persistent_size  floating only: reopens at the size it was left at",
    "-- workspace  \"3\", \"special\" or \"\"; silent keeps you where you are",
    "-- idle_inhibit  \"focus\", \"fullscreen\", \"always\" or \"\"",
    "-- open     \"maximize\", \"fullscreen\" or \"\"",
    "-- border   \"accent\", \"blue\", \"green\", \"yellow\", \"magenta\" or \"\" (the theme's)",
  ]), (rules || []).map(normWindowRule).map((r) => {
    // only a stand-in for a shipped rule says which one
    if (r.shipped === "") delete r.shipped;
    return r;
  }), RULE_ORDER);
}
// The suite's own rules (2026-10-24): hypr/lua/windowdefaults.lua, which
// oracle reads and never writes. Each has a `shipped` name; a rule in
// windows.lua with the same name stands in for it, so a shipped rule is
// changed, or turned off, like one of yours, and put back by dropping the
// stand-in. rules.lua reads both files the same way.
function parseWindowDefaults(text) {
  return parseLuaRecords(text)
    .filter((r) => typeof r.shipped === "string" && r.shipped !== "" && typeof r.class === "string" && r.class !== "")
    .map(normWindowRule);
}
// The list the section shows: yours first, then every shipped rule — your
// stand-in where you changed it. A row is { rule, shipped, base, changed, at }:
// `shipped` its name ("" for one of yours), `base` the shipped rule as it
// ships, `at` its index in yours (-1 for a shipped rule left as it ships).
// A stand-in whose shipped rule is gone is one of yours.
function windowRuleRows(shipped, yours) {
  shipped = shipped || []; yours = yours || [];
  const ids = {};
  for (const d of shipped) ids[d.shipped] = true;
  const rows = [];
  yours.forEach((r, i) => {
    if (!r.shipped || !ids[r.shipped]) rows.push({ rule: r, shipped: "", base: null, changed: false, at: i });
  });
  for (const d of shipped) {
    const at = yours.findIndex((r) => r.shipped === d.shipped);
    rows.push({ rule: at >= 0 ? yours[at] : d, shipped: d.shipped, base: d, changed: at >= 0, at: at });
  }
  return rows;
}
// yours, with row `i` of windowRuleRows changed. A shipped rule changed back
// to just what ships needs no stand-in, so it loses it.
function windowRulesPatched(shipped, yours, i, change) {
  const w = windowRuleRows(shipped, yours)[i];
  const next = (yours || []).map((r) => Object.assign({}, r));
  if (!w) return next;
  if (!w.shipped) { Object.assign(next[w.at], change); return next; }
  const r = normWindowRule(Object.assign({}, w.rule, change, { shipped: w.shipped }));
  if (JSON.stringify(r) === JSON.stringify(w.base)) { if (w.at >= 0) next.splice(w.at, 1); }
  else if (w.at >= 0) next[w.at] = r;
  else next.push(r);
  return next;
}
// yours, with row `i` gone: one of yours is deleted, a shipped rule goes
// back to what ships (to be rid of one, turn it off)
function windowRulesRemoved(shipped, yours, i) {
  const w = windowRuleRows(shipped, yours)[i];
  const next = (yours || []).slice();
  if (w && w.at >= 0) next.splice(w.at, 1);
  return next;
}
// what the rule does, for its row: "Floats · 1200×800 · centered"
function windowRuleWords(r) {
  const w = [];
  if (r.float) w.push("floats" + (r.size ? " " + r.size.replace(" ", "×") : "") + (r.center ? ", centered" : ""));
  else if (r.center) w.push("centered");
  if (r.open) w.push(r.open === "maximize" ? "maximized" : "full screen");
  if (r.workspace) w.push((r.workspace === "special" ? "special workspace" : "workspace " + r.workspace.replace(/^name:/, "")) + (r.silent ? ", quietly" : ""));
  if (r.opacity < 100) w.push(r.opacity + "% opaque");
  if (r.pin && r.float) w.push("pinned");     // rules.lua pins floating windows only
  if (r.persistent_size && r.float) w.push("remembers its size");
  if (r.no_blur) w.push("no blur");
  if (r.idle_inhibit) w.push("keeps awake" + (r.idle_inhibit === "always" ? "" : r.idle_inhibit === "focus" ? " while focused" : " in full screen"));
  if (r.no_initial_focus) w.push("opens unfocused");
  if (r.border) w.push(r.border + " border");
  if (!w.length) return "does nothing yet";
  const s = w.join(" · ");
  return s[0].toUpperCase() + s.slice(1);
}
function windowRulesSummary(rules, shipped) {
  const rows = windowRuleRows(shipped, rules);
  const n = rows.filter((w) => !w.shipped).length;
  const s = rows.length - n;
  const off = rows.filter((w) => !w.rule.on).length;
  const parts = [];
  if (n) parts.push(n + (n === 1 ? " rule" : " rules"));
  if (s) parts.push(s + " shipped");
  if (off) parts.push(off + " off");
  return parts.length ? parts.join(" · ") : "none";
}

// ── STARTUP ──
// Windows' "Startup apps" (2026-10-22): what hyprland starts at login
// besides the suite's own. hypr/lua/startup.lua, one table an app;
// autostart.lua runs the ones that are on, `delay` seconds after the start.
// The suite's own lines in autostart.lua stay there: STARTUP_OWN names
// them for the list, each with the process that says it is up.
const STARTUP_ORDER = ["name", "command", "on", "delay"];
const STARTUP_OWN = [
  { name: "This shell", look: "quickshell" },
  { name: "Clipboard keeper", look: "wl-clip-persist" },
  { name: "Clipboard history · text", look: "wl-paste --type text --watch" },
  { name: "Clipboard history · images", look: "wl-paste --type image --watch" },
  { name: "Password prompts (polkit)", look: "hyprpolkitagent" },
];
function startupOwn() { return STARTUP_OWN; }
function normStartup(r) {
  return { name: String(r && typeof r.name === "string" ? r.name : ""),
           command: String(r && typeof r.command === "string" ? r.command : ""),
           on: !(r && r.on === false),
           delay: Math.max(0, Math.min(600, Math.round(Number(r && r.delay) || 0))) };
}
function parseStartupLua(text) {
  return parseLuaRecords(text).filter((r) => typeof r.command === "string" && r.command.trim() !== "").map(normStartup);
}
function renderStartupLua(apps) {
  return luaRecordsFile(ZEN_HEAD.concat([
    "-- STARTUP",
    "-- Written by oracle's Windows section (Startup apps), and read back by it.",
    "-- What starts at login besides the shell's own (those are autostart.lua's).",
    "-- command  run as it is; on = false keeps it from starting",
    "-- delay    seconds after hyprland starts, 0-600",
  ]), (apps || []).map(normStartup), STARTUP_ORDER);
}
// The process an entry starts: its first word that is not an env setting or
// a wrapper, by name — what `ps -eo args` is searched for.
function startupLook(command) {
  const words = String(command || "").trim().split(/\s+/);
  let i = 0;
  while (i < words.length && (/^\w+=/.test(words[i]) || ["env", "sh", "-c", "exec", "nice", "uwsm", "app", "--", "gtk-launch", "flatpak", "run"].indexOf(words[i]) >= 0)) i++;
  const w = (words[i] || "").replace(/^['"]|['"]$/g, "");
  // a shell script's first word is the shell's, not a program to look for
  // ("for" would be found in nearly every line ps prints)
  if (["for", "while", "until", "if", "case", "{", "(", "!"].indexOf(w) >= 0) return "";
  return w.slice(w.lastIndexOf("/") + 1);
}
// is `look` in one of `ps -eo args=`'s lines (not ps' own, not a grep)?
function startupRunning(psText, look) {
  if (!look) return false;
  const lines = String(psText || "").split("\n");
  for (const l of lines) {
    if (l.indexOf(look) < 0) continue;
    if (/^(ps|pgrep|grep) /.test(l)) continue;
    return true;
  }
  return false;
}
// What a desktop entry's Exec runs at login: its field codes (%U, --uri=%u)
// gone, and the options that only led up to them ("--url --") with them.
function execForStartup(exec) {
  const words = String(exec || "").trim().split(/\s+/).filter((w) => w !== "");
  const code = (w) => /%[a-zA-Z]/.test(w);
  // from the end: a code, and the options that led up to it
  while (words.length > 1 && code(words[words.length - 1])) {
    words.pop();
    while (words.length > 1 && /^-/.test(words[words.length - 1])) words.pop();
  }
  return words.filter((w) => !code(w)).join(" ");
}
// "Discord" from "discord --start-minimized", for a command added by hand
function startupName(command) {
  const w = startupLook(command);
  return w ? w[0].toUpperCase() + w.slice(1) : "";
}

// only what differs from binds.lua, in its order; ids the list no longer has
// are dropped, so a bind taken out of binds.lua takes its override with it
function renderKeysLua(values, binds) {
  const lines = [
    "-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐",
    "-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐",
    "-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘",
    "-- https://github.com/kbuckleys/",
    "",
    "-- KEYS",
    "-- Written by oracle's Shortcuts section, and read back by it: change one",
    "-- there or here, either way works. Only the binds moved off the keys",
    "-- binds.lua gives them are named; \"\" turns one off.",
    "",
    "return {"
  ];
  const v = values || ({});
  const moved = binds.filter((b) => b.id in v && normChord(v[b.id]) !== b.chord);
  const w = Math.max(0, ...moved.map((b) => b.id.length));
  for (const b of moved)
    lines.push("\t" + b.id + " ".repeat(w - b.id.length) + " = " + luaString(normChord(v[b.id])) + ",");
  lines.push("}");
  return lines.join("\n") + "\n";
}

const CHORD_MODS = ["SUPER", "SHIFT", "CONTROL", "ALT"];
const MOD_ALIAS = { CTRL: "CONTROL", WIN: "SUPER", LOGO: "SUPER", META: "SUPER", MOD4: "SUPER", MOD1: "ALT" };
const MOD_MASK = { SHIFT: 1, CONTROL: 4, ALT: 8, SUPER: 64 };

// one spelling for a chord: the modifiers in CHORD_MODS' order, upper case,
// then the key — "ctrl + super + k" and "SUPER + CONTROL + K" are one chord.
// A mouse button keeps hyprland's own spelling, mouse:272.
function normChord(c) {
  const parts = String(c === null || c === undefined ? "" : c).split("+")
    .map((p) => p.trim()).filter((p) => p !== "");
  if (!parts.length) return "";
  let key = parts.pop();
  const mods = ({});
  for (const p of parts) mods[MOD_ALIAS[p.toUpperCase()] || p.toUpperCase()] = true;
  // a bare modifier names itself as the key
  if (MOD_ALIAS[key.toUpperCase()] || CHORD_MODS.indexOf(key.toUpperCase()) >= 0) {
    mods[MOD_ALIAS[key.toUpperCase()] || key.toUpperCase()] = true;
    key = "";
  }
  key = /^(mouse|code):/i.test(key) ? key.toLowerCase() : key.toUpperCase();
  const out = CHORD_MODS.filter((m) => mods[m]);
  if (key !== "") out.push(key);
  return out.join(" + ");
}

// what hyprctl binds -j calls it: { mask, key }, the key upper case
function chordMask(c) {
  const parts = normChord(c).split(" + ");
  const key = parts.pop() || "";
  let mask = 0;
  for (const p of parts) mask |= MOD_MASK[p] || 0;
  return { mask: mask, key: key.toUpperCase() };
}

// the caps a chord is drawn on: Super, Shift, Ctrl, Alt, then the key
const KEY_LABELS = {
  RETURN: "Return", ESCAPE: "Esc", SPACE: "Space", TAB: "Tab", PRINT: "Print",
  GRAVE: "`", MINUS: "-", EQUAL: "=", PLUS: "+", COMMA: ",", PERIOD: ".", SLASH: "/",
  BACKSLASH: "\\", SEMICOLON: ";", APOSTROPHE: "'", BRACKETLEFT: "[", BRACKETRIGHT: "]",
  LEFT: "←", RIGHT: "→", UP: "↑", DOWN: "↓",
  BACKSPACE: "Backspace", DELETE: "Delete", INSERT: "Insert", HOME: "Home", END: "End",
  PRIOR: "Page Up", NEXT: "Page Down", PAGE_UP: "Page Up", PAGE_DOWN: "Page Down",
  "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click",
  "mouse:275": "Back button", "mouse:276": "Forward button",
  MOUSE_UP: "Wheel up", MOUSE_DOWN: "Wheel down",
  XF86AUDIORAISEVOLUME: "Volume up", XF86AUDIOLOWERVOLUME: "Volume down",
  XF86AUDIOMUTE: "Mute", XF86AUDIOPLAY: "Play", XF86AUDIONEXT: "Next", XF86AUDIOPREV: "Previous"
};
function chordCaps(c) {
  const n = normChord(c);
  if (n === "") return [];
  const mods = { SUPER: "Super", SHIFT: "Shift", CONTROL: "Ctrl", ALT: "Alt" };
  return n.split(" + ").map((p) => mods[p] || KEY_LABELS[p]
    || (p.length === 1 ? p : p.charAt(0) + p.slice(1).toLowerCase()));
}

// ── a key pressed, as hyprland names it ──
// `key` is Qt's (Qt.Key_*), `mods` Qt's modifier flags, `text` what the
// press typed. Hyprland matches the UNSHIFTED key — Super+Shift+1, not
// Super+! — so a shifted symbol is put back on its key (a US keyboard's
// pairs: the layouts this shell is set up with). "" for a press that is
// only a modifier, or one there is no name for.
const QT_KEYS = {
  0x01000000: "ESCAPE", 0x01000001: "TAB", 0x01000002: "TAB", 0x01000003: "BACKSPACE",
  0x01000004: "RETURN", 0x01000005: "RETURN", 0x01000006: "INSERT", 0x01000007: "DELETE",
  0x01000009: "PRINT", 0x01000010: "HOME", 0x01000011: "END",
  0x01000012: "LEFT", 0x01000013: "UP", 0x01000014: "RIGHT", 0x01000015: "DOWN",
  0x01000016: "PRIOR", 0x01000017: "NEXT", 0x20: "SPACE",
  0x01000070: "XF86AudioLowerVolume", 0x01000071: "XF86AudioMute",
  0x01000072: "XF86AudioRaiseVolume", 0x01000080: "XF86AudioPlay",
  0x01000082: "XF86AudioPrev", 0x01000083: "XF86AudioNext"
};
const SYMBOL_KEYS = {
  "`": "GRAVE", "~": "GRAVE", "-": "MINUS", "_": "MINUS", "=": "EQUAL", "+": "EQUAL",
  "[": "BRACKETLEFT", "{": "BRACKETLEFT", "]": "BRACKETRIGHT", "}": "BRACKETRIGHT",
  "\\": "BACKSLASH", "|": "BACKSLASH", ";": "SEMICOLON", ":": "SEMICOLON",
  "'": "APOSTROPHE", "\"": "APOSTROPHE", ",": "COMMA", "<": "COMMA",
  ".": "PERIOD", ">": "PERIOD", "/": "SLASH", "?": "SLASH",
  "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0"
};
function chordFromKey(key, mods, text) {
  let name = QT_KEYS[key] || "";
  if (name === "" && key >= 0x01000030 && key <= 0x01000052) name = "F" + (key - 0x01000030 + 1);
  if (name === "" && ((key >= 0x30 && key <= 0x39) || (key >= 0x41 && key <= 0x5a)))
    name = String.fromCharCode(key);
  if (name === "") {
    const ch = key > 0x20 && key < 0x7f ? String.fromCharCode(key) : String(text || "");
    name = SYMBOL_KEYS[ch] || "";
  }
  if (name === "") return "";
  const out = [];
  if (mods & 0x10000000) out.push("SUPER");     // Qt.MetaModifier
  if (mods & 0x02000000) out.push("SHIFT");
  if (mods & 0x04000000) out.push("CONTROL");
  if (mods & 0x08000000) out.push("ALT");
  out.push(name);
  return normChord(out.join(" + "));
}

// a mouse button pressed on the capture chip: Qt's button → mouse:27x
function chordFromButton(button, mods) {
  const code = { 1: 272, 2: 273, 4: 274, 8: 275, 16: 276 }[button];
  if (!code) return "";
  const out = [];
  if (mods & 0x10000000) out.push("SUPER");
  if (mods & 0x02000000) out.push("SHIFT");
  if (mods & 0x04000000) out.push("CONTROL");
  if (mods & 0x08000000) out.push("ALT");
  // a bare click is every click: hyprland would take the pointer away
  if (!out.length) return "";
  out.push("mouse:" + code);
  return normChord(out.join(" + "));
}

// ── NO TWO BINDS ON ONE CHORD ──
// Which bind already answers `chord`, as words for the refusal, or "".
// `values` is id → chord now; `live` is hyprctl binds -j, for the binds the
// other files make (smart-move, zoom, the recorder) — ours carry their label
// as the description, and are told apart by it.
function chordTaken(chord, id, binds, values, live) {
  const n = normChord(chord);
  if (n === "") return "";
  for (const b of binds) {
    if (b.id === id) continue;
    const v = values && b.id in values ? normChord(values[b.id]) : b.chord;
    if (v === n) return b.label;
  }
  const ours = ({});
  for (const b of binds) ours[b.label] = true;
  const m = chordMask(n);
  for (const l of (Array.isArray(live) ? live : [])) {
    if (l.submap || ours[l.description]) continue;
    if (Number(l.modmask) === m.mask && String(l.key).toUpperCase() === m.key)
      return l.description || "another hyprland bind";
  }
  return "";
}

// ── SETTINGS, CARRIED ELSEWHERE ───────────────────────────────────────────
// Export / Import in About (2026-10-21): one JSON file holding oracle.json,
// the hypr files Oracle writes (keys, wake, effects, default apps, input, screens)
// and the themes you saved — for a reinstall or another machine. Settings
// only: no notes, no screen time, no passwords. A bundle names its files
// by these relative paths, and nothing outside them is ever written back.
const BUNDLE_FIXED = ["oracle.json", "hypr/keys.lua", "hypr/wake.lua", "hypr/effects.lua", "hypr/defaults.lua",
                      "hypr/input.lua", "hypr/inputmethod.lua", "hypr/windows.lua", "hypr/startup.lua",
                      "hypr/monitors.lua", "hypr/hyprland.lua"];
const BUNDLE_WORDS = { "oracle.json": "Settings", "hypr/keys.lua": "Shortcuts", "hypr/wake.lua": "Wake by",
                       "hypr/effects.lua": "Window shadows and animations",
                       "hypr/defaults.lua": "Default apps", "hypr/input.lua": "Keyboard and mouse",
                       "hypr/inputmethod.lua": "Input methods",
                       "hypr/windows.lua": "Window rules", "hypr/startup.lua": "Startup apps",
                       "hypr/monitors.lua": "Screen arrangement",
                       "hypr/hyprland.lua": "Hyprland settings" };
function bundlePathOk(rel) {
  const r = String(rel || "");
  return BUNDLE_FIXED.indexOf(r) >= 0 || /^themes\/[A-Za-z0-9][A-Za-z0-9_-]*\.json$/.test(r);
}
function makeBundle(files, made) {
  const keep = {};
  for (const rel of Object.keys(files).sort()) if (bundlePathOk(rel) && typeof files[rel] === "string") keep[rel] = files[rel];
  return JSON.stringify({ zenworks: "settings", v: 1, made: made, files: keep }, null, 1) + "\n";
}
// { ok, why, made, files: { rel: text }, skipped }
function readBundle(text) {
  let j = null;
  try { j = JSON.parse(text); } catch (e) {}
  if (!j || j.zenworks !== "settings" || !j.files || typeof j.files !== "object")
    return { ok: false, why: "Not a Zenworks settings file", made: "", files: {}, skipped: 0 };
  const files = {};
  let skipped = 0;
  for (const rel in j.files) {
    if (bundlePathOk(rel) && typeof j.files[rel] === "string") files[rel] = j.files[rel];
    else skipped++;
  }
  if (!Object.keys(files).length) return { ok: false, why: "There are no settings in it", made: "", files: {}, skipped: skipped };
  return { ok: true, why: "", made: String(j.made || ""), files: files, skipped: skipped };
}
// May an imported theme land where `existing` (that file's text here, or
// null) is? Only over nothing or over one of your own: a bundle naming a
// shipped theme ("themes/dracula.json") would otherwise replace it.
function bundleThemeWritable(existing) {
  if (existing === null || existing === undefined || existing === "") return true;
  try { const t = JSON.parse(existing); return !!(t && t.custom === true); } catch (e) { return false; }
}
// what a bundle holds, a line each, in BUNDLE_FIXED's order, themes last
function bundleWords(files) {
  const out = [];
  for (const rel of BUNDLE_FIXED) if (rel in files) out.push(BUNDLE_WORDS[rel]);
  const themes = Object.keys(files).filter((r) => r.startsWith("themes/")).sort();
  for (const r of themes) out.push("Theme " + r.slice(7, -5));
  return out;
}
// WHAT AN IMPORT MAY WRITE (2026-10-24). hyprland `require`s every
// hypr/*.lua, so a bundle's text written as it came ran whatever Lua it
// held at the next reload: a settings file someone shared was a program.
// Each is read through its own parser and written fresh by its own
// renderer, so only the values those know come through — the same file
// Oracle itself would write for them. monitors.lua's lines written by hand
// do not. oracle.json and themes are JSON, read as data, and pass as they
// are. `binds` is binds.lua's list (Oracle.bindList); with none, every
// shortcut the bundle names is kept.
function sanitizeBundleFile(rel, text, binds) {
  const t = String(text || "");
  switch (rel) {
    case "hypr/keys.lua": {
      const v = parseDefaultsLua(t);
      const b = (binds && binds.length) ? binds
        : Object.keys(v).map((id) => ({ id: id, chord: null }));
      return renderKeysLua(v, b);
    }
    case "hypr/wake.lua": return renderWakeLua(parseWakeLua(t));
    case "hypr/inputmethod.lua": return renderImLua(parseImLua(t));
    case "hypr/effects.lua": return renderEffectsLua(parseEffectsLua(t));
    // only the fields, each the kind it should be
    case "hypr/hyprland.lua": return renderHyprLua(hyprSanitize(parseHyprLua(t)), true);
    case "hypr/defaults.lua": return renderDefaultsLua(parseDefaultsLua(t));
    case "hypr/input.lua": {
      const v = parseInputLua(t);
      for (const k in v) if (typeof v[k] === "number" && !isFinite(v[k])) delete v[k];
      return renderInputLua(v);
    }
    case "hypr/windows.lua": return renderWindowsLua(parseWindowsLua(t));
    case "hypr/startup.lua": return renderStartupLua(parseStartupLua(t));
    case "hypr/monitors.lua": {
      // the catch-all rule ("") is the renderer's own first line
      const rules = parseMonitorRules(t).filter((r) => r.output !== "").map((r) => {
        const f = {};
        for (const k in r.fields) if (typeof r.fields[k] !== "number" || isFinite(r.fields[k])) f[k] = r.fields[k];
        return { output: r.output, fields: f };
      });
      return renderMonitorRules([], rules, []);
    }
  }
  return t;
}
// The commands an import would have run for you, for the sheet to show
// before it is taken: every startup app, and the default apps that are a
// command rather than a desktop id. [{ what, command, off }]
function bundleCommands(files) {
  const out = [];
  const f = files || {};
  if (typeof f["hypr/startup.lua"] === "string")
    for (const a of parseStartupLua(f["hypr/startup.lua"]))
      out.push({ what: "At login" + (a.name ? " · " + a.name : ""), command: a.command, off: !a.on });
  if (typeof f["hypr/defaults.lua"] === "string") {
    const d = parseDefaultsLua(f["hypr/defaults.lua"]);
    const named = { terminal: "Terminal", editor: "Editor", sysmon: "System monitor" };
    for (const k in named) {
      const c = String(d[k] || "").trim();
      if (c !== "" && !(k === "sysmon" && (c === "zeus" || /\.desktop$/.test(c))))
        out.push({ what: named[k], command: c, off: false });
    }
  }
  return out;
}

// ── DATE & TIME (2026-10-29) ──────────────────────────────────────────────
// The time zone, the network clock and the hardware clock are systemd's
// (timedatectl), not oracle.json's; the world map under them is WorldMap.qml.

// "+3003+03115" or "-0745+11036" (zone.tab's ±DDMM±DDDMM, seconds allowed)
// as { lat, lon } in degrees, or null
function parseIso6709(s) {
  const m = /^([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$/.exec(String(s || ""));
  if (!m) return null;
  const deg = (sign, d, mi, se) => (sign === "-" ? -1 : 1) * (Number(d) + Number(mi) / 60 + Number(se || 0) / 3600);
  return { lat: deg(m[1], m[2], m[3], m[4]), lon: deg(m[5], m[6], m[7], m[8]) };
}

// A zone's city as people say it: "America/Argentina/Buenos_Aires" is
// "Buenos Aires (Argentina)"
function zoneCity(zone) {
  const parts = String(zone || "").split("/");
  const city = parts[parts.length - 1].replace(/_/g, " ");
  return parts.length > 2 ? city + " (" + parts.slice(1, -1).join(", ").replace(/_/g, " ") + ")" : city;
}
function zoneRegion(zone) {
  const z = String(zone || "");
  return z.indexOf("/") < 0 ? "Other" : z.split("/")[0];
}

// zone.tab (one row per country and zone) as
// [{ zone, region, city, lat, lon }], by region then city. A zone two
// countries share is listed once.
function parseZoneTab(text) {
  const out = [];
  const seen = {};
  for (const line of String(text || "").split("\n")) {
    if (line === "" || line[0] === "#") continue;
    const f = line.split("\t");
    if (f.length < 3 || seen[f[2]]) continue;
    const at = parseIso6709(f[1]);
    if (!at) continue;
    seen[f[2]] = true;
    out.push({ zone: f[2], region: zoneRegion(f[2]), city: zoneCity(f[2]), lat: at.lat, lon: at.lon });
  }
  out.sort((a, b) => a.region < b.region ? -1 : a.region > b.region ? 1 : a.city < b.city ? -1 : a.city > b.city ? 1 : 0);
  return out;
}

// the regions, for the Time zone row's first chip; the zone worn is always
// among them, listed or not (UTC, Etc/GMT+3)
function zoneRegionOptions(zones, worn) {
  const out = [];
  const seen = {};
  for (const z of zones) if (!seen[z.region]) { seen[z.region] = true; out.push(z.region); }
  const w = zoneRegion(worn);
  if (worn && !seen[w]) out.push(w);
  return out.map((r) => ({ value: r, label: r }));
}
// a region's cities, for the second chip
function zoneCityOptions(zones, region, worn) {
  const out = zones.filter((z) => z.region === region).map((z) => ({ value: z.zone, label: z.city }));
  if (worn && zoneRegion(worn) === region && !out.some((o) => o.value === worn))
    out.unshift({ value: worn, label: zoneCity(worn) });
  return out;
}

// the zone whose city is nearest a point, by great circle; null in an empty list
function nearestZone(zones, lat, lon) {
  const r = Math.PI / 180;
  let best = null, bestD = Infinity;
  const sl = Math.sin(lat * r), cl = Math.cos(lat * r);
  for (const z of zones) {
    const d = -(sl * Math.sin(z.lat * r) + cl * Math.cos(z.lat * r) * Math.cos((z.lon - lon) * r));
    if (d < bestD) { bestD = d; best = z; }
  }
  return best;
}

// `timedatectl show` as { zone, ntp, canNtp, synced, localRtc, abbrev }
function parseTimedate(text) {
  const kv = {};
  for (const line of String(text || "").split("\n")) {
    const i = line.indexOf("=");
    if (i > 0) kv[line.slice(0, i)] = line.slice(i + 1).trim();
  }
  const yes = (k) => kv[k] === "yes";
  // "Thu 2026-10-29 19:29:34 EEST": the zone's abbreviation is the last word
  const t = String(kv.TimeUSec || "").split(" ");
  return { zone: kv.Timezone || "", ntp: yes("NTP"), canNtp: yes("CanNTP"), synced: yes("NTPSynchronized"),
           localRtc: yes("LocalRTC"), abbrev: t.length > 3 ? t[t.length - 1] : "" };
}

// minutes east of UTC as "UTC+3", "UTC−4:30", "UTC"
function utcOffsetText(mins) {
  const m = Math.round(Number(mins) || 0);
  if (m === 0) return "UTC";
  const a = Math.abs(m);
  return "UTC" + (m < 0 ? "−" : "+") + Math.floor(a / 60) + (a % 60 ? ":" + String(a % 60).padStart(2, "0") : "");
}

// The point the sun stands straight over at a moment (ms since the epoch),
// { lat, lon } in degrees: the almanac's low-precision formulae, good to a
// fraction of a degree, which at a map's scale is under a pixel.
function subsolar(ms) {
  const r = Math.PI / 180;
  const n = ms / 86400000 + 2440587.5 - 2451545.0;
  const L = ((280.460 + 0.9856474 * n) % 360 + 360) % 360;
  const g = ((357.528 + 0.9856003 * n) % 360 + 360) % 360 * r;
  const lam = (L + 1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g)) * r;
  const eps = (23.439 - 0.0000004 * n) * r;
  const dec = Math.asin(Math.sin(eps) * Math.sin(lam));
  const ra = Math.atan2(Math.cos(eps) * Math.sin(lam), Math.cos(lam)) / r;
  // the equation of time, in degrees of turn (4 minutes each)
  let eot = L - ra;
  eot = ((eot + 180) % 360 + 360) % 360 - 180;
  const utcH = ((ms / 3600000) % 24 + 24) % 24;
  let lon = -15 * (utcH - 12) - eot;
  lon = ((lon + 180) % 360 + 360) % 360 - 180;
  return { lat: dec / r, lon: lon };
}

// Down one meridian, the latitudes where the sun stands higher than `alt`
// degrees (0 the horizon, −6 the end of civil twilight): a list of
// [south, north] spans, empty in a polar night. Along a meridian the sun's
// height is R·cos(lat − φ0), so each span is φ0 ± a, cut to the poles.
function daySpans(lon, sun, alt) {
  const r = Math.PI / 180;
  const A = Math.sin(sun.lat * r), B = Math.cos(sun.lat * r) * Math.cos((lon - sun.lon) * r);
  const R = Math.sqrt(A * A + B * B);
  const s = Math.sin((alt || 0) * r);
  if (R < 1e-9) return s < 0 ? [[-90, 90]] : [];
  const c = s / R;
  if (c >= 1) return [];
  if (c <= -1) return [[-90, 90]];
  const phi = Math.atan2(A, B) / r, a = Math.acos(c) / r;
  const out = [];
  for (const k of [-360, 0, 360]) {
    const lo = Math.max(-90, phi - a + k), hi = Math.min(90, phi + a + k);
    if (lo < hi) out.push([lo, hi]);
  }
  return out;
}
