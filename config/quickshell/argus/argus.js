// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

.pragma library
// ONE COPY FOR THE WHOLE SHELL (see morpheus/icons.js).
//
// ARGUS' PURE HALF: the times as written, the range kept sane, the file a
// cut is saved as, and the ffmpeg line for each format — so the editor only
// draws and asks, and oracle/tests/argus.js checks every command.

var FORMATS = [
  { id: "mp4", label: "MP4", ext: ".mp4" },
  { id: "gif", label: "GIF", ext: ".gif" },
  { id: "webm", label: "WebM", ext: ".webm" }
];
// a GIF's longest side, and how many frames a second; 0 is the original
var GIF_WIDTHS = [0, 960, 720, 480];
var GIF_FPS = [10, 15, 24, 30];
var MIN_LEN = 100;   // ms: shorter than this is not a clip

function formatOf(id) {
  for (var i = 0; i < FORMATS.length; ++i) if (FORMATS[i].id === id) return FORMATS[i];
  return FORMATS[0];
}

function defaults() {
  return { format: "mp4", exact: false, audio: true, gifWidth: 720, gifFps: 15, loop: true };
}
function parseSettings(text) {
  var d = defaults(), j;
  try { j = JSON.parse(String(text || "")); } catch (e) { return d; }
  if (!j || typeof j !== "object") return d;
  if (FORMATS.some(function (f) { return f.id === j.format; })) d.format = j.format;
  if (typeof j.exact === "boolean") d.exact = j.exact;
  if (typeof j.audio === "boolean") d.audio = j.audio;
  if (GIF_WIDTHS.indexOf(j.gifWidth) >= 0) d.gifWidth = j.gifWidth;
  if (GIF_FPS.indexOf(j.gifFps) >= 0) d.gifFps = j.gifFps;
  if (typeof j.loop === "boolean") d.loop = j.loop;
  return d;
}
function serializeSettings(s) { return JSON.stringify(parseSettings(JSON.stringify(s)), null, 2) + "\n"; }

// ── TIMES ────────────────────────────────────────────────────────────────
// 83450 → "1:23.4": tenths, because a cut is placed finer than a second
function stamp(ms) {
  var t = Math.max(0, Math.round((Number(ms) || 0) / 100));
  var tenths = t % 10, s = Math.floor(t / 10) % 60, m = Math.floor(t / 600) % 60, h = Math.floor(t / 36000);
  var two = function (n) { return (n < 10 ? "0" : "") + n; };
  return (h > 0 ? h + ":" + two(m) : String(m)) + ":" + two(s) + "." + tenths;
}
// ffmpeg's: seconds, three places
function secs(ms) { return (Math.max(0, Number(ms) || 0) / 1000).toFixed(3); }

// The range, kept inside the clip and at least MIN_LEN long. `moved` says
// which end the user is holding, so that end gives way last.
function clampRange(inMs, outMs, dur, moved) {
  var d = Math.max(0, Number(dur) || 0);
  var a = Math.max(0, Math.min(d, Number(inMs) || 0));
  var b = Math.max(0, Math.min(d, outMs === undefined || outMs === null ? d : Number(outMs)));
  if (d <= MIN_LEN) return { inMs: 0, outMs: d };
  if (b - a < MIN_LEN) {
    if (moved === "out") { b = Math.max(b, MIN_LEN); a = b - MIN_LEN; }
    else { a = Math.min(a, d - MIN_LEN); b = a + MIN_LEN; }
  }
  return { inMs: Math.round(a), outMs: Math.round(b) };
}
function whole(inMs, outMs, dur) { return inMs <= 0 && outMs >= dur; }

// ── NAMES ────────────────────────────────────────────────────────────────
function dirOf(p) { var s = String(p || ""); var i = s.lastIndexOf("/"); return i > 0 ? s.slice(0, i) : "/"; }
function baseOf(p) { var s = String(p || "").replace(/.*\//, ""); var i = s.lastIndexOf("."); return i > 0 ? s.slice(0, i) : s; }
// beside the original: "2026-10-20-232145-DP-1.mp4" → "…-DP-1-cut.mp4";
// taken already ("taken(path)" true) → "-cut-2", "-cut-3"…
function outPath(src, format, taken) {
  var f = formatOf(format);
  var stem = dirOf(src) + "/" + baseOf(src) + "-cut";
  var p = stem + f.ext;
  for (var n = 2; taken && taken(p) && n < 1000; ++n) p = stem + "-" + n + f.ext;
  return p;
}
// A path and the names that follow it, for when it is taken: "a.mp4",
// "a-2.mp4" … "a-59.mp4". For a name the file picker never asked about —
// Save as's, once withExt has changed its extension (2026-10-23: "clip.mov"
// as MP4 overwrote an existing "clip.mp4" without a word).
function variants(path) {
  const s = String(path || "");
  const m = /^(.*?)(\.[A-Za-z0-9]{2,5})?$/.exec(s);
  const out = [s];
  for (let n = 2; n < 60; ++n) out.push(m[1] + "-" + n + (m[2] || ""));
  return out;
}
// whatever was typed into Save as, with this format's extension
function withExt(path, format) {
  var f = formatOf(format), s = String(path || "");
  return /\.[A-Za-z0-9]{2,5}$/.test(s.replace(/.*\//, "")) ? s.replace(/\.[A-Za-z0-9]{2,5}$/, f.ext) : s + f.ext;
}

// ── THE COMMANDS ─────────────────────────────────────────────────────────
// o: { inMs, outMs, format, exact, audio, gifWidth, gifFps, loop }
// Seeking BEFORE -i (fast, on keyframes for a copy; exact for a re-encode,
// which decodes from the keyframe before and drops what precedes `in`).
// ── THE CROP (2026-10-21) ────────────────────────────────────────────────
// { x, y, w, h } in the video's pixels, or null for all of it. Even numbers:
// yuv420p (MP4, WebM) halves the color planes and refuses an odd size.
var CROP_RATIOS = [
  { id: "free", label: "Free", value: 0 },
  { id: "1:1", label: "1:1", value: 1 },
  { id: "4:5", label: "4:5", value: 4 / 5 },
  { id: "16:9", label: "16:9", value: 16 / 9 },
  { id: "9:16", label: "9:16", value: 9 / 16 }
];
function ratioValue(id) {
  for (var i = 0; i < CROP_RATIOS.length; i++) if (CROP_RATIOS[i].id === id) return CROP_RATIOS[i].value;
  return 0;
}
function even(v) { return Math.max(0, Math.floor(Number(v) / 2) * 2); }
// null when the box is (near enough) the whole picture
function cropOf(r, vw, vh) {
  if (!r || !(vw > 0) || !(vh > 0)) return null;
  var x = even(Math.max(0, Math.min(vw - 2, r.x))), y = even(Math.max(0, Math.min(vh - 2, r.y)));
  var w = even(Math.max(2, Math.min(vw - x, r.w))), h = even(Math.max(2, Math.min(vh - y, r.h)));
  if (x === 0 && y === 0 && w >= even(vw) && h >= even(vh)) return null;
  return { x: x, y: y, w: w, h: h };
}
function cropFilter(c) { return c ? "crop=" + c.w + ":" + c.h + ":" + c.x + ":" + c.y : ""; }

function ffmpegArgs(src, out, o) {
  var len = Math.max(MIN_LEN, o.outMs - o.inMs);
  var head = ["ffmpeg", "-hide_banner", "-nostdin", "-y", "-progress", "pipe:1", "-nostats"];
  var cut = ["-ss", secs(o.inMs), "-t", secs(len), "-i", src];
  var audio = function (codec) { return o.audio ? codec : ["-an"]; };
  var crop = cropFilter(o.crop || null);
  var vf = crop ? ["-vf", crop] : [];
  if (o.format === "gif") {
    var w = o.gifWidth > 0 ? String(o.gifWidth) : "iw";
    var graph = (crop ? crop + "," : "") + "fps=" + o.gifFps + ",scale='min(" + w + ",iw)':-1:flags=lanczos,split[a][b];"
      + "[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle";
    return head.concat(cut, ["-filter_complex", graph, "-loop", o.loop ? "0" : "-1", out]);
  }
  if (o.format === "webm")
    return head.concat(cut, vf, ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "33", "-row-mt", "1",
                             "-deadline", "good", "-cpu-used", "4", "-pix_fmt", "yuv420p"],
                       audio(["-c:a", "libopus", "-b:a", "128k"]), [out]);
  // mp4: copied as it is (instant, cuts on the nearest keyframe), or exact —
  // and a crop is always an encode: a copied stream cannot be cut down
  if (!o.exact && !crop)
    return head.concat(cut, ["-c:v", "copy"], audio(["-c:a", "copy"]),
                       ["-avoid_negative_ts", "make_zero", "-movflags", "+faststart", out]);
  return head.concat(cut, vf, ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p"],
                     audio(["-c:a", "aac", "-b:a", "160k"]), ["-movflags", "+faststart", out]);
}

// `-progress pipe:1`: key=value lines, a block at a time; the last
// out_time_us (or out_time_ms, which is microseconds too) over the length
function progressOf(text, lenMs) {
  var lines = String(text || "").split("\n"), us = -1;
  for (var i = lines.length - 1; i >= 0; --i) {
    var m = /^out_time_(?:us|ms)=(\d+)/.exec(lines[i]);
    if (m) { us = Number(m[1]); break; }
  }
  if (us < 0 || !(lenMs > 0)) return 0;
  return Math.max(0, Math.min(1, us / 1000 / lenMs));
}

// The filmstrip: `count` frames spread over the clip, small, into `dir`
function stripArgs(src, dir, durMs, count) {
  var n = Math.max(1, count | 0);
  var rate = n / Math.max(0.1, (Number(durMs) || 0) / 1000);
  return ["ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-i", src,
          "-vf", "fps=" + rate.toFixed(4) + ",scale=-2:96", "-frames:v", String(n), "-q:v", "5",
          dir + "/f%02d.jpg"];
}

// ── RECORDING PREFERENCES ────────────────────────────────────────────────
// What argus.lua asks for before it records (`qs ipc call Argus recPrefs`):
// one line of key=value words its shell reads with a case, nothing quoted.
// Anything odd falls back to how it recorded before these existed.
var REC_AUDIO = ["none", "system", "mic", "both"];
function recPrefsLine(o) {
  var cd = Math.max(0, Math.min(10, Math.round(Number(o && o.recCountdown) || 0)));
  var au = REC_AUDIO.indexOf(o && o.recAudio) >= 0 ? o.recAudio : "system";
  return "countdown=" + cd + " audio=" + au + " pointer=" + (o && o.recBigPointer ? 1 : 0) + " camera=" + (o && o.recCamera ? 1 : 0);
}
// the camera bubble's anchors for a corner
function cornerAnchors(c) {
  return { top: c === "topLeft" || c === "topRight", bottom: c !== "topLeft" && c !== "topRight",
           left: c === "topLeft" || c === "bottomLeft", right: c !== "topLeft" && c !== "bottomLeft" };
}
