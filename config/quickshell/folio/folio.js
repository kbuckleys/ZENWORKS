// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

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

function highlightedPreview(text, query) {
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
    out.push("<span style=\"color:#eebebe;font-weight:700;\">" + Strings.escapeHtml(text.slice(idx, idx + q.length)) + "</span>");
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

// PAIRS, NOT MARKUP. It used to hand back finished rich text with the colours
// written into it as hex — which meant the palette lived in two places, and a
// hint could only ever be drawn one way. The popup draws these as chips now;
// what belongs here is which key and what it does.
function hintText(mode) {
  const tab = ["tab", "toggle mode"];
  const del = ["delete", "remove entry"];
  const open = ["shift return", "annotate"];
  if (mode === "image") return [tab, open, del];
  return [tab, del];
}
