// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PICASSO'S CAPTURE HALF, the pure part — the screenshot's names and
// geometry, and the color picker's arithmetic. Nothing here touches
// Quickshell or a process, which is what lets oracle/tests check it.

// ── the screenshot ────────────────────────────────────────────────────────

// "2026-09-26-134642" — the same stamp hyprshot.lua wrote, so the directory
// keeps sorting the way it always has.
.pragma library
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file — every row, tile, card and sheet — evaluated all of
// it again; a profile caught terminus.js and icons.js costing hundreds of ms
// that way (qmlprofiler, 2026-10-09).

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

// ── the region's quick presets ───────────────────────────────────────────
// A shape (r, width over height) or an exact size in real pixels (pw × ph,
// divided by the output's scale here), or the whole screen. `key` is the
// number that picks it on the overlay.
const PRESETS = [
  { key: "1", label: "1:1", r: 1 },
  { key: "2", label: "4:3", r: 4 / 3 },
  { key: "3", label: "16:9", r: 16 / 9 },
  { key: "4", label: "9:16", r: 9 / 16 },
  { key: "5", label: "1920×1080", pw: 1920, ph: 1080 },
  { key: "6", label: "1280×720", pw: 1280, ph: 720 },
  { key: "7", label: "Screen", full: true }
];

// The selection reshaped to a preset, about its own center — or, with none
// drawn yet (w ≤ 2), about the screen's, at 60% of it. A shape keeps the
// selection's width unless the height would not fit; a size too big for the
// screen is scaled down at its own shape. Always whole and on screen.
function presetRect(sel, p, w, h, dpr) {
  if (!p || !(w > 0) || !(h > 0)) return sel;
  if (p.full) return { x: 0, y: 0, w: Math.round(w), h: Math.round(h) };
  const has = sel && sel.w > 2 && sel.h > 2;
  const cx = has ? sel.x + sel.w / 2 : w / 2, cy = has ? sel.y + sel.h / 2 : h / 2;
  let rw, rh;
  if (p.pw > 0 && p.ph > 0) {
    const s = dpr > 0 ? dpr : 1;
    rw = p.pw / s; rh = p.ph / s;
  } else {
    const r = p.r > 0 ? p.r : 1;
    rw = has ? sel.w : Math.min(w, h * r) * 0.6;
    rh = rw / r;
  }
  const k = Math.min(1, w / rw, h / rh);
  rw *= k; rh *= k;
  const x = Math.max(0, Math.min(w - rw, cx - rw / 2));
  const y = Math.max(0, Math.min(h - rh, cy - rh / 2));
  return { x: Math.round(x), y: Math.round(y), w: Math.round(rw), h: Math.round(rh) };
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
               w: c.size[0], h: c.size[1], title: String(c.title || ""),
               address: String(c.address || "") });
  }
  return out;
}

// ── the window's shadow ──────────────────────────────────────────────────
// A window shot the way macOS takes one: the window alone (grim -T, its own
// buffer), its corners rounded off, over a transparent canvas with its drop
// shadow. Hyprland draws that shadow in the compositor, so no capture has
// it — it is drawn again here, from hyprland's own settings and with its
// own shader's arithmetic (render/shaders/glsl/shadow.glsl), so the shot
// looks the way the window did on screen.

// `hyprctl -j getoption` answers with the value under its type's name.
function optionValue(o) {
  if (!o) return undefined;
  for (const k of ["int", "float", "vec2", "gradient", "str", "custom"])
    if (o[k] !== undefined) return o[k];
  return undefined;
}

// "7a000000 0deg" — a gradient's first stop, AARRGGBB — as 0..1 parts.
function argbOf(text) {
  const m = /^(?:0x)?([0-9a-f]{8})\b/i.exec(String(text || "").trim());
  if (!m) return { r: 0, g: 0, b: 0, a: 0x7a / 255 };
  const n = parseInt(m[1], 16);
  return { a: ((n >>> 24) & 255) / 255, r: ((n >>> 16) & 255) / 255,
           g: ((n >>> 8) & 255) / 255, b: (n & 255) / 255 };
}

// The shadow as hyprland would draw it, in the capture's pixels. `opts` is
// the getoption answers, `scale` the monitor's. `plain` (or shadows off in
// hyprland, or a fullscreen window) keeps the rounding and drops the shadow.
const SHADOW_OPTIONS = ["decoration:rounding", "decoration:shadow:enabled",
  "decoration:shadow:range", "decoration:shadow:render_power",
  "decoration:shadow:offset", "decoration:shadow:color", "decoration:shadow:scale"];
function shadowSpec(opts, scale, plain, fullscreen) {
  const v = {};
  for (const o of opts || []) if (o && o.option) v[o.option] = optionValue(o);
  const s = scale > 0 ? scale : 1;
  const num = (k, d) => (typeof v[k] === "number" ? v[k] : d);
  const off = Array.isArray(v["decoration:shadow:offset"]) ? v["decoration:shadow:offset"] : [0, 0];
  const on = !plain && !fullscreen && num("decoration:shadow:enabled", 1) !== 0;
  return {
    rounding: fullscreen ? 0 : Math.round(num("decoration:rounding", 0) * s),
    range: on ? Math.round(num("decoration:shadow:range", 0) * s) : 0,
    power: Math.max(1, Math.min(4, num("decoration:shadow:render_power", 3))),
    ox: on ? Math.round(off[0] * s) : 0,
    oy: on ? Math.round(off[1] * s) : 0,
    color: argbOf(v["decoration:shadow:color"])
  };
}

// Where things go on the canvas: the window, and the shadow — the window's
// box grown by `range` on every side, then moved by the offset — with the
// canvas just big enough for both.
function shadowLayout(spec, w, h) {
  const R = spec.range;
  const wx = Math.max(0, R - spec.ox), wy = Math.max(0, R - spec.oy);
  const sx = wx - R + spec.ox, sy = wy - R + spec.oy;
  return { wx: wx, wy: wy, sx: sx, sy: sy,
           cw: Math.max(wx + w, sx + w + 2 * R), ch: Math.max(wy + h, sy + h + 2 * R) };
}

// The shell that does it, with ImageMagick: "$1" the raw capture, "$2" the
// shot. The shader's falloff — ((range − d) / range)^power, d how far past
// the window's rounded edge — is worked out by -fx on one small tile only (a
// window just big enough for its rounded corners, with its shadow round
// it), and the tile is then cut nine ways and stretched: along an edge the
// shadow does not change, so stretching it is exact. The whole canvas
// through -fx took over a second for a large window.
//
// The corners are an honest rounded rectangle's. The shader measures them
// from the window's square corner less the rounding, which leaves a faint
// step where corner meets edge — invisible on a background, plain on the
// flat transparency of a shot.
function shadowCommand(spec, w, h) {
  w = Math.max(1, Math.round(w)); h = Math.max(1, Math.round(h));
  const R = spec.range;
  const r = Math.max(0, Math.min(spec.rounding, Math.floor((Math.min(w, h) - 1) / 2)));
  const L = shadowLayout(spec, w, h);
  const at = (x, y) => (x < 0 ? "" : "+") + x + (y < 0 ? "" : "+") + y;
  const mask = "\\( -size " + w + "x" + h + " xc:none -fill white -draw "
    + "'roundrectangle 0,0 " + (w - 1) + "," + (h - 1) + " " + r + "," + r + "' \\)";
  // the window, its corners rounded off
  let cmd = "magick \"$1\" -alpha set -resize " + w + "x" + h + "! " + mask
    + " -compose DstIn -composite -compose Over -write mpr:win +delete ";
  if (R <= 0)
    return cmd + "mpr:win \"$2\"";
  const c = spec.color, k = (n) => +n.toFixed(4);
  // The tile's window runs from K - r to E + r: its corners' centers at K
  // and E, two pixels of straight edge between them — the strip that is
  // stretched.
  const K = R + r, E = K + 2;
  const fx = "qx=max(0,max(" + K + "-i-0.5,i+0.5-" + E + "));"
    + "qy=max(0,max(" + K + "-j-0.5,j+0.5-" + E + "));"
    + "qd=max(0,hypot(qx,qy)-" + r + ");"
    + "qd>=" + R + "?0:" + k(c.a) + "*pow((" + R + "-qd)/" + R + "," + spec.power + ")";
  const rgb = "rgb(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ")";
  cmd += "-size " + (2 * K + 2) + "x" + (2 * K + 2) + " 'xc:" + rgb + "' -alpha set -channel A -fx '"
    + fx + "' +channel -write mpr:tile +delete ";
  // the nine pieces: crop from the tile, stretch the middles
  const mw = w - 2 * r, mh = h - 2 * r;
  const piece = (cw, ch, x, y, tw, th) => "\\( mpr:tile -crop " + cw + "x" + ch + at(x, y)
    + " +repage" + (tw ? " -scale " + tw + "x" + th + "!" : "") + " \\)";
  const row = (y, ch, th) => "\\( " + piece(K, ch, 0, y, th ? K : 0, th) + " "
    + piece(2, ch, K, y, mw, th || K) + " " + piece(K, ch, E, y, th ? K : 0, th) + " +append \\)";
  cmd += "\\( " + row(0, K, 0) + " " + row(K, 2, mh) + " " + row(E, K, 0) + " -append \\) "
    + "-write mpr:shadow +delete ";
  // the canvas: the shadow, none of it under the window (the shader leaves
  // the window's own box clear — it shows through a translucent one
  // otherwise), then the window
  return cmd + "-size " + L.cw + "x" + L.ch + " xc:none "
    + "mpr:shadow -geometry " + at(L.sx, L.sy) + " -composite "
    + mask + " -geometry " + at(L.wx, L.wy) + " -compose DstOut -composite "
    + "mpr:win -geometry " + at(L.wx, L.wy) + " -compose Over -composite \"$2\"";
}

// morpheus Strings.shellQuote's body — this file cannot reach the singleton
function quote(s) { return "'" + String(s == null ? "" : s).replace(/'/g, "'\\''") + "'"; }

// The whole window shot as one shell line. The window's own buffer through
// grim -T, its identifier found by `helper` (bin/toplevel.py) from hyprctl's
// address; if that fails, the screen's rectangle as before (`geo`), which
// has whatever is behind and over the window in it but is still a shot.
// Then the rounding and the shadow, into `file`, and the raw capture gone.
function windowShotCommand(o) {
  return "mkdir -p " + quote(o.dir) + " && { id=$(python3 -I " + quote(o.helper) + " " + quote(o.address)
    + ") && grim -T \"$id\" " + quote(o.raw) + " || grim -g " + quote(o.geo) + " " + quote(o.raw) + "; } && "
    + "sh -c " + quote(shadowCommand(o.spec, o.w, o.h)) + " sh " + quote(o.raw) + " " + quote(o.file)
    + "; s=$?; rm -f " + quote(o.raw) + "; exit $s";
}

// ── the color picker ─────────────────────────────────────────────────────
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

// A color written in one scheme, as it would be pasted into CSS or a
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

// Black or white, whichever reads on this color — for the loupe's
// crosshair and the swatch's label.
function inkOn(r, g, b) {
  const lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  return lum > 0.55 ? "#000000" : "#ffffff";
}
