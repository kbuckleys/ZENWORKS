// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "calypso.js" as Calypso
import "../morpheus/helpers.js" as Helpers
import "../morpheus"

LayerPopup {
  id: popup

  readonly property color bgColor: Zenon.layerBg
  readonly property color fgColor: Zenon.white
  readonly property color headColor: Zenon.cyan
  readonly property color keyColor: Zenon.keyInk
  readonly property color dimColor: Zenon.muted
  readonly property color entryColor: Zenon.pink
  readonly property color errColor: Zenon.red
  // Not a highlight: the red a failed unlock wears. Selection bars are
  // Zenon.border, like every highlight in the shell.
  readonly property color failTint: "#4de78284"

  // mode: list · actions · unlock · error
  property string mode: "list"

  // ── the passphrase ───────────────────────────────────────────────────
  // Held the way cerberus holds it: a plain string, filled by a raw key
  // handler, never a TextInput. There is no masked-input type anywhere in this
  // shell and there does not need to be — the dots are drawn from the LENGTH,
  // so the characters themselves never reach the scene graph.
  property string pw: ""
  // input · checking · fail · success
  property string phase: "input"
  // why the last unlock failed, when it was not simply the wrong password —
  // a first login can fail for reasons the password has nothing to do with
  property string failMsg: ""

  // ── first-run setup ──────────────────────────────────────────────────
  // With no account in rbw's config, the unlock view asks for one instead:
  // the email, then the server (empty for bitwarden.com). Typed the same raw
  // way as the passphrase, but shown, since neither is a secret.
  // email · server · saving
  property string setupStep: "email"
  property string setupText: ""
  property string setupEmail: ""
  property string setupErr: ""

  // The private channel to the pinentry helper. Calypso creates this immediately
  // before an unlock and removes it immediately after; its existence is also
  // what tells the helper to answer instead of drawing a window, so a stale one
  // would hijack `rbw` in a terminal — hence the sweep in ensureRbwConfig.
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string fifoPath: popup.runtimeDir + "/calypso-pinentry"
  readonly property string pinentryPath: Helpers.script("calypso-pinentry.sh")
  readonly property string rbwConfigPath:
    (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
      + "/rbw/config.json"

  // rbw cannot be used at all without an account address, and calypso cannot
  // invent one — this drives a plain instruction in the unlock view rather
  // than an empty list nobody can explain.
  property bool emailSet: true

  // which question the in-flight `rbw unlocked` is answering
  property string checkFor: ""
  property string checkNext: ""

  property string query: ""
  property var entries: []
  property var filtered: []
  property int sel: 0

  // the entry whose action strip is open
  property var activeEntry: null
  property string pendingKind: ""
  property int actionSel: 0
  // col 0 is typed where the cursor is, col 1 goes on the clipboard. The
  // order within a column is the order on screen, and index 0 is where the
  // selection starts — "both" is what you want nine times in ten.
  readonly property var actionTypes: [
    { kind: "both",     col: 0, glyph: "", label: "user ⇥ pass" },
    { kind: "user",     col: 0, glyph: "", label: "username" },
    { kind: "pass",     col: 0, glyph: "", label: "password" },
    { kind: "totp",     col: 0, glyph: "", label: "TOTP code" },
    { kind: "copypass", col: 1, glyph: "", label: "password" },
    { kind: "copyuser", col: 1, glyph: "", label: "username" },
    { kind: "copytotp", col: 1, glyph: "", label: "TOTP code" },
  ]

  // Named because calcHeight() does arithmetic with them, and a literal in
  // both places is a literal that drifts.
  readonly property int msgH: 28        // the hint strip, as artemis and folio
  readonly property int searchH: 36     // the filter line, as artemis
  readonly property int emptyH: 64
  readonly property int lockFieldH: 64  // as ceres' PasswordField
  readonly property int actHeadH: 64
  readonly property int actSectH: 28
  readonly property int actBodyH: 6 + popup.actSectH + 4 * popup.cellH + 8

  readonly property int cols: 2
  // results that fit one visible column span the whole window
  readonly property int effCols:
    (popup.filtered.length >= 1 && popup.filtered.length <= popup.visibleRows)
      ? 1 : popup.cols
  readonly property int visibleRows: 8
  readonly property int cellH: 32

  focusable: true

  HyprlandFocusGrab {
    id: grab
    windows: [ popup ]
    active: popup.shown
    onCleared: popup.closePopup()
  }

  IpcHandler {
    target: "Calypso"

    function toggle() { popup.toggle(); }
  }

  // ------------------------------------------------- rbw's own config --
  //
  // Calypso points rbw at its helper itself, so the suite works on a new machine
  // with no manual rbw setup. `rbw config set` is the supported API and
  // preserves every other field, so this never clobbers an account.
  //
  // The path comes from Quickshell.shellDir, so it is right wherever the config
  // is checked out and gets rewritten if it moves.

  FileView {
    id: rbwCfgFile
    path: popup.rbwConfigPath
    blockLoading: true
    printErrors: false
    // reload() is asynchronous even with blockLoading, so the config is read
    // when it has actually arrived — reading it straight after reload() saw
    // the old text, and a first-run setup that had just written the email
    // came back to the setup view.
    onLoaded: popup.readRbwConfig()
    onLoadFailed: popup.readRbwConfig()
  }

  Process { id: rbwCfgProc }
  Process { id: prepProc }

  function ensureRbwConfig() {
    // make the helper runnable from a fresh checkout, and sweep any fifo a
    // crashed session left behind before it can capture a terminal's rbw
    prepProc.command = ["sh", "-c",
      "chmod +x " + Strings.shellQuote(popup.pinentryPath)
        + (popup.runtimeDir !== "" ? "; rm -f " + Strings.shellQuote(popup.fifoPath)
            + " " + Strings.shellQuote(popup.fifoPath + ".spent") : "")];
    prepProc.running = true;
    popup.readRbwConfig();
  }

  function readRbwConfig() {
    let cfg = {};
    try { cfg = JSON.parse(rbwCfgFile.text() || "{}"); } catch (e) {}
    popup.emailSet = typeof cfg.email === "string" && cfg.email !== "";
    if (cfg.pinentry !== popup.pinentryPath && !rbwCfgProc.running) {
      rbwCfgProc.command = ["rbw", "config", "set", "pinentry", popup.pinentryPath];
      rbwCfgProc.running = true;
    }
  }

  Component.onCompleted: popup.ensureRbwConfig()

  // ------------------------------------------------------------- procs --

  Process {
    id: lsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: popup.onEntries(text)
    }
  }

  Process {
    id: syncProc
    onExited: popup.loadEntries()
  }

  // exit code tells us whether the agent is unlocked
  Process {
    id: unlockedCheck
    onExited: (exitCode) => {
      popup.onUnlockedCheck(exitCode);
      // a question asked while this one was out is asked now, rather than
      // being dropped by a no-op restart and answered with this reply
      if (popup.checkNext !== "") {
        const next = popup.checkNext;
        popup.checkNext = "";
        popup.checkLock(next);
      }
    }
  }

  // runs the actual rbw fetch + consume pipeline; secrets stay in pipes
  // (only the failure sentinel ever reaches stdout)
  Process {
    id: actionProc
    stdout: StdioCollector {
      id: actionCol
      waitForEnd: true
    }
    onExited: popup.onActionDone()
  }

  property string errorMsg: ""

  // ── which entries carry an authenticator ────────────────────────────
  // `rbw ls` does not say, and the only thing that does without decrypting
  // a secret into this process is --list-fields, which prints field NAMES.
  // One pass over the logins after every listing (47 of them take ~0.2s),
  // printing back only the ids that have a totp field. Logins only: cards
  // sit behind the master-password re-prompt, and asking about one would
  // start a pinentry nobody is there to answer.
  property var totpIds: ({})
  property bool totpKnown: false

  Process {
    id: totpScan
    property bool again: false
    onExited: if (totpScan.again) { totpScan.again = false; popup.scanTotp(); }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const ids = {};
        for (const l of text.split("\n")) if (l !== "") ids[l] = true;
        popup.totpIds = ids;
        popup.totpKnown = true;
      }
    }
  }

  function scanTotp() {
    const ids = popup.entries.filter((e) => e.type === "Login").map((e) => e.id);
    if (ids.length === 0) return;
    // `running = true` on a running Process is a no-op, so a listing that
    // arrived mid-scan is scanned again once this one is done
    if (totpScan.running) { totpScan.again = true; return; }
    totpScan.command = ["bash", "-c",
      'for id; do rbw get --list-fields "$id" </dev/null 2>/dev/null'
        + ' | grep -qx totp && printf "%s\\n" "$id"; done',
      "calypso-totp"].concat(ids);
    totpScan.running = true;
  }

  // true / false once the scan is in; undefined before, which keeps the
  // TOTP actions offered rather than hiding one that works
  function hasTotp(e) {
    if (!e) return false;
    return popup.totpKnown ? !!popup.totpIds[e.id] : undefined;
  }

  function actionOk(i) {
    const a = popup.actionTypes[i];
    return !!a && Calypso.actionEnabled(a.kind, popup.activeEntry,
                                        popup.hasTotp(popup.activeEntry));
  }

  // Locks the agent, and drops everything calypso knew about what was in
  // it. Called by the shell when cerberus locks the screen: a vault left
  // open behind a locked session is a vault open to whoever unlocks it.
  function lockVault() {
    // An action still out may be about to wtype a secret into whatever has
    // focus — which, a moment from now, is the lock screen.
    closeTimer.stop();
    actionProc.running = false;
    popup.clearPassword();
    if (popup.shown) popup.closePopup();
    popup.entries = [];
    popup.filtered = [];
    popup.totpIds = ({});
    popup.totpKnown = false;
    popup.activeEntry = null;
    popup.detach("rbw lock");
  }

  function loadEntries() {
    lsProc.command = ["rbw", "ls", "--raw"];
    lsProc.running = true;
  }

  function onEntries(text) {
    popup.entries = Calypso.parseEntries(text);
    popup.applyFilter();
    popup.scanTotp();
  }

  // ---------------------------------------------------------- actions --

  function currentEntry() {
    return popup.filtered[popup.sel] || null;
  }

  function openActions() {
    const e = currentEntry();
    if (!e) return;
    popup.activeEntry = e;
    popup.actionSel = popup.firstAction();
    popup.query = "";
    filterInput.text = "";
    popup.applyFilter();
    popup.mode = "actions";
    popup.syncFocus();
  }

  // Back from the error view to the entry the failed action was FOR.
  // openActions() reads filtered[sel], and it had just been reset to 0 by the
  // filter clear on the way in — so this used to open a different
  // credential's actions, one Return away from typing it.
  function backToActions() {
    if (!popup.activeEntry) { popup.openActions(); return; }
    popup.actionSel = popup.firstAction();
    popup.mode = "actions";
    popup.syncFocus();
  }

  // Each fetch is an assignment whose status is rbw's own, so it chains
  // with && and a failed lookup stops before anything is typed or copied.
  function rbwFetch(kind, entry) {
    const id = Strings.shellQuote(entry.id);
    if (kind === "user")
      return "u=$(rbw get --field user " + id + ")";
    if (kind === "pass")
      return "p=$(rbw get " + id + ")";
    if (kind === "totp")
      return "t=$(rbw code " + id + ")";
    return "";
  }

  // Through wtype's stdin, never its argv: argv is readable in /proc by
  // anything running as you, and a secret that began with "-" would have
  // been parsed as an option.
  function typeVar(v) {
    return "printf '%s' \"$" + v + "\" | wtype -";
  }

  // `wl-paste --watch cliphist store` keeps everything copied, so a secret
  // has to be kept out of the history, not just cleared from the clipboard
  // afterwards. wl-copy --sensitive marks the offer so the watcher reports
  // CLIPBOARD_STATE=sensitive and cliphist skips it; wl-clipboard releases
  // up to 2.2.1 lack the flag, so there the entry is taken back out of
  // cliphist once stored, and only if the newest entry is this secret.
  // A shell function, so the secret is passed without an exec and never
  // reaches any process's argv. Clears the clipboard after 30s if it still
  // holds the secret — in a BACKGROUNDED subshell with its output closed, so
  // the action itself ends as soon as the copy lands. Waiting out the 30s in
  // the foreground kept actionProc running: every action in that window was
  // a silent no-op, and its late exit closed whatever panel was open then.
  readonly property string copySecretFn:
    "copy_secret() { "
    + "if wl-copy --help 2>&1 | grep -q -- --sensitive; then "
    + "printf '%s' \"$1\" | wl-copy --sensitive >/dev/null 2>&1 || return 1; "
    + "else "
    + "printf '%s' \"$1\" | wl-copy >/dev/null 2>&1 || return 1; "
    + "if command -v cliphist >/dev/null 2>&1; then "
    + "sleep 0.5; l=$(cliphist list 2>/dev/null | head -n1); "
    + "if [ -n \"$l\" ] && [ \"$(printf '%s\\n' \"$l\" | cliphist decode 2>/dev/null)\" = \"$1\" ]; then "
    + "printf '%s\\n' \"$l\" | cliphist delete >/dev/null 2>&1; fi; fi; "
    + "fi; "
    + "( sleep 30; "
    + "if [ \"$(wl-paste 2>/dev/null)\" = \"$1\" ]; then wl-copy --clear >/dev/null 2>&1; fi "
    + ") </dev/null >/dev/null 2>&1 & "
    + "return 0; }; "

  function execute(kind) {
    const entry = popup.activeEntry;
    if (!entry) return;

    popup.pendingKind = kind;

    // consume pipelines: rbw output flows through pipes only — secrets
    // never appear in argv, env, files, or logs
    const fail = " || echo CALYPSO_ACTION_FAILED";
    const fetchVar = { user: "u", pass: "p", totp: "t" };
    let script = "";
    if (kind === "both") {
      script = rbwFetch("user", entry) + " && " + rbwFetch("pass", entry)
        + " && sleep 0.3 && " + typeVar("u") + " && wtype -k Tab && " + typeVar("p");
    } else if (kind === "user" || kind === "pass" || kind === "totp") {
      script = rbwFetch(kind, entry) + " && sleep 0.3 && " + typeVar(fetchVar[kind]);
    } else if (kind === "copyuser" || kind === "copypass" || kind === "copytotp") {
      const k = kind.slice(4);
      script = popup.copySecretFn + rbwFetch(k, entry)
        + " && copy_secret \"$" + fetchVar[k] + "\"";
    } else {
      return;
    }
    actionProc.command = ["bash", "-c", script + fail];

    // gate everything behind the agent's lock state
    checkLock("action");
  }

  // One `rbw unlocked` runner for three different questions. It used to be
  // shared implicitly between the action gate and the unlock poll, so a poll
  // tick landing during a pending action fired that action a second time.
  function checkLock(reason) {
    if (unlockedCheck.running) { popup.checkNext = reason; return; }
    popup.checkFor = reason;
    unlockedCheck.command = ["rbw", "unlocked"];
    unlockedCheck.running = true;
  }

  function onUnlockedCheck(code) {
    const reason = popup.checkFor;
    popup.checkFor = "";
    const unlocked = (code === 0);

    // Asked on open, BEFORE listing. `rbw ls` on a locked vault makes the agent
    // spawn a pinentry on its own and returns nothing, which parseEntries
    // swallows — so calypso used to open on "No matches found" with an invisible
    // prompt behind it, which is exactly the first-run symptom.
    if (reason === "open") {
      if (unlocked) popup.loadEntries();
      else { popup.mode = "unlock"; popup.syncFocus(); }
      return;
    }

    if (reason === "unlock") {
      if (unlocked) {
        popup.phase = "success";
        popup.mode = "list";
        popup.loadEntries();
        popup.syncFocus();
      } else {
        popup.phase = "fail";
        failReset.restart();
      }
      return;
    }

    if (!unlocked) {
      popup.mode = "unlock";
      popup.syncFocus();
      return;
    }
    actionProc.running = true;
    closeTimer.restart();
  }

  function onActionDone() {
    closeTimer.stop();
    if (actionCol.text.indexOf("CALYPSO_ACTION_FAILED") >= 0) {
      popup.errorMsg = popup.pendingKind === "totp"
        ? "no TOTP configured for this entry" : "action failed";
      popup.mode = "error";
      popup.syncFocus();
      return;
    }
    popup.closePopup();
  }

  Timer {
    id: closeTimer
    interval: 700
    repeat: false
    onTriggered: {
      if (popup.mode !== "actions") return;
      popup.closePopup();
    }
  }

  function detach(script) {
    if (script) Quickshell.execDetached(["bash", "-c", script]);
  }

  // The passphrase goes over this process's STDIN and nowhere else — not argv,
  // not the environment, and not disk, since a fifo has no contents. `cat`
  // forwards it into the fifo the helper is waiting on.
  Process {
    id: unlockProc
    stdinEnabled: true
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: popup.failMsg = Calypso.unlockFailure(text)
    }
    onExited: {
      // whatever happened, the fifo must not outlive the attempt
      popup.checkLock("unlock");
    }
  }

  function submitUnlock() {
    if (popup.phase !== "input") return;
    if (popup.pw === "") return;
    popup.failMsg = "";
    if (popup.runtimeDir === "") return;   // nowhere private to put the fifo
    popup.phase = "checking";
    unlockProc.command = ["bash", "-c",
      'f="$1"; rm -f "$f" "$f.spent"; mkfifo -m 600 "$f" || exit 9; ' +
      // exec 3<&0 is load-bearing. POSIX assigns /dev/null to the stdin of a
      // backgrounded job, so `cat > "$f" &` was reading nothing at all and the
      // password never reached the fifo — the helper saw an empty read and
      // reported a cancelled prompt, so EVERY unlock failed regardless of what
      // was typed. Duplicating stdin onto fd 3 first survives that assignment.
      'exec 3<&0; cat <&3 > "$f" & w=$!; rbw unlock; s=$?; ' +
      'kill "$w" 2>/dev/null; rm -f "$f" "$f.spent"; exit "$s"',
      "calypso-unlock", popup.fifoPath];
    unlockProc.running = true;
    unlockProc.write(popup.pw + "\n");
    // held no longer than it takes to hand over, as cerberus does
    popup.clearPassword();
  }

  function clearPassword() { popup.pw = ""; }

  Timer {
    id: failReset
    interval: 1400
    onTriggered: popup.phase = "input"
  }

  // ------------------------------------------------------------- open --

  // fills down each column first:  1 3
  //                                2 4
  property var displayOrder: []

  // The GridView lays its cells out row by row, so the model is indexed by
  // CELL: cell (row, col) holds credential col * rows + row. It used to push
  // the credentials column by column, which is just 0, 1, 2… — the grid
  // came out row-major while the keys moved as if it were column-major, so
  // left and right went up and down. A short last column leaves holes,
  // marked -1.
  readonly property int gridRows:
    Math.max(1, Math.ceil(popup.filtered.length / popup.effCols))

  function rebuildDisplayOrder() {
    const len = popup.filtered.length;
    const c = popup.effCols;
    const r = Math.max(1, Math.ceil(len / c));
    const order = [];
    for (let row = 0; row < r; ++row)
      for (let col = 0; col < c; ++col) {
        const i = col * r + row;
        order.push(i < len ? i : -1);
      }
    popup.displayOrder = order;
  }

  // the cell a credential sits in, for positionViewAtIndex
  function cellOf(i) {
    const r = popup.gridRows;
    return (i % r) * popup.effCols + Math.floor(i / r);
  }

  function applyFilter() {
    popup.filtered = Calypso.filterEntries(popup.entries, popup.query);
    if (popup.sel >= popup.filtered.length) popup.sel = popup.filtered.length - 1;
    if (popup.sel < 0) popup.sel = 0;
    rebuildDisplayOrder();
    Qt.callLater(() => list.positionViewAtIndex(popup.cellOf(popup.sel), GridView.Contain));
  }

  function syncFocus() {
    Qt.callLater(() => {
      if (!popup.shown) return;
      if (popup.mode === "list") filterInput.forceActiveFocus();
      else bgRoot.forceActiveFocus();
    });
  }

  Process {
    id: setupProc
    onExited: (code) => {
      if (code === 0) {
        rbwCfgFile.reload();
        popup.ensureRbwConfig();
        popup.setupStep = "email";
        popup.setupText = "";
        popup.phase = "input";
      } else {
        popup.setupStep = "server";
        popup.setupErr = "rbw could not save the account";
      }
      popup.syncFocus();
    }
  }

  function submitSetup() {
    const text = popup.setupText.trim();
    if (popup.setupStep === "email") {
      if (!Calypso.looksLikeEmail(text)) {
        popup.setupErr = "that does not look like an email";
        return;
      }
      popup.setupEmail = text;
      popup.setupText = "";
      popup.setupErr = "";
      popup.setupStep = "server";
    } else if (popup.setupStep === "server") {
      popup.setupErr = "";
      popup.setupStep = "saving";
      // argv, never interpolated: the email and url are the user's text
      setupProc.command = ["bash", "-c",
        'rbw config set email "$1" && { [ -z "$2" ] || rbw config set base_url "$2"; }',
        "calypso-setup", popup.setupEmail, Calypso.serverUrl(text)];
      setupProc.running = true;
    }
  }

  function openPopup() {
    popup.shown = true;
    popup.collapsing = false;
    popup.mode = "list";
    popup.query = "";
    filterInput.text = "";
    popup.sel = 0;
    popup.entries = [];
    popup.filtered = [];
    popup.pw = "";
    popup.phase = "input";
    popup.failMsg = "";
    popup.setupStep = "email";
    popup.setupText = "";
    popup.setupErr = "";
    // re-read on every open, not just at startup, so an account added with
    // `rbw config set email` shows up without restarting the shell
    rbwCfgFile.reload();
    popup.ensureRbwConfig();
    popup.checkLock("open");

    focusRetry.counter = 0;
    focusRetry.restart();
    popup.playOpen();
    popup.syncFocus();
  }

  function closePopup() {
    popup.collapsing = true;
    popup.playClose();
  }

  function toggle() {
    if (popup.shown) popup.closePopup();
    else popup.openPopup();
  }

  function goBack() {
    popup.mode = "list";
    popup.clearPassword();
    popup.applyFilter();
    popup.syncFocus();
  }

  // ----------------------------------------------------------- hints --

  // The caret every other input in this shell blinks. Defined once and placed
  // twice — leading an empty field, trailing the dots once there are any — so
  // it reads as one caret that moves rather than two that blink in sync.
  component Caret: Rectangle {
    id: caret
    property bool on: true
    anchors.verticalCenter: parent.verticalCenter
    width: 3
    height: 20
    radius: 1
    color: popup.entryColor
    opacity: 0.25
    visible: caret.on
    SequentialAnimation on opacity {
      running: caret.on
      loops: Animation.Infinite
      NumberAnimation { to: 1; duration: 550; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.25; duration: 550; easing.type: Easing.InOutSine }
    }
  }

  // ── AS WIDE AS ITS WIDEST ENTRY ───────────────────────────────────
  // It was a fixed 1000 while every other layer fits itself. Now: the
  // widest credential row — glyph, folder / name, user, as drawn — times
  // the columns showing, with the hint strip of the current view as the
  // floor, and the 1000 every layer shares as the ceiling. The actions view
  // is about one entry, so there it is that entry's name that has to fit.
  FontMetrics { id: rowFm; font.family: Zenon.face; font.weight: 600; font.pixelSize: 16 }
  FontMetrics { id: userFm; font.family: Zenon.face; font.pixelSize: 14 }
  FontMetrics { id: headFm; font.family: Zenon.face; font.weight: 700; font.pixelSize: 17 }
  FontMetrics { id: noteFm; font.family: Zenon.face; font.pixelSize: 12 }
  function rowTextW(e) {
    if (!e) return 0;
    // 16 + 26 + 10 in front, 16 behind, 24 between name and user
    return 16 + 26 + 10 + 16
      + rowFm.advanceWidth((e.folder ? e.folder + " / " : "") + String(e.name || ""))
      + (popup.hasTotp(e) === true ? 22 : 0)
      + (e.user ? 24 + userFm.advanceWidth(e.user) : 0);
  }
  // As wide as the hint strip actually draws: measured off a copy of the
  // row itself rather than re-derived from text, so the caps' own padding is
  // counted and can never drift from it. Opacity 0, not invisible — a Row
  // lays out only its visible children, and an invisible one measures 0.
  HintRow { id: hintMeasure; opacity: 0; rows: popup.hints() }
  // the list's count sits at the strip's right edge; the hints stay centred,
  // so it is paid for on both sides
  readonly property int noteW: popup.mode === "list"
    ? Math.ceil(noteFm.advanceWidth("000 credentials")) + 16 : 0
  readonly property int minW:
    Math.max(360, Math.ceil(hintMeasure.implicitWidth + 48 + 2 * popup.noteW))
  readonly property int panelWidth: {
    if (popup.mode === "actions" && popup.activeEntry) {
      const e = popup.activeEntry;
      const head = headFm.advanceWidth((e.folder ? e.folder + " / " : "") + String(e.name || ""));
      return Math.max(popup.minW, 460, Math.min(1000, Math.ceil(head + 16 + 40 + 12 + 16 + 8)));
    }
    if (popup.mode !== "list") return Math.max(popup.minW, 420);
    let most = 0;
    for (const e of popup.filtered) most = Math.max(most, popup.rowTextW(e));
    // a few pixels for shaping
    const cell = Math.ceil(most) + 8;
    return Math.max(popup.minW, Math.min(1000, cell * popup.effCols));
  }
  readonly property int panelTarget: Zenon.layerWidth(popup.panelWidth)
  property real liveWidth: (popup.morphMode && popup.statusbar
      && popup.statusbar.pillWidth > 0)
    ? popup.statusbar.pillWidth : popup.panelTarget
  Behavior on liveWidth {
    enabled: !popup.morphMode
    NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease }
  }

  // ── the TOTP clock ────────────────────────────────────────────────
  // Codes turn over on the wall clock's 30-second boundaries, the same for
  // every entry, so one ticker drives every ring and no code is ever
  // fetched to draw it — only the time is.
  property real totpLeft: 30
  Timer {
    interval: 250
    repeat: true
    triggeredOnStart: true
    running: popup.shown && popup.mode === "actions"
    onTriggered: popup.totpLeft = 30 - (Date.now() / 1000) % 30
  }

  component TotpRing: Item {
    id: ringRoot
    readonly property bool late: popup.totpLeft <= 5
    readonly property color ink: late ? popup.errColor : popup.headColor
    implicitWidth: ringRow.implicitWidth
    implicitHeight: 18

    Row {
      id: ringRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Math.ceil(popup.totpLeft) + "s"
        color: ringRoot.ink
        font.family: Zenon.faceMono
        font.pixelSize: 11
      }

      Canvas {
        id: arc
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        readonly property real frac: popup.totpLeft / 30
        onFracChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onPaint: {
          const ctx = getContext("2d");
          ctx.reset();
          ctx.lineWidth = 2;
          ctx.strokeStyle = Zenon.border;
          ctx.beginPath();
          ctx.arc(8, 8, 6, 0, Math.PI * 2);
          ctx.stroke();
          ctx.strokeStyle = ringRoot.ink;
          ctx.lineCap = "round";
          ctx.beginPath();
          ctx.arc(8, 8, 6, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac);
          ctx.stroke();
        }
      }
    }
  }

  // The strip every view ends on: artemis' and folio's, ground, rule and
  // height, with the keys as caps. See morpheus/HintRow.
  component HintBar: Rectangle {
    id: hintBarRoot
    height: popup.msgH
    // see-through only over a list that rises out of it (a ScrollEdge)
    property bool frosted: false
    color: hintBarRoot.frosted ? Zenon.hintFrostBg : Zenon.hintBg
    property var rows: popup.hints()
    property string note: ""

    Rectangle {
      anchors.top: parent.top
      width: parent.width
      height: 1
      color: Zenon.border
    }

    HintRow {
      anchors.centerIn: parent
      rows: hintBarRoot.rows
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      visible: hintBarRoot.note !== ""
      text: hintBarRoot.note
      color: popup.dimColor
      font.family: Zenon.face
      font.pixelSize: 12
    }
  }

  function hints() {
    if (popup.mode === "actions")
      return [["arrows", "choose"], ["return", "run"], ["backspace", "back"]];
    if (popup.mode === "unlock" && !popup.emailSet)
      return popup.setupStep === "server"
        ? [["return", popup.setupText.trim() === "" ? "use bitwarden.com" : "save"],
           ["esc", "back"]]
        : [["return", "next"], ["esc", "clear · close"]];
    if (popup.mode === "unlock")
      // "return unlock" was advertised here before anything handled Return in
      // this mode; it does now. Esc clears a typed passphrase, then closes.
      return [["return", "unlock"], ["esc", "clear · close"]];
    if (popup.mode === "error")
      return [["return", "back"]];
    return [["type", "filter"], ["return", "actions"], ["alt s", "sync"],
            ["alt l", "lock"]];
  }

  // the first action that applies to the open entry, or -1 if none does
  function firstAction() {
    for (let i = 0; i < popup.actionTypes.length; ++i)
      if (popup.actionOk(i)) return i;
    return -1;
  }

  // indices into actionTypes, in on-screen order, for one column
  function actionsIn(col) {
    const out = [];
    for (let i = 0; i < popup.actionTypes.length; ++i)
      if (popup.actionTypes[i].col === col) out.push(i);
    return out;
  }

  // Up and down walk a column, wrapping; left and right cross to the same
  // row of the other one, or its last if it is shorter.
  // Actions that do not apply are stepped over; a column with none left is
  // not crossed into.
  function moveAction(dCol, dRow) {
    const cur = popup.actionTypes[popup.actionSel];
    if (!cur) return;
    let col = cur.col, list = popup.actionsIn(col);
    let row = list.indexOf(popup.actionSel);
    if (dCol !== 0) {
      const other = popup.actionsIn((col + dCol + 2) % 2).filter((i) => popup.actionOk(i));
      if (other.length === 0) return;
      // the nearest enabled row to this one
      let best = other[0], dist = 1e9;
      for (const i of other) {
        const d = Math.abs(popup.actionsIn(popup.actionTypes[i].col).indexOf(i) - row);
        if (d < dist) { dist = d; best = i; }
      }
      popup.actionSel = best;
      return;
    }
    for (let step = 1; step <= list.length; ++step) {
      const i = list[((row + dRow * step) % list.length + list.length) % list.length];
      if (popup.actionOk(i)) { popup.actionSel = i; return; }
    }
  }

  // ----------------------------------------------------------- keys --

  // ---------------------------------------------------------- panel --

  MouseArea {
    anchors.fill: parent
    z: 0
    onClicked: popup.closePopup()
  }

  Item {
    id: panel
    width: Math.round(popup.liveWidth)
    height: popup.calcHeight()
    // Zenon.slow is the pill's own height easing in shell.qml
    Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
    // Either edge. A layer opens out of the pill, so it has to be on the
    // same one, off whichever it is by the same lift. Placed by y, NOT by a
    // top/bottom anchor pair: flipping two anchors at runtime updates one
    // before the other, for that instant both apply and stretch the panel to
    // the screen, and that stretch overwrites — and so unbinds — `height`.
    // The panel then stayed screen-tall until the shell was restarted.
    anchors.horizontalCenter: parent.horizontalCenter
    y: Zenon.barTop ? Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
      : parent.height - height - Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
    z: 1
    opacity: popup.contentFade
    transform: Scale {
      origin.x: panel.width / 2
      // grows out of the edge the bar is on, which is the edge it came from
      origin.y: Zenon.barTop ? 0 : panel.height
      xScale: popup.panelX
      yScale: popup.panelY
    }

    MouseArea { anchors.fill: parent }

    LayerShadow {
      panel: bgRoot
      cornerRadius: Zenon.pillRadius
      morphed: popup.morphMode
    }

    // ClippingRectangle, not Rectangle + clip: true. Qt's own clip is
    // RECTANGULAR — it clips to the bounding box and knows nothing about the
    // radius — so every square child painted to the panel's edge (the bottom
    // strip most visibly) filled in the rounded corners behind it. This one
    // clips to the rounded shape itself.
    ClippingRectangle {
      id: bgRoot
      anchors.fill: parent
      // Grown by its own border: a ClippingRectangle insets its children by
      // border.width on every side, so the content box came out 2px smaller
      // than the panel and any layout measured against the panel's size fell
      // one row or one column short. This hands the content its full box back.
      anchors.margins: -bgRoot.border.width
      color: popup.bgColor
      radius: Zenon.pillRadius
      topLeftRadius: Zenon.pillRadius
      topRightRadius: Zenon.pillRadius
      bottomLeftRadius: Zenon.pillRadius
      bottomRightRadius: Zenon.pillRadius
      border.color: Zenon.border
      border.width: 1
      focus: true

      // ---------------------------------------------------- list view --

      Item {
        id: listView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.mode === "list" ? 1 : 0
        x: popup.mode === "list" ? 0 : -24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        // credentials scrolled off either end carry on under the filter line
        // and up out of the hint strip, frosted, as artemis has it — see
        // morpheus/ScrollEdge. Before the column, so both draw over them.
        ScrollEdge {
          view: list
          x: list.x
          width: list.width
          height: list.y
        }
        ScrollEdge {
          view: list
          below: true
          x: list.x
          y: list.y + list.height
          width: list.width
          height: listHints.height
        }

        Column {
          anchors.fill: parent

          // The filter, as artemis wears its search: a line that only
          // exists once there is something typed into it.
          Item {
            id: inputBar
            width: parent.width
            height: popup.query.length > 0 ? popup.searchH : 0
            Behavior on height { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
            clip: true

            Row {
              anchors.fill: parent
              anchors.leftMargin: 16
              visible: inputBar.height > 2

              Text {
                width: 26 + 10
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: ""
                color: popup.entryColor
                font.family: Zenon.faceMono
                font.pixelSize: 15
              }

              TextInput {
                id: filterInput
                width: parent.width - 36 - 16
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                color: popup.entryColor
                selectionColor: popup.entryColor
                selectedTextColor: "#000000"
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: 18
                cursorVisible: false
                cursorDelegate: Item {}
                clip: true
                Keys.forwardTo: bgRoot

                Rectangle {
                  anchors.left: parent.left
                  anchors.leftMargin: Math.min(filterInput.contentWidth + 2,
                                               filterInput.width - 5)
                  anchors.verticalCenter: parent.verticalCenter
                  width: 3
                  height: 20
                  radius: 1
                  color: popup.entryColor
                  opacity: 0.25
                  visible: filterInput.activeFocus && filterInput.text.length > 0
                  SequentialAnimation on opacity {
                    running: filterInput.activeFocus && filterInput.text.length > 0
                    loops: Animation.Infinite
                    NumberAnimation { to: 1; duration: 550; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.25; duration: 550; easing.type: Easing.InOutSine }
                  }
                }

                onTextChanged: {
                  popup.query = filterInput.text;
                  popup.sel = 0;
                  popup.applyFilter();
                }
              }
            }
          }

          Item {
            width: parent.width
            height: popup.filtered.length === 0 ? popup.emptyH : 0
            Text {
              anchors.centerIn: parent
              visible: popup.filtered.length === 0
              text: popup.query === "" ? "vault is empty" : "No matches found"
              color: popup.dimColor
              font.family: Zenon.face
              font.weight: 600
              font.pixelSize: 15
            }
          }

          GridView {
            id: list
            // Finder's rubber band and the smooth wheel notch, one rule for
            // the whole shell — see morpheus/Elastic.qml. Inside the view
            // rather than over it: it pins itself to the viewport.
            ElasticScroll { view: list }
            width: parent.width
            height: popup.listHeight()
            clip: true
            flow: GridView.FlowLeftToRight
            cellWidth: width / popup.effCols
            cellHeight: popup.cellH
            model: popup.displayOrder
            highlightMoveDuration: 120

            delegate: Item {
              id: cell
              // modelData is the index into `filtered`; index is only where
              // the cell sits in the column-major display. Selection speaks
              // in the first — comparing it against the second lit the
              // wrong row's text the moment there were two columns.
              required property var modelData
              required property int index
              readonly property var entry: modelData >= 0 ? popup.filtered[modelData] : null
              readonly property bool picked: modelData >= 0 && modelData === popup.sel
              width: list.cellWidth
              height: list.cellHeight

              Rectangle {
                anchors.fill: parent
                color: cell.picked ? Zenon.border : "transparent"
              }

              Text {
                id: rowGlyph
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                horizontalAlignment: Text.AlignHCenter
                visible: !!cell.entry
                readonly property var mark: Calypso.glyphFor(cell.entry)
                text: mark.glyph
                // a site's own mark a shade up from the generic key, so the
                // column reads as pictures rather than a stripe of keys
                color: cell.picked ? popup.entryColor
                  : mark.brand ? popup.keyColor : popup.dimColor
                font.family: Zenon.faceMono
                // artemis' size: these are pictures, not letters, and at
                // the text's own size they read as smudges in the margin
                font.pixelSize: 22
              }

              // folder / name — the thing you are looking for, first and
              // in full weight
              Text {
                id: rowName
                anchors.left: rowGlyph.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth,
                                cell.width - x - 16 - (rowUser.visible ? 60 : 0))
                text: {
                  if (!cell.entry) return "";
                  const pref = cell.entry.folder
                    ? "<span style=\"color:" + popup.dimColor + ";\">"
                      + Strings.escapeHtml(cell.entry.folder) + " / </span>" : "";
                  // a small clock where there is an authenticator — the
                  // scan's answer, so it appears a moment after the list
                  const totp = popup.hasTotp(cell.entry) === true
                    ? "&nbsp;&nbsp;<span style=\"color:" + popup.headColor
                      + ";font-size:12px;\">\uF017</span>" : "";
                  return pref + Calypso.highlight(cell.entry.name, popup.query) + totp;
                }
                color: cell.picked ? popup.entryColor : popup.fgColor
                textFormat: Text.RichText
                clip: true
                font.family: Zenon.face
                font.weight: 600
                font.pixelSize: 16
              }

              // the account, set back to the far edge where it is there to
              // tell two logins apart, not to be read first
              Text {
                id: rowUser
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.left: rowName.right
                anchors.leftMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                visible: !!cell.entry && cell.entry.user !== ""
                horizontalAlignment: Text.AlignRight
                text: cell.entry ? cell.entry.user : ""
                color: popup.dimColor
                elide: Text.ElideLeft
                font.family: Zenon.face
                font.pixelSize: 14
              }

              MouseArea {
                anchors.fill: parent
                enabled: !!cell.entry
                onClicked: {
                  popup.sel = cell.modelData;
                  popup.openActions();
                }
              }
            }
          }

          HintBar {
            id: listHints
            width: parent.width
            frosted: true
            note: popup.filtered.length + (popup.filtered.length === 1
              ? " credential" : " credentials")
          }
        }
      }

      // ------------------------------------------------- actions view --

      Item {
        id: actionsView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.mode === "actions" ? 1 : 0
        x: popup.mode === "actions" ? 0 : 24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        Column {
          anchors.fill: parent

          // which entry the actions are about, in the same place and the
          // same shape as its row in the list
          Item {
            width: parent.width
            height: popup.actHeadH

            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              height: 1
              color: Zenon.border
            }

            Text {
              id: actGlyph
              anchors.left: parent.left
              anchors.leftMargin: 16
              anchors.verticalCenter: parent.verticalCenter
              width: 40
              horizontalAlignment: Text.AlignHCenter
              text: Calypso.glyphFor(popup.activeEntry).glyph
              color: popup.entryColor
              font.family: Zenon.faceMono
              font.pixelSize: 34
            }

            Column {
              anchors.left: actGlyph.right
              anchors.leftMargin: 12
              anchors.right: parent.right
              anchors.rightMargin: 16
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1

              Text {
                width: parent.width
                text: popup.activeEntry
                  ? (popup.activeEntry.folder ? popup.activeEntry.folder + " / " : "")
                    + popup.activeEntry.name
                  : ""
                color: popup.fgColor
                elide: Text.ElideMiddle
                font.family: Zenon.face
                font.weight: 700
                font.pixelSize: 17
              }

              Text {
                readonly property bool isCard:
                  !!popup.activeEntry && popup.activeEntry.type === "Card"
                width: parent.width
                visible: isCard || (!!popup.activeEntry && popup.activeEntry.user !== "")
                // why every action below is dimmed, rather than leaving
                // that to be discovered one failure at a time
                text: isCard ? "card \u00b7 behind bitwarden's re-prompt, open it in the vault"
                  : popup.activeEntry ? popup.activeEntry.user : ""
                color: isCard ? popup.errColor : popup.dimColor
                elide: Text.ElideMiddle
                font.family: Zenon.face
                font.pixelSize: 13
              }
            }
          }

          // Two columns — what gets typed where the cursor is, and what
          // goes on the clipboard — instead of seven labels in one strip
          // that ran into each other as soon as the panel was narrower
          // than all seven.
          Row {
            id: actionGrid
            width: parent.width
            height: popup.actBodyH

            Repeater {
              model: [
                { title: "type", glyph: "" },
                { title: "copy", glyph: "" }
              ]

              delegate: Item {
                id: group
                required property var modelData
                required property int index
                width: actionGrid.width / 2
                height: actionGrid.height

                Rectangle {
                  visible: group.index === 1
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.topMargin: 10
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: 10
                  width: 1
                  color: Zenon.border
                }

                Column {
                  anchors.fill: parent
                  topPadding: 6

                  Item {
                    width: parent.width
                    height: popup.actSectH

                    Row {
                      anchors.left: parent.left
                      anchors.leftMargin: 16
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 8

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: group.modelData.glyph
                        color: popup.headColor
                        font.family: Zenon.faceMono
                        font.pixelSize: 13
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: group.modelData.title
                        color: popup.headColor
                        font.family: Zenon.face
                        font.weight: 600
                        font.pixelSize: 13
                        font.letterSpacing: 1
                      }
                    }
                  }

                  Repeater {
                    model: popup.actionsIn(group.index)

                    delegate: Item {
                      id: act
                      required property var modelData   // index into actionTypes
                      readonly property var action: popup.actionTypes[modelData]
                      readonly property bool ok: popup.actionOk(modelData)
                      readonly property bool picked: ok && popup.actionSel === modelData
                      readonly property bool isTotp:
                        action.kind === "totp" || action.kind === "copytotp"
                      width: group.width
                      height: popup.cellH
                      // there, so the grid keeps its shape, but plainly not
                      // on offer
                      opacity: ok ? 1 : 0.3

                      Rectangle {
                        anchors.fill: parent
                        color: act.picked ? Zenon.border : "transparent"
                      }

                      Text {
                        id: actIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        horizontalAlignment: Text.AlignHCenter
                        text: act.action.glyph
                        color: act.picked ? popup.entryColor : popup.dimColor
                        font.family: Zenon.faceMono
                        font.pixelSize: 22
                      }

                      // How long the code that would be typed has left. A
                      // code with two seconds to live is a code that expires
                      // on the way to the server, so it goes red for the
                      // last five — wait for the ring to refill.
                      TotpRing {
                        id: ring
                        visible: act.isTotp && act.ok && popup.hasTotp(popup.activeEntry) === true
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Text {
                        anchors.left: actIcon.right
                        anchors.leftMargin: 10
                        anchors.right: ring.visible ? ring.left : parent.right
                        anchors.rightMargin: ring.visible ? 8 : 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: act.action.label
                        color: act.picked ? popup.entryColor : popup.fgColor
                        elide: Text.ElideRight
                        font.family: Zenon.face
                        font.weight: act.picked ? 600 : 400
                        font.pixelSize: 15
                      }

                      MouseArea {
                        anchors.fill: parent
                        enabled: act.ok
                        hoverEnabled: true
                        onEntered: popup.actionSel = act.modelData
                        onClicked: {
                          popup.actionSel = act.modelData;
                          popup.execute(act.action.kind);
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          HintBar { width: parent.width }
        }
      }

      // ---------------------------------------------------- error view --

      Item {
        id: errorView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.mode === "error" ? 1 : 0
        x: popup.mode === "error" ? 0 : -24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        Column {
          anchors.fill: parent

          // Said in red, not ON red: a full slab was the loudest thing in
          // the shell for "this entry has no TOTP".
          Item {
            width: parent.width
            height: popup.lockFieldH

            Rectangle {
              anchors.fill: parent
              color: popup.failTint
              opacity: 0.45
            }

            Row {
              anchors.centerIn: parent
              spacing: 10

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: popup.errColor
                font.family: Zenon.faceMono
                font.pixelSize: 15
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: popup.errorMsg
                color: popup.errColor
                font.family: Zenon.face
                font.weight: 600
                font.pixelSize: 15
              }
            }
          }

          HintBar { width: parent.width }
        }
      }

      // -------------------------------------------------- unlock view --

      Item {
        id: unlockView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.mode === "unlock" ? 1 : 0
        x: popup.mode === "unlock" ? 0 : 24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        Column {
          anchors.fill: parent

          // ── the passphrase field ─────────────────────────────────────
          // No external prompt any more. rbw's pinentry is pointed at calypso's
          // own helper (ensureRbwConfig), so the password is typed here and
          // handed straight to the agent. Shaped like ceres' PasswordField —
          // lock, message, and what the password is for underneath — rather
          // than under a red "vault locked" slab: a locked vault is the
          // normal state, not an alarm.
          Item {
            id: field
            width: parent.width
            height: popup.lockFieldH

            // rbw cannot do anything at all without an account address, so
            // on a fresh machine this asks for one, then for the server.
            Column {
              anchors.centerIn: parent
              visible: !popup.emailSet
              spacing: 4

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 9
                opacity: popup.setupStep === "saving" ? 0.45 : 1

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  // envelope, then server
                  text: popup.setupStep === "email" ? "\uF0E0" : "\uF233"
                  color: popup.errColor
                  font.family: Zenon.face
                  font.pixelSize: 14
                }

                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 2

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property bool empty: popup.setupText === ""
                    text: popup.setupStep === "saving" ? "saving…"
                      : !empty ? popup.setupText
                      : popup.setupStep === "email" ? "your bitwarden email"
                      : "server url, or return for bitwarden.com"
                    color: empty || popup.setupStep === "saving"
                      ? popup.dimColor : popup.entryColor
                    font.family: Zenon.face
                    font.pixelSize: 14
                  }

                  Caret { on: popup.setupStep !== "saving" && popup.setupText !== "" }
                }
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: popup.setupErr !== "" ? popup.setupErr
                  : popup.setupStep === "email" ? "no bitwarden account set yet"
                  : "self-hosted? your vaultwarden address"
                color: popup.setupErr !== "" ? popup.errColor : Zenon.keyInk
                font.family: Zenon.face
                font.pixelSize: 12
              }
            }

            Item {
              id: entry
              width: parent.width
              height: parent.height
              visible: popup.emailSet

              Rectangle {
                anchors.fill: parent
                color: popup.phase === "fail" ? popup.failTint : "transparent"
                Behavior on color {
                  ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                }
              }

              Column {
                id: fieldCol
                anchors.centerIn: parent
                spacing: 4

                // Message-or-dots and the caret ride in ONE row so the caret
                // always sits just after whatever is there, instead of two
                // centred children fighting for the same middle. A Row skips
                // invisible children, so the placeholder simply drops out once
                // there is a password to draw.
                Row {
                  id: fieldRow
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: 5
                  opacity: popup.phase === "checking" ? 0.45 : 1
                  Behavior on opacity { NumberAnimation { duration: Zenon.fast } }

                  // The lock carries the glow: it is the thing telling you the
                  // field is live and waiting, in place of a caret parked on an
                  // empty field.
                  //
                  // A REAL blurred copy stacked behind, not layer.effect with a
                  // scaled shadow. A layer's texture is exactly the item's
                  // bounds, so a shadow scaled past them is clipped off and all
                  // that survives is the glyph itself — which reads as the glyph
                  // pulsing, not as anything radiating.
                  Item {
                    id: glyphBox
                    anchors.verticalCenter: parent.verticalCenter
                    visible: popup.pw.length === 0
                    implicitWidth: lockGlyph.implicitWidth + 9
                    implicitHeight: lockGlyph.implicitHeight

                    readonly property bool lit:
                      popup.phase === "input" && popup.pw.length === 0

                    Text {
                      id: lockGlyph
                      // left-anchored, so glyphBox's extra 9px falls entirely on
                      // the right as the gap before the message
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: popup.phase === "success" ? "" : ""
                      color: popup.phase === "success" ? Zenon.green
                        : popup.phase === "input" || popup.phase === "fail"
                          ? popup.errColor : popup.dimColor
                      font.family: Zenon.face
                      // Bound to the message beside it rather than set to a
                      // number, so the two cannot drift apart later
                      font.pixelSize: fieldMsg.font.pixelSize
                    }

                    // Wide wrapper, small disc, big blur — the three together
                    // are what make it a spread glow rather than a tight ring:
                    // the disc supplies the light, the blur spreads it, and the
                    // wrapper is the room it is allowed to spread into.
                    Glow {
                      z: -1
                      anchors.centerIn: lockGlyph
                      width: lockGlyph.implicitHeight * 4.2
                      height: width
                      ink: popup.errColor
                      // square source on a square wrapper — a round bloom, which
                      // is what a glyph wants
                      sourceW: lockGlyph.implicitHeight * 1.09
                      sourceH: lockGlyph.implicitHeight * 1.09
                      soft: 48
                      visible: glyphBox.lit
                      opacity: glyphBox.glowPulse
                    }

                    // Slower than the caret's blink on purpose: this is a thing
                    // breathing, not a cursor ticking.
                    property real glowPulse: 0.40
                    SequentialAnimation on glowPulse {
                      running: glyphBox.lit
                      loops: Animation.Infinite
                      NumberAnimation { to: 1.0; duration: 1300; easing.type: Easing.InOutSine }
                      NumberAnimation { to: 0.40; duration: 1300; easing.type: Easing.InOutSine }
                    }
                  }

                  Text {
                    id: fieldMsg
                    anchors.verticalCenter: parent.verticalCenter
                    visible: popup.pw.length === 0
                    text: popup.phase === "checking" ? "unlocking…"
                      : popup.phase === "fail" ? "wrong master password"
                      : popup.phase === "success" ? "unlocked"
                      : "input your master password"
                    color: popup.phase === "fail" ? popup.errColor : popup.dimColor
                    font.family: Zenon.face
                    font.pixelSize: 14
                  }

                  // The COUNT is the model — the characters never reach the
                  // scene graph. Straight out of cerberus.
                  Repeater {
                    model: popup.phase === "success" ? 0 : popup.pw.length
                    delegate: Text {
                      anchors.verticalCenter: parent.verticalCenter
                      // U+F09DE, past the BMP, so it is written as the surrogate
                      // pair a QML string literal needs
                      text: "󰧞"
                      color: popup.entryColor
                      font.family: Zenon.face
                      font.pixelSize: 15
                    }
                  }

                  Caret { on: popup.phase === "input" && popup.pw.length > 0 }
                }

                // what the password is for — never ask for one without
                // saying what it will do
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: popup.failMsg !== "" ? popup.failMsg : "unlocks your bitwarden vault"
                  color: popup.failMsg !== "" ? popup.errColor : Zenon.keyInk
                  font.family: Zenon.face
                  font.pixelSize: 12
                }
              }

              // Just past the dots, clear of the centred row so it never
              // shifts it — the same place ceres' password field wears it.
              // Plain x/y: anchors are unreliable in a layer window.
              CapsGlyph {
                shown: popup.mode === "unlock"
                size: 15
                x: (entry.width + fieldRow.width) / 2 + 10
                y: fieldCol.y + fieldRow.y + (fieldRow.height - height) / 2
              }

              // a wrong passphrase should be felt, not just read
              SequentialAnimation {
                id: shake
                running: popup.phase === "fail"
                NumberAnimation { target: entry; property: "x"; to:  9; duration: 55 }
                NumberAnimation { target: entry; property: "x"; to: -7; duration: 90 }
                NumberAnimation { target: entry; property: "x"; to:  4; duration: 80 }
                NumberAnimation { target: entry; property: "x"; to:  0; duration: 70 }
              }
            }
          }

          HintBar { width: parent.width }
        }
      }

  Keys.onEscapePressed: (event) => {
    event.accepted = true;
    if (popup.mode === "list" && filterInput.text !== "") {
      filterInput.text = "";
    } else if (popup.mode === "list") popup.closePopup();
    else if (popup.mode === "error") popup.backToActions();
    else if (popup.mode === "unlock") {
      // there is nothing behind a locked vault to go back TO — going "back"
      // used to land on an empty list with no explanation
      if (!popup.emailSet) {
        if (popup.setupStep === "saving") return;
        popup.setupErr = "";
        if (popup.setupText !== "") popup.setupText = "";
        else if (popup.setupStep === "server") {
          popup.setupStep = "email";
          popup.setupText = popup.setupEmail;
        } else popup.closePopup();
      }
      else if (popup.pw !== "") popup.clearPassword();
      else popup.closePopup();
    }
    else popup.goBack();
  }

  // Caps Lock turning OFF lands on the key's release, not its press — see
  // morpheus/CapsLock — so the vault field asks again when it is let go.
  Keys.onReleased: (event) => {
    if (popup.mode === "unlock" && event.key === Qt.Key_CapsLock) {
      event.accepted = true;
      CapsLock.read();
    }
  }

  // Asked as the vault prompt opens: caps may already be on.
  Connections {
    target: popup
    function onModeChanged() { if (popup.mode === "unlock") CapsLock.read(); }
  }

  Keys.onPressed: (event) => {
    if (popup.mode === "list") {
      if ((event.key === Qt.Key_S) && (event.modifiers & Qt.AltModifier)) {
        event.accepted = true;
        syncProc.command = ["rbw", "sync"];
        syncProc.running = true;
        return;
      }
      if ((event.key === Qt.Key_L) && (event.modifiers & Qt.AltModifier)) {
        event.accepted = true;
        popup.closePopup();
        popup.detach("rbw lock");
        return;
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        event.accepted = true;
        popup.openActions();
        return;
      }
      if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
        event.accepted = true;
        popup.moveSel(event.key === Qt.Key_PageUp
          ? -popup.visibleRows : popup.visibleRows);
        return;
      }
      if (event.key === Qt.Key_Up) {
        event.accepted = true; popup.moveVert(-1); return;
      }
      if (event.key === Qt.Key_Down) {
        event.accepted = true; popup.moveVert(1); return;
      }
      if (event.key === Qt.Key_Left) {
        event.accepted = true; popup.moveHoriz(-1); return;
      }
      if (event.key === Qt.Key_Right) {
        event.accepted = true; popup.moveHoriz(1); return;
      }
    } else if (popup.mode === "unlock" && !popup.emailSet) {
      if (popup.setupStep === "saving") { event.accepted = true; return; }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        event.accepted = true;
        popup.submitSetup();
      } else if (event.key === Qt.Key_Backspace) {
        event.accepted = true;
        const chars = Array.from(popup.setupText);
        chars.pop();
        popup.setupText = chars.join("");
        popup.setupErr = "";
      } else if (event.text && event.text.length > 0 &&
                 !(event.modifiers & Qt.ControlModifier) &&
                 !(event.modifiers & Qt.MetaModifier)) {
        event.accepted = true;
        popup.setupText += event.text;
        popup.setupErr = "";
      }
    } else if (popup.mode === "unlock") {
      // The whole field, in one place. Backspace deletes a character here
      // rather than leaving the mode — escape is how you leave.
      if (event.key === Qt.Key_CapsLock) {
        event.accepted = true;
        CapsLock.read();
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        event.accepted = true;
        popup.submitUnlock();
      } else if (event.key === Qt.Key_Backspace) {
        event.accepted = true;
        if (popup.pw.length > 0) {
          // Array.from, not slice(0,-1): a codepoint outside the BMP is two
          // UTF-16 units and slicing would leave half of one behind
          const chars = Array.from(popup.pw);
          chars.pop();
          popup.pw = chars.join("");
        }
      } else if (event.text && event.text.length > 0 &&
                 !(event.modifiers & Qt.ControlModifier) &&
                 !(event.modifiers & Qt.MetaModifier)) {
        event.accepted = true;
        if (popup.phase === "input") popup.pw += event.text;
      }
    } else if (event.key === Qt.Key_Backspace && popup.mode === "actions") {
      event.accepted = true;
      popup.goBack();
    } else if (popup.mode === "actions") {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        event.accepted = true;
        if (popup.actionOk(popup.actionSel))
          popup.execute(popup.actionTypes[popup.actionSel].kind);
        return;
      }
      if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
        event.accepted = true;
        popup.moveAction(0, event.key === Qt.Key_Up ? -1 : 1);
        return;
      }
      if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
        event.accepted = true;
        popup.moveAction(event.key === Qt.Key_Left ? -1 : 1, 0);
        return;
      }
      // Tab still walks every action in order, as it always did
      if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
        event.accepted = true;
        const n = popup.actionTypes.length;
        let i = popup.actionSel;
        for (let step = 0; step < n; ++step) {
          i = (i + (event.key === Qt.Key_Backtab ? n - 1 : 1)) % n;
          if (popup.actionOk(i)) { popup.actionSel = i; break; }
        }
        return;
      }
    } else if (popup.mode === "error") {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter ||
          event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
        event.accepted = true;
        popup.backToActions();
        return;
      }
    }
  }
    }
  }

  // -------------------------------------------------------- helpers --

  function listHeight() {
    if (popup.filtered.length === 0) return 0;
    const needed = Math.ceil(popup.filtered.length / popup.effCols);
    return Math.max(1, Math.min(needed, popup.visibleRows)) * popup.cellH;
  }

  function calcHeight() {
    if (popup.mode === "list")
      return (popup.query.length > 0 ? popup.searchH : 0)
        + (popup.filtered.length === 0 ? popup.emptyH : popup.listHeight())
        + popup.msgH;
    if (popup.mode === "actions")
      return popup.actHeadH + popup.actBodyH + popup.msgH;
    return popup.lockFieldH + popup.msgH;
  }

  // column-major display: down = next credential (running on into the
  // next column), right = the same row of the next column
  function moveVert(delta) {
    moveSel(delta);
  }

  function moveHoriz(delta) {
    const len = popup.filtered.length;
    const c = popup.effCols;
    if (len === 0 || c < 2) return;
    const r = popup.gridRows;
    const row = popup.sel % r;
    const col = (Math.floor(popup.sel / r) + delta + c) % c;
    // a shorter last column has no cell on this row; take its last one
    popup.sel = Math.min(col * r + row, len - 1);
    Qt.callLater(() => list.positionViewAtIndex(popup.cellOf(popup.sel), GridView.Contain));
  }

  function moveSel(delta) {
    const len = popup.filtered.length;
    if (len === 0) return;
    popup.sel = ((popup.sel + delta) % len + len) % len;
    Qt.callLater(() => list.positionViewAtIndex(popup.cellOf(popup.sel), GridView.Contain));
  }

  Timer {
    id: focusRetry
    interval: 60
    repeat: true
    onTriggered: {
      if (!popup.shown) {
        stop();
        return;
      }
      popup.syncFocus();
      if ((popup.mode === "list" && filterInput.activeFocus) ||
          (popup.mode !== "list" && bgRoot.activeFocus)) stop();
      if (focusRetry.counter++ > 12) stop();
    }
    property int counter: 0
  }
}
