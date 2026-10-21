// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

.pragma library
.import qs.morpheus as Morpheus
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file evaluated all of it again (see morpheus/icons.js).
// The shell's singletons come in through the imports above (the same
// instances); the node tests hand in stubs of their own.
var Paths = typeof Morpheus !== "undefined" ? Morpheus.Paths : globalThis.Paths;
var Strings = typeof Morpheus !== "undefined" ? Morpheus.Strings : globalThis.Strings;

function thumbDir() {
  return Paths.cacheDir() + "/cliphist";
}

// Where a clipboard image is decoded to be opened or dragged. The RUNTIME
// directory, not /tmp: a predictable name in a shared, sticky /tmp could be
// made first by another user — to read the images, or as a symlink for the
// `>` redirect to write through.
function openDir() {
  return Paths.runtimeDir() + "/cliphist-open";
}

const THUMB = 256;

// `ink`: the match's color, a 6-digit hex (Zenon.hex) — the theme's, so
// it follows a theme change
function highlightedPreview(text, query, ink) {
  const q = (query || "").trim().toLowerCase();
  if (!q) return Strings.escapeHtml(text);
  const lower = text.toLowerCase();
  const out = [];
  let i = 0;
  while (i < text.length) {
    const idx = lower.indexOf(q, i);
    if (idx < 0) {
      out.push(Strings.escapeHtml(text.slice(i)));
      break;
    }
    if (idx > i) out.push(Strings.escapeHtml(text.slice(i, idx)));
    out.push("<span style=\"color:" + ink + ";font-weight:700;\">" + Strings.escapeHtml(text.slice(idx, idx + q.length)) + "</span>");
    i = idx + q.length;
  }
  return out.join("");
}

function cleanText(s) {
  s = String(s || "");
  s = s.replace(/\r/g, "");
  s = s.replace(/\0/g, "");
  s = s.replace(/\u001f/g, "");
  s = s.replace(/\n/g, " \u21b5 ");
  s = s.replace(/\s+/g, " ");
  return s;
}

function preview(s) {
  let p = cleanText(s);
  if (p === "") p = "(empty)";
  return p;
}

function parseList(text) {
  const entries = [];
  const imageIds = [];
  if (!text) return { entries: entries, imageIds: imageIds };
  for (const line of text.split("\n")) {
    if (line.trim() === "") continue;
    const m = line.match(/^(\d+)\t(.*)$/);
    if (!m) continue;
    const id = m[1];
    const content = m[2];
    if (content.startsWith("[[ binary")) {
      imageIds.push(id);
    } else {
      entries.push({ id: id, content: content, preview: preview(content) });
    }
  }
  return { entries: entries, imageIds: imageIds };
}

function filterEntries(entries, query) {
  const q = (query || "").trim().toLowerCase();
  if (q === "") return entries.slice();
  const out = [];
  for (const e of entries) {
    if ((e.content + " " + e.preview).toLowerCase().includes(q)) out.push(e);
  }
  return out;
}

function thumbCommand(ids, dir) {
  if (!ids || ids.length === 0) return null;
  const quoted = ids.map((i) => Strings.shellQuote(i)).join(" ");
  // The directory reaches the inner script as $1, not spliced into its
  // single-quoted text, where a quote in $XDG_CACHE_HOME would end it.
  return "mkdir -p " + Strings.shellQuote(dir) + "; printf '%s\\n' " + quoted +
      " | xargs -P 8 -I{} sh -c '[ -f \"$1/{}.png\" ] || { printf \"%s\" \"{}\" | cliphist decode | " +
      "magick - -thumbnail " + THUMB + "x" + THUMB + " -background none -gravity center -extent " +
      THUMB + "x" + THUMB + " \"$1/{}.png\" >/dev/null 2>&1; }' folio-thumb " + Strings.shellQuote(dir);
}

function copyCommand(id) {
  return "printf '%s' " + Strings.shellQuote(id) + " | cliphist decode | wl-copy";
}

function deleteCommand(id, dir) {
  return "printf '%s' " + Strings.shellQuote(id) + " | cliphist delete; rm -f " +
      Strings.shellQuote(dir + "/" + id + ".png");
}

// The preview is rich text — it is drawn with Text.RichText so a match can be
// marked — and a drag card is a plain label. Tags stripped and entities put
// back, then trimmed to something that reads at a glance beside a moving
// cursor rather than a paragraph trailing off the screen.
function plain(s) {
  var t = String(s || "").replace(/<[^>]*>/g, "");
  t = t.replace(/&lt;/g, "<").replace(/&gt;/g, ">")
       .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
       .replace(/&amp;/g, "&");
  t = t.replace(/\s+/g, " ").trim();
  return t.length > 48 ? t.slice(0, 47) + "\u2026" : t;
}

// The file's own name, for the same card.
function baseName(p) {
  var s = String(p || "");
  var cut = s.lastIndexOf("/");
  return cut < 0 ? s : s.slice(cut + 1);
}

// THE FULL IMAGE, WRITTEN OUT SO IT CAN BE DRAGGED SOMEWHERE.
//
// The grid draws thumbnails — small PNGs this module renders for itself — and
// handing one of those to another application would be giving it a downscaled
// copy of what it asked for. cliphist still holds the original, so a drag
// decodes the original, and prints where it landed. Shift+return uses the
// same file to hand the image to the annotator.
//
// A half-hour sweep of the same directory on every write: a dragged image
// is a file somebody else now owns a copy of, and leaving ours behind forever
// would make a cache out of every drag.
function dragFileCommand(id, dir) {
  const file = dir + "/" + id + ".png";
  return "mkdir -p -m 700 " + Strings.shellQuote(dir) + "; find " + Strings.shellQuote(dir) +
      " -type f -name '*.png' -mmin +30 -delete 2>/dev/null; printf '%s' " +
      Strings.shellQuote(id) + " | cliphist decode > " + Strings.shellQuote(file) +
      "; [ -s " + Strings.shellQuote(file) + " ] && printf '%s' " +
      Strings.shellQuote(file);
}

// ── WHEN EACH ENTRY ARRIVED ─────────────────────────────────────────────
// cliphist keeps no time at all: its database is id → bytes and nothing
// else. So folio keeps its own ledger beside it, id → milliseconds, filled
// in by watching the database for the one CLOSE_WRITE each `cliphist store`
// makes (a list or a decode makes none, so reading it back cannot loop).
//
// An id the ledger has never seen gets `now` when the scan was set off by a
// store, and 0 — "no time known" — when it was the scan the shell does on
// starting, because those arrived while nobody was watching and stamping
// them with the start time would be a confident lie. The very first run has
// no ledger, so everything already there is 0 the same way.
//
// `carry` is a re-copy from folio itself: cliphist dedupes by deleting the
// old entry and storing it again under a new id, and the moment it was
// first taken belongs to the new id rather than being reset to now.
function ledgerPath() {
  return thumbDir() + "/folio-ledger.json";
}

function parseLedger(text) {
  try {
    const o = JSON.parse(text || "");
    return o && typeof o === "object" ? o : null;
  } catch (e) {
    return null;
  }
}

function listIds(text) {
  const ids = [];
  for (const line of String(text || "").split("\n")) {
    const m = line.match(/^(\d+)\t/);
    if (m) ids.push(m[1]);
  }
  return ids;
}

// ids are newest first, as cliphist lists them. Returns the new ledger, or
// null when nothing changed and there is nothing to write.
function reconcile(ledger, ids, live, now, carry) {
  const out = {};
  let changed = false;
  let carried = false;
  for (const id of ids) {
    if (ledger[id] !== undefined) { out[id] = ledger[id]; continue; }
    changed = true;
    if (!live) { out[id] = 0; continue; }
    // only the newest unseen id can be the re-copy
    if (carry !== null && carry !== undefined && !carried) { out[id] = carry; carried = true; }
    else out[id] = now;
  }
  for (const id in ledger) if (out[id] === undefined) { changed = true; break; }
  return changed ? out : null;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// "Today · 14:32", "Yesterday · 9:05 PM", "Oct 3 · 14:32", and the year only
// when it is not this one. Both halves always: what this row is for is when
// you copied it, and "3d ago" answers only half of that.
function stampLabel(ms, now, h24) {
  if (!ms) return "Time unknown";
  const d = new Date(ms);
  const n = new Date(now);
  const mins = String(d.getMinutes()).padStart(2, "0");
  const time = h24
    ? String(d.getHours()).padStart(2, "0") + ":" + mins
    : ((d.getHours() + 11) % 12 + 1) + ":" + mins + (d.getHours() < 12 ? " AM" : " PM");
  const day0 = new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime();
  const then0 = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const back = Math.round((day0 - then0) / 86400000);
  let day;
  if (back === 0) day = "Today";
  else if (back === 1) day = "Yesterday";
  else {
    day = MONTHS[d.getMonth()] + " " + d.getDate();
    if (d.getFullYear() !== n.getFullYear()) day += " " + d.getFullYear();
  }
  return day + " · " + time;
}

// PAIRS, NOT MARKUP. It used to hand back finished rich text with the colors
// written into it as hex — which meant the palette lived in two places, and a
// hint could only ever be drawn one way. The popup draws these as chips now;
// what belongs here is which key and what it does.
function hintText(mode) {
  const tab = ["tab", "next mode"];
  const del = ["delete", "remove entry"];
  const open = ["shift return", "annotate"];
  if (mode === "image") return [tab, open, del];
  if (mode === "snip") return [tab, ["return", "paste"], ["ctrl n", "new"], ["ctrl e", "edit"], ["delete", "remove"]];
  return [tab, ["ctrl s", "keep as snippet"], del];
}

// ── SNIPPETS (2026-10-21) ────────────────────────────────────────────────
// Text you paste again and again, kept: one plain .txt file each in the
// snippets directory, named by its file name, edited in plato. Folio's third
// mode lists them; return pastes one with its placeholders filled in.
//
//   {date} 2026-10-21   {time} 14:05   {datetime} 2026-10-21 14:05
//   {weekday} Tuesday   {year} {month} {day}   {clipboard} what was copied
//   last — and {{ }} for a literal brace
function snippetDir() {
  return Paths.dataDir() + "/folio/snippets";
}
// the listing command's JSON: [{ name, path, text }]
function parseSnippets(text) {
  let j;
  try { j = JSON.parse(String(text || "")); } catch (e) { return []; }
  if (!Array.isArray(j)) return [];
  return j.filter((s) => s && s.name && s.path).map((s) => ({
    name: String(s.name), path: String(s.path), text: String(s.text || "")
  })).sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
}
// the rows the text pane draws: the name, and the text under it
function snippetRows(snips, query) {
  const q = String(query || "").trim().toLowerCase();
  return (snips || []).filter((s) => q === "" || (s.name + " " + s.text).toLowerCase().includes(q))
    .map((s) => ({ id: "snip:" + s.name, snip: true, path: s.path, content: s.text,
                   preview: s.name, sub: preview(s.text) }));
}
const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
function expandSnippet(text, now, clipboard) {
  const d = now || new Date();
  const two = (n) => (n < 10 ? "0" : "") + n;
  const date = d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate());
  const time = two(d.getHours()) + ":" + two(d.getMinutes());
  const vals = {
    date: date, time: time, datetime: date + " " + time, weekday: WEEKDAYS[d.getDay()],
    year: String(d.getFullYear()), month: two(d.getMonth() + 1), day: two(d.getDate()),
    clipboard: String(clipboard || "")
  };
  return String(text || "")
    .replace(/\{\{/g, "\u0001").replace(/\}\}/g, "\u0002")
    .replace(/\{([a-z]+)\}/g, (m, k) => vals[k] !== undefined ? vals[k] : m)
    .replace(/\u0001/g, "{").replace(/\u0002/g, "}");
}
// a name for a clip kept as a snippet: its first few words, safe as a file
// name, and not one already taken ("…", "… 2", "… 3")
function snippetName(text, taken) {
  let base = cleanText(text).split(/\s+/).filter((w) => w !== "").slice(0, 5).join(" ")
    .replace(/[\/\\:*?"<>|]/g, "").slice(0, 48).trim();
  if (base === "") base = "Snippet";
  const used = {};
  (taken || []).forEach((n) => used[n.toLowerCase()] = true);
  let name = base;
  for (let i = 2; used[name.toLowerCase()] && i < 1000; ++i) name = base + " " + i;
  return name;
}
