// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

// The name a background goes by in the picker: the file's own, without the
// directory or the extension.
.pragma library
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file — every row, tile, card and sheet — evaluated all of
// it again; a profile caught terminus.js and icons.js costing hundreds of ms
// that way (qmlprofiler, 2026-10-09).

function label(path) {
  const base = String(path || "").split("/").pop();
  const dot = base.lastIndexOf(".");
  return dot > 0 ? base.slice(0, dot) : base;
}

// The path with the background root stripped off, e.g. "ether/pack_21/eveWS".
// This is what the filter matches: the scan is recursive, and typing a
// directory's name is the only way to narrow to one pack without a tree view.
function rel(path, dir) {
  const p = String(path || "");
  const d = String(dir || "");
  return (d !== "" && p.indexOf(d + "/") === 0) ? p.slice(d.length + 1) : p;
}

// A row is { path, thumb, mtime, size }: the background, the cached thumbnail
// the picker actually draws (thumb is "" when one could not be generated),
// and the two facts the ordering needs.
function filter(files, query, dir) {
  const q = String(query || "").trim().toLowerCase();
  if (q === "") return files;
  return files.filter((f) => rel(f.path, dir).toLowerCase().indexOf(q) >= 0);
}

// scan() emits "<path>\t<thumb>\t<mtime>\t<size>" per line; a line with the
// wrong field count is a filename with a tab in it, and is dropped rather
// than half-parsed into a row that would sort somewhere absurd.
function parseRows(text) {
  const out = [];
  for (const line of String(text || "").split("\n")) {
    if (line.trim() === "") continue;
    const parts = line.split("\t");
    if (parts.length !== 4) continue;
    out.push({
      path: parts[0],
      thumb: parts[1],
      mtime: parseFloat(parts[2]) || 0,
      size: parseInt(parts[3], 10) || 0
    });
  }
  return out;
}

// Ordering. Sorts a COPY: the caller's array is the scan's own result and is
// shared with everything else reading it.
function sortRows(files, mode, dir) {
  const out = (files || []).slice();
  if (mode === "name")
    out.sort((a, b) => rel(a.path, dir).localeCompare(rel(b.path, dir)));
  else if (mode === "size")
    out.sort((a, b) => b.size - a.size);
  else
    // "recent" — newest first, which is the default
    out.sort((a, b) => b.mtime - a.mtime);
  return out;
}

function parse(text) {
  try {
    const v = JSON.parse(text || "{}");
    return (v && typeof v === "object" && !Array.isArray(v)) ? v : {};
  } catch (e) {
    return {};
  }
}

// ── solid colours ─────────────────────────────────────────────────────────
// A colour is assigned exactly like a picture — the same maps, the same
// per-monitor keys — so it needs a spelling that can never be a path. No
// path starts with "color:", which is the whole of the trick; everything that
// reads an assignment asks isColor() before it treats one as a file.
function isColor(p) { return String(p || "").indexOf("color:") === 0; }

// "#rrggbb", or "" for anything that is not a colour assignment
function colorOf(p) {
  if (!isColor(p)) return "";
  const hex = normHex(String(p).slice(6));
  return hex;
}

function colorPath(hex) {
  const h = normHex(hex);
  return h === "" ? "" : "color:" + h;
}

// "#abc", "abc", "#AABBCC" -> "#aabbcc"; anything else -> ""
function normHex(v) {
  let h = String(v || "").trim().replace(/^#/, "").toLowerCase();
  if (/^[0-9a-f]{3}$/.test(h)) h = h.split("").map((c) => c + c).join("");
  return /^[0-9a-f]{6}$/.test(h) ? "#" + h : "";
}

// The presets. Dark first, because a background is behind everything and the
// darks are what most people reach for; then the shell's own accents, so a
// desktop can wear the palette the bar already speaks; then a few deeper
// tones that are not in it.
const presetColors = [
  { hex: "#000000", name: "Black" },
  { hex: "#0b0d10", name: "Ink" },
  { hex: "#14171c", name: "Night" },
  { hex: "#20242a", name: "Slate" },
  { hex: "#2e343d", name: "Graphite" },
  { hex: "#45505c", name: "Storm" },
  { hex: "#6a707f", name: "Ash" },
  { hex: "#dfdfdd", name: "Paper" },
  { hex: "#9bbfbf", name: "Cyan" },
  { hex: "#9fcbfc", name: "Blue" },
  { hex: "#c8a4e0", name: "Violet" },
  { hex: "#eebebe", name: "Rose" },
  { hex: "#e78284", name: "Red" },
  { hex: "#fab387", name: "Peach" },
  { hex: "#e0d8a4", name: "Sand" },
  { hex: "#b6e0a4", name: "Green" },
  { hex: "#1d3b3b", name: "Deep teal" },
  { hex: "#1b2a44", name: "Navy" },
  { hex: "#2d1f3d", name: "Plum" },
  { hex: "#3b1d24", name: "Wine" },
  { hex: "#3a2a1a", name: "Umber" },
  { hex: "#1f3322", name: "Forest" },
  { hex: "#3d3a2a", name: "Olive" },
  { hex: "#26262b", name: "Charcoal" }
];

// ── colour arithmetic for the picker ─────────────────────────────────────
// HSV in 0..1 each, because that is the shape of the square you drag in.
function hexToHsv(hex) {
  const h = normHex(hex);
  if (h === "") return { h: 0, s: 0, v: 0 };
  const r = parseInt(h.slice(1, 3), 16) / 255;
  const g = parseInt(h.slice(3, 5), 16) / 255;
  const b = parseInt(h.slice(5, 7), 16) / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let hue = 0;
  if (d > 0) {
    if (max === r) hue = ((g - b) / d) % 6;
    else if (max === g) hue = (b - r) / d + 2;
    else hue = (r - g) / d + 4;
    hue /= 6;
    if (hue < 0) hue += 1;
  }
  return { h: hue, s: max === 0 ? 0 : d / max, v: max };
}

function hsvToHex(h, s, v) {
  const i = Math.floor(h * 6) % 6, f = h * 6 - Math.floor(h * 6);
  const p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  const rgb = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i];
  return "#" + rgb.map((c) => {
    const n = Math.round(Math.max(0, Math.min(1, c)) * 255);
    return (n < 16 ? "0" : "") + n.toString(16);
  }).join("");
}

// ── how a picture is laid on a monitor ────────────────────────────────────
// Everything past the image and its fit, per monitor. A monitor only stores
// what it has CHANGED from these; lookOf() fills in the rest, so a new option
// arriving later reads as its default on every monitor that never touched it.
const lookDefaults = {
  rotate: 0,          // 0, 90, 180, 270 — clockwise
  mirror: false,      // flipped left to right
  align: "c",         // which part a crop keeps: tl t tr l c r bl b br
  backdrop: "black",  // what shows around a picture that does not fill:
                      //   black, color, accent (taken from the image), blur
  backdropColor: "#20242a",
  dim: 0,             // 0 .. 0.8, black laid over the top
  vignette: 0,        // 0 .. 1, the edges darkened towards the corners
  blur: 0,            // 0 .. 1
  saturation: 0,      // -1 (grey) .. 1
  brightness: 0,      // -1 .. 1, lifted or lowered before the tint
  contrast: 0,        // -1 .. 1
  tint: "",           // "" none, "accent", or "#rrggbb"
  tintAmount: 0.5     // 0 .. 1
};

const alignKeys = ["tl", "t", "tr", "l", "c", "r", "bl", "b", "br"];

function lookOf(partial) {
  const out = Object.assign({}, lookDefaults);
  const p = partial || {};
  for (const k in lookDefaults) if (k in p) out[k] = p[k];
  out.rotate = [0, 90, 180, 270].indexOf(out.rotate) >= 0 ? out.rotate : 0;
  if (alignKeys.indexOf(out.align) < 0) out.align = "c";
  return out;
}

// Only what differs from the defaults, which is what gets written down.
function lookDiff(look) {
  const out = {};
  const l = lookOf(look);
  for (const k in lookDefaults) if (l[k] !== lookDefaults[k]) out[k] = l[k];
  return out;
}

// is anything asked of the effect pass at all — it costs a layer, so a
// monitor with a plain look must not pay for one
function lookNeedsFx(look) {
  const l = lookOf(look);
  return l.blur > 0 || l.saturation !== 0 || l.brightness !== 0 || l.contrast !== 0
    || (l.tint !== "" && l.tintAmount > 0);
}

// The swatches a look's tint is chosen from, and what can fill the space
// around a picture — one list each, read by the card's controls and by its
// keyboard, and by the viewer's edit panel, so the three step through the
// same answers.
var tintPresets = ["", "accent", "#9bbfbf", "#9fcbfc", "#c8a4e0",
                     "#eebebe", "#fab387", "#b6e0a4", "custom"];
var backdropKeys = ["black", "color", "accent", "blur"];

// Qt's alignment flags for a crop position: [horizontal, vertical]
function alignFlags(a) {
  const k = alignKeys.indexOf(a) < 0 ? 4 : alignKeys.indexOf(a);
  const col = k % 3, row = Math.floor(k / 3);
  return [[1, 4, 2][col], [32, 128, 64][row]];   // Left HCenter Right, Top VCenter Bottom
}

// A crop position is chosen against the SCREEN — "keep the top" means the top
// of the monitor you are looking at — but the image is laid in a frame that
// may be mirrored and turned, where its own top is somewhere else. So the
// screen's position is carried back through the turn (anticlockwise) and the
// mirror, which is the frame's transform run in reverse.
function alignInFrame(align, rotate, mirror) {
  const k = alignKeys.indexOf(align) < 0 ? 4 : alignKeys.indexOf(align);
  let x = (k % 3) - 1, y = Math.floor(k / 3) - 1;
  for (let n = ((rotate || 0) / 90) % 4; n > 0; --n) { const t = x; x = y; y = -t; }
  if (mirror) x = -x;
  return alignKeys[(y + 1) * 3 + (x + 1)];
}

// The box a picture is drawn into, in the monitor's own coordinates.
// `target` is the region the picture covers — the monitor itself, or for a
// span the whole desk moved into this monitor's frame. A quarter turn swaps
// the box's sides, and the box is centred on the target so it turns in place.
function frameRect(target, rotate) {
  const q = rotate === 90 || rotate === 270;
  const w = q ? target.h : target.w, h = q ? target.w : target.h;
  return { x: target.x + (target.w - w) / 2, y: target.y + (target.h - h) / 2, w: w, h: h };
}

// The bounding box of a set of monitors — what a span covers.
function boundsOf(rects) {
  if (!rects || rects.length === 0) return null;
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const r of rects) {
    x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y);
    x1 = Math.max(x1, r.x + r.w); y1 = Math.max(y1, r.y + r.h);
  }
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
}

// ── the slideshow ─────────────────────────────────────────────────────────
// The next picture after `current` in `pool` (an array of paths). Shuffle
// never hands back the one already up, unless it is the only one there is.
function nextSlide(pool, current, shuffle, rand) {
  if (!pool || pool.length === 0) return "";
  if (pool.length === 1) return pool[0];
  const i = pool.indexOf(current);
  if (shuffle) {
    const r = rand ? rand() : Math.random();
    let j = Math.floor(r * (pool.length - 1));
    if (i >= 0 && j >= i) j += 1;
    return pool[Math.min(j, pool.length - 1)];
  }
  return pool[(i + 1) % pool.length];
}

// ── the whole of picasso's state ──────────────────────────────────────────
// Two maps now, both keyed by monitor name: which image is on it, and how
// that image is fitted to it. Fit used to be one global setting, which is
// wrong the moment two monitors are different shapes — the exact case picasso
// already handled for the image itself.
//
// THE OLD FILE IS A BARE MAP of monitor to path, with no wrapper at all. It
// has to keep loading, and a version marker is the only honest way to tell
// the two apart: a monitor cannot be called "v", but it could in principle be
// called "assignment", and a format that guesses from a key name is a format
// that corrupts somebody's config the day they buy that monitor.
function isMap(v) { return !!v && typeof v === "object" && !Array.isArray(v); }

// Version 3 adds the looks, the span, the saved colours and the slideshow.
// Each is optional on the way in, so a v2 file loads with all of them empty.
function serializeState(st) {
  return JSON.stringify({
    v: 3,
    assignment: st.assignment || {},
    fits: st.fits || {},
    looks: st.looks || {},
    span: st.span || null,
    colors: st.colors || [],
    slideshow: st.slideshow || null
  });
}

function parseState(text) {
  const j = parse(text);
  const empty = { looks: {}, span: null, colors: [], slideshow: null };
  if (j.v === 2 || j.v === 3) {
    const span = isMap(j.span) && typeof j.span.path === "string"
      && Array.isArray(j.span.screens) ? j.span : null;
    const ss = isMap(j.slideshow) && j.slideshow.minutes > 0 ? j.slideshow : null;
    return {
      assignment: isMap(j.assignment) ? j.assignment : {},
      fits: isMap(j.fits) ? j.fits : {},
      looks: isMap(j.looks) ? j.looks : {},
      span: span,
      colors: Array.isArray(j.colors) ? j.colors.map(normHex).filter((c) => c !== "") : [],
      slideshow: ss
    };
  }
  // version 1: the object IS the assignment, and nothing had a fit of its own
  return Object.assign({ assignment: j, fits: {} }, empty);
}
