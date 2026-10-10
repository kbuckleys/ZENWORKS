// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

// The shared pollers. One directory at the shell root rather than inside
// morpheus, because zeus reads the same ones the bar does and a script the
// process monitor depends on has no business living in the status bar's directory.
//
// Quickshell.shellDir is the directory the loaded shell file came from, so this
// no longer hand-rolls the XDG lookup — and it is right whatever path the
// config was launched from.
.pragma library
.import Quickshell as QuickshellModule
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file evaluated all of it again (qmlprofiler, 2026-10-09;
// see morpheus/icons.js and terminus/terminus.js for what that cost).
// The shell's singletons come in through the imports above (the same
// instances); the node tests hand in stubs of their own.
var Quickshell = typeof QuickshellModule !== "undefined" ? QuickshellModule.Quickshell : globalThis.Quickshell;

function script(name) {
  return Quickshell.shellDir + "/scripts/" + name;
}

function collapse(s) {
  return (s ?? "").replace(/ {2,}/g, " ");
}

function pangoToStyled(s) {
  if (!s) return "";
  return s
    .replace(/<span\b[^>]*\bforeground=(["'])([^"']+)\1[^>]*>/g, '<font color="$2">')
    .replace(/<span\b[^>]*>/g, "")
    .replace(/<\/span\s*>/g, "</font>");
}

function apply(s) {
  return collapse(pangoToStyled(s));
}

function tooltip(s) {
  return (s ?? "")
    .replace(/<span\b[^>]*\bforeground=(["'])([^"']+)\1[^>]*>/g, '<font color="$2">')
    .replace(/<span\b[^>]*>/g, "")
    .replace(/<\/span\s*>/g, "</font>")
    .replace(/\n/g, "<br/>");
}

function pad(n) {
  n = Math.trunc(n);
  return n < 10 ? "0" + n : String(n);
}

// The unlit face behind a seven-segment reading. DSEG only ghosts if you draw
// every segment lit behind the live digits, so the ghost has to be the same
// SHAPE as what sits on top of it or the two will not register. Lives here
// rather than in chronos: the clock, the countdowns, the forecast and zeus'
// graphs all draw the same way, and that is one rule, not four.
function ghostText(s) {
  return String(s ?? "").replace(/\d/g, "8");
}

// "2.1MB/s" -> { num: "2.1", unit: "MB/s" }. A throughput reading is a number
// in the segment face with its unit beside it in the text face, so the two have
// to come apart — DSEG has no letters worth looking at.
function splitRate(s) {
  const m = String(s ?? "").match(/^([\d.]+)(.*)$/);
  return m ? { num: m[1], unit: m[2] } : { num: String(s ?? ""), unit: "" };
}

function powFormat(val) {
  return sizeFormat(val) + "/s";
}

// A byte count in the same units the rates are read in, so "4.2GB" beside
// "1.3MB/s" is one scale and not two.
function sizeFormat(val) {
  const units = ["", "k", "M", "G", "T", "P"];
  let fraction = Math.max(0, val);
  let pow = 0;
  while (pow + 1 < units.length && fraction / 1000 >= 1) {
    fraction /= 1000;
    ++pow;
  }
  return fraction.toFixed(1) + units[pow] + "B";
}

// The mounted filesystems as Sysmon's df pass prints them, one tab-separated
// line each: source, type, size, used, avail, percent, the kernel's name for
// the block device behind it, and the mount point last (so a space in it
// survives). One entry per SOURCE: btrfs mounts the same partition as a dozen
// subvolumes, and listing it a dozen times would say there are a dozen disks.
// The shortest mount point stands for the rest — "/" over "/var/log".
function parseMounts(text) {
  const bySource = ({});
  const order = [];
  for (const line of String(text ?? "").split("\n")) {
    const f = line.split("\t");
    if (f.length < 8 || f[0] === "") continue;
    const d = { source: f[0], fstype: f[1],
                size: Number(f[2]) || 0, used: Number(f[3]) || 0,
                avail: Number(f[4]) || 0, pct: parseInt(f[5], 10) || 0,
                dev: f[6], target: f.slice(7).join("\t") };
    if (d.size <= 0) continue;
    const had = bySource[d.source];
    if (!had) { bySource[d.source] = d; order.push(d.source); }
    else if (d.target.length < had.target.length) bySource[d.source] = d;
  }
  return order.map((k) => bySource[k]);
}

function giB(kb) {
  return Math.round(kb / 10485.76) / 100;
}

function format1f(v) {
  return v.toFixed(1);
}

