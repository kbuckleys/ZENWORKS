// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CALYPSO'S WINDOW HALF: shelves, search, the list's headings, marks, codes,
// sign-in forms. (The vault half is oracle/tests/calypso-core.py.)

"use strict";

const ITEMS = [
  { acct: "a", id: "1", title: "GitHub", sub: "ada", kind: "login", host: "github.com", folder: "Work", tags: ["dev"], fav: false, updated: 1760000000, totp: true },
  { acct: "a", id: "2", title: "github notes", sub: "", kind: "note", host: "", folder: "", tags: [], fav: false, updated: 1750000000, totp: false },
  { acct: "b", id: "1", title: "Visa Gold", sub: "", kind: "card", host: "", folder: "Work / Bank", tags: [], fav: true, updated: 1700000000, totp: false },
  { acct: "b", id: "9", title: "x.com", sub: "ada", kind: "login", host: "x.com", folder: "", tags: ["dev", "social"], fav: false, updated: 0, totp: null },
  { acct: "b", id: "8", title: "Dropbox", sub: "ada@example.com", kind: "login", host: "dropbox.com", folder: "", tags: [], fav: false, updated: 1760000100, totp: false },
];

module.exports = {
  module: "calypso/calypso.js",
  cases: (C, t) => {
    const ids = (rows) => rows.map((r) => r.acct + r.id);
    t.eq("all, by name", ids(C.shelve(ITEMS, { shelf: "all" }, "", {}, "name")), ["b8", "a1", "a2", "b1", "b9"]);
    t.eq("recent first", ids(C.shelve(ITEMS, { shelf: "all" }, "", {}, "recent")), ["b8", "a1", "a2", "b1", "b9"]);
    t.eq("favorites: the platform's and calypso's", ids(C.shelve(ITEMS, { shelf: "fav" }, "", { "a\u00011": true }, "name")), ["a1", "b1"]);
    t.eq("one-time passwords: known ones only", ids(C.shelve(ITEMS, { shelf: "totp" }, "", {}, "name")), ["a1"]);
    t.eq("one account", ids(C.shelve(ITEMS, { acct: "b" }, "", {}, "name")), ["b8", "b1", "b9"]);
    t.eq("a folder holds its subfolders", ids(C.shelve(ITEMS, { folder: "Work" }, "", {}, "name")), ["a1", "b1"]);
    t.eq("a tag", ids(C.shelve(ITEMS, { tag: "dev" }, "", {}, "name")), ["a1", "b9"]);
    t.eq("search: title start beats a username", ids(C.shelve(ITEMS, {}, "git", {}, "name")), ["a1", "a2"]);
    t.eq("search: every word somewhere", ids(C.shelve(ITEMS, {}, "ada drop", {}, "name")), ["b8"]);
    t.eq("search: a site, its title first", ids(C.shelve(ITEMS, {}, "x.com", {}, "name")), ["b9", "b8"]);
    t.eq("count", C.count(ITEMS, { kind: "login" }, {}), 3);
    t.eq("folders, nested under their parent", C.folders(ITEMS).map((f) => f.name + ":" + f.count + ":" + f.depth),
         ["Work:1:0", "Work / Bank:1:1"]);
    t.eq("tags", C.tags(ITEMS).map((x) => x.name + x.count), ["dev2", "social1"]);
    t.eq("heading by letter", ["GitHub", "1Pass", "étoile"].map((s) => C.sectionOf({ title: s }, "name", 0)), ["G", "0–9", "#"]);
    const now = new Date(2026, 9, 11, 12).getTime();
    t.eq("heading by age", [new Date(2026, 9, 11, 1), new Date(2026, 9, 10, 23), new Date(2026, 9, 7), new Date(2026, 6, 1)]
      .map((d) => C.ageWord(d.getTime() / 1000, now)), ["Today", "Yesterday", "This week", "July 2026"]);
    t.eq("undated", C.ageWord(0, now), "Undated");
    t.eq("a site's mark, whole domains whole", [C.markOf(ITEMS[0]).brand, C.markOf(ITEMS[4]).glyph === C.markOf(ITEMS[3]).glyph], [true, false]);
    t.eq("a visa", C.markOf(ITEMS[2]).glyph, "");
    t.eq("a note wears its kind", C.markOf(ITEMS[1]).glyph, C.kindOf("note").glyph);
    t.eq("codes in halves", [C.codeShown("123456"), C.codeShown("12345678"), C.codeShown("1234567")], ["123 456", "1234 5678", "1234 567"]);
    t.eq("dots", C.dots(3).length, 8);
    t.eq("a key is per account", C.keyOf(ITEMS[0]) === C.keyOf(ITEMS[2]), false);
    t.eq("actions: no user, no typing it", C.actionEnabled("user", ITEMS[0]), true);
    t.eq("actions: no code where there is none", C.actionEnabled("totp", ITEMS[4]), false);
    t.eq("actions: a code not yet known is offered", C.actionEnabled("copytotp", ITEMS[3]), true);
    t.eq("highlight", C.highlight("GitHub <x>", "hub", "#f00"), "Git<b><span style=\"color:#f00;\">Hub</span></b> &lt;x&gt;");
    t.eq("every platform but Proton's browser sign-in has a form", C.PLATFORM_ORDER.filter((k) => k !== "proton").every((k) => C.setupForm(k).fields.length > 0), true);
    t.eq("proton signs in two ways", C.setupForm("proton", "here").fields[0].key, "email");
    t.eq("names: given", C.accountName("bitwarden", { name: " Work " }, []), "Work");
    t.eq("names: a clash says who", C.accountName("bitwarden", { email: "a@b.c" }, ["Bitwarden"]), "Bitwarden · a@b.c");
    const D = { id: "i1", kind: "login", title: "GitHub", folder: "Work", fav: true, tags: ["a", "b"], notes: "n",
      sections: [{ title: "", fields: [
        { ref: "username", label: "username", kind: "text", value: "ada", secret: false },
        { ref: "password", label: "password", kind: "secret", value: "", secret: true }] },
        { title: "websites", fields: [{ ref: "url0", label: "website", kind: "url", value: "https://github.com", secret: false }] },
        { title: "more", fields: [{ ref: "c:0", label: "pin", kind: "secret", value: "", secret: true },
                                  { ref: "c:1", label: "x", kind: "text", value: "y", secret: false }] },
        { title: "password history", fields: [{ ref: "h:0", label: "old", kind: "secret", value: "", secret: true }] }] };
    const st = C.editState(D, "", "a");
    t.eq("edit: an unrevealed secret is not known", [st.std.password.known, st.std.username.value, st.std.totp.had], [false, "ada", false]);
    t.eq("edit: customs, history left out", st.custom.map((c) => c.ref + c.known), ["c:0false", "c:1true"]);
    st.std.username.value = "lovelace";
    const dr = C.draftOf(st);
    t.eq("draft: kept is null, changed is sent", [dr.fields.password, dr.fields.username, dr.fields.totp], [null, "lovelace", ""]);
    t.eq("draft: tags split, urls kept", [dr.tags, dr.urls], [["a", "b"], ["https://github.com"]]);
    t.eq("draft: a custom kept as it was", dr.custom[0], { ref: "c:0", label: "pin", value: null, hidden: true });
    const fresh = C.editState(null, "card", "b", "Bank");
    t.eq("new: the kind's fields, empty, known", [Object.keys(fresh.std).length, fresh.std.number.known, fresh.folder], [5, true, "Bank"]);
    const flags = {}; flags["a\u00011"] = ["weak"]; flags["b\u00019"] = ["reused", "pwned"];
    t.eq("watchtower: flagged ones", ids(C.shelve(ITEMS, { shelf: "watch" }, "", {}, "name", flags)), ["a1", "b9"]);
    flags["b\u00018"] = ["no2fa"];
    t.eq("watchtower: a hint alone is not a problem", ids(C.shelve(ITEMS, { shelf: "watch" }, "", {}, "name", flags)), ["a1", "b9"]);
    t.eq("watchtower: but is on its own card", ids(C.shelve(ITEMS, { shelf: "watch", audit: "no2fa" }, "", {}, "name", flags)), ["b8"]);
    t.eq("watchtower: one problem", ids(C.shelve(ITEMS, { shelf: "watch", audit: "pwned" }, "", {}, "name", flags)), ["b9"]);
    t.eq("can", [C.canCreate({ can: { create: ["login"] } }, "card"), C.deleteWord({ can: { delete: "trash" } })], [false, "Move to Trash"]);
    t.eq("names: a database by its file", C.accountName("keepass", { path: "/x/Home.kdbx" }, []), "Home");
  },
};
