// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SUITE'S HTTP REQUESTS, through curl — never XMLHttpRequest. Qt's own
// network stack speaks HTTP/2 to any https server that offers it, and Qt
// 6.12's HTTP/2 crashed this shell (and Hyprland after it) on 2026-10-20
// (QHttp2Stream::handleHEADERS, a cover fetch). Covers moved to curl then
// (NowPlaying.art); Lexi's translations and lookups, Minerva's and Ideo's
// glyph list still went through XMLHttpRequest — the same stack, and Lexi's
// live translation asks as you type. A crash in curl is curl's alone.
//
//   Net.request(method, url, { headers, body, timeout }, (status, text) => …)
//   Net.fetch(url, file, { timeout, maxBytes }, (ok) => …)
//
// `status` is the HTTP status, or 0 when nothing came back (no network, a
// timeout, curl missing) — what XMLHttpRequest said in the same case, so a
// caller's "status === 0 means no connection" holds. `body` goes to curl on
// stdin, never argv: a long text to translate would pass argv's limit.
// Each request is its own Process, so they run side by side; a caller that
// only wants the newest answer keeps its own sequence number, as before.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  function request(method, url, opts, done) {
    const o = opts || {};
    const argv = ["curl", "-sS", "-L", "--max-time", String(o.timeout || 20),
                  "-X", String(method || "GET"), "-w", "\n%{http_code}"];
    const headers = o.headers || {};
    for (const k in headers) argv.push("-H", k + ": " + headers[k]);
    const hasBody = o.body !== undefined && o.body !== null;
    if (hasBody) argv.push("--data-binary", "@-");
    argv.push("--", String(url));
    // started as it is made: everything it needs is set before it runs
    call.createObject(root, { command: argv, done: done, input: hasBody ? String(o.body) : "",
                              stdinEnabled: hasBody, running: true });
  }

  // A FILE FROM THE WEB, KEPT: `url` into `file` once — already there, it
  // is not asked for again. The covers (NowPlaying.art), the pictures in
  // Delphi's release notes, Alexandria's glyph names: one way, not three
  // (audit, 2026-10-27). Only http(s), and curl kept to it on redirects
  // too, with `--` before the address — these come from other people's
  // words (release notes, a player's metadata), and curl would as readily
  // take a gopher:// or a -K. Written as file.part and moved, so a fetch
  // cut short never passes for the file. done(ok).
  function fetch(url, file, opts, done) {
    const o = opts || {};
    const u = String(url || "");
    if (!/^https?:\/\/\S+$/i.test(u) || String(file || "") === "") { if (done) Qt.callLater(() => done(false)); return; }
    getter.createObject(root, { done: done, running: true, command: ["sh", "-c",
      'f=$1; [ -s "$f" ] && exit 0; mkdir -p "${f%/*}" || exit 1; '
      + 'curl -fsSL --proto =http,https --proto-redir =http,https --max-time "$3" --max-filesize "$4" -o "$f.part" -- "$2" '
      + '&& [ -s "$f.part" ] && mv -f "$f.part" "$f" || { rm -f "$f.part"; exit 1; }',
      "sh", String(file), u, String(o.timeout || 30), String(o.maxBytes || 100000000)] });
  }
  Component {
    id: getter
    Process {
      id: g
      property var done: null
      onExited: (code) => {
        const fn = g.done;
        g.done = null;
        g.destroy();
        if (fn) fn(code === 0);
      }
    }
  }

  // the text curl printed, split from the status -w put on its last line
  function split(text) {
    const s = String(text || "");
    const at = s.lastIndexOf("\n");
    const code = parseInt(at >= 0 ? s.slice(at + 1) : s, 10);
    return { status: code > 0 ? code : 0, body: at >= 0 ? s.slice(0, at) : "" };
  }

  Component {
    id: call
    Process {
      id: proc
      property var done: null
      property string out: ""
      // the body, written once curl is really there: a Process made here
      // starts a beat after `running`, and a write before that was lost —
      // with stdin then never closed, curl waited on it for good
      property string input: ""
      onStarted: if (proc.stdinEnabled) { proc.write(proc.input); proc.stdinEnabled = false; }
      stdout: StdioCollector { onStreamFinished: proc.out = this.text }
      // streamFinished comes before exited (morpheus/process-exit order)
      onExited: (code) => {
        const r = code === 0 ? root.split(proc.out) : { status: 0, body: "" };
        const fn = proc.done;
        proc.done = null;
        proc.destroy();
        if (fn) fn(r.status, r.body);
      }
    }
  }
}
