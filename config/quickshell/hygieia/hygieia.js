.pragma library
// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HYGIEIA'S PURE HALF (Tidy, 2026-10-22): core/tidy.py's answers read with
// every field there, what each part could give back, which copy of a
// duplicate is kept, and the root steps Ceres runs. Nothing here touches the
// machine; oracle/tests/hygieia.js pins it.

// the journal is vacuumed down to this, not emptied: the last boots' logs
// are what Hestia reads when something goes wrong
const JOURNAL_KEEP = 200 * 1024 * 1024;

function num(v) { const n = Number(v); return n >= 0 ? n : 0; }

function parseOverview(text) {
  let j = null;
  try { j = JSON.parse(text); } catch (e) {}
  const o = j && typeof j === "object" && !j.error ? j : {};
  const t = o.trash || {}, c = o.caches || {}, p = o.pkgcache || {}, jr = o.journal || {}, d = o.downloads || {};
  return {
    known: !!(j && !j.error),
    trash: { bytes: num(t.bytes), items: num(t.items), dir: String(t.dir || "") },
    caches: { bytes: num(c.bytes), dirs: (Array.isArray(c.dirs) ? c.dirs : [])
      .filter((x) => x && typeof x.path === "string").map((x) => ({ name: String(x.name || ""), path: x.path, bytes: num(x.bytes) })) },
    pkgcache: { bytes: num(p.bytes), tool: p.tool === true,
                old: { count: num(p.old && p.old.count), bytes: num(p.old && p.old.bytes) },
                gone: { count: num(p.gone && p.gone.count), bytes: num(p.gone && p.gone.bytes) },
                both: { count: num(p.both && p.both.count), bytes: num(p.both && p.both.bytes) } },
    orphans: (Array.isArray(o.orphans) ? o.orphans : []).filter((x) => x && typeof x.name === "string")
      .map((x) => ({ name: x.name, bytes: num(x.bytes) })),
    journal: { bytes: num(jr.bytes) },
    downloads: { dir: String(d.dir || ""), files: (Array.isArray(d.files) ? d.files : [])
      .filter((x) => x && typeof x.path === "string").map((x) => ({ path: x.path, bytes: num(x.bytes), mtime: num(x.mtime) })) }
  };
}

function journalSpare(bytes) { return Math.max(0, num(bytes) - JOURNAL_KEEP); }
function orphanBytes(list) { return (list || []).reduce((a, x) => a + num(x.bytes), 0); }

// What the head says could be given back, without counting the same room
// twice: the package cache's old and gone versions, the orphans, the
// journal above what is kept. Caches, downloads and copies are yours to
// judge, so they are not in it.
function reclaimable(ov) {
  if (!ov || !ov.known) return 0;
  // a removed package's older versions are in both old (-k1 keeps one of
  // every package) and gone (-uk0 keeps none of a removed one)
  return pkgcacheBytes(ov.pkgcache) + orphanBytes(ov.orphans) + journalSpare(ov.journal.bytes);
}
// the package cache's two parts, apart: older versions of what is still
// installed (old less both), and every version of what is not (gone)
function pkgcacheOld(p) {
  return { count: Math.max(0, p.old.count - p.both.count), bytes: Math.max(0, p.old.bytes - p.both.bytes) };
}
function pkgcacheBytes(p) { return pkgcacheOld(p).bytes + p.gone.bytes; }

// ── DUPLICATES ─────────────────────────────────────────────────────────────
function parseDupes(text) {
  let j = null;
  try { j = JSON.parse(text); } catch (e) {}
  if (!Array.isArray(j)) return [];
  return j.filter((g) => g && Array.isArray(g.paths) && g.paths.length > 1)
    .map((g) => ({ bytes: num(g.bytes), paths: g.paths.filter((p) => p && typeof p.path === "string")
      .map((p) => ({ path: p.path, mtime: num(p.mtime) })) }))
    .filter((g) => g.paths.length > 1);
}
// room the copies take beyond one each
function dupeWaste(groups) {
  return (groups || []).reduce((a, g) => a + g.bytes * (g.paths.length - 1), 0);
}
// The copies ticked to go when the list arrives: every one but the one
// kept — the oldest, the original before it was copied — so one of each
// always stays. A set: path -> true.
function dupePicks(groups) {
  const out = {};
  for (const g of groups || []) {
    const keep = g.paths.reduce((a, p) => (p.mtime < a.mtime || (p.mtime === a.mtime && p.path < a.path)) ? p : a, g.paths[0]);
    for (const p of g.paths) if (p !== keep) out[p.path] = true;
  }
  return out;
}
// Never every copy of one file: a group whose every path is ticked keeps
// its first (the safety the window enforces before trashing)
function safePicks(groups, picks) {
  const out = Object.assign({}, picks || {});
  for (const g of groups || []) {
    if (g.paths.every((p) => out[p.path])) delete out[g.paths[0].path];
  }
  return out;
}
// ── ROOT'S STEPS, for Ceres' password card ──────────────────────────────────
function pkgcacheSteps(gone) {
  return [["@sudo", "paccache", "-rk1"]].concat(gone ? [["@sudo", "paccache", "-ruk0"]] : []);
}
function orphanSteps(names) {
  const n = (names || []).filter((x) => /^[A-Za-z0-9@._+-]+$/.test(x));
  return n.length ? [["@sudo", "pacman", "-Rns", "--noconfirm"].concat(n)] : [];
}
function journalSteps() {
  return [["@sudo", "journalctl", "--vacuum-size=" + Math.round(JOURNAL_KEEP / 1048576) + "M"]];
}

// ── WORDS ──────────────────────────────────────────────────────────────────
function baseName(p) { const s = String(p || ""); return s.slice(s.lastIndexOf("/") + 1); }
// the directory, home as ~
function where(p, home) {
  const s = String(p || "");
  const d = s.slice(0, s.lastIndexOf("/")) || "/";
  return home && (d === home || d.indexOf(home + "/") === 0) ? "~" + d.slice(home.length) : d;
}
function ageWords(mtime, now) {
  const days = Math.floor((num(now) - num(mtime)) / 86400);
  if (days < 1) return "today";
  if (days < 60) return days + (days === 1 ? " day" : " days") + " old";
  if (days < 730) return Math.floor(days / 30) + " months old";
  return Math.floor(days / 365) + " years old";
}
