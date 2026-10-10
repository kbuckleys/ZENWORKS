// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PICASSO'S VIEWER: what the launcher hands over, zoom and pan, the crop's
// ratio, and what the camera said.

"use strict";

module.exports = {
  module: "picasso/viewer.js",
  cases: (V, t) => {
    t.eq("one path", V.parsePaths("/a/b.png"), ["/a/b.png"]);
    t.eq("several, blank and twice", V.parsePaths("/a.png\n\n/b.png\n/a.png\n"), ["/a.png", "/b.png"]);
    t.eq("found by path", V.indexOfPath([{ path: "/a" }, { path: "/b" }], "/b"), 1);

    t.eq("a big picture fits", V.fitScale(4000, 2000, 1000, 800), 0.25);
    t.eq("a small one is not blown up", V.fitScale(100, 100, 1000, 800), 1);
    t.eq("unless allowed", V.fitScale(100, 100, 1000, 800, 4), 4);
    t.eq("up from the fit to the next stop", V.stepZoom(0.3, 1), 0.33);
    t.eq("down through actual size", V.stepZoom(1.25, -1), 1);
    t.eq("down from actual size", V.stepZoom(1, -1), 0.8);

    t.eq("fitted is centred", V.fitView(2000, 1000, 1000, 1000),
      { z: 0.5, x: 0, y: 250 });
    t.eq("a picture smaller than the stage stays centred",
      V.clampView({ z: 1, x: -300, y: 40 }, 100, 100, 500, 500), { z: 1, x: 200, y: 200 });
    t.eq("an overflowing one cannot leave a gap",
      V.clampView({ z: 1, x: 50, y: -5000 }, 2000, 2000, 500, 500), { z: 1, x: 0, y: -1500 });
    // zooming about a point keeps that point of the picture under it
    const v = V.zoomAbout({ z: 1, x: -500, y: -500 }, 2, 250, 250, 2000, 2000, 500, 500);
    t.eq("the pointer's pixel stays put", [(250 - v.x) / v.z, (250 - v.y) / v.z], [750, 750]);

    t.eq("a quarter turn swaps", V.turnedSize(300, 200, 90), { w: 200, h: 300 });
    t.eq("a half turn does not", V.turnedSize(300, 200, 180), { w: 300, h: 200 });
    t.eq("edited keeps its type", V.editedName("/a/IMG_1.jpg"), "IMG_1-edited.jpg");
    t.eq("tagged", V.editedName("/a/s.png", "crop"), "s-crop.png");
    t.eq("a jpeg can be written", V.writable("/a/b.JPG"), true);
    t.eq("a raw cannot", V.writable("/a/b.cr2"), false);

    t.eq("a square out of a wide picture", V.centredCrop(400, 200, 1), { x: 100, y: 0, w: 200, h: 200 });
    t.eq("free is the whole", V.centredCrop(400, 200, 0), { x: 0, y: 0, w: 400, h: 200 });
    t.eq("letterbox trimmed", V.parseTrim("462 232 400x200+31+16", 460, 230), { x: 30, y: 15, w: 400, h: 200 });
    t.eq("trim scaled to a stand-in", V.parseTrim("462 232 400x200+31+16", 230, 115), { x: 15, y: 8, w: 200, h: 100 });
    t.eq("no border, nothing to trim", V.parseTrim("102 102 100x100+1+1", 100, 100), { none: true });
    t.eq("all black is no picture", V.parseTrim("102 102 0x0+102+102", 100, 100), null);
    t.eq("garbage", V.parseTrim("", 100, 100), null);
    t.eq("trim turns as the stage", V.trimCommand(90, true).indexOf("-flop -rotate 90 -bordercolor") > 0, true);
    t.eq("dragging the right side drags the height, from the middle",
      V.fitAspect({ x: 0, y: 50, w: 200, h: 100 }, "r", 1, 1000, 1000), { x: 0, y: 0, w: 200, h: 200 });
    // bottom-right held at (400, 200); the square it wants would pass the top
    t.eq("a corner keeps the opposite corner",
      V.fitAspect({ x: 100, y: 100, w: 300, h: 100 }, "tl", 1, 1000, 1000), { x: 200, y: 0, w: 200, h: 200 });
    t.eq("shrunk rather than run off the picture",
      V.fitAspect({ x: 0, y: 0, w: 400, h: 100 }, "br", 1, 1000, 300), { x: 0, y: 0, w: 300, h: 300 });

    t.eq("exif, read like a photographer",
      V.parseExif("Model=X100V\nExposureTime=1/250\nFNumber=28/10\nFocalLength=23/1\n"
        + "PhotographicSensitivity=400\nDateTimeOriginal=2026:09:28 14:03:11\nLensModel=\n"),
      [{ k: "Camera", v: "X100V" }, { k: "Exposure", v: "1/250 s" }, { k: "Aperture", v: "f/2.8" },
       { k: "Focal length", v: "23 mm" }, { k: "ISO", v: "400" }, { k: "Taken", v: "2026-09-28 14:03" }]);

    t.eq("gps, north and east", V.parseGps("GPSLatitude=52/1, 31/1, 1200/100\nGPSLatitudeRef=N\n"
      + "GPSLongitude=13/1, 24/1, 0/1\nGPSLongitudeRef=E\n"), { lat: 52.52, lon: 13.4 });
    t.eq("gps, south and west are negative", V.parseGps("GPSLatitude=33/1,52/1,0/1\nGPSLatitudeRef=S\n"
      + "GPSLongitude=151/1,12/1,36/1\nGPSLongitudeRef=W\n"), { lat: -33.86667, lon: -151.21 });
    t.eq("half a location is none", V.parseGps("GPSLatitude=52/1, 0/1, 0/1\nGPSLatitudeRef=N\n"), null);
    t.eq("the map", V.mapUrl({ lat: 1.5, lon: -2 }), "https://www.openstreetmap.org/?mlat=1.5&mlon=-2#map=15/1.5/-2");

    const h = V.histogram("P3\n# a comment\n2 2\n255\n0 0 0  255 255 255\n255 0 0  0 0 255\n", 4);
    t.eq("histogram counts every pixel", h.pixels, 4);
    t.eq("red: two dark, two bright", h.r, [2, 0, 0, 2]);
    t.eq("blue likewise", h.b, [2, 0, 0, 2]);
    t.eq("luminance by weight", h.l, [3, 0, 0, 1]);
    t.eq("the tallest bin", h.max, 3);
    t.eq("not a ppm is empty", V.histogram("hello", 2).pixels, 0);

    // every turn and mirror walks back to where it came from: the forward
    // walk is Scene's — mirror, then the clockwise turn
    const fwd = (x, y, w, h, rot, mir) => {
      const mx = mir ? w - 1 - x : x;
      if (rot === 90) return { x: h - 1 - y, y: mx };
      if (rot === 180) return { x: w - 1 - mx, y: h - 1 - y };
      if (rot === 270) return { x: y, y: w - 1 - mx };
      return { x: mx, y: y };
    };
    for (const rot of [0, 90, 180, 270]) for (const mir of [false, true]) {
      const p = fwd(3, 1, 10, 6, rot, mir);
      t.eq("unturned " + rot + (mir ? " mirrored" : ""), V.unturn(p.x, p.y, 10, 6, rot, mir), { x: 3, y: 1 });
    }
    t.eq("hex", V.pixelHex(255, 128.4, 0), "#ff8000");

    const c = V.centreOf({ z: 2, x: -500, y: -300 }, 1000, 800, 1000, 600);
    t.eq("the stage's middle, in the picture", c, { fx: 0.5, fy: 0.375 });
    t.eq("and put back there", V.viewAt(2, c.fx, c.fy, 1000, 800, 1000, 600), { z: 2, x: -500, y: -300 });
    t.eq("clamped at the edges", V.viewAt(2, 0, 0, 1000, 800, 1000, 600), { z: 2, x: 0, y: 0 });

    t.eq("filter: tags and words", V.splitFilter("  #red beach  #★ sun "),
      { tags: ["red", "favourite"], text: "beach sun", kinds: [] });
    t.eq("a bare star is the favourite", V.splitFilter("★").tags, ["favourite"]);
    t.eq("all tags carried", V.hasAllTags(["a", "b"], ["b"]), true);
    t.eq("one missing", V.hasAllTags(["a"], ["a", "b"]), false);
    t.eq("no tags wanted", V.hasAllTags(undefined, []), true);

    t.eq("clipboard files", V.parseClipboardLook("uris\u001efile:///home/a%20b.png\r\nfile:///c.jpg\r\nhttp://x/y\r\n"),
      { kind: "uris", paths: ["/home/a b.png", "/c.jpg"] });
    t.eq("clipboard picture", V.parseClipboardLook("image\u001e/run/p.png"), { kind: "image", paths: ["/run/p.png"] });
    t.eq("gnome's list, its verb dropped", V.parseClipboardLook("gnome\u001ecopy\nfile:///a.png"),
      { kind: "uris", paths: ["/a.png"] });
    t.eq("terminus wrote one", V.parseClipboardLook("wrote\u001ePasted image.png\u001e"),
      { kind: "wrote", paths: ["Pasted image.png"] });
    t.eq("clipboard nothing", V.parseClipboardLook("none\u001e"), { kind: "none", paths: [] });

    // ── the 2026-10-04 second round ──
    t.eq("monitors' ratios, when they differ", V.screenRatios([{ name: "A", width: 2560, height: 1440 },
      { name: "B", width: 2560, height: 1080 }]).map((r) => r.t), ["A  16:9", "B  21:9"]);
    t.eq("one monitor adds nothing", V.screenRatios([{ name: "A", width: 1920, height: 1080 }]), []);
    t.eq("16:10 named", V.ratioName(1920, 1200), "16:10");
    t.eq("no turn, no growth", V.straightenScale(400, 300, 0), 1);
    t.eq("a turn grows to cover", Math.round(V.straightenScale(400, 300, 5) * 1000), 1112);

    const row = (vals) => vals.join(" ");
    const pgm = "P2\n9 8\n255\n" + [0, 1, 2, 3, 4, 5, 6, 7].map(() => row([9, 8, 7, 6, 5, 4, 3, 2, 1])).join("\n");
    t.eq("falling rows hash to ones", V.dhashFromPgm(pgm), "ffffffffffffffff");
    t.eq("not a 9×8 pgm", V.dhashFromPgm("P2\n2 2\n255\n1 2 3 4"), "");
    t.eq("hamming", V.hamming("ff00", "0f01"), 5);
    t.eq("missing is far", V.hamming("", "ff"), 64);
    const gs = V.alikeGroups([{ path: "a", hash: "0000000000000000" }, { path: "b", hash: "ffffffffffffffff" },
      { path: "c", hash: "0000000000000007" }, { path: "d", hash: "000000000000003f" }, { path: "e", hash: "" }]);
    t.eq("alike in a chain", gs.map((g) => g.map((x) => x.path)), [["a", "c", "d"]]);
    t.eq("keeper: most pixels", V.keeperOf([{ path: "a", w: 10, h: 10 }, { path: "b", w: 20, h: 10 }]).path, "b");
    t.eq("keeper: then the bigger file", V.keeperOf([{ path: "a", w: 1, h: 1, size: 5 }, { path: "b", w: 1, h: 1, size: 9 }]).path, "b");
    t.eq("keeper: then the oldest", V.keeperOf([{ path: "a", w: 1, h: 1, size: 5, mtime: 9 }, { path: "b", w: 1, h: 1, size: 5, mtime: 2 }]).path, "b");
    t.eq("hashes parsed", V.parseHashes("/a.jpg\t40 30 " + pgm.replace(/\n/g, " ") + "\nnoise\n"),
      { "/a.jpg": { hash: "ffffffffffffffff", w: 40, h: 30 } });

    t.eq("no date", V.exifTime("0000:00:00 00:00:00"), NaN);
    t.eq("subseconds", V.exifTime("2024:05:01 10:00:00", "25") - V.exifTime("2024:05:01 10:00:00"), 0.25);
    const meta = V.parseMeta(JSON.stringify([{ SourceFile: "/a.jpg", DateTimeOriginal: "2024:05:01 10:00:00",
      GPSLatitude: 52.5, GPSLongitude: 13.4 }, { SourceFile: "/b.jpg", CreateDate: "2024:05:02 10:00:00", GPSLatitude: 0, GPSLongitude: 0 }]));
    t.eq("where, when it says", [meta["/a.jpg"].lat, meta["/a.jpg"].lon], [52.5, 13.4]);
    t.eq("null island is nowhere", meta["/b.jpg"].lat, null);
    t.eq("create date stands in", meta["/b.jpg"].t > 0, true);
    t.eq("bad json is nothing", V.parseMeta("{"), {});
    t.eq("taken falls back to mtime", V.takenOf({ path: "/x", mtime: 7 }, meta), 7);
    t.eq("a short span is by day", V.sectionScale([1e9, 1e9 + 86400 * 3]), "day");
    t.eq("a long one by month", V.sectionScale([1e9, 1e9 + 86400 * 90]), "month");
    t.eq("month heading", V.sectionOf(new Date(2024, 4, 3, 12).getTime() / 1000, "month").text, "May 2024");
    t.eq("undated", V.sectionOf(0, "day").key, "none");
    t.eq("bursts of three or more", V.bursts([1, 2, 3, 3.5, 10, 11, 20, 20.5, 21, 0]), [{ start: 0, n: 4 }, { start: 6, n: 3 }]);

    const L = V.galleryLayout([{ path: "/up", isDir: true }], [{ path: "/a" }, { path: "/b" }, { path: "/c" }], 3,
      { 0: { text: "May" }, 2: { text: "June" } }, null);
    t.eq("sections start a line", L.items.map((x) => x.isFill ? "_" : x.path), ["/up", "_", "_", "/a", "/b", "_", "/c"]);
    t.eq("chips on the first cells", Object.keys(L.chips), ["3", "6"]);
    t.eq("where each picture is", L.at["/c"], 6);
    t.eq("hidden rows are left out", V.galleryLayout([], [{ path: "/a" }, { path: "/b" }], 4, null, { 1: true }).items.length, 1);
    t.eq("no sections, no padding", V.galleryLayout([{ path: "/up" }], [{ path: "/a" }], 3, {}, null).items.length, 2);
    t.eq("seek past a filler", V.gallerySeek(L.items, 4, 1, 3), 6);
    t.eq("seek back past fillers", V.gallerySeek(L.items, 3, -1, 3), 0);
    t.eq("down onto a filler goes back along its line", V.gallerySeek(L.items, 4, 3, 3), 6);
    t.eq("up onto fillers", V.gallerySeek(L.items, 4, -3, 3), 0);

    t.eq("tile x", Math.floor(V.lonToX(13.4, 10)), 550);
    t.eq("tile y", Math.floor(V.latToY(52.5, 10)), 335);
    t.eq("and back", Math.round(V.yToLat(V.latToY(52.5, 10), 10) * 1000) / 1000, 52.5);
    t.eq("one point is street level", V.fitMap([{ lat: 1, lon: 2 }], 800, 600).z, 16);
    t.eq("the world fits low", V.fitMap([{ lat: 60, lon: -120 }, { lat: -30, lon: 140 }], 800, 600).z <= 2, true);
    t.eq("near pins gather", V.clusterPins([{ lat: 52.5, lon: 13.4 }, { lat: 52.50001, lon: 13.40001 }, { lat: 10, lon: 10 }], 5, 48)
      .map((p) => p.n), [2, 1]);
    t.eq("a tile on disk", V.tileFile("/c", 3, 4, 5), "/c/3/4/5.png");

    t.eq("palette, most used first", V.parsePalette("   12: (1,2,3) #010203 srgb(1,2,3)\n  40: (255,0,0) #FF0000 red\n"),
      [{ n: 40, hex: "#ff0000" }, { n: 12, hex: "#010203" }]);
    t.eq("sheet columns", [V.contactCols(1), V.contactCols(10), V.contactCols(200)], [1, 4, 8]);
    t.eq("backup name", V.backupName("/u", "/p/a.jpg", "123"), "/u/123-a.jpg");
    t.eq("tools found", V.parseTools("rembg\n\ntesseract\n"), { rembg: true, tesseract: true });
    t.eq("monitor cuts", V.monitorCuts(4000, 3000, [{ name: "A", width: 1600, height: 900 }]),
      [{ name: "A", x: 0, y: 375, w: 4000, h: 2250, short: false }]);
    t.eq("small for the monitor", V.monitorCuts(800, 600, [{ name: "A", width: 2560, height: 1440 }])[0].short, true);
    t.eq("recent: newest first, no twice", V.noteRecent(["/a", "/b", "/c"], "/b", 3), ["/b", "/a", "/c"]);
    t.eq("clock", [V.clock(7000), V.clock(62000), V.clock(3723000)], ["0:07", "1:02", "1:02:03"]);
  }
};
