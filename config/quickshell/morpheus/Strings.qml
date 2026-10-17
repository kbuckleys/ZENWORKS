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
  function fileUrl(p) {
    return "file://" + String(p ?? "").split("/").map(encodeURIComponent).join("/");
  }

  function escapeHtml(s) {
    return String(s ?? "")
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  // THE CLIPBOARD, as text. copy hands it to wl-copy as an argument, never
  // spliced into the shell line. paste asks Quickshell first; on Wayland that
  // read can come back empty while another client owns the clipboard (a token
  // copied in the browser, 2026-10-11) — then wl-paste is asked, and `done`
  // gets its answer later. One read at a time: a second paste while wl-paste
  // is out replaces the first one's `done`.
  function copy(t) {
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy >/dev/null 2>&1", "_", String(t ?? "")]);
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
