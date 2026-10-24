// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT IS TAKING UP A VOLUME'S ROOM — the pure half of the colored bar
// (morpheus/py/usage.py answers, terminus/UsageScan asks, UsageBar and
// UsageLegend draw): the kinds in their order and colors, the bar's
// stretches, the legend's words (oracle/tests/usage.js).
//
// Colors are named, not given: Zenon's own names, which the QML side
// looks up, so a theme change recolors the bar.

.pragma library
.import "terminus.js" as Terminus

var KINDS = [
  { id: "system", label: "System", ink: "muted" },
  { id: "apps", label: "Apps", ink: "blue" },
  { id: "documents", label: "Documents", ink: "cyan" },
  { id: "pictures", label: "Pictures", ink: "magenta" },
  { id: "videos", label: "Videos", ink: "pink" },
  { id: "music", label: "Music", ink: "green" },
  { id: "archives", label: "Archives and images", ink: "yellow" },
  { id: "caches", label: "Caches", ink: "sand" },
  { id: "trash", label: "Trash", ink: "red" },
  { id: "other", label: "Other", ink: "accentMuted" }
];

// The bar's stretches, left to right: { id, label, ink, bytes, frac }.
// `df` is { total, used, free }; `cats` the walk's bytes by kind, or null
// before any walk — then the used room is one stretch, "Used". What the
// walk did not find (unreadable, metadata) is Other; a walk that found
// more than is used (shared extents, compression) is scaled down to it.
function stretches(df, cats) {
  if (!df || !(df.total > 0)) return [];
  if (!cats) return df.used > 0 ? [{ id: "used", label: "Used", ink: "cyan", bytes: df.used, frac: df.used / df.total }] : [];
  var known = 0;
  KINDS.forEach(function (k) { known += Number(cats[k.id]) || 0; });
  var scale = known > df.used && known > 0 ? df.used / known : 1;
  var out = [];
  KINDS.forEach(function (k) {
    var b = (Number(cats[k.id]) || 0) * scale;
    if (k.id === "other") b += Math.max(0, df.used - known * scale);
    if (b / df.total >= 0.002) out.push({ id: k.id, label: k.label, ink: k.ink, bytes: b, frac: b / df.total });
  });
  return out;
}

// the legend under it: every stretch, then what is free
function legend(df, cats) {
  if (!df || !(df.total > 0)) return [];
  return stretches(df, cats).map(function (s) {
    return { name: s.label, line: Terminus.formatSize(s.bytes), ink: s.ink };
  }).concat([{ name: "Free", line: Terminus.formatSize(df.free), ink: "" }]);
}

// "12.4 GiB free of 46.0 GiB"
function freeWords(df) {
  if (!df || !(df.total > 0)) return "";
  return Terminus.formatSize(df.free) + " free of " + Terminus.formatSize(df.total);
}

// what the walk is doing, or how old its answer is
function scanWords(state, nowMs) {
  if (!state) return "";
  if (state.scanning) return "Sorting what is where… " + (state.files || 0).toLocaleString() + " files";
  if (!state.at) return "";
  var mins = Math.floor(((nowMs || Date.now()) / 1000 - state.at) / 60);
  if (mins < 1) return "Sorted just now";
  if (mins < 60) return "Sorted " + mins + " min ago";
  var h = Math.floor(mins / 60);
  if (h < 48) return "Sorted " + h + " h ago";
  return "Sorted " + Math.floor(h / 24) + " days ago";
}

// usage.py's lines, one JSON object each; null for anything else
function parseLine(line) {
  var s = String(line || "").trim();
  if (s.charAt(0) !== "{") return null;
  try {
    var e = JSON.parse(s);
    return e && typeof e.ev === "string" ? e : null;
  } catch (err) {
    return null;
  }
}
