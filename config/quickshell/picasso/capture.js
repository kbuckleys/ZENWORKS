// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PICASSO'S CAPTURE HALF, the pure part — the screenshot's names and
// geometry, and the colour picker's arithmetic. Nothing here touches
// Quickshell or a process, which is what lets scripts/tests check it.

// ── the screenshot ────────────────────────────────────────────────────────

// "2026-09-26-134642" — the same stamp hyprshot.lua wrote, so the folder
// keeps sorting the way it always has.
function stamp(d) {
  const p = (n) => (n < 10 ? "0" : "") + n;
  return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate())
    + "-" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
}

// What a capture is called: the stamp, then what it was of — the monitor
// for a whole screen, "window" or "region" otherwise, exactly as before.
function fileName(d, mode, monitor) {
  const what = mode === "screen" ? String(monitor || "screen")
    : mode === "window" ? "window" : "region";
  return stamp(d) + (mode === "screen" ? "-" : "_") + what + ".png";
}

// The annotated copy's default name: the original's, marked.
function annotatedName(path) {
  const base = String(path || "").split("/").pop() || "picture.png";
  const dot = base.lastIndexOf(".");
  const stem = dot > 0 ? base.slice(0, dot) : base;
  return stem + "-annotated.png";
}

// A rectangle from two corners, in any order, clamped to the screen.
function rectOf(x1, y1, x2, y2, w, h) {
  const cx = (v, m) => Math.max(0, Math.min(m, v));
  const ax = cx(Math.min(x1, x2), w), bx = cx(Math.max(x1, x2), w);
  const ay = cx(Math.min(y1, y2), h), by = cx(Math.max(y1, y2), h);
  return { x: Math.round(ax), y: Math.round(ay),
           w: Math.round(bx - ax), h: Math.round(by - ay) };
}

// A rectangle moved by (dx, dy), kept whole and on screen.
function moveRect(r, dx, dy, w, h) {
  return { x: Math.round(Math.max(0, Math.min(w - r.w, r.x + dx))),
           y: Math.round(Math.max(0, Math.min(h - r.h, r.y + dy))),
           w: r.w, h: r.h };
}

// One edge or corner dragged. `edge` names what is held: any of "l", "r",
// "t", "b" together ("tl" is the top-left corner). The opposite edges stay
// where they are; dragging past one flips the rectangle rather than
// inverting it.
function resizeRect(r, edge, dx, dy, w, h) {
  let x1 = r.x, y1 = r.y, x2 = r.x + r.w, y2 = r.y + r.h;
  if (edge.indexOf("l") >= 0) x1 += dx;
  if (edge.indexOf("r") >= 0) x2 += dx;
  if (edge.indexOf("t") >= 0) y1 += dy;
  if (edge.indexOf("b") >= 0) y2 += dy;
  return rectOf(x1, y1, x2, y2, w, h);
}

// The window under a point, from `hyprctl clients -j` already narrowed to
// what is on this screen — the SMALLEST that contains it, so a floating
// window wins over the tiled one behind it. Rectangles in the screen's own
// coordinates.
function windowAt(wins, x, y) {
  let best = null;
  for (const w of wins || []) {
    if (x < w.x || y < w.y || x >= w.x + w.w || y >= w.y + w.h) continue;
    if (!best || w.w * w.h < best.w * best.h) best = w;
  }
  return best;
}

// `hyprctl clients -j`, reduced to the windows visible on one monitor, in
// that monitor's coordinates. `ws` is the ids of the workspaces shown on
// it (the active one, and a special one if open).
function windowsOn(clients, monitor, ws) {
  const out = [];
  for (const c of clients || []) {
    if (!c || !c.mapped || c.hidden) continue;
    if (!c.workspace || ws.indexOf(c.workspace.id) < 0) continue;
    out.push({ x: c.at[0] - monitor.x, y: c.at[1] - monitor.y,
               w: c.size[0], h: c.size[1], title: String(c.title || "") });
  }
  return out;
}

// ── the colour picker ─────────────────────────────────────────────────────
// The schemes it can speak, in the order the wheel walks them.
const SCHEMES = ["hex", "rgb", "hsl", "hsv", "oklch", "cmyk"];
const SCHEME_LABELS = { hex: "HEX", rgb: "RGB", hsl: "HSL", hsv: "HSV",
                        oklch: "OKLCH", cmyk: "CMYK" };

function stepScheme(s, dir) {
  const i = Math.max(0, SCHEMES.indexOf(s));
  return SCHEMES[(i + dir + SCHEMES.length) % SCHEMES.length];
}

function hex2(n) { return (n < 16 ? "0" : "") + n.toString(16); }

function round(v, places) {
  const f = Math.pow(10, places || 0);
  return Math.round(v * f) / f;
}

// r, g, b in 0..255 → h in degrees, s and l/v in 0..1.
function hslOf(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  const l = (max + min) / 2;
  let h = 0, s = 0;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    h = max === r ? (g - b) / d + (g < b ? 6 : 0)
      : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
    h *= 60;
  }
  return { h: h, s: s, l: l };
}

function hsvOf(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let h = 0;
  if (d !== 0)
    h = 60 * (max === r ? ((g - b) / d + (g < b ? 6 : 0))
      : max === g ? (b - r) / d + 2 : (r - g) / d + 4);
  return { h: h, s: max === 0 ? 0 : d / max, v: max };
}

// OKLCH, through linear sRGB and OKLab — Björn Ottosson's matrices.
function oklchOf(r, g, b) {
  const lin = (c) => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  const R = lin(r), G = lin(g), B = lin(b);
  const l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B);
  const m = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B);
  const s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B);
  const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  const A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  const Bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  const C = Math.sqrt(A * A + Bb * Bb);
  let H = Math.atan2(Bb, A) * 180 / Math.PI;
  if (H < 0) H += 360;
  return { l: L, c: C, h: C < 1e-4 ? 0 : H };
}

function cmykOf(r, g, b) {
  const k = 1 - Math.max(r, g, b) / 255;
  if (k >= 1) return { c: 0, m: 0, y: 0, k: 1 };
  return { c: (1 - r / 255 - k) / (1 - k), m: (1 - g / 255 - k) / (1 - k),
           y: (1 - b / 255 - k) / (1 - k), k: k };
}

// A colour written in one scheme, as it would be pasted into CSS or a
// config file.
function format(r, g, b, scheme) {
  r = Math.round(r); g = Math.round(g); b = Math.round(b);
  switch (scheme) {
  case "rgb": return "rgb(" + r + ", " + g + ", " + b + ")";
  case "hsl": {
    const c = hslOf(r, g, b);
    return "hsl(" + Math.round(c.h) + ", " + Math.round(c.s * 100) + "%, "
      + Math.round(c.l * 100) + "%)";
  }
  case "hsv": {
    const c = hsvOf(r, g, b);
    return "hsv(" + Math.round(c.h) + ", " + Math.round(c.s * 100) + "%, "
      + Math.round(c.v * 100) + "%)";
  }
  case "oklch": {
    const c = oklchOf(r, g, b);
    return "oklch(" + round(c.l * 100, 1) + "% " + round(c.c, 3) + " " + round(c.h, 1) + ")";
  }
  case "cmyk": {
    const c = cmykOf(r, g, b);
    return "cmyk(" + Math.round(c.c * 100) + "%, " + Math.round(c.m * 100) + "%, "
      + Math.round(c.y * 100) + "%, " + Math.round(c.k * 100) + "%)";
  }
  default: return "#" + hex2(r) + hex2(g) + hex2(b);
  }
}

// Black or white, whichever reads on this colour — for the loupe's
// crosshair and the swatch's label.
function inkOn(r, g, b) {
  const lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  return lum > 0.55 ? "#000000" : "#ffffff";
}
