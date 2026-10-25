// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// DELPHI'S WINDOW HALF: a status into the Changes list, a diff into rows and
// a dragged range back into the lines to stage, ages, remotes, questions.
// (The git half is oracle/tests/delphi-core.py.)

"use strict";

const ST = {
  branch: { head: "main" },
  staged: [{ path: "b.txt", kind: "modified" }, { path: "a/new.qml", kind: "added" }],
  unstaged: [{ path: "z.txt", kind: "deleted" }, { path: "b.txt", kind: "modified" }],
  untracked: [{ path: "dir/n.md" }],
  conflicts: [],
};

const FILE = {
  old: "f", new: "f", status: "modified", binary: false, header: [],
  hunks: [
    { oldStart: 3, oldCount: 4, newStart: 3, newCount: 4, section: "",
      lines: [
        { t: " ", text: "c", old: 3, new: 3 },
        { t: "-", text: "x", old: 4 },
        { t: "-", text: "y", old: 5 },
        { t: "+", text: "X", new: 4 },
        { t: "+", text: "Y", new: 5 },
        { t: " ", text: "d", old: 6, new: 6 },
      ] },
    { oldStart: 20, oldCount: 1, newStart: 20, newCount: 2, section: "fn()",
      lines: [{ t: " ", text: "e", old: 20, new: 20 }, { t: "+", text: "E", new: 21 }] },
  ],
};

module.exports = {
  module: "delphi/delphi.js",
  cases: (D, t) => {
    const secs = D.sections(ST);
    t.eq("sections in working order", secs.map((s) => s.id), ["unstaged", "staged"]);
    t.eq("untracked join the changes, sorted", secs[0].rows.map((r) => r.path + ":" + r.state),
      ["b.txt:modified", "dir/n.md:untracked", "z.txt:deleted"]);
    t.eq("dir and name split", [secs[0].rows[1].dir, secs[0].rows[1].name], ["dir/", "n.md"]);
    t.eq("staged is terminus' staged, whatever was done", secs[1].rows.map((r) => r.state + ":" + r.word),
      ["staged:added", "staged:modified"]);
    t.eq("conflicts come first when there are any",
      D.sections(Object.assign({}, ST, { conflicts: [{ path: "c", how: "both modified" }] }))[0].id, "conflict");

    const rows = D.flatten(secs);
    t.eq("heads in the flat list", rows.filter((r) => r.head).map((r) => r.title + r.count),
      ["Changes3", "Staged2"]);
    t.eq("reseat: same file, same area", D.reseat(rows, { path: "z.txt", sec: "unstaged" }, 0), 3);
    // b.txt was staged whole and left the Changes section: the cursor stays
    // in the section it was working through
    const after = D.flatten(D.sections(Object.assign({}, ST,
      { unstaged: [{ path: "z.txt", kind: "deleted" }] })));
    t.eq("reseat: gone, stays in its area", after[D.reseat(after, { path: "b.txt", sec: "unstaged" }, 1)].path, "dir/n.md");
    t.eq("reseat: empty", D.reseat([], null, 0), -1);
    t.eq("nextFile skips heads", D.nextFile(rows, 3, 1), 5);

    const dr = D.diffRows([FILE]);
    t.eq("one file: no file head", dr[0].kind, "hunk");
    t.eq("rows", dr.length, 2 + 6 + 2);
    t.eq("line address", [dr[2].hi, dr[2].li, dr[2].t, dr[2].old], [0, 1, "-", 4]);
    t.eq("hunk label", dr[0].text, "lines 3–6");
    t.eq("two files: heads", D.diffRows([FILE, FILE]).filter((r) => r.kind === "file").length, 2);

    t.eq("range → changed lines only", D.chosenIn(dr, 1, 3), { 0: [1, 2] });
    t.eq("range either way", D.chosenIn(dr, 3, 1), { 0: [1, 2] });
    t.eq("range across hunks", D.chosenIn(dr, 4, 9), { 0: [3, 4], 1: [1] });
    t.eq("hunk head alone = whole hunk", D.chosenIn(dr, 7, 7), { 1: null });
    t.eq("context only = nothing", D.chosenIn(dr, 1, 1), null);
    t.eq("nextChange down", D.nextChange(dr, 1, 1), 2);
    t.eq("nextChange to next hunk", D.nextChange(dr, 6, 1), 9);
    t.eq("nextChange stops at the end", D.nextChange(dr, 9, 1), 9);
    t.eq("stats", D.diffStats([FILE]), { added: 3, deleted: 2 });

    const now = Date.UTC(2026, 9, 10, 12, 0, 0);
    const s = now / 1000;
    t.eq("ago now", D.ago(s - 5, now), "now");
    t.eq("ago min", D.ago(s - 600, now), "10 min");
    t.eq("ago h", D.ago(s - 7200, now), "2 h");
    t.eq("ago yesterday", D.ago(s - 90000, now), "yesterday");
    t.eq("ago days", D.ago(s - 5 * 86400, now), "5 d");
    t.eq("ago this year", /^\d+ [A-Z][a-z]{2}$/.test(D.ago(s - 90 * 86400, now)), true);
    t.eq("ago another year", /\d{4}$/.test(D.ago(s - 400 * 86400, now)), true);
    t.eq("laneInk wraps", [D.laneInk(0), D.laneInk(8), D.laneInk(-1)], ["cyan", "cyan", "pink"]);

    t.eq("chips: checked out first", D.chips([{ kind: "remote", name: "origin/main" },
      { kind: "tag", name: "v1" }, { kind: "local", name: "main", head: true }]).map((c) => c.label),
      ["main", "v1", "origin/main"]);

    t.eq("subject", D.subjectOf("\n  Fix it  \n\nbody"), "Fix it");
    t.eq("empty message", D.messageNote("  \n").ok, false);
    t.eq("long subject", D.messageNote("x".repeat(80)).ink, "red");
    t.eq("over 50", D.messageNote("x".repeat(60)).ink, "yellow");

    t.eq("remote https", D.remoteOf("https://github.com/kbuckleys/zenworks.git"),
      { host: "github.com", full: "kbuckleys/zenworks", web: "https://github.com/kbuckleys/zenworks" });
    t.eq("remote scp-like", D.remoteOf("git@github.com:o/n.git").full, "o/n");
    t.eq("remote ssh url with port", D.remoteOf("ssh://git@codeberg.org:22/o/n").host, "codeberg.org");
    t.eq("remote nonsense", D.remoteOf(""), null);
    t.eq("protocols", ["https://github.com/o/n", "git@github.com:o/n.git", "ssh://aur@aur.archlinux.org/z.git", "/srv/x.git"].map(D.protocolOf),
      ["HTTPS", "SSH", "SSH", ""]);
    t.eq("https to ssh: a forge", D.otherUrl("https://github.com/kbuckleys/ZENWORKS.git"), "git@github.com:kbuckleys/ZENWORKS.git");
    t.eq("https to ssh: the AUR", D.otherUrl("https://aur.archlinux.org/zenworks.git"), "ssh://aur@aur.archlinux.org/zenworks.git");
    t.eq("ssh to https", D.otherUrl("git@codeberg.org:kb/z"), "https://codeberg.org/kb/z.git");
    t.eq("and back again", D.otherUrl(D.otherUrl("https://gitlab.com/g/sub/p.git")), "https://gitlab.com/g/sub/p.git");
    t.eq("a path has no other way", D.otherUrl("/srv/x.git"), "");
    t.eq("ssh target", [D.sshTarget("git@github.com:o/n"), D.sshTarget("ssh://aur@aur.archlinux.org/z.git"), D.sshTarget("https://x/y")],
      [{ user: "git", host: "github.com" }, { user: "aur", host: "aur.archlinux.org" }, null]);
    t.eq("clone name", D.cloneName("git@github.com:o/my-repo.git"), "my-repo");

    t.eq("ask password", D.askCard({ prompt: "Password for 'https://me@github.com': ", secret: true }),
      { title: "Password", detail: "me@github.com", secret: true });
    t.eq("ask username", D.askCard({ prompt: "Username for 'https://github.com': ", secret: false }).title, "Username");
    t.eq("ask passphrase", D.askCard({ prompt: "Enter passphrase for key '/home/u/.ssh/id_ed25519': ", secret: true }).detail,
      "/home/u/.ssh/id_ed25519");
    t.eq("ask host key", D.askCard({ prompt: "The authenticity of host ... (yes/no/[fingerprint])?", kind: "confirm" }).confirm, true);

    t.eq("error text", D.errorText("hint: do this\nerror: failed to push some refs\n"), "failed to push some refs");
    t.eq("error empty", D.errorText(""), "It did not work");
    t.eq("remember", D.remember([{ root: "/a" }, { root: "/b" }], "/b", "b", 5, 20).map((r) => r.root), ["/b", "/a"]);
    t.eq("tilde", D.tilde("/home/x/src", "/home/x"), "~/src");
    t.eq("signed: none", D.signatureOf("N", ""), null);
    t.eq("signed: good ssh", D.signatureOf("G", 'Good "git" signature for me@x.org with ED25519 key SHA256:abc').words, "Signed by me@x.org");
    t.eq("signed: cannot check", D.signatureOf("E", "").ink, "muted");
    t.eq("ci: words", D.ciWords({ runs: [{ state: "success" }, { state: "failure" }, { state: "success" }] }), "Checks: 1 failed · 2 passed");
    t.eq("ci: running", D.ciWords({ runs: [{ state: "success" }, { state: "pending" }] }), "Checks running — 1 of 2 done");
    t.eq("release: next after v1.4.2", D.nextVersion("v1.4.2"), "v1.4.3");
    t.eq("release: next after 2.0", D.nextVersion("2.0"), "2.1");
    t.eq("release: next after release-7", D.nextVersion("release-7"), "release-8");
    t.eq("release: v0.1.0 first", D.nextVersion(""), "v0.1.0");
    t.eq("release: notes from commits", D.notesFrom([{ subject: "Add b", sha: "abc" }], "v1"), "## Changes since v1\n\n- Add b (abc)\n");
    // servers of your own
    t.eq("server: an address as typed", D.hostOf("https://Git.Example.org/group/repo"), "git.example.org");
    t.eq("server: with a port and a user", D.hostOf("git@code.lan:3000"), "code.lan:3000");
    t.eq("server: not an address", D.hostOf("not a host!"), "");
    D.setServers([{ kind: "gitlab", host: "git.example.org", name: "Work" }, { kind: "nope", host: "x.org" }]);
    t.eq("server: after the three, by kind@host", D.FORGE_ORDER, ["github", "gitlab", "codeberg", "gitlab@git.example.org"]);
    t.eq("server: GitLab's words", D.FORGES["gitlab@git.example.org"].pulls, "Merge requests");
    t.eq("server: a remote on it is its", D.hubOf([{ name: "origin", fetch: "https://git.example.org/team/app.git" }]).forge,
      "gitlab@git.example.org");
    D.setServers([]);
    t.eq("server: removed, and the three as they were", [D.FORGE_ORDER, !!D.FORGES["gitlab@git.example.org"]],
      [["github", "gitlab", "codeberg"], false]);
    const M = (xs) => D.autoMessage(xs.map(([p, k]) => ({ path: p, kind: k })));
    t.eq("auto: one", M([["dir/README.md", "added"]]), "Add README.md");
    t.eq("auto: two added", M([["README.md", "added"], ["LICENSE", "added"]]), "Add README.md and LICENSE");
    t.eq("auto: mixed", M([["install", "modified"], ["LICENSE", "deleted"]]), "Update install, remove LICENSE");
    t.eq("auto: many", M(["a.qml", "b.js", "c.js", "d.js", "e.js"].map((p) => [p, "modified"])), "Update a.qml, b.js, c.js and 2 more");
    t.eq("auto: counts when long", M(Array.from({ length: 40 }, (_, i) => ["a-rather-long-file-name-" + i + ".qml", i % 2 ? "added" : "modified"])),
      "Update 20 files, add 20 files");
    t.eq("auto: nothing", M([]), "");

    const TST = { branch: { head: "main" }, staged: [{ path: "x/y/z/deep.txt", kind: "modified" }],
      unstaged: [{ path: "a/b.qml", kind: "modified" }, { path: "a/c/d.js", kind: "modified" }, { path: "top.md", kind: "modified" }],
      untracked: [{ path: "a/new.txt" }], conflicts: [] };
    const tr = D.treeRows(D.sections(TST), {});
    t.eq("tree rows", tr.map((r) => r.head ? "#" + r.id : "  ".repeat(r.depth) + r.name + (r.isDir ? "/" : "") + (r.guide >= 0 ? " " + r.guide : "")),
      ["#unstaged", "a/", "  c/ 3", "    d.js 3", "  b.qml 3", "  new.txt 1", "top.md", "#staged", "x/y/z/", "  deep.txt 0"]);
    t.eq("tree dir knows its files", [tr[1].count, tr[1].paths.slice().sort(), tr[1].untracked], [3, ["a/b.qml", "a/c/d.js", "a/new.txt"], ["a/new.txt"]]);
    t.eq("tree closed", D.treeRows(D.sections(TST), { "unstaged:a": true }).map((r) => r.name || r.id), ["unstaged", "a", "top.md", "staged", "x/y/z", "deep.txt"]);

    const rem = (name, url) => ({ name: name, fetch: url, push: url });
    t.eq("hub: upstream first", D.hubOf([rem("origin", "git@github.com:me/x.git"), rem("upstream", "https://github.com/them/x")]).full, "them/x");
    t.eq("hub: origin", D.hubOf([rem("origin", "git@github.com:me/x.git")]), { remote: "origin", host: "github.com", full: "me/x", web: "https://github.com/me/x", forge: "github" });
    t.eq("hub: upstream on codeberg", D.hubOf([rem("upstream", "https://codeberg.org/a/b"), rem("origin", "https://github.com/me/x")]).forge, "codeberg");
    t.eq("hub: gitlab subgroup", D.hubOf([rem("origin", "git@gitlab.com:grp/sub/x.git")]).full, "grp/sub/x");
    t.eq("hub: none", D.hubOf([rem("origin", "https://git.example.org/a/b")]), null);
    t.eq("forge words", [D.FORGES.gitlab.pulls, D.forgeOfHost("CODEBERG.org").name], ["Merge requests", "Codeberg"]);
    t.eq("seconds of iso", D.secondsOf("1970-01-02T00:00:00Z"), 86400);
    t.eq("seconds of nothing", D.secondsOf(null), 0);
    t.eq("mark merged", D.forgeMark({ pull: true, state: "merged" }).word, "Merged");
    t.eq("mark draft", D.forgeMark({ pull: true, state: "open", draft: true }).ink, "muted");
    t.eq("mark issue closed", D.forgeMark({ pull: false, state: "closed" }).word, "Closed");
    t.eq("md comments", D.mdOf("a\r\n<!-- template -->\n\n\n\nb"), "a\n\nb");
    t.eq("md picture", D.mdOf("see ![shot](https://x/y.png \"t\")"), "see [shot](https://x/y.png)");
    t.eq("md img tag", D.mdOf('<img width="5" src="https://x/z.png">'), "[picture](https://x/z.png)");
    t.eq("plain", D.plainOf("## Why\n\nIt **breaks** on `x` — see [the log](https://l)\n\n> quoted"), "Why\nIt breaks on x — see the log\nquoted");
    t.eq("hub: own prefers origin", D.hubOf([rem("origin", "git@github.com:me/x.git"), rem("upstream", "https://github.com/them/x")], true).full, "me/x");
    t.eq("attention: clean", D.attentionOf({ changed: 0, ahead: 0, behind: 0, conflicts: 0, state: null, branch: "main", upstream: "origin/main", oid: "a", remotes: [{}] }, null), []);
    t.eq("attention: words", D.attentionOf({ changed: 2, ahead: 1, behind: 3, conflicts: 0, state: { op: "rebase" }, branch: "main", upstream: null, oid: "a", remotes: [{}] },
      { state: "failure" }).map((a) => a.word), ["rebase under way", "2 changed", "↑1 to push", "↓3 to pull", "not published", "checks failing"]);
    // underlined headings (GitHub's other way to write one) and the places
    // kept for the hairlines under big headings and dividers
    const R = D.RULE_MARK;
    t.eq("md underline: - a heading, ruled", D.mdLinesOf("Intro\n\nAdded\n-\n- a thing"), "Intro\n\n## Added\n" + R + "\n\n- a thing");
    t.eq("md underline: = a title, lines joined", D.mdLinesOf("Big\nname\n===\ntext"), "# Big name\n" + R + "\n\ntext");
    t.eq("md # heading ruled, ### not", D.mdLinesOf("## A\n\n### B"), "## A\n" + R + "\n\n\n### B");
    t.eq("md divider under a heading: its one line", D.mdLinesOf("## A\n\n---\n\nb"), "## A\n" + R + "\n\n\nb");
    t.eq("md blank rows are room by blocks too", D.mdLinesOf("- a\n\n### B\n\n\nc"), "- a\n\n\u00a0\n\n### B\n\n\u00a0\n\n\u00a0\n\nc");
    t.eq("md divider under words ends them", D.mdLinesOf("a\n***"), "a\n\n" + R + "\n");
    t.eq("plain: underlines gone", D.plainOf("Added\n-\n- x"), "Added\n- x");
    t.eq("md details", D.mdOf("<details><summary>Log</summary>\n\nline</details>"), "Log\n\nline");
  },
};
