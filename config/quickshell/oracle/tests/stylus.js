// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// stylus' pure half: image names, drive words, what fits where, forge.py's
// event lines and the words for a write as it goes.

"use strict";

module.exports = {
  module: "stylus/stylus.js",
  cases: (S, t) => {
    const GiB = 1073741824;
    // names
    t.eq("iso", S.isImageName("archlinux-2026.10.01-x86_64.iso"), true);
    t.eq("packed img", S.isImageName("raspios.img.xz"), true);
    t.eq("packed iso", S.isImageName("x.ISO.ZST"), true);
    t.eq("a bare xz is not one", S.isImageName("notes.tar.xz"), false);
    t.eq("no extension", S.isImageName("iso"), false);
    t.eq("text", S.isImageName("readme.txt"), false);

    // the image
    const hybrid = { kind: "hybrid", size: 1.2 * GiB, rawSize: 1.2 * GiB, compressed: "" };
    const packed = { kind: "disk", size: GiB, rawSize: 4 * GiB, compressed: "xz" };
    const gz = { kind: "raw", size: GiB, rawSize: 0, compressed: "gz" };
    t.eq("plain line", S.sourceLine(hybrid), "Bootable ISO  ·  1.2 GiB");
    t.eq("packed line", S.sourceLine(packed), "Disk image  ·  xz  ·  4.0 GiB unpacked");
    t.eq("unknown unpacked size", S.sourceLine(gz), "Raw image  ·  gzip  ·  1.0 GiB packed");

    // the drives
    const usb = { kind: "usb", vendor: "SanDisk", model: "Ultra", dev: "/dev/sdb", size: 32 * GiB, removable: true,
                  parts: [{ number: 1, label: "ARCH_202610", fstype: "iso9660", size: GiB, mounts: [] },
                          { number: 2, label: "", fstype: "vfat", size: 1 << 20, mounts: ["/run/media/b/X"] }] };
    const bare = { kind: "sd", vendor: "", model: "", dev: "/dev/mmcblk0", size: 2 * GiB, parts: [] };
    const ro = { kind: "usb", model: "Locked", size: 8 * GiB, readOnly: true, parts: [] };
    t.eq("title", S.driveTitle(usb), "SanDisk Ultra");
    t.eq("nameless sd", S.driveTitle(bare), "SD card");
    t.eq("line", S.driveLine(usb), "32.0 GiB  ·  USB  ·  sdb");
    t.eq("parts", S.partsLine(usb), "ARCH_202610  ·  vfat");
    t.eq("no parts", S.partsLine(bare), "No partitions");
    t.eq("glyph", S.driveGlyph(bare), "\u{F0479}");
    t.eq("unknown kind glyph", S.driveGlyph({}), "\u{F02CA}");

    // the sidebar
    const internal = { kind: "disk", size: 500 * GiB, removable: false, bus: "ata", table: "gpt", parts: [] };
    const loop = { kind: "loop", size: GiB, parts: [] };
    t.eq("sections", S.sections([internal, usb, loop, bare]).map((s) => [s.id, s.drives.length]),
      [["internal", 1], ["external", 2], ["images", 1]]);
    t.eq("empty sections left out", S.sections([usb]).map((s) => s.id), ["external"]);
    t.eq("order follows sections", S.ordered([internal, usb, loop, bare]).map((d) => d.kind), ["disk", "usb", "sd", "loop"]);

    // the detail pane
    t.eq("detail line", S.detailLine(Object.assign({ table: "gpt" }, usb)), "USB external drive  \u00b7  GUID partition map");
    t.eq("internal line", S.detailLine(internal), "Internal drive  \u00b7  GUID partition map");
    t.eq("no table", S.tableWords(""), "No partition map");
    t.eq("facts", S.facts(Object.assign({ bus: "usb", table: "dos", serial: "" }, usb)).map((r) => r[0]),
      ["Capacity", "Location", "Connection", "Device", "Partition map", "Partitions"]);
    t.eq("read-only said", S.facts(ro).some((r) => r[0] === "Write protected"), true);
    const map = S.mapOf({ size: 100, parts: [{ number: 2, offset: 60, size: 30 }, { number: 1, offset: 10, size: 40 }] });
    t.eq("map", map.map((m) => [m.part ? m.part.number : 0, m.start, m.frac, m.ink]),
      [[0, 0, 0.1, -1], [1, 0.1, 0.4, 0], [0, 0.5, 0.1, -1], [2, 0.6, 0.3, 1], [0, 0.9, 0.1, -1]]);
    const two = { size: 100, parts: [{ dev: "b", number: 2, offset: 60, size: 30 }, { dev: "a", number: 1, offset: 10, size: 40 }] };
    t.eq("part inks by place on the drive", [S.partInk(two, "a"), S.partInk(two, "b"), S.partInk(two, "zz")], ["cyan", "magenta", ""]);
    t.eq("blank drive is all free", S.mapOf(bare).map((m) => [m.part, m.frac]), [[null, 1]]);
    t.eq("tiny gaps dropped", S.mapOf({ size: 1000, parts: [{ number: 1, offset: 1, size: 999 }] }).length, 1);
    t.eq("part name", [S.partName({ label: "", number: 3 }), S.partName(null)], ["Partition 3", "Free space"]);
    t.eq("part name falls back", [S.partName({ partLabel: "home", number: 8 }), S.partName({ mounts: ["/"], number: 2 })], ["home", "/"]);
    t.eq("nvme words", S.facts({ bus: "nvme", system: true, size: 1, parts: [] }).filter((r) => r[0] === "Connection" || r[0] === "Role"),
      [["Role", "The system runs from it"], ["Connection", "NVMe"]]);

    // a volume
    const home = { dev: "/dev/nvme0n1p8", number: 8, label: "", partLabel: "home", fstype: "ext4", version: "1.0",
                   uuid: "ab-12", size: 1800 * GiB, mounts: ["/home"] };
    const sysd = { kind: "disk", system: true, dev: "/dev/nvme0n1", model: "CT2000", size: 1900 * GiB, parts: [home] };
    t.eq("part of", S.partOf(sysd, "/dev/nvme0n1p8"), home);
    t.eq("no part", S.partOf(sysd, ""), null);
    t.eq("volume line", S.volumeLine(home), "ext4 1.0  \u00b7  mounted at /home");
    t.eq("unmounted line", S.volumeLine({ fstype: "vfat", mounts: [] }), "vfat  \u00b7  not mounted");
    t.eq("volume facts", S.volumeFacts(sysd, home, { total: 10, used: GiB, free: GiB }).map((r) => r[0]),
      ["Capacity", "Used", "Free", "Filesystem", "Partition name", "Mounted at", "Device", "UUID", "On"]);
    const td = S.asDisk(usb, usb.parts[1]);
    t.eq("terminus record", [td.path, td.mount, td.device, td.fstype, td.size], ["", "/run/media/b/X", "/dev/sdb", "vfat", "1.0 MiB"]);

    // LUKS
    const locked = { dev: "/dev/sdc1", fstype: "crypto_LUKS", encrypted: true, inner: null, mounts: [], size: 8 * GiB, number: 1 };
    const open_ = Object.assign({}, locked, { inner: { dev: "/dev/dm-3", fstype: "ext4", version: "1.0", label: "vault" }, mounts: ["/run/media/b/vault"] });
    t.eq("locked line", S.volumeLine(locked), "Encrypted (LUKS)  \u00b7  locked");
    t.eq("unlocked line", S.volumeLine(open_), "Encrypted ext4  \u00b7  mounted at /run/media/b/vault");
    t.eq("first aid acts inside", [S.fsPart(open_).dev, S.fsPart(open_).fstype], ["/dev/dm-3", "ext4"]);
    t.eq("a plain volume is itself", S.fsPart(home), home);
    t.eq("repair a locked one", S.offWhy("repair", usb, locked), "Unlock it first");
    t.eq("lock a locked one", S.offWhy("lock", usb, locked), "It is not unlocked");
    t.eq("lock an open one", S.offWhy("lock", usb, open_), "");

    // what is off
    t.eq("write to the system disk", S.offWhy("write", sysd, null), "The system runs from this drive");
    t.eq("eject the system disk", S.offWhy("eject", sysd, null), "The system runs from this drive");
    t.eq("erase the system disk", S.offWhy("erase", sysd, null), "The system runs from this drive");
    t.eq("repair a mounted system volume", S.offWhy("repair", sysd, home), "The system stands on /home");
    t.eq("write a usb", S.offWhy("write", usb, null), "");
    t.eq("erase a whole usb", S.offWhy("erase", usb, null), "");
    t.eq("erase a blank drive", S.offWhy("erase", bare, null), "");
    t.eq("rename a system volume", S.offWhy("rename", sysd, home), "The system stands on /home");
    t.eq("reset preset, small", S.resetPreset(usb), { scope: "msdos", fs: "vfat", label: "USB" });
    t.eq("reset preset, big", S.resetPreset({ size: 64 * GiB }).fs, "exfat");
    t.eq("whole disk record", [S.wholeDisk(usb).path, S.wholeDisk(usb).device, S.wholeDisk(usb).deviceBytes], ["/dev/sdb", "/dev/sdb", 32 * GiB]);
    t.eq("partition names only on gpt", [S.canName({ table: "gpt" }, {}), S.canName({ table: "dos" }, {})], [true, false]);
    t.eq("clean name", S.cleanName("  a\u0001b" + "x".repeat(50)), "ab" + "x".repeat(34));
    t.eq("repair needs a volume", S.offWhy("repair", usb, null), "Pick a volume in the sidebar");
    t.eq("repair a usb volume", S.offWhy("repair", usb, usb.parts[0]), "");
    t.eq("mount on a locked drive is fine", S.offWhy("mount", ro, { fstype: "vfat", mounts: [] }), "");
    t.eq("erase on a locked drive is not", S.offWhy("erase", ro, { fstype: "vfat", mounts: [] }), "The drive is write-protected");

    // partitioning
    const M = 1048576;
    const disk = { size: 1000 * M, table: "gpt", parts: [
      { dev: "a", offset: 1 * M, size: 300 * M, fstype: "ext4", used: 100 * M },
      { dev: "b", offset: 500 * M, size: 200 * M, fstype: "vfat", used: -1 }] };
    t.eq("free between and after", S.freeSpaces(disk), [{ offset: 301 * M, size: 199 * M }, { offset: 700 * M, size: 299 * M }]);
    t.eq("a blank drive is one stretch", S.freeSpaces({ size: 64 * M, table: "", parts: [] }), [{ offset: M, size: 62 * M }]);
    t.eq("mbr keeps no tail", S.freeSpaces({ size: 64 * M, table: "dos", parts: [] }), [{ offset: M, size: 63 * M }]);
    const ext = { grow: true, shrink: true }, xfs = { grow: true, shrink: false };
    t.eq("ext4 mounted: down to what it holds, up to the next", S.resizeRange(disk, disk.parts[0], ext),
      { min: 174 * M, max: 499 * M, why: "" });
    t.eq("unmounted: no floor known", S.resizeRange(disk, disk.parts[1], ext).why, "Mount it, so what it holds is known, to make it smaller");
    t.eq("last one grows to the end", S.resizeRange(disk, disk.parts[1], ext).max, 499 * M);
    t.eq("xfs never shrinks", S.resizeRange(disk, disk.parts[0], xfs), { min: 300 * M, max: 499 * M, why: "ext4 cannot be made smaller" });
    t.eq("exfat neither way", S.resizeRange(disk, disk.parts[0], { grow: false, shrink: false }), { min: 300 * M, max: 300 * M, why: "ext4 cannot be resized" });
    t.eq("four on mbr", S.createWhy({ table: "dos", parts: [1, 2, 3, 4] }), "An MBR table holds four partitions — erase it as GPT for more");
    t.eq("types", [S.newType("vfat", "dos"), S.newType("ext4", "gpt")], ["0x0c", "0FC63DAF-8483-4772-8E79-3D69D8477DE4"]);
    t.eq("partition the system disk", S.offWhy("partition", sysd, null), "The system runs from this drive");

    // settings
    t.eq("settings default", S.parseSettings("nope"), { sidebar: true });
    t.eq("settings kept", S.parseSettings('{"sidebar":false,"showAll":true}'), { sidebar: false });

    // what fits
    t.eq("fits", S.fits(hybrid, usb).ok, true);
    t.eq("too small", S.fits(packed, bare), { ok: false, why: "Too small — the image needs 4.0 GiB" });
    t.eq("read-only", S.fits(hybrid, ro).ok, false);
    t.eq("size unknown: let it try", S.fits(gz, bare).ok, true);
    t.eq("nothing chosen", S.blocker(null, [usb], false), "Choose an image");
    t.eq("no drive", S.blocker(hybrid, [], false), "Choose a drive");
    t.eq("one too small", S.blocker(packed, [usb, bare], false), "SD card: Too small — the image needs 4.0 GiB");
    t.eq("windows onto one", S.blocker({ kind: "windows", size: 1, rawSize: 1 }, [usb], false), "");
    t.eq("windows not onto two", S.blocker({ kind: "windows", size: 1, rawSize: 1 }, [usb, bare], false), "A Windows installer goes onto one drive at a time");
    t.eq("bad signature warned first", S.writeWarning(hybrid, true, true), "The signature does not match — this may not be what its makers released");
    t.eq("signed", S.sigWords({ state: "good", signer: "Pierre Schmitz <pierre@archlinux.org>", of: "image" }), { words: "Signed by Pierre Schmitz", level: "good", key: "" });
    t.eq("signed sums", S.sigWords({ state: "good", signer: "Ubuntu CD Image Automatic Signing Key (2012) <cdimage@ubuntu.com>", of: "sums" }).words,
      "Signed by Ubuntu CD Image Automatic Signing Key (2012) (its checksums)");
    t.eq("no key", S.sigWords({ state: "nokey", key: "ABC" }), { words: "Signed with a key not on this machine", level: "", key: "ABC" });
    t.eq("bad", S.sigWords({ state: "bad" }).level, "bad");
    t.eq("unsigned", S.sigWords({ state: "none" }).words, "");
    t.eq("copy phase", S.progressLine({ phase: "copy", frac: 0.5, rate: 0, phaseMs: 0 }), "Copying the installer 50%");
    t.eq("all clear", S.blocker(hybrid, [usb], false), "");
    t.eq("label one", S.writeLabel([usb]), "Write to SanDisk Ultra");
    t.eq("label many", S.writeLabel([usb, bare]), "Write to 2 drives");

    t.eq("erase notice", [S.eraseNotice(1), S.eraseNotice(2)], ["This action will erase the drive", "This action will erase 2 drives"]);
    t.eq("bad sums warned", S.writeWarning(hybrid, true), "The checksum does not match — the download may be damaged");
    t.eq("plain iso warned", S.writeWarning({ kind: "iso" }, false), "This ISO is not made to start from a USB drive; it may not boot");
    t.eq("nothing to warn of", S.writeWarning(hybrid, false), "");

    // events
    t.eq("event", S.parseEvent('{"ev": "phase", "phase": "write"}'), { ev: "phase", phase: "write" });
    t.eq("not json", S.parseEvent("Traceback (most recent call last):"), null);
    t.eq("json, not an event", S.parseEvent("[1,2]"), null);
    t.eq("phase words", [S.phaseWords("open"), S.phaseWords("nope")], ["Waiting for permission", "Starting"]);
    t.eq("rate", S.rateWords(25 * 1048576), "25.0 MiB/s");
    t.eq("eta too early", S.etaWords(0.02, 60000), "");
    t.eq("eta minutes", S.etaWords(0.25, 60000), "about 3 min left");
    t.eq("eta seconds", S.etaWords(0.9, 60000), "less than a minute left");
    t.eq("eta hours", S.etaWords(0.1, 600000), "about 1 h 30 min left");
    t.eq("progress line", S.progressLine({ phase: "write", frac: 0.426, rate: 10485760, phaseMs: 1000 }), "Writing 42%  ·  10.0 MiB/s");
    t.eq("sync line", S.progressLine({ phase: "sync" }), "Finishing writing");
    t.eq("fill writing", S.phaseFrac({ phase: "write", frac: 0.5 }), 0.5);
    t.eq("fill syncing", S.phaseFrac({ phase: "sync", frac: 0 }), 1);
    t.eq("fill done", S.phaseFrac({ phase: "verify", frac: 0.2, result: {} }), 1);
    t.eq("head, no drives", S.headWords(null, []), "Plug in a drive");
    t.eq("head, drives", S.headWords(null, [{}, {}]), "2 drives");
    t.eq("head, writing", S.headWords({ phase: "sync" }, []), "Finishing writing");

    const j0 = { frac: 0.5, rate: 9, at: 1000 };
    t.eq("a new phase starts over", S.advance(j0, { ev: "phase", phase: "scan" }, 5000), { frac: 0, rate: 0, at: 5000, phase: "scan", phaseMs: 0 });
    t.eq("progress", S.advance(j0, { ev: "progress", frac: 0.7, rate: 3 }, 4000), { frac: 0.7, rate: 3, at: 1000, phaseMs: 3000 });
    t.eq("done holds the answer", S.advance(j0, { ev: "done", ok: true }, 2000).result, { ev: "done", ok: true });
    t.eq("scan line", S.progressLine({ phase: "scan", frac: 0.25, rate: 0, phaseMs: 100 }), "Reading every sector 25%");

    const sj = { drive: usb, phase: "scan", frac: 0.5, rate: 0, phaseMs: 10, result: null };
    t.eq("scan, another drive", S.scanWords(sj, bare).level, "");
    t.eq("scan, running", S.scanWords(sj, usb).words, "Reading every sector 50%");
    t.eq("scan, clean", S.scanWords(Object.assign({}, sj, { result: { ok: true } }), usb), { words: "Every sector reads", level: "good" });
    t.eq("scan, bad", S.scanWords(Object.assign({}, sj, { result: { ok: false, why: "3 unreadable sectors" } }), usb), { words: "3 unreadable sectors", level: "bad" });
    t.eq("scan, stopped", S.scanWords(Object.assign({}, sj, { result: { ok: false, code: "cancelled", why: "Stopped at 50%" } }), usb).level, "");

    // back up, clone
    const ds = S.driveSource(usb);
    t.eq("a drive as a source", [ds.kind, ds.rawSize, S.sourceLine(ds)], ["drive", 32 * GiB, "A whole drive  \u00b7  32.0 GiB"]);
    t.eq("it fits a bigger one", S.fits(ds, { size: 64 * GiB }).ok, true);
    t.eq("not a smaller one", S.fits(ds, bare), { ok: false, why: "Too small — SanDisk Ultra is 32.0 GiB" });
    const day = new Date(2026, 9, 4);
    t.eq("backup name, drive", S.backupName(usb, null, true, day), "SanDisk Ultra 2026-10-04.img.zst");
    t.eq("backup name, volume at /", S.backupName(sysd, { mounts: ["/"], number: 2 }, false, day), "backup 2026-10-04.img");
    t.eq("backup name, no slashes", S.backupName({ vendor: "A/B", model: "C:D" }, null, true, day), "A-B C-D 2026-10-04.img.zst");
    t.eq("backup running", S.backupWords({ phase: "backup", frac: 0.1, rate: 0, phaseMs: 0 }), "Backing up 10%");
    t.eq("backup saved", S.backupWords({ result: { ok: true, written: GiB, read: 8 * GiB } }), "Saved \u2014 1.0 GiB on disk, from 8.0 GiB");

    // benchmark
    const br = { ok: true, avg: 2 * GiB, min: 1.5 * GiB, max: 2.4 * GiB, accessMs: 0.083,
                 rates: [{ at: 0, rate: 2 * GiB }, { at: 0.5, rate: 1 * GiB }] };
    t.eq("bars against the fastest", S.benchBars(br).map((b) => b.frac), [1, 0.5]);
    t.eq("bench words", S.benchWords(br), "Reads at 2.0 GiB/s on average, between 1.5 GiB/s and 2.4 GiB/s across it");
    t.eq("even drive, no spread said", S.benchWords({ ok: true, avg: GiB, min: GiB, max: GiB }), "Reads at 1.0 GiB/s on average");
    t.eq("access, flash", S.accessWords(0.083), "0.08 ms to reach a random spot");
    t.eq("access, spinning", S.accessWords(12.4), "12 ms to reach a random spot");
    t.eq("an image is ejected by detaching", S.offWhy("eject", loop, null), "");

    // outcomes
    const done = { ok: false, verified: true, why: "x", targets: [
      { target: "/org/a", dev: "/dev/sdb", ok: true }, { target: "/org/b", dev: "/dev/sdc", ok: false, why: "The drive was taken out" }] };
    t.eq("head, some written", S.headWords({ result: done }, []), "1 of 2 written");
    t.eq("head, none", S.headWords({ result: { ok: false, why: "Permission was not given" } }, []), "Permission was not given");
    t.eq("head, done", S.headWords({ result: { ok: true } }, []), "Done");
    t.eq("written", S.resultOf(done, "/dev/sdb"), { ok: true, words: "Written and checked" });
    t.eq("pulled", S.resultOf(done, "/dev/sdc"), { ok: false, words: "The drive was taken out" });
    t.eq("failed before targets", S.resultOf({ ok: false, why: "Permission was not given" }, "/dev/sdb"), { ok: false, words: "Permission was not given" });
    t.eq("toast ok", S.toastOf({ ok: true, verified: true }, ["SanDisk Ultra"]), { title: "Written", body: "SanDisk Ultra — written and checked" });
    t.eq("toast stopped", S.toastOf({ ok: false, code: "cancelled" }, ["a", "b"]).body, "2 drives is half written");

    // sums chip
    t.eq("sums running", S.sumsOf({ sums: { algo: "sha512" } }, { running: true }).words, "Checking sha512…");
    t.eq("sums ok", S.sumsOf({}, { done: { checked: true, ok: true, algo: "sha256" } }), { state: "ok", words: "sha256 matches" });
    t.eq("sums bad", S.sumsOf({}, { done: { checked: true, ok: false, algo: "sha256" } }).state, "bad");
    t.eq("no sums file", S.sumsOf({ sums: null }, null).state, "none");
  }
};
