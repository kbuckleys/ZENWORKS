// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Tidy (hygieia): tidy.py's answers read, what can be given back, and above
// all that one copy of every duplicate always stays.

"use strict";

module.exports = {
  module: "hygieia/hygieia.js",
  cases: (H, t) => {
    const blank = H.parseOverview("nope");
    t.eq("a broken answer is the empty one", [blank.known, blank.caches.dirs, blank.orphans], [false, [], []]);
    const ov = H.parseOverview(JSON.stringify({
      trash: { bytes: 10, items: 1, dir: "/t" },
      caches: { bytes: 5, dirs: [{ name: "a", path: "/c/a", bytes: 5 }, { bad: 1 }] },
      pkgcache: { bytes: 900, tool: true, old: { count: 3, bytes: 300 }, gone: { count: 1, bytes: 100 } },
      orphans: [{ name: "x", bytes: 50 }],
      journal: { bytes: 200 * 1024 * 1024 + 7 },
      downloads: { dir: "/d", files: [{ path: "/d/f", bytes: 1, mtime: 2 }] }
    }));
    t.eq("read", [ov.known, ov.caches.dirs.length, ov.pkgcache.old.count, ov.downloads.files[0].path], [true, 1, 3, "/d/f"]);
    t.eq("reclaimable", H.reclaimable(ov), 300 + 100 + 50 + 7);
    t.eq("journal kept", [H.journalSpare(5), H.journalSpare(200 * 1024 * 1024 + 1)], [0, 1]);

    const g = H.parseDupes(JSON.stringify([
      { bytes: 10, paths: [{ path: "/b", mtime: 5 }, { path: "/a", mtime: 1 }, { path: "/c", mtime: 9 }] },
      { bytes: 4, paths: [{ path: "/only", mtime: 1 }] }
    ]));
    t.eq("a group of one is not a group", g.length, 1);
    t.eq("waste", H.dupeWaste(g), 20);
    t.eq("the oldest is kept", H.dupePicks(g), { "/b": true, "/c": true });
    t.eq("never every copy", H.safePicks(g, { "/a": true, "/b": true, "/c": true }), { "/a": true, "/c": true });

    t.eq("steps", [H.pkgcacheSteps(false), H.orphanSteps(["ok-1", "bad;rm"]), H.journalSteps()],
      [[["@sudo", "paccache", "-rk1"]], [["@sudo", "pacman", "-Rns", "--noconfirm", "ok-1"]],
       [["@sudo", "journalctl", "--vacuum-size=200M"]]]);
    t.eq("no orphans, no step", H.orphanSteps([]), []);
    t.eq("words", [H.baseName("/a/b.txt"), H.where("/h/x/y.txt", "/h"), H.where("/etc/x", "/h"),
                   H.ageWords(0, 3 * 86400), H.ageWords(0, 400 * 86400), H.ageWords(0, 800 * 86400)],
      ["b.txt", "~/x", "/etc", "3 days old", "13 months old", "2 years old"]);
  }
};
