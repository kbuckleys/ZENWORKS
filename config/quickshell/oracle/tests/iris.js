// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The pure half of iris: the address line deciding between an address and a
// search, and a tab's name.

"use strict";

module.exports = {
  module: "iris/iris.js",
  cases: (I, t) => {
    const S = I.SEARCH;
    // ── addresses, as written ────────────────────────────────────────
    for (const u of ["https://example.com", "http://a.b/c?d=e#f", "about:blank", "file:///etc/hosts",
                     "chrome://gpu", "mailto:a@b.c", "data:text/plain,hi"])
      t.eq("as written: " + u, I.toUrl(u), u);
    // ── a host, given its scheme ─────────────────────────────────────
    t.eq("bare host", I.toUrl("example.com"), "https://example.com");
    t.eq("host and path", I.toUrl("archlinux.org/packages/?q=qt6"), "https://archlinux.org/packages/?q=qt6");
    t.eq("subdomain", I.toUrl("wiki.archlinux.org"), "https://wiki.archlinux.org");
    t.eq("ip and port", I.toUrl("192.168.1.1:8080/x"), "https://192.168.1.1:8080/x");
    t.eq("host and port is not a scheme", I.toUrl("example.com:8443"), "https://example.com:8443");
    t.eq("localhost is plain http", I.toUrl("localhost:3000"), "http://localhost:3000");
    t.eq("localhost path", I.toUrl("localhost/admin"), "http://localhost/admin");
    t.eq("trimmed", I.toUrl("  example.com  "), "https://example.com");
    // ── words, searched ──────────────────────────────────────────────
    t.eq("a word", I.toUrl("qt6"), S + "qt6");
    t.eq("words", I.toUrl("arch linux wiki"), S + "arch%20linux%20wiki");
    t.eq("a dotted word with a space is a search", I.toUrl("node.js tutorial"), S + "node.js%20tutorial");
    t.eq("a version number is a search", I.toUrl("6.12.0"), S + "6.12.0");
    t.eq("a trailing dot is a search", I.toUrl("hello."), S + "hello.");
    t.eq("symbols are encoded", I.toUrl("c++ & rust?"), S + "c%2B%2B%20%26%20rust%3F");
    t.eq("nothing", I.toUrl("   "), "");
    // ── shown and named ──────────────────────────────────────────────
    t.eq("blank shows nothing", I.shown("about:blank"), "");
    t.eq("an address shows whole", I.shown("https://a.b/c"), "https://a.b/c");
    t.eq("a title names a tab", I.tabName("Arch Linux", "https://archlinux.org/"), "Arch Linux");
    t.eq("no title: the address, bare", I.tabName("", "https://archlinux.org/"), "archlinux.org");
    t.eq("a title that is the address: bare", I.tabName("https://a.b/", "https://a.b/"), "a.b");
    t.eq("nothing at all", I.tabName("", "about:blank"), "New tab");
    // ── the site a login is for ──────────────────────────────────────
    t.eq("subdomain to its site", I.siteOf("https://accounts.google.com/signin?x=1"), "google.com");
    t.eq("deeper subdomain", I.siteOf("https://a.b.gist.github.com/x"), "github.com");
    t.eq("already the site", I.siteOf("https://github.com/login"), "github.com");
    t.eq("a registry's own second level", I.siteOf("https://www.bbc.co.uk/"), "bbc.co.uk");
    t.eq("port dropped", I.siteOf("http://my.nas.local:5000/"), "nas.local");
    t.eq("an address whole", I.siteOf("https://192.168.1.1/admin"), "192.168.1.1");
    t.eq("one label whole", I.siteOf("http://localhost:3000/"), "localhost");
    t.eq("no host, nothing", I.siteOf("about:blank"), "");
    // ── the host ─────────────────────────────────────────────────────
    t.eq("host lower-cased", I.hostOf("https://www.Reddit.com/r/x"), "www.reddit.com");
    t.eq("host without user or port", I.hostOf("http://user@host:80/"), "host");
    t.eq("no host", I.hostOf("file:///x"), "");
    t.eq("an ipv6 host", I.hostOf("http://[::1]:3/"), "[::1]");
    // ── the line at rest ─────────────────────────────────────────────
    t.eq("rest: the site, bare", I.restOf("https://www.reddit.com/r/linux/comments/x?a=1"), "reddit.com");
    t.eq("rest: a subdomain kept", I.restOf("https://mail.google.com/mail/u/0/"), "mail.google.com");
    t.eq("rest: plain http too", I.restOf("http://neverssl.com/online"), "neverssl.com");
    t.eq("rest: a file by its name", I.restOf("file:///home/u/My%20Doc.pdf"), "My Doc.pdf");
    t.eq("rest: an internal page as itself", I.restOf("chrome://gpu/"), "chrome://gpu/");
    t.eq("rest: blank is nothing", I.restOf("about:blank"), "");
  }
};
