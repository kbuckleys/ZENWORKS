// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Plato's plugins, known once for every plato window: which are installed
// (~/.config/zenworks/plato/plugins.json), and what vim.pack would update.
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
import "../../oracle"
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
  // YOURS: nvim's config directory under NVIM_APPNAME=zenworks/plato (see
  // nvim/lua/plato/plugins.lua); the shipped set beside the engine is
  // copied there the first time (seeder, below)
  readonly property string userDir: Oracle.zenworksDir + "/plato"
  readonly property string manifestPath: plugins.userDir + "/plugins.json"
  readonly property string configDir: plugins.userDir + "/lua/plato/config"

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
    // none at the first start: seeded, not an error (onLoadFailed)
    printErrors: false
    onFileChanged: manifestFile.reload()
    onLoaded: plugins._readManifest()
    // none yet: the shipped set copied in, once, then read
    onLoadFailed: if (!seeder.tried) { seeder.tried = true; seeder.running = true; }
  }
  // THE SHIPPED SET, THE FIRST TIME — what plugins.lua's M.seed() does,
  // for the panel opened before any engine started: never over a file of
  // yours, plugins.json last
  Process {
    id: seeder
    property bool tried: false
    command: ["sh", "-c",
      "u=\"$1\"; s=\"$2\"; mkdir -p \"$u/lua/plato/config\" || exit 1; "
      + "cp -n \"$s/nvim-pack-lock.json\" \"$u/\" 2>/dev/null; "
      + "cp -n \"$s\"/lua/plato/config/*.lua \"$u/lua/plato/config/\" 2>/dev/null; "
      + "cp -n \"$s/plugins.json\" \"$u/\"",
      "sh", plugins.userDir, plugins._local("../nvim")]
    onExited: manifestFile.reload()
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

  // NEVER STUCK ON "checking". A Process' stdin is a pipe that never
  // closes, so anything that stopped to ask — git for a password, ssh for a
  // host key, nvim at a prompt — waited on it for good, and the panel said
  // "checking for updates…" until the shell restarted. Now stdin is
  // /dev/null and git may not ask, and a run that still overstays is
  // stopped and said so. Each run is stamped (pack.lua prints `RUN n`
  // first): stopping a Process still hands over its partial output, and
  // that must not be read as the answer.
  property int _run: 0
  function run(mode, names) {
    plugins._run += 1;
    worker.stamp = String(plugins._run);
    worker.mode = mode;
    worker.names = names || [];
    worker.command = ["sh", "-c", "exec \"$@\" </dev/null", "sh",
      "env", "NVIM_APPNAME=zenworks/plato", "PLATO_PACK=" + mode,
      "PLATO_PACK_NAMES=" + (names || []).join(","), "PLATO_PACK_RUN=" + worker.stamp,
      "GIT_TERMINAL_PROMPT=0", "GIT_ASKPASS=true", "SSH_ASKPASS=true",
      "GIT_SSH_COMMAND=ssh -o BatchMode=yes -o ConnectTimeout=20",
      // A FETCH THAT STALLS gives up after 20 s at under 1 KB/s. GitHub
      // now and then holds one open with nothing coming (seen: nvim-lspconfig,
      // 2026-10-17), and vim.pack waited two minutes for it and then failed
      // the whole check; now that plugin errors alone and the rest report.
      "GIT_HTTP_LOW_SPEED_LIMIT=1000", "GIT_HTTP_LOW_SPEED_TIME=20",
      // and out, whatever pack.lua did: a Lua error in it left a headless
      // nvim running with nobody to quit it
      "nvim", "--headless", "-i", "NONE", "--clean", "-c", "luafile " + plugins.script,
      "-c", "qall!"];
    worker.answered = false;
    worker.running = true;
    // vim.pack gives up on its own after two minutes; a clone of a big
    // plugin on a slow line may honestly take longer
    overstay.interval = mode === "check" ? 180 * 1000 : 600 * 1000;
    overstay.restart();
  }
  // the output is handed over around the exit, in either order
  Timer {
    id: unanswered
    interval: 1000
    onTriggered: {
      if (worker.running || worker.answered || worker.stamp === "") return;
      if (plugins.phase !== "checking" && plugins.phase !== "applying") return;
      plugins.phase = "failed";
      plugins.note = "Nvim stopped without an answer.";
    }
  }
  Timer {
    id: overstay
    onTriggered: {
      if (!worker.running) return;
      const mode = worker.mode;
      worker.stamp = "";
      worker.running = false;
      if (mode === "install")
        plugins._writeManifest(plugins.installed.filter((p) => p.name !== worker.names[0]));
      plugins.phase = "failed";
      plugins.note = mode === "check"
        ? "The check for updates took too long and was stopped. Is the network up?"
        : "That took too long and was stopped. Is the network up?";
    }
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
    // this run's stamp; "" once it was given up on
    property string stamp: ""
    // whether this run's output was read; gone without an answer (no
    // stamp: it failed before pack.lua could say anything) is a failure,
    // not a phase left on "checking" for good
    property bool answered: false
    onExited: {
      overstay.stop();
      if (worker.stamp !== "") unanswered.restart();
    }
    stdout: StdioCollector {
      id: said
      onStreamFinished: {
        const m = /^RUN (\S+)\n/.exec(said.text);
        if (!m || m[1] !== worker.stamp) return;
        const text = said.text.slice(m[0].length);
        worker.answered = true;
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
    parserWorker.command = ["env", "NVIM_APPNAME=zenworks/plato", "PLATO_PARSERS=" + mode,
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
