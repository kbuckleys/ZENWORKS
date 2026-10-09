// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Plato, the editor: the part of it that is always in the shell, which is
// almost nothing.
//
// NOT BUILT AT STARTUP. terminus compiles its window type a second after the
// shell comes up and keeps a hidden window ready (TerminusManager.qml) — a
// file manager is opened constantly and should be instant. An editor is not,
// and the rule for this one is that it costs nothing until it is asked for.
// So until the first `Plato open` this is an IPC handler and an empty list:
// the window type is compiled then, asynchronously, and let go of again when
// the last window closes.
//
// SURVIVING A RELOAD. quickshell reloads the whole config when a file it
// loaded changes — which includes saving a file of this shell from inside
// plato. Every window is torn down by that, but its nvim is not (it is
// started detached, see core/NvimClient.qml). The sessions are kept in
// PersistentProperties across the reload, and each is rebuilt and reconnects
// to the nvim that is still holding its buffers.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../morpheus/lagnotes.js" as LagNotes
import "core"

Scope {
  id: mgr

  // terminus, handed in by shell.qml, for open and save dialogs
  property var fileManager: null
  // artemis, handed in by shell.qml: Ctrl-P is its index, scoped to a project
  property var finder: null

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────
  // Not shipped as a file: written into ~/.local/share/applications on
  // startup when it is missing, with this machine's path to bin/plato (see
  // Desktop.installCommand). That is what file managers, artemis and
  // `gio mime` find it by. One already there is left alone.
  Process {
    running: true
    command: ["sh", "-c", Desktop.installCommand("plato", {
      Type: "Application",
      Name: "Plato",
      GenericName: "Text Editor",
      Comment: "Edit text, in ZENWORKS",
      Icon: "accessories-text-editor",
      Categories: ["Development", "TextEditor"],
      Keywords: ["editor", "text", "code", "nvim"],
      Exec: Desktop.execLine(Quickshell.shellDir + "/plato/bin/plato", "%F"),
      Terminal: "false",
      StartupNotify: "false",
      MimeType: [
        "text/plain", "text/x-qml", "text/x-lua", "text/markdown", "text/x-sh",
        "text/x-python", "text/x-csrc", "text/x-c++src", "text/x-java",
        "text/csv", "text/css", "text/x-log", "application/json",
        "application/ld+json", "application/x-toml", "application/x-yaml",
        "application/x-shellscript", "application/javascript",
        "application/xml", "application/x-perl", "inode/x-empty"
      ],
    })]
  }

  property var wins: []
  property var _comp: null
  property var _waiting: []

  // ── what every window shares: plato's settings ────────────────────
  // core/Settings.qml, drawn by the settings sheet in every window (Space ,
  // or Ctrl ,) and kept in the shell's state directory as plato.json. Every
  // plato window follows a change the moment it is made. Only the editor's
  // text follows the size — tabs, menus and the status line keep the
  // shell's, as a browser's chrome does.
  readonly property alias settings: settings
  Settings { id: settings }
  // the chrome's own size: the shell's 16, whatever the editor's text is
  readonly property int chromeSize: 16
  readonly property int defaultSize: settings.fontSize
  readonly property string fontFamily: settings.fontFamily !== "" ? settings.fontFamily
    : Zenon.faceFixed
  readonly property int fontWeight: ({
    regular: Font.Normal, medium: Font.Medium, semibold: Font.DemiBold, bold: Font.Bold,
  })[settings.fontWeight] || Font.DemiBold
  readonly property bool treeShown: settings.treeShown
  readonly property int treeWidth: settings.treeWidth

  // ── ZOOM IS PER TAB ────────────────────────────────────────────────
  // <C-=> <C--> and Ctrl+wheel make the tab you are in bigger or smaller and
  // leave the others alone; <C-0> puts it back to the settings' size. A tab is
  // known by its file (or, with none, its buffer), and what is kept is how
  // many steps it is off the settings' size — so changing that size in the sheet
  // moves the zoomed tabs along with the rest. Kept across a reload, and
  // shared by every window: the same file is as big wherever it is open.
  property var zooms: ({})
  function sizeFor(key) {
    const d = mgr.zooms[key];
    return Math.max(10, Math.min(32, mgr.defaultSize + (d !== undefined ? d : 0)));
  }
  function zoom(key, step) {
    const z = Object.assign({}, mgr.zooms);
    const next = step === 0 ? mgr.defaultSize
      : Math.max(10, Math.min(32, mgr.sizeFor(key) + step));
    if (next === mgr.defaultSize) delete z[key];
    else z[key] = next - mgr.defaultSize;
    mgr.zooms = z;
    kept.zooms = JSON.stringify(z);
  }
  function setTree(shown) { settings.set("treeShown", shown); }
  // Dragging the edge moves the tree at once, and tells the settings when it is
  // let go: a store written on every pixel of a drag is a store rewriting
  // its file sixty times a second.
  property int liveTreeWidth: -1
  function dragTree(w) { mgr.liveTreeWidth = w; }
  function dropTree() {
    if (mgr.liveTreeWidth > 0) settings.set("treeWidth", mgr.liveTreeWidth);
    mgr.liveTreeWidth = -1;
  }

  // ── WHAT THE PALETTE IS USED FOR ───────────────────────────────────
  // Every action and ex command run from the command palette, counted and
  // dated, so the palette can put what you reach for first (Picker.qml). In
  // the shell's state directory as plato-palette.json; shared by every
  // window. `usage` is { key: [count, lastUsedMs] }.
  property var usage: ({})
  function used(key) {
    const u = Object.assign({}, mgr.usage);
    const was = u[key] || [0, 0];
    u[key] = [was[0] + 1, Date.now()];
    mgr.usage = u;
    usageFile.setText(JSON.stringify(u));
  }
  // how much a key has been used: the count, fading by half every fortnight
  function usageScore(key) {
    const u = mgr.usage[key];
    if (!u) return 0;
    return u[0] * Math.pow(0.5, (Date.now() - u[1]) / (14 * 86400000));
  }
  FileView {
    id: usageFile
    path: Quickshell.statePath("plato-palette.json")
    printErrors: false
    onLoaded: { try { mgr.usage = JSON.parse(usageFile.text() || "{}"); } catch (e) {} }
  }

  // ── EACH PROJECT'S TREE, AS YOU LEFT IT ───────────────────────────
  // Which directories were open in the file tree, per project root, for
  // FileTree's `memory`: every window, and the next session, opens a
  // project's tree the way it was. plato-trees.json in the state directory,
  // written a moment after the last change.
  property var treeDirs: ({})
  readonly property var treeMemory: ({
    recall: (root) => mgr.treeDirs[root] || [],
    keep: (root, dirs) => {
      const t = Object.assign({}, mgr.treeDirs);
      t[root] = dirs;
      mgr.treeDirs = t;
      treeSave.restart();
    },
  })
  Timer { id: treeSave; interval: 600; onTriggered: treeFile.setText(JSON.stringify(mgr.treeDirs)) }
  FileView {
    id: treeFile
    path: Quickshell.statePath("plato-trees.json")
    blockLoading: true
    printErrors: false
    Component.onCompleted: { try { mgr.treeDirs = JSON.parse(treeFile.text() || "{}"); } catch (e) {} }
  }

  // ── plugin updates, known once for every window ───────────────────
  // see core/Plugins.qml; it looks a little after the first window opens,
  // and stops looking when the last one closes
  readonly property alias plugins: pluginWatch
  Plugins {
    id: pluginWatch
    watching: mgr.wins.length > 0
    // installed or switched on: every engine loads it now, not next time
    onLoaded: (name) => { for (const w of mgr.wins) w.loadPlugin(name); }
    // parsers built: every engine starts treesitter on the files they fit
    onParsersBuilt: (langs) => { for (const w of mgr.wins) w.parsersAdded(langs); }
  }

  PersistentProperties {
    id: kept
    reloadableId: "plato"
    // the session ids of the open windows, as JSON: a plain string is what
    // is certain to come through a reload intact
    property string sessions: "[]"
    property string zooms: "{}"
    onReloaded: {
      try { mgr.zooms = JSON.parse(kept.zooms); } catch (e) {}
      let ids = [];
      try { ids = JSON.parse(kept.sessions); } catch (e) {}
      kept.sessions = "[]";
      // a capture window stays one ({ id, capture }); older lists are ids
      for (const s of ids) {
        if (typeof s === "string") mgr.spawn("", s, true);
        else mgr.spawn("", s.id, true, null, s.capture === true);
      }
    }
  }

  function _remember() {
    kept.sessions = JSON.stringify(mgr.wins.map((w) => ({ id: w.sessionId, capture: w.capture })));
  }

  // Run `fn` once the window type is compiled, compiling it if this is the
  // first window since plato was last closed.
  function _withComponent(fn) {
    if (mgr._comp && mgr._comp.status === Component.Ready) { fn(); return; }
    mgr._waiting.push(fn);
    if (mgr._comp) return;
    const comp = Qt.createComponent(Qt.resolvedUrl("PlatoWindow.qml"), Component.Asynchronous);
    mgr._comp = comp;
    const settle = () => {
      if (comp.status === Component.Loading) return;
      const queued = mgr._waiting;
      mgr._waiting = [];
      if (comp.status !== Component.Ready) {
        console.warn("plato:", comp.errorString());
        mgr._comp = null;
        // nothing is coming: opens must not keep waiting for it
        mgr._queued = null;
        return;
      }
      for (const f of queued) f();
    };
    if (comp.status === Component.Loading) comp.statusChanged.connect(settle);
    else settle();
  }

  function _newId() {
    return Date.now().toString(36) + Math.floor(Math.random() * 1e8).toString(36);
  }

  function spawn(path, id, reconnect, then, capture) {
    mgr._withComponent(() => {
      const t0 = Date.now();
      const w = mgr._comp.createObject(mgr, {
        mgr: mgr,
        sessionId: id || mgr._newId(),
        reconnect: !!reconnect,
        openPath: path || "",
        capture: !!capture,
      });
      LagNotes.mark("plato window", t0);
      if (!w) {
        console.warn("plato: the window could not be made:", mgr._comp.errorString());
        // nothing is coming: opens waiting for this window must not wait
        // forever — every later `Plato open` would have queued behind it
        mgr._queued = null;
        return;
      }
      mgr.wins = mgr.wins.concat([w]);
      mgr._remember();
      w.visible = true;
      if (then) then();
    });
  }

  // called by a window on its way out
  function forget(w) {
    mgr.wins = mgr.wins.filter((x) => x !== w);
    mgr._remember();
    // the last one: let the compiled type go with it
    if (mgr.wins.length === 0) mgr._comp = null;
  }

  // "~" and relative paths: relative to home, since an ipc call does not
  // carry the caller's directory. bin/plato resolves against the shell's
  // own directory before it gets here.
  function _expand(path) {
    let p = String(path || "").trim();
    if (p === "") return "";
    const home = Quickshell.env("HOME");
    if (p === "~") return home;
    if (p.startsWith("~/")) return home + p.slice(1);
    if (!p.startsWith("/")) return home + "/" + p;
    return p;
  }

  // Open a file: in the newest window if there is one, a new window if not.
  // Nothing to open, with a window up, means "show me plato" — not another
  // empty window.
  //
  // A WINDOW ON ITS WAY COUNTS. The first open compiles the window type
  // asynchronously, and `plato a b c` sends b and c while that is still
  // happening: seeing no window yet, each spawned one of its own. Opens that
  // arrive while the first window is being made wait for it instead.
  property var _queued: null
  function open(path) {
    const p = mgr._expand(path);
    if (mgr._queued !== null) {
      if (p !== "") mgr._queued.push(p);
      return;
    }
    // the newest window that is an editor, not a capture note
    const eds = mgr.wins.filter((w) => !w.capture);
    if (eds.length > 0) {
      if (p !== "") eds[eds.length - 1].openFile(p);
      // in the lua dispatcher's words, as ceres and oracle focus theirs
      Hyprland.dispatch('hl.dsp.focus({ window = "title:^(plato)$" })');
      return;
    }
    mgr._queued = [];
    mgr.spawn(p, "", false, () => {
      const more = mgr._queued || [];
      mgr._queued = null;
      const w = mgr.wins[mgr.wins.length - 1];
      for (const q of more) w.openFile(q);
    });
  }

  // ── WAITING ON A FILE ──────────────────────────────────────────────
  // `plato --wait f`, which is how plato is $EDITOR: git, sudoedit and
  // crontab hand it a file and read it back when the editor exits, and a
  // window has no exit of its own. So bin/plato opens the file and then asks
  // this until no window has it open any more — its tab closed, or its
  // window. The waiting is bin/plato's, not the shell's, so a reload of the
  // shell (saving one of its files from plato does that) loses nothing.
  //
  // "pending" while it cannot be known: a window still being made, or one
  // that has not heard its nvim's buffers yet — the first moments, and the
  // reconnect after every reload.
  function holding(path) {
    const p = mgr._expand(path);
    if (mgr._queued !== null) return "pending";
    let unsure = false;
    for (const w of mgr.wins) {
      if (!w.settled) { unsure = true; continue; }
      if (w.openPaths.some((q) => mgr._expand(q) === p)) return "yes";
    }
    return unsure ? "pending" : "no";
  }

  // ── QUICK CAPTURE ──────────────────────────────────────────────────
  // `qs ipc call Plato capture`, from a key: a small window of its own on
  // one note (the settings' captureFile, strftime's % codes filled in, so
  // ~/notes/%Y-%m-%d.md is a daily note), the cursor at its end. Called
  // again while it is open, it goes there. Titled plato-capture, so a
  // window rule can float it.
  function strftime(fmt, d) {
    const z = (n, w) => String(n).padStart(w || 2, "0");
    const days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    const months = ["January", "February", "March", "April", "May", "June", "July",
      "August", "September", "October", "November", "December"];
    const start = new Date(d.getFullYear(), 0, 1);
    const map = {
      Y: d.getFullYear(), y: z(d.getFullYear() % 100), m: z(d.getMonth() + 1), d: z(d.getDate()),
      e: String(d.getDate()), H: z(d.getHours()), M: z(d.getMinutes()), S: z(d.getSeconds()),
      A: days[d.getDay()], a: days[d.getDay()].slice(0, 3), B: months[d.getMonth()],
      b: months[d.getMonth()].slice(0, 3), j: z(Math.floor((d - start) / 86400000) + 1, 3),
      F: d.getFullYear() + "-" + z(d.getMonth() + 1) + "-" + z(d.getDate()), "%": "%",
    };
    return String(fmt).replace(/%([A-Za-z%])/g, (m, k) => map[k] !== undefined ? map[k] : m);
  }
  function capture() {
    const open = mgr.wins.filter((w) => w.capture);
    if (open.length > 0) {
      Hyprland.dispatch('hl.dsp.focus({ window = "title:^(plato-capture)$" })');
      return;
    }
    const p = mgr._expand(mgr.strftime(settings.captureFile || "~/.local/share/quickshell/plato/scratch.md", new Date()));
    mgr.spawn(p, "", false, null, true);
  }

  IpcHandler {
    target: "Plato"

    // the capture note, in a small window of its own (see capture())
    function capture(): string {
      mgr.capture();
      return "ok";
    }

    // `qs ipc call Plato open ~/notes.md`
    function open(path: string): string {
      mgr.open(path);
      return "ok";
    }
    // whether a file is open in any window: yes, no or pending (holding())
    function holds(path: string): string {
      return mgr.holding(path);
    }
    // always a new window, even with one open
    function spawn(path: string): string {
      mgr.spawn(mgr._expand(path));
      return "ok";
    }
    // closes a window by session id, or every window with none — the same
    // way super+q does, so an unsaved buffer is rescued rather than lost
    function close(id: string): string {
      const hit = mgr.wins.filter((w) => id === "" || w.sessionId === id);
      for (const w of hit) w.finish(true);
      return hit.length + " closed";
    }
    // keys, in nvim's notation, to the newest window's editor — for scripts
    // and for testing plato without a keyboard: `qs ipc call Plato keys vjj`
    function keys(k: string): string {
      if (mgr.wins.length === 0) return "no plato window is open";
      mgr.wins[mgr.wins.length - 1].sendKeys(k);
      return "ok";
    }
    // the plugin panel, in the newest window
    function plugins(): string {
      if (mgr.wins.length === 0) return "no plato window is open";
      mgr.wins[mgr.wins.length - 1].showPlugins();
      return "ok";
    }
    // one of plato's settings: `qs ipc call Plato setting fontSize 18`; with
    // no value, what it is now
    function setting(key: string, value: string): string {
      // mgr.settings: this handler has a settings() of its own
      const s = mgr.settings.spec(key);
      if (!s) return "no such setting: " + key;
      if (value !== "") mgr.settings.set(key, s.type === "bool"
        ? (value === "1" || value.toLowerCase() === "true" || value.toLowerCase() === "on")
        : (s.type === "int" || s.type === "real") ? Number(value) : value);
      return key + " = " + String(mgr.settings.get(key));
    }
    // the settings sheet, in the newest window
    function settings(): string {
      if (mgr.wins.length === 0) return "no plato window is open";
      mgr.wins[mgr.wins.length - 1].showSettings();
      return "ok";
    }
    // the file tree in every window: shown, or put away
    function tree(): string {
      mgr.setTree(!mgr.treeShown);
      return mgr.treeShown ? "shown" : "hidden";
    }
    function list(): string {
      return mgr.wins.map((w) => w.sessionId).join("\n");
    }
  }
}
