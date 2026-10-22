// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// NETWORK PLACES — the arithmetic (oracle/tests/network.js). What a typed
// address means, what it is called, what gvfs packages it needs, and the
// saved places' file. The mounting is net/netplaces.py's.

.pragma library

// what each kind of address is, said plainly, and what it needs installed
const KINDS = {
  smb:  { words: "Windows share", pkgs: ["gvfs", "gvfs-smb"] },
  sftp: { words: "SFTP", pkgs: ["gvfs"] },
  ssh:  { words: "SFTP", pkgs: ["gvfs"] },
  ftp:  { words: "FTP", pkgs: ["gvfs"] },
  ftps: { words: "FTP", pkgs: ["gvfs"] },
  dav:  { words: "WebDAV", pkgs: ["gvfs", "gvfs-dnssd"] },
  davs: { words: "WebDAV", pkgs: ["gvfs", "gvfs-dnssd"] },
  nfs:  { words: "NFS", pkgs: ["gvfs", "gvfs-nfs"] },
  afp:  { words: "Apple share", pkgs: ["gvfs", "gvfs-afp"] }
};
function schemes() { return Object.keys(KINDS); }

// What was typed, as an address gvfs takes, or "" for nothing usable:
//   smb://nas/share, sftp://me@host/path   as they are
//   \\nas\share, //nas/share               Windows' way: smb
//   me@host:/path, host:path               scp's way: sftp
//   https://… http://…                     WebDAV (davs/dav)
//   nas/share                              a bare server and share: smb
function normalize(typed) {
  let t = String(typed || "").trim();
  if (t === "") return "";
  if (/^\\\\/.test(t)) t = "smb:" + t.replace(/\\/g, "/");
  else if (/^\/\//.test(t)) t = "smb:" + t;
  const m = /^([a-z][a-z0-9+.-]*):\/\/(.*)$/i.exec(t);
  if (m) {
    let scheme = m[1].toLowerCase();
    if (scheme === "https") scheme = "davs";
    else if (scheme === "http") scheme = "dav";
    if (!KINDS[scheme] || m[2] === "") return "";
    return scheme + "://" + m[2].replace(/\/+$/, "");
  }
  // scp's user@host:path (not a Windows drive like C:)
  const scp = /^((?:[^@\s/]+@)?[^:\s/]{2,}):(.*)$/.exec(t);
  if (scp) {
    const path = scp[2] === "" ? "" : "/" + scp[2].replace(/^\/+/, "");
    return "sftp://" + scp[1] + path.replace(/\/+$/, "");
  }
  if (/^[^\s/:@]+(\/[^\s]*)?$/.test(t)) return "smb://" + t.replace(/\/+$/, "");
  return "";
}

// { scheme, user, host, port, path } of an address; null if it is not one
function parse(uri) {
  const m = /^([a-z][a-z0-9+.-]*):\/\/(?:([^@/]*)@)?(\[[^\]]+\]|[^:/]+)(?::(\d+))?(\/.*)?$/i.exec(String(uri || ""));
  if (!m) return null;
  return { scheme: m[1].toLowerCase(), user: decodeURIComponent(m[2] || ""), host: m[3],
           port: m[4] ? Number(m[4]) : 0, path: m[5] || "" };
}

// what a place is called in the sidebar: its own name, else "share on host"
function label(place) {
  if (place && place.name) return place.name;
  const p = parse(place ? place.uri : "");
  if (!p) return place && place.uri ? place.uri : "";
  const last = p.path.split("/").filter((s) => s !== "").pop() || "";
  return last !== "" ? last + " on " + p.host : p.host;
}
function kindWords(uri) {
  const p = parse(uri);
  return p && KINDS[p.scheme] ? KINDS[p.scheme].words : "";
}
// what has to be installed for an address; [] for one that cannot be
function packagesFor(uri) {
  const p = parse(uri);
  return p && KINDS[p.scheme] ? KINDS[p.scheme].pkgs.slice() : [];
}

// Two spellings of one place are one place: case of scheme and host,
// trailing slashes, and a user written in the address or beside it.
function sameUri(a, b) {
  const x = parse(a), y = parse(b);
  if (!x || !y) return false;
  const path = (s) => s.replace(/\/+$/, "");
  return x.scheme.replace(/^ssh$/, "sftp") === y.scheme.replace(/^ssh$/, "sftp")
    && x.host.toLowerCase() === y.host.toLowerCase()
    && x.port === y.port && path(x.path) === path(y.path);
}

// ── THE SAVED PLACES ──
// [{ uri, name, user, domain }], in the order saved; no password, ever
function parsePlaces(text) {
  try {
    const j = JSON.parse(text);
    if (Array.isArray(j)) return j.filter((p) => p && typeof p.uri === "string" && p.uri !== "")
      .map((p) => ({ uri: p.uri, name: String(p.name || ""), user: String(p.user || ""), domain: String(p.domain || "") }));
  } catch (e) {}
  return [];
}
function savePlace(places, place) {
  const out = places.filter((p) => !sameUri(p.uri, place.uri));
  out.push({ uri: place.uri, name: place.name || "", user: place.user || "", domain: place.domain || "" });
  return out;
}
function dropPlace(places, uri) { return places.filter((p) => !sameUri(p.uri, uri)); }

// The sidebar's rows: every saved place, mounted or not, then whatever
// else is mounted (connected from somewhere else, or not saved):
// [{ uri, name, user, domain, saved, path }] — path "" while not mounted
function rows(places, mounts) {
  const out = [];
  const used = {};
  for (const p of places) {
    let path = "";
    for (let i = 0; i < mounts.length; ++i)
      if (sameUri(p.uri, mounts[i].uri) || (mounts[i].path !== "" && sameUri(p.uri, mounts[i].uri.replace(/\/$/, "")))) {
        path = mounts[i].path; used[i] = true; break;
      }
    out.push({ uri: p.uri, name: p.name, user: p.user, domain: p.domain, saved: true, path: path });
  }
  for (let i = 0; i < mounts.length; ++i) {
    if (used[i]) continue;
    out.push({ uri: mounts[i].uri, name: mounts[i].name || "", user: "", domain: "", saved: false, path: mounts[i].path });
  }
  return out;
}

// the words for a failed connect, from netplaces.py's answer
function failWords(r) {
  if (!r) return "The connection did not answer";
  if (r.why === "auth") return "The server did not take that name and password";
  if (r.why === "missing") return "Network places need gvfs installed";
  if (r.why === "question") return r.message || "The server asked a question";
  return r.message || "Could not connect";
}
