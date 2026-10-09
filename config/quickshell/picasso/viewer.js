// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE VIEWER'S PURE HALF — zoom and pan, the crop's geometry, and what the
// launcher hands over. Nothing here touches Quickshell or a process, which
// is what lets oracle/tests check it. The directory listing, the image test and
// the sort are terminus.js'; the look is picasso.js'.

// ── what was asked for ────────────────────────────────────────────────────
// One path, or several separated by newlines (the launcher's %F). Blank lines
// dropped, the same file named twice kept once, the order kept.
.pragma library
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file evaluated all of it again (qmlprofiler, 2026-10-09;
// see morpheus/icons.js and terminus/terminus.js for what that cost).

function parsePaths(text) {
  const out = [];
  for (const raw of String(text || "").split("\n")) {
    const p = raw.trim().replace(/\/+$/, "");
    if (p !== "" && out.indexOf(p) < 0) out.push(p);
  }
  return out;
}

function indexOfPath(rows, path) {
  for (let i = 0; i < (rows || []).length; ++i) if (rows[i].path === path) return i;
  return -1;
}

// ── zoom ──────────────────────────────────────────────────────────────────
// A view is { z, x, y }: the scale, and where the picture's top-left corner
// sits in the stage. Everything below returns a new one.

const ZOOM_MIN = 0.02;
const ZOOM_MAX = 32;

// The stops + and - walk. 1 is on it, so stepping always passes through
// actual size rather than hopping over it.
const ZOOM_STOPS = [0.05, 0.1, 0.15, 0.25, 0.33, 0.5, 0.67, 0.8, 1, 1.25, 1.5,
                    2, 3, 4, 6, 8, 12, 16, 24, 32];

function clampZoom(z) { return Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, z)); }

// The scale that fits the picture in the box. Never past `max`: a small
// picture blown up to fill a window is only blur — 1 by default, which is
// what a viewer should do with an icon.
function fitScale(iw, ih, bw, bh, max) {
  if (!(iw > 0) || !(ih > 0) || !(bw > 0) || !(bh > 0)) return 1;
  return Math.min(max === undefined ? 1 : max, bw / iw, bh / ih);
}

// The next stop past `z` in direction `dir`. From the fit, which is rarely a
// stop, it goes to the nearest stop that way.
function stepZoom(z, dir) {
  if (dir > 0) {
    for (const s of ZOOM_STOPS) if (s > z * 1.001) return s;
    return ZOOM_MAX;
  }
  for (let i = ZOOM_STOPS.length - 1; i >= 0; --i)
    if (ZOOM_STOPS[i] < z * 0.999) return ZOOM_STOPS[i];
  return ZOOM_MIN;
}

// Where the picture sits once it can move no further: centred on an axis it
// does not fill, and on one it overflows, no edge pulled in past the stage's.
function clampView(v, iw, ih, sw, sh) {
  const dw = iw * v.z, dh = ih * v.z;
  const x = dw <= sw ? (sw - dw) / 2 : Math.max(sw - dw, Math.min(0, v.x));
  const y = dh <= sh ? (sh - dh) / 2 : Math.max(sh - dh, Math.min(0, v.y));
  return { z: v.z, x: x, y: y };
}

// Zoomed to `z`, keeping the picture's point under (px, py) where it is — the
// wheel's zoom, which is towards the pointer rather than the middle.
function zoomAbout(v, z, px, py, iw, ih, sw, sh) {
  const nz = clampZoom(z);
  const k = nz / v.z;
  return clampView({ z: nz, x: px - (px - v.x) * k, y: py - (py - v.y) * k }, iw, ih, sw, sh);
}

// The fitted view: the picture whole and centred.
function fitView(iw, ih, sw, sh, max) {
  return clampView({ z: fitScale(iw, ih, sw, sh, max), x: 0, y: 0 }, iw, ih, sw, sh);
}

// ── the edited picture ────────────────────────────────────────────────────
// A quarter turn swaps the sides of what is saved.
function turnedSize(w, h, rotate) {
  return (rotate === 90 || rotate === 270) ? { w: h, h: w } : { w: w, h: h };
}

// Scene's `unit`, for a picture rather than a monitor: the blur a background
// gets on a 2560-wide screen is the blur a photo gets across its own width,
// so "blur 40%" softens a phone photo and a thumbnail of it alike — and the
// preview, drawn smaller, agrees with the saved file drawn at full size.
function unitFor(w, h) {
  return Math.max(w, h) / 2560;
}

// "shot.png" -> "shot-edited.png", beside it. The extension is kept: saving
// an edited jpeg as a jpeg is what somebody who clicked "save new" expects.
function editedName(path, tag) {
  const base = String(path || "").split("/").pop() || "picture.png";
  const dot = base.lastIndexOf(".");
  const stem = dot > 0 ? base.slice(0, dot) : base;
  const ext = dot > 0 ? base.slice(dot) : ".png";
  return stem + "-" + (tag || "edited") + ext;
}

// Formats a picture can be written back to. Anything else — a raw, a psd, a
// heic — is saved beside itself as a png instead of being overwritten in a
// format the writer would have to guess at.
const WRITABLE = { png: 1, jpg: 1, jpeg: 1, webp: 1, bmp: 1, tif: 1, tiff: 1 };
function writable(path) {
  const m = /\.([^./]+)$/.exec(String(path || ""));
  return !!m && WRITABLE[m[1].toLowerCase()] === 1;
}

// ── the crop ──────────────────────────────────────────────────────────────
// A crop is a rectangle in the SAVED picture's pixels — after the turn — so
// it is the same box whatever the zoom. Its sides are moved with capture.js'
// resizeRect; this is what keeps them to a ratio while they move.

// The biggest box of `ratio` (width / height) that fits, centred.
function centredCrop(w, h, ratio) {
  if (!(ratio > 0)) return { x: 0, y: 0, w: w, h: h };
  let cw = w, ch = w / ratio;
  if (ch > h) { ch = h; cw = h * ratio; }
  return { x: Math.round((w - cw) / 2), y: Math.round((h - ch) / 2),
           w: Math.round(cw), h: Math.round(ch) };
}

// `r` after a drag of `edge` (any of l r t b, as capture.js names them),
// bent back to `ratio`. The side held still stays still; a side dragged
// alone drags the other axis along with it, from the middle. Shrunk rather
// than pushed when the ratio would run it off the picture.
function fitAspect(r, edge, ratio, w, h) {
  if (!(ratio > 0)) return r;
  const hz = /[lr]/.test(edge), vt = /[tb]/.test(edge);
  let nw = r.w, nh = r.h;
  if (hz && !vt) nh = nw / ratio;
  else if (vt && !hz) nw = nh * ratio;
  else if (nw / Math.max(1, nh) > ratio) nh = nw / ratio;
  else nw = nh * ratio;

  const cx = r.x + r.w / 2, cy = r.y + r.h / 2;
  const maxW = edge.indexOf("l") >= 0 ? r.x + r.w
    : edge.indexOf("r") >= 0 ? w - r.x : 2 * Math.min(cx, w - cx);
  const maxH = edge.indexOf("t") >= 0 ? r.y + r.h
    : edge.indexOf("b") >= 0 ? h - r.y : 2 * Math.min(cy, h - cy);
  const s = Math.min(1, maxW / Math.max(1, nw), maxH / Math.max(1, nh));
  nw *= s; nh *= s;

  const x = edge.indexOf("l") >= 0 ? r.x + r.w - nw
    : edge.indexOf("r") >= 0 ? r.x : cx - nw / 2;
  const y = edge.indexOf("t") >= 0 ? r.y + r.h - nh
    : edge.indexOf("b") >= 0 ? r.y : cy - nh / 2;
  return { x: Math.round(x), y: Math.round(y), w: Math.round(nw), h: Math.round(nh) };
}

// The ratios the crop offers. "screen" is filled in by the caller with the
// monitor the window is on — the one to reach for when a crop is going to
// become a background.
var CROP_RATIOS = [
  { k: "free", t: "Free", r: 0 },
  { k: "orig", t: "Original", r: -1 },
  { k: "screen", t: "Screen", r: -2 },
  { k: "1:1", t: "1:1", r: 1 },
  { k: "4:3", t: "4:3", r: 4 / 3 },
  { k: "3:2", t: "3:2", r: 3 / 2 },
  { k: "16:9", t: "16:9", r: 16 / 9 },
  { k: "4:5", t: "4:5", r: 4 / 5 },
  { k: "9:16", t: "9:16", r: 9 / 16 }
];

// One more ratio per monitor, when there is more than one and they differ
// from each other — "DP-1 21:9" beside "Screen", for the background that is
// going on the other one. `screens` is [{ name, width, height }].
function screenRatios(screens) {
  const out = [], seen = {};
  for (const s of screens || []) {
    if (!(s.width > 0) || !(s.height > 0)) continue;
    const r = s.width / s.height, key = r.toFixed(3);
    if (seen[key]) continue;
    seen[key] = true;
    out.push({ k: "mon:" + s.name, t: s.name + "  " + ratioName(s.width, s.height), r: r });
  }
  return out.length > 1 ? out : [];
}

// 2560×1080 -> "21:9", 1920×1200 -> "16:10": the reduced ratio, or the
// common name a near miss is sold as.
function ratioName(w, h) {
  const r = w / h;
  const known = [[21, 9, 64 / 27], [16, 9], [16, 10], [4, 3], [5, 4], [3, 2], [32, 9], [1, 1]];
  for (const k of known) if (Math.abs(r - (k[2] || k[0] / k[1])) < 0.02) return k[0] + ":" + k[1];
  const gcd = (a, b) => b === 0 ? a : gcd(b, a % b);
  const g = gcd(Math.round(w), Math.round(h)) || 1;
  return Math.round(w) / g + ":" + Math.round(h) / g;
}

// ── black borders ─────────────────────────────────────────────────────────
// The strips a film frame, a screenshot of a video or a scan carries round
// the picture. ImageMagick's trim keys on the corner colour, so the picture
// is first given a one-pixel black border of its own: then only black (to
// within `fuzz`) is trimmed, never a white sky. It is turned and mirrored
// the way the stage is — mirror first, then turn, as Scene does — so the
// box comes back in the SAVED picture's pixels, where the crop lives.
// Prints "W H WxH+X+Y" of the bordered picture; see parseTrim.
function trimCommand(rotate, mirror, fuzz) {
  return 'magick -- "$1[0]" -auto-orient' + (mirror ? " -flop" : "")
    + (rotate ? " -rotate " + rotate : "")
    + " -bordercolor black -border 1 -fuzz " + (fuzz || 8) + '% -format "%w %h %@" info:';
}

// trimCommand's line -> the crop { x, y, w, h } in a `w`×`h` picture (what
// the stage shows, which can be a smaller stand-in than the file), or
// { none: true } when there is nothing to trim, or null when it is all black
// or could not be read.
function parseTrim(text, w, h) {
  const m = /^(\d+) (\d+) (\d+)x(\d+)\+(-?\d+)\+(-?\d+)/.exec(String(text || "").trim());
  if (!m || !(w > 0) || !(h > 0)) return null;
  const bw = +m[1] - 2, bh = +m[2] - 2;
  if (!(bw > 0) || !(bh > 0) || +m[3] === 0 || +m[4] === 0) return null;
  const kx = w / bw, ky = h / bh;
  const x0 = Math.max(0, +m[5] - 1), y0 = Math.max(0, +m[6] - 1);
  const x1 = Math.min(bw, +m[5] - 1 + +m[3]), y1 = Math.min(bh, +m[6] - 1 + +m[4]);
  if (x1 - x0 < 4 || y1 - y0 < 4) return null;
  const r = { x: Math.round(x0 * kx), y: Math.round(y0 * ky),
              w: Math.round((x1 - x0) * kx), h: Math.round((y1 - y0) * ky) };
  // a pixel or two is JPEG fringe, not a border
  if (r.x <= 1 && r.y <= 1 && r.w >= w - 2 && r.h >= h - 2) return { none: true };
  return r;
}

// ── straightening ─────────────────────────────────────────────────────────
// A fine turn of a few degrees, which a horizon wants and a quarter turn
// cannot give. The picture is turned about its middle and grown just enough
// that no corner of the frame falls outside it — so what is saved is the
// same size, cropped inward, never with a wedge of nothing in a corner.
function straightenScale(w, h, deg) {
  if (!(w > 0) || !(h > 0) || !deg) return 1;
  const a = Math.abs(deg) * Math.PI / 180, c = Math.cos(a), s = Math.sin(a);
  return Math.max((w * c + h * s) / w, (w * s + h * c) / h);
}

// ── what the camera said ──────────────────────────────────────────────────
// `magick identify -format` lines of "Key=value", the empty ones dropped
// and exposure written the way a photographer reads it.
function parseExif(text) {
  const out = [];
  const names = { Model: "Camera", LensModel: "Lens", DateTimeOriginal: "Taken",
                  ExposureTime: "Exposure", FNumber: "Aperture",
                  PhotographicSensitivity: "ISO", FocalLength: "Focal length" };
  for (const line of String(text || "").split("\n")) {
    const cut = line.indexOf("=");
    if (cut <= 0) continue;
    const k = line.slice(0, cut).trim(), raw = line.slice(cut + 1).trim();
    if (raw === "" || !names[k]) continue;
    out.push({ k: names[k], v: exifValue(k, raw) });
  }
  return out;
}

function ratio_(s) {
  const m = /^(\d+)\/(\d+)$/.exec(s);
  if (!m) return parseFloat(s);
  return Number(m[2]) === 0 ? NaN : Number(m[1]) / Number(m[2]);
}

function exifValue(k, raw) {
  if (k === "ExposureTime") {
    const v = ratio_(raw);
    if (!(v > 0)) return raw;
    return v >= 1 ? (Math.round(v * 10) / 10) + " s" : "1/" + Math.round(1 / v) + " s";
  }
  if (k === "FNumber") {
    const v = ratio_(raw);
    return v > 0 ? "f/" + (Math.round(v * 10) / 10) : raw;
  }
  if (k === "FocalLength") {
    const v = ratio_(raw);
    return v > 0 ? Math.round(v) + " mm" : raw;
  }
  if (k === "DateTimeOriginal") {
    const m = /^(\d{4}):(\d{2}):(\d{2}) (\d{2}:\d{2})/.exec(raw);
    return m ? m[1] + "-" + m[2] + "-" + m[3] + " " + m[4] : raw;
  }
  return raw;
}

// Where the camera was, from the four GPS tags as `magick identify` prints
// them — degrees, minutes, seconds as rationals ("52/1, 31/1, 1234/100") and
// a hemisphere letter. null when any of it is missing: a half location is
// no location.
function parseGps(text) {
  const tag = {};
  for (const line of String(text || "").split("\n")) {
    const cut = line.indexOf("=");
    if (cut > 0) tag[line.slice(0, cut).trim()] = line.slice(cut + 1).trim();
  }
  const deg = (raw, ref, neg) => {
    const parts = String(raw || "").split(",").map((s) => ratio_(s.trim()));
    if (parts.length === 0 || !(parts[0] >= 0)) return NaN;
    const v = parts[0] + (parts[1] > 0 ? parts[1] / 60 : 0) + (parts[2] > 0 ? parts[2] / 3600 : 0);
    return String(ref || "").toUpperCase() === neg ? -v : v;
  };
  const lat = deg(tag.GPSLatitude, tag.GPSLatitudeRef, "S");
  const lon = deg(tag.GPSLongitude, tag.GPSLongitudeRef, "W");
  if (!isFinite(lat) || !isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
  return { lat: Math.round(lat * 1e5) / 1e5, lon: Math.round(lon * 1e5) / 1e5 };
}

function mapUrl(g) {
  return "https://www.openstreetmap.org/?mlat=" + g.lat + "&mlon=" + g.lon
    + "#map=15/" + g.lat + "/" + g.lon;
}

// ── the histogram ─────────────────────────────────────────────────────────
// Read from a plain (P3) ppm of a small copy — `magick … -compress none
// ppm:-` — so it is text all the way and needs no binary pipe. `bins` per
// channel, and the luminance (Rec. 709) beside red, green and blue; `max` is
// the tallest bin of any, for scaling the drawing.
function histogram(ppm, bins) {
  const n = bins || 64;
  const zero = () => { const a = []; for (let i = 0; i < n; ++i) a.push(0); return a; };
  const out = { r: zero(), g: zero(), b: zero(), l: zero(), max: 0, pixels: 0 };
  const tok = String(ppm || "").replace(/#[^\n]*/g, " ").split(/\s+/).filter((s) => s !== "");
  if (tok[0] !== "P3" || tok.length < 4) return out;
  const top = Number(tok[3]) || 255;
  const bin = (v) => Math.min(n - 1, Math.floor(v / (top + 1) * n));
  for (let i = 4; i + 2 < tok.length; i += 3) {
    const r = Number(tok[i]), g = Number(tok[i + 1]), b = Number(tok[i + 2]);
    out.r[bin(r)]++; out.g[bin(g)]++; out.b[bin(b)]++;
    out.l[bin(0.2126 * r + 0.7152 * g + 0.0722 * b)]++;
    out.pixels++;
  }
  for (const k of ["r", "g", "b", "l"]) for (const v of out[k]) if (v > out.max) out.max = v;
  return out;
}

// ── the pixel under the pointer ───────────────────────────────────────────
// The stage shows the picture turned by the edit — mirror first, then the
// turn, Scene's order. The inspector reads the pixel off the Image itself,
// which is already upright (autoTransform), so only the edit is walked back.

// A point in the TURNED picture (tw × th, as shown) to the same point in the
// upright one (w × h, before the edit).
function unturn(x, y, w, h, rotate, mirror) {
  let ux, uy;
  if (rotate === 90) { ux = y; uy = h - 1 - x; }
  else if (rotate === 180) { ux = w - 1 - x; uy = h - 1 - y; }
  else if (rotate === 270) { ux = w - 1 - y; uy = x; }
  else { ux = x; uy = y; }
  return { x: mirror ? w - 1 - ux : ux, y: uy };
}

function hex2_(v) { return ("0" + Math.max(0, Math.min(255, Math.round(v))).toString(16)).slice(-2); }
function pixelHex(r, g, b) { return "#" + hex2_(r) + hex2_(g) + hex2_(b); }

// ── keeping the place across pictures ─────────────────────────────────────
// What part of the picture the middle of the stage is on, as fractions of
// it — and the view that puts the same fractions back in the middle of
// another picture at zoom `z`. Locked zoom, and the compare's second half.
function centreOf(v, w, h, sw, sh) {
  if (!(w > 0) || !(h > 0) || !(v.z > 0)) return { fx: 0.5, fy: 0.5 };
  return { fx: (sw / 2 - v.x) / (w * v.z), fy: (sh / 2 - v.y) / (h * v.z) };
}

function viewAt(z, fx, fy, w, h, sw, sh) {
  const nz = clampZoom(z);
  return clampView({ z: nz, x: sw / 2 - fx * w * nz, y: sh / 2 - fy * h * nz }, w, h, sw, sh);
}

// ── the gallery's filter ──────────────────────────────────────────────────
// What was typed, split: words starting # are tags the picture must carry
// ("#★" is the favourite), and the rest is matched against the name.
const FAVOURITE = "favourite";

// `is:` words narrow by kind instead: is:video, is:picture (or is:image),
// is:marked, is:directory — the last keeps only the directories.
const FILTER_KINDS = { video: "video", videos: "video", picture: "picture", pictures: "picture",
                       image: "picture", images: "picture", marked: "marked",
                       folder: "folder", folders: "folder", dir: "folder",
                       directory: "folder", directories: "folder", dirs: "folder" };

function splitFilter(q) {
  const tags = [], words = [], kinds = [];
  for (const w of String(q || "").trim().split(/\s+/)) {
    if (w === "") continue;
    const m = /^is:(\w+)$/i.exec(w);
    if (m && FILTER_KINDS[m[1].toLowerCase()]) { kinds.push(FILTER_KINDS[m[1].toLowerCase()]); continue; }
    if (w.charAt(0) === "#" && w.length > 1) {
      const t = w.slice(1);
      tags.push(t === "★" || t === "fav" ? FAVOURITE : t);
    } else if (w === "★") tags.push(FAVOURITE);
    else words.push(w);
  }
  return { tags: tags, text: words.join(" "), kinds: kinds };
}

function hasAllTags(names, wanted) {
  for (const t of wanted || []) if (!names || names.indexOf(t) < 0) return false;
  return true;
}

// ── the slideshow ─────────────────────────────────────────────────────────
const SLIDE_SECS = [2, 4, 8, 15, 30];

// ── the clipboard ─────────────────────────────────────────────────────────
// What it holds, to look at: files (text/uri-list) come back as "uris" and
// their list; a picture with no file behind it is written to `stem` plus the
// extension its type says, and comes back as "image". Anything else is
// "none".
function clipboardLookCommand(stem) {
  return 't=$(wl-paste --list-types 2>/dev/null)\n'
    + 'if printf \'%s\\n\' "$t" | grep -qx "text/uri-list"; then\n'
    + '  printf \'uris\\036\'; wl-paste -t text/uri-list 2>/dev/null; exit 0\n'
    + 'fi\n'
    + 'm=$(printf \'%s\\n\' "$t" | grep -m1 "^image/")\n'
    + '[ -n "$m" ] || { printf \'none\\036\'; exit 0; }\n'
    + 'ext=${m#image/}\n'
    + 'case $ext in jpeg) ext=jpg ;; svg+xml) ext=svg ;; x-*) ext=${ext#x-} ;; esac\n'
    + 'f="$1.$ext"\n'
    + 'mkdir -p "$(dirname "$f")" && wl-paste -t "$m" > "$f" 2>/dev/null && [ -s "$f" ]'
    + ' && printf \'image\\036%s\' "$f" || printf \'none\\036\'\n';
}

// That answer — or terminus' clipboardPasteCommand's — as { kind, paths }.
// uri-list lines are file:// URLs, percent-encoded, CRLF or LF; anything not
// a local file is dropped (GNOME's list leads with "copy" or "cut", which
// goes the same way). "wrote" is terminus' picture written into a directory,
// and its path is the name it was given there.
function parseClipboardLook(text) {
  const s = String(text || "");
  const cut = s.indexOf("\u001e");
  const kind = cut < 0 ? "none" : s.slice(0, cut);
  const rest = cut < 0 ? "" : s.slice(cut + 1);
  if (kind === "image" || kind === "wrote") {
    const p = rest.split("\u001e")[0].trim();
    return p === "" ? { kind: "none", paths: [] } : { kind: kind, paths: [p] };
  }
  if (kind !== "uris" && kind !== "gnome") return { kind: "none", paths: [] };
  const paths = [];
  for (const line of rest.split(/\r?\n/)) {
    const l = line.trim();
    if (l.indexOf("file://") !== 0) continue;
    try { paths.push(decodeURIComponent(l.slice(7).replace(/^[^/]*/, ""))); } catch (e) {}
  }
  return { kind: paths.length > 0 ? "uris" : "none", paths: paths };
}

// ── reading text ──────────────────────────────────────────────────────────
// tesseract on a png, its text to the clipboard. A missing tesseract says so
// with exit 127, which the caller turns into "install it".
function ocrCommand(png) {
  return 'command -v tesseract >/dev/null || exit 127\n'
    + 'out=$(tesseract "$1" - 2>/dev/null | sed -e \'s/[[:space:]]*$//\' | sed -e :a -e \'/^\\n*$/{$d;N;ba\' -e \'}\')\n'
    + 'rm -f "$1"\n'
    + '[ -n "$out" ] || exit 3\n'
    + 'printf \'%s\' "$out" | wl-copy\n';
}

// ── alike pictures ────────────────────────────────────────────────────────
// A difference hash: the picture squeezed to 9×8 in grey, each pixel
// compared with the one to its right — 64 bits that survive a resize, a
// re-save and a little colour, which a checksum does not. Read from a plain
// (P2) pgm, so it is text all the way, as the histogram is. Hex, 16 digits;
// "" for anything that is not a 9×8 pgm.
function dhashFromPgm(text) {
  const tok = String(text || "").replace(/#[^\n]*/g, " ").split(/\s+/).filter((x) => x !== "");
  if (tok[0] !== "P2" || Number(tok[1]) !== 9 || Number(tok[2]) !== 8 || tok.length < 4 + 72) return "";
  let hex = "";
  for (let row = 0; row < 8; ++row) {
    let nib = 0;
    for (let col = 0; col < 8; ++col) {
      const a = Number(tok[4 + row * 9 + col]), b = Number(tok[4 + row * 9 + col + 1]);
      nib = (nib << 1) | (a > b ? 1 : 0);
      if (col % 4 === 3) { hex += nib.toString(16); nib = 0; }
    }
  }
  return hex;
}

const POP4 = [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4];
// Bits that differ between two hashes; 64 when either is missing.
function hamming(a, b) {
  if (!a || !b || a.length !== b.length) return 64;
  let d = 0;
  for (let i = 0; i < a.length; ++i) d += POP4[parseInt(a.charAt(i), 16) ^ parseInt(b.charAt(i), 16)];
  return d;
}

// How alike is alike: up to this many of the 64 bits apart. Six catches a
// re-save, a resize and a small crop; past ten, two shots of the same wall
// start to meet.
const ALIKE = 6;

// The pictures that look alike, in groups of two or more: `items` is
// [{ path, hash, … }], grouped by any chain of near ones (so a, b and c are
// one group when a is near b and b near c). Each group is in the order the
// items came, and the groups in the order of their first member.
function alikeGroups(items, maxDist) {
  const n = (items || []).length, lim = maxDist === undefined ? ALIKE : maxDist;
  const up = [];
  for (let i = 0; i < n; ++i) up.push(i);
  const top = (i) => { while (up[i] !== i) { up[i] = up[up[i]]; i = up[i]; } return i; };
  for (let i = 0; i < n; ++i) {
    if (!items[i].hash) continue;
    for (let j = i + 1; j < n; ++j)
      if (items[j].hash && hamming(items[i].hash, items[j].hash) <= lim) {
        const a = top(i), b = top(j);
        if (a !== b) up[Math.max(a, b)] = Math.min(a, b);
      }
  }
  const byTop = {}, order = [];
  for (let i = 0; i < n; ++i) {
    if (!items[i].hash) continue;
    const t = top(i);
    if (!byTop[t]) { byTop[t] = []; order.push(t); }
    byTop[t].push(items[i]);
  }
  return order.map((t) => byTop[t]).filter((g) => g.length > 1);
}

// The one of a group worth keeping: the most pixels, then the biggest file
// (the least squeezed), then the oldest (the original, not the copy).
function keeperOf(group) {
  let best = null;
  for (const it of group || []) {
    if (!best) { best = it; continue; }
    const pa = (it.w || 0) * (it.h || 0), pb = (best.w || 0) * (best.h || 0);
    if (pa !== pb) { if (pa > pb) best = it; continue; }
    if ((it.size || 0) !== (best.size || 0)) { if ((it.size || 0) > (best.size || 0)) best = it; continue; }
    if ((it.mtime || 0) < (best.mtime || 0)) best = it;
  }
  return best;
}

// The hash of each of `$@`, one line each: "path<TAB>w h P2 9 8 255 …" —
// the size read off the header (the decode below is shrunk, and so is
// what it would say), then the pgm's lines joined with spaces. Four at
// once; a jpeg is decoded small to begin with, which is most of the time.
function dhashCommand() {
  return 'printf \'%s\\0\' "$@" | xargs -0 -P 4 -n 1 sh -c \''
    + 'd=$(magick identify -ping -format "%w %h" -- "$0[0]" 2>/dev/null); '
    + 'g=$(magick -define jpeg:size=64x64 -- "$0[0]" -auto-orient '
    + '-colorspace gray -resize "9x8!" -depth 8 -compress none pgm:- 2>/dev/null | tr "\\n" " "); '
    + '[ -n "$g" ] && printf "%s\\t%s %s\\n" "$0" "$d" "$g"\'\n';
}

// That output as { path: { hash, w, h } }. The size comes first in each
// line — the -format before the pgm — and is the picture's upright size.
function parseHashes(text) {
  const out = {};
  for (const line of String(text || "").split("\n")) {
    const cut = line.indexOf("\t");
    if (cut <= 0) continue;
    const rest = line.slice(cut + 1);
    const m = /^(\d+) (\d+) (P2.*)$/.exec(rest.trim());
    if (!m) continue;
    const hash = dhashFromPgm(m[3]);
    if (hash !== "") out[line.slice(0, cut)] = { hash: hash, w: Number(m[1]), h: Number(m[2]) };
  }
  return out;
}

// ── when, and where ───────────────────────────────────────────────────────
// exiftool -j -n of a directory's pictures: when each was taken (to the
// hundredth, for bursts) and where. Seconds since the epoch in local time,
// as the camera wrote it; NaN for a file that does not say.
function exifTime(s, sub) {
  const m = /^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/.exec(String(s || ""));
  if (!m || m[1] === "0000") return NaN;
  const t = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6])).getTime() / 1000;
  const frac = parseFloat("0." + String(sub === undefined || sub === null ? "" : sub).replace(/\D/g, ""));
  return isFinite(frac) ? t + frac : t;
}

function parseMeta(json) {
  const out = {};
  let list = [];
  try { list = JSON.parse(String(json || "[]")); } catch (e) { return out; }
  for (const e of list || []) {
    if (!e || !e.SourceFile) continue;
    let t = exifTime(e.DateTimeOriginal, e.SubSecTimeOriginal);
    if (!isFinite(t)) t = exifTime(e.CreateDate, e.SubSecCreateDate);
    const lat = Number(e.GPSLatitude), lon = Number(e.GPSLongitude);
    const geo = isFinite(lat) && isFinite(lon) && e.GPSLatitude !== undefined && e.GPSLongitude !== undefined
      && !(lat === 0 && lon === 0) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180;
    out[e.SourceFile] = { t: isFinite(t) ? t : null, lat: geo ? lat : null, lon: geo ? lon : null };
  }
  return out;
}

const META_TAGS = ["-DateTimeOriginal", "-SubSecTimeOriginal", "-CreateDate", "-SubSecCreateDate",
                   "-GPSLatitude", "-GPSLongitude"];
function metaArgv(paths) {
  return ["exiftool", "-j", "-n", "-q", "-fast2"].concat(META_TAGS).concat(["--"]).concat(paths);
}

// When a row was taken: what the camera said, else when the file was written.
function takenOf(row, meta) {
  const m = meta ? meta[row.path] : null;
  return m && m.t !== null && m.t !== undefined ? m.t : (row.mtime || 0);
}

// ── the gallery's sections ───────────────────────────────────────────────
// Day by day for a directory that spans a couple of months at most, month by
// month past that — a phone's camera directory by day is a thousand headings.
function sectionScale(times) {
  let lo = Infinity, hi = -Infinity;
  for (const t of times) if (t > 0) { lo = Math.min(lo, t); hi = Math.max(hi, t); }
  return hi - lo <= 62 * 86400 ? "day" : "month";
}

const MONTHS = ["January", "February", "March", "April", "May", "June", "July",
                "August", "September", "October", "November", "December"];
const DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

// The section a moment falls in: a key to compare, the heading, and the
// scrubber's short word for it.
function sectionOf(t, scale) {
  if (!(t > 0)) return { key: "none", text: "No date", short: "—" };
  const d = new Date(t * 1000);
  const y = d.getFullYear(), m = d.getMonth();
  if (scale === "day")
    return { key: y + "-" + m + "-" + d.getDate(),
             text: DAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[m] + " " + y,
             short: d.getDate() + " " + MONTHS[m].slice(0, 3) };
  return { key: y + "-" + m, text: MONTHS[m] + " " + y, short: MONTHS[m].slice(0, 3) + " " + String(y).slice(2) };
}

// Runs of pictures taken moments apart — a burst, a bracket — in the order
// given: consecutive rows no more than `gap` seconds apart, three or more of
// them. { start, n } by the index of the first.
function bursts(times, gap) {
  const g = gap === undefined ? 2 : gap, out = [];
  let i = 0;
  while (i < times.length) {
    let j = i;
    while (j + 1 < times.length && times[i] > 0 && times[j + 1] > 0 && Math.abs(times[j + 1] - times[j]) <= g) j++;
    if (j - i + 1 >= 3) out.push({ start: i, n: j - i + 1 });
    i = j + 1;
  }
  return out;
}

// The gallery's items, laid out for a grid `cols` wide: the directories, then
// the pictures — a section starting a fresh line of the grid, padded to it
// with empty cells ({ isFill }), and its heading carried on its first cell
// rather than taking a line of its own (see chips). `sectionAt` is { row
// index: { text, kind, key, … } }; `hidden` the row indices a folded burst
// keeps out of sight.
// Returns { items, chips: { item index: section }, at: { path: item index } }.
function galleryLayout(directories, rows, cols, sectionAt, hidden) {
  const items = [], chips = {}, at = {};
  const c = Math.max(1, cols || 1);
  const breakLine = () => { while (items.length % c !== 0) items.push({ isFill: true }); };
  for (const f of directories || []) items.push(f);
  const any = sectionAt && Object.keys(sectionAt).length > 0;
  if (any && items.length > 0) breakLine();
  for (let i = 0; i < (rows || []).length; ++i) {
    if (hidden && hidden[i]) continue;
    const sec = sectionAt ? sectionAt[i] : null;
    if (sec) { breakLine(); chips[items.length] = sec; }
    at[rows[i].path] = items.length;
    items.push(rows[i]);
  }
  return { items: items, chips: chips, at: at };
}

// What the cursor can rest on: a directory or a picture, not a filler.
function selectable(it) { return !!it && !it.isFill; }

// The cursor moved by `d` items from `i` — a step across a line passes
// over fillers in the direction it is going; a step down or up (by `cols`)
// that lands on one goes on to the nearest thing before it on that line,
// then the line beyond.
function gallerySeek(items, i, d, cols) {
  const n = (items || []).length;
  if (n === 0) return 0;
  let j = Math.max(0, Math.min(n - 1, i + d));
  if (selectable(items[j])) return j;
  if (Math.abs(d) <= 1) {
    const s = d < 0 ? -1 : 1;
    while (j >= 0 && j < n && !selectable(items[j])) j += s;
    if (j >= 0 && j < n) return j;
    return i;
  }
  // a vertical step onto a filler: back along the line to the last real cell
  let k = j;
  const lineStart = j - (j % Math.max(1, cols));
  while (k > lineStart && !selectable(items[k])) k--;
  if (selectable(items[k])) return k;
  const s = d < 0 ? -1 : 1;
  while (k >= 0 && k < n && !selectable(items[k])) k += s;
  return k >= 0 && k < n ? k : i;
}

// ── the map ──────────────────────────────────────────────────────────────
// Web Mercator, in tiles: the world is 2^z tiles of 256 across at zoom z.
const TILE = 256;
function lonToX(lon, z) { return (lon + 180) / 360 * Math.pow(2, z); }
function latToY(lat, z) {
  const r = Math.max(-85.05112878, Math.min(85.05112878, lat)) * Math.PI / 180;
  return (1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2 * Math.pow(2, z);
}
function xToLon(x, z) { return x / Math.pow(2, z) * 360 - 180; }
function yToLat(y, z) {
  const n = Math.PI - 2 * Math.PI * y / Math.pow(2, z);
  return 180 / Math.PI * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)));
}

// The zoom and middle that show all of `pts` ([{ lat, lon }]) in a box of
// w × h pixels, with a margin; one point alone is shown at street level.
function fitMap(pts, w, h) {
  if (!pts || pts.length === 0) return { z: 2, lat: 20, lon: 0 };
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  for (const p of pts) {
    const x = lonToX(p.lon, 0), y = latToY(p.lat, 0);
    x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y);
  }
  let z = 16;
  while (z > 1 && ((x1 - x0) * Math.pow(2, z) * TILE > w * 0.8 || (y1 - y0) * Math.pow(2, z) * TILE > h * 0.8)) z--;
  return { z: z, lat: yToLat((y0 + y1) / 2, 0), lon: xToLon((x0 + x1) / 2, 0) };
}

// Pins near each other on screen are one pin with a count: `pts` placed at
// zoom z, gathered into squares of `cell` pixels. Each pin is { x, y, n,
// items } in world pixels, at the middle of what it holds.
function clusterPins(pts, z, cell) {
  const k = Math.pow(2, z) * TILE, size = cell || 48, bins = {}, order = [];
  for (const p of pts || []) {
    const x = lonToX(p.lon, 0) * k, y = latToY(p.lat, 0) * k;
    const key = Math.floor(x / size) + "," + Math.floor(y / size);
    if (!bins[key]) { bins[key] = { sx: 0, sy: 0, items: [] }; order.push(key); }
    bins[key].sx += x; bins[key].sy += y; bins[key].items.push(p);
  }
  return order.map((key) => {
    const b = bins[key];
    return { x: b.sx / b.items.length, y: b.sy / b.items.length, n: b.items.length, items: b.items };
  });
}

// OpenStreetMap's tiles, fetched once with a name of our own and kept on
// disk — the tile policy asks for both, and a map opened twice should not
// ask twice. Prints the file when it is there.
function tileUrl(z, x, y) { return "https://tile.openstreetmap.org/" + z + "/" + x + "/" + y + ".png"; }
function tileFile(dir, z, x, y) { return dir + "/" + z + "/" + x + "/" + y + ".png"; }
function tileCommand() {
  return 'f=$1; u=$2\n'
    + '[ -s "$f" ] && { printf "%s" "$f"; exit 0; }\n'
    + 'mkdir -p "$(dirname "$f")" && curl -fsSL --max-time 20 -A "picasso-view/1.0 (ZENWORKS image viewer)" -o "$f.part" "$u"'
    + ' && mv -f "$f.part" "$f" && printf "%s" "$f"\n';
}

// ── a picture's own colours ───────────────────────────────────────────────
// `magick … -colors N -format %c histogram:info:-` — "  1234: (r,g,b) #RRGGBB …"
// a line per colour; the most used first.
function parsePalette(text) {
  const out = [];
  for (const line of String(text || "").split("\n")) {
    const m = /^\s*(\d+):.*?(#[0-9A-Fa-f]{6})/.exec(line);
    if (m) out.push({ n: Number(m[1]), hex: m[2].toLowerCase() });
  }
  out.sort((a, b) => b.n - a.n);
  return out;
}

// ── a sheet of them ───────────────────────────────────────────────────────
// ImageMagick's montage: the pictures in a grid `cols` wide, each in a 4:3
// cell `cell` pixels wide, their names under them if asked, on the window's
// dark.
// `$1` the file to write, the pictures after it.
function contactSheetCommand(cols, cell, names) {
  // the labels are set on the pictures once they are read: given before
  // them, as montage's own -label, they never showed
  // and their font is named outright: ImageMagick's own default is a font
  // this machine may not have, and then the names are silently left off
  return 'out=$1; shift\n'
    + 'f=$(fc-match -f "%{file}" sans 2>/dev/null)\n'
    + 'magick montage "$@" -auto-orient ' + (names ? '-set label "%f" ${f:+-font "$f"} -pointsize 14 -fill "#dfdfdd" ' : '')
    + '-background "#15161b" -tile ' + Math.max(1, cols) + 'x -geometry '
    + cell + 'x' + Math.round(cell * 3 / 4) + '+12+12 "$out"\n';
}
function contactCols(n) { return Math.max(1, Math.min(8, Math.ceil(Math.sqrt(n || 1)))); }

// ── putting back what was written over ────────────────────────────────────
// Before a file is written over in place — a save, a turn, a mark saved on
// itself — it is copied here, and `u` copies it back. Kept by the hour of
// the session, not forever: a cache.
function backupName(dir, path, stamp) {
  const base = String(path || "").split("/").pop() || "picture";
  return dir + "/" + stamp + "-" + base;
}
function backupCommand() {
  // $1 the directory, then pairs of picture and copy
  return 'mkdir -p "$1" || exit 1; shift\n'
    + 'while [ $# -ge 2 ]; do cp -p -- "$1" "$2" || exit 1; shift 2; done\n';
}
function restoreCommand() {
  // pairs of copy and picture: each copy back where it came from
  return 's=0\nwhile [ $# -ge 2 ]; do cp -p -- "$1" "$2" && rm -f -- "$1" || s=1; shift 2; done\nexit $s\n';
}

// ── the extra tools, when they are installed ─────────────────────────────
// Which of them this machine has — one `command -v` for all, so a menu row
// for a tool that is not there is never offered.
const EXTRA_TOOLS = ["rembg", "realesrgan-ncnn-vulkan", "upscayl-bin", "tesseract", "exiftool"];
function toolsCommand() {
  return 'for t in ' + EXTRA_TOOLS.join(" ") + '; do command -v "$t" >/dev/null 2>&1 && printf "%s\\n" "$t"; done; exit 0\n';
}
function parseTools(text) {
  const out = {};
  for (const l of String(text || "").split("\n")) if (l.trim() !== "") out[l.trim()] = true;
  return out;
}

// What each tool is asked: the input $1, the output $2.
function cutoutCommand() { return 'rembg i -- "$1" "$2"\n'; }
function upscaleCommand(bin) {
  return bin === "upscayl-bin"
    ? 'upscayl-bin -i "$1" -o "$2" -s 4 -n realesrgan-x4plus -f png\n'
    : 'realesrgan-ncnn-vulkan -i "$1" -o "$2" -s 4 -n realesrgan-x4plus -f png\n';
}
// One key's worth of better: levels stretched, the mid-tones evened, a
// little sharpening. ImageMagick, so every format it reads.
function enhanceCommand() {
  return 'magick -- "$1[0]" -auto-orient -auto-level -auto-gamma -unsharp 0x0.8+0.6+0.02 -quality 92 "$2"\n';
}

// ── the background's view of it ───────────────────────────────────────────
// The part of a w × h picture each monitor would show, filled and centred —
// as the background's own "fill" crops. [{ name, x, y, w, h }] in the
// picture's pixels.
function monitorCuts(w, h, screens) {
  const out = [];
  for (const s of screens || []) {
    if (!(s.width > 0) || !(s.height > 0) || !(w > 0) || !(h > 0)) continue;
    const r = s.width / s.height;
    const c = centredCrop(w, h, r);
    out.push({ name: s.name, x: c.x, y: c.y, w: c.w, h: c.h,
               short: s.width > c.w * 1.05 || s.height > c.h * 1.05 });
  }
  return out;
}

// ── somewhere to go ───────────────────────────────────────────────────────
// Directories worth jumping to: the last ones looked at here, newest first, at
// most `max`, and the one now shown not counted twice.
function noteRecent(list, dir, max) {
  if (!dir) return (list || []).slice();
  const out = [dir].concat((list || []).filter((d) => d !== dir));
  return out.slice(0, max || 10);
}

// ── a video's time ───────────────────────────────────────────────────────
// Milliseconds as a clock: 0:07, 1:02:03.
function clock(ms) {
  const t = Math.max(0, Math.floor((Number(ms) || 0) / 1000));
  const h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, s = t % 60;
  const two = (n) => (n < 10 ? "0" : "") + n;
  return (h > 0 ? h + ":" + two(m) : String(m)) + ":" + two(s);
}

// ── for sending ──────────────────────────────────────────────────────────
// The sizes Export for the web offers: the longest side, the format, how
// hard it is squeezed.
const EXPORTS = [
  { t: "1600 px  ·  WebP", edge: 1600, ext: "webp", q: 82 },
  { t: "2560 px  ·  WebP", edge: 2560, ext: "webp", q: 85 },
  { t: "1600 px  ·  JPEG", edge: 1600, ext: "jpg", q: 85 },
  { t: "2048 px  ·  AVIF", edge: 2048, ext: "avif", q: 60 }
];
