// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Zenworks' TERMINAL SETUP, OFFERED — the zsh prompt, suggestions and fuzzy
// completion shipped in zsh/ beside the shell (scripts/zsh-setup.sh does
// the files). The package never puts it in place: it is asked.
//
//   ONCE, AT THE FIRST START: a notification with two buttons, a few
//   seconds after the desktop has settled. Closed unanswered, it is asked
//   once more at the next start, then only here in Oracle (Default apps ›
//   Terminal setup). One whose ~/.zshrc is the shipped one already and
//   whose login shell is zsh is never asked: that is a yes. The shipped
//   files with bash still the login shell are asked as usual (user,
//   2026-10-25: the setup must make zsh the default shell — that case used
//   to count as a yes and never got there).
//
//   USE IT: the tools it needs that are missing installed through Ceres
//   (its own password card), yours kept as *.before-zenworks, the shipped
//   ones copied in, then zsh made your login shell if it is not — the
//   polkit agent asks for that password — and this session told so, so
//   what starts next is zsh without logging out. Then a note: a new
//   terminal's first start fetches the prompt's plugins once.
//
// The answer is kept in welcome.json (Quickshell.statePath).
//
// THE CHEAT SHEET, ONCE: no welcome.json at all is the very first start,
// so the shortcuts sheet opens over the new desktop (Oracle.keysSheetAsked,
// KeysSheet listens) and welcome.json notes it at once. Closed, it hands on
// to Make it yours (Oracle.welcomeLookAsked, WelcomeLook: theme, accent,
// background). The terminal question waits until both are closed.

import QtQuick
import Quickshell
import Quickshell.Io
import "../ceres"

Scope {
  id: zsh

  readonly property string script: Quickshell.shellDir + "/scripts/zsh-setup.sh"
  // "" not asked yet · "asked" shown once, not answered · "yes" · "no" ·
  // "quiet" shown twice, not answered: Oracle's row is the way now
  property string answer: ""
  // "" not shown yet · "shown"
  property string keys: ""
  property bool busy: false

  FileView {
    id: stateFile
    path: Quickshell.statePath("welcome.json")
    blockLoading: true
    printErrors: false
  }
  function save() {
    stateFile.setText(JSON.stringify({ zsh: zsh.answer, keys: zsh.keys }, null, 1) + "\n");
  }
  function keep(a) {
    zsh.answer = a;
    zsh.save();
  }
  Component.onCompleted: {
    const text = stateFile.text() || "";
    try {
      const j = JSON.parse(text || "{}");
      zsh.answer = String(j.zsh || "");
      zsh.keys = String(j.keys || "");
    } catch (e) {}
    // older welcome.json files have no keys: those desktops are not new
    if (text.trim() === "") {
      zsh.keys = "shown";
      zsh.save();
      welcome.start();
    }
    if (zsh.answer === "" || zsh.answer === "asked") settle.start();
  }

  // the bar up first, so the sheet arrives on a desktop
  property bool lookNext: false
  Timer {
    id: welcome
    interval: 2000
    onTriggered: { zsh.lookNext = true; Oracle.keysSheetAsked(); }
  }
  // the first start's two cards again, on asking: `qs ipc call Welcome
  // show` (the cheat sheet, then Make it yours), or `look` for the second
  IpcHandler {
    target: "Welcome"
    function show(): void { zsh.lookNext = true; Oracle.keysSheetAsked(); }
    function look(): void { Oracle.welcomeLookAsked(); }
  }
  Connections {
    target: Oracle
    function onKeysSheetOpenChanged() {
      if (Oracle.keysSheetOpen || !zsh.lookNext) return;
      zsh.lookNext = false;
      Oracle.welcomeLookAsked();
    }
  }

  // a few seconds in: the bar is up and a notification lands on a desktop
  // — never under the cheat sheet, which is read first
  Timer {
    id: settle
    interval: 8000
    onTriggered: {
      if (welcome.running || zsh.lookNext || Oracle.keysSheetOpen || Oracle.welcomeLookOpen) { settle.restart(); return; }
      check.then = "offer";
      check.running = true;
    }
  }

  // what is here: the shipped setup already, and what it needs that is not
  Process {
    id: check
    property string then: ""
    property bool same: false
    property bool loginZsh: false
    property var missing: []
    command: ["sh", zsh.script, "check"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = String(text).split("\n");
        check.same = lines[0] === "same";
        check.loginZsh = lines.indexOf("login: yes") >= 0;
        const m = lines.find((l) => l.startsWith("missing:")) || "missing:";
        check.missing = m.slice(8).trim().split(/\s+/).filter((p) => p !== "");
      }
    }
    onExited: (code) => {
      if (code !== 0) return;
      if (check.then === "offer") {
        if (check.same && check.loginZsh) zsh.keep("yes");
        else ask.running = true;
      } else if (check.then === "apply") zsh.install();
    }
  }

  // the question, as a notification with its two buttons (howler draws
  // them); notify-send waits, and says which was pressed — nothing, when
  // it was closed without an answer
  Process {
    id: ask
    command: ["notify-send", "--app-name=Zenworks", "--icon=utilities-terminal",
              "--action=use=Use it", "--action=no=No thanks",
              "Use Zenworks' terminal setup?",
              "zsh with a fast prompt, suggestions and fuzzy completion. Your current setup is kept as a backup."]
    stdout: StdioCollector {
      onStreamFinished: {
        const a = String(text).trim();
        if (a === "use") zsh.apply();
        else if (a === "no") zsh.keep("no");
        else zsh.keep(zsh.answer === "asked" ? "quiet" : "asked");
      }
    }
  }

  // ── USE IT ─────────────────────────────────────────────────────────
  // Oracle's row and the notification's button both come here.
  function apply() {
    if (zsh.busy) return;
    zsh.busy = true;
    check.then = "apply";
    check.running = true;
  }
  function install() {
    if (check.missing.length === 0) { files.running = true; return; }
    const asked = Ceres.install(check.missing, "for Zenworks' terminal setup", (ok, how) => {
      if (ok) files.running = true;
      else zsh.finish(how === "cancelled" ? "" : "The terminal setup needs " + check.missing.join(", ") + ", which did not install");
    });
    if (!asked) zsh.finish("Ceres is busy with another job — try again once it is done");
  }
  Process {
    id: files
    command: ["sh", zsh.script, "apply"]
    stderr: StdioCollector { id: filesErr }
    onExited: (code) => {
      if (code !== 0) { zsh.finish("The setup files were not copied: " + String(filesErr.text).trim()); return; }
      zsh.keep("yes");
      login.running = true;
    }
  }
  Process {
    id: login
    command: ["sh", zsh.script, "login"]
    stderr: StdioCollector { id: loginErr }
    onExited: (code) => zsh.finish(code === 0
      ? "Done — open a new terminal. Its first start fetches the prompt's plugins once."
      : "The setup is in place, but zsh is not your login shell yet: "
        + (String(loginErr.text).trim() || "the password was not given") + ". Use it again here to retry.")
  }
  function finish(said) {
    zsh.busy = false;
    if (said !== "") Quickshell.execDetached(["notify-send", "--app-name=Zenworks", "--icon=utilities-terminal", "Terminal setup", said]);
  }
}
