// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// morpheus/share.js: the Share menu's ways out and their commands.

"use strict";

module.exports = {
  module: "morpheus/share.js",
  cases: (S, t) => {
    t.eq("one file", S.targets(1, false, true).map((x) => x.id), ["email", "clio"]);
    t.eq("several", S.targets(3, false, true).map((x) => x.id), ["email", "clio"]);
    t.eq("no mail app, no Email", S.targets(1, false, false).map((x) => x.id), ["clio"]);
    t.eq("a directory", S.targets(2, true), []);
    t.eq("nothing", S.targets(0, false), []);
    t.eq("email", S.emailArgs(["/a", "/b"]), ["xdg-email", "--attach", "/a", "--attach", "/b"]);
  }
};
