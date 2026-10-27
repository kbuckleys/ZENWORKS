// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// STRINGS — the string functions every layer needed a copy of, and the
// clipboard as text.
//
// shellQuote had ten identical definitions and escapeHtml nine, one per
// layer's own .js. Nineteen copies of six lines, and two of them had already
// drifted: picasso and howler had grown a `?? ""` the others never got, so the
// same call was null-safe in two layers and threw in the rest. That is what
// duplicated logic does, and it is the whole argument for this file.
//
// A SINGLETON rather than a shared .js, which is not a style choice. A .js
// file gains its own scope the moment it carries an `.import` statement, and
// loses the QML document's — so a layer's .js that imported a helpers library
// would stop being able to reach `Quickshell.env`, which several of them call.
// A plain .js keeps the host document's scope, and a singleton the document
// imports is in it: verified before this file was written.
//
// The null-safe forms are the ones kept. They are supersets — the same result
// for every input the others accepted, and an answer instead of a throw for
// null and undefined.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "."

QtObject {
  id: root
  // POSIX single-quoting: wrap in quotes and replace each embedded quote with
  // '\'' — close, escape, reopen. Safe for every byte a filename can hold,
  // which is why every layer that shells out reaches for it.
  function shellQuote(s) {
    return "'" + String(s ?? "").replace(/'/g, "'\\''") + "'";
  }

  // The palette as plain 6-digit hex strings, for the places that need color
  // as TEXT rather than as a color: rich-text markup, and terminus' translation
  // of bat's ANSI output. Zenon owns the values; this is only the form.
  function zenonHex() {
    return {
      black: Zenon.hex(Zenon.black), white: Zenon.hex(Zenon.white),
      muted: Zenon.hex(Zenon.muted), red: Zenon.hex(Zenon.red),
      green: Zenon.hex(Zenon.green), yellow: Zenon.hex(Zenon.yellow),
      blue: Zenon.hex(Zenon.blue), magenta: Zenon.hex(Zenon.magenta),
      cyan: Zenon.hex(Zenon.cyan), pink: Zenon.hex(Zenon.pink),
      sand: Zenon.hex(Zenon.sand)
    };
  }

  // The three characters that turn text into markup. Enough for Qt's
  // StyledText and RichText, which is all this shell renders.
  // A local path as a file:// URL, every segment percent-encoded. "file://"
  // pasted onto a raw path is read by Qt — and by whatever a drag lands in —
  // as a URL, so a # in a filename started a fragment, a ? a query, and a %
  // an escape: the image never loaded and the dropped file was a different
  // name. encodeURI leaves # and ? alone, which is the same bug.
  // SENTENCE CASE, the suite's one rule for words a person reads: the first
  // letter up, the rest as written (user, 2026-10-19 — hint words, chips,
  // badges and tooltips too). Leading spaces, glyphs and punctuation are
  // stepped over to the first letter; a word that already starts with a
  // capital, a digit or a key name in a chip is left as it is.
  function sentence(s) {
    const t = String(s === undefined || s === null ? "" : s);
    const m = t.match(/^([^A-Za-z]*)([a-z])/);
    return m ? m[1] + m[2].toUpperCase() + t.slice(m[0].length) : t;
  }
  function fileUrl(p) {
    return "file://" + String(p ?? "").split("/").map(encodeURIComponent).join("/");
  }

  function escapeHtml(s) {
    return String(s ?? "")
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  // A LINK FROM SOMEONE ELSE'S TEXT (a PDF, an issue, release notes, store
  // data): opened only when it is the web or mail. xdg-open hands file:,
  // a .desktop or any scheme handler whatever it names (audit 2026-10-26).
  // false when refused.
  function openLink(u) {
    const s = String(u ?? "").trim();
    if (!/^(https?|mailto):/i.test(s)) return false;
    Quickshell.execDetached(["xdg-open", s]);
    return true;
  }

  // A FILE THAT COULD NOT BE READ, KEPT (audit, 2026-10-27). A state file
  // that does not parse came back as nothing — no settings, no accounts, no
  // collections — and the next save wrote that nothing over it. Called where
  // a parse fails on text that was there: a copy beside it as
  // <name>.broken-<when>, and a notice from `app`.
  function keepAside(path, app) {
    const p = String(path || "");
    if (p === "") return;
    const name = p.replace(/^.*\//, "");
    Quickshell.execDetached(["sh", "-c", 'cp -f -- "$1" "$1.broken-$(date +%Y%m%d-%H%M%S)"', "sh", p]);
    Quickshell.execDetached(["notify-send", "-a", String(app || "zenworks"), name + " could not be read",
      "A copy is kept beside it as " + name + ".broken-… — " + String(app || "it") + " goes on without what it held."]);
  }

  // THE CLIPBOARD, as text. copy hands it to wl-copy as an argument, never
  // spliced into the shell line. paste asks Quickshell first; on Wayland that
  // read can come back empty while another client owns the clipboard (a token
  // copied in the browser, 2026-10-11) — then wl-paste is asked, and `done`
  // gets its answer later. One read at a time: a second paste while wl-paste
  // is out replaces the first one's `done`.
  //
  // Long text goes on stdin instead (audit, 2026-10-27): one argument holds
  // 128 KiB at the most, and past it the copy failed without a word — a
  // whole transaction log selected in Ceres, a diff in Delphi.
  function copy(t) {
    const s = String(t ?? "");
    if (s.length < 32768) {
      Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy >/dev/null 2>&1", "_", s]);
      return;
    }
    root.copier.createObject(root, { input: s, running: true });
  }
  readonly property Component copier: Component {
    Process {
      id: cp
      property string input: ""
      command: ["sh", "-c", "wl-copy >/dev/null 2>&1"]
      stdinEnabled: true
      // written once it is really there (AtomicWriter's lesson)
      onStarted: { cp.write(cp.input); cp.stdinEnabled = false; }
      onExited: cp.destroy()
    }
  }
  function paste(done) {
    const t = String(Quickshell.clipboardText || "");
    if (t !== "") { done(t); return; }
    pasteProc.done = done;
    if (!pasteProc.running) pasteProc.running = true;
  }
  property Process pasteProc: Process {
    property var done: null
    command: ["wl-paste", "--no-newline", "--type", "text/plain"]
    stdout: StdioCollector {
      onStreamFinished: {
        const f = pasteProc.done;
        pasteProc.done = null;
        if (f && text !== "") f(String(text));
      }
    }
  }
}
