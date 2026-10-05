// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Plato's plugin panel reads vim.pack's confirmation buffer, which is written
// for people and not for programs. These pin the reading to a real buffer
// (captured from nvim 0.12.5), so a change in its shape shows up here rather
// than as an empty panel.

"use strict";

const BUFFER = [
  "# Update ───────────────────────────────",
  "",
  "## mini.nvim",
  "Path:            /home/test/.local/share/quickshell/plato/nvim/site/pack/core/opt/mini.nvim",
  "Source:          https://github.com/nvim-mini/mini.nvim",
  "Revision before: 6791615e48801cbf5b2baefadcea77a7760de3f4",
  "Revision after:  561751e839b99a4baca36b9d963166b66d2536a6 (main)",
  "",
  "Pending updates:",
  "> 561751e │ fix(icons): update `mock_nvim_web_devicons` to respect global `default`",
  "> ed76caa │ docs(completion): add 'complete' option value recommendation",
  "",
  "## marks.nvim",
  "Revision before: f353e8c08c50f39e99a9ed474172df7eddd89b72",
  "Revision after:  a1b2c3d4e5f60718293a4b5c6d7e8f9012345678 (master)",
  "Pending updates:",
  "< 1a2b3c4 │ reverted thing",
  "",
  "# Same ───────────────────────────────",
  "",
  "## vim-fugitive (not active)",
  "Path:            /x",
  "",
  "# Error ──────────────────────────────",
  "",
  "## nvim-lspconfig",
  "fatal: unable to access 'https://github.com/…': Could not resolve host",
].join("\n");

module.exports = {
  module: "plato/editor/pack.js",
  cases: (P, t) => {
    const r = P.parse(BUFFER);
    t.eq("two plugins to update", r.updates.map((u) => u.name), ["mini.nvim", "marks.nvim"]);
    t.eq("revisions read", [r.updates[0].before.slice(0, 7), r.updates[0].after.slice(0, 7)],
      ["6791615", "561751e"]);
    t.eq("the branch, out of its brackets", r.updates[0].branch, "main");
    t.eq("commits in order", r.updates[0].commits.map((c) => c.sha), ["561751e", "ed76caa"]);
    t.eq("a commit's message whole, backticks and all",
      r.updates[0].commits[0].msg,
      "fix(icons): update `mock_nvim_web_devicons` to respect global `default`");
    t.eq("> brings a commit in", r.updates[0].commits[0].dir, "in");
    t.eq("< takes one away", r.updates[1].commits[0].dir, "out");
    t.eq("up to date ones listed as such, standing trimmed off", r.same, ["vim-fugitive"]);
    t.eq("an error kept with its plugin", r.errors[0].name, "nvim-lspconfig");
    t.eq("and its text", /Could not resolve host/.test(r.errors[0].text), true);
    t.eq("summary: new commits", P.summary(r.updates[0]), "2 new commits");
    t.eq("summary: going back", P.summary(r.updates[1]), "1 commit back");
    t.eq("nothing to update is nothing", P.parse("").updates.length, 0);
    t.eq("a failure before any section", P.parse("ERROR no network").error, "no network");
    // nvim's progress line has no newline after it: read with stderr mixed
    // in, the first header arrives glued onto its end
    const glued = P.parse("vim.pack: 100% Downloading updates (7/7) - nvim-autopairs# Update ─────\n\n## mini.nvim\n"
      + "Revision before: 6791615e48801cbf5b2baefadcea77a7760de3f4\n"
      + "Revision after:  561751e839b99a4baca36b9d963166b66d2536a6 (main)\n"
      + "> 561751e │ fix(icons): x");
    t.eq("a header glued to nvim's progress still starts its section",
      glued.updates.map((u) => u.name), ["mini.nvim"]);
  },
};
