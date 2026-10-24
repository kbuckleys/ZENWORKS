// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

.pragma library
.import qs.morpheus as Morpheus
.import Quickshell as QuickshellModule
// ONE COPY FOR THE WHOLE SHELL. Without the pragma every component instance
// that imports this file evaluated all of it again (see morpheus/icons.js).
// The shell's singletons come in through the imports above (the same
// instances); the node tests hand in stubs of their own.
var Desktop = typeof Morpheus !== "undefined" ? Morpheus.Desktop : globalThis.Desktop;
var Paths = typeof Morpheus !== "undefined" ? Morpheus.Paths : globalThis.Paths;
var Strings = typeof Morpheus !== "undefined" ? Morpheus.Strings : globalThis.Strings;
var Quickshell = typeof QuickshellModule !== "undefined" ? QuickshellModule.Quickshell : globalThis.Quickshell;

function histPath() {
  return Paths.cacheDir() + "/cynosure-history";
}

function freqPath() {
  return Paths.cacheDir() + "/cynosure-freq";
}

function shell() {
  return Quickshell.env("SHELL") || "/bin/bash";
}

const ICON_T = "\uEA85";
const ICON_P = "\uEB7F";
const ICON_B = "\uEE23";

// ── THE SHELL'S OWN VERBS ─────────────────────────────────────────────────
// Every component already answers `qs ipc call`, so the launcher can reach
// all of them without knowing anything about them: one line per verb, found
// by its name or any of its keys, ranked by the same frecency as the apps.
//
// The session verbs (erebus' old five, which live here now) carry `confirm`:
// they open the picker as "Reboot?" with Back already selected, so a typed
// "re" and a couple of returns is never a reboot.
//
// `sh` is a shell line; `{dir}` in it is the shell's own directory, already
// quoted — write it bare — and `{session}` the logind session this shell runs
// in.
//
// `needs` names a live flag the popup passes in (as `state` does): while it
// is not set the row is not offered at all — Wi-Fi on a machine without it
// is a row that can only fail (2026-10-21).
const SHELL_ACTIONS = [
  { name: "Lock screen", glyph: "\uF456", keys: "lock cerberus", sh: "sleep 0.35 && qs ipc call Cerberus lock" },
  { name: "Log out", glyph: "\uDB81\uDF43", keys: "logout session exit quit", sh: "hyprshutdown -t 'Logging out…' -p 'loginctl terminate-session {session}'", confirm: true },
  { name: "Suspend", glyph: "\uDB82\uDD04", keys: "sleep standby", sh: "systemctl suspend", confirm: true },
  { name: "Reboot", glyph: "\uF021", keys: "restart", sh: "hyprshutdown -t 'Rebooting…' -p 'systemctl reboot'", confirm: true },
  { name: "Shutdown", glyph: "\u23FB", keys: "shutdown power off poweroff halt", sh: "hyprshutdown -t 'Shutting down…' -p 'systemctl poweroff'", confirm: true },
  { name: "Settings", glyph: "\uF013", keys: "oracle preferences options config", ipc: "Oracle open" },
  { name: "Check for updates", glyph: "\uF2F1", keys: "ceres upgrade refresh sync", ipc: "Ceres check" },
  { name: "Store", glyph: "\uDB83\uDD68", keys: "ceres store apps app store packages install remove paru pacman aur flatpak flathub", ipc: "Ceres window store" },
  { name: "Updates", glyph: "\uF062", keys: "ceres upgrade packages", ipc: "Ceres window updates" },
  { name: "Package history", glyph: "\uF1DA", keys: "ceres downgrade rollback log", ipc: "Ceres window history" },
  { name: "Package maintenance", glyph: "\uF0AD", keys: "ceres clean cache orphans pacnew", ipc: "Ceres window maintenance" },
  { name: "Files", glyph: "\uF114", keys: "terminus file manager directories folders", ipc: "Terminus toggle" },
  { name: "Find files", glyph: "\uF002", keys: "artemis search finder locate", ipc: "Artemis toggle" },
  { name: "Background", glyph: "\uF03E", keys: "picasso background wallpaper", ipc: "Picasso toggle" },
  { name: "Pick a color", glyph: "\u{F020A}", keys: "picasso color colour picker eyedropper hex palette", sh: "sleep 0.35 && qs ipc call Picasso pick" },
  { name: "Measure on screen", glyph: "\u{F046D}", keys: "picasso ruler measure pixels distance size", sh: "sleep 0.35 && qs ipc call Picasso measure" },
  { name: "New note", glyph: "\uF24A", keys: "clio sticky desktop", ipc: "Clio add" },
  { name: "New journal entry", glyph: "\u{F0B64}", keys: "clio journal diary write reflect mood", ipc: "Clio journal" },
  { name: "Today's journal entry", glyph: "\u{F00F6}", keys: "clio journal today daily diary", ipc: "Clio today" },
  { name: "Quick note", glyph: "\u{F140B}", keys: "clio capture jot quick note inbox", ipc: "Clio capture" },
  { name: "Notifications", glyph: "\uF0F3", keys: "howler bell history", ipc: "Howler toggle" },
  { name: "Clear notifications", glyph: "\uF1F6", keys: "howler bell dismiss", ipc: "Howler clear" },
  { name: "Clipboard", glyph: "\uF0EA", keys: "folio paste history copy", ipc: "Folio toggle" },
  { name: "Passwords", glyph: "\uEB11", keys: "calypso pass login totp quick access", ipc: "Calypso toggle" },
  { name: "Password manager", glyph: "\uEB11", keys: "calypso vault bitwarden 1password proton keepass gopass accounts", ipc: "Calypso open" },
  { name: "Lock passwords", glyph: "\uF023", keys: "calypso lock vault", ipc: "Calypso lock" },
  { name: "Calculator", glyph: "\uF1EC", keys: "metis math calc", ipc: "Metis toggle" },
  { name: "Dictionary", glyph: "\uF02D", keys: "lexi define word", ipc: "Lexi toggle" },
  { name: "Translate", glyph: "\uF1AB", keys: "lexi language", ipc: "Lexi translate" },
  { name: "Emoji", glyph: "\uF118", keys: "ideo emoticon smiley", ipc: "Ideo emoji" },
  { name: "Nerd glyphs", glyph: "\uF031", keys: "ideo icons font symbols", ipc: "Ideo nerd" },
  { name: "Sound & system", glyph: "\uF028", keys: "zeus volume audio mixer cpu memory monitor", ipc: "Zeus toggle" },
  { name: "Calendar & weather", glyph: "\uF073", keys: "chronos clock date forecast", ipc: "Chronos toggle" },
  // `choose: "timer"`: with more than one idle timer the popup asks which
  // one in its picker (see timerChoices) instead of running `ipc` blind.
  { name: "Start timer", glyph: "\uF017", keys: "chronos pomodoro focus countdown", ipc: "Chronos start", choose: "timer" },
  { name: "Stop timer", glyph: "\uF28D", keys: "chronos pomodoro halt countdown", ipc: "Chronos halt" },
  // A toggle in socordia (forceAwake flips), so the row says what pressing it
  // does: Caffeinate while the screen may sleep, Decaffeinate while it is
  // held awake. Not `Socordia release`: that drops logind's delay lock before
  // a suspend, an escape hatch rather than the way back from keeping awake.
  // `state` names a live flag the popup passes in; while it is set the row
  // wears `on` instead. `name` stays the frecency key in both states.
  { name: "Caffeinate", glyph: "\u{F06CA}", keys: "socordia keep awake idle inhibit caffeine coffee decaf sleep",
    ipc: "Socordia awake", state: "awake", on: { name: "Decaffeinate", glyph: "\u{F0FAB}" } },
  { name: "Reload shell", glyph: "\uF01E", keys: "quickshell restart qs", sh: "{dir}/scripts/restart.sh" },

  // ── the 10-20 apps ──
  // control hub (hermes): the window, and its switches where there is one
  { name: "Grayscale screen", glyph: "\u{F0301}", keys: "hermes color filter grayscale greyscale monochrome focus", ipc: "Hermes filter gray" },
  { name: "Control Hub", glyph: "\u{F1542}", keys: "hermes network wifi wi-fi ethernet bluetooth vpn display brightness settings", ipc: "Hermes window ''" },
  { name: "Printers & scanners", glyph: "\u{F042A}", keys: "hermes printer printing print scanner scan cups", ipc: "Hermes window printers" },
  { name: "Night light", glyph: "\u{F0594}", keys: "hermes hyprsunset warm blue light evening", ipc: "Hermes night",
    needs: "nightReady", state: "night", on: { name: "Night light off", glyph: "\u{F00DF}" } },
  { name: "Wi-Fi off", glyph: "\u{F05AA}", keys: "hermes wireless network radio", ipc: "Hermes wifi",
    needs: "wifiReady", state: "wifiOff", on: { name: "Wi-Fi on", glyph: "\u{F05A9}" } },
  { name: "Bluetooth off", glyph: "\u{F00B2}", keys: "hermes radio headphones", ipc: "Hermes bluetooth",
    needs: "btReady", state: "btOff", on: { name: "Bluetooth on", glyph: "\u{F00AF}" } },
  // argus: recording, through the same ZenRecord the binds use; after the
  // launcher has gone, so it is not in the picture
  { name: "Record the screen", glyph: "\u{F044B}", keys: "argus recording video capture screencast", sh: "sleep 0.35 && hyprctl repl 'ZenRecord(\"full\")'" },
  { name: "Record a region", glyph: "\u{F0A6D}", keys: "argus recording video capture area selection", sh: "sleep 0.35 && hyprctl repl 'ZenRecord(\"region\")'" },
  { name: "Record a window", glyph: "\u{F0614}", keys: "argus recording video capture", sh: "sleep 0.35 && hyprctl repl 'ZenRecord(\"window\")'" },
  { name: "Stop recording", glyph: "\u{F0667}", keys: "argus recording end finish", sh: "hyprctl repl 'ZenRecord(\"stop\")'" },
  { name: "Cut the last recording", glyph: "\u{F0190}", keys: "argus trim edit gif webm mp4 video", ipc: "Argus last" },
  // minerva
  { name: "Continue reading", glyph: "\u{F05DA}", keys: "minerva book ebook pdf epub reader", ipc: "Minerva last" },
  { name: "Library", glyph: "\u{F03D2}", keys: "minerva books reading pdf epub", ipc: "Minerva library" },
  // hestia
  { name: "Services", glyph: "\u{F08D6}", keys: "hestia systemd systemctl daemons units", ipc: "Hestia open system" },
  { name: "System journal", glyph: "\u{F09EE}", keys: "hestia logs journalctl errors", ipc: "Hestia journal ''" },
  { name: "What's wrong", glyph: "\u{F05D6}", keys: "hestia failed services errors broken overview health", ipc: "Hestia open overview" },
  // stylus
  { name: "Write an image to a drive", glyph: "\u{F0D13}", keys: "stylus iso usb flash burn etcher rufus sd card bootable dd", ipc: "Stylus open ''" },
  // kairos
  { name: "This week's screen time", glyph: "\u{F0128}", keys: "kairos screen time usage week apps hours", ipc: "Kairos open week" },
  { name: "Keyboard shortcuts", glyph: "\u{F030C}", keys: "keys keybinds binds cheat sheet hotkeys shortcuts", sh: "sleep 0.3 && qs ipc call Keys open" },
];

// The frecency key, kept apart from app names: an app called "Files" and the
// shell's Files are two rows with two counts.
function actionKey(a) {
  return "shell:" + a.name;
}

// The idle timers as picker rows, keyed by their index in Chronos.timers.
// Running ones are left out: starting them again would do nothing.
function timerChoices(timers) {
  const out = [];
  for (let i = 0; i < (timers || []).length; ++i) {
    const t = timers[i];
    if (t.running) continue;
    out.push({ key: "timer:" + i, label: "  " + t.label + " " + t.minutes + "m" });
  }
  return out;
}

function actionCommand(a, dir, session) {
  // {dir} is quoted HERE, whole, rather than wrapped in quotes in the table:
  // hand-written '…' around it broke on a directory with a quote in it
  if (a.sh) return a.sh.split("{dir}").join(Strings.shellQuote(dir))
    .split("{session}").join(session || "");
  return "qs ipc call " + a.ipc;
}

const HIST_MAX = 200;

function stripIcon(entry) {
  let rest = entry;
  for (const ic of [ICON_T, ICON_P]) {
    if (rest.startsWith(ic)) {
      rest = rest.slice(ic.length);
      break;
    }
  }
  return rest;
}

function stripPrefix(s) {
  const idx = s.indexOf("  ");
  return idx >= 0 ? s.slice(idx + 2) : s;
}

function parseHistory(text) {
  const lines = [];
  if (!text) return lines;
  for (const line of text.split("\n")) {
    if (line.trim() === "") continue;
    if (stripIcon(line).trim() === "") continue;
    lines.push(line);
  }
  return lines;
}

function parseFreq(text) {
  const map = {};
  if (!text) return map;
  for (const line of text.split("\n")) {
    const m = line.match(/^(.*)=(\d+)$/);
    if (m && m[1] !== "") map[m[1]] = parseInt(m[2], 10);
  }
  return map;
}

// the Exec line's field codes gone, and %% the literal % it stands for —
// in one pass, so "%%f" is "%f" and not nothing (2026-10-23: a date format
// like `date +%%H` reached the shell as `+%%H`)
function stripFieldCodes(exec) {
  return exec.replace(/%([%fFuUdDnNickvm])/g, (m, c) => (c === "%" ? "%" : "")).replace(/\s+$/, "");
}

function getApps(modelValues) {
  const apps = [];
  const seen = {};
  for (const v of modelValues) {
    if (!v) continue;
    const name = (v.name || "").trim();
    const exec = stripFieldCodes(v.exec || "").trim();
    const id = v.id || "";
    if (!name || !exec) continue;
    const key = name.toLowerCase();
    if (seen[key]) continue;
    seen[key] = true;
    apps.push({ name, exec, id, icon: v.icon || "", terminal: !!v.terminal, words: String(v.words || "") });
  }
  apps.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  return apps;
}

// A toggle's row wears its state — Caffeinate while it is off, Decaffeinate
// while it is on — or you cannot tell which way it is.
function actionFace(a, states) {
  return a.state && a.on && (states || {})[a.state] ? a.on : a;
}

// "glyph  label" split at its first double space — the history lines and the
// picker labels are stored that way. Drawn as two pieces: in rich text the
// double space collapses to one and the glyph sits on the word.
function splitGlyph(s) {
  const t = String(s);
  const idx = t.indexOf("  ");
  return idx > 0 ? { glyph: t.slice(0, idx), label: t.slice(idx + 2) } : { glyph: "", label: t.trim() };
}

// `glyphOf` is morpheus' appGlyph — handed in rather than imported, so this
// file stays loadable on its own. An app nothing claims shows no glyph at all.
function buildRows(apps, histLines, freq, actions, states, glyphOf) {
  const appNames = {};
  for (const a of apps) appNames[a.name.toLowerCase()] = true;

  const rows = [];
  const appRow = {};
  for (const a of apps) {
    const g = glyphOf ? glyphOf([a.id, a.exec, a.name]) : "";
    const r = { kind: "app", key: a.name, text: a.name, exec: a.exec, id: a.id, icon: a.icon, words: a.words || "",
      glyph: g || "", label: a.name, displayText: g ? g + "  " + a.name : a.name };
    appRow[a.name.toLowerCase()] = r;
    rows.push(r);
  }
  for (const a of actions || []) {
    if (a.needs && !(states || {})[a.needs]) continue;
    const f = actionFace(a, states);
    // ONE ROW PER NAME (user, 2026-10-21: "two control hub entries"): the
    // shell writes .desktop files for its own windows, so an app and a verb
    // can share a name. The app stays and finds by the verb's words too.
    const twin = appRow[f.name.toLowerCase()];
    if (twin) { twin.words = (twin.words + " " + (a.keys || "")).trim(); continue; }
    rows.push({ kind: "shell", key: actionKey(a), text: f.name, exec: "", keys: a.keys, action: a,
      glyph: f.glyph, label: f.name, displayText: f.glyph + "  " + f.name });
  }
  for (const line of histLines) {
    const cmd = stripPrefix(line);
    if (appNames[cmd.toLowerCase()]) continue;
    const glyph = line.startsWith(ICON_P) ? ICON_P : ICON_T;
    rows.push({ kind: "hist", key: cmd, text: cmd, exec: "", glyph: splitGlyph(line).glyph || glyph,
      label: cmd, raw: line, displayText: line });
  }
  rows.sort((a, b) => {
    const fa = freq[a.key] || 0;
    const fb = freq[b.key] || 0;
    if (fa !== fb) return fb - fa;
    return a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
  });
  return rows;
}

function filterRows(rows, query) {
  const q = (query || "").trim().toLowerCase();
  if (q === "") return rows.slice();
  const out = [];
  for (const r of rows) {
    // an app's generic name and keywords count, so "font" finds the font book
    const hay = (r.text + " " + (r.exec || "") + " " + (r.keys || "") + " " + (r.words || "")).toLowerCase();
    if (hay.includes(q)) out.push(r);
  }
  return out;
}

function addHistory(lines, cmd, mode, customIcon) {
  const icon = customIcon || (mode === "Terminal" ? ICON_T : ICON_P);
  const formatted = icon + "  " + cmd;
  const filtered = lines.filter((e) => e !== formatted);
  filtered.unshift(formatted);
  return filtered.slice(0, HIST_MAX);
}

function deleteHistoryLine(lines, rawLine) {
  return lines.filter((e) => e !== rawLine);
}

function bumpFreq(map, key) {
  if (!key) return map;
  map[key] = (map[key] || 0) + 1;
  return map;
}

function serializeHistory(lines) {
  return lines.length ? lines.join("\n") + "\n" : "";
}

function serializeFreq(map) {
  const parts = [];
  for (const k in map) parts.push(k + "=" + map[k]);
  return parts.length ? parts.join("\n") + "\n" : "";
}

// `term` is oracle's Default apps terminal. Empty is the old guess below.
function terminalCommand(cmd, term) {
  const t = String(cmd).trim().toLowerCase();
  if (t === "kitty") {
    return "setsid kitty --detach " + Strings.shellQuote(cmd) + " >/dev/null 2>&1 &";
  }
  // footclient BY NAME when it is there, and the reason is the window rule.
  //
  // xdg-terminal-exec only forwards --hold and --title if the terminal's
  // desktop entry declares TerminalArgHold= and TerminalArgTitle=. foot.desktop
  // declares neither, so the script dropped both without a word: every command
  // that printed and exited took its window with it, and the window that did
  // survive was class `foot` with no title — while the hyprland rule is written
  // for `footclient` + title `cynosure` and so never matched.
  //
  // Calling footclient directly gets all three right at once: the server is
  // already up from hyprland's autostart, --hold is foot's own flag, and the
  // class is what the rule expects. xdg-terminal-exec stays the fallback for a
  // machine with no foot on it, where the rule does not apply anyway.
  const run = shell() + " -i -c " + Strings.shellQuote(cmd);
  // ── THE TERMINAL YOU CHOSE ─────────────────────────────────────────
  // Oracle puts its entry first in xdg-terminals.list, so xdg-terminal-exec
  // already lands in it; the title and the hold go through the entry's own
  // TerminalArg keys, which kitty, alacritty and ghostty declare. foot is
  // the one that does not, so it is still called by name, for the reason
  // above.
  const want = String(term || "").trim().split(/\s+/)[0].replace(/.*\//, "");
  if (want === "foot" || want === "footclient") {
    return "if command -v footclient >/dev/null 2>&1; then "
      + "footclient --hold --title=cynosure " + run + "; "
      + "else foot --hold --title=cynosure " + run + "; fi"
      + " >/dev/null 2>&1 &";
  }
  if (want !== "")
    return "xdg-terminal-exec --title=cynosure --hold -e " + run + " >/dev/null 2>&1 &";
  return "if command -v footclient >/dev/null 2>&1; then "
    + "footclient --hold --title=cynosure " + run + "; "
    + "else xdg-terminal-exec --title=cynosure --hold -e " + run + "; fi"
    + " >/dev/null 2>&1 &";
}

function processCommand(cmd) {
  return "setsid " + shell() + " -i -c " + Strings.shellQuote(cmd) + " >/dev/null 2>&1 &";
}

// gio launch, by way of Desktop — NOT gtk-launch.
//
// gtk-launch runs the entry's Exec line and nothing else, so an entry that
// declares Terminal=true was started with no terminal around it and died
// immediately with no error anywhere. See morpheus/Desktop.qml, which also
// owns the search path all three launching layers now share.
function launchAppCommand(id) {
  return Desktop.launchCommand(id, "");
}

// the shell's one escaping rule (morpheus/Strings)
function escMarkup(s) {
  return Strings.escapeHtml(s);
}

function highlight(text, query) {
  const t = String(text);
  const q = (query || "").trim();
  if (q === "") return escMarkup(t);
  const idx = t.toLowerCase().indexOf(q.toLowerCase());
  if (idx < 0) return escMarkup(t);
  return escMarkup(t.slice(0, idx)) + "<u>" + escMarkup(t.slice(idx, idx + q.length)) +
      "</u>" + escMarkup(t.slice(idx + q.length));
}
