// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
// ICARUS — desktop context menu, tray-menu styled, floating on focused monitor

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../oracle"
import "icarus.js" as Icarus
import "../morpheus/icons.js" as Icons
// terminus' pure half, for the verbs a file already has there — trash, copy,
// open with, a shell here — so the Home cards do them the same way
import "../terminus/terminus.js" as Terminus
import "../terminus"
import "../clio"

Item {
  id: root

  // shell passes focusedScreen here (like other popups)
  property var screen: null
  property point anchorPos: Qt.point(0, 0)
  property bool shown: false
  property string cwd: Quickshell.env("HOME") || "/"
  // ── THE HOME CARDS ────────────────────────────────────────────────────
  // A stack, one entry per card: the base card's directory, then each directory
  // opened beside it. `from` is the row of the card before that opened it.
  // cwd is the base card's directory and stays in step with homeTrail[0].
  property var homeTrail: [{ dir: root.cwd, from: -1 }]
  // When the menu was last put away, for Oracle.menuHomeRemember.
  property real closedAt: 0
  // The Home cards alive right now, by level, for the focus grab and for the
  // keyboard. Filled by the Instantiator that makes them.
  property var homeCards: []
  // THE SELECTION, one for every card: which card, which row. The pointer
  // and the keyboard both move it, so a row is lit for one reason only.
  property int selLevel: -1
  property int selIndex: -1
  // the keyboard walked into a card whose rows had not arrived yet
  property bool selWantFirst: false
  property string pendingConfirmId: ""
  property string childMenu: "" // "" | "apps" | "file" | "session" | "trash"

  // ── the trash ─────────────────────────────────────────────────────────
  // XDG's trash, wherever XDG_DATA_HOME points — not a path written out here.
  readonly property string trashDir: Paths.dataDir() + "/Trash"
  property int trashCount: 0
  // Emptying is not undoable, so it takes two clicks: the row arms first and
  // says so. The confirm submenu this menu already has is wired to the session
  // entries by index, and generalising it was more surgery than one red row.
  property bool trashArmed: false
  // ── WHERE EACH SUBMENU HANGS FROM ───────────────────────────────────
  // Every row that has children reports its own offset inside the root card,
  // and its menu is placed against that. Read off the ROW rather than
  // computed, because an index times a row height is wrong the moment a row
  // above it is switched off in oracle — and because there is no single row
  // height anyway, separators being 7 and rows 30.
  //
  // This replaces three different rules that had grown up side by side:
  // trash and shell were already row-anchored; apps, home and recent pinned
  // themselves to the TOP of the root card regardless of which row they
  // belonged to; and session used `4 + 30 + 1 + 8 + 1`, a constant that was
  // true when session was the second thing in the menu and has been wrong
  // since — most recently by a whole Shell row. That constant is what made
  // the session menu open above its own row.
  // ASKED OF THE CARD, not reported by its rows. Every row used to push its
  // own y up here through noteRowY, because the card was hand-built and only
  // a delegate knew where it had landed. rootMenu is a CardMenu now and can
  // simply be asked — which also retires the whole reporting mechanism and
  // the stale-value bug it carried, where a row that stopped existing left
  // its last offset behind.
  function rowIndexOf(kind) {
    for (let i = 0; i < root.rootModel.length; ++i)
      if (root.rootModel[i].kind === kind) return i;
    return -1;
  }

  // The top margin a submenu belonging to `kind` should take, clamped so a
  // long one cannot hang off the bottom or the top of the screen. `bgH` is
  // the card's own height, without the shadow padding around it.
  function submenuTop(kind, bgH) {
    if (!root.screen) return 0;
    const pad = Zenon.menuShadowPad;
    const gap = Zenon.padScreen;
    const i = root.rowIndexOf(kind);
    let bgY = rootMenu.cardY + (i >= 0 ? rootMenu.rowY(i) : 0);
    if (bgY + bgH > root.screen.height - gap) bgY = root.screen.height - bgH - gap;
    if (bgY < gap) bgY = gap;
    return bgY - pad;
  }

  // ── WHAT ARTEMIS HAS LEARNED ──────────────────────────────────────────
  // The finder keeps a frecency map — path to how often you have opened it —
  // and it is the most useful list of paths on this machine. It lived behind
  // opening artemis and typing; here it is a submenu off the desktop.
  //
  // Read from artemis's own state file rather than asked for over IPC: there
  // is nothing to ask, the file IS the answer, and a menu that has to wait for
  // a round trip before it can draw its rows is a menu that flickers.
  FileView {
    id: artemisState
    path: Quickshell.statePath("artemis.json")
    blockLoading: true
    printErrors: false
  }

  readonly property var recentEntries: {
    let freq = ({});
    try {
      const j = JSON.parse(artemisState.text() || "{}");
      freq = j.freq || ({});
    } catch (e) {
      return [];
    }
    const keys = [];
    for (const k in freq) keys.push(k);
    // The same order artemis shows them in: most reached for first, and the
    // path itself breaking ties so the list does not shuffle between opens.
    keys.sort((a, b) => (freq[b] - freq[a]) || (a < b ? -1 : 1));
    const out = [];
    const cap = Oracle.menuRecentCount;
    for (let i = 0; i < keys.length && out.length < cap; ++i) {
      const p = keys[i];
      const bare = p.replace(/\/+$/, "");
      const cut = bare.lastIndexOf("/");
      out.push({ path: p, isDir: /\/$/.test(p),
                 text: cut < 0 ? bare : bare.slice(cut + 1) });
    }
    return out;
  }
  // ── the shell's own menu ─────────────────────────────────────────────
  // Restarting the panels used to sit at the bottom of the session list,
  // because that is where the "start something over" verbs were. It is not a
  // session action: ending a session and reloading a bar have nothing in
  // common but a vague sense of beginning again, and the SETTINGS — which
  // belong beside it — had no home in that list at all.
  //
  // Both are about this shell, so they are a menu about this shell. Neither
  // confirms: one opens a panel, and the other is over in a second with
  // nothing lost.
  // A new note comes first, then backgrounds. Backgrounds are the lightest
  // thing here — a panel that changes nothing on its own — and used to sit
  // out on the root menu among the PLACES, which is a list of things to
  // open, not a list of things to change. Still behind its own setting, which is why this is
  // built rather than written out.
  property var shellEntries: {
    const out = [];
    // A note is made from here because here is where you are when you want
    // one: the desktop, with nothing else open. It needs no panel of its own
    // — the note IS the panel.
    if (Oracle.menuShowNote)
      out.push({ id: "note", text: "New note", icon: "\uF24A",
                 cmd: "qs ipc call Clio add" });
    // And the wall of them put out of sight, or brought back — one row
    // saying whichever it will do, read off clio's own state. Only once
    // there is a note: hiding nothing is not a choice worth a row.
    if (Oracle.menuShowNote && Clio.count > 0)
      out.push({ id: "notes-shown",
                 text: Clio.shown ? "Hide notes" : "Show notes",
                 icon: Clio.shown ? "\uF070" : "\uF06E",
                 cmd: "qs ipc call Clio toggle" });
    if (Oracle.menuShowBackground)
      out.push({ id: "background", text: "Set background", icon: "\uF03E",
                 cmd: "qs ipc call Picasso toggle" });
    // Straight to oracle's Display section: a resolution or a rotation is
    // changed from the desktop it is about, not from a menu of the shell.
    if (Oracle.menuShowDisplay)
      out.push({ id: "display", text: "Display settings", icon: "\uF108",
                 cmd: "qs ipc call Oracle at display" });
    return out;
  }

  // ── AND THE TWO THAT ARE ABOUT THE SHELL ITSELF ───────────────────────
  // Set background and New note act on the desktop in front of you, so they
  // stay out on the root menu where a click reaches them. These two act on
  // the shell drawing that desktop — one opens its settings, the other
  // throws it away and starts it again — and that is a different subject
  // and a heavier one. Behind a door, where a mis-click cannot reach them.
  readonly property var shellOnlyEntries: [
    { id: "settings", text: "Settings", icon: "\uF013",
      cmd: "qs ipc call Oracle first" },
    // Through scripts/restart.sh, in a shell that has already been
    // detached — so the replacement is never a child of the instance it
    // replaces. It ends this instance with SIGTERM rather than `qs kill`
    // (whose clean exit crashes quickshell's teardown here, see the script),
    // waits for it to be gone, then relaunches with `-n -d`: `-n` still
    // declines if somehow a shell is left, rather than two fighting over the
    // same layer surfaces and state files.
    { id: "restart", text: "Reload Shell", icon: "\uF01E",
      cmd: Strings.shellQuote(Quickshell.shellDir) + "/scripts/restart.sh" }
  ]

  property var sessionEntries: [
    { id: "lockscreen", text: "Lock",  icon: "\uF023", cmd: "sleep 0.35 && qs ipc call Cerberus lock", confirm: false },
    { id: "logout",     text: "Logout",      icon: "\uF08B", cmd: "hyprshutdown -p " + Strings.shellQuote("loginctl terminate-session "
        + Strings.shellQuote(Quickshell.env("XDG_SESSION_ID") || "")), confirm: true },
    { id: "suspend",    text: "Suspend",     icon: "\uF186", cmd: "systemctl suspend", confirm: true },
    { id: "reboot",     text: "Reboot",      icon: "\uF021", cmd: "hyprshutdown -p 'systemctl reboot'", confirm: true },
    { id: "shutdown",   text: "Shutdown",    icon: "\uF011", cmd: "hyprshutdown -p 'systemctl poweroff'", confirm: true }
  ]

  // for grab
  readonly property var grabWindows: {
    const out = [rootMenu];
    if (appsMenu.visible) out.push(appsMenu);
    for (const c of root.homeCards) if (c && c.visible) out.push(c);
    if (ctxMenu.visible) out.push(ctxMenu);
    if (owMenu.visible) out.push(owMenu);
    if (sessionMenu.visible) out.push(sessionMenu);
    if (shellMenu.visible) out.push(shellMenu);
    if (trashMenu.visible) out.push(trashMenu);
    if (recentMenu.visible) out.push(recentMenu);
    if (confirmMenu.visible) out.push(confirmMenu);
    return out;
  }

  // ── ONE ICON FAMILY, AND WHY IT MATTERS ──────────────────────────────
  // Every glyph this menu writes for itself — these rows, the session list,
  // the shell list, the chevrons — comes from Nerd Fonts' Font Awesome
  // range, U+F000 to U+F2FF, and nothing else may be added from anywhere
  // else.
  //
  // THINGS ARE THE EXCEPTION. A file, a directory or an application wears the
  // glyph morpheus/icons.js gives it — the map terminus, artemis, cynosure
  // and plato read — so the same file looks the same here as in the file
  // manager, and an app the same as in the launcher. One map for things is
  // worth more than one family for this menu.
  //
  // This menu had collected four families: Font Awesome, Codicons (U+EAxx),
  // Material Design (U+F0xxx) and one bare Unicode power symbol. They are
  // drawn on different em squares, so at a single font.pixelSize they come
  // out at visibly different sizes — the Material ones oversized, the
  // Codicons small — and a column of icons that are meant to read as one
  // column instead reads as a ransom note. Nothing is wrong with any
  // individual glyph; the problem is only ever the mixture.
  //
  // centred model for root: files, recent, apps, home, trash, then this
  // shell — which is where backgrounds live now — and the session it is
  // running in.
  //
  // BUILT rather than written out, because three of these rows are switches in
  // oracle now. A literal list with `enabled: false` on a switched-off row
  // would still DRAW it — greyed out and unreachable, which reads as "this is
  // broken" where the truth is "you asked for it not to be here". So a row
  // that is off is not in the list at all, and the SEPARATORS are placed
  // around whatever survived rather than written between fixed rows:
  // switching off the last row of a group otherwise leaves a rule with
  // nothing under it.
  readonly property var rootModel: {
    const rows = [];
    const sep = () => {
      // never lead with a rule, and never two in a row
      if (rows.length === 0) return;
      if (rows[rows.length - 1].isSeparator) return;
      rows.push({ text: "", icon: "", hasChildren: false,
                  isSeparator: true, enabled: false });
    };

    // First, because it is the thing this menu is most often opened to reach.
    // No children: it opens a window, so there is no menu level to walk into.
    if (Oracle.menuShowFiles)
      rows.push({ text: "Files", icon: "\uF114", hasChildren: false,
                  kind: "terminus", isSeparator: false, enabled: true });
    // What artemis has learned you open. The finder ranks by how often you
    // reach for a thing, and that ranking is the most useful list of paths on
    // this machine — and it was reachable only by opening artemis and typing.
    // Muted when it has learned nothing yet, the way the trash is.
    if (Oracle.menuShowRecent)
      rows.push({ text: "Recent", icon: "\uF1DA", hasChildren: true,
                  kind: "recent", isSeparator: false,
                  enabled: root.recentEntries.length > 0 });
    sep();
    if (Oracle.menuShowApps)
      rows.push({ text: "Apps", icon: "\uF009", hasChildren: true,
                  kind: "apps", isSeparator: false, enabled: true });
    if (Oracle.menuShowHome)
      rows.push({ text: "Home", icon: "\uF46D", hasChildren: true,
                  kind: "file", isSeparator: false, enabled: true });
    // Muted when there is nothing in it — an empty trash is still worth
    // SEEING, so you know where it is and that it is empty, but there is
    // nothing to open and nothing to empty, and a row offering both would
    // be lying about what it can do.
    if (Oracle.menuShowTrash)
      rows.push({ text: root.trashCount > 0
                    ? "Trash (" + root.trashCount + ")" : "Trash",
                  icon: "\uF014", hasChildren: false, kind: "trash",
                  isSeparator: false, enabled: root.trashCount > 0 });
    sep();
    // ── THE SHELL'S OWN ENTRIES, ON THE MENU ITSELF ────────────────────
    // They were behind a "Shell" row that opened a card with four things in
    // it. A submenu earns its place by holding more than fits or more than
    // you want to read at once; this held a note, a background, the settings
    // and a restart — four leaves behind one door, each one a click further
    // away than it needed to be.
    //
    // Built from the same shellEntries the card was built from, so what is
    // offered and what it does are still written down once.
    for (let i = 0; i < root.shellEntries.length; ++i) {
      const e = root.shellEntries[i];
      rows.push({ text: e.text, icon: e.icon, hasChildren: false,
                  kind: "shellcmd", cmd: e.cmd,
                  isSeparator: false, enabled: true });
    }
    // A RULE OF ITS OWN. Everything above acts on this desktop — open a
    // thing, set a background, write a note. Below are the two subjects that
    // are about the machinery instead: the shell drawing the desktop, and
    // the session the whole lot runs in.
    sep();
    // With the machinery, below the rule: it manages the system the desktop
    // runs on rather than acting on the desktop itself.
    if (Oracle.menuShowPackages)
      rows.push({ text: "Package Manager", icon: "\uF487", hasChildren: false,
                  kind: "shellcmd", cmd: "qs ipc call Ceres window packages",
                  isSeparator: false, enabled: true });
    // The shell's own pair, behind their own door — see shellOnlyEntries.
    rows.push({ text: "Shell", icon: "\uF120", hasChildren: true,
                kind: "shell", isSeparator: false, enabled: true });
    rows.push({ text: "Session", icon: "\uF2C0", hasChildren: true,
                kind: "session", isSeparator: false, enabled: true });
    return rows;
  }

  function openAt(pos, clickedScreen) {
    // clickedScreen is the monitor where the right-click landed. The spec
    // says "on focused monitor" — the click focuses that monitor, so by the
    // time the handler fires focusedScreen === clickedScreen. Honour the
    // explicit screen to avoid a one-frame race where the binding hasn't
    // caught up yet.
    if (clickedScreen) root.screen = clickedScreen;
    root.anchorPos = pos;
    // Where it was left, for a few minutes; home otherwise.
    if (!Icarus.keepFolder(root.closedAt, Date.now(), Oracle.menuHomeRemember))
      root.homeReroot(Paths.home());
    root.pendingConfirmId = "";
    root.childMenu = "";
    // artemis writes this as you use it, so it is re-read on the way in
    artemisState.reload();
    root.shown = true;
    root.stopBranches("");
    root.refreshHome();
    refreshTrash();
  }

  // Where the pointer actually is, for the keybind path. The desktop catcher
  // hands over its own click point; opening from IPC had nothing to hand over
  // and used the middle of the screen — the one place a context menu should
  // never appear.
  //
  // hyprctl rather than a cursor property: quickshell's Hyprland module does
  // not expose one. A subprocess, but only on the open, and nothing is drawn
  // until the answer is back.
  function openAtCursor() {
    cursorProc.running = true;
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // "2186, 774", in hyprland's global logical space
        const m = String(text).trim().match(/(-?\d+)\s*,\s*(-?\d+)/);
        if (!m) {
          root.openAt(Qt.point(root.screen ? root.screen.width / 2 : 200,
                               root.screen ? root.screen.height / 2 : 200), root.screen);
          return;
        }
        const gx = parseInt(m[1], 10);
        const gy = parseInt(m[2], 10);
        // which monitor that global point is on, and where it sits inside it
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; ++i) {
          const sc = screens[i];
          if (gx >= sc.x && gx < sc.x + sc.width && gy >= sc.y && gy < sc.y + sc.height) {
            root.openAt(Qt.point(gx - sc.x, gy - sc.y), sc);
            return;
          }
        }
        root.openAt(Qt.point(gx, gy), root.screen);
      }
    }
  }

  function onAppChosen(entry) {
    if (!entry || !entry.id) return;
    // Desktop.launchCommand, for the Terminal=true entries gtk-launch drops on
    // the floor — and because quoting a shell argument by hand here was a
    // fourth copy of the function Strings exists to be.
    Quickshell.execDetached(["sh", "-c", Desktop.launchCommand(entry.id, "")]);
    root.closeAll();
  }

  function closeAll() {
    if (root.shown) root.closedAt = Date.now();
    root.shown = false;
    root.childMenu = "";
    root.pendingConfirmId = "";
    root.closeCtx();
  }

  function execCmd(cmd) {
    Quickshell.execDetached(["sh", "-c", cmd + " >/dev/null 2>&1 &"]);
  }

  // ── OPENING A FILE, AND ASKING WHEN NOTHING WILL ──────────────────────
  // Terminus' opener (Terminus.openOrAskCommand), so a file opens here with
  // what it opens with there. It used to be a detached gio open into
  // /dev/null, so a file nothing claims — an empty one, a stray binary — did
  // nothing when chosen. Now its exit is heard, and NO_HANDLER raises the
  // open-with card (owCard, below): the menu that was asked is already gone
  // by then, so the card stands in a window of its own.
  Component {
    id: openerProc
    Process {
      property string path: ""
      onExited: (code) => {
        if (code === Terminus.NO_HANDLER) owCard.ask(path);
        destroy();
      }
    }
  }

  function openFile(path) {
    const p = openerProc.createObject(root, {
      path: path, command: ["sh", "-c", Terminus.openOrAskCommand(path)]
    });
    if (p) p.running = true;
  }

  // ── THE CARD, FOR A FILE NOTHING OPENS ────────────────────────────────
  // Terminus' open-with card (terminus/OpenWithLayer.qml), floating in the
  // middle of the screen. Overlay, as every popup here is, and holding the
  // keyboard only while the card is up; the surface is mapped only then too.
  PanelWindow {
    id: owWindow
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "icarus-openwith"
    WlrLayershell.keyboardFocus: owCard.open ? WlrKeyboardFocus.Exclusive
                                             : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    screen: root.screen
    visible: owCard.active

    OpenWithLayer { id: owCard }
  }

  function refreshTrash() {
    root.trashArmed = false;
    trashProc.command = ["sh", "-c",
      "ls -A1 " + Strings.shellQuote(root.trashDir + "/files") + " 2>/dev/null | wc -l"];
    trashProc.running = true;
  }

  // ── WHAT A ROW OF THE ROOT MENU DOES ──────────────────────────────────
  // Lifted out of the row delegate when the card became a CardMenu. A branch
  // arms its hover timer and puts away whatever else was open; a target opens
  // nothing and closes the branches, because a row you are about to click is
  // not a row you are browsing past.
  function rowEntered(m) {
    if (!m) return;
    if (m.kind === "trash" || m.kind === "shellcmd") {
      root.stopBranches("");
      if (root.childMenu !== "trash") root.childMenu = "";
    } else if (m.kind === "apps") {
      root.stopBranches("apps");
      root.armBranch("apps");
    } else if (m.kind === "file") {
      root.stopBranches("file");
      root.armBranch("file");
    } else if (m.kind === "session") {
      root.stopBranches("session");
      root.armBranch("session");
    } else if (m.kind === "shell") {
      root.stopBranches("shell");
      root.armBranch("shell");
    } else if (m.kind === "recent") {
      root.stopBranches("recent");
      root.armBranch("recent");
    }    else if (m.kind === "terminus") {
      root.stopBranches("");
      root.childMenu = "";
    }
  }

  // The LEFT button's answer. CardMenu has already flashed the row by the
  // time this runs — the flash is its reply to the click, and the action is
  // what happens at the end of it — so nothing here fires one.
  function rowChosen(m) {
    if (!m) return;
    if (m.kind === "trash") { root.openTrash(); return; }
    if (m.kind === "shellcmd") {
      root.execCmd(m.cmd);
      root.closeAll();
      return;
    }
    if (m.kind === "apps")        root.childMenu = "apps";
    else if (m.kind === "file")   root.childMenu = "file";
    else if (m.kind === "session") root.childMenu = "session";
    else if (m.kind === "shell")  root.childMenu = "shell";
    else if (m.kind === "recent") root.childMenu = "recent";
    else if (m.kind === "terminus") {
      // Reveal, not navigate — see revealTerminus.
      root.revealTerminus();
      root.closeAll();
    }
  }

  function openTrash() {
    // TERMINUS, not whatever xdg-open hands a directory to. Every other place
    // icarus opens — a recent directory, a browsed one — goes to terminus, and
    // the trash is a directory like any other.
    root.openInTerminus(root.trashDir + "/files");
    root.closeAll();
  }

  // Both halves: the files themselves and the .trashinfo records pointing at
  // them. Deleting only one leaves a trash no file manager agrees about.
  function emptyTrash() {
    const files = Strings.shellQuote(root.trashDir + "/files");
    const info = Strings.shellQuote(root.trashDir + "/info");
    // Every entry, by find rather than by glob: `.[!.]*` skipped names that
    // start with two dots ("..foo"), which then sat in a trash reported empty.
    root.execCmd("find " + files + " " + info
      + " -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null; true");
    root.trashCount = 0;
    root.closeAll();
  }

  Process {
    id: trashProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.trashCount = parseInt(String(text).trim(), 10) || 0
    }
  }

  // A SECOND WINDOW IF ONE IS ALREADY UP. `open` reuses window 0, which is
  // right when terminus is put away and wrong when it is on screen — asking
  // for a file manager while looking at one means you want another, not that
  // one navigated out from under you. `windows` reports each window's state,
  // so the shell picks between the two verbs.
  // ── WHAT SUPER+E DOES, AND NOTHING ELSE ──────────────────────────────
  // The Files entry used to hand Terminus the desktop's current directory.
  // That is a destination, so the window always arrived somewhere instead
  // of coming back where you left it — and openInTerminus spawns a second
  // window when one is already up, so "Files" kept making new ones.
  //
  // SUPER+E sends no path at all, and the manager treats that as a reveal
  // rather than a navigation: a hidden window is still where it was. This
  // is the same call, so the two entry points cannot drift.
  //
  // openInTerminus below keeps taking a path, because its other callers —
  // the trash, and a directory you picked out of the browser — are asking
  // for somewhere specific.
  function revealTerminus() {
    root.execCmd("qs ipc call Terminus spawn ''");
  }

  function openInTerminus(where) {
    const q = Strings.shellQuote(where);
    root.execCmd(
      "if qs ipc call Terminus windows 2>/dev/null | grep -q ' shown '; "
      + "then qs ipc call Terminus spawn " + q + "; "
      + "else qs ipc call Terminus open " + q + "; fi");
  }

  // ══ THE HOME CARDS ═════════════════════════════════════════════════════
  // See HomeCard.qml for what one card is. Everything that happens BETWEEN
  // them lives here: the stack, the one selection, the keyboard, and the
  // verbs a row can be asked for.

  // ── the stack ─────────────────────────────────────────────────────────
  // The Instantiator below makes one card per entry of this model. A JS array
  // as its model would rebuild every card on every change — the base card
  // blinking each time a directory opened beside it — while a ListModel grows
  // and shrinks at the end, so only the card that came or went is touched.
  // Only its count means anything; homeTrail is what the cards read.
  ListModel { id: homeModel }

  // Cards are ADDED at once and REMOVED after their fade: a card cut off the
  // stack sees no entry of its own, fades where it stands, and only then
  // goes — see "leaving is a state" in HomeCard. One opened again at the same
  // level before that is simply the leaving card, given its new entry.
  function setTrail(t) {
    root.homeTrail = t;
    while (homeModel.count < t.length) homeModel.append({ n: 0 });
    if (homeModel.count > t.length) homeSweep.restart();
  }

  Timer {
    id: homeSweep
    interval: Zenon.menuFade + 60
    onTriggered: {
      while (homeModel.count > Math.max(1, root.homeTrail.length))
        homeModel.remove(homeModel.count - 1);
    }
  }
  Component.onCompleted: root.setTrail(root.homeTrail)

  function openChild(level, index, dir) {
    root.setTrail(root.homeTrail.slice(0, level + 1).concat([{ dir: dir, from: index }]));
  }

  // The base card walks somewhere: a crumb, a directory clicked, Backspace.
  // Everything beside it closes, because it hung off rows that are gone.
  function homeReroot(dir, fromKeys) {
    const d = String(dir || "/");
    homeTimer.stop();
    root.closeCtx();
    root.cwd = d;
    root.setTrail([{ dir: d, from: -1 }]);
    if (fromKeys) root.enterHomeKeys(0);
    else { root.selLevel = -1; root.selIndex = -1; root.selWantFirst = false; }
  }

  function homeFolderGone(dir) {
    if (dir !== Paths.home()) root.homeReroot(Paths.home(), root.selLevel >= 0);
  }

  function homeCrumbs(dir) { return Terminus.crumbs(dir, Paths.home()); }

  function refreshHome() {
    for (const c of root.homeCards) if (c) c.refresh();
    root.refreshPlaces();
    terminusView.reload();
  }

  // Put away with the branch: coming back to Home starts at the base card.
  onChildMenuChanged: {
    if (root.childMenu === "file") return;
    homeTimer.stop();
    root.closeCtx();
    root.selLevel = -1;
    root.selIndex = -1;
    if (root.homeTrail.length > 1) root.setTrail(root.homeTrail.slice(0, 1));
  }

  // ── the pointer ───────────────────────────────────────────────────────
  // A directory opens beside its card after the same pause every branch here
  // waits; a file closes whatever was open beside it, after the same pause,
  // so the pointer crossing a file on its way to an open card does not shut
  // it. Entering the next card restarts the timer with that card's answer,
  // which is what cancels the one the crossing armed.
  Timer {
    id: homeTimer
    interval: root.branchDelay
    property var act: null
    onTriggered: if (homeTimer.act) homeTimer.act();
  }

  function homeHovered(c, i) {
    // a right-click menu is open: the cards behind it hold still — and a card
    // fading out is not there to be pointed at
    if (root.ctxOpen || !c.alive) return;
    root.selLevel = c.level;
    root.selIndex = i;
    root.selWantFirst = false;
    const r = c.rows[i];
    const next = root.homeTrail[c.level + 1];
    if (c.isBranch(i)) {
      if (next && next.from === i && next.dir === r.path) { homeTimer.stop(); return; }
      homeTimer.act = () => root.openChild(c.level, i, r.path);
    } else {
      if (!next) { homeTimer.stop(); return; }
      homeTimer.act = () => root.setTrail(root.homeTrail.slice(0, c.level + 1));
    }
    homeTimer.restart();
  }

  function homeUnhovered(c, i) {
    if (root.ctxOpen || !c.alive) return;
    if (root.selLevel === c.level && root.selIndex === i) root.selIndex = -1;
  }

  // Left walks into a directory or opens a file, middle hands either to terminus
  // or its opener, right asks about it. Right on a note row asks nothing.
  function homeClicked(c, i, button, pt) {
    if (root.ctxOpen) { root.closeCtx(); return; }
    if (!c.alive) return;
    const r = c.rows[i];
    if (!r || !c.selectable(i)) return;
    if (button === Qt.RightButton) {
      if (r.kind === "entry" || r.kind === "place") root.openCtx(c, i, r, pt);
      return;
    }
    const act = root.homeAction(r, button === Qt.MiddleButton, false);
    if (act) c.flashRow(i, act);
  }

  // What choosing a row does. Walking into a directory happens at once and
  // returns nothing — the card stays up and redraws, it is not an event this
  // menu has finished with. Anything that ends the menu comes back as a
  // function, to run at the end of the row's flash.
  function homeAction(r, middle, fromKeys) {
    if (r.kind === "more")
      return () => { root.openInTerminus(r.path); root.closeAll(); };
    const isDir = r.kind === "place" || r.isDir;
    if (isDir && middle)
      return () => { root.openInTerminus(r.path); root.closeAll(); };
    if (isDir) { root.homeReroot(r.path, fromKeys); return null; }
    return () => { root.openFile(r.path); root.closeAll(); };
  }

  // ── the keyboard ──────────────────────────────────────────────────────
  // The root menu's window is the one that holds the keyboard — the cards
  // are not focusable, and a focus grab moving between five windows would
  // lose keys in the handover — so its key handler hands them here.
  function enterHomeKeys(level) {
    root.selLevel = level;
    root.selIndex = -1;
    root.selWantFirst = true;
    const c = root.homeCards[level];
    if (c) root.homeRowsArrived(c);
  }

  // A card walked into by the keyboard selects its first row — once the rows
  // it is showing are the directory's own and not the last directory's.
  function homeRowsArrived(c) {
    if (!root.selWantFirst || root.selLevel !== c.level || c.shownDir !== c.dir) return;
    const i = c.firstSelectable();
    if (i < 0) return;
    root.selIndex = i;
    root.selWantFirst = false;
    c.ensureVisible(i);
  }

  property string typed: ""
  Timer { id: typedTimer; interval: 900; onTriggered: root.typed = "" }

  function onKey(e) {
    if (root.ctxOpen) return root.ctxKey(e);
    if (root.childMenu === "file" && root.selLevel >= 0) return root.homeKey(e);
    const k = e.key;
    if (k === Qt.Key_Escape) { root.closeAll(); return true; }
    if (k === Qt.Key_Right || (k === Qt.Key_Down && root.childMenu === "file")) {
      if (root.childMenu === "" || root.childMenu === "file") {
        root.childMenu = "file";
        root.enterHomeKeys(0);
      }
      return true;
    }
    if (k === Qt.Key_Left) { root.childMenu = ""; return true; }
    return false;
  }

  function homeKey(e) {
    const c = root.homeCards[root.selLevel];
    if (!c) return false;
    const k = e.key;
    const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
    const alt = (e.modifiers & Qt.AltModifier) !== 0;
    const cur = root.selIndex;
    const r = cur >= 0 ? c.rows[cur] : null;

    // Moving off the row whose card is open beside this one closes that card,
    // as it would under the pointer.
    const move = (i) => {
      if (i < 0) return;
      root.selIndex = i;
      root.selWantFirst = false;
      c.ensureVisible(i);
      const next = root.homeTrail[c.level + 1];
      if (next && next.from !== i) root.setTrail(root.homeTrail.slice(0, c.level + 1));
    };
    const askAbout = () => {
      if (!r || (r.kind !== "entry" && r.kind !== "place")) return;
      root.openCtx(c, cur, r, Qt.point(c.cardX + 48, c.rowScreenTop(cur) + Zenon.menuRowHeight));
    };

    switch (k) {
    case Qt.Key_Escape: root.closeAll(); return true;
    case Qt.Key_Down: move(cur < 0 ? c.firstSelectable() : c.nextSelectable(cur, 1)); return true;
    case Qt.Key_Up: move(cur < 0 ? c.lastSelectable() : c.nextSelectable(cur, -1)); return true;
    case Qt.Key_PageDown: move(c.nextSelectable(Math.max(cur, 0), c.pageRows)); return true;
    case Qt.Key_PageUp: move(c.nextSelectable(Math.max(cur, 0), -c.pageRows)); return true;
    case Qt.Key_Home: move(c.firstSelectable()); return true;
    case Qt.Key_End: move(c.lastSelectable()); return true;
    case Qt.Key_Right:
      if (c.isBranch(cur)) {
        homeTimer.stop();
        root.openChild(c.level, cur, r.path);
        root.enterHomeKeys(c.level + 1);
      }
      return true;
    case Qt.Key_Left:
      homeTimer.stop();
      if (c.level > 0) {
        const back = root.homeTrail[c.level].from;
        root.setTrail(root.homeTrail.slice(0, c.level));
        root.selLevel = c.level - 1;
        root.selIndex = back;
      } else {
        // off the base card and back onto the root menu
        root.childMenu = "";
      }
      return true;
    case Qt.Key_Return:
    case Qt.Key_Enter:
      if (r && c.selectable(cur)) {
        const act = root.homeAction(r, alt, true);
        if (act) c.flashRow(cur, act);
      }
      return true;
    case Qt.Key_Backspace:
      root.homeReroot(Icarus.dirname(root.cwd), true);
      return true;
    case Qt.Key_Menu:
      askAbout();
      return true;
    }
    if (k === Qt.Key_F10 && (e.modifiers & Qt.ShiftModifier)) { askAbout(); return true; }
    // Ctrl+H, as every file manager spells "hidden files"
    if (ctrl && k === Qt.Key_H) {
      Oracle.set("menuShowHidden", !Oracle.menuShowHidden);
      return true;
    }
    // ── typing a name jumps to it ───────────────────────────────────────
    if (!ctrl && !alt && e.text.length === 1 && e.text >= " "
        && !(e.text === " " && root.typed === "")) {
      root.typed += e.text;
      typedTimer.restart();
      const names = c.rows.map((x, i) => (x.kind === "entry" || x.kind === "place") ? x.name : null);
      const i = Icarus.typeAhead(names, root.typed, cur);
      if (i >= 0) move(i);
      return true;
    }
    return false;
  }

  // ── places ────────────────────────────────────────────────────────────
  // terminus' bookmarks, read from its own file rather than asked for — the
  // same reasoning as artemisState above. Pinned in terminus is pinned here.
  FileView {
    id: bookmarkFile
    path: Quickshell.statePath("terminus-bookmarks")
    blockLoading: true
    printErrors: false
    onLoaded: {
      if (JSON.stringify(root.marksIn(bookmarkFile.text()))
          !== JSON.stringify(root.placeMarks)) root.probePlaces();
    }
  }

  property var placeUser: []
  property var placeMarks: []
  // which of those exist, asked once per open — a bookmark to a drive that
  // is not plugged in is a place that goes nowhere
  property var placesThere: []

  // reload() is asynchronous even with blockLoading, so what text() says
  // straight after it is the LAST read — a bookmark pinned in terminus only
  // showed up on the open after next. The places are worked out now from what
  // is known, and again when the fresh read lands if it says anything new.
  function refreshPlaces() {
    bookmarkFile.reload();
    root.probePlaces();
  }

  function marksIn(text) {
    return String(text || "").split("\n").map((l) => l.trim()).filter((l) => l !== "");
  }

  function probePlaces() {
    if (placesProc.running) { placesProc.again = true; return; }
    root.placeUser = [UserDirs.desktop, UserDirs.documents, UserDirs.downloads,
                      UserDirs.music, UserDirs.pictures, UserDirs.videos];
    root.placeMarks = root.marksIn(bookmarkFile.text());
    placesProc.command = Icarus.existingDirsArgv(
      [Paths.home()].concat(root.placeUser, root.placeMarks));
    placesProc.running = true;
  }

  Process {
    id: placesProc
    property bool again: false
    onExited: if (placesProc.again) { placesProc.again = false; root.probePlaces(); }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.placesThere = Icarus.parseExisting(text)
    }
  }

  readonly property var placeRows: {
    const there = ({});
    for (const p of root.placesThere) there[String(p).replace(/\/+$/, "")] = true;
    const ok = (p) => there[String(p).replace(/\/+$/, "")] === true;
    const home = Paths.home();
    return Icarus.places(ok(home) ? home : "", root.placeUser.filter(ok),
                         root.placeMarks.filter(ok), root.cwd)
      .map((p) => ({
        label: p.label, path: p.path,
        // Home wears the root menu's Home glyph; the rest, the shared map's
        glyph: p.path === home ? ""
          : Icons.glyphFor({ name: Icarus.basename(p.path), isDir: true })
      }));
  }

  // ── the right-click menu ──────────────────────────────────────────────
  // What terminus would offer for the same row, the handful that make sense
  // from a menu: open it, open it with something else, hand it to terminus or
  // a shell, copy it, trash it. The header asks about the directory itself.
  property bool ctxOpen: false
  property var ctxRows: []
  // { level, index, path, isDir, header }
  property var ctxTarget: null
  property point ctxAt: Qt.point(0, 0)
  property int ctxSel: -1

  function isCtxRow(level, i) {
    return root.ctxOpen && !!root.ctxTarget && !root.ctxTarget.header
      && root.ctxTarget.level === level && root.ctxTarget.index === i;
  }

  function openCtx(c, i, r, pt) {
    const isDir = r.kind === "place" || r.isDir;
    const rows = [];
    if (isDir) {
      rows.push({ text: "Open here", icon: "", act: "reroot" });
      rows.push({ text: "Open in Terminus", icon: "", act: "terminus" });
      rows.push({ text: "Open terminal here", icon: "", act: "shell" });
    } else {
      rows.push({ text: "Open", icon: "", act: "open" });
      rows.push({ text: "Open with", icon: "", act: "openwith",
                  hasChildren: true, asks: true });
    }
    rows.push({ isSeparator: true });
    rows.push({ text: "Copy path", icon: "", act: "copypath" });
    if (r.kind === "entry") {
      rows.push({ text: "Copy", icon: "", act: "copy" });
      rows.push({ isSeparator: true });
      rows.push({ text: "Move to trash", icon: "", act: "trash" });
    }
    root.showCtx({ level: c.level, index: i, path: r.path, isDir: isDir, header: false },
                 rows, pt);
  }

  function homeHeaderMenu(c, pt) {
    root.showCtx({ level: c.level, index: -1, path: c.dir, isDir: true, header: true }, [
      { text: "Open in Terminus", icon: "", act: "terminus" },
      { text: "Open terminal here", icon: "", act: "shell" },
      { text: "Copy path", icon: "", act: "copypath" },
      { isSeparator: true },
      { text: "Show hidden files", icon: "", act: "hidden",
        mark: Oracle.menuShowHidden }
    ], pt);
  }

  function showCtx(target, rows, pt) {
    homeTimer.stop();
    root.ctxTarget = target;
    root.ctxRows = rows;
    root.ctxAt = pt;
    root.ctxSel = -1;
    root.owOpen = false;
    root.owSel = -1;
    root.ctxOpen = true;
  }

  function closeCtx() {
    root.ctxOpen = false;
    root.owOpen = false;
    root.ctxSel = -1;
    root.owSel = -1;
  }

  // terminus' own "open shell here" setting, so both open the same terminal
  FileView {
    id: terminusView
    path: Quickshell.statePath("terminus-view.json")
    blockLoading: true
    printErrors: false
  }
  function termCmd() {
    try {
      const j = JSON.parse(terminusView.text() || "{}");
      return typeof j.termCmd === "string" ? j.termCmd : "";
    } catch (e) {
      return "";
    }
  }

  function ctxDo(act) {
    const t = root.ctxTarget;
    if (!t) return;
    if (act === "reroot") { root.homeReroot(t.path, root.selLevel >= 0); return; }
    if (act === "openwith") { root.openOw(); return; }
    if (act === "trash") { root.trashHomePath(t); root.closeCtx(); return; }
    if (act === "hidden") {
      Oracle.set("menuShowHidden", !Oracle.menuShowHidden);
      root.closeCtx();
      return;
    }
    if (act === "terminus") root.openInTerminus(t.path);
    else if (act === "shell")
      Quickshell.execDetached(["sh", "-c", Terminus.shellCommand(t.path, root.termCmd())]);
    else if (act === "open") root.openFile(t.path);
    else if (act === "copypath")
      Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "icarus", t.path]);
    else if (act === "copy")
      Quickshell.execDetached(Terminus.shArgv(Terminus.clipboardCopyCommand([t.path], false)));
    root.closeAll();
  }

  // Through gio, as terminus trashes — see its trashCommand for why not by
  // hand. The card the row was in is listed again when it is done, and the
  // Trash row's count with it.
  // Queued, not refused: a second "Move to trash" while the first was still
  // out used to be dropped without a word, and the file simply stayed.
  function trashHomePath(t) {
    const next = root.homeTrail[t.level + 1];
    if (next && next.from === t.index) root.setTrail(root.homeTrail.slice(0, t.level + 1));
    homeTrashProc.queue = homeTrashProc.queue.concat([{ path: t.path, level: t.level }]);
    root.drainHomeTrash();
  }

  function drainHomeTrash() {
    if (homeTrashProc.running || homeTrashProc.queue.length === 0) return;
    const job = homeTrashProc.queue[0];
    homeTrashProc.queue = homeTrashProc.queue.slice(1);
    homeTrashProc.level = job.level;
    homeTrashProc.command = Terminus.shArgv(Terminus.trashCommand([job.path]));
    homeTrashProc.running = true;
  }

  Process {
    id: homeTrashProc
    property int level: 0
    property var queue: []
    onExited: {
      const c = root.homeCards[homeTrashProc.level];
      if (c) c.refresh();
      root.refreshTrash();
      root.drainHomeTrash();
    }
  }

  // ── open with ─────────────────────────────────────────────────────────
  // terminus' own question — gio's type, then what is registered for it —
  // so the list here is the list there, and the default is ticked.
  property bool owOpen: false
  property int owSel: -1
  property var owApps: []
  property string owDefault: ""
  property bool owLoading: false
  property string owFor: ""
  property string owAsked: ""

  function owRowIndex() {
    for (let i = 0; i < root.ctxRows.length; ++i)
      if (root.ctxRows[i].act === "openwith") return i;
    return -1;
  }

  function openOw() {
    const t = root.ctxTarget;
    if (!t || t.isDir) return;
    root.owOpen = true;
    if (root.owFor === t.path && !root.owLoading) return;
    root.owFor = t.path;
    root.owApps = [];
    root.owLoading = true;
    root.askOw();
  }

  function askOw() {
    if (owProc.running) return;   // onRunningChanged asks again
    root.owAsked = root.owFor;
    owProc.command = ["sh", "-c", Terminus.appsCommand(root.owFor)];
    owProc.running = true;
  }

  Process {
    id: owProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.owAsked !== root.owFor) return;
        const seen = ({});
        root.owApps = Terminus.parseApps(text).filter((a) => {
          if (seen[a.id]) return false;
          seen[a.id] = true;
          return true;
        });
        root.owDefault = Terminus.parseAppsDefault(text);
        root.owLoading = false;
      }
    }
    onRunningChanged: if (!owProc.running && root.owAsked !== root.owFor) root.askOw();
  }

  readonly property var owRows: root.owLoading
    ? [{ text: "Looking…", enabled: false }]
    : (root.owApps.length === 0
      ? [{ text: "No applications", enabled: false }]
      : root.owApps.map((a) => ({
          text: a.name, icon: Icons.appGlyph([a.id, a.name]),
          mark: a.id === root.owDefault
        })))

  function owChoose(i) {
    const a = root.owApps[i];
    const t = root.ctxTarget;
    if (!a || !t) return;
    Quickshell.execDetached(["sh", "-c", Terminus.openWithCommand(a.id, t.path)]);
    root.closeAll();
  }

  // The keyboard inside the right-click menu and the list beside it. The
  // cards' own `activeIndex` is the selection, so the pointer and the keys
  // light the same row.
  function ctxKey(e) {
    const k = e.key;
    const inOw = root.owOpen && root.owSel >= 0;
    const list = inOw ? root.owRows : root.ctxRows;
    const cur = inOw ? root.owSel : root.ctxSel;
    const ok = (i) => !!list[i] && !list[i].isSeparator && list[i].enabled !== false;
    const step = (from, d) => {
      for (let i = from + d; i >= 0 && i < list.length; i += d) if (ok(i)) return i;
      return cur;
    };
    const set = (i) => {
      if (inOw) { root.owSel = i; return; }
      root.ctxSel = i;
      if (!(list[i] && list[i].act === "openwith")) root.owOpen = false;
    };
    const intoOw = () => { root.openOw(); root.owSel = 0; };

    switch (k) {
    case Qt.Key_Escape:
      if (inOw) { root.owSel = -1; root.owOpen = false; }
      else root.closeCtx();
      return true;
    case Qt.Key_Down: set(step(cur < 0 ? -1 : cur, 1)); return true;
    case Qt.Key_Up: set(step(cur < 0 ? list.length : cur, -1)); return true;
    case Qt.Key_Right:
      if (!inOw && list[cur] && list[cur].act === "openwith") intoOw();
      return true;
    case Qt.Key_Left:
      if (inOw) { root.owSel = -1; root.owOpen = false; }
      return true;
    case Qt.Key_Return:
    case Qt.Key_Enter:
      if (inOw) root.owChoose(cur);
      else if (ok(cur)) {
        if (list[cur].act === "openwith") intoOw();
        else root.ctxDo(list[cur].act);
      }
      return true;
    }
    return true;
  }

  function onSessionChosen(entry) {
    if (!entry) return;
    if (entry.confirm) {
      root.pendingConfirmId = entry.id;
      // keep session menu open, show confirm as its child
      return;
    }
    root.execCmd(entry.cmd);
    root.closeAll();
  }

  // Every branch row opens its own submenu and closes the other four. That was
  // five copies of the same four stop() calls, one of which had to be edited
  // each time a branch was added — and adding Shell would have made it six
  // copies of five. One list, named by the branch that is being kept.
  // ── OPENING A BRANCH ON HOVER ─────────────────────────────────────────
  // A submenu that opened the instant the pointer crossed its row would
  // flicker open and shut all the way down a menu. It waits instead, and the
  // wait is cancelled by moving onto anything else.
  //
  // ONE timer. There were five, identical but for the kind they opened, and
  // every caller had to remember to stop the other four.
  readonly property int branchDelay: 140
  property string pendingBranch: ""

  Timer {
    id: branchTimer
    interval: root.branchDelay
    onTriggered: if (root.pendingBranch !== "") root.childMenu = root.pendingBranch;
  }

  function armBranch(kind) {
    root.pendingBranch = kind;
    branchTimer.restart();
  }

  function stopBranches(keep) {
    if (root.pendingBranch !== keep) {
      root.pendingBranch = "";
      branchTimer.stop();
    }
  }

  function sessionEntryById(id) {
    for (let i = 0; i < root.sessionEntries.length; ++i)
      if (root.sessionEntries[i].id === id) return root.sessionEntries[i];
    return null;
  }

  // ── autofit + directional placement helpers ──────────────────────────
  function availBelow(anchor, screenH, pad) { return Math.max(0, screenH - anchor - pad); }
  function availAbove(anchor, pad) { return Math.max(0, anchor - pad); }
  function chooseY(anchor, bgH, screenH, pad) {
    const below = availBelow(anchor, screenH, pad);
    const above = availAbove(anchor, pad);
    if (bgH <= below) return anchor;
    if (bgH <= above) return anchor - bgH;
    // not enough space either side — clamp to screen and reduce height elsewhere
    return Math.max(pad, Math.min(anchor, screenH - bgH - pad));
  }
  function chooseX(anchor, bgW, screenW, pad) {
    const right = Math.max(0, screenW - anchor - pad);
    const left = Math.max(0, anchor - pad);
    if (bgW <= right) return anchor;
    if (bgW <= left) return anchor - bgW;
    return Math.max(pad, Math.min(anchor, screenW - bgW - pad));
  }


  // ── WHAT A DRAG IS CARRYING ─────────────────────────────────────────
  // Off screen and never seen directly: it exists to be photographed. The
  // labels are filled in, the picture is taken, and the drag carries the
  // photograph — the same card terminus and artemis put beside the cursor.
  //
  // Without it a drag out of here was an invisible one: the menu is gone the
  // moment you drop, and between picking a row up and letting go there was
  // nothing on screen saying which row it was.
  property string dragLabel: ""
  property string dragGlyph: ""
  property color dragInk: Zenon.white
  // The grab result is HELD, not discarded. It owns the image the compositor
  // is still reading from; let it go and the drag can end up carrying nothing.
  property var dragGrab: null

  // A failed grab is not a reason to refuse the drag; it just goes without a
  // picture, which is what it did before there was one.
  function dragPicture(label, glyph, ink, then) {
    root.dragLabel = label;
    root.dragGlyph = glyph;
    root.dragInk = ink;
    if (!dragCard.grabToImage(function(res) { root.dragGrab = res; then(res.url); }))
      then("");
  }

  // The row flash lives in ChosenFlash.qml now: the Home cards are their own
  // file and flash the same way.

  // ── root menu ────────────────────────────────────────────────────────
  CardMenu {
    id: rootMenu
    screen: root.screen
    model: root.rootModel
    cardWidth: Zenon.menuWidth
    open: root.shown

    // OPENED AT THE POINTER, so it flips around it rather than clamping: a
    // menu near an edge should open the other way, not slide across the
    // cursor that asked for it. chooseX/chooseY are icarus' own and know
    // about the space above and below; CardMenu is handed the answer.
    at: {
      if (!root.screen) return Qt.point(0, 0);
      const gap = Zenon.padScreen;
      return Qt.point(
        root.chooseX(root.anchorPos.x, Zenon.menuWidth, root.screen.width, gap),
        root.chooseY(root.anchorPos.y, rootMenu.contentH, root.screen.height, gap));
    }

    // The branch whose card is open stays lit while you are inside it. This
    // was six `kind === ... && childMenu === ...` clauses spelled out.
    activeIndex: {
      if (!root.childMenu) return -1;
      for (let i = 0; i < root.rootModel.length; ++i)
        if (root.rootModel[i].kind === root.childMenu) return i;
      return -1;
    }

    onHovered: i => root.rowEntered(root.rootModel[i])
    onChosen: i => root.rowChosen(root.rootModel[i])
    // The trash row is the one with two answers: its card on the right
    // button, the directory itself on the left.
    onSecondary: i => {
      const m = root.rootModel[i];
      if (!m || m.kind !== "trash") return;
      root.trashArmed = false;
      root.childMenu = "trash";
    }

    HyprlandFocusGrab {
      windows: root.grabWindows
      active: root.shown
      onCleared: root.closeAll()
    }

    Item {
      id: rootMenuContent
      anchors.fill: parent
      focus: true
      // every key goes through onKey — the Home cards and their right-click
      // menu are not focusable, so this window reads the keyboard for them
      Keys.onPressed: (e) => { if (root.onKey(e)) e.accepted = true; }
    }

    Item {
      id: dragCard
      opacity: 0
      z: -100
      x: -4000
      height: 38

      // SIZED FROM THE TEXT rather than from a laid-out row, and anchored
      // rather than positioned, because grabToImage reads the width in the
      // same tick the labels are filled in — a Row would not have set its own
      // width yet, and the first drag of every session would carry a card cut
      // to a few pixels.
      readonly property real pad: 12
      width: dragCard.pad * 2 + dragCardGlyph.implicitWidth
        + (root.dragGlyph !== "" ? 8 : 0) + dragCardLabel.implicitWidth

      Rectangle {
        anchors.fill: parent
        radius: Zenon.menuRadius
        color: Zenon.layerBg
        border.width: 1
        border.color: Zenon.border
      }

      Text {
        id: dragCardGlyph
        anchors.left: parent.left
        anchors.leftMargin: dragCard.pad
        anchors.verticalCenter: parent.verticalCenter
        text: root.dragGlyph
        color: root.dragInk
        font.family: Zenon.faceFixed
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(16)
      }

      Text {
        id: dragCardLabel
        anchors.left: dragCardGlyph.right
        anchors.leftMargin: root.dragGlyph !== "" ? 8 : 0
        anchors.verticalCenter: parent.verticalCenter
        text: root.dragLabel
        color: Zenon.white
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
    }
  }

  // ── trash context menu ──────────────────────────────────────────
  // The trash's own menu, on right-click. Placed against the trash ROW rather
  // than the pointer, the way every other submenu here is placed against the
  // row it belongs to.
  CardMenu {
    id: trashMenu
    screen: root.screen
    cardWidth: 180
    open: root.shown && root.childMenu === "trash"
    hinged: true
    flipFrom: rootMenu.margins.left + Zenon.menuShadowPad + Zenon.menuWidth
    flipParentLeft: rootMenu.margins.left + Zenon.menuShadowPad
    at: Qt.point(0, root.submenuTop("trash", trashMenu.contentH)
                    + Zenon.menuShadowPad)

    // Emptying cannot be undone, so the row arms on the first click and acts
    // on the second. `danger` turns it red while it is armed — arming is not
    // an event, so it does not flash; the row going red is the reply.
    model: [
      { text: "Open" },
      { text: "Empty Trash", danger: root.trashArmed, asks: !root.trashArmed }
    ]

    onChosen: index => {
      if (index === 0) { root.openTrash(); return; }
      if (!root.trashArmed) { root.trashArmed = true; return; }
      root.emptyTrash();
    }
    // moving off the armed row disarms it, so it cannot sit primed waiting
    // for a stray click later
    onUnhovered: index => { if (index === 1) root.trashArmed = false; }
  }

  // ── artemis's recent paths ──────────────────────────────────────
  // The finder's own ranking, as a submenu. Same shape as the trash menu it
  // sits below — placed against its row, closing the whole stack when
  // something is chosen — because a submenu that behaves differently from the
  // one above it is a second thing to learn.
  CardMenu {
    id: recentMenu
    screen: root.screen
    cardWidth: 300
    open: root.shown && root.childMenu === "recent"
    // recentEntries carry a path and a name but no glyph — so they are given
    // the shared map's (morpheus/icons.js), the one terminus draws the same
    // place with.
    model: root.recentEntries.map(e => ({
      text: e.text, icon: Icons.glyphFor({ name: e.text, isDir: e.isDir })
    }))
    hinged: true
    flipFrom: rootMenu.margins.left + Zenon.menuShadowPad + Zenon.menuWidth
    flipParentLeft: rootMenu.margins.left + Zenon.menuShadowPad
    at: Qt.point(0, root.submenuTop("recent", recentMenu.contentH)
                    + Zenon.menuShadowPad)

    onChosen: index => {
      const e = root.recentEntries[index];
      if (!e) return;
      if (e.isDir) root.openInTerminus(e.path);
      else root.openFile(e.path);
      root.closeAll();
    }
  }

  // ── apps submenu ────────────────────────────────────────────────
  PanelWindow {
    // OVERLAY, like every other popup this shell puts up. These eight set no
    // layer at all, which left the desktop menu on Top while the pill's
    // panels sat on Overlay above it — a menu opened over a panel went
    // behind it. Within a layer the last surface mapped is the top one, and
    // a menu maps when you open it, so this puts it where it belongs.
    WlrLayershell.layer: WlrLayer.Overlay
    id: appsMenu
    property bool wanted: root.shown && root.childMenu === "apps"
    property real shade: 0
    onWantedChanged: appsMenu.shade = appsMenu.wanted ? 1 : 0
    Behavior on shade {
      NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
    }
    visible: appsMenu.wanted || appsMenu.shade > 0.01
    focusable: false
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // THE CARD'S RECTANGLE, NOT THE CARD. It arrives scaled up from
    // Zenon.menuScaleFrom, and a Region following an ITEM re-reads it only when
    // its geometry changes — never when its scale does. So the mask could be
    // left at the arrival's 94%, and the bottom rows of a long menu sat outside
    // it: a click on them went through to the desktop, the focus grab took it
    // as a click away, and the menu closed without its row ever flashing.
    mask: Region { x: appsBg.x; y: appsBg.y; width: appsBg.width; height: appsBg.height }
    anchors { top: true; left: true }
    screen: root.screen
    implicitWidth: 300 + Zenon.menuShadowPad * 2
    implicitHeight: {
      if (!root.screen) return 300 + Zenon.menuShadowPad * 2;
      const maxBgH = root.screen.height - Zenon.menuShadowPad * 2;
      return Math.min(appsContent.implicitHeight + 8, maxBgH) + Zenon.menuShadowPad * 2;
    }

    margins.left: {
      if (!root.screen || !rootMenu.visible) return 0;
      return Math.round(Zenon.hingeX(
        rootMenu.cardX, Zenon.menuWidth, 300,
        root.screen.width, Zenon.padScreen)) - Zenon.menuShadowPad;
    }
    margins.top: root.submenuTop("apps",
      appsMenu.implicitHeight - Zenon.menuShadowPad * 2)

    ClippingRectangle {
      id: appsBg
      anchors.fill: parent
      anchors.margins: Zenon.menuShadowPad
      transformOrigin: Item.TopLeft
      scale: Zenon.menuScale(appsMenu.shade)
      opacity: appsMenu.shade
      color: Zenon.frostBg   // quick look's ground — see Zenon.frostBg
      border.color: Zenon.border
      border.width: 1
      radius: Zenon.menuRadius
      topLeftRadius: 0
      topRightRadius: Zenon.menuRadius
      bottomLeftRadius: 0
      bottomRightRadius: Zenon.menuRadius

      Column {
        id: appsContent
        anchors.fill: parent
        anchors.margins: Zenon.menuCardPad
        spacing: 0

        // ── the scroll, and why it is an overlay ──────────────────────
        // A WheelHandler declared inside a Flickable NEVER FIRES. Flickable's
        // default property parents non-Item children to contentItem as a plain
        // QObject, so the handler is registered on no item at all and is never
        // offered an event — verified with a logging handler inside the very
        // view the wheel was visibly scrolling, which logged nothing while a
        // console.log elsewhere logged fine. The 5.6x speed this asked for had
        // therefore never once applied; what you felt was Qt's built-in wheel
        // step, and the code saying otherwise sat here looking correct.
        //
        // A MouseArea over the view does get them. NoButton is what makes it
        // safe to lay over everything: it never takes a press, so clicking and
        // hovering the rows underneath are untouched.
        //
        // The wrapper exists because the MouseArea cannot be a CHILD of the
        // Flickable for the same reason the handler failed — anything Item
        // shaped goes into contentItem and scrolls away with the content.
        Item {
          width: parent.width
          height: {
            if (!root.screen) return Math.min(500, appsRepeaterHolder.childrenRect.height);
            const maxH = root.screen.height - Zenon.menuShadowPad * 2 - 12;
            return Math.min(appsRepeaterHolder.childrenRect.height, Math.max(120, maxH - 6));
          }

        Flickable {
          id: appsFlick
          // Finder's rubber band and the smooth wheel notch, one rule for
          // the whole shell — see morpheus/Elastic.qml. Inside the view
          // rather than over it: it pins itself to the viewport.
          ElasticScroll { view: appsFlick }
          anchors.fill: parent
          clip: false
          contentWidth: width
          contentHeight: appsRepeaterHolder.childrenRect.height
          boundsBehavior: Flickable.StopAtBounds
          flickDeceleration: 1800
          maximumFlickVelocity: 2800

          Column {
            id: appsRepeaterHolder
            width: parent.width
            spacing: 0

            Repeater {
              id: appsRepeater
              // sorted and deduplicated — see Icarus.appRows
              model: Icarus.appRows(DesktopEntries.applications.values, Icons.appGlyph)

              delegate: Item {
                id: appEntry
                required property var modelData
                required property int index
                width: appsRepeaterHolder.width
                height: Zenon.menuRowHeight

                Rectangle {
                  anchors.fill: parent
                  radius: 0
                  color: appHover.containsMouse ? Zenon.border : "transparent"
                }

                Item {
                  anchors.fill: parent
                  anchors.leftMargin: 12
                  anchors.rightMargin: 10

                  // THE APP'S OWN GLYPH, from the map cynosure uses, so an
                  // application looks the same here as in the launcher. The
                  // column is kept even for one the map does not know, so
                  // the names stay in one line down the menu.
                  Text {
                    id: appGlyph
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    text: appEntry.modelData.glyph
                    color: Zenon.white
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(15)
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Text {
                    id: appLabel
                    anchors.left: appGlyph.right
                    anchors.leftMargin: Zenon.menuIconGap
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignLeft
                    text: appEntry.modelData.name
                    elide: Text.ElideRight
                    color: Zenon.white
                    font.family: Zenon.face
                    font.weight: Font.Medium
                    font.pixelSize: Zenon.px(16)
                  }
                }

                ChosenFlash { id: appFlash }

                MouseArea {
                  id: appHover
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !appFlash.running
                  onClicked: appFlash.fire(() => root.onAppChosen(appEntry.modelData.entry))
                }
              }
            }
          }
        }

        }
      }
    }

    MenuShadow {
      panel: appsBg
      opacity: appsMenu.shade
      transformOrigin: Item.TopLeft
      scale: appsBg.scale
    }
  }

  // ── the Home cards ────────────────────────────────────────────────
  // One HomeCard per entry of homeTrail — see HomeCard.qml and "THE HOME
  // CARDS" above.
  Instantiator {
    id: homeInst
    model: homeModel
    delegate: HomeCard {
      required property int index
      owner: root
      level: index
      parentCard: index === 0 ? rootMenu : (root.homeCards[index - 1] || null)
    }
    onObjectAdded: (i, o) => {
      const a = root.homeCards.slice();
      a[i] = o;
      root.homeCards = a;
    }
    onObjectRemoved: (i, o) => {
      root.homeCards = root.homeCards.filter((x) => x !== o);
    }
  }

  // ── a Home row's own menu ─────────────────────────────────────────────
  // At the pointer rather than hinged: it is a question about one row of a
  // card, and the card's side is already taken by the directory beside it.
  CardMenu {
    id: ctxMenu
    screen: root.screen
    model: root.ctxRows
    cardWidth: 190
    fit: true
    open: root.shown && root.ctxOpen
    at: root.ctxAt
    activeIndex: root.owOpen ? root.owRowIndex() : root.ctxSel
    onHovered: i => {
      root.ctxSel = i;
      const r = root.ctxRows[i];
      if (r && r.act === "openwith") root.openOw();
      else root.owOpen = false;
    }
    onChosen: i => {
      const r = root.ctxRows[i];
      if (r) root.ctxDo(r.act);
    }
  }

  CardMenu {
    id: owMenu
    screen: root.screen
    model: root.owRows
    cardWidth: 190
    fit: true
    open: root.shown && root.ctxOpen && root.owOpen
    hinged: true
    flipFrom: ctxMenu.cardX + ctxMenu.cardW
    flipParentLeft: ctxMenu.cardX
    at: Qt.point(0, ctxMenu.cardY + ctxMenu.rowY(Math.max(0, root.owRowIndex())))
    activeIndex: root.owSel
    onHovered: i => root.owSel = i
    onChosen: i => root.owChoose(i)
  }

  // ── session submenu ───────────────────────────────────────────────
  CardMenu {
    id: sessionMenu
    screen: root.screen
    cardWidth: Zenon.menuWidth
    open: root.shown && root.childMenu === "session"
    hinged: true
    flipFrom: rootMenu.margins.left + Zenon.menuShadowPad + Zenon.menuWidth
    flipParentLeft: rootMenu.margins.left + Zenon.menuShadowPad
    at: Qt.point(0, root.submenuTop("session", sessionMenu.contentH)
                    + Zenon.menuShadowPad)

    // The ones that ask first carry `asks`, so they open their card and flash
    // nothing: the question is the reply. They also carry `hasChildren`, for
    // the chevron — a row that opens something has to say so, and with no
    // flash either there would be nothing at all to connect the card that
    // appears to the row it came from.
    model: root.sessionEntries.map(e => ({
      text: e.text, icon: e.icon,
      asks: e.confirm || false, hasChildren: e.confirm || false
    }))

    // The row whose confirm card is up stays lit, the way every branch row in
    // icarus and terminus does.
    activeIndex: {
      if (!root.pendingConfirmId) return -1;
      for (let i = 0; i < root.sessionEntries.length; ++i)
        if (root.sessionEntries[i].id === root.pendingConfirmId) return i;
      return -1;
    }

    onChosen: index => {
      const e = root.sessionEntries[index];
      if (!e) return;
      if (e.confirm) { root.pendingConfirmId = e.id; return; }
      root.onSessionChosen(e);
    }
  }

  // ── shell submenu ─────────────────────────────────────────────────
  // The settings, and putting the panels back. Placed against its own ROW
  // rather than at a fixed offset down the root menu, the way the trash menu
  // is: rows above it come and go with the switches in oracle, so an offset
  // measured in row heights would be wrong the moment one of them went.
  CardMenu {
    id: shellMenu
    screen: root.screen
    model: root.shellOnlyEntries
    cardWidth: 200
    open: root.shown && root.childMenu === "shell"

    // Hinged off the root menu: to its right where there is room, to its left
    // otherwise, squaring whichever corner ends up against it.
    hinged: true
    flipFrom: rootMenu.margins.left + Zenon.menuShadowPad + Zenon.menuWidth
    flipParentLeft: rootMenu.margins.left + Zenon.menuShadowPad

    // Against its own ROW rather than a fixed offset down the root menu: the
    // rows above it come and go with the switches in oracle, so an offset
    // measured in row heights would be wrong the moment one of them went.
    at: Qt.point(0, root.submenuTop("shell", shellMenu.contentH)
                    + Zenon.menuShadowPad)

    onChosen: index => {
      const e = root.shellOnlyEntries[index];
      if (!e) return;
      root.execCmd(e.cmd);
      root.closeAll();
    }
  }

  // ── confirm submenu (tertiary, to the right of session) ──────────
  PanelWindow {
    // OVERLAY, like every other popup this shell puts up. These eight set no
    // layer at all, which left the desktop menu on Top while the pill's
    // panels sat on Overlay above it — a menu opened over a panel went
    // behind it. Within a layer the last surface mapped is the top one, and
    // a menu maps when you open it, so this puts it where it belongs.
    WlrLayershell.layer: WlrLayer.Overlay
    id: confirmMenu
    property bool wanted: root.shown && root.childMenu === "session" && root.pendingConfirmId !== ""
    property real shade: 0
    onWantedChanged: confirmMenu.shade = confirmMenu.wanted ? 1 : 0
    Behavior on shade {
      NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
    }
    visible: confirmMenu.wanted || confirmMenu.shade > 0.01
    focusable: false
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // THE CARD'S RECTANGLE, NOT THE CARD. It arrives scaled up from
    // Zenon.menuScaleFrom, and a Region following an ITEM re-reads it only when
    // its geometry changes — never when its scale does. So the mask could be
    // left at the arrival's 94%, and the bottom rows of a long menu sat outside
    // it: a click on them went through to the desktop, the focus grab took it
    // as a click away, and the menu closed without its row ever flashing.
    mask: Region { x: confirmBg.x; y: confirmBg.y; width: confirmBg.width; height: confirmBg.height }
    anchors { top: true; left: true }
    screen: root.screen
    implicitWidth: 160 + Zenon.menuShadowPad * 2
    implicitHeight: {
      if (!root.screen) return 160 + Zenon.menuShadowPad * 2;
      const maxBgH = root.screen.height - Zenon.menuShadowPad * 2;
      return Math.min(confirmContent.implicitHeight + 8, maxBgH) + Zenon.menuShadowPad * 2;
    }

    property var pendingEntry: root.sessionEntryById(root.pendingConfirmId)

    margins.left: {
      if (!root.screen || !sessionMenu.visible) return 0;
      return Math.round(Zenon.hingeX(
        sessionMenu.cardX, sessionMenu.cardWidth, 160,
        root.screen.width, Zenon.padScreen)) - Zenon.menuShadowPad;
    }
    margins.top: {
      if (!root.screen || !sessionMenu.visible) return 0;
      const pad = Zenon.menuShadowPad;
      const parentBgY = sessionMenu.margins.top + pad;
      // the session card's own rows, not numbers that match them today
      let idx = -1;
      for (let i = 0; i < root.sessionEntries.length; ++i) if (root.sessionEntries[i].id === root.pendingConfirmId) { idx = i; break; }
      const rowH = Zenon.menuRowHeight;
      const bgH = confirmMenu.implicitHeight - pad * 2;
      let bgY = parentBgY + Zenon.menuCardPad + idx * rowH;
      if (bgY + bgH > root.screen.height - pad) bgY = root.screen.height - bgH - pad;
      if (bgY < pad) bgY = pad;
      return bgY - pad;
    }

    ClippingRectangle {
      id: confirmBg
      anchors.fill: parent
      anchors.margins: Zenon.menuShadowPad
      transformOrigin: Item.TopLeft
      scale: Zenon.menuScale(confirmMenu.shade)
      opacity: confirmMenu.shade
      color: Zenon.menuBg
      border.color: Zenon.border
      border.width: 1
      radius: Zenon.menuRadius
      topLeftRadius: 0
      topRightRadius: Zenon.menuRadius
      bottomLeftRadius: 0
      bottomRightRadius: Zenon.menuRadius

      Column {
        id: confirmContent
        anchors.fill: parent
        anchors.margins: Zenon.menuCardPad
        spacing: 0

        Item {
          width: parent.width
          height: Zenon.menuRowHeight
          Rectangle {
            anchors.fill: parent
            radius: 0
            color: confirmHover.containsMouse ? Zenon.border : "transparent"
          }
          Text {
            id: confirmLabel
            anchors.centerIn: parent
            text: " Confirm"
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Font.Medium
            font.pixelSize: Zenon.px(16)
          }
          ChosenFlash { id: confirmFlash }

          MouseArea {
            id: confirmHover
            anchors.fill: parent
            hoverEnabled: true
            enabled: !confirmFlash.running
            onClicked: confirmFlash.fire(() => {
              const e = confirmMenu.pendingEntry;
              if (e) root.execCmd(e.cmd);
              root.closeAll();
            })
          }
        }

        Item {
          width: parent.width
          height: Zenon.menuRowHeight
          Rectangle {
            anchors.fill: parent
            radius: 0
            color: cancelHover.containsMouse ? Zenon.headBg : "transparent"
          }
          Text {
            id: cancelLabel
            anchors.centerIn: parent
            text: " Cancel"
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Font.Medium
            font.pixelSize: Zenon.px(16)
          }
          ChosenFlash { id: cancelFlash }

          MouseArea {
            id: cancelHover
            anchors.fill: parent
            hoverEnabled: true
            enabled: !cancelFlash.running
            onClicked: cancelFlash.fire(() => root.pendingConfirmId = "")
          }
        }
      }
    }

    MenuShadow {
      panel: confirmBg
      opacity: confirmMenu.shade
      transformOrigin: Item.TopLeft
      scale: confirmBg.scale
    }
  }

  // clicking outside root but inside screen should also be caught by grab;
  // fallback transparent catcher when no menu child
  // (grab handles it — no extra MouseArea needed)

  IpcHandler {
    target: "Icarus"
    function toggle(): void { if (root.shown) root.closeAll(); else root.openAtCursor(); }
    function openAt(x: int, y: int): void { root.openAt(Qt.point(x, y), root.screen); }
    function hide(): void { root.closeAll(); }
  }
}
