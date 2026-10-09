// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Plato's plugins, known once for every plato window: which are installed
// (plato/nvim/plugins.json), and what vim.pack would update.
//
// The one place plugins are installed, removed, switched on and off, and
// updated. The status line's indicator and the plugin panel are both views
// of this: the panel asks it to act, the indicator shows how many updates
// are waiting.
//
// INSTALLING writes the plugin into plugins.json and has a throwaway nvim
// clone it (nvim/pack.lua); every open window's engine is then told to load
// it (`loaded`), so it works at once. REMOVING takes it out of the list and
// off the disk; an engine that already loaded it keeps it until it closes.
// SWITCHING OFF keeps it on disk but no longer loads it.
//
// HOW. A throwaway nvim runs nvim/pack.lua, which lets vim.pack fetch and
// write its confirmation buffer and prints it; editor/pack.js reads that.
// Never in an editor's own nvim — vim.pack waits on the network, and the
// editor would wait with it. See pack.lua.
//
// WHEN. Not at shell startup — plato costs nothing until it is opened — but
// a little after the first window opens, and then no more than every few
// hours while windows stay open. Quietly: a check that fails in the
// background (no network) shows nothing, and the panel says why when opened.

import QtQuick
import Quickshell
import Quickshell.Io
import "../editor/pack.js" as Pack

Scope {
  id: plugins

  // "" | "checking" | "ready" | "applying" | "done" | "failed"
  property string phase: ""
  // what the worker is doing now, for the panel: "" | "check" | "apply" |
  // "install" | "remove"
  readonly property string doing: worker.running ? worker.mode : ""
  property var report: ({ updates: [], errors: [], same: [], error: "" })
  property string note: ""
  property double checkedAt: 0
  readonly property int count: plugins.report.updates.length
  readonly property bool busy: worker.running

  // how stale a check may be before a window opening asks again
  readonly property int staleMs: 6 * 3600 * 1000

  // the last answer, across a shell reload: a reload is not new information
  PersistentProperties {
    id: kept
    reloadableId: "plato-plugins"
    property string report: ""
    property double checkedAt: 0
    onReloaded: {
      try { plugins.report = JSON.parse(kept.report); } catch (e) {}
      plugins.checkedAt = kept.checkedAt;
      if (plugins.checkedAt > 0) plugins.phase = "ready";
    }
  }

  readonly property string script:
    decodeURIComponent(String(Qt.resolvedUrl("../nvim/pack.lua")).replace(/^file:\/\//, ""))
  function _local(rel) {
    return decodeURIComponent(String(Qt.resolvedUrl(rel)).replace(/^file:\/\//, ""));
  }
  readonly property string manifestPath: plugins._local("../nvim/plugins.json")
  readonly property string configDir: plugins._local("../nvim/lua/plato/config")

  // ── what is installed ──────────────────────────────────────────────
  // plugins.json, read whenever it changes on disk (by this, or by hand):
  // [{ src, name, enabled, configured }] — configured: it has a config file
  property var installed: []
  property var configured: ({})
  // an engine should load this plugin now: it was just installed, or
  // switched on (PlatoManager tells every window)
  signal loaded(string name)

  function nameOf(src) {
    return String(src).replace(/\/+$/, "").replace(/.*\//, "").replace(/\.git$/, "");
  }
  FileView {
    id: manifestFile
    path: plugins.manifestPath
    watchChanges: true
    onFileChanged: manifestFile.reload()
    onLoaded: plugins._readManifest()
  }
  function _readManifest() {
    let list = [];
    try { list = JSON.parse(manifestFile.text()).plugins || []; } catch (e) {}
    plugins.installed = list.filter((p) => p && typeof p.src === "string" && p.src !== "")
      .map((p) => ({ src: p.src, name: plugins.nameOf(p.src), enabled: p.enabled !== false,
                     version: p.version }));
    configLister.running = true;
  }
  function _writeManifest(list) {
    const out = list.map((p) => {
      const o = { src: p.src, enabled: p.enabled !== false };
      if (p.version) o.version = p.version;
      return o;
    });
    manifestFile.setText(JSON.stringify({ plugins: out }, null, 2) + "\n");
    plugins.installed = list;
  }
  // which plugins have a configuration file
  Process {
    id: configLister
    command: ["sh", "-c", "ls -1 \"$1\" 2>/dev/null", "sh", plugins.configDir]
    stdout: StdioCollector {
      id: configListed
      onStreamFinished: {
        const c = {};
        for (const f of String(configListed.text).split("\n"))
          if (/\.lua$/.test(f)) c[f.slice(0, -4)] = true;
        plugins.configured = c;
      }
    }
  }

  // "owner/repo", a github URL, or any git URL → the source to clone
  function sourceOf(input) {
    const t = String(input || "").trim().replace(/\/+$/, "");
    if (t === "") return "";
    if (/^[\w.-]+\/[\w.-]+$/.test(t)) return "https://github.com/" + t.replace(/\.git$/, "");
    if (/^(https?:\/\/|git@|ssh:\/\/)/.test(t)) return t;
    return "";
  }
  function install(input) {
    if (worker.running) return "busy";
    const src = plugins.sourceOf(input);
    if (src === "") return "not a plugin source: owner/repo, or a git URL";
    const name = plugins.nameOf(src);
    if (plugins.installed.some((p) => p.name === name)) return name + " is already installed";
    plugins._writeManifest(plugins.installed.concat([{ src: src, name: name, enabled: true }]));
    plugins.phase = "applying";
    plugins.note = "Installing " + name + "…";
    plugins.run("install", [name]);
    return "";
  }
  function remove(name) {
    if (worker.running) return;
    plugins._writeManifest(plugins.installed.filter((p) => p.name !== name));
    plugins.phase = "applying";
    plugins.note = "Removing " + name + "…";
    plugins.run("remove", [name]);
  }
  function setEnabled(name, on) {
    plugins._writeManifest(plugins.installed.map((p) =>
      p.name === name ? Object.assign({}, p, { enabled: on }) : p));
    if (on) plugins.loaded(name);
    plugins.note = on ? name + " is on." : name + " is off from the next plato window on.";
    plugins.phase = "done";
  }
  // its configuration file, made from a template the first time: the panel
  // opens it in the editor
  function configFile(name) {
    return plugins.configDir + "/" + name + ".lua";
  }
  function ensureConfig(name, then) {
    const f = plugins.configFile(name);
    const head = "-- " + name + ": run by plato after the plugin loads.\n"
      + "-- Most plugins want their setup() called; see the plugin's README.\n"
      + "--\n-- require(\"" + name.replace(/\.nvim$|\.lua$/, "").replace(/^nvim-/, "")
      + "\").setup({})\n";
    maker.then = then;
    maker.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\"; [ -e \"$1\" ] || printf '%s' \"$2\" > \"$1\"",
      "sh", f, head];
    maker.running = true;
  }
  Process {
    id: maker
    property var then: null
    onExited: {
      configLister.running = true;
      if (maker.then) maker.then();
      maker.then = null;
    }
  }

  function run(mode, names) {
    worker.mode = mode;
    worker.names = names || [];
    worker.command = ["env", "NVIM_APPNAME=quickshell/plato/nvim", "PLATO_PACK=" + mode,
      "PLATO_PACK_NAMES=" + (names || []).join(","),
      "nvim", "--headless", "-i", "NONE", "--clean", "-c", "luafile " + plugins.script];
    worker.running = true;
  }

  function check() {
    if (worker.running) return;
    plugins.phase = "checking";
    plugins.note = "";
    plugins.run("check", []);
  }
  // a check only if the last one is old: what a window opening asks for
  function checkIfStale() {
    if (Date.now() - plugins.checkedAt > plugins.staleMs) plugins.check();
  }
  function apply(names) {
    if (worker.running || !names || names.length === 0) return;
    plugins.phase = "applying";
    plugins.note = names.length === 1 ? "Updating " + names[0] + "…"
      : "Updating " + names.length + " plugins…";
    plugins.run("apply", names);
  }

  Process {
    id: worker
    property string mode: ""
    property var names: []
    stdout: StdioCollector {
      id: said
      onStreamFinished: {
        const text = said.text;
        if (worker.mode === "check") {
          const r = Pack.parse(text);
          if (r.error !== "") {
            plugins.phase = "failed";
            plugins.note = r.error;
            return;
          }
          plugins.report = r;
          plugins.checkedAt = Date.now();
          kept.report = JSON.stringify(r);
          kept.checkedAt = plugins.checkedAt;
          plugins.phase = "ready";
          return;
        }
        if (/^OK/m.test(text)) {
          plugins.phase = "done";
          const name = worker.names[0] || "";
          if (worker.mode === "install") {
            plugins.note = name + " is installed.";
            plugins.loaded(name);
          } else if (worker.mode === "remove") {
            plugins.note = name + " is removed. Windows that loaded it keep it until they close.";
          } else {
            plugins.note = "Updated. New plato windows use the new versions.";
            // what is left, now
            Qt.callLater(plugins.check);
          }
        } else {
          // an install that failed is not installed
          if (worker.mode === "install")
            plugins._writeManifest(plugins.installed.filter((p) => p.name !== worker.names[0]));
          plugins.phase = "failed";
          plugins.note = String(text).replace(/^ERROR /, "").trim() || "The update failed.";
        }
      }
    }
  }

  // ── TREESITTER PARSERS ─────────────────────────────────────────────
  // The plugin panel's third page. nvim/parsers.lua, in a throwaway nvim
  // like pack.lua, lists every language nvim-treesitter pins a grammar for
  // and builds the ones asked for with the C compiler (no tree-sitter CLI).
  // Built parsers go to every open engine at once (`parsersBuilt`).
  readonly property string parserScript: plugins._local("../nvim/parsers.lua")
  // [{ lang, installed, bundled, revision, built, generate, tier, requires }]
  property var parsers: []
  // the language of the file being edited when the list was asked for
  property string parserWant: ""
  property bool parserCli: false
  // "" | "listing" | "building" | "done" | "failed"
  property string parserPhase: ""
  property string parserNote: ""
  readonly property bool parserBusy: parserWorker.running
  signal parsersBuilt(var langs)

  function listParsers(ft) {
    if (parserWorker.running) return;
    plugins.parserPhase = "listing";
    plugins._runParsers("list", [], ft || "");
  }
  function installParsers(names) {
    if (parserWorker.running || !names || names.length === 0) return;
    plugins.parserPhase = "building";
    plugins.parserNote = "Building " + names.join(", ") + "…";
    plugins._runParsers("install", names, "");
  }
  function removeParsers(names) {
    if (parserWorker.running || !names || names.length === 0) return;
    plugins.parserPhase = "building";
    plugins.parserNote = "Removing " + names.join(", ") + "…";
    plugins._runParsers("remove", names, "");
  }
  function _runParsers(mode, names, ft) {
    parserWorker.mode = mode;
    parserWorker.ft = ft;
    parserWorker.command = ["env", "NVIM_APPNAME=quickshell/plato/nvim", "PLATO_PARSERS=" + mode,
      "PLATO_PARSERS_NAMES=" + names.join(","), "PLATO_PARSERS_FT=" + ft,
      "nvim", "--headless", "-i", "NONE", "--clean", "-c", "luafile " + plugins.parserScript];
    parserWorker.running = true;
  }
  Process {
    id: parserWorker
    property string mode: ""
    property string ft: ""
    stdout: StdioCollector {
      id: parserSaid
      onStreamFinished: {
        const lines = String(parserSaid.text).split("\n");
        const err = lines.find((l) => l.startsWith("ERROR "));
        if (err) { plugins.parserPhase = "failed"; plugins.parserNote = err.slice(6); return; }
        if (parserWorker.mode === "list") {
          const j = lines.find((l) => l.startsWith("JSON "));
          try {
            const r = JSON.parse(j.slice(5));
            plugins.parsers = r.langs || [];
            plugins.parserWant = r.want || "";
            plugins.parserCli = r.cli === true;
            plugins.parserPhase = "";
          } catch (e) {
            plugins.parserPhase = "failed";
            plugins.parserNote = "the parser list could not be read";
          }
          return;
        }
        const ok = lines.filter((l) => l.startsWith("OK ")).map((l) => l.slice(3).trim());
        const fail = lines.filter((l) => l.startsWith("FAIL ")).map((l) => l.slice(5));
        if (parserWorker.mode === "install" && ok.length > 0) plugins.parsersBuilt(ok);
        plugins.parserPhase = fail.length > 0 ? "failed" : "done";
        plugins.parserNote = fail.length > 0
          ? fail.map((f) => f.replace(/^(\S+) /, "$1: ")).join("  ·  ")
          : parserWorker.mode === "install"
            ? (ok.join(", ") + (ok.length === 1 ? " is built." : " are built.") + " Open files use it now.")
            : (ok.join(", ") + " removed. Windows that loaded it keep it until they close.");
        // the list again, with what changed
        Qt.callLater(() => plugins.listParsers(parserWorker.ft));
      }
    }
  }

  // while windows are open, look again now and then
  property bool watching: false
  Timer {
    interval: 20 * 1000
    running: plugins.watching
    onTriggered: plugins.checkIfStale()
  }
  Timer {
    interval: plugins.staleMs
    running: plugins.watching
    repeat: true
    onTriggered: plugins.check()
  }
}
