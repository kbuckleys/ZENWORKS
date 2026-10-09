// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// FOLLOW BACKGROUND: a theme made from a background. picasso/FollowBackground
// asks ImageMagick for the picture's dominant colours (parseHistogram) and
// this turns them into a theme in the shape themes/*.json have, so Zenon,
// ThemeSync, plato and every preview take it like any other.
//
// IN OKLCH. Lightness there is lightness as the eye has it, so "a ground at
// 0.17" is equally dark whatever the hue — in RGB or HSL a blue and a yellow
// at one number are nowhere near one brightness.
//
// THE BACKGROUND LENDS A HUE, NOT A LOOK:
//   - the seed is its most colourful colour that is also really there;
//   - grounds and text take the seed's hue at low chroma — tinted, not
//     coloured; a grey picture gives an all but neutral theme;
//   - cyan, the shell's own accent (selection, focus, the clock), BECOMES
//     the seed, so the highlight is the background's colour;
//   - every other accent keeps its meaning (red is still the error) and is
//     only turned up to 15 degrees towards the seed — harmonised.
// Then every slot is pushed lighter (dark) or darker (light) until it reads
// on the ground: ink 7:1, keyInk 4.5, soft 3.5, muted 2.6, accents 3.

// ── colour space ─────────────────────────────────────────────────────────
function hexToRgb(h) {
  const s = String(h).replace(/^#/, "").slice(-6);
  return [0, 2, 4].map((i) => parseInt(s.slice(i, i + 2), 16) / 255);
}
function rgbToHex(c) {
  return "#" + c.map((v) => Math.round(Math.max(0, Math.min(1, v)) * 255)
    .toString(16).padStart(2, "0")).join("");
}
function lin(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
function gam(c) { return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055; }

function rgbToOklch(rgb) {
  const [r, g, b] = rgb.map(lin);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  const A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  let h = Math.atan2(B, A) * 180 / Math.PI;
  if (h < 0) h += 360;
  return { L: L, C: Math.sqrt(A * A + B * B), h: h };
}

function oklchToRgbRaw(L, C, h) {
  const A = C * Math.cos(h * Math.PI / 180), B = C * Math.sin(h * Math.PI / 180);
  const l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3);
  const m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3);
  const s = Math.pow(L - 0.0894841775 * A - 1.2914855480 * B, 3);
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  ].map(gam);
}

// a colour the screen can show: chroma given up, hue and lightness kept
function oklch(L, C, h) {
  L = Math.max(0, Math.min(1, L));
  const fits = (c) => oklchToRgbRaw(L, c, h).every((v) => v >= -0.0005 && v <= 1.0005);
  if (fits(C)) return rgbToHex(oklchToRgbRaw(L, C, h));
  let lo = 0, hi = C;
  for (let i = 0; i < 18; ++i) { const mid = (lo + hi) / 2; if (fits(mid)) lo = mid; else hi = mid; }
  return rgbToHex(oklchToRgbRaw(L, lo, h));
}

function luminance(hex) {
  const [r, g, b] = hexToRgb(hex).map(lin);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contrast(a, b) {
  const x = luminance(a), y = luminance(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}

// ── ImageMagick's answer ─────────────────────────────────────────────────
// `magick … -colors 12 -format %c histogram:info:-` prints a line per colour:
//   "      4210: (23,41,60) #17293C srgb(23,41,60)"
function parseHistogram(text) {
  const out = [];
  for (const line of String(text || "").split("\n")) {
    const m = /^\s*(\d+):.*?#([0-9A-Fa-f]{6})/.exec(line);
    if (m) out.push({ hex: "#" + m[2].toLowerCase(), n: parseInt(m[1], 10) });
  }
  return out;
}

// ── the theme ────────────────────────────────────────────────────────────
function hueToward(h, seed, neutral) {
  if (neutral) return h;
  let d = ((seed - h + 540) % 360) - 180;
  return (h + Math.sign(d) * Math.min(Math.abs(d) * 0.25, 15) + 360) % 360;
}

// RED KEEPS ITS DISTANCE. It is the error, and the accent is the
// background's colour: a rose background made both the same pink, and a
// failure read as a selection. Within 45 degrees of the seed, red steps
// away from it instead of towards it, to at least 40 degrees apart.
function redFrom(seed, neutral) {
  const h = 25;
  if (neutral) return h;
  const d = ((seed - h + 540) % 360) - 180;
  if (Math.abs(d) >= 45) return hueToward(h, seed, false);
  return (seed - Math.sign(d || 1) * 40 + 360) % 360;
}

// lightness walked away from the ground until the colour reads on it
function legible(L, C, h, ground, need, light) {
  let hex = oklch(L, C, h);
  for (let i = 0; i < 100 && contrast(hex, ground) < need; ++i) {
    L += light ? -0.01 : 0.01;
    if (L <= 0 || L >= 1) break;
    hex = oklch(L, C, h);
  }
  return hex;
}

// `colors`: parseHistogram's list. `opts`: { mode: "auto"|"dark"|"light",
// vivid: 0..1, name }. Returns { name, mode, colors } or null for nothing
// to go on.
function palette(colors, opts) {
  const o = opts || {};
  const list = (colors || []).filter((c) => c && c.n > 0 && /^#[0-9a-f]{6}$/i.test(c.hex));
  if (!list.length) return null;
  const total = list.reduce((s, c) => s + c.n, 0);
  const lch = list.map((c) => Object.assign({ n: c.n / total }, rgbToOklch(hexToRgb(c.hex))));
  const avgL = lch.reduce((s, c) => s + c.L * c.n, 0);
  const light = o.mode === "light" || (o.mode !== "dark" && avgL > 0.62);
  const v = Math.max(0, Math.min(1, o.vivid === undefined ? 0.5 : Number(o.vivid)));

  // the seed: colourful AND present, never a speck of near-black or white
  let seed = null, best = -1;
  for (const c of lch) {
    if (c.L < 0.2 || c.L > 0.94) continue;
    const score = Math.sqrt(c.n) * c.C;
    if (score > best) { best = score; seed = c; }
  }
  const neutral = !seed || seed.C < 0.035;
  const most = lch.slice().sort((a, b) => b.n - a.n)[0];
  const seedH = seed && !neutral ? seed.h : (most.C > 0.01 ? most.h : 250);
  const seedC = neutral ? 0 : seed.C;

  const bgC = neutral ? 0.006 : Math.min(seedC, 0.012 + 0.05 * v);
  const txC = neutral ? 0.004 : Math.min(seedC, 0.008 + 0.02 * v);
  const lv = light
    ? { ground: 0.975, card: 0.95, surface: 0.9, dim: 0.82, border: 0.74,
        ink: 0.32, keyInk: 0.42, soft: 0.48, muted: 0.6, acc: 0.56, pink: 0.62 }
    : { ground: 0.17, card: 0.2, surface: 0.27, dim: 0.37, border: 0.44,
        ink: 0.93, keyInk: 0.84, soft: 0.78, muted: 0.64, acc: 0.8, pink: 0.86 };
  const accC = light ? 0.11 + 0.07 * v : 0.09 + 0.06 * v;

  const ground = oklch(lv.ground, bgC, seedH);
  const text = (L, need) => legible(L, txC, seedH, ground, need, light);
  const accent = (h, need, L, C) => legible(L === undefined ? lv.acc : L,
    C === undefined ? accC : C, h, ground, need, light);
  const hues = { yellow: 60, sand: 95, green: 145, blue: 255, magenta: 320 };
  const c = {
    ground: ground,
    card: oklch(lv.card, bgC, seedH),
    surface: oklch(lv.surface, bgC, seedH),
    dim: oklch(lv.dim, bgC, seedH),
    ink: text(lv.ink, 7),
    keyInk: text(lv.keyInk, 4.5),
    soft: text(lv.soft, 3.5),
    muted: text(lv.muted, 2.6),
    cyan: accent(neutral ? 210 : seedH, 3, lv.acc, neutral ? accC * 0.7 : Math.max(accC, Math.min(seedC, 0.2))),
    pink: accent(hueToward(10, seedH, neutral), 3, lv.pink, accC * 0.55),
  };
  for (const k in hues) c[k] = accent(hueToward(hues[k], seedH, neutral), 3);
  c.red = accent(redFrom(seedH, neutral), 3, lv.acc, accC * 1.15);
  const border = oklch(lv.border, bgC, seedH);
  const a = (alpha, hex) => "#" + Math.round(alpha * 255).toString(16).padStart(2, "0") + hex.slice(1);
  c.sparkFill = a(0.2, c.cyan);
  c.border = a(light ? 0.4 : 0.3, border);
  c.headBg = a(0.4, c.surface);
  c.selBg = a(0.3, c.dim);
  c.onAccent = ground;
  if (light) { c.wash = "#000000"; c.shadow = "#000000"; }
  return { name: o.name || "Follow Background", mode: light ? "light" : "dark", colors: c };
}
