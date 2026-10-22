// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The pure half of argus' editor: times, the range, names, and every ffmpeg
// line it can run.

"use strict";

module.exports = {
  module: "argus/argus.js",
  cases: (A, t) => {
    // times
    t.eq("tenths", A.stamp(83450), "1:23.5");
    t.eq("zero", A.stamp(0), "0:00.0");
    t.eq("an hour", A.stamp(3723400), "1:02:03.4");
    t.eq("seconds for ffmpeg", A.secs(1500), "1.500");

    // the range
    t.eq("kept inside the clip", A.clampRange(-50, 99999, 10000), { inMs: 0, outMs: 10000 });
    t.eq("in pushed past out gives way", A.clampRange(9990, 9995, 10000, "in"), { inMs: 9900, outMs: 10000 });
    t.eq("out pulled before in gives way", A.clampRange(500, 520, 10000, "out"), { inMs: 420, outMs: 520 });
    t.eq("a clip shorter than the minimum is all of it", A.clampRange(10, 20, 80), { inMs: 0, outMs: 80 });
    t.eq("no out is the end", A.clampRange(0, undefined, 5000).outMs, 5000);
    t.eq("whole", A.whole(0, 5000, 5000), true);

    // names
    const src = "/home/u/Videos/Captures/2026-10-20-232145-DP-1.mp4";
    t.eq("beside the original", A.outPath(src, "mp4"), "/home/u/Videos/Captures/2026-10-20-232145-DP-1-cut.mp4");
    t.eq("a gif", A.outPath(src, "gif"), "/home/u/Videos/Captures/2026-10-20-232145-DP-1-cut.gif");
    const taken = new Set([A.outPath(src, "webm"), A.outPath(src, "webm").replace("-cut.", "-cut-2.")]);
    t.eq("taken names are stepped past", A.outPath(src, "webm", (p) => taken.has(p)), "/home/u/Videos/Captures/2026-10-20-232145-DP-1-cut-3.webm");
    t.eq("save as keeps the format's extension", A.withExt("/tmp/clip.mp4", "gif"), "/tmp/clip.gif");
    t.eq("…and adds one", A.withExt("/tmp/clip", "webm"), "/tmp/clip.webm");

    // commands
    const o = { inMs: 1500, outMs: 4000, format: "mp4", exact: false, audio: true, gifWidth: 720, gifFps: 15, loop: true };
    const copy = A.ffmpegArgs(src, "/o.mp4", o);
    t.eq("ffmpeg first", copy[0], "ffmpeg");
    t.has("seeks before the input", copy.join(" "), "-ss 1.500 -t 2.500 -i " + src);
    t.has("a plain cut copies", copy.join(" "), "-c:v copy");
    t.has("…its audio too", copy.join(" "), "-c:a copy");
    t.has("progress on stdout", copy.join(" "), "-progress pipe:1");
    t.eq("the output last", copy[copy.length - 1], "/o.mp4");
    const exact = A.ffmpegArgs(src, "/o.mp4", Object.assign({}, o, { exact: true, audio: false }));
    t.has("an exact cut re-encodes", exact.join(" "), "-c:v libx264");
    t.has("no audio is -an", exact.join(" "), "-an");
    const gif = A.ffmpegArgs(src, "/o.gif", Object.assign({}, o, { format: "gif" }));
    t.has("gif palette", gif.join(" "), "palettegen");
    t.has("gif rate", gif.join(" "), "fps=15");
    t.has("gif never upscales", gif.join(" "), "scale='min(720,iw)'");
    t.has("gif loops", gif.join(" "), "-loop 0");
    t.eq("gif has no audio flags", gif.indexOf("-an") < 0 && gif.indexOf("-c:a") < 0, true);
    const orig = A.ffmpegArgs(src, "/o.gif", Object.assign({}, o, { format: "gif", gifWidth: 0, loop: false }));
    t.has("original width", orig.join(" "), "scale='min(iw,iw)'");
    t.has("once", orig.join(" "), "-loop -1");
    const webm = A.ffmpegArgs(src, "/o.webm", Object.assign({}, o, { format: "webm" }));
    t.has("webm is vp9", webm.join(" "), "libvpx-vp9");
    t.has("…with opus", webm.join(" "), "libopus");
    // the crop: even, clamped, null for the whole picture; MP4 copy turns into an encode
    t.eq("crop rounds to even", A.cropOf({ x: 11, y: 7, w: 301, h: 201 }, 1920, 1080), { x: 10, y: 6, w: 300, h: 200 });
    t.eq("crop of everything is none", A.cropOf({ x: 0, y: 0, w: 1920, h: 1080 }, 1920, 1080), null);
    t.eq("crop clamped inside", A.cropOf({ x: 1900, y: 0, w: 400, h: 100 }, 1920, 1080), { x: 1900, y: 0, w: 20, h: 100 });
    const c = { x: 10, y: 6, w: 300, h: 200 };
    const cc = A.ffmpegArgs(src, "/o.mp4", Object.assign({}, o, { crop: c }));
    t.has("a cropped mp4 is encoded", cc.join(" "), "libx264");
    t.has("…through the crop filter", cc.join(" "), "-vf crop=300:200:10:6");
    t.has("a cropped gif crops first", A.ffmpegArgs(src, "/o.gif", Object.assign({}, o, { format: "gif", crop: c })).join(" "), "crop=300:200:10:6,fps=");
    t.has("a cropped webm", A.ffmpegArgs(src, "/o.webm", Object.assign({}, o, { format: "webm", crop: c })).join(" "), "-vf crop=300:200:10:6");
    t.eq("ratio of 1:1", A.ratioValue("1:1"), 1);
    // every argument a plain string, so Process gets it untouched
    t.eq("all strings", [copy, exact, gif, webm].every((a) => a.every((x) => typeof x === "string")), true);

    // progress
    t.eq("progress", A.progressOf("frame=10\nout_time_us=1250000\nprogress=continue\n", 2500), 0.5);
    t.eq("the last block wins", A.progressOf("out_time_us=1\nout_time_us=2500000\n", 2500), 1);
    t.eq("none yet", A.progressOf("frame=1\n", 2500), 0);

    // settings
    t.eq("defaults", A.parseSettings(""), A.defaults());
    t.eq("unknown widths fall back", A.parseSettings('{"gifWidth":123}').gifWidth, 720);
    t.eq("round trip", A.parseSettings(A.serializeSettings({ format: "gif", gifFps: 24 })).gifFps, 24);

    // the filmstrip
    const strip = A.stripArgs(src, "/tmp/s", 12000, 12);
    t.has("one frame a second for 12 in 12 s", strip.join(" "), "fps=1.0000,scale=-2:96");
    t.has("into the dir", strip.join(" "), "/tmp/s/f%02d.jpg");

    // ── recording preferences ──
    t.eq("the line argus.lua reads", A.recPrefsLine({ recCountdown: 3, recAudio: "both", recBigPointer: true, recCamera: false }),
      "countdown=3 audio=both pointer=1 camera=0");
    t.eq("odd values fall back", A.recPrefsLine({ recCountdown: 99, recAudio: "loud" }), "countdown=10 audio=system pointer=0 camera=0");
    t.eq("nothing is how it was", A.recPrefsLine(null), "countdown=0 audio=system pointer=0 camera=0");
    t.eq("bottom right", A.cornerAnchors("bottomRight"), { top: false, bottom: true, left: false, right: true });
    t.eq("top left", A.cornerAnchors("topLeft"), { top: true, bottom: false, left: true, right: false });
  }
};
