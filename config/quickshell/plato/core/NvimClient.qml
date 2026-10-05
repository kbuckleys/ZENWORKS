// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The only thing in plato that knows there is an nvim, or how to talk to it.
// Everything above this sees methods and signals; the JSON-lines protocol
// (see nvim/lua/plato/bridge.lua) stays in here.
//
// NVIM IS NOT OUR CHILD. It is started detached, with its socket named after
// the session, because a shell reload destroys this object and everything
// around it — and a child would die with it, taking unsaved edits along. A
// rebuilt client with the same sessionId simply reconnects to the nvim that
// is still there. The bridge, not this file, makes sure an nvim with nobody
// connected does not linger (see GRACE_MS there).

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: client
  visible: false

  // names the nvim this client belongs to; its socket is derived from it
  property string sessionId: ""
  // true: start an nvim for this session. false: one is already running (a
  // client rebuilt after a reload) and only needs finding again.
  property bool spawn: true

  readonly property string socketPath:
    Quickshell.env("XDG_RUNTIME_DIR") + "/plato/" + client.sessionId + ".sock"
  // resolved from this file, not from the shell root, so plato works the same
  // whichever config loads it
  readonly property string initPath:
    decodeURIComponent(String(Qt.resolvedUrl("../nvim/init.lua")).replace(/^file:\/\//, ""))
  readonly property bool ready: sock.connected && client._hello

  signal hello()
  // keys typed into the editor, as they go: EditorState shows a command half
  // typed from them (keysSent)
  signal keysSent(string keys)
  signal view(var ev)
  signal theme(var ev)
  signal pum(var ev)
  signal pumSelect(int selected)
  signal cmdline(var ev)
  signal cmdlinePos(int pos)
  signal message(var ev)
  signal messagesCleared()
  // a yank or a delete, as screen cells, for the editor to light up (see
  // editing.lua's flashes)
  signal flash(var ev)
  // :w on a buffer with no file: plato's save dialog is wanted instead
  signal saveAsWanted(bool quit)
  // the minimap's lines (minimap.lua)
  signal minimap(var ev)
  // the language server's references, for the picker (peek.lua)
  signal references(var items)
  // a question for a card with choices (bridge.lua's ask), and one taken
  // back; answer() sends the choice
  signal ask(var ev)
  signal unask(int n)
  // z=: suggestions for a word (spell.lua)
  signal spellSuggest(var ev)
  // nvim went away and is not coming back — `:q`, a crash, the grace ran out
  signal exited()

  property bool _hello: false
  property int _nextId: 1
  property var _pending: ({})
  property int _tries: 0

  // ── keypress → frame timing, for the phase 1 gate ──────────────────
  // PLATO_LATENCY=1 in the shell's environment logs p50/p95 every 200 keys.
  readonly property bool _measure: Quickshell.env("PLATO_LATENCY") === "1"
  property real _keyAt: 0
  property var _lat: []

  function start() {
    if (client.sessionId === "") return;
    if (client.spawn) {
      // setsid: its own session, so nothing aimed at the shell's process
      // group reaches it either. stderr goes to a log beside plato's state.
      //
      // NVIM_APPNAME=quickshell/plato/nvim makes nvim's config directory this
      // repository's plato/nvim — so vim.pack's lockfile is written there and
      // travels with it — and keeps its data, state and plugins apart from
      // any other nvim's, under ~/.local/{share,state}/quickshell/plato/nvim.
      const log = Quickshell.env("HOME") + "/.local/state/quickshell/plato/nvim.log";
      //
      // AND IT TAKES NOTHING OF THE SHELL'S WITH IT. A detached child inherits
      // every file the shell has open, and a stuck engine was found holding
      // four of the GPU's render-node handles and an io_uring it has no use
      // for. Everything past stdin/out/err is closed before nvim starts.
      Quickshell.execDetached(["bash", "-c",
        "for f in /proc/$$/fd/*; do n=${f##*/}; [ \"$n\" -gt 2 ] 2>/dev/null && eval \"exec $n>&-\"; done; "
        + "mkdir -p \"$(dirname \"$1\")\" \"$(dirname \"$3\")\"; "
        + "NVIM_APPNAME=quickshell/plato/nvim PLATO_SOCK=\"$1\" exec setsid nvim --headless -u \"$2\" "
        + "</dev/null >/dev/null 2>>\"$3\"",
        "sh", client.socketPath, client.initPath, log]);
    }
    client._tries = 0;
    retry.start();
  }

  // Ask. `done(result, error)` is optional; without it nothing is held for
  // the reply.
  function request(method, params, done) {
    if (!sock.connected) return false;
    const msg = { method: method, params: params || {} };
    if (done) {
      msg.id = client._nextId++;
      client._pending[msg.id] = done;
    }
    sock.write(JSON.stringify(msg) + "\n");
    sock.flush();
    return true;
  }

  function input(keys) {
    if (keys === "") return;
    client.keysSent(keys);
    if (client._measure) client._keyAt = Date.now();
    client.request("input", { keys: keys });
  }
  function open(path) { client.request("open", { path: path }); }
  function resize(rows, cols) { client.request("resize", { rows: rows, cols: cols }); }
  function scrollTo(win, line) { client.request("scrollTo", { win: win, line: line }); }
  function scroll(lines) { client.request("scroll", { lines: lines }); }
  function cmd(command) { client.request("cmd", { cmd: command }); }
  function openAt(path, line, col) { client.request("openAt", { path: path, line: line, col: col }); }
  function bufShow(id) { client.request("bufShow", { id: id }); }
  function bufClose(id, force) { client.request("bufClose", { id: id, force: force }); }
  // the settings sheet's editing settings, all at once (editing.lua)
  function options(opts) { client.request("options", opts); }
  function answer(n, choice) { client.request("answer", { ask: n, choice: choice }); }
  function pumPick(index) { client.request("pumPick", { index: index }); }
  function mouse(button, action, mods, row, col) {
    client.request("mouse", { button: button, action: action, mods: mods, row: row, col: col });
  }
  // the window was closed on purpose: nvim goes now, not after the grace
  function quit() {
    client.request("quit", {});
  }

  function _handle(line) {
    let ev;
    try { ev = JSON.parse(line); } catch (e) {
      console.warn("plato: bad line from nvim:", line);
      return;
    }
    if (ev.id !== undefined) {
      const done = client._pending[ev.id];
      delete client._pending[ev.id];
      if (done) done(ev.result, ev.error);
      else if (ev.error) console.warn("plato:", ev.error);
      return;
    }
    switch (ev.event) {
      case "view":
        if (client._measure && client._keyAt > 0) client._noteLatency();
        client.view(ev);
        break;
      case "hello": client._hello = true; client.hello(); break;
      case "theme": client.theme(ev); break;
      case "pum": client.pum(ev); break;
      case "pum_select": client.pumSelect(ev.selected); break;
      case "cmdline": client.cmdline(ev); break;
      case "cmdline_pos": client.cmdlinePos(ev.pos); break;
      case "msg": client.message(ev); break;
      case "msg_clear": client.messagesCleared(); break;
      case "flash": client.flash(ev); break;
      case "saveAs": client.saveAsWanted(ev.quit === true); break;
      case "minimap": client.minimap(ev); break;
      case "refs": client.references(ev.items); break;
      case "ask": client.ask(ev); break;
      case "unask": client.unask(ev.ask); break;
      case "spell": client.spellSuggest(ev); break;
      case "error": console.warn("plato: nvim:", ev.message); break;
    }
  }

  function _noteLatency() {
    client._lat.push(Date.now() - client._keyAt);
    client._keyAt = 0;
    if (client._lat.length < 200) return;
    const s = client._lat.slice().sort((a, b) => a - b);
    console.log("plato latency: p50", s[Math.floor(s.length * 0.5)],
      "ms  p95", s[Math.floor(s.length * 0.95)], "ms  max", s[s.length - 1], "ms");
    client._lat = [];
  }

  // The socket appears a moment after nvim starts, so the first connects are
  // expected to fail: keep knocking for a few seconds before giving up.
  Timer {
    id: retry
    interval: 50
    repeat: true
    onTriggered: {
      if (sock.connected) { retry.stop(); return; }
      if (++client._tries > 120) {
        retry.stop();
        console.warn("plato: no nvim at", client.socketPath);
        client.exited();
        return;
      }
      sock.connected = true;
    }
  }

  Socket {
    id: sock
    path: client.socketPath
    parser: SplitParser { onRead: (data) => client._handle(data) }
    onConnectionStateChanged: {
      if (sock.connected) { retry.stop(); return; }
      // Connected once and now not: nvim has gone. Before the first hello it
      // is just the socket not being there yet, which retry is handling.
      if (client._hello) {
        client._hello = false;
        lost.restart();
      }
    }
  }

  // NOT SAID AT ONCE. A reload destroys this socket too, and from in here
  // that looks exactly like nvim leaving — but the window reacting to it
  // would forget its session, and the rebuilt window would have nothing to
  // reconnect to. A timer is destroyed with everything else in a reload, so
  // this only ever fires when the client is still alive to hear it: nvim
  // really went.
  Timer {
    id: lost
    interval: 150
    onTriggered: client.exited()
  }

  Component.onCompleted: client.start()
}
