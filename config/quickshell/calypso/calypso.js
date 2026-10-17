.pragma library
// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CALYPSO'S PURE HALF — what the window and Quick Access do with the
// daemon's answers before drawing them: which platform looks like what,
// which items a shelf holds, the order and the headings of the list, a
// site's mark, a code in two halves, a time in words, the sign-in each
// platform asks. No vault here (that is calypso/core), no QML state; tested
// by oracle/tests/calypso.js.

// ── THE PLATFORMS ──────────────────────────────────────────────────────────
// What each looks like here; what each IS (its CLI, its package) is the
// daemon's (`platforms`). `ink` is a Zenon slot name, read as Zenon[ink], so
// a theme change reaches it.
const PLATFORMS = {
  bitwarden:   { name: "Bitwarden",   glyph: "",           ink: "cyan",
                 tagline: "Bitwarden or Vaultwarden, through rbw" },
  onepassword: { name: "1Password",   glyph: "\u{F0881}",        ink: "blue",
                 tagline: "Your 1Password account, through op" },
  proton:      { name: "Proton Pass", glyph: "\u{F099D}",        ink: "magenta",
                 tagline: "Proton Pass, through pass-cli" },
  keepass:     { name: "KeePassXC",   glyph: "\u{F0AAA}",        ink: "green",
                 tagline: "A .kdbx database of your own" },
  pass:        { name: "pass",        glyph: "\u{F07F5}",        ink: "sand",
                 tagline: "The standard Unix password store, on gpg" },
  gopass:      { name: "gopass",      glyph: "\u{F1574}",        ink: "yellow",
                 tagline: "gopass' store, on gpg" },
};
const PLATFORM_ORDER = ["bitwarden", "onepassword", "proton", "keepass", "pass", "gopass"];

function platform(kind) {
  return PLATFORMS[kind] || { name: kind, glyph: "", ink: "muted", tagline: "" };
}

// ── THE KINDS OF ITEM ──────────────────────────────────────────────────────
const KINDS = [
  { id: "login",    label: "Logins",        one: "Login",       glyph: "",    ink: "cyan" },
  { id: "password", label: "Passwords",     one: "Password",    glyph: "\u{F07F5}", ink: "blue" },
  { id: "card",     label: "Cards",         one: "Card",        glyph: "",    ink: "sand" },
  { id: "note",     label: "Secure notes",  one: "Secure note", glyph: "",    ink: "green" },
  { id: "identity", label: "Identities",    one: "Identity",    glyph: "",    ink: "magenta" },
  { id: "ssh",      label: "SSH keys",      one: "SSH key",     glyph: "\u{F030B}", ink: "yellow" },
  { id: "other",    label: "Other",         one: "Item",        glyph: "\u{F01D8}", ink: "muted" },
];

function kindOf(id) {
  for (const k of KINDS) if (k.id === id) return k;
  return KINDS[KINDS.length - 1];
}

// the shelves above the kinds
const SHELVES = [
  { id: "all",   label: "All items",          glyph: "\u{F0A6A}" },
  { id: "fav",   label: "Favorites",         glyph: "" },
  { id: "totp",  label: "One-time passwords", glyph: "\u{F097F}" },
  { id: "watch", label: "Watchtower",         glyph: "\u{F0565}" },
  { id: "trash", label: "Trash",              glyph: "" },
];

// ── WATCHTOWER'S WORDS ─────────────────────────────────────────────────────
// What each problem audit.py finds is called, what it means, and its ink.
const PROBLEMS = [
  { id: "pwned",    label: "Breached",        ink: "red",
    say: "Seen in known data breaches — change it everywhere it is used" },
  { id: "reused",   label: "Reused",          ink: "yellow",
    say: "The same password on more than one item: one leak opens them all" },
  { id: "weak",     label: "Weak",            ink: "yellow",
    say: "Short or predictable: easy to guess" },
  { id: "insecure", label: "Unsecured sites", ink: "magenta",
    say: "A website saved with http://, not https://" },
  { id: "old",      label: "Old",             ink: "blue",
    say: "Not changed for over two years" },
  { id: "no2fa",    label: "No one-time password", ink: "muted",
    say: "A login with no one-time password saved — turn on two-factor where the site has it" },
];
function problem(id) {
  for (const p of PROBLEMS) if (p.id === id) return p;
  return { id: id, label: id, ink: "muted", say: "" };
}

// ── WHAT EACH KIND OF ITEM HOLDS ───────────────────────────────────────────
// The editor's fields, in order, by the shared keys the daemon saves with
// (calypso/core/base.Provider.save). `secret` masked; `gen` gets the
// generator; `totp` a one-time password (scanned, pasted); `hint` the ghost.
const FIELDS = {
  login: [{ key: "username", label: "username" },
          { key: "password", label: "password", secret: true, gen: true },
          { key: "totp", label: "one-time password", secret: true, totp: true, hint: "otpauth:// or a secret" }],
  password: [{ key: "password", label: "password", secret: true, gen: true }],
  note: [],
  card: [{ key: "cardholder", label: "cardholder name" }, { key: "brand", label: "type", hint: "Visa" },
         { key: "number", label: "number", secret: true }, { key: "expiry", label: "expiry date", hint: "MM/YYYY" },
         { key: "code", label: "verification number", secret: true }],
  identity: [{ key: "title", label: "title", hint: "Ms" }, { key: "first", label: "first name" },
             { key: "middle", label: "middle name" }, { key: "last", label: "last name" },
             { key: "username", label: "username" }, { key: "company", label: "company" },
             { key: "email", label: "email" }, { key: "phone", label: "phone" },
             { key: "address1", label: "address" }, { key: "address2", label: "address line 2" },
             { key: "city", label: "city" }, { key: "state", label: "state" },
             { key: "postal", label: "postal code" }, { key: "country", label: "country" },
             { key: "ssn", label: "social security number", secret: true },
             { key: "passport", label: "passport number", secret: true },
             { key: "license", label: "license number", secret: true }],
  ssh: [{ key: "private", label: "private key", secret: true }, { key: "public", label: "public key" },
        { key: "fingerprint", label: "fingerprint" }],
};
function fieldsOf(kind) { return FIELDS[kind] || []; }

// A detail (or nothing, for a new item) → what the editor holds. A secret
// the window was never shown is `known: false`: it is sent back as null,
// "as it was", unless it is revealed or typed over.
function editState(d, kind, acct, folder) {
  const k = d ? d.kind : kind;
  const byRef = {};
  const custom = [], urls = [];
  for (const s of (d && d.sections) || [])
    for (const f of s.fields) {
      if (f.ref.indexOf("h:") === 0) continue;
      if (f.kind === "url") { urls.push(f.value); continue; }
      byRef[f.ref] = f;
    }
  const std = {};
  const keys = {};
  for (const f of fieldsOf(k)) {
    keys[f.key] = true;
    const have = byRef[f.key];
    std[f.key] = have ? { value: have.secret ? "" : have.value, known: !have.secret, had: true }
                      : { value: "", known: true, had: false };
  }
  for (const ref in byRef) {
    if (keys[ref]) continue;
    const f = byRef[ref];
    custom.push({ ref: ref, label: f.label, value: f.secret ? "" : f.value, known: !f.secret,
                  hidden: f.secret, totp: f.kind === "totp" });
  }
  return { id: d ? d.id : "", acct: acct || (d ? d.acct : ""), kind: k,
           title: d ? d.title : "", folder: d ? d.folder : (folder || ""),
           fav: d ? !!d.fav : false, tags: d ? (d.tags || []).join(", ") : "",
           notes: d ? d.notes || "" : "", std: std, urls: urls.length ? urls : (k === "login" ? [""] : []),
           custom: custom };
}

// What the editor holds → the daemon's draft
function draftOf(st) {
  const fields = {};
  for (const key in st.std) {
    const f = st.std[key];
    fields[key] = f.known ? f.value : null;
  }
  return { kind: st.kind, title: String(st.title || "").trim(), folder: String(st.folder || "").trim(),
           fav: !!st.fav, notes: st.notes,
           tags: String(st.tags || "").split(",").map((t) => t.trim()).filter((t) => t),
           fields: fields, urls: st.urls.map((u) => String(u).trim()).filter((u) => u),
           custom: st.custom.filter((c) => String(c.label).trim() !== "" || c.value)
             .map((c) => ({ ref: c.ref || "", label: String(c.label).trim() || "field",
                            value: c.known ? c.value : null, hidden: !!c.hidden })) };
}

// what a platform can do (the daemon's `can`), with nothing for unknown
function can(info, what) {
  return !!(info && info.can && info.can[what]);
}
function canCreate(info, kind) {
  return !!(info && info.can && (info.can.create || []).indexOf(kind) >= 0);
}
function deleteWord(info) {
  const d = info && info.can ? info.can.delete : null;
  return d === "trash" ? "Move to Trash" : d === "archive" ? "Archive" : d === "delete" ? "Delete" : "";
}

// ── A SITE'S MARK ──────────────────────────────────────────────────────────
// "https://www.amazon.eg/foo" → "amazon.eg"
function hostOf(uri) {
  const m = /^[a-z][a-z0-9+.-]*:\/\/([^/?#:]+)/i.exec(String(uri || ""));
  return m ? m[1].toLowerCase().replace(/^www\./, "") : "";
}

const cp = (n) => String.fromCodePoint(n);

// A site's own mark where the font has one, else the kind of thing it is.
// Matched against the host (see siteMatches), first hit wins — so the more
// specific names go before anything they contain. Every codepoint here was
// checked against JetBrainsMono Nerd Font 3.5; anything missing would draw
// as a box.
const SITES = [
  ["github",        cp(0xF09B)],
  ["gitlab",        cp(0xF296)],
  ["codeberg",      cp(0xF330)],
  ["archlinux",     cp(0xF303)],
  ["discord",       cp(0xF1FF)],
  ["amazon",        cp(0xF270)],
  ["steampowered",  cp(0xF1B6)],
  ["steamcommunity",cp(0xF1B6)],
  ["reddit",        cp(0xF1A1)],
  ["twitch",        cp(0xF1E8)],
  ["spotify",       cp(0xF1BC)],
  ["paypal",        cp(0xF1ED)],
  ["google",        cp(0xF1A0)],
  ["apple.com",     cp(0xF179)],
  ["microsoft",     cp(0xF17A)],
  ["dropbox",       cp(0xF16B)],
  ["sony",          cp(0xED18)],
  ["playstation",   cp(0xED18)],
  ["nintendo",      cp(0xF07E1)],
  ["battle.net",    cp(0xEF94)],
  ["blizzard",      cp(0xEF94)],
  ["squarespace",   cp(0xEE85)],
  ["wix.com",       cp(0xEE96)],
  ["deviantart",    cp(0xF1BD)],
  ["patreon",       cp(0xED13)],
  ["gog.com",       cp(0xF0BA1)],
  ["ubisoft",       cp(0xF0BDA)],
  ["outlook",       cp(0xF0D22)],
  ["live.com",      cp(0xF0D22)],
  ["x.com",         cp(0xF099)],
  ["twitter",       cp(0xF099)],
  ["bitwarden",     cp(0xED25)],
  ["1password",     cp(0xF0881)],
  ["tuta",          cp(0xF01EE)],
  ["proton.me",     cp(0xF01EE)],
  ["musixmatch",    cp(0xF001)],
  ["coolors",       cp(0xEFCC)],
  ["raindrop",      cp(0xE34A)],
  ["figma",         cp(0xEF47)],
  ["dominos",       cp(0xF0409)],
  ["burger",        cp(0xF0685)],
  ["elmenus",       cp(0xF025A)],
  ["alahly",        cp(0xF19C)],
  ["bank",          cp(0xF19C)],
  // games without a mark of their own
  ["epicgames",     cp(0xF11B)],
  ["pathofexile",   cp(0xF11B)],
  ["diablo",        cp(0xF11B)],
  ["tarkov",        cp(0xF11B)],
  ["rockstargames", cp(0xF11B)],
  ["soulframe",     cp(0xF11B)],
  ["nexusmods",     cp(0xF11B)],
];

// A key with a dot in it is a whole domain and has to match as one —
// "x.com" is inside "dropbox.com" and "netflix.com". A bare word is a
// substring, so "steampowered" finds store.steampowered.com.
function siteMatches(host, key) {
  if (key.indexOf(".") < 0) return host.indexOf(key) >= 0;
  return host === key || host.endsWith("." + key);
}

// the glyph an item wears, and its color (a Zenon slot); `brand` says it
// is a site's own mark
function markOf(it) {
  if (!it) return { glyph: kindOf("login").glyph, ink: "muted", brand: false };
  const k = kindOf(it.kind);
  if (it.kind === "card") {
    const n = String(it.title || "").toLowerCase() + " " + String(it.sub || "").toLowerCase();
    if (n.indexOf("visa") >= 0) return { glyph: cp(0xF1F0), ink: k.ink, brand: true };
    if (n.indexOf("master") >= 0) return { glyph: cp(0xF1F1), ink: k.ink, brand: true };
    if (n.indexOf("amex") >= 0 || n.indexOf("american express") >= 0) return { glyph: cp(0xF1F3), ink: k.ink, brand: true };
  }
  const h = it.host || "";
  if (h && (it.kind === "login" || it.kind === "password"))
    for (const [key, g] of SITES)
      if (siteMatches(h, key)) return { glyph: g, ink: k.ink, brand: true };
  return { glyph: k.glyph, ink: k.ink, brand: false };
}

// ── WHICH ITEMS A SHELF HOLDS ──────────────────────────────────────────────
// Every item carries `acct` (its account's id) beside the daemon's fields;
// `key` is unique across accounts.
function keyOf(it) { return it ? it.acct + "\u0001" + it.id : ""; }

// favorite: the platform's own (1Password's) or calypso's (favs[key])
function isFav(it, favs) { return !!(it && (it.fav || (favs && favs[keyOf(it)]))); }

// scope: { shelf: all|fav|totp, kind, acct, folder, tag } — any left out
// does not narrow
// flags: Watchtower's findings by C.keyOf — { key: [problem ids] }
function inScope(it, scope, favs, flags) {
  if (!scope) return true;
  if (scope.shelf === "watch") {
    const f = flags ? flags[keyOf(it)] : null;
    if (!f || f.length === 0) return false;
    if (scope.audit && f.indexOf(scope.audit) < 0) return false;
    // "no one-time password" alone is a hint, listed only on its own card
    if (!scope.audit && f.every((p) => p === "no2fa")) return false;
  }
  if (scope.acct && it.acct !== scope.acct) return false;
  if (scope.shelf === "fav" && !isFav(it, favs)) return false;
  if (scope.shelf === "totp" && it.totp !== true) return false;
  if (scope.kind && it.kind !== scope.kind) return false;
  if (scope.folder !== undefined && scope.folder !== null && scope.folder !== ""
      && it.folder !== scope.folder && it.folder.indexOf(scope.folder + " / ") !== 0) return false;
  if (scope.tag && (it.tags || []).indexOf(scope.tag) < 0) return false;
  return true;
}

// How well an item answers a search, 0 for not at all. Every word has to be
// found somewhere; a title that starts with the search beats one that holds
// it, which beats a username, a site, a folder or a tag holding it.
function score(it, query) {
  const q = String(query || "").trim().toLowerCase();
  if (!q) return 1;
  const title = String(it.title || "").toLowerCase();
  const rest = [it.sub, it.host, it.folder].concat(it.tags || []).join("\u0001").toLowerCase();
  let s = 0;
  for (const w of q.split(/\s+/)) {
    if (title.indexOf(w) === 0) s += 8;
    else if (title.indexOf(" " + w) >= 0 || title.indexOf("." + w) >= 0) s += 5;
    else if (title.indexOf(w) >= 0) s += 3;
    else if (rest.indexOf(w) >= 0) s += 1;
    else return 0;
  }
  if (title === q) s += 10;
  return s;
}

function byName(a, b) {
  const n = String(a.title).toLowerCase().localeCompare(String(b.title).toLowerCase());
  if (n !== 0) return n;
  return String(a.sub).localeCompare(String(b.sub));
}

// sort: name | recent; a search orders by how well each answers it
function shelve(items, scope, query, favs, sort, flags) {
  const q = String(query || "").trim();
  const out = [];
  for (const it of items || []) {
    if (!inScope(it, scope, favs, flags)) continue;
    const s = score(it, q);
    if (s > 0) out.push({ it: it, s: s });
  }
  if (q) out.sort((a, b) => b.s - a.s || byName(a.it, b.it));
  else if (sort === "recent") out.sort((a, b) => (b.it.updated || 0) - (a.it.updated || 0) || byName(a.it, b.it));
  else out.sort((a, b) => byName(a.it, b.it));
  return out.map((o) => o.it);
}

function count(items, scope, favs, flags) {
  let n = 0;
  for (const it of items || []) if (inScope(it, scope, favs, flags)) n++;
  return n;
}

// the folders (vaults, groups) of the items given, with how many each
// holds, by name — nested ones under their parent ("Work / Servers")
function folders(items) {
  const n = {};
  for (const it of items || []) {
    if (!it.folder) continue;
    n[it.folder] = (n[it.folder] || 0) + 1;
  }
  return Object.keys(n).sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()))
    .map((f) => ({ name: f, count: n[f], depth: f.split(" / ").length - 1,
                   leaf: f.split(" / ").pop() }));
}

function tags(items) {
  const n = {};
  for (const it of items || []) for (const t of it.tags || []) n[t] = (n[t] || 0) + 1;
  return Object.keys(n).sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()))
    .map((t) => ({ name: t, count: n[t] }));
}

// ── THE LIST'S HEADINGS ────────────────────────────────────────────────────
// By name, the first letter (anything else under "#"); by recent, how long
// ago. `now` in ms. A search has no headings.
function sectionOf(it, sort, now) {
  if (sort === "recent") return ageWord(it.updated, now);
  const c = String(it.title || "").trim().charAt(0).toUpperCase();
  return /[A-Z]/.test(c) ? c : /[0-9]/.test(c) ? "0–9" : "#";
}

const MONTHS = ["January", "February", "March", "April", "May", "June", "July",
                "August", "September", "October", "November", "December"];

function ageWord(epoch, now) {
  if (!epoch) return "Undated";
  const d = new Date(epoch * 1000);
  const n = new Date(now);
  const day = (x) => Math.floor((Date.UTC(x.getFullYear(), x.getMonth(), x.getDate())) / 86400000);
  const ago = day(n) - day(d);
  if (ago <= 0) return "Today";
  if (ago === 1) return "Yesterday";
  if (ago < 7) return "This week";
  if (ago < 31 && d.getMonth() === n.getMonth()) return "This month";
  return MONTHS[d.getMonth()] + " " + d.getFullYear();
}

// "Changed 3 October 2026"
function dateWords(epoch) {
  if (!epoch) return "";
  const d = new Date(epoch * 1000);
  return d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear();
}

// ── A CODE, IN TWO HALVES ──────────────────────────────────────────────────
function codeShown(code) {
  const c = String(code || "");
  if (c.length < 6) return c;
  const h = Math.ceil(c.length / 2);
  return c.slice(0, h) + " " + c.slice(h);
}

// a secret drawn as dots — as many as it has characters, up to a row's worth
function dots(n) {
  return "•".repeat(Math.max(8, Math.min(Number(n) || 12, 24)));
}

// ── SIGNING IN ─────────────────────────────────────────────────────────────
// The FormBody card that adds an account of a platform (delphi/FormBody:
// fields, a secret). `how` picks between a platform's ways in (Proton's
// browser or here).
function setupForm(kind, how) {
  const p = platform(kind);
  const base = { title: "Add " + p.name, glyph: p.glyph, verb: "Add" };
  if (kind === "bitwarden") return Object.assign(base, {
    detail: "Your Bitwarden account, through bw. A self-hosted Vaultwarden? Its address goes in Server. The master password is asked next.",
    fields: [{ key: "email", label: "Email", hint: "ada@example.com" },
             { key: "server", label: "Server", hint: "bitwarden.com", optional: true },
             { key: "name", label: "Name", hint: "Bitwarden", optional: true }],
    secret: null, then2: "setup" });
  if (kind === "onepassword") return Object.assign(base, {
    detail: "Your sign-in address, email and Secret Key are in your Emergency Kit. The password is asked next.",
    fields: [{ key: "address", label: "Sign-in address", value: "my.1password.com" },
             { key: "email", label: "Email", hint: "ada@example.com" },
             { key: "secretKey", label: "Secret Key", hint: "A3-XXXXXX-XXXXXX-XXXXX-XXXXX-XXXXX" },
             { key: "name", label: "Name", hint: "1Password", optional: true }],
    secret: null, then2: "setup" });
  if (kind === "proton" && how === "here") return Object.assign(base, {
    detail: "Signed in here, in calypso. Accounts that sign in with SSO or a security key use the browser instead.",
    fields: [{ key: "email", label: "Email", hint: "ada@proton.me" },
             { key: "totp", label: "2FA code", hint: "if your account has one", optional: true },
             { key: "extra", label: "Extra password", hint: "Proton Pass' own, if you set one", optional: true }],
    secret: null, then2: "setup" });
  if (kind === "keepass") return Object.assign(base, {
    detail: "A KeePass database (.kdbx) of your own — or a new one, made there. A key file too, if it needs one.",
    fields: [{ key: "path", label: "Database", hint: "~/Passwords.kdbx", file: true },
             { key: "keyfile", label: "Key file", hint: "none", optional: true, file: true },
             { key: "name", label: "Name", hint: "the file's name", optional: true }],
    secret: null, then2: "unlock" });
  if (kind === "pass" || kind === "gopass") return Object.assign(base, {
    detail: kind === "pass"
      ? "The password store's directory (PASSWORD_STORE_DIR, ~/.password-store when unset). It is read with gpg."
      : "gopass' store is found by gopass itself; another can be named here. It is read with gpg.",
    fields: [{ key: "store", label: "Store", hint: kind === "pass" ? "~/.password-store" : "gopass' own", optional: true, path: true },
             { key: "name", label: "Name", hint: p.name, optional: true }],
    secret: null, then2: "unlock" });
  return Object.assign(base, { detail: "", fields: [], secret: null, then2: "unlock" });
}

// what the unlock field says, for a platform that asks for something
function unlockPrompt(asks) {
  return asks === "passphrase" ? "input your gpg passphrase" : "input your master password";
}

// A name for a new account when none was given: the platform's, then the
// user, then the file — "Bitwarden", "Bitwarden · ada@example.com" when there
// is one already.
function accountName(kind, values, taken) {
  const p = platform(kind);
  const given = String((values && values.name) || "").trim();
  if (given) return given;
  let n = p.name;
  if (kind === "keepass" && values && values.path)
    n = String(values.path).replace(/.*\//, "").replace(/\.kdbx$/i, "");
  const clash = (taken || []).indexOf(n) >= 0;
  const who = values && (values.email || "");
  return clash && who ? n + " · " + who : n;
}

// ── QUICK ACCESS: WHAT AN ITEM CAN DO ──────────────────────────────────────
// `totp` the item's own answer (true / false / null for not known yet),
// which leaves the code's actions offered while unknown rather than hiding
// one that works.
function actionEnabled(kind, it) {
  if (!it) return false;
  // a card's own (CalypsoPopup.cardActions): every one, whatever it holds
  if (kind.indexOf(":") > 0) return it.kind === "card";
  const wantsUser = kind === "user" || kind === "copyuser" || kind === "both";
  const wantsTotp = kind === "totp" || kind === "copytotp";
  if (wantsUser && !it.sub) return false;
  if (wantsTotp && (it.kind !== "login" || it.totp === false)) return false;
  if (it.kind === "note") return false;
  return true;
}

// query matches drawn in `ink`, bold, across a line of rich text
function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
function highlight(text, query, ink) {
  text = String(text);
  if (!query) return esc(text);
  const lower = text.toLowerCase();
  const words = String(query).toLowerCase().trim().split(/\s+/).filter((w) => w);
  // marked characters, then runs of them
  const lit = new Array(text.length).fill(false);
  for (const w of words) {
    const i = lower.indexOf(w);
    if (i >= 0) for (let j = i; j < i + w.length; j++) lit[j] = true;
  }
  let out = "", run = "", on = false;
  const flush = () => {
    if (!run) return;
    out += on ? "<b><span style=\"color:" + ink + ";\">" + esc(run) + "</span></b>" : esc(run);
    run = "";
  };
  for (let i = 0; i < text.length; i++) {
    if (lit[i] !== on) { flush(); on = lit[i]; }
    run += text[i];
  }
  flush();
  return out;
}

// an error from the daemon, as a sentence
function failWords(err) {
  if (!err) return "Something went wrong";
  if (err.kind === "gone") return "Calypso's backend stopped";
  if (err.kind === "missing") return err.error;
  return plainError(err.error) || "Something went wrong";
}

// What an unlock's refusal adds to the field's own "wrong password": nothing
// when that is all it says, else the reason in plain words.
function authNote(err) {
  const t = err && err.error ? String(err.error) : "";
  if (t === "" || /wrong|invalid (master )?password|incorrect|decryption operation failed|bad passphrase/i.test(t)) return "";
  return plainError(t);
}

// A tool's raw error made fit to read: a log prefix ("ERROR
// some_crate::module: error=") and a trailing full stop off, the first
// letter raised.
function plainError(t) {
  let s = String(t || "").split("\n")[0].trim();
  s = s.replace(/^(error|warn(ing)?|fatal)\b[:\s]*/i, "");
  s = s.replace(/^[\w-]+(::[\w-]+)+:?\s*/, "");
  s = s.replace(/^error\s*=\s*/i, "");
  s = s.replace(/\.$/, "");
  return s.charAt(0).toUpperCase() + s.slice(1);
}
