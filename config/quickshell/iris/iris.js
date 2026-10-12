// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The pure half of iris: what the address line makes of what was typed, and
// how a page's address is shown. Functions of their arguments only, tested
// in oracle/tests/iris.js.

.pragma library

// Where a search goes. DuckDuckGo until iris has settings of its own.
const SEARCH = "https://duckduckgo.com/?q=";

// What typed text means: an address to go to, or words to search for.
//
//   https://a.b/c · about:blank · file:///x · chrome://gpu   as written
//   example.com · a.b.c/d?e · 192.168.1.1:8080/x              https:// added
//   localhost:3000 · localhost/x                              http:// (a dev
//                                                             server has no tls)
//   anything with a space, or no dot, or a dot at an end      a search
//
// "a scheme" is letters then ":" — but "host:port" is not a scheme, so a
// colon followed by digits is a port, not one.
function toUrl(typed) {
  const s = String(typed || "").trim();
  if (s === "") return "";
  if (/\s/.test(s)) return SEARCH + encodeURIComponent(s);
  if (/^[a-z][a-z0-9+.-]*:/i.test(s) && !/^[^:\/]+:\d+(\/|$)/.test(s)) return s;
  if (/^localhost(:\d+)?(\/.*)?$/i.test(s)) return "http://" + s;
  const host = s.split(/[\/?#]/)[0].replace(/:\d+$/, "");
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return "https://" + s;
  if (/^[a-z0-9-]+(\.[a-z0-9-]+)+$/i.test(host) && /[a-z]/i.test(host.split(".").pop()))
    return "https://" + s;
  return SEARCH + encodeURIComponent(s);
}

// The address as the line shows it while not being typed in: whole, but an
// empty page shows nothing rather than "about:blank".
function shown(url) {
  const s = String(url || "");
  return s === "about:blank" ? "" : s;
}

// THE SITE A LOGIN IS FOR: the address' host down to its registrable name,
// what a vault files a login under — accounts.google.com and mail.google.com
// are both google.com, gist.github.com is github.com. Two labels, or three
// where the second-to-last is a registry's own (co.uk, com.au, ac.jp…); an
// address, a single label or no host at all is given back whole or "".
function siteOf(url) {
  const m = String(url || "").match(/^[a-z][a-z0-9+.-]*:\/\/([^\/?#:]+)/i);
  if (!m) return "";
  const host = m[1].toLowerCase().replace(/\.$/, "");
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.indexOf(".") < 0) return host;
  const p = host.split(".");
  const n = p.length >= 3 && p[p.length - 1].length === 2
    && /^(co|com|net|org|gov|edu|ac|or|ne|go)$/.test(p[p.length - 2]) ? 3 : 2;
  return p.slice(-n).join(".");
}

// A tab's name: the page's title, else its address without the scheme, else
// "New tab".
function tabName(title, url) {
  const t = String(title || "").trim();
  const u = shown(url);
  if (t !== "" && t !== u) return t;
  if (u !== "") return u.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").replace(/\/$/, "");
  return "New tab";
}
