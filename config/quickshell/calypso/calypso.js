// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

// rbw ls --raw → JSON array [{ id, name, user, directory, uris, type }]
// uris are plain strings; only the first one's host is kept, for the glyph

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
  ["tuta",          cp(0xF01EE)],
  ["proton.me",     cp(0xF01EE)],
  ["musixmatch",    cp(0xF001)],
  ["coolors",       cp(0xEFCC)],
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

const GLYPH_LOGIN = cp(0xF084);    // key
const GLYPH_CARD  = cp(0xF09D);    // credit card
const GLYPH_NOTE  = cp(0xF249);    // sticky note
const GLYPH_ID    = cp(0xF2C2);    // id card
const GLYPH_SSH   = cp(0xF030B);   // key variant

// A key with a dot in it is a whole domain and has to match as one —
// "x.com" is inside "dropbox.com" and "netflix.com". A bare word is a
// substring, so "steampowered" finds store.steampowered.com.
function siteMatches(host, key) {
  if (key.indexOf(".") < 0) return host.indexOf(key) >= 0;
  return host === key || host.endsWith("." + key);
}

// the glyph an entry wears; `brand` says whether it is a site's own mark,
// which is drawn a shade brighter than the generic ones
function glyphFor(e) {
  if (!e) return { glyph: GLYPH_LOGIN, brand: false };
  if (e.type === "Card") {
    const n = String(e.name).toLowerCase();
    if (n.indexOf("visa") >= 0) return { glyph: cp(0xF1F0), brand: true };
    if (n.indexOf("master") >= 0) return { glyph: cp(0xF1F1), brand: true };
    return { glyph: GLYPH_CARD, brand: false };
  }
  if (e.type === "Note" || e.type === "SecureNote") return { glyph: GLYPH_NOTE, brand: false };
  if (e.type === "Identity") return { glyph: GLYPH_ID, brand: false };
  if (e.type === "SshKey") return { glyph: GLYPH_SSH, brand: false };
  const h = e.host || "";
  if (h)
    for (const [k, g] of SITES)
      if (siteMatches(h, k)) return { glyph: g, brand: true };
  return { glyph: GLYPH_LOGIN, brand: false };
}

// Which actions mean anything for an entry. `totp` is whether the vault
// scan found an authenticator on it (undefined while that is unknown, which
// leaves the TOTP actions offered — the old behaviour — rather than hiding
// one that works).
//
// Cards are off entirely: their number and CVV sit behind Bitwarden's
// master-password re-prompt, which rbw can only answer through a pinentry
// calypso is not driving at that moment, so every action on one failed.
function actionEnabled(kind, e, totp) {
  if (!e) return false;
  if (e.type === "Card") return false;
  const wantsUser = kind === "user" || kind === "copyuser" || kind === "both";
  const wantsTotp = kind === "totp" || kind === "copytotp";
  if (wantsUser && !e.user) return false;
  if (wantsTotp && (e.type !== "Login" || totp === false)) return false;
  if (e.type === "Note" || e.type === "SecureNote")
    return kind === "pass" || kind === "copypass";
  return true;
}
function parseEntries(jsonText) {
  let data;
  try { data = JSON.parse(jsonText); } catch (e) { return []; }
  if (!Array.isArray(data)) return [];
  const rows = [];
  for (const e of data) {
    if (!e || typeof e.name !== "string" || !e.id) continue;
    rows.push({
      id: e.id,
      name: e.name,
      user: typeof e.user === "string" ? e.user : "",
      folder: typeof e.folder === "string" ? e.folder : "",
      // Login · Card · Identity · Note · SshKey — decides the glyph and
      // which actions mean anything for it
      type: typeof e.type === "string" ? e.type : "Login",
      host: hostOf(Array.isArray(e.uris) ? e.uris[0] : ""),
    });
  }
  // folder-less entries float to the top, then alphabetical by name
  rows.sort((a, b) => {
    const fa = a.folder, fb = b.folder;
    if ((fa === "") !== (fb === "")) return fa === "" ? -1 : 1;
    const n = a.name.toLowerCase().localeCompare(b.name.toLowerCase());
    if (n !== 0) return n;
    return a.user.localeCompare(b.user);
  });
  return rows;
}

function filterEntries(rows, query) {
  const q = String(query).toLowerCase();
  if (!q) return rows;
  return rows.filter((r) =>
    r.name.toLowerCase().indexOf(q) >= 0 ||
    r.user.toLowerCase().indexOf(q) >= 0 ||
    r.folder.toLowerCase().indexOf(q) >= 0);
}

// query matches render bold #eebebe across every field
function highlight(text, query) {
  text = String(text);
  const esc = (s) => String(s).replace(/&/g, "&amp;")
    .replace(/</g, "&lt;").replace(/>/g, "&gt;");
  if (!query) return esc(text);
  const lower = text.toLowerCase();
  const ql = String(query).toLowerCase();
  let out = "", pos = 0, i;
  while ((i = lower.indexOf(ql, pos)) >= 0) {
    out += esc(text.slice(pos, i));
    out += "<b><span style=\"color:#eebebe;\">" +
      Strings.escapeHtml(text.substr(i, ql.length)) + "</span></b>";
    pos = i + ql.length;
  }
  return out + esc(text.slice(pos));
}

// ── first-run setup ─────────────────────────────────────────────────────────

// Loose on purpose: rbw and the server are the real judges, this only catches
// a stray keypress being taken for an address.
function looksLikeEmail(s) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(s || "").trim());
}

// What the server step typed → rbw's base_url. Empty means bitwarden.com,
// which is rbw's default and needs no setting; a bare host gets https://.
function serverUrl(s) {
  s = String(s || "").trim().replace(/\/+$/, "");
  if (s === "") return "";
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(s) ? s : "https://" + s;
}

// rbw unlock's stderr → a line worth showing, or "" when it was simply the
// wrong password (the field already says so). A first login fails for reasons
// the password has nothing to do with, and "wrong master password" for those
// sends people typing the same right password again and again.
function unlockFailure(err) {
  err = String(err || "");
  if (err.trim() === "") return "";
  if (/register/i.test(err)) return "new device: run rbw register in a terminal once";
  if (/error sending request|dns|connect|timed? ?out|network|resolve/i.test(err))
    return "could not reach the server";
  if (/password|unauthorized|invalid_grant|incorrect/i.test(err)) return "";
  return "sign-in failed: see rbw unlock in a terminal";
}
