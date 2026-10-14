// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The Store's rules: sections, search, the front page, and the keys.

"use strict";

function app(name, o) {
  return Object.assign({ key: "arch:" + name, source: "arch", repo: "extra", id: name, pkg: name.toLowerCase(),
    name: name, summary: "", dev: "", cats: [], keywords: [], pop: 0, polished: true, installed: false }, o || {});
}

module.exports = {
  module: "ceres/store.js",
  cases: (S, t) => {
    const gimp = app("GIMP", { cats: ["Graphics"], summary: "image editor", keywords: ["photo"], pop: 50 });
    const krita = app("Krita", { cats: ["Graphics"], pop: 10 });
    const vlc = app("VLC", { cats: ["AudioVideo", "Player"], pop: 53, installed: true });
    const avahi = app("Avahi", { cats: ["Network"], pop: 96, polished: false });
    const apps = [avahi, vlc, gimp, krita];

    // ── sections ───────────────────────────────────────────────────────────
    t.ok("GIMP is Create", S.inSection(gimp, "create"));
    t.ok("and not Play", !S.inSection(gimp, "play"));
    t.ok("VLC is Listen & Watch by AudioVideo", S.inSection(vlc, "watch"));
    t.ok("installed is what is installed", S.inSection(vlc, "installed") && !S.inSection(gimp, "installed"));
    t.eq("polished first, then by popularity", S.sectionApps([avahi, app("Net", { cats: ["Network"] })], "internet").map(a => a.name),
      ["Net", "Avahi"]);
    t.eq("an unknown section is Discover", S.section("nope")[0], "discover");

    // ── sources ───────────────────────────────────────────────────────────
    t.eq("Arch's mark", S.sourceGlyph(gimp), "");
    t.eq("Flathub's mark", S.sourceGlyph({ source: "flatpak" }), "");
    t.eq("Arch, with its repo", S.sourceLabel(app("X", { repo: "multilib" })), "Arch · multilib");

    // ── search ────────────────────────────────────────────────────────────
    t.eq("by name", S.search(apps, "krita").map(a => a.name), ["Krita"]);
    t.eq("by keyword", S.search(apps, "photo").map(a => a.name), ["GIMP"]);
    t.eq("every word must be found", S.search(apps, "gimp video").length, 0);
    t.eq("nothing typed, nothing found", S.search(apps, "  ").length, 0);
    const two = [app("Image Viewer", { summary: "views a gimp file", pop: 90 }), gimp];
    t.eq("a name hit beats a summary hit", S.search(two, "gimp")[0].name, "GIMP");

    // ── the front page ────────────────────────────────────────────────────
    const shot = (o) => Object.assign({ shot: "u" }, o);
    const pics = [shot(gimp), shot(krita), vlc, app("Lutris", { cats: ["Game"], pop: 40, shot: "u" })];
    t.eq("features: polished, not installed, with a picture", S.features(pics, 0, 5).map(a => a.name), ["GIMP", "Krita", "Lutris"]);
    t.eq("they turn over by the day", S.features(pics, 1, 1).map(a => a.name), ["Krita"]);
    t.eq("none left, none shown", S.features([vlc], 0, 5), []);
    t.eq("an app's first section", S.sectionOf(gimp)[0], "create");
    const plumbing = app("Volume Control", { cats: ["AudioVideo", "Settings"], shot: "u", pop: 99 });
    t.ok("an app people look for is featured", S.features([shot(gimp)], 0, 1).length === 1);
    t.eq("a desktop's plumbing is not", S.features([app("NetworkManager", { cats: ["Settings"], shot: "u" })], 0, 1), []);
    t.eq("artwork: one per section, none featured", S.stories(pics, [pics[0]], 4).map(a => a.name), ["Krita", "Lutris"]);
    const many = [];
    for (let i = 0; i < 9; i++) many.push(app("G" + i, { cats: ["Development"], pop: 50 - i }));
    const sh = S.shelves(many, 3, [], 2);
    t.eq("most used: two rows of three", sh[0].apps.length, 6);
    t.eq("then Develop, with what is left, whole rows only", sh[1].apps.map(a => a.name), ["G6", "G7", "G8"]);
    t.ok("no app twice", new Set(sh.flatMap(s => s.apps.map(a => a.key))).size === 9);
    t.ok("what is featured is not on a shelf too", !S.shelves(many, 3, [many[0]], 2).some(s => s.apps.includes(many[0])));
    t.eq("too few for a row: no shelf", S.shelves([gimp], 3, [], 2).length, 0);
    const games = [];
    for (let i = 0; i < 4; i++) games.push(app("P" + i, { cats: ["Game"], shot: "u" }));
    const play = S.shelves(games, 9, [], 1, 4).find(s => s.key === "play");
    t.ok("Play is pictures", play && play.art && play.apps.length === 4);
    const fl = [2, 0, 1, 3, 4, 5].map(i => app("F" + i, { source: "flatpak", trend: i, pop: 1, cats: ["Utility"] }));
    const trending = S.shelves(fl, 3, [], 1).find(s => s.title === "Trending on Flathub");
    t.ok("trending on Flathub, when it is here", !!trending);
    t.eq("in Flathub's order", trending ? trending.apps.map(a => a.name) : [], ["F0", "F1", "F2"]);
    t.eq("a count, short", [S.count(52714), S.count(1234567), S.count(840), S.count(1530)], ["53K", "1.2M", "840", "1.5K"]);
    t.eq("a size, split", S.sizeParts("84.12 MiB"), ["84.1", "MiB"]);
    t.eq("a big one, whole", S.sizeParts("312.6 MiB"), ["313", "MiB"]);

    // ── the keys ──────────────────────────────────────────────────────────
    t.eq("right", S.step(0, 1, 10), 1);
    t.eq("down a row", S.step(1, 4, 10), 5);
    t.eq("down past the end stays", S.step(8, 4, 10), 8);
    t.eq("up from the top row stays", S.step(2, -4, 10), 2);
    t.eq("left from the first stays", S.step(0, -1, 10), 0);
    t.eq("right from the last stays", S.step(9, 1, 10), 9);

    // ── Flatpak ───────────────────────────────────────────────────────────
    const ri = S.remoteInfo("Spotify - Online\n\n            ID: com.spotify.Client\n       Version: 1.2.95\n Download Size: 9.8 MB\nInstalled Size: 14.1 MB\n");
    t.eq("remote-info read", [ri["Version"], ri["Download Size"], ri["Installed Size"]], ["1.2.95", "9.8 MB", "14.1 MB"]);
    const meta = "[Application]\nname=x\n\n[Context]\nshared=ipc;network;\nsockets=x11;wayland;\ndevices=dri;\nfilesystems=xdg-pictures:ro;host;\n\n[Session Bus Policy]\nx=talk\n";
    const perms = S.permissions(meta);
    t.eq("all your files first", perms[0], { text: "Can read and change all your files", level: "high" });
    t.ok("the network said", perms.some(p => p.text === "The network"));
    t.ok("pictures, to read", perms.some(p => p.text === "Your Pictures directory, to read"));
    t.ok("drawing and sound are not news", !perms.some(p => /x11|wayland|dri/i.test(p.text)));
    t.eq("home read-only is not high", S.permissions("[Context]\nfilesystems=home:ro;\n")[0], { text: "Can read your home directory", level: "mid" });
    t.eq("a sealed app asks for nothing", S.permissions("[Context]\nsockets=wayland;\n"), []);

    // ── one app, more than one source ─────────────────────────────────────
    const spot = app("Spotify", { source: "aur", repo: "aur", pkg: "spotify",
      others: [{ source: "flatpak", repo: "flathub", pkg: "com.spotify.Client", verified: true, installs: 100, installed: true, scope: "user" }] });
    const fs = S.asSource(spot, "flatpak");
    t.eq("as Flathub's", [fs.source, fs.pkg, fs.repo, fs.installed, fs.scope], ["flatpak", "com.spotify.Client", "flathub", true, "user"]);
    t.eq("and the AUR is then its other", fs.others.map(o => o.source), ["aur"]);
    t.eq("its own source is itself", S.asSource(spot, "aur"), spot);
    t.eq("the switch, own first", S.sources(spot).map(x => x[0]), ["aur", "flatpak"]);
    t.has("says which is here", S.sources(spot)[1][1], "installed");
    t.eq("one source, no switch", S.sources(gimp), []);
    t.eq("more than one: the layers mark", S.cardGlyph(spot), "\uDB80\uDF28");
    t.eq("one: its source's", S.cardGlyph(gimp), "\uF303");
    t.eq("an install from the Flathub side goes to Flathub", S.asSource(spot, "flatpak").source, "flatpak");

    // ── the page ──────────────────────────────────────────────────────────
    t.eq("links in the page's order", S.links({ donation: "d", homepage: "h" }).map(l => l.label), ["Website", "Donate"]);
    t.eq("proprietary said plainly", S.licence("LicenseRef-proprietary=https://x"), "Proprietary");
    t.eq("a date", S.releaseDate(1776384000), "17 April 2026");
    t.eq("an install is a Packages row", S.changeRow(gimp, false),
      { state: "avail", name: "gimp", size: 0, repo: "extra", version: "", installed: false, aur: false });
    t.ok("a removal is an installed one", S.changeRow(vlc, true).installed);
    const zen = app("Zen", { source: "aur", repo: "aur", pkg: "zen-browser-bin" });
    t.eq("an AUR app is an AUR row", [S.changeRow(zen, false).aur, S.changeRow(zen, false).repo], [true, "aur"]);
    t.eq("with the AUR's mark", S.sourceGlyph(zen), "\uF415");
    t.eq("and its name", S.sourceLabel(zen), "AUR");
  }
};
