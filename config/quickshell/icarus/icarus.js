// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

function dirname(p) {
  if (!p || p === "/") return "/";
  const s = String(p).replace(/\/+$/, "");
  const idx = s.lastIndexOf("/");
  if (idx <= 0) return "/";
  return s.slice(0, idx);
}

function isHidden(name) {
  return name.length > 0 && name[0] === ".";
}

// ── READING A DIRECTORY FOR THE HOME CARDS ───────────────────────────────────
// find, as terminus reads one, and for the reason terminus gives: `ls -A1p`
// said "directory" with a trailing slash and nothing else, and that slash is
// only written for a REAL directory. A link to a directory came back as a bare
// name, so the menu drew it as a file and a click handed it to `gio open`
// instead of walking into it. %Y is the type after following the link — the
// question this menu is actually asking.
//
// The same two separators terminus uses, for the same reason: a name may
// legally hold a newline or a tab, and neither is a safe place to split.
const FIELD = "\u001f";
const RECORD = "\u001e";

// A STATUS RECORD LEADS, because an empty listing had three meanings — an
// empty directory, one you may not read, one that is not there — and all three
// drew as the same blank card. The shell knows which it is before find runs.
//
// The trailing slash makes find follow the directory itself when it is a link;
// see terminus' listPath.
function listPath(dir) {
  const d = String(dir);
  return d === "" || d.charAt(d.length - 1) === "/" ? d : d + "/";
}

function listCommand(dir) {
  return "d=" + Strings.shellQuote(listPath(dir)) + "; "
    + "if [ ! -e \"$d\" ]; then printf 'missing\\036'; "
    + "elif [ ! -r \"$d\" ] || [ ! -x \"$d\" ]; then printf 'denied\\036'; "
    + "else printf 'ok\\036'; find \"$d\" -mindepth 1 -maxdepth 1 "
    + "-printf '%y\\037%Y\\037%m\\037%s\\037%f\\036' 2>/dev/null; fi";
}

function joinPath(dir, name) {
  const d = String(dir);
  return d.endsWith("/") ? d + name : d + "/" + name;
}

// { state, rows } — state is "ok", "denied" or "missing". Output with no
// status at all (a killed run) reads as "ok" and empty, which is what it
// would have drawn anyway.
function parseListing(text, dir) {
  const recs = String(text || "").split(RECORD);
  let state = "ok";
  let from = 0;
  if (recs.length > 0 && /^(ok|denied|missing)$/.test(recs[0])) {
    state = recs[0];
    from = 1;
  }
  const rows = [];
  for (let i = from; i < recs.length; ++i) {
    if (recs[i] === "") continue;
    const f = recs[i].split(FIELD);
    if (f.length < 5) continue;
    // a name cannot hold the separator, but a stray one would shift the
    // fields; the name is everything after the fourth
    const name = f.slice(4).join(FIELD);
    if (name === "" || name === "." || name === "..") continue;
    const mode = parseInt(f[2], 8) || 0;
    rows.push({
      name: name,
      path: joinPath(dir, name),
      isDir: f[1] === "d",
      isLink: f[0] === "l",
      broken: f[1] === "N",
      isExec: f[1] !== "d" && (mode & 73) !== 0,
      isHidden: isHidden(name),
      size: parseInt(f[3], 10) || 0
    });
  }
  return { state: state, rows: rows };
}

// ── THE ORDER ─────────────────────────────────────────────────────────────
// Directories first, then by name, case-insensitively and with numbers read as
// numbers — "photo 9" before "photo 10". Hidden entries go to the END of their
// group rather than the start: a dot sorts before every letter, so with them
// shown, twenty-four dotfiles stood between you and Documents.
function sortEntries(a, b) {
  if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
  if (a.isHidden !== b.isHidden) return a.isHidden ? 1 : -1;
  const an = String(a.name).replace(/^\./, "");
  const bn = String(b.name).replace(/^\./, "");
  const c = an.localeCompare(bn, undefined, { sensitivity: "base", numeric: true });
  if (c !== 0) return c;
  return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
}

// What a card shows of a listing: hidden entries only when asked for, sorted,
// and no more than `cap` of them. `more` is how many were left out, for the
// row that offers the rest in terminus. A card of thousands of rows — /usr/bin
// — was thousands of delegates built before the menu could draw.
function visibleRows(rows, showHidden, cap) {
  const kept = (rows || []).filter((r) => showHidden || !r.isHidden);
  kept.sort(sortEntries);
  const n = cap > 0 ? Math.min(cap, kept.length) : kept.length;
  return { rows: kept.slice(0, n), more: kept.length - n };
}

// ── WHAT A DIRECTORY HOLDS, FOR THE NUMBER ON ITS ROW ────────────────────────
// One find over every directory in the card rather than one process per directory:
// %H is the starting point a line was found under, so `uniq -c` over it is a
// count per directory. Each directory goes in with a trailing slash, for a link to
// one; the answer comes back keyed by the path as it went in, slash removed.
//
// The paths are ARGUMENTS, not script text — the same limit terminus' withArgs
// explains: a card of hundreds of directories spliced into one argument is how an
// execve fails silently.
function countArgv(dirs, showHidden) {
  const hide = showHidden ? "" : " ! -name '.*'";
  return ["sh", "-c",
    "find \"$@\" -mindepth 1 -maxdepth 1" + hide
      + " -printf '%H\\n' 2>/dev/null | sort | uniq -c",
    "icarus"].concat((dirs || []).map(listPath));
}

// Every directory that was asked about gets an answer; one with nothing in it
// prints no line at all, and that is a count of 0, not an unknown.
function parseCounts(text, dirs) {
  const out = {};
  for (const d of dirs || []) out[String(d).replace(/\/+$/, "") || "/"] = 0;
  for (const line of String(text || "").split("\n")) {
    const m = /^\s*(\d+) (.*)$/.exec(line);
    if (!m) continue;
    const key = m[2].replace(/\/+$/, "") || "/";
    out[key] = parseInt(m[1], 10);
  }
  return out;
}

// Short, because it sits in the margin of a 300px card: "4.2M", not
// "4.2 MiB". Binary units, as everything else on this machine reports.
function shortSize(n) {
  let v = Number(n) || 0;
  const units = ["B", "K", "M", "G", "T"];
  let i = 0;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; ++i; }
  if (i === 0) return v + "B";
  return (v < 10 ? v.toFixed(1) : Math.round(v)) + units[i];
}

// ── PLACES ────────────────────────────────────────────────────────────────
// Home, the XDG directories and terminus' own bookmarks — the list terminus'
// sidebar is built from, so a place pinned there is pinned here. Nothing
// written here is a second list to keep.
//
// Anything already on screen below them is dropped: a place that IS the directory
// you are in, or sits directly inside it, is a row of the listing a few lines
// further down, and drawing it twice is noise. At home that leaves only the
// bookmarks from elsewhere, which is the point: places are for getting AWAY.
function places(home, userDirs, bookmarks, cwd) {
  const seen = {};
  const out = [];
  const here = String(cwd || "").replace(/\/+$/, "") || "/";
  const add = (p, label) => {
    const path = String(p || "").replace(/\/+$/, "") || "/";
    if (path === "" || seen[path]) return;
    seen[path] = true;
    if (path === here || dirname(path) === here) return;
    out.push({ path: path, label: label || basename(path) });
  };
  add(home, "Home");
  for (const d of userDirs || []) add(d);
  for (const b of bookmarks || []) add(b);
  return out;
}

function basename(p) {
  const s = String(p).replace(/\/+$/, "");
  if (s === "") return "/";
  const cut = s.lastIndexOf("/");
  return cut >= 0 ? s.slice(cut + 1) : s;
}

// Which of a list of paths are directories that exist, asked in one process. A
// bookmark to an unplugged drive is a place that goes nowhere.
function existingDirsArgv(paths) {
  return ["sh", "-c", "for p; do [ -d \"$p\" ] && printf '%s\\036' \"$p\"; done; true",
    "icarus"].concat(paths || []);
}

function parseExisting(text) {
  return String(text || "").split(RECORD).filter((p) => p !== "");
}

// ── THE CRUMBS THAT FIT ───────────────────────────────────────────────────
// The header of the base card is the path you are in, and a path is longer
// than 300px sooner than you would think. The END of it is what matters —
// the directory you are in and the one above it — so crumbs are dropped from the
// front, and a leading "…" stands for them and leads to the deepest one
// dropped. `widthOf` measures a label; `sepW` is the separator between two.
function fitCrumbs(crumbs, avail, widthOf, sepW) {
  const all = crumbs || [];
  if (all.length === 0) return [];
  let used = widthOf(all[all.length - 1].label);
  let first = all.length - 1;
  const ell = widthOf("…") + sepW;
  while (first > 0) {
    const w = widthOf(all[first - 1].label) + sepW;
    // room for this one, and for the "…" if anything is still left over
    const needEll = first - 1 > 0 ? ell : 0;
    if (used + w + needEll > avail) break;
    used += w;
    first--;
  }
  const shown = all.slice(first);
  if (first > 0)
    return [{ label: "…", path: all[first - 1].path, elided: true }].concat(shown);
  return shown;
}

// ── TYPING A NAME TO JUMP TO IT ───────────────────────────────────────────
// The first row, starting AT the current one, whose name begins with what has
// been typed — so typing the same letter again walks through every match, as
// every file manager does. -1 when nothing matches. `names` holds null for the
// rows that cannot be selected.
function typeAhead(names, typed, from) {
  const q = String(typed || "").toLowerCase();
  const n = (names || []).length;
  if (q === "" || n === 0) return -1;
  // a single repeated letter cycles: start one past the current row
  const cycling = q.length > 1 && q.split("").every((c) => c === q[0]);
  const needle = cycling ? q[0] : q;
  // with nothing selected yet, the first row is as good a start as any
  const start = from < 0 ? 0 : from + (cycling || q.length === 1 ? 1 : 0);
  for (let k = 0; k < n; ++k) {
    const i = (start + k) % n;
    const nm = names[i];
    if (nm !== null && nm !== undefined && String(nm).toLowerCase().indexOf(needle) === 0)
      return i;
  }
  return -1;
}

// ── WHERE A CASCADED CARD GOES ────────────────────────────────────────────
// Beside its parent, on the SAME side the cascade has been going. Zenon.hingeX
// picks right whenever it fits, so a stack that had to turn left at the screen
// edge came straight back on the next level, over the card it came from.
function cascadeX(parentLeft, parentW, w, screenW, gap, goingLeft) {
  const right = parentLeft + parentW;
  const left = parentLeft - w;
  const fitsRight = right + w <= screenW - gap;
  const fitsLeft = left >= gap;
  if (goingLeft && fitsLeft) return left;
  if (fitsRight) return right;
  if (fitsLeft) return left;
  return Math.max(gap, Math.min(right, screenW - w - gap));
}

// Whether to start the Home cards where they were left: within `minutes` of
// closing, and never if they were never closed. 0 minutes means always home.
function keepFolder(closedAt, now, minutes) {
  if (!(minutes > 0) || !(closedAt > 0)) return false;
  return now - closedAt <= minutes * 60000;
}

// Files are opened by terminus.js' openOrAskCommand — see IcarusPopup's
// openFile — so there is no opener of icarus' own here any more.


// ── THE APPS SUBMENU'S ROWS ───────────────────────────────────────────────
// DesktopEntries hands the applications over in whatever order it found their
// .desktop files, which is no order anyone can scan. Alphabetical, ignoring
// case — "firefox" and "Firefox" are not two places in the list — and one row
// per name, as cynosure lists them, since an application installed twice
// (flatpak beside the package) is still one thing you meant to open.
//
// `glyphOf` is morpheus' appGlyph, handed in rather than imported so this
// file stays loadable on its own; the same map cynosure and artemis read.
function appRows(entries, glyphOf) {
  const seen = {};
  const out = [];
  for (const e of entries || []) {
    if (!e || e.noDisplay) continue;
    const name = String(e.name || "").trim();
    if (name === "") continue;
    const key = name.toLowerCase();
    if (seen[key]) continue;
    seen[key] = true;
    out.push({ entry: e, name: name,
               glyph: glyphOf ? glyphOf([e.id, e.execString, name]) : "" });
  }
  out.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: "base" }));
  return out;
}
