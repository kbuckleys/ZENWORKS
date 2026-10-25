// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// stylus' pure half: what an image and a drive are called, whether one can
// go onto the other, forge.py's event lines, and the words for a write in
// progress (oracle/tests/stylus.js).

.pragma library
.import "../terminus/terminus.js" as Terminus

// ── WHAT AN IMAGE IS ─────────────────────────────────────────────────────
// By name, for the menus that offer "Write to a drive…" before anything
// has been opened; forge.py's probe is the one that knows.
var IMAGE_EXTS = { iso: 1, img: 1, raw: 1, dd: 1 };
var PACKED_EXTS = { xz: 1, zst: 1, gz: 1, bz2: 1 };

function isImageName(name) {
  var parts = String(name || "").toLowerCase().split(".");
  if (parts.length < 2) return false;
  var last = parts[parts.length - 1];
  if (IMAGE_EXTS[last] === 1) return true;
  // image.img.xz, image.iso.zst; a bare .xz could be anything
  return PACKED_EXTS[last] === 1 && parts.length > 2 && IMAGE_EXTS[parts[parts.length - 2]] === 1;
}

var KIND_WORDS = {
  hybrid: "Bootable ISO",
  iso: "ISO image",
  windows: "Windows installer",
  disk: "Disk image",
  raw: "Raw image",
  drive: "A whole drive"
};
var COMP_WORDS = { xz: "xz", zst: "zstd", gz: "gzip", bz2: "bzip2", zip: "zip" };

// "Bootable ISO · 1.2 GiB", "Disk image · xz · 3.8 GiB unpacked"
function sourceLine(p) {
  if (!p) return "";
  var out = [KIND_WORDS[p.kind] || "Image"];
  if (p.compressed) {
    out.push(COMP_WORDS[p.compressed] || p.compressed);
    out.push(p.rawSize ? Terminus.formatSize(p.rawSize) + " unpacked" : Terminus.formatSize(p.size) + " packed");
  } else {
    out.push(Terminus.formatSize(p.size));
  }
  return out.join("  ·  ");
}

// what the size check can trust: the unpacked size when it is known
function needs(p) {
  return p ? (p.rawSize || 0) : 0;
}

// ── THE DRIVES ───────────────────────────────────────────────────────────
var DRIVE_GLYPHS = { usb: "\u{F129E}", sd: "\u{F0479}", disk: "\u{F02CA}", loop: "\u{F05EE}" };

function driveGlyph(d) {
  return DRIVE_GLYPHS[(d && d.kind) || ""] || DRIVE_GLYPHS.disk;
}

function driveTitle(d) {
  if (!d) return "";
  var name = [d.vendor, d.model].filter(function (x) { return !!x; }).join(" ").trim();
  if (name !== "") return name;
  return d.kind === "sd" ? "SD card" : d.kind === "usb" ? "USB drive" : String(d.dev || "Drive").replace(/^\/dev\//, "");
}

// "32.0 GiB · USB · sdb"
function driveLine(d) {
  if (!d) return "";
  var bus = { usb: "USB", sd: "SD", loop: "Loop device", disk: d.removable ? "Removable" : "Internal" }[d.kind] || "";
  return [Terminus.formatSize(d.size), bus, String(d.dev || "").replace(/^\/dev\//, "")]
    .filter(function (x) { return !!x; }).join("  ·  ");
}

// what is on it now — what writing will lose: "ARCH_202610 · data", or
// "Nothing on it" when it has no partitions
function partsLine(d) {
  var ps = (d && d.parts) || [];
  if (ps.length === 0) return "No partitions";
  return ps.map(function (p) {
    return p.label || p.fstype || ("partition " + p.number);
  }).join("  ·  ");
}

// ── THE SIDEBAR ──────────────────────────────────────────────────────────
// Disk Utility's grouping: the machine's own, what is plugged in, and
// images set up as loop devices
var SECTIONS = [
  { id: "internal", label: "Internal" },
  { id: "external", label: "External" },
  { id: "images", label: "Disk images" }
];

function sectionOf(d) {
  if (d.kind === "loop") return "images";
  return d.removable || d.kind === "usb" || d.kind === "sd" ? "external" : "internal";
}

// [{ id, label, drives }], the empty ones left out
function sections(drives) {
  return SECTIONS.map(function (s) {
    return { id: s.id, label: s.label, drives: (drives || []).filter(function (d) { return sectionOf(d) === s.id; }) };
  }).filter(function (s) { return s.drives.length > 0; });
}

// the sidebar's order, for ↑ ↓: section by section
function ordered(drives) {
  var out = [];
  sections(drives).forEach(function (s) { out = out.concat(s.drives); });
  return out;
}

// ── THE DETAIL PANE ──────────────────────────────────────────────────────
var TABLE_WORDS = { gpt: "GUID partition map", dos: "Master boot record" };

function tableWords(t) {
  return TABLE_WORDS[t] || (t ? String(t).toUpperCase() : "No partition map");
}

// "USB external drive  ·  GUID partition map"
function detailLine(d) {
  if (!d) return "";
  var what = d.kind === "loop" ? "Disk image" : d.kind === "sd" ? "SD card"
    : (d.kind === "usb" ? "USB " : "") + (sectionOf(d) === "external" ? "external drive" : "internal drive");
  return cap(what) + "  \u00b7  " + tableWords(d.table);
}

function cap(s) { s = String(s || ""); return s.charAt(0).toUpperCase() + s.slice(1); }

// [label, value] rows, the empty ones left out
function facts(d) {
  if (!d) return [];
  return [
    ["Capacity", Terminus.formatSize(d.size)],
    ["Location", sectionOf(d) === "internal" ? "Internal" : sectionOf(d) === "images" ? "Loop device" : "External"],
    ["Role", d.system ? "The system runs from it" : ""],
    ["Connection", BUS_WORDS[d.bus] || (d.bus ? String(d.bus).toUpperCase() : "")],
    ["Device", d.dev || ""],
    ["Partition map", tableWords(d.table)],
    ["Partitions", String((d.parts || []).length)],
    ["Serial", d.serial || ""],
    ["Write protected", d.readOnly ? "Yes" : ""]
  ].filter(function (r) { return r[1] !== ""; });
}

// the capacity bar: every partition where it lies, and the room between
// them worth showing (over 1% of the drive). { part, start, frac, ink }
// where ink indexes the bar's colors; a free stretch has part null.
function mapOf(d) {
  if (!d || !(d.size > 0)) return [];
  var ps = (d.parts || []).slice().sort(function (a, b) { return (a.offset || 0) - (b.offset || 0); });
  var out = [], at = 0, ink = 0;
  var gap = function (to) {
    if ((to - at) / d.size > 0.01) out.push({ part: null, start: at / d.size, frac: (to - at) / d.size, ink: -1 });
  };
  ps.forEach(function (p) {
    var off = p.offset || at;
    gap(off);
    out.push({ part: p, start: off / d.size, frac: Math.max(0, p.size / d.size), ink: ink++ });
    at = off + p.size;
  });
  gap(d.size);
  return out;
}

// a partition's color, the same in the map, its key and the sidebar: the
// n-th partition by where it lies on the drive takes the n-th of these
// (Zenon's names, looked up by the QML)
var PART_INKS = ["cyan", "magenta", "yellow", "green", "blue", "pink"];

function partInk(d, dev) {
  var segs = mapOf(d);
  for (var i = 0; i < segs.length; i++)
    if (segs[i].part && segs[i].part.dev === dev) return PART_INKS[segs[i].ink % PART_INKS.length];
  return "";
}

// a partition's name: its filesystem label, its partition name, where it
// is mounted, or its number, the first there is
function partName(p) {
  if (!p) return "Free space";
  return p.label || p.partLabel || ((p.mounts || [])[0] || "") || ("Partition " + p.number);
}

var BUS_WORDS = { usb: "USB", sdio: "SD", nvme: "NVMe", ata: "SATA", scsi: "SCSI", ieee1394: "FireWire" };

// ── A VOLUME ─────────────────────────────────────────────────────────────
function partOf(d, dev) {
  return d && dev ? ((d.parts || []).find(function (p) { return p.dev === dev; }) || null) : null;
}

// "ext4  ·  mounted at /home", "vfat  ·  not mounted", "Encrypted  ·
// locked", "Encrypted ext4  ·  mounted at /run/media/…"
function volumeLine(p) {
  if (!p) return "";
  if (p.encrypted) {
    if (!p.inner) return "Encrypted (LUKS)  \u00b7  locked";
    return "Encrypted " + (p.inner.fstype || "") + "  \u00b7  " + (p.mounts && p.mounts.length ? "mounted at " + p.mounts[0] : "unlocked, not mounted");
  }
  var fs = p.fstype ? p.fstype + (p.version ? " " + p.version : "") : "No filesystem";
  return fs + "  \u00b7  " + (p.mounts && p.mounts.length ? "mounted at " + p.mounts[0] : "not mounted");
}

function volumeFacts(d, p, df) {
  if (!p) return [];
  return [
    ["Capacity", Terminus.formatSize(p.size)],
    ["Used", df && df.total > 0 ? Terminus.formatSize(df.used) : ""],
    ["Free", df && df.total > 0 ? Terminus.formatSize(df.free) : ""],
    ["Filesystem", p.fstype ? p.fstype + (p.version ? " " + p.version : "") : ""],
    ["Label", p.label || ""],
    ["Partition name", p.partLabel || ""],
    ["Mounted at", (p.mounts || []).join(", ")],
    ["Device", p.dev || ""],
    ["UUID", p.uuid || ""],
    ["On", d ? driveTitle(d) : ""]
  ].filter(function (r) { return r[1] !== ""; });
}

// what First Aid and the usage bar act on: an unlocked LUKS volume's own
// filesystem, inside the container; the volume itself otherwise
function fsPart(p) {
  if (!p || !p.encrypted || !p.inner) return p;
  return { dev: p.inner.dev, fstype: p.inner.fstype, version: p.inner.version, label: p.inner.label,
           partLabel: p.partLabel, uuid: "", size: p.size, mounts: p.mounts, number: p.number };
}

// terminus' disk record (parseDisks' shape) for a partition: what its
// DiskTool (check, repair, format) is handed
function asDisk(d, p) {
  return {
    name: p.label || String(p.dev).replace(/^\/dev\//, ""), label: p.label || "", path: p.dev || "",
    size: Terminus.formatSize(p.size), mount: (p.mounts || [])[0] || "", removable: !!d.removable,
    fstype: p.fstype || "", avail: "", fsSize: "", fsUsed: "", fsVer: p.version || "", uuid: p.uuid || "",
    partLabel: p.partLabel || "", readOnly: !!d.readOnly, hotplug: !!d.removable, model: d.model || "",
    vendor: d.vendor || "", transport: d.bus || "", device: d.dev,
    // exact, for DiskTool's Auto block size
    bytes: p.size || 0, deviceBytes: d.size || 0
  };
}

// a drive with nothing on it (or nothing worth keeping) as DiskTool's
// record: the whole device, for a whole-drive erase
function wholeDisk(d) {
  return asDisk(d, { dev: d.dev, label: "", fstype: "", size: d.size, mounts: [] });
}

// RESET TO A NORMAL DRIVE: what an image left on a stick (an ISO's
// partitions, a Pi's) wiped, and one partition across it that everything
// reads — FAT32 up to 32 GiB (cars, TVs, cameras), exFAT above. DiskTool's
// preset; its card still shows every choice before anything is erased.
function resetPreset(d) {
  return { scope: "msdos", fs: d && d.size > 32 * 1073741824 ? "exfat" : "vfat", label: "USB" };
}

// what a rename may set: the label by the filesystem's rules (terminus'
// cleanLabel), the partition name only on GPT (36 characters)
function canName(d, p) {
  return !!d && !!p && d.table === "gpt";
}
function cleanName(n) {
  return Array.from(String(n || "").replace(/[\u0000-\u001f]/g, "").trim()).slice(0, 36).join("");
}

// ── WHAT IS OFF, AND WHY ─────────────────────────────────────────────────
// The system's own disk is listed but never written, erased, repaired or
// unmounted from here: what the system stands on cannot be let go of while
// it runs. "" when the action may go ahead.
function systemMounted(p) {
  return !!p && (p.mounts || []).some(function (m) { return Terminus.isSystemMount(m); });
}

function offWhy(action, d, p) {
  if (!d) return "Pick a drive";
  if (action === "write") {
    if (d.system) return "The system runs from this drive";
    if (d.readOnly) return "The drive is write-protected";
    return "";
  }
  if (action === "partition") {
    if (d.system) return "The system runs from this drive";
    if (d.readOnly) return "The drive is write-protected";
    return "";
  }
  // a disk image is ejected by being detached (forge detach)
  if (action === "eject") return d.system ? "The system runs from this drive" : "";
  if (!p) {
    if (action === "erase" && (d.parts || []).length > 0) {
      return (d.parts || []).some(systemMounted) ? "The system runs from this drive" : "";
    }
    if (action === "erase") return d.readOnly ? "The drive is write-protected" : "";
    return "Pick a volume in the sidebar";
  }
  if (systemMounted(p)) return "The system stands on " + p.mounts[0];
  if (action === "repair" && p.encrypted && !p.inner) return "Unlock it first";
  if (action === "lock" && !(p.encrypted && p.inner)) return "It is not unlocked";
  if (action === "repair" && !p.fstype) return "No filesystem to check";
  if (action === "rename" && !p.fstype && d.table !== "gpt") return "Nothing on it to name";
  if (action === "mount" && !p.fstype) return "No filesystem to mount";
  if (action !== "mount" && d.readOnly) return "The drive is write-protected";
  return "";
}

// ── PARTITIONING ─────────────────────────────────────────────────────────
// Everything on whole MiB: where a partition starts and how long it is. A
// table's own room is kept clear — the first MiB, and GPT's backup at the
// end.
var MIB = 1048576;
function mibUp(n) { return Math.ceil(n / MIB) * MIB; }
function mibDown(n) { return Math.floor(n / MIB) * MIB; }

// the free stretches a partition can go in: [{ offset, size }], each at
// least a MiB; a blank drive (no table yet) is all one
function freeSpaces(d) {
  if (!d || !(d.size > 0)) return [];
  var end = mibDown(d.size - (d.table === "dos" ? 0 : MIB));
  var ps = (d.parts || []).slice().sort(function (a, b) { return a.offset - b.offset; });
  var out = [], at = MIB;
  var gap = function (to) {
    var a = mibUp(at), b = mibDown(Math.min(to, end));
    if (b - a >= MIB) out.push({ offset: a, size: b - a });
  };
  ps.forEach(function (p) { gap(p.offset); at = Math.max(at, p.offset + p.size); });
  gap(end);
  return out;
}

// how far a partition may be resized: { min, max, why } in bytes. The
// room after it up to the next one; down to what it holds and a margin
// when its filesystem can shrink and that is known (mounted). `can` is
// forge's `resizable` for its filesystem, null for none.
function resizeRange(d, p, can) {
  if (!d || !p) return { min: 0, max: 0, why: "" };
  var ps = (d.parts || []).slice().sort(function (a, b) { return a.offset - b.offset; });
  var next = ps.filter(function (q) { return q.offset > p.offset; })[0];
  var end = next ? next.offset : mibDown(d.size - (d.table === "dos" ? 0 : MIB));
  var size = p.size;
  var max = mibDown(end - p.offset);
  var grow = !p.fstype || (can && can.grow);
  var shrink = !p.fstype || (can && can.shrink);
  if (p.encrypted) return { min: size, max: size, why: "An encrypted volume is not resized from here yet" };
  if (!grow) max = size;
  var min = size, why = "";
  if (shrink) {
    if (!p.fstype) min = MIB;
    else if (p.used >= 0) min = Math.min(size, mibUp(p.used * 1.1 + 64 * MIB));
    else why = "Mount it, so what it holds is known, to make it smaller";
  } else if (p.fstype) why = p.fstype + " cannot be made smaller";
  if (!grow && p.fstype) why = shrink ? (why || p.fstype + " cannot be made larger") : p.fstype + " cannot be resized";
  return { min: Math.min(min, size), max: Math.max(max, size), why: why };
}

// why a new partition cannot go here, "" when it can: an MBR table holds
// four
function createWhy(d) {
  if (!d) return "Pick a drive";
  if (d.table === "dos" && (d.parts || []).length >= 4) return "An MBR table holds four partitions — erase it as GPT for more";
  return "";
}

// the type a new partition is given, by its filesystem and the table
// (terminus' partType, in udisks' spelling)
function newType(fs, table) {
  var win = fs === "ntfs" || fs === "vfat" || fs === "exfat";
  if (table === "dos") return fs === "vfat" ? "0x0c" : win ? "0x07" : "0x83";
  return win ? "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7" : "0FC63DAF-8483-4772-8E79-3D69D8477DE4";
}

// ── KEPT BETWEEN OPENINGS ────────────────────────────────────────────────
function defaults() { return { sidebar: true }; }
function parseSettings(text) {
  var d = defaults(), j;
  try { j = JSON.parse(String(text || "")); } catch (e) { return d; }
  if (!j || typeof j !== "object") return d;
  if (typeof j.sidebar === "boolean") d.sidebar = j.sidebar;
  return d;
}
function serializeSettings(s) { return JSON.stringify(parseSettings(JSON.stringify(s)), null, 2) + "\n"; }

// ── CAN IT GO THERE ──────────────────────────────────────────────────────
// { ok, why } for an image and one drive: the first thing in the way
function fits(p, d) {
  if (!p || !d) return { ok: false, why: "" };
  if (d.readOnly) return { ok: false, why: "Read-only — is its lock switch on?" };
  var n = needs(p);
  if (n > 0 && d.size > 0 && n > d.size)
    return { ok: false, why: "Too small — " + (p.kind === "drive" ? p.label + " is " : "the image needs ") + Terminus.formatSize(n) };
  return { ok: true, why: "" };
}

// what holds the Write button back, "" when nothing does
function blocker(p, drives, busy) {
  if (busy) return "busy";
  if (!p) return "Choose an image";
  if (!drives || drives.length === 0) return "Choose a drive";
  // a Windows installer is made, not copied: one drive at a time
  if (p.kind === "windows" && drives.length > 1) return "A Windows installer goes onto one drive at a time";
  for (var i = 0; i < drives.length; i++) {
    var f = fits(p, drives[i]);
    if (!f.ok) return driveTitle(drives[i]) + ": " + f.why;
  }
  return "";
}

// the write sheet's question, in a red-ringed box at its foot (user,
// 2026-10-24: one plain sentence, not a list of what goes)
function eraseNotice(n) {
  return n > 1 ? "This action will erase " + n + " drives" : "This action will erase the drive";
}

// what to know about the image before it is written, "" for nothing
function writeWarning(p, sumsBad, sigBad) {
  if (sigBad) return "The signature does not match — this may not be what its makers released";
  if (sumsBad) return "The checksum does not match — the download may be damaged";
  if (p && p.kind === "iso") return "This ISO is not made to start from a USB drive; it may not boot";
  return "";
}

// ── THE WRITE, AS IT GOES ────────────────────────────────────────────────
// forge.py's lines, one JSON object each; null for anything else
function parseEvent(line) {
  var s = String(line || "").trim();
  if (s === "" || s.charAt(0) !== "{") return null;
  try {
    var e = JSON.parse(s);
    return e && typeof e.ev === "string" ? e : null;
  } catch (err) {
    return null;
  }
}

var PHASE_WORDS = {
  unmount: "Unmounting",
  open: "Waiting for permission",
  write: "Writing",
  sync: "Finishing writing",
  verify: "Checking",
  scan: "Reading every sector",
  prepare: "Preparing the drive",
  copy: "Copying the installer",
  split: "Splitting install.wim",
  download: "Downloading",
  bench: "Measuring",
  backup: "Backing up",
  hash: "Checking the download"
};

// the phases that say how far they are
var PROGRESS_PHASES = { write: 1, verify: 1, scan: 1, backup: 1, copy: 1, split: 1, download: 1, bench: 1 };

function phaseWords(phase) {
  return PHASE_WORDS[phase] || "Starting";
}

function rateWords(rate) {
  var r = Number(rate) || 0;
  return r > 0 ? Terminus.formatSize(r) + "/s" : "";
}

// "about 3 min left", "less than a minute left", "" until it can tell
function etaWords(frac, elapsedMs) {
  var f = Number(frac) || 0;
  var t = Number(elapsedMs) || 0;
  // the first few percent are the drive's cache filling, not its speed
  if (f < 0.03 || t < 3000) return "";
  var left = t * (1 - f) / f / 1000;
  if (left < 60) return "less than a minute left";
  var m = Math.round(left / 60);
  if (m < 60) return "about " + m + " min left";
  var h = Math.floor(m / 60);
  return "about " + h + " h " + (m % 60) + " min left";
}

// the line under a drive while it is being written
function progressLine(job) {
  if (!job) return "";
  var bits = [phaseWords(job.phase)];
  if (PROGRESS_PHASES[job.phase]) {
    bits[0] += " " + Math.floor((job.frac || 0) * 100) + "%";
    var r = rateWords(job.rate);
    if (r) bits.push(r);
    var eta = etaWords(job.frac, job.phaseMs);
    if (eta) bits.push(eta);
  }
  return bits.join("  ·  ");
}

// the fill: how far through the phase the line names (writing, then
// checking runs the band again)
function phaseFrac(job) {
  if (!job) return 0;
  if (job.result) return 1;
  if (PROGRESS_PHASES[job.phase]) return Number(job.frac) || 0;
  return job.phase === "sync" ? 1 : 0;
}

// ── BACK UP, CLONE ───────────────────────────────────────────────────────
// a drive as a write's source (a clone): what probe() says of a file
function driveSource(d) {
  return d ? { path: d.dev, size: d.size, rawSize: d.size, compressed: "", kind: "drive",
               label: driveTitle(d), table: d.table || "", windows: null, sums: null } : null;
}

// the name a backup is offered under: "SanDisk Ultra 2026-10-24.img.zst",
// "home 2026-10-24.img" — no slashes, nothing a filesystem minds
function backupName(d, p, compress, date) {
  var who = p ? partName(p) : driveTitle(d);
  who = String(who).replace(/^\/+/, "").replace(/[\/\\:*?"<>|]+/g, "-").trim() || "backup";
  var day = date || new Date();
  var two = function (n) { return (n < 10 ? "0" : "") + n; };
  return who + " " + day.getFullYear() + "-" + two(day.getMonth() + 1) + "-" + two(day.getDate()) + (compress ? ".img.zst" : ".img");
}

// the backup sheet's line: how far, how it went
function backupWords(job) {
  if (!job) return "";
  if (!job.result) return progressLine(job);
  var r = job.result;
  if (r.ok) return "Saved \u2014 " + Terminus.formatSize(r.written) + " on disk, from " + Terminus.formatSize(r.read);
  return r.why || "Not saved";
}

// ── BENCHMARK ────────────────────────────────────────────────────────────
// forge bench's answer as bars: each point's height against the fastest
function benchBars(r) {
  var rates = (r && r.rates) || [];
  var top = rates.reduce(function (m, x) { return Math.max(m, x.rate); }, 0);
  return rates.map(function (x) { return { at: x.at, frac: top > 0 ? x.rate / top : 0, rate: x.rate }; });
}
// "Reads at 1.9 GiB/s on average, between 1.7 GiB/s and 2.1 GiB/s across it"
function benchWords(r) {
  if (!r || !r.ok) return "";
  var line = "Reads at " + rateWords(r.avg) + " on average";
  if (r.max > r.min * 1.15) line += ", between " + rateWords(r.min) + " and " + rateWords(r.max) + " across it";
  return line;
}
// "0.08 ms to reach any spot", "12.4 ms" (a spinning disk's head moving)
function accessWords(ms) {
  if (!(ms > 0)) return "";
  return (ms < 1 ? ms.toFixed(2) : ms < 10 ? ms.toFixed(1) : String(Math.round(ms))) + " ms to reach a random spot";
}

// ── DISK IMAGES ──────────────────────────────────────────────────────────
// the sizes a new image is offered at, in GiB
var IMAGE_SIZES = [1, 4, 8, 16, 32, 64];

// ── WHO SIGNED IT ────────────────────────────────────────────────────────
// forge sig's answer as the image card's line: { words, level, key } —
// `key` set when the signer's key is not here to check with
function sigWords(sg) {
  if (!sg || !sg.state || sg.state === "none") return { words: "", level: "", key: "" };
  var who = String(sg.signer || "").replace(/\s*<[^>]*>\s*$/, "") || "its key";
  var what = sg.of === "sums" ? " (its checksums)" : "";
  if (sg.state === "good") return { words: "Signed by " + who + what, level: "good", key: "" };
  if (sg.state === "nokey") return { words: "Signed with a key not on this machine", level: "", key: sg.key || "" };
  if (sg.state === "expired") return { words: "Signed by " + who + ", with a key that has expired", level: "warn", key: "" };
  if (sg.state === "revoked") return { words: "Signed by " + who + ", with a key since revoked", level: "bad", key: "" };
  return { words: "The signature does not match", level: "bad", key: "" };
}

// the surface scan's line for a drive: how far, how it went, or what it is
// { words, level: good|bad|"" }
function scanWords(job, d) {
  if (!job || !d || !job.drive || job.drive.block !== d.block)
    return { words: "Not run \u2014 reads every sector once, writes nothing", level: "" };
  if (!job.result) return { words: progressLine(job), level: "" };
  var r = job.result;
  if (r.ok) return { words: "Every sector reads", level: "good" };
  return { words: r.why || "The scan stopped", level: r.code === "cancelled" ? "" : "bad" };
}

// a running job (a write, a surface scan) moved on by one of forge's lines:
// a new object, with how long its phase has run (`at` is when it began)
function advance(job, e, now) {
  var j = {};
  for (var k in job) j[k] = job[k];
  if (e.ev === "phase") { j.phase = e.phase; j.frac = 0; j.rate = 0; j.at = now; }
  else if (e.ev === "progress") { j.frac = e.frac; j.rate = e.rate; }
  else if (e.ev === "done") j.result = e;
  j.phaseMs = now - (j.at || now);
  return j;
}

// what the head says under the name: the drives, the write as it goes, or
// how it went ("1 of 2 written" when only some were)
function headWords(job, drives) {
  if (!job) {
    var n = (drives || []).length;
    return n === 0 ? "Plug in a drive" : n === 1 ? "1 drive" : n + " drives";
  }
  if (!job.result) return progressLine(job);
  var r = job.result;
  if (r.ok) return "Done";
  var ts = r.targets || [];
  var good = ts.filter(function (t) { return t.ok; }).length;
  return good > 0 ? good + " of " + ts.length + " written" : (r.why || "Not written");
}

// what one drive's outcome says: { ok, words }
function resultOf(done, dev) {
  if (!done) return null;
  var ts = done.targets || [];
  var t = null;
  for (var i = 0; i < ts.length; i++) if (ts[i].dev === dev || ts[i].target === dev) t = ts[i];
  if (!t) return { ok: !!done.ok, words: done.ok ? "Written" : (done.why || "Not written") };
  if (!t.ok) return { ok: false, words: t.why || "Not written" };
  return { ok: true, words: done.verified ? "Written and checked" : "Written" };
}

// howler's toast at the end, for a window that was shut while it ran
function toastOf(done, names) {
  if (!done) return null;
  var who = names.length === 1 ? names[0] : names.length + " drives";
  if (done.ok) return { title: "Written", body: who + (done.verified ? " — written and checked" : " — written") };
  if (done.code === "cancelled") return { title: "Stopped", body: who + " is half written" };
  return { title: "Not written", body: who + ": " + (done.why || "the write failed") };
}

// the sums chip on the image: { state: ok|bad|running|none, words }
function sumsOf(probe, check) {
  if (check && check.running) return { state: "running", words: "Checking " + ((probe && probe.sums && probe.sums.algo) || "sha256") + "…" };
  if (check && check.done) {
    var d = check.done;
    if (!d.checked) return { state: "none", words: "No checksum beside it" };
    return d.ok ? { state: "ok", words: d.algo + " matches" } : { state: "bad", words: d.algo + " does not match" };
  }
  if (probe && !probe.sums) return { state: "none", words: "No checksum beside it" };
  return { state: "none", words: "" };
}
