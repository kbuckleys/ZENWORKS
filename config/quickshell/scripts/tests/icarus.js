// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The pure half of icarus' Home cards: reading a folder, the order it is
// shown in, the places above it, the crumbs that fit, and typing to jump.
//
// The listing is fed the shape listCommand actually prints — a status record,
// then find's records — because that shape is what the parser has to survive.

"use strict";

const F = "\u001f", R = "\u001e";
function rec(y, Y, mode, size, name) { return [y, Y, mode, size, name].join(F) + R; }

module.exports = {
  module: "icarus/icarus.js",
  cases: (I, t) => {
    // ── reading a folder ──────────────────────────────────────────────────
    const out = "ok" + R
      + rec("d", "d", "755", "4096", "Documents")
      + rec("l", "d", "777", "7", "proj")
      + rec("f", "f", "644", "2048", ".bashrc")
      + rec("f", "f", "755", "100", "run.sh")
      + rec("l", "N", "777", "3", "gone");
    const L = I.parseListing(out, "/home/test");
    t.eq("the status is read", L.state, "ok");
    t.eq("every record is a row", L.rows.length, 5);
    t.eq("a link to a folder is a folder", L.rows[1].isDir, true);
    t.eq("and still a link", L.rows[1].isLink, true);
    t.eq("paths are joined", L.rows[1].path, "/home/test/proj");
    t.eq("a dotfile is hidden", L.rows[2].isHidden, true);
    t.eq("the exec bit is seen", L.rows[3].isExec, true);
    t.eq("a folder is never exec", L.rows[0].isExec, false);
    t.eq("a broken link is broken", L.rows[4].broken, true);
    t.eq("the size is kept", L.rows[2].size, 2048);
    t.eq("denied says so", I.parseListing("denied" + R, "/root").state, "denied");
    t.eq("missing says so", I.parseListing("missing" + R, "/nope").state, "missing");
    t.eq("no status reads as ok", I.parseListing("", "/x").state, "ok");
    t.eq("joined at the root", I.parseListing("ok" + R + rec("d", "d", "755", "0", "etc"), "/").rows[0].path, "/etc");
    t.has("the command follows a linked folder", I.listCommand("/a/link"), "'/a/link/'");
    t.has("and prints the resolved type", I.listCommand("/a"), "%Y");

    // ── the order ─────────────────────────────────────────────────────────
    const rows = [
      { name: "b.txt", isDir: false, isHidden: false },
      { name: ".config", isDir: true, isHidden: true },
      { name: "Music", isDir: true, isHidden: false },
      { name: "a10", isDir: false, isHidden: false },
      { name: "a9", isDir: false, isHidden: false },
      { name: "documents", isDir: true, isHidden: false }
    ];
    t.eq("hidden are left out",
      I.visibleRows(rows, false, 0).rows.map((r) => r.name),
      ["documents", "Music", "a9", "a10", "b.txt"]);
    t.eq("and go last among folders when shown",
      I.visibleRows(rows, true, 0).rows.map((r) => r.name),
      ["documents", "Music", ".config", "a9", "a10", "b.txt"]);
    const capped = I.visibleRows(rows, true, 2);
    t.eq("a cap keeps the first", capped.rows.length, 2);
    t.eq("and counts the rest", capped.more, 4);
    t.eq("no cap is no cap", I.visibleRows(rows, true, 0).more, 0);

    // ── counts ────────────────────────────────────────────────────────────
    const argv = I.countArgv(["/h/a", "/h/b"], false);
    t.eq("folders go in as arguments", argv.slice(-2), ["/h/a/", "/h/b/"]);
    t.has("hidden are not counted when hidden", argv[2], "! -name '.*'");
    t.eq("shown hidden are counted", I.countArgv(["/h/a"], true)[2].indexOf("-name"), -1);
    t.eq("uniq's counts, keyed by folder",
      I.parseCounts("      3 /h/a/\n", ["/h/a", "/h/b"]), { "/h/a": 3, "/h/b": 0 });

    t.eq("bytes", I.shortSize(512), "512B");
    t.eq("kibibytes", I.shortSize(4300), "4.2K");
    t.eq("big numbers lose the decimal", I.shortSize(50 * 1048576), "50M");

    // ── places ────────────────────────────────────────────────────────────
    const ud = ["/home/test/Documents", "/home/test/Downloads"];
    t.eq("at home only the far places are left",
      I.places("/home/test", ud, ["/srv/media"], "/home/test").map((p) => p.path),
      ["/srv/media"]);
    t.eq("elsewhere they all are",
      I.places("/home/test", ud, ["/srv/media"], "/etc").map((p) => p.label),
      ["Home", "Documents", "Downloads", "media"]);
    t.eq("a bookmark that is a user dir is one place",
      I.places("/home/test", ud, ["/home/test/Documents/"], "/etc").length, 3);
    t.eq("the existing ones are read back",
      I.parseExisting("/a" + R + "/b" + R), ["/a", "/b"]);

    // ── crumbs ────────────────────────────────────────────────────────────
    const cr = [{ label: "~", path: "/h" }, { label: "aaaa", path: "/h/aaaa" },
                { label: "bbbb", path: "/h/aaaa/bbbb" }, { label: "cc", path: "/h/aaaa/bbbb/cc" }];
    const w = (s) => s.length * 10;
    t.eq("all of them when they fit", I.fitCrumbs(cr, 500, w, 10).length, 4);
    const fit = I.fitCrumbs(cr, 100, w, 10);
    t.eq("the front is dropped first", fit.map((c) => c.label), ["…", "bbbb", "cc"]);
    t.eq("and the … leads to what it hides", fit[0].path, "/h/aaaa");
    t.eq("the last one always stays", I.fitCrumbs(cr, 1, w, 10).map((c) => c.label), ["…", "cc"]);

    // ── typing ────────────────────────────────────────────────────────────
    const names = ["Desktop", null, "Documents", "Downloads", "Music"];
    t.eq("a letter finds the first", I.typeAhead(names, "d", -1), 0);
    t.eq("the same letter walks on", I.typeAhead(names, "d", 0), 2);
    t.eq("and again", I.typeAhead(names, "dd", 2), 3);
    t.eq("and wraps", I.typeAhead(names, "d", 3), 0);
    t.eq("more letters narrow it", I.typeAhead(names, "dow", 0), 3);
    t.eq("staying put when it still matches", I.typeAhead(names, "do", 2), 2);
    t.eq("nothing is -1", I.typeAhead(names, "z", 0), -1);

    // ── placing a cascade ─────────────────────────────────────────────────
    t.eq("to the right when it fits", I.cascadeX(100, 300, 300, 2000, 8, false), 400);
    t.eq("left when it does not", I.cascadeX(1500, 300, 300, 2000, 8, false), 1200);
    t.eq("and stays left", I.cascadeX(900, 300, 300, 2000, 8, true), 600);

    // ── remembering ───────────────────────────────────────────────────────
    t.eq("within the window", I.keepFolder(1000, 1000 + 60000, 5), true);
    t.eq("outside it", I.keepFolder(1000, 1000 + 6 * 60000, 5), false);
    t.eq("0 is always home", I.keepFolder(1000, 1001, 0), false);
    t.eq("never closed is home", I.keepFolder(0, 1001, 5), false);
  }
};
