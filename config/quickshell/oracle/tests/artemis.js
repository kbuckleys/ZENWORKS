// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// artemis builds shell text that runs over an index of $HOME, and plato's
// Ctrl-P runs the same text scoped to one project. A quoting slip here does
// not fail, it searches the wrong thing — so the commands are checked as
// text, and `covers` (which decides whether a project can use the shared
// index at all) against the excludes it is read from.

"use strict";

module.exports = {
  module: "artemis/artemis.js",
  cases: (A, t) => {
    // ── unscoped: artemis' own search, unchanged ──────────────────────────
    t.eq("filter reads the whole index",
      A.filterCommand("/c/idx", "foo", false),
      "cat '/c/idx' 2>/dev/null | fzf --filter 'foo' 2>/dev/null | head -n 500");
    t.eq("dirs-only reads the directories",
      A.filterCommand("/c/idx", "foo", true).indexOf("grep '/$' '/c/idx'") === 0, true);
    t.eq("browse is the head of the index",
      A.browseCommand("/c/idx", false), "cat '/c/idx' 2>/dev/null | head -n 200");

    // ── scoped: plato's project search ────────────────────────────────────
    const f = A.filterCommand("/c/idx", "view", false, "/home/test/proj");
    t.eq("a scope reads only files under it, relative",
      f.indexOf("awk -v r='/home/test/proj/' 'index($0, r) == 1") === 0, true);
    t.eq("a scope drops directories", f.indexOf("substr($0, length($0)) != \"/\"") > 0, true);
    t.eq("and ranks what is left the same way", / \| fzf --filter 'view' /.test(f), true);
    t.eq("a scope with a quote in it stays one word",
      A.filterCommand("/c/idx", "x", false, "/home/test/o'dd").indexOf("'/home/test/o'\\''dd/'") > 0, true);

    t.eq("the whole index's files, for plato's finder",
      A.filterCommand("/c/idx", "x", false, "files").indexOf("grep -v '/$' '/c/idx'") === 0, true);

    // ── covers ────────────────────────────────────────────────────────────
    t.eq("home covers a project in it", A.covers("/home/test", "/home/test/.config/quickshell"), true);
    t.eq("and itself", A.covers("/home/test/", "/home/test"), true);
    t.eq("not a directory outside it", A.covers("/home/test", "/srv/code"), false);
    t.eq("not a sibling that shares a prefix", A.covers("/home/test", "/home/tester/x"), false);
    t.eq("not anything under an excluded name",
      A.covers("/home/test", "/home/test/.local/share/thing"), false);
    t.eq("nor under node_modules", A.covers("/home/test", "/home/test/p/node_modules/q"), false);
  },
};
