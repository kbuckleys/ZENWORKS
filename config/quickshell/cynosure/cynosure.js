// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

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
const SHELL_ACTIONS = [
  { name: "Lock screen", glyph: "\uF456", keys: "lock cerberus", sh: "sleep 0.35 && qs ipc call Cerberus lock" },
  { name: "Log out", glyph: "\uDB81\uDF43", keys: "logout session exit quit", sh: "hyprshutdown -p 'loginctl terminate-session {session}'", confirm: true },
  { name: "Suspend", glyph: "\uDB82\uDD04", keys: "sleep standby", sh: "systemctl suspend", confirm: true },
  { name: "Reboot", glyph: "\uF021", keys: "restart", sh: "hyprshutdown -p 'systemctl reboot'", confirm: true },
  { name: "Shutdown", glyph: "\u23FB", keys: "shutdown power off poweroff halt", sh: "hyprshutdown -p 'systemctl poweroff'", confirm: true },
  { name: "Settings", glyph: "\uF013", keys: "oracle preferences options config", ipc: "Oracle open" },
  { name: "Check for updates", glyph: "\uF2F1", keys: "ceres upgrade refresh sync", ipc: "Ceres check" },
  { name: "Package manager", glyph: "\uF487", keys: "ceres packages install remove paru pacman aur", ipc: "Ceres window packages" },
  { name: "Updates", glyph: "\uF062", keys: "ceres upgrade packages", ipc: "Ceres window updates" },
  { name: "Package history", glyph: "\uF1DA", keys: "ceres downgrade rollback log", ipc: "Ceres window history" },
  { name: "Package maintenance", glyph: "\uF0AD", keys: "ceres clean cache orphans pacnew", ipc: "Ceres window maintenance" },
  { name: "Files", glyph: "\uF114", keys: "terminus file manager directories folders", ipc: "Terminus toggle" },
  { name: "Find files", glyph: "\uF002", keys: "artemis search finder locate", ipc: "Artemis toggle" },
  { name: "Background", glyph: "\uF03E", keys: "picasso background wallpaper", ipc: "Picasso toggle" },
  { name: "New note", glyph: "\uF24A", keys: "clio sticky desktop", ipc: "Clio add" },
  { name: "Notifications", glyph: "\uF0F3", keys: "howler bell history", ipc: "Howler toggle" },
  { name: "Clear notifications", glyph: "\uF1F6", keys: "howler bell dismiss", ipc: "Howler clear" },
  { name: "Clipboard", glyph: "\uF0EA", keys: "folio paste history copy", ipc: "Folio toggle" },
  { name: "Passwords", glyph: "\uF084", keys: "calypso pass login totp", ipc: "Calypso toggle" },
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
  // A toggle in socordia (forceAwake flips), so the row says which way it is. Not
  // `Socordia release`: that drops logind's delay lock before a suspend, an
  // escape hatch rather than the way back from keeping awake.
  // `state` names a live flag the popup passes in, and the row wears it.
  { name: "Keep Awake", glyph: "\uF0F4", keys: "socordia idle inhibit caffeine sleep", ipc: "Socordia awake", state: "awake" },
  { name: "Reload shell", glyph: "\uF01E", keys: "quickshell restart qs", sh: "{dir}/scripts/restart.sh" },
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

function stripFieldCodes(exec) {
  return exec.replace(/%[fFuUdDnNickvm]/g, "").replace(/\s+$/, "");
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

// A toggle's row wears its state — "Keep Awake ON" while it is on, "Keep
// Awake OFF" while it is off — or you cannot tell which way it is.
function actionLabel(a, states) {
  if (!a.state) return a.name;
  return a.name + ((states || {})[a.state] ? " ON" : " OFF");
}

// `glyphOf` is morpheus' appGlyph — handed in rather than imported, so this
// file stays loadable on its own. An app nothing claims shows no glyph at all.
function buildRows(apps, histLines, freq, actions, states, glyphOf) {
  const appNames = {};
  for (const a of apps) appNames[a.name.toLowerCase()] = true;

  const rows = [];
  for (const a of apps) {
    const g = glyphOf ? glyphOf([a.id, a.exec, a.name]) : "";
    rows.push({ kind: "app", key: a.name, text: a.name, exec: a.exec, id: a.id, icon: a.icon, words: a.words || "",
      displayText: g ? g + "  " + a.name : a.name });
  }
  for (const a of actions || []) {
    rows.push({ kind: "shell", key: actionKey(a), text: actionLabel(a, states), exec: "", keys: a.keys, action: a,
      displayText: a.glyph + "  " + actionLabel(a, states) });
  }
  for (const line of histLines) {
    const cmd = stripPrefix(line);
    if (appNames[cmd.toLowerCase()]) continue;
    const glyph = line.startsWith(ICON_P) ? ICON_P : ICON_T;
    rows.push({ kind: "hist", key: cmd, text: cmd, exec: "", glyph, raw: line, displayText: line });
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

// `term` is oracle's Default Apps terminal. Empty is the old guess below.
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

function escMarkup(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
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
