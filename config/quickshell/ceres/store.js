// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The pure half of the Store: which apps a section holds, what a search
// finds, how the front page is laid out, and how the keys walk it. The
// catalog itself comes from ceres/bin/ceres-store; nothing here reads a
// file or runs anything, so every rule is pinned in oracle/tests/ceresstore.js.

.pragma library

// ── the sections, in the sidebar's order ───────────────────────────────────
// [key, label, glyph, AppStream main categories]. An app is in every section
// one of its categories names — GIMP is Create, OBS is Listen & Watch.
const SECTIONS = [
  ["discover",  "Discover",       "", []],
  ["create",    "Create",         "", ["Graphics"]],
  ["work",      "Work",           "", ["Office"]],
  ["play",      "Play",           "", ["Game"]],
  ["develop",   "Develop",        "", ["Development"]],
  ["watch",     "Listen & Watch", "", ["AudioVideo", "Audio", "Video"]],
  ["internet",  "Internet",       "", ["Network"]],
  ["learn",     "Learn",          "", ["Education", "Science"]],
  ["utilities", "Utilities",      "", ["Utility"]],
  ["system",    "System",         "", ["System", "Settings"]],
  ["installed", "Installed",      "", []]
];

function section(key) {
  for (const s of SECTIONS) if (s[0] === key) return s;
  return SECTIONS[0];
}

// The source's mark and name: the glyph on a card, the words on a page —
// the same marks the Updates and Packages tabs head their lists with.
function sourceGlyph(app) {
  if (!app) return "";
  if (app.source === "flatpak") return "\uF324";
  if (app.source === "aur") return "\uF415";
  return "\uF303";
}
function sourceLabel(app) {
  if (!app) return "";
  if (app.source === "flatpak") return "Flathub" + (app.installed && app.scope === "user" ? " \u00B7 just you" : "");
  if (app.source === "aur") return "AUR";
  return "Arch \u00B7 " + (app.repo || "extra");
}

function inSection(app, key) {
  if (key === "installed") return !!app.installed;
  const cats = section(key)[3];
  if (!cats.length) return true;
  for (const c of app.cats || []) if (cats.indexOf(c) >= 0) return true;
  return false;
}

// A section's apps: the polished ones first, each half by popularity — the
// catalog arrives sorted by it, and the sort is stable.
function sectionApps(apps, key) {
  const out = (apps || []).filter(a => inSection(a, key));
  if (key === "installed") return out.sort((a, b) => a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1);
  return out.filter(a => a.polished).concat(out.filter(a => !a.polished));
}

// ── search ─────────────────────────────────────────────────────────────────
// Every word must be found somewhere — name, package, summary, developer,
// keywords. A hit in the name counts most, then the package, then the rest;
// popularity breaks ties. "photo editor" finds GIMP by its keywords.
function score(app, words) {
  const name = app.name.toLowerCase(), pkg = app.pkg.toLowerCase();
  const rest = (app.summary + " " + app.dev + " " + (app.keywords || []).join(" ")).toLowerCase();
  let s = 0;
  for (const w of words) {
    if (name === w || pkg === w) s += 100;
    else if (name.startsWith(w)) s += 40;
    else if (name.indexOf(w) >= 0) s += 25;
    else if (pkg.indexOf(w) >= 0) s += 15;
    else if (rest.indexOf(w) >= 0) s += 5;
    else return -1;
  }
  return s;
}

function search(apps, query) {
  const words = String(query || "").toLowerCase().split(/\s+/).filter(w => w);
  if (!words.length) return [];
  const hits = [];
  for (const a of apps || []) {
    const s = score(a, words);
    if (s >= 0) hits.push([s + (a.polished ? 3 : 0) + (a.pop || 0) / 100, a]);
  }
  hits.sort((x, y) => y[0] - x[0]);
  return hits.map(h => h[1]);
}

// ── the front page ─────────────────────────────────────────────────────────
// After the Mac App Store (user, 2026-10-14): a carousel of features, a row
// of artwork, then shelves of apps three rows deep — and Play, which is all
// pictures, as artwork too. Only polished apps (screenshots, a description,
// one app to its package) make the front page — see ceres-store's CARD.
//
// THE FEATURES TURN OVER DAILY, through the twenty most used polished apps
// you do not have: `day` is days since the epoch, so the set is the same all
// day and different tomorrow.
//
// ONLY APPS PEOPLE GO LOOKING FOR. The most used polished apps include the
// desktop's own plumbing — Volume Control, Dolphin, NetworkManager — used
// by many because a desktop brought them, not chosen; System and Utilities
// keep them on their shelves, off the features and the artwork.
const SHOWCASE = ["create", "work", "play", "develop", "watch", "internet", "learn"];
function showcase(app) {
  const s = sectionOf(app);
  if (!s || SHOWCASE.indexOf(s[0]) < 0) return false;
  // Volume Control is filed under Audio too; Settings says what it is
  for (const c of app.cats || []) if (c === "Settings" || c === "System") return false;
  return true;
}
function features(apps, day, n) {
  const pool = (apps || []).filter(a => a.polished && !a.installed && a.shot && showcase(a)).slice(0, 20);
  if (!pool.length) return [];
  const out = [];
  const start = ((day * n) % pool.length + pool.length) % pool.length;
  for (let i = 0; i < Math.min(n, pool.length); i++) out.push(pool[(start + i) % pool.length]);
  return out;
}

// The section an app is filed under first, for an eyebrow ("CREATE").
function sectionOf(app) {
  if (!app) return null;
  for (const s of SECTIONS) if (s[3].length && inSection(app, s[0])) return s;
  return null;
}

// The artwork row: `n` apps with a screenshot, each from a different
// section, none of them already up in the carousel.
function stories(apps, taken, n) {
  const seen = {}, used = {};
  for (const a of taken || []) seen[a.key] = true;
  const out = [];
  for (const a of apps || []) {
    if (out.length >= n) break;
    if (!a.polished || !a.shot || a.installed || seen[a.key] || !showcase(a)) continue;
    const s = sectionOf(a);
    if (used[s[0]]) continue;
    used[s[0]] = true;
    out.push(a);
  }
  return out;
}

// → [{ key, title, apps, art }]. A row shelf holds whole rows (`rows` deep,
// `cols` wide), so the keys walk the rows as one grid; an `art` shelf is
// one row of `artCols` pictures, for the mouse. A section too thin for a
// whole row is left off rather than shown ragged.
const ART = ["play"];
function shelves(apps, cols, taken, rows, artCols) {
  rows = rows || 2;
  artCols = artCols || cols;
  const per = Math.max(1, cols) * rows;
  const seen = {};
  for (const a of taken || []) seen[a.key] = true;
  const out = [];
  const take = (list, n) => {
    const got = [];
    for (const a of list) {
      if (got.length >= n) break;
      if (!seen[a.key]) got.push(a);
    }
    return got;
  };
  const keep = (got) => { for (const a of got) seen[a.key] = true; return got; };
  const polished = (apps || []).filter(a => a.polished);
  // what Arch machines report having (pkgstats) — not Flathub's installs,
  // which are on its own scale and have their own shelf
  const top = take(polished.filter(a => a.source !== "flatpak"), per);
  const whole = top.length - top.length % Math.max(1, cols);
  if (whole > 0) out.push({ key: "", title: "Most used on Arch", apps: keep(top.slice(0, whole)), art: false });
  // what Flathub says is rising this week, in its order — with Flatpak here
  const rising = polished.filter(a => a.source === "flatpak" && a.trend >= 0).sort((a, b) => a.trend - b.trend);
  const tr = take(rising, per);
  const trWhole = tr.length - tr.length % Math.max(1, cols);
  if (trWhole > 0) out.push({ key: "", title: "Trending on Flathub", apps: keep(tr.slice(0, trWhole)), art: false });
  for (const s of SECTIONS) {
    if (!s[3].length) continue;
    const art = ART.indexOf(s[0]) >= 0;
    const list = polished.filter(a => inSection(a, s[0]) && (!art || a.shot));
    const got = take(list, art ? artCols : per);
    const n = art ? (got.length === artCols ? artCols : 0) : got.length - got.length % Math.max(1, cols);
    if (n <= 0) continue;
    out.push({ key: s[0], title: s[1], apps: keep(got.slice(0, n)), art: art });
  }
  return out;
}

// A size as pacman says it, split for the stats strip: "84.12 MiB" →
// ["84.1", "MiB"].
function sizeParts(s) {
  const m = /^([\d.]+)\s*(\S+)/.exec(String(s || "").trim());
  if (!m) return ["", ""];
  const v = Number(m[1]);
  return [v >= 100 ? String(Math.round(v)) : String(Math.round(v * 10) / 10), m[2]];
}

// ── walking a grid with the keys ───────────────────────────────────────────
// `d` is ±1 across, ±cols down; it stops at the ends rather than wrapping.
function step(sel, d, count) {
  if (count <= 0) return 0;
  const n = sel + d;
  if (n < 0) return Math.abs(d) > 1 ? sel : 0;
  if (n >= count) return Math.abs(d) > 1 ? sel : count - 1;
  return n;
}

// ── the page ───────────────────────────────────────────────────────────────
// The links an app has, in the order a page lists them, with their labels.
const LINKS = [
  ["homepage", "Website", ""],
  ["help", "Help", ""],
  ["bugtracker", "Report a problem", ""],
  ["donation", "Donate", ""],
  ["vcs-browser", "Source code", ""],
  ["translate", "Translate", ""],
  ["contribute", "Contribute", ""]
];
function links(urls) {
  const out = [];
  for (const l of LINKS) if (urls && urls[l[0]]) out.push({ key: l[0], label: l[1], glyph: l[2], url: urls[l[0]] });
  return out;
}

// A license expression as people say it: "GPL-3.0+ AND LGPL-3.0+" stays as
// it is; LicenseRef-proprietary is "Proprietary".
function licence(s) {
  const t = String(s || "").trim();
  if (!t) return "";
  if (/^LicenseRef-proprietary/i.test(t)) return "Proprietary";
  return t.replace(/LicenseRef-/g, "");
}

// When a release came out, as a date: "12 March 2026".
const MONTHS = ["January", "February", "March", "April", "May", "June", "July",
                "August", "September", "October", "November", "December"];
function releaseDate(ts) {
  if (!ts) return "";
  const d = new Date(ts * 1000);
  return d.getUTCDate() + " " + MONTHS[d.getUTCMonth()] + " " + d.getUTCFullYear();
}

// What the window's confirm sheet is handed: a Packages row, so installing
// from the Store is the same change, sheet and log as from Packages. An AUR
// app is an AUR row, so the sheet offers its PKGBUILD for review.
function changeRow(app, remove) {
  const aur = app.source === "aur";
  return { state: remove ? "explicit" : "avail", name: app.pkg, size: 0, repo: aur ? "aur" : (app.repo || "extra"),
           version: "", installed: !!remove, aur: aur };
}

// ── Flatpak ────────────────────────────────────────────────────────────────
// `flatpak remote-info` → { "Version", "Download Size", "Installed Size", … }:
// the same names pacman gives, so a Flathub page's strip reads as any other.
function remoteInfo(text) {
  const out = {};
  for (const raw of String(text ?? "").split("\n")) {
    const m = /^\s*([A-Z][A-Za-z ]*?):\s(.*)$/.exec(raw);
    if (m && !(m[1] in out)) out[m[1].trim()] = m[2].trim();
  }
  return out;
}

// WHAT AN APP MAY TOUCH, said plainly — from its metadata's [Context]: the
// sandbox's holes, worst first. `level` is "high" (your files, the whole
// machine), "mid" (devices, the network) or "low". Sockets for drawing and
// sound, fonts and its own settings are what every app needs and are not
// listed; only what someone deciding would want to know.
const FS_WORDS = {
  "host": ["Can read and change all your files", "high"],
  "host-os": ["Can read the system's own files", "high"],
  "host-etc": ["Can read the system's settings", "mid"],
  "home": ["Can read and change your home directory", "high"],
  "xdg-download": ["Your Downloads directory", "mid"],
  "xdg-documents": ["Your Documents directory", "mid"],
  "xdg-music": ["Your Music directory", "mid"],
  "xdg-pictures": ["Your Pictures directory", "mid"],
  "xdg-videos": ["Your Videos directory", "mid"],
  "xdg-desktop": ["Your Desktop directory", "mid"]
};
// A metadata or override file's [Context], as { key: [values] }.
function contextOf(text) {
  const ctx = {};
  let inCtx = false;
  for (const raw of String(text ?? "").split("\n")) {
    const l = raw.trim();
    if (/^\[.*\]$/.test(l)) { inCtx = l === "[Context]"; continue; }
    if (!inCtx) continue;
    const i = l.indexOf("=");
    if (i > 0) ctx[l.slice(0, i)] = l.slice(i + 1).split(";").filter(x => x);
  }
  return ctx;
}

// One permission in words — { text, level } — or null for what is not news.
function permWords(kind, value, raw) {
  if (kind === "filesystems") {
    const ro = /:ro$/.test(raw || "");
    const w = FS_WORDS[value];
    if (w) return { text: ro && /^Can read and change/.test(w[0]) ? w[0].replace(" and change", "")
                      : w[0] + (value.startsWith("xdg-") ? (ro ? ", to read" : ", to read and change") : ""),
                    level: ro && w[1] === "high" ? "mid" : w[1] };
    if (/^[~/]/.test(value)) return { text: "The directory " + value + (ro ? ", to read" : ""), level: "mid" };
    return null;
  }
  const words = {
    "devices:all": ["Every device: cameras, controllers, USB", "high"],
    "devices:input": ["Input devices such as controllers", "mid"],
    "shared:network": ["The network", "mid"],
    "sockets:system-bus": ["The system's message bus", "high"],
    "sockets:session-bus": ["Everything on your session's message bus", "high"],
    "sockets:ssh-auth": ["Your SSH keys, through the agent", "high"],
    "sockets:cups": ["Printing", "low"],
    "sockets:pcsc": ["Smart cards", "mid"]
  }[kind + ":" + value];
  return words ? { text: words[0], level: words[1] } : null;
}

// WHAT AN APP MAY TOUCH, and — given its overrides — what it may NOW
// (user, 2026-10-15: each one a switch). Every row: { text, level, kind,
// value, raw, on, changed }. `on` is the app's own ask with the overrides
// laid over it ("!home" takes home away); `changed` says an override speaks
// of it. Something the overrides grant that the app never asked for is a
// row too, on and changed.
function permissions(metadata, overrides) {
  const ctx = contextOf(metadata), over = contextOf(overrides);
  const bare = v => v.replace(/:(ro|rw|create)$/, "");
  const said = (kind, value) => (over[kind] || []).find(x => bare(x.replace(/^!/, "")) === value);
  const out = [], seen = {};
  const add = (kind, raw, asked) => {
    const value = bare(raw);
    if (seen[kind + ":" + value]) return;
    seen[kind + ":" + value] = true;
    const w = permWords(kind, value, raw);
    if (!w) return;
    const o = said(kind, value);
    out.push({ text: w.text, level: w.level, kind: kind, value: value, raw: raw,
               on: o ? !o.startsWith("!") : asked, changed: !!o });
  };
  for (const kind of ["filesystems", "devices", "shared", "sockets"]) {
    for (const raw of ctx[kind] || []) add(kind, raw, true);
    for (const raw of over[kind] || []) if (!raw.startsWith("!")) add(kind, raw, false);
  }
  // every device says the lesser ones too: input goes under all
  if (out.some(r => r.kind === "devices" && r.value === "all" && r.on))
    for (let i = out.length - 1; i >= 0; i--) if (out[i].kind === "devices" && out[i].value === "input") out.splice(i, 1);
  const rank = { high: 0, mid: 1, low: 2 };
  return out.sort((a, b) => rank[a.level] - rank[b.level]);
}

// The `flatpak override` flag that turns a row on or off. Back on, it is
// given as the app asked for it (xdg-pictures:ro stays read-only).
function overrideFlag(row, on) {
  const verb = { filesystems: ["--filesystem=", "--nofilesystem="], shared: ["--share=", "--unshare="],
                 devices: ["--device=", "--nodevice="], sockets: ["--socket=", "--nosocket="] }[row.kind];
  if (!verb) return "";
  return on ? verb[0] + (row.kind === "filesystems" ? row.raw : row.value) : verb[1] + row.value;
}
// the steps that set it — yours as you, the system's as root
function overrideSteps(id, scope, flag) {
  if (scope === "user") return [["@user", "flatpak override --user " + flag + " " + id]];
  return [["@sudo", "flatpak", "override", "--system", flag, id]];
}
function overrideResetSteps(id, scope) {
  if (scope === "user") return [["@user", "flatpak override --user --reset " + id]];
  return [["@sudo", "flatpak", "override", "--system", "--reset", id]];
}

// Flathub's monthly installs, as a strip says them: 52K, 1.2M, 840.
function count(n) {
  n = Number(n) || 0;
  if (n >= 1e6) return (Math.round(n / 1e5) / 10) + "M";
  if (n >= 1e4) return Math.round(n / 1e3) + "K";
  if (n >= 1e3) return (Math.round(n / 100) / 10) + "K";
  return String(n);
}

// ── ONE APP, MORE THAN ONE SOURCE ──────────────────────────────────────────
// A card is one app; `others` are the same app from elsewhere (ceres-store
// records them — today Flathub's build of a repo or AUR app). The page's
// switch offers each, with what choosing it means.
function sourceNote(app) {
  if (!app) return "";
  if (app.source === "flatpak") return (app.verified ? "verified · " : "") + "sandboxed, updates on its own";
  if (app.source === "aur") return "built here from its PKGBUILD";
  return "signed by Arch · shares the system's libraries";
}
function sourceName(src) {
  return src === "flatpak" ? "Flathub" : src === "aur" ? "AUR" : "Arch";
}
// The card as `src`: its own fields where that source has them.
function asSource(app, src) {
  if (!app || !src || src === app.source) return app;
  const o = (app.others || []).find(x => x.source === src);
  if (!o) return app;
  return Object.assign({}, app, {
    source: o.source, repo: o.repo, pkg: o.pkg, launch: o.launch || "", verified: !!o.verified,
    installs: o.installs || 0, installed: !!o.installed, scope: o.scope || "", alts: o.alts || [],
    others: [Object.assign({}, app, { others: [] })].concat((app.others || []).filter(x => x !== o))
  });
}
// [[source, name, note]] for the switch — the card's own first
function sources(app) {
  if (!app || !(app.others || []).length) return [];
  return [app].concat(app.others.map(o => asSource(app, o.source)))
    .map(a => [a.source, sourceName(a.source) + (a.installed ? "  ·  installed" : ""), sourceNote(a)]);
}

// THE CARD'S MARK (user, 2026-10-14): one source's, or — when the app comes
// from more than one — the layers mark, so a card that also has Flathub's
// build is never taken for the AUR's alone.
const MULTI_GLYPH = "\uDB80\uDF28";
function cardGlyph(app) {
  if (app && (app.others || []).length) return MULTI_GLYPH;
  return sourceGlyph(app);
}

// WHERE A PAGE OPENS (Settings › Channels' "Open apps on"): the card's own
// source, unless the preference is Flathub and the card has Flathub's build
// — and never away from what is installed, which the card already leads with.
function openingSource(app, prefer) {
  if (!app) return "";
  if (app.installed || prefer !== "flatpak") return app.source;
  return (app.others || []).some(o => o.source === "flatpak") ? "flatpak" : app.source;
}

// ── WALKING ROWS OF ANY WIDTH (user, 2026-10-15) ───────────────────────────
// A page as rows: Discover's carousel is one item, its artwork row four, a
// shelf `cols` a row, Play's pictures their own count. `rows` are lengths,
// `sel` a flat index; `dir` is left, right, up, down, pageup or pagedown.
// Across stops at a row's ends; up and down keep to the same place along
// the row — the same column between rows alike, the nearest share of the
// width between rows that are not — and stop at the page's ends.
function rowOf(sel, rows) {
  let start = 0;
  for (let r = 0; r < rows.length; r++) {
    if (sel < start + rows[r]) return { r: r, c: sel - start, start: start };
    start += rows[r];
  }
  return null;
}
function stepRows(sel, dir, rows) {
  if (!rows || !rows.length) return 0;
  const at = rowOf(sel, rows);
  if (!at) return 0;
  if (dir === "left") return at.c > 0 ? sel - 1 : sel;
  if (dir === "right") return at.c < rows[at.r] - 1 ? sel + 1 : sel;
  const by = dir === "up" ? -1 : dir === "down" ? 1 : dir === "pageup" ? -4 : dir === "pagedown" ? 4 : 0;
  if (!by) return sel;
  const nr = Math.max(0, Math.min(rows.length - 1, at.r + by));
  if (nr === at.r) return sel;
  let start = 0;
  for (let r = 0; r < nr; r++) start += rows[r];
  const nc = rows[nr] === rows[at.r] ? Math.min(at.c, rows[nr] - 1)
    : Math.min(rows[nr] - 1, Math.floor((at.c + 0.5) * rows[nr] / rows[at.r]));
  return start + nc;
}
// n items in rows of `cols`
function chunkRows(n, cols) {
  const out = [];
  for (let i = 0; i < n; i += Math.max(1, cols)) out.push(Math.min(Math.max(1, cols), n - i));
  return out;
}
