// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// terminus' network places, the pure half: typed addresses, names,
// packages, the saved list and the sidebar's rows.

"use strict";

module.exports = {
  module: "terminus/network.js",
  cases: (N, t) => {
    t.eq("as typed", N.normalize("smb://nas/share/"), "smb://nas/share");
    t.eq("windows' way", N.normalize("\\\\nas\\media"), "smb://nas/media");
    t.eq("two slashes", N.normalize("//nas/media"), "smb://nas/media");
    t.eq("scp's way", N.normalize("me@box:/srv/data"), "sftp://me@box/srv/data");
    t.eq("scp, relative", N.normalize("box:notes"), "sftp://box/notes");
    t.eq("https is webdav", N.normalize("https://cloud.example/remote.php/dav"), "davs://cloud.example/remote.php/dav");
    t.eq("bare server", N.normalize("nas/share"), "smb://nas/share");
    t.eq("unknown scheme", N.normalize("gopher://x"), "");
    t.eq("nothing", N.normalize("   "), "");

    t.eq("parse", N.parse("sftp://me@box:2222/srv"), { scheme: "sftp", user: "me", host: "box", port: 2222, path: "/srv" });
    t.eq("not an address", N.parse("hello"), null);
    t.eq("label from path", N.label({ uri: "smb://nas/media" }), "media on nas");
    t.eq("label, own name", N.label({ uri: "smb://nas/media", name: "Films" }), "Films");
    t.eq("label, host only", N.label({ uri: "sftp://box" }), "box");
    t.eq("kind", [N.kindWords("smb://a/b"), N.kindWords("davs://a")], ["Windows share", "WebDAV"]);
    t.eq("packages", N.packagesFor("smb://a/b"), ["gvfs", "gvfs-smb"]);
    t.eq("packages, sftp", N.packagesFor("sftp://a"), ["gvfs"]);
    t.eq("same place", N.sameUri("SMB://NAS/share/", "smb://nas/share"), true);
    t.eq("ssh is sftp", N.sameUri("ssh://box/x", "sftp://me@box/x"), true);
    t.eq("other share", N.sameUri("smb://nas/a", "smb://nas/b"), false);

    let places = N.parsePlaces('[{"uri":"smb://nas/a","name":"A","password":"no"},{"bad":1}]');
    t.eq("parsed, no password kept", places, [{ uri: "smb://nas/a", name: "A", user: "", domain: "" }]);
    places = N.savePlace(places, { uri: "smb://NAS/a/", name: "Again" });
    t.eq("saving the same place replaces it", places.map((p) => p.name), ["Again"]);
    places = N.savePlace(places, { uri: "sftp://box/x", user: "me" });
    const rows = N.rows(places, [
      { uri: "sftp://me@box/x", name: "x on box", path: "/run/user/1000/gvfs/sftp:host=box,user=me/x" },
      { uri: "ftp://other/", name: "other", path: "/run/user/1000/gvfs/ftp:host=other" }
    ]);
    t.eq("rows", rows.map((r) => [r.saved, r.path !== ""]), [[true, false], [true, true], [false, true]]);
    t.eq("dropped", N.dropPlace(places, "smb://nas/a").length, 1);
    t.eq("fail words", N.failWords({ why: "auth" }), "The server did not take that name and password");
  }
};
