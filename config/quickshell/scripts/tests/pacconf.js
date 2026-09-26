// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ceres' pacman.conf editor: that an edit touches the line it means and no
// other, that a commented line comes back rather than a duplicate being
// added, and that SigLevel reads the way pacman reads it.

"use strict";

const FILE = [
  "# my banner",
  "[options]",
  "ILoveCandy",
  "#RootDir\t\t     = /",
  "HoldPkg\t\t\t     = pacman glibc",
  "#XferCommand\t\t     = /usr/bin/curl -L -C - -f -o %o %u",
  "#XferCommand\t\t     = /usr/bin/wget --passive-ftp -c -O %o %u",
  "#IgnorePkg\t\t     =",
  "#VerbosePkgLists",
  "ParallelDownloads = 5",
  "SigLevel\t\t     = Required DatabaseOptional",
  "",
  "# the testing repositories, on purpose",
  "[core-testing]",
  "Include = /etc/pacman.d/mirrorlist",
  "",
  "[core]",
  "Include = /etc/pacman.d/mirrorlist",
  "",
  "#[multilib]",
  "#Include = /etc/pacman.d/mirrorlist",
  "",
  "[my repo]",
  "SigLevel = Optional TrustAll",
  "Server = file:///home/b/my packages",
  ""
].join("\n");

module.exports = {
  module: "ceres/pacconf.js",
  cases: (P, t) => {
    const L = P.lines(FILE);
    t.eq("the file round-trips untouched", P.text(L), FILE);

    // ── reading ───────────────────────────────────────────────────────────
    t.eq("a flag that is on", P.getOption(L, "ILoveCandy").value, true);
    t.eq("a commented flag is off", P.getOption(L, "VerbosePkgLists").set, false);
    t.eq("a value", P.getOption(L, "HoldPkg").value, "pacman glibc");
    t.eq("a commented value is unset", P.getOption(L, "XferCommand").set, false);
    t.eq("a key is not a prefix of another", P.getOption(L, "Color").set, false);

    // ── writing: the line itself ──────────────────────────────────────────
    const on = P.setOption(L, "VerbosePkgLists", true);
    t.eq("a flag switched on uncomments its line", on[8], "VerbosePkgLists");
    t.eq("and adds nothing", on.length, L.length);
    const off = P.setOption(L, "ILoveCandy", false);
    t.eq("switched off, it is commented out, not deleted", off[2], "#ILoveCandy");
    const hp = P.setOption(L, "HoldPkg", "pacman glibc linux");
    t.eq("a value is replaced in place, spacing kept", hp[4], "HoldPkg\t\t\t     = pacman glibc linux");
    const xf = P.setOption(L, "XferCommand", "/usr/bin/aria2c %u");
    t.eq("the first commented line comes back with the new value", xf[5], "XferCommand\t\t     = /usr/bin/aria2c %u");
    t.eq("the second example stays a comment", xf[6], L[6]);
    const ig = P.setOption(L, "IgnorePkg", "linux*");
    t.eq("an empty commented value is filled", ig[7], "IgnorePkg\t\t     = linux*");
    const col = P.setOption(L, "Color", true);
    t.eq("a setting never mentioned joins its section", col[11], "Color");
    t.eq("before the blank line that closes it", col[12], "");
    t.eq("a value unset is commented", P.setOption(L, "ParallelDownloads", "")[9], "#ParallelDownloads = 5");
    t.eq("unset then set is the same line back",
      P.setOption(P.setOption(L, "ParallelDownloads", ""), "ParallelDownloads", "5")[9], "ParallelDownloads = 5");
    t.eq("nothing else moved", P.changedCount(L, hp), 1);

    // ── signatures ────────────────────────────────────────────────────────
    const s = P.parseSig("Required DatabaseOptional");
    t.eq("packages required", s.pkg.check, "Required");
    t.eq("databases optional", s.db.check, "Optional");
    t.eq("trust defaults to TrustedOnly", s.db.trust, "TrustedOnly");
    t.eq("written back the same way", P.formatSig(s), "Required DatabaseOptional");
    t.eq("later words win", P.parseSig("Never Required").pkg.check, "Required");
    t.eq("a Package word touches packages only", P.parseSig("Optional PackageRequired").db.check, "Optional");
    t.eq("TrustAll for both", P.formatSig(P.parseSig("Optional TrustAll")), "Optional TrustAll");
    t.eq("trust that differs is spelled out",
      P.formatSig({ pkg: { check: "Required", trust: "TrustAll" }, db: { check: "Required", trust: "TrustedOnly" } }),
      "Required TrustAll DatabaseTrustedOnly");
    t.eq("a repository starts from the default it inherits",
      P.parseSig("PackageOptional", P.parseSig("Required DatabaseOptional")).db.check, "Optional");

    // ── repositories ──────────────────────────────────────────────────────
    const R = P.repos(L);
    t.eq("every repository, in order", R.map(r => r.name).join(), "core-testing,core,multilib,my repo");
    t.eq("switched off is read", R[2].enabled, false);
    t.eq("and still knows its Include", R[2].Include.join(), "/etc/pacman.d/mirrorlist");
    t.eq("a custom one's settings", R[3].SigLevel + " | " + R[3].Server.join(), "Optional TrustAll | file:///home/b/my packages");
    t.ok("Arch's own are marked", R[0].official && !R[3].official);

    const ml = P.setRepoEnabled(L, "multilib", true);
    t.eq("switching on uncomments the header", ml[19], "[multilib]");
    t.eq("and its directives", ml[20], "Include = /etc/pacman.d/mirrorlist");
    t.eq("and nothing else", P.changedCount(L, ml), 2);
    t.eq("and back", P.text(P.setRepoEnabled(ml, "multilib", false)), FILE);

    const mv = P.moveRepo(L, "core", -1);
    t.eq("moving up swaps with the one above", P.repos(mv).map(r => r.name).slice(0, 2).join(), "core,core-testing");
    t.eq("the note between them stays where it was", mv[12], "# the testing repositories, on purpose");
    t.eq("and moving back restores the file", P.text(P.moveRepo(mv, "core", 1)), FILE);
    t.eq("the first cannot move up", P.moveRepo(L, "core-testing", -1), L);

    const sv = P.setRepoKey(L, "my repo", "Server", ["https://a/$arch", "https://b/$arch"]);
    t.eq("servers: one line each", P.repoNamed(sv, "my repo").Server.join(), "https://a/$arch,https://b/$arch");
    const sg = P.setRepoKey(L, "core", "SigLevel", "Required");
    t.eq("a new SigLevel goes under the header", sg[17], "SigLevel = Required");
    t.eq("and the Include follows it", sg[18], "Include = /etc/pacman.d/mirrorlist");
    t.eq("a switched-off repository is not edited", P.setRepoKey(L, "multilib", "Usage", "Sync"), L);

    // ── adding and removing ───────────────────────────────────────────────
    t.eq("a name must be a name", P.validRepoName("a b", L), "letters, digits and . _ + - only");
    t.eq("local is reserved", P.validRepoName("local", L), "“local” is reserved");
    t.eq("no duplicates", P.validRepoName("core", L), "there is already a [core]");
    t.eq("a good name", P.validRepoName("chaotic-aur", L), "");
    const add = P.addRepo(L, "chaotic-aur", "https://x/$repo/$arch", "Required DatabaseOptional");
    t.eq("added at the end", P.repos(add).pop().name, "chaotic-aur");
    t.eq("with its settings", P.repoNamed(add, "chaotic-aur").SigLevel, "Required DatabaseOptional");
    t.eq("removed again, the file is as it was", P.text(P.removeRepo(add, "chaotic-aur")), P.text(L));
    t.eq("Arch's own are never removed", P.removeRepo(L, "core"), L);

    // ── the review ────────────────────────────────────────────────────────
    const rv = P.readReviewOut("--- a\n+++ b\n@@was\n@@now\n@@exit 0\n");
    t.ok("a clean parse is ok", rv.ok && rv.diff.indexOf("+++ b") >= 0);
    const bad = P.readReviewOut("@@was\n@@now\nwarning: config file /d, line 27: directive 'Bogus' in section 'options' not recognized.\n@@exit 0\n");
    t.ok("a warning is a refusal, though pacman-conf exits 0", !bad.ok);
    t.eq("and says why", bad.problems[0], "warning: config file /d, line 27: directive 'Bogus' in section 'options' not recognized.");
    const old = P.readReviewOut("@@was\nwarning: config file /etc/pacman.conf, line 9: directive 'Old' in section 'options' not recognized.\n"
      + "@@now\nwarning: config file /d, line 10: directive 'Old' in section 'options' not recognized.\n@@exit 0\n");
    t.ok("a warning the file already had does not block", old.ok);
    t.has("the draft path is quoted", P.reviewCommand("/home/b/my cache/draft"), "'/home/b/my cache/draft'");
    t.ok("every option has help", P.SCHEMA.every(s => s.help && s.label && s.group));
  }
};
