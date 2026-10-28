// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One plato window: an editor, its status line, and the nvim behind them.
//
// A CLOSED WINDOW IS GONE. Not hidden and kept for next time, the way
// terminus keeps window 0: closing it tells its nvim to quit, and the window
// destroys itself. When the last one goes, PlatoManager lets go of the
// component too, and nothing of plato is left running.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../morpheus"
import "../terminus"
import "core"
import "editor"
import "editor/actions.js" as Actions
import "../morpheus/icons.js" as Icons
import "../morpheus/hypr.js" as Hypr
import "../ceres"
import "../delphi/delphi.js" as D

FloatingWindow {
  id: win

  // A fixed title, for the window rules: `plato` is what hyprland matches on.
  // The file being edited is in the status line instead.
  title: win.capture ? "plato-capture" : "plato"
  // CLEAR, and the ground laid by `groundLeft`/`groundBelow` around the
  // tab strip, whose tabs paint their own — an inactive tab is thinner glass
  // than the window (user, 2026-10-09, as terminus)
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: win.capture ? 760 : 1100
  implicitHeight: win.capture ? 460 : 800
  minimumSize: Qt.size(480, 240)

  property var mgr: null
  property string sessionId: ""
  // rebuilt after a reload: the nvim is already running, find it again
  property bool reconnect: false
  // a file to open once nvim is listening
  property string openPath: ""
  // (a path handed in at creation sets no change signal off)
  onOpenPathChanged: if (win.openPath !== "") win.noteOpening()
  // QUICK CAPTURE (PlatoManager.capture): a small window on one note, the
  // cursor at its end, no tree; whatever is typed is saved when it loses
  // focus, and the note's directory is made if it is not there
  property bool capture: false
  // and any more asked for before it was
  property var _later: []

  // A FILE IS ON ITS WAY: sent to nvim, not yet in a frame. The frames
  // before it are of the empty buffer every engine starts on, and the start
  // card came up for them and faded out again — a flash of the home tab on
  // every file opened from terminus or artemis. Until the file's frame
  // lands (or a moment passes: a file that cannot be opened), no card.
  property bool opening: false
  Timer { id: openingCeiling; interval: 1500; onTriggered: win.opening = false }
  function noteOpening() { win.opening = true; openingCeiling.restart(); }
  Connections {
    target: st
    function onFileChanged() { if (st.file !== "") { win.opening = false; openingCeiling.stop(); } }
  }

  function openFile(path) {
    // opened from outside (terminus, artemis, `plato f`): the tree goes there
    sidebar.follow(path, false);
    win.noteOpening();
    if (nvim.ready) nvim.open(path);
    else if (win.openPath === "") win.openPath = path;
    else win._later.push(path);
  }

  // the files open here, as nvim names them ("~/…"), and whether that list
  // can be believed yet — for `plato --wait` (PlatoManager.holding)
  readonly property var openPaths: st.buffers.map((b) => b.path).filter((p) => p !== "")
  readonly property bool settled: nvim.ready && st.buffersKnown

  // Once, whichever way the window goes. `quit` is false when nvim has
  // already gone on its own (`:q`), since there is no one left to tell.
  property bool _done: false
  function finish(quit) {
    if (win._done) return;
    win._done = true;
    if (quit) nvim.quit();
    if (win.mgr) win.mgr.forget(win);
    win.visible = false;
    Qt.callLater(() => win.destroy());
  }

  // CLOSED BY THE COMPOSITOR (super+q) is reported here, with the surface
  // already gone — there is nothing left to ask "save changes?" on. The
  // bridge keeps any unsaved buffer in plato's rescue directory and says so in
  // a notification, rather than losing it.
  onClosed: win.finish(true)

  EditorState {
    id: st
    // until nvim's own highlight groups arrive, the theme's — core keeps
    // dark-theme literals (it imports nothing), which flashed a pale
    // text on a light theme's first frame (2026-10-20). nvim's first
    // colors replace these bindings for good.
    normalFg: Zenon.ink
    cursorLineBg: Zenon.wash(0.06)
    lineNrFg: Zenon.muted
    cursorLineNrFg: Zenon.sand
    visualInk: Zenon.magenta
    // the settings' "Current line number color", one of zenon's
    numberHere: {
      const k = win.settings ? win.settings.lineNumberInk : "white";
      const ink = Zenon[k];
      return ink !== undefined ? ink : Zenon.white;
    }
  }

  // ── the settings that are nvim's to apply ──────────────────────────
  // core/Settings.qml's editing settings, all sent when nvim is first
  // reached (or reached again after a reload) and again on any change; see
  // editing.lua's options().
  readonly property var settings: win.mgr ? win.mgr.settings : null
  function pushOptions() {
    const s = win.settings;
    if (!s) return;
    nvim.options({
      wrap: s.wrap, relativeNumbers: s.relativeNumbers, tabWidth: s.tabWidth,
      expandTab: s.expandTab, scrollOff: s.scrollOff, smartCase: s.smartCase,
      completeAsYouType: s.completeAsYouType, cmdlineAsYouType: s.cmdlineAsYouType,
      trimOnSave: s.trimOnSave, formatOnSave: s.formatOnSave, editFlash: s.editFlash,
      gitBlame: s.gitBlame, stickyScroll: s.stickyScroll, reopenTabs: s.reopenTabs,
      zen: win.zen, minimap: s.minimap,
      typewriter: win.zen && s.typewriter, indentGuides: s.indentGuides,
      largeFileMB: s.largeFileMB, rainbowBrackets: s.rainbowBrackets,
      suggestParsers: s.suggestParsers,
      suggestTools: s.suggestTools,
      markdown: {
        render: s.mdRender, rawLine: s.mdRawLine, headings: s.mdHeadings, inline: s.mdInline,
        lists: s.mdLists, code: s.mdCode, tables: s.mdTables, quotes: s.mdQuotes, rules: s.mdRules,
      },
    });
  }

  // ── ZEN MODE ───────────────────────────────────────────────────────
  // Space z: the tree, the tabs and the status line put away, the text in a
  // centered column (the settings' "Zen mode text width"), and everything
  // but the cursor's paragraph faded back (nvim says which lines that is:
  // view.lua's `para`). Per window, and not kept: it is a mood, not a
  // setting. Esc does not leave it; Space z does.
  property bool zen: false

  // ── MARKDOWN, AS IT READS (user, 2026-10-27) ──────────────────────────
  // Beside a Markdown file, the page as delphi's notes reader draws it —
  // pictures and videos included, which the text's own rendering
  // (markdown.lua) cannot show. Space M; only for Markdown, never in zen.
  // The text is asked for while it is up (bridge `text`), and comes back
  // only when the buffer changed.
  property bool mdPreview: false
  readonly property bool previewShown: win.mdPreview && st.filetype === "markdown" && !win.zen
  property string mdText: ""
  property string mdBase: ""
  property var mdAt: ({ buf: -1, tick: -1 })
  Timer {
    interval: 350
    repeat: true
    triggeredOnStart: true
    running: win.previewShown && win.visible
    onTriggered: nvim.request("text", { buf: win.mdAt.buf, tick: win.mdAt.tick }, (r) => {
      if (!r || r.same) return;
      win.mdAt = { buf: r.buf, tick: r.tick };
      win.mdText = String(r.text || "");
      const f = String(r.file || "");
      win.mdBase = f.lastIndexOf("/") > 0 ? f.slice(0, f.lastIndexOf("/")) : "";
    })
  }
  onZenChanged: { win.pushOptions(); zenSlide.restart(); }

  // ── SAVED WHEN YOU LOOK AWAY ───────────────────────────────────────
  // With the setting on, every modified file with a name is written as the
  // window loses focus (silently: a new buffer has nowhere to go).
  readonly property bool focused: editor.Window.active
  // ── WHICH WINDOW IS WHICH, TO HYPRLAND ────────────────────────────
  // Every plato window is titled "plato" (the window rules match on it), so
  // a focus by title picked any of them. Each notes its own address while it
  // has the focus, and files opened from outside go to the plato window
  // used last and focus that one (PlatoManager.open).
  property string hyprAddress: ""
  function noteAddress() {
    const t = Hyprland.activeToplevel;
    if (!win.focused || !t || t.title !== win.title) return;
    const a = String(t.address || "").replace(/^0x/, "");
    if (a !== "") win.hyprAddress = "0x" + a;
  }
  Connections {
    target: Hyprland
    function onActiveToplevelChanged() { win.noteAddress(); }
  }
  function raise() {
    const sel = win.hyprAddress !== "" ? "address:" + win.hyprAddress : "title:^(" + win.title + ")$";
    Hyprland.dispatch(Hypr.focusWindow(sel));
  }
  onFocusedChanged: {
    if (win.focused) {
      win.noteAddress();
      if (win.mgr) win.mgr.noteFocus(win);
    }
    if (!win.focused && win.settings && (win.settings.saveOnBlur || win.capture) && nvim.ready)
      nvim.cmd("silent! wall");
    // back from another window: did anything change on disk meanwhile?
    // (disk.lua asks about it)
    if (win.focused && nvim.ready) nvim.cmd("silent! checktime");
  }
  Connections {
    target: win.settings
    function onRevisionChanged() { if (nvim.ready) win.pushOptions(); }
  }

  // ── THE SHELL'S THEME, FOR NVIM'S COLORS ──────────────────────────
  // The text is colored by nvim's highlight groups (theme.lua), which
  // are Zenon's own palette. Under another theme nvim is sent the resolved
  // colors — Zenon has already filled in any slot the theme left out —
  // and rebuilds its groups; null is Zenon itself, so Zenon's bright_
  // variants stay exactly as palette.lua has them. Hex without alpha:
  // nvim's colors have none.
  readonly property var themeMsg: Zenon.nvimTheme()
  function pushTheme() { nvim.request("theme", win.themeMsg || {}); }
  // once the theme has settled (Zenon.themeEpoch): a Follow Background
  // crossfade is several steps, and nvim rebuilding its groups on each was
  // a stutter for colors nobody would see
  Connections { target: Zenon; function onThemeEpochChanged() { if (nvim.ready) win.pushTheme(); } }

  // :w (or the leader's Save) on a buffer with no file: terminus' save
  // dialog, then :saveas — and :quit after, for :wq
  function saveAs(quit) {
    win.ctx.choose(win.ctx.here(), true, (paths) => {
      if (!paths.length) return;
      nvim.cmd(Actions.saveAsCmd(paths[0]));
      if (quit) nvim.cmd("quit");
    });
  }

  NvimClient {
    id: nvim
    sessionId: win.sessionId
    spawn: !win.reconnect
    onHello: {
      win.pushOptions();
      win.pushTheme();
      if (win.capture && win.openPath !== "") {
        nvim.openAt(win.openPath);
        nvim.cmd("normal! G$");
      } else if (win.openPath !== "") {
        nvim.open(win.openPath);
        // a new window's first file: the tree goes there, as openFile's do
        sidebar.follow(win.openPath, false);
      }
      for (const p of win._later) nvim.open(p);
      win.openPath = "";
      win._later = [];
    }
    onView: (ev) => st.applyView(ev)
    onKeysSent: (keys) => st.keysSent(keys)
    onTheme: (ev) => st.applyTheme(ev)
    onPum: (ev) => st.applyPum(ev)
    onPumSelect: (i) => st.pumSelected = i
    onCmdline: (ev) => st.applyCmdline(ev)
    onCmdlinePos: (pos) => st.cmdlinePos = pos
    onMessage: (ev) => toasts.take(ev)
    onAsk: (ev) => toasts.takeAsk(ev)
    onUnask: (n) => toasts.unask(n)
    onSpellSuggest: (ev) => win.spellMenu(ev)
    onFlash: (ev) => editor.flash(ev)
    onMinimap: (ev) => st.applyMinimap(ev)
    onReferences: (items) => picker.openRefs(items)
    onSaveAsWanted: (quit) => win.saveAs(quit)
    onBuildParsers: (langs) => win.buildParsers(langs)
    // a language's missing tools, asked for in a card (suggest.lua)
    onInstallWanted: (pkgs, why) => {
      // installed: the servers turned on again (plugins.lsp) and the file
      // read again, so the new ones attach, format and check it
      const asked = Ceres.install(pkgs, why, (ok) => {
        if (ok) nvim.cmd("lua require('plato.plugins').lsp() | silent! edit");
      });
      if (!asked) toasts.take({ kind: "wmsg", text: "Ceres is busy — ask again when it is done" });
    }
    // `:q` in the editor quits nvim, and a window with no nvim is no editor
    onExited: win.finish(false)
  }

  // the editor's text, zoomed per tab; the chrome's, not — see PlatoManager.
  // A tab is its file, or its buffer when it has none.
  readonly property string tabKey: {
    if (st.file !== "") return st.file;
    const t = st.tabs.find((b) => b.current);
    return t ? "buf:" + t.id : "";
  }
  readonly property int fontSize: win.mgr ? (win.mgr.zooms, win.mgr.sizeFor(win.tabKey)) : 17
  readonly property int chromeSize: win.mgr ? win.mgr.chromeSize : Zenon.px(16)

  // ── the file tree ──────────────────────────────────────────────────
  // morpheus' FileTree, which is terminus' tree standing on its own. Shown
  // and sized the same in every window (PlatoManager keeps both).
  //
  // ROOTED AT HOME, ALWAYS. It used to follow the current file's project,
  // and opening a file from the tree narrowed the tree to that one project —
  // a hard focus a tree view has no need for: it is already a tree, the
  // file is revealed (its directories opened, the cursor on it) wherever it
  // is, and the rest of home stays a click away. A file outside home is
  // simply not in it. (The picker and grep still work per project: nvim's
  // `root`, asked for when they open.)
  readonly property string treeRoot: Quickshell.env("HOME")
  readonly property bool treeShown: win.mgr && !win.capture ? win.mgr.treeShown : false
  function toggleTree() {
    if (!win.mgr) return;
    // hidden: show it and go there; shown but elsewhere: go there;
    // shown and in it: put it away
    if (!win.mgr.treeShown) {
      win.mgr.setTree(true);
      sidebar.forceActiveFocus();
    } else if (!sidebar.activeFocus) {
      sidebar.forceActiveFocus();
    } else {
      win.mgr.setTree(false);
      editor.forceActiveFocus();
    }
  }

  // ── the tree slides out, and the window makes room for it ─────────
  // The tree keeps its full width inside a box whose width animates, so it
  // is uncovered rather than squeezed. A tree shown or hidden in the window
  // you are using (a floating one) grows or shrinks the WINDOW by the tree's
  // width, so the editor keeps its size rather than being pushed inward
  // (see SideRoom, below).
  readonly property real treeTarget: !win.mgr ? 300
    : win.mgr.liveTreeWidth > 0 ? win.mgr.liveTreeWidth : win.mgr.treeWidth
  Item {
    id: sidebarBox
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    clip: true
    visible: width > 0.5
    // while Hyprland resizes the window for it, the tree is whatever the
    // window has gained (SideRoom); otherwise it slides on its own
    width: room.keepW >= 0 ? Math.max(0, Math.min(win.treeTarget, win.width - room.keepW))
      : win.treeShown && !win.zen ? win.treeTarget : 0
    Behavior on width {
      // a drag of the edge follows the pointer, not an easing; nor does a
      // tree that is following the window's own resize (room.following)
      enabled: (!win.mgr || win.mgr.liveTreeWidth < 0) && !room.following
      NumberAnimation { id: treeSlide; duration: Zenon.normal * 2; easing.type: Zenon.travelEase }
    }

    // the sheet's veil, as terminus' sidebar and every strip wear it
    // (user, 2026-10-13: terminus' sheet frost "in tabs and sidebars")
    Rectangle {
      anchors.fill: parent
      color: Zenon.ground
      opacity: 0.6
    }

    FileTree {
      id: sidebar
      // fading with the slide: faint while it is barely out, whole once it is
      opacity: Math.pow(Math.min(1, sidebarBox.width / Math.max(1, win.treeTarget)), 1.5)
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: win.treeTarget
      // its band of buttons along the bottom, in line with the status line
      // and in the tree's own color
      toolbar: true
      toolbarBottom: true
      toolbarColor: "transparent"
      toolbarHeight: status.height
      hideable: true
      // | put it away, as | brought it out
      hideKey: "|"
      memory: win.mgr ? win.mgr.treeMemory : null
      showHidden: win.settings ? win.settings.treeHidden : true
      onShowHiddenChanged: if (win.settings) win.settings.set("treeHidden", sidebar.showHidden)
      onHideRequested: { if (win.mgr) win.mgr.setTree(false); editor.forceActiveFocus(); }
      // kept while the tree slides away, so it does not empty as it goes
      rootPath: win.treeRoot
      currentPath: st.file.replace(/^~/, Quickshell.env("HOME"))
      // a pixel larger than it was (user, 2026-10-08): the chrome's own size
      fontSize: win.chromeSize
      // its bar's glyphs as big as the status line's beside it: the tree
      // toggle and the root marker (StatusBar's iconSize), four pixels under
      // the quarter-larger rule (user, 2026-10-08: too big, twice), then
      // the toggle's own size (2026-10-09, a third time)
      toolbarGlyphSize: win.chromeSize - 1
      window: win
      onFileActivated: (p) => { nvim.openAt(p); editor.forceActiveFocus(); }
      onDismissed: editor.forceActiveFocus()
      onPathChanged: (from, to) => nvim.request("renamed", { from: from, to: to })
      // Properties on the menu and alt+return: terminus' card (PropsSheet)
      props: true
      onPropsWanted: (p) => propsSheet.showPath(p)
      // plato's own verbs on the tree's menu, after Open
      extraItems: [
        { text: "Open in a split", icon: "\u{F0E4F}", hint: "ctrl w v", when: "file",
          run: (p) => { nvim.cmd("lua vim.cmd.vsplit(" + JSON.stringify(p) + ")"); editor.forceActiveFocus(); } },
        { text: "Open below", icon: "\u{F0E4E}", hint: "ctrl w s", when: "file",
          run: (p) => { nvim.cmd("lua vim.cmd.split(" + JSON.stringify(p) + ")"); editor.forceActiveFocus(); } },
        { text: "Search in here", icon: "\u{F0349}",
          run: (p, isDir) => picker.openGrepIn(isDir ? p : p.slice(0, p.lastIndexOf("/"))) },
      ]
    }
  }

  // ── THE WINDOW MAKES ROOM FOR ITS TREE (terminus/SideRoom) ────────────
  // Showing the tree in a floating window widens it by the tree, as far as
  // the monitor allows, and hiding it gives exactly that back, from the left
  // edge so the editor holds still. Tiled, fullscreen or maximized, the
  // layout owns the size and the tree just slides. While Hyprland resizes,
  // the editor keeps its width (room.keepW) and the tree is what the window
  // has gained, one animation rather than two (the text used to shake).
  //
  // Only the window the toggle happened in: the tree is shown or hidden in
  // every plato window at once (oracle's setting), and the others keep their
  // size and make room inside.
  SideRoom {
    id: room
    window: win
    anchor: editor
    shown: win.treeShown
    want: win.treeTarget
    box: sidebarBox
    edge: "left"
    minW: 480
  }

  // the tree's edge: terminus/SeamGrip — a hairline, cyan under the pointer,
  // a handle to drag it wider or narrower, measured in the window's content.
  // A DRAG INTO THE TREE MUST STAY A DRAG (its rows carry DragHandlers and
  // its list is a Flickable): the grip does not let them take the pointer.
  SeamGrip {
    visible: sidebarBox.visible
    // over the editor, which overlaps the handle's right half
    z: 10
    frame: win.contentItem
    at: sidebarBox.x + sidebarBox.width
    min: 180
    max: Math.max(180, Math.min(700, win.width * 0.5))
    onMoved: (p) => { if (win.mgr) win.mgr.dragTree(p); }
    onReleased: if (win.mgr) win.mgr.dropTree()
  }

  // ── THE GROUND, less the tab strip (see the window's color) ──────
  // the tree's: an inactive tab's thinner glass, not the window's (user,
  // 2026-10-10, as terminus' sidebar and alexandria's)
  Rectangle {
    id: groundLeft
    z: -1
    width: tabs.x
    height: parent.height
    color: tabs.awayGlass
  }
  Rectangle {
    id: groundBelow
    z: -1
    x: tabs.x
    // not under the sticky lines' bar, which wears the active tab's glass
    // (see WindowView's sticky): laid twice, it came out darker
    y: tabs.height + stickyHost.band
    width: parent.width - x
    height: parent.height - y
    color: Zenon.layerBg
  }

  // ── UNDER THE BARS ─────────────────────────────────────────────────
  // The editor's windows lay their frost here (see WindowView): before the
  // tab strip and the status line, so both draw over it, and over the
  // window's own ground.
  //
  // The strip's inactive glass goes first, under the frost: the TabBar
  // painted it over the frost and the strip came out unfrosted (see
  // TabBar's groundBelow).
  TabGlass {
    id: tabsGround
    x: tabs.x
    width: tabs.width
    height: tabs.height
    visible: tabs.visible
    opacity: tabs.opacity
    cell: tabs.hereCell
  }
  Item {
    id: edgeHost
    anchors.fill: parent
    // ONE SCRIM ACROSS EACH BAR, not one per window: over the ghosts (z,
    // since the edges are parented in after this) and under the bar. Each
    // window's stopped at its own edge, which left the editor's inset a
    // darker sliver under the first tab — terminus' topScrim, the same fix.
    Rectangle {
      z: 1
      x: tabs.x
      width: tabs.width
      height: tabs.height
      color: Zenon.ground
      // the sheet's veil, always (user, 2026-10-13): the strip's glass is
      // terminus' sheet's — see WindowView's stripGlass
      opacity: tabs.visible ? 0.6 : 0
      visible: opacity > 0.001
      Behavior on opacity { NumberAnimation { duration: Zenon.ms(180); easing.type: Easing.OutCubic } }
    }
    Rectangle {
      z: 1
      x: status.x
      y: status.y
      width: status.width
      height: status.height
      color: Zenon.ground
      opacity: status.visible && editor.edgesBelow ? 0.35 : 0
      visible: opacity > 0.001
      Behavior on opacity { NumberAnimation { duration: Zenon.ms(180); easing.type: Easing.OutCubic } }
    }
  }

  TabBar {
    id: tabs
    spliceInk: win.upSheet ? win.upSheet.cardInk : 0
    spliceX: win.upSheet ? win.upSheet.x + win.upSheet.drawnX - tabs.x : 0
    spliceW: win.upSheet ? win.upSheet.drawnW : 0
    groundBelow: true
    anchors.left: sidebarBox.right
    anchors.leftMargin: sidebarBox.visible ? 1 : 0
    anchors.right: parent.right
    anchors.top: parent.top
    height: win.zen ? 0 : implicitHeight
    opacity: win.zen ? 0 : 1
    animate: win.settings ? win.settings.animateLayout : true
    tips: tips
    ed: st
    client: nvim
    face.family: Zenon.faceFixed
    face.pixelSize: win.chromeSize
  }

  // ── what the leader menu and the palette act through ───────────────
  // see editor/actions.js
  readonly property var ctx: ({
    client: nvim,
    picker: picker,
    here: () => {
      const f = st.file.replace(/^~/, Quickshell.env("HOME"));
      const cut = f.lastIndexOf("/");
      return cut > 0 ? f.slice(0, cut) : Quickshell.env("HOME");
    },
    // the file being edited, as a path ("" for a buffer with no file)
    file: () => st.file.replace(/^~/, Quickshell.env("HOME")),
    exec: (argv) => Quickshell.execDetached(argv),
    // delphi, when the shell has it (PlatoManager.gitClient): history(file),
    // blame(file, line), show(path, page); null and fugitive does the work
    git: () => win.mgr ? win.mgr.gitClient : null,
    line: () => st.line,
    toggleTree: () => win.toggleTree(),
    // another plato window, empty, beside this one (as SUPER+E is for terminus)
    newWindow: () => { if (win.mgr) win.mgr.spawn(""); },
    // the tree out, and the file being edited found in it
    revealInTree: () => {
      if (win.mgr && !win.mgr.treeShown) win.mgr.setTree(true);
      sidebar.revealCurrent();
    },
    plugins: (page) => pluginPanel.open(page),
    toggleSetting: (key) => { if (win.settings) win.settings.set(key, !win.settings.get(key)); },
    settings: () => settingsSheet.open(),
    // the settings', so the sheet and every plato window agree
    toggleWrap: () => { if (win.settings) win.settings.set("wrap", !win.settings.wrap); },
    peek: () => nvim.cmd("lua require('plato.peek').definition()"),
    restoreTabs: () => nvim.request("restore", {}),
    toggleZen: () => { win.zen = !win.zen; },
    toggleMdPreview: () => { win.mdPreview = !win.mdPreview; },
    pickColor: () => win.pickColor(),
    pastePicture: () => win.pastePicture(),
    toNote: () => win.toNote(),
    // the status line's indent part: how this file is indented and ended
    formatMenu: () => {
      const st0 = st.status, ind = st0.indent || {};
      const cur = (tabs, w) => !!ind.tabs === tabs && ind.width === w ? "current" : "";
      const sp = (w) => ({ label: "Indent with " + w + " spaces", detail: cur(false, w),
        cmd: "setlocal expandtab shiftwidth=" + w + " tabstop=" + w + " softtabstop=" + w });
      const tb = (w) => ({ label: "Indent with tabs, " + w + " wide", detail: cur(true, w),
        cmd: "setlocal noexpandtab shiftwidth=" + w + " tabstop=" + w + " softtabstop=0" });
      picker.openMenu("Indentation and line endings", "\u{F0276}", [
        sp(2), sp(4), sp(8), tb(4), tb(8),
        { label: "Convert the file's indentation to this", detail: "retab", cmd: "%retab!" },
        { label: "Guess the indentation from the file again", detail: "", cmd: "silent! GuessIndent" },
        { label: "Line endings: LF (unix)", detail: st0.eol === "unix" ? "current" : "",
          cmd: "setlocal fileformat=unix" },
        { label: "Line endings: CRLF (windows)", detail: st0.eol === "dos" ? "current" : "",
          cmd: "setlocal fileformat=dos" },
        { label: "Encoding: UTF-8", detail: st0.enc === "utf-8" ? "current" : "",
          cmd: "setlocal fileencoding=utf-8" },
      ]);
    },
    // the status line's language-server part
    lspMenu: () => picker.openMenu("Language servers", "\u{F0493}", [
      { label: "Restart the language servers", detail: "lsp restart", cmd: "lsp restart" },
      { label: "Stop them", detail: "lsp stop", cmd: "lsp stop" },
      { label: "Format the file", detail: "space l f", cmd: "lua require('plato.editing').format()" },
      { label: "What they are, and how they are", detail: "checkhealth", cmd: "checkhealth vim.lsp" },
    ]),
    save: (all) => {
      if (st.file === "" && st.tabs.some((t) => t.current && t.path === "")) win.saveAs(false);
      // root's file is asked about and written as root (root.lua)
      else nvim.cmd("lua require('plato.root').save(" + (all ? "true" : "false") + ")");
    },
    // terminus' dialog: open, or save with the current name suggested
    choose: (dir, save, reply) => {
      const fm = win.mgr ? win.mgr.fileManager : null;
      if (!fm) return;
      const name = st.file.slice(st.file.lastIndexOf("/") + 1) || "untitled";
      fm.choose(false, dir, reply, save ? name : undefined);
    },
  })

  // zen's column: the configured width in cells, plus the gutter, centered
  readonly property real zenMargin: !win.zen ? 0 : Math.max(0, (win.width - sidebarBox.width
    - ((win.settings ? win.settings.zenWidth : 100) + 10) * editor.cellW) / 2)
  // THE EDITOR'S INSET, ON EVERY SIDE THAT MEETS THE WINDOW: the gap above
  // the first line is also the gap beside it, so the current line's bar
  // sits off the window's edges by the same amount all round
  readonly property int editorInset: 6
  // the Markdown preview's pane (mdPreview): delphi's NotesView, by URL,
  // in the suite's scroll helpers. IT OPENS AS THE TREE DOES (user,
  // 2026-10-27: "the same animation like the sidebar, same mechanic"):
  // terminus' SideRoom on the right edge — a floating window widens by it
  // and the text holds still, tiled it slides in — and what it shows keeps
  // its full width, uncovered rather than squeezed, fading with the slide.
  readonly property real mdWidth: 560
  SideRoom {
    id: mdRoom
    window: win
    anchor: editor
    shown: win.previewShown
    want: win.mdWidth
    box: previewBox
    edge: "right"
    minW: 480
  }
  Item {
    id: previewBox
    anchors.right: parent.right
    anchors.top: tabs.bottom
    anchors.bottom: status.top
    width: mdRoom.keepW >= 0 ? Math.max(0, Math.min(win.mdWidth, win.width - mdRoom.keepW))
      : win.previewShown ? win.mdWidth : 0
    Behavior on width {
      enabled: !mdRoom.following
      NumberAnimation { duration: Zenon.normal * 2; easing.type: Zenon.travelEase }
    }
    visible: width > 0.5
    clip: true
    opacity: Math.pow(Math.min(1, previewBox.width / Math.max(1, win.mdWidth)), 1.5)
    Rectangle { width: 1; height: parent.height; color: Zenon.border; z: 2 }
    Flickable {
      id: mdFlick
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: win.mdWidth
      contentWidth: width
      contentHeight: mdLoader.height + 48
      boundsBehavior: Flickable.StopAtBounds
      ElasticScroll { view: mdFlick }
      Loader {
        id: mdLoader
        x: 24
        y: 24
        width: win.mdWidth - 48
        active: previewBox.visible
        source: Qt.resolvedUrl("../delphi/NotesView.qml")
        onLoaded: {
          item.width = Qt.binding(() => mdLoader.width);
          item.body = Qt.binding(() => win.mdText);
          item.base = Qt.binding(() => win.mdBase);
          item.empty = "Nothing written yet";
          item.textSize = Qt.binding(() => Zenon.px(16));
        }
      }
    }
    Scrollbar {
      z: 1
      flick: mdFlick
      anchors.right: mdFlick.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
    }
  }

  EditorView {
    id: editor
    hostWindow: win
    anchors.leftMargin: (sidebarBox.visible ? 1 : 0) + win.editorInset + win.zenMargin
    anchors.rightMargin: win.editorInset + win.zenMargin
    Behavior on anchors.leftMargin { NumberAnimation { duration: Zenon.normal * 2; easing.type: Zenon.travelEase } }
    Behavior on anchors.rightMargin { NumberAnimation { duration: Zenon.normal * 2; easing.type: Zenon.travelEase } }
    onLeaderRequested: leader.open()
    onPickerRequested: (mode) => picker.open(mode)
    onZoomRequested: (step) => { if (win.mgr) win.mgr.zoom(win.tabKey, step); }
    onTyped: toasts.keyTyped()
    // 1-9 on the start card opens that recent file
    digitKey: (n) => win.startOpen(n)
    answerKey: (k) => toasts.tryKey(k)
    // | : show the tree and go to it; go to it; (from in it) put it away
    onTreeToggleRequested: win.toggleTree()
    onSettingsRequested: settingsSheet.open()
    onNewWindowRequested: win.ctx.newWindow()
    onContextRequested: (x, y) => contextMenu.open(x, y)
    anchors.left: sidebarBox.right
    anchors.right: previewBox.left
    anchors.top: tabs.bottom
    anchors.bottom: status.top
    anchors.topMargin: win.editorInset
    ed: st
    client: nvim
    edgeHost: edgeHost
    // the map's frost runs on to the window's edge, past the inset
    mapEdgeOut: win.editorInset + win.zenMargin
    topBar: tabs
    bottomBar: status
    stickyHost: win.zen ? null : stickyHost
    stickyTop: tabs.height
    stickyLeft: tabs.x
    fileDir: win.ctx.here()
    fontSize: win.fontSize
    fontFamily: win.mgr ? win.mgr.fontFamily : Zenon.faceCode
    fontWeight: win.mgr ? win.mgr.fontWeight : Zenon.codeWeight
    cursorBreathes: win.settings ? win.settings.cursorBreathes : true
    cursorGlides: win.settings ? win.settings.cursorGlides : true
    smoothScroll: win.settings ? win.settings.smoothScroll : true
    animateLayout: win.settings ? win.settings.animateLayout : true
    gitGutter: win.settings ? win.settings.gitGutter : true
    jumpTrail: win.settings ? win.settings.jumpTrail : true
    dimInactive: win.settings ? win.settings.dimInactive : true
    minimap: (win.settings ? win.settings.minimap : true) && !win.zen && st.status.large !== true
    onMinimapRows: (n) => nvim.options({ minimapRows: n })
    // nvim is told the editor's new size once the tree has finished moving,
    // not on every frame of it (which re-wrapped the text all the way)
    holdSize: treeSlide.running || zenSlide.running
  }
  // one resize when zen's column has settled, not one a frame
  Timer { id: zenSlide; interval: Zenon.normal * 2 + 20 }

  // the sticky lines' layer: over the editor, so their bar runs the whole
  // width under the tab strip (see WindowView's sticky)
  Item {
    id: stickyHost
    anchors.fill: parent
    // how deep the bar on show is: it lays the window's ground itself, and
    // groundBelow stops above it. Read off what is in here (a window's bar
    // is reparented in), not handed over by the bar, so no order of windows
    // coming and going can leave the ground laid twice.
    readonly property real band: {
      let h = 0;
      for (const c of stickyHost.children)
        if (c.visible && c.height > h) h = c.height;
      return h;
    }
  }

  // ── what nvim says: cards in the editor's lower right corner ───────
  Toasts {
    id: toasts
    anchors.right: editor.right
    anchors.bottom: editor.bottom
    anchors.rightMargin: 18
    anchors.bottomMargin: 12
    width: Math.min(560, editor.width - 36)
    height: editor.height * 0.7
    face.family: Zenon.face
    face.pixelSize: win.chromeSize
    timeout: win.settings ? win.settings.notifyTimeout : 4000
    client: nvim
    z: 20
  }

  // ── THE START CARD ─────────────────────────────────────────────────
  // A blank tab — an empty buffer with no file — shows what
  // you might have come for: the files opened lately (1 to 9 open them),
  // the files pinned in any project, and the projects with tabs kept (a
  // click brings their tabs back). Gone the moment there is text or a file;
  // the editor keeps the keys all along, so i still types.
  readonly property bool startShown: {
    st.frame;
    if (!win.settings || !win.settings.startCard || win.capture || !nvim.ready || win.opening) return false;
    // any blank tab, not only a window's first: a new one (space n) gets it too
    if (st.file !== "" || st.modified || st.lines > 1) return false;
    if (st.cmdlineShown || st.modeName !== "normal" || st.floats.length > 0) return false;
    const w = st.curWin;
    const r = w ? st.rowsOf(w.id)[0] : null;
    return !r || r.t === "";
  }
  property var startData: ({ recent: [], pins: [], projects: [] })
  onStartShownChanged: if (win.startShown) nvim.request("startCard", {}, (r) => {
    if (r) win.startData = { recent: st._list(r.recent), pins: st._list(r.pins), projects: st._list(r.projects) };
  })
  function startOpen(n) {
    if (!win.startShown) return false;
    const p = n <= startCard.fit.n.recent ? win.startData.recent[n - 1] : null;
    if (!p) return false;
    nvim.openAt(p);
    return true;
  }
  function tidyPath(p) {
    const home = Quickshell.env("HOME");
    return p.indexOf(home + "/") === 0 ? "~" + p.slice(home.length) : p === home ? "~" : p;
  }
  // ON THE BLANK WINDOW, not the editor. Split (:vsplit, :split), the card
  // was centered on the whole editor and lay across both windows and over
  // the text of the other one (user, 2026-10-09). It goes on the window it
  // is about — the current one, the blank one — in the window's own size.
  readonly property rect startRect: {
    st.frame;
    const w = st.curWin;
    const it = w && st.winIds.length > 1 ? editor.windowItem(w.id) : null;
    return it ? Qt.rect(editor.x + it.x, editor.y + it.y, it.width, it.height)
              : Qt.rect(editor.x, editor.y, editor.width, editor.height);
  }
  Item {
    id: startCard
    x: Math.round(win.startRect.x + (win.startRect.width - width) / 2)
    y: Math.round(win.startRect.y + (win.startRect.height - height) / 2)
    width: Math.max(0, Math.min(win.startRect.width - 48, 640))
    height: startCol.implicitHeight
    z: 15
    clip: true
    opacity: win.startShown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
    readonly property int rowH: 30
    // A SHORT WINDOW: the card gives way rather than spill past the text —
    // the name goes first, then the hints, then rows off the longest list,
    // the recent files (the ones 1 to 9 open) held onto longest
    FontMetrics { id: headMetrics; font.family: Zenon.face; font.pixelSize: Zenon.px(12) }
    readonly property var fit: {
      const d = win.startData;
      const avail = win.startRect.height - 32;
      const head = headMetrics.height + 4 + 12;   // heading, its padding, the section's
      const n = { recent: d.recent.length, pins: d.pins.length, projects: d.projects.length };
      let logo = true, hints = true;
      const tall = () => {
        let h = 0, parts = 0;
        if (logo) { h += startLogo.implicitHeight; parts++; }
        if (hints) { h += startHints.implicitHeight; parts++; }
        for (const k in n) if (n[k] > 0) { h += head + n[k] * startCard.rowH; parts++; }
        return h + Math.max(0, parts - 1) * startCol.spacing > avail;
      };
      if (tall()) logo = false;
      if (tall()) hints = false;
      while (tall()) {
        let k = null;
        for (const o of ["projects", "pins", "recent"]) {
          const w = (x) => n[x] * (x === "recent" ? 0.5 : 1);
          if (n[o] > 0 && (k === null || w(o) > w(k))) k = o;
        }
        if (k === null) break;
        n[k]--;
      }
      return { logo: logo, hints: hints, n: n };
    }
    Column {
      id: startCol
      width: parent.width
      spacing: 4
      // the name, in the box-drawing letters the shell's file headers use;
      // a fixed face at its own line height, so the strokes meet
      Text {
        id: startLogo
        visible: startCard.fit.logo
        // the art's own face, whatever the shell's (Zenon.artFace)
        font.family: Zenon.artFace
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(22)
        color: Zenon.white
        textFormat: Text.PlainText
        text: "┌─┐┬  ┌─┐┌┬┐┌─┐\n├─┘│  ├─┤ │ │ │\n┴  ┴─┘┴ ┴ ┴ └─┘"
        bottomPadding: 18
      }
      // a heading for each list, and its rows
      Repeater {
        model: [
          { title: "Recent files", kind: "recent" },
          { title: "Pinned", kind: "pins" },
          { title: "Projects", kind: "projects" },
        ]
        Column {
          id: section
          required property var modelData
          readonly property var items: (win.startData[section.modelData.kind] || [])
            .slice(0, startCard.fit.n[section.modelData.kind])
          visible: section.items.length > 0
          width: startCol.width
          bottomPadding: 12
          SectionLabel {
            text: section.modelData.title.toUpperCase()
            bottomPadding: 4
          }
          Repeater {
            model: section.items
            Item {
              id: entry
              required property var modelData
              required property int index
              readonly property bool project: section.modelData.kind === "projects"
              readonly property string path: entry.project ? entry.modelData.root : entry.modelData
              readonly property string name: entry.path.slice(entry.path.lastIndexOf("/") + 1)
              width: section.width
              height: startCard.rowH
              Rectangle {
                anchors.fill: parent
                anchors.leftMargin: -10
                anchors.rightMargin: -10
                radius: Zenon.windowRadius
                color: entryPress.pressed ? Zenon.wash(0.05) : "transparent"
              }
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Text {
                  textFormat: Text.PlainText
                  width: 22
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                  font.family: Zenon.faceMono
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(17)
                  // a directory in the theme's accent (user, 2026-10-28), as
                  // directories are everywhere else in the suite
                  color: entry.project ? Zenon.cyan : Zenon.white
                  text: entry.project ? "\u{F024B}" : Icons.glyphFor({ name: entry.name, isDir: false })
                }
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  font.family: Zenon.face
                  font.pixelSize: Zenon.px(15)
                  font.weight: 600
                  color: Zenon.white
                  text: entry.name
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, section.width * 0.55)
                  elide: Text.ElideMiddle
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(13)
                  color: Zenon.accentMuted
                  text: entry.project
                    ? win.tidyPath(entry.path) + "  ·  " + entry.modelData.files
                      + (entry.modelData.files === 1 ? " file" : " files") + "  ·  " + entry.modelData.ago
                    : win.tidyPath(entry.path.slice(0, entry.path.lastIndexOf("/")))
                }
              }
              KeyCap {
                visible: section.modelData.kind === "recent"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: String(entry.index + 1)
                fontSize: 12
              }
              HoverHandler { id: entryHover }
              TapHandler {
                id: entryPress
                onTapped: {
                  if (entry.project) nvim.request("openProject", { root: entry.path });
                  else nvim.openAt(entry.path);
                  editor.forceActiveFocus();
                }
              }
            }
          }
        }
      }
      // what else gets you somewhere
      // the shared hint strip (morpheus/HintRow), as every panel's; what
      // does not fit the card waits behind its `?`
      HintRow {
        id: startHints
        visible: startCard.fit.hints
        maxWidth: startCol.width
        topPadding: 6
        rows: [["space f", "find a file"], ["space space", "open…"], ["space n", "blank tab"], ["space /", "search"], ["i", "just type"]]
      }
    }
  }

  // ── FILES DROPPED ON THE WINDOW ────────────────────────────────────
  // From terminus or any file manager: dropped on the text, each opens as a
  // tab at the end of the strip; dropped on the strip, they go where they
  // fell — a line in the strip says where while they are held over it.
  DropArea {
    id: drop
    anchors.left: sidebarBox.right
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: status.top
    z: 30
    // a Markdown file also takes a picture as data (a screenshot tool's)
    keys: st.filetype === "markdown" ? ["text/uri-list"].concat(win.imageTypes) : ["text/uri-list"]
    property bool over: false
    property real atX: 0
    readonly property bool onStrip: drop.over && tabs.visible && drop.atY < tabs.height
    property real atY: 0
    readonly property real cellW: tabs.width / Math.max(1, st.tabs.length)
    readonly property int slot: Math.max(0, Math.min(st.tabs.length, Math.round(drop.atX / drop.cellW)))
    onEntered: (d) => { drop.over = true; drop.atX = d.x; drop.atY = d.y; }
    onPositionChanged: (d) => { drop.atX = d.x; drop.atY = d.y; }
    onExited: drop.over = false
    onDropped: (d) => {
      const slot = drop.onStrip ? drop.slot : -1;
      drop.over = false;
      // PICTURES INTO MARKDOWN (user, 2026-10-27): on the text of a Markdown
      // file, a picture or video becomes a link under the cursor's line —
      // one of this computer where it is, a web one fetched and picture data
      // written out beside the file (delphi's MediaDrop, D.dropSorted).
      // Anything else still opens as a tab.
      if (st.filetype === "markdown" && slot < 0 && win.mdDir() !== "") {
        const kind = win.imageTypes.find((t) => (d.formats || []).indexOf(t) >= 0) || "";
        const got = D.dropSorted(d.hasUrls ? d.urls : [], "", kind !== "");
        if (got.files.length || got.web.length || kind !== "") {
          d.acceptProposedAction();
          if (got.files.length) win.linkMedia(got.files);
          for (const u of got.web) mediaHelp.item.fetch(u, Qt.point(0, 0));
          if (!got.files.length && !got.web.length && kind !== "") {
            const buf = d.getDataAsArrayBuffer(kind);
            if (buf && buf.byteLength > 0)
              mediaHelp.item.write(D.base64Of(buf), kind.split("/")[1].replace("jpeg", "jpg"), Qt.point(0, 0));
          }
          editor.forceActiveFocus();
          return;
        }
      }
      const paths = (d.urls || []).map((u) => String(u))
        .filter((u) => u.startsWith("file://"))
        .map((u) => decodeURIComponent(u.replace(/^file:\/\/[^/]*/, "")));
      if (paths.length === 0) return;
      d.acceptProposedAction();
      nvim.request("dropped", { paths: paths }, (ids) => {
        const list = st._list(ids);
        if (slot >= 0 && list.length) st.placeTabs(list, slot);
      });
      editor.forceActiveFocus();
    }
    // held over the text: the editor outlined
    Rectangle {
      visible: drop.over && !drop.onStrip
      x: 0
      y: tabs.height
      width: parent.width
      height: parent.height - tabs.height
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.05)
      border.width: 1
      border.color: Zenon.cyan
      radius: Zenon.radiusControl
    }
    // held over the strip: where the tabs will go
    Rectangle {
      visible: drop.onStrip
      x: Math.round(drop.slot * drop.cellW) - 1
      y: 3
      width: 2
      height: tabs.height - 6
      radius: 1
      color: Zenon.cyan
    }
  }

  // what can follow a command half typed (g, z, d…): never takes a key
  // the two cards about keys being typed rise from the status bar, over the
  // editor's column (the tree runs the window's height beside it)
  Item {
    id: keyWell
    anchors.left: sidebarBox.right
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
  }
  KeyHints {
    id: keyHints
    backdrop: editor   // frosted over it — see morpheus/Sheet
    anchors.fill: keyWell
    toBottom: status.height
    ed: st
    active: win.settings ? win.settings.keyHints : true
    z: 25
  }

  ContextMenu {
    id: contextMenu
    anchors.fill: editor
    ed: st
    client: nvim
    ctx: win.ctx
    window: win
    onClosed: editor.forceActiveFocus()
  }

  // one tooltip for the window's buttons, as the tree's toolbar has its own
  WindowTip { id: tips; window: win }

  // ── SHEETS SPLICE OUT OF THE BARS ──────────────────────────────────
  // The one hanging furthest down from each end, for the bar it hangs
  // from: the status line goes black under the key hints or the leader
  // card and opens its hairline over them; the tab strip, the same for the
  // picker, the plugins and the settings (see TabBar/StatusBar spliceInk).
  // where the editor's column starts: a sheet's dim stops there
  readonly property real treeEdge: sidebarBox.visible ? sidebarBox.width + 1 : 0
  function spliceOf(list) {
    let best = null;
    for (const s of list)
      if (s && s.cardInk > (best ? best.cardInk : 0.001)) best = s;
    return best;
  }
  // the picker splices out of whichever bar it came from: a menu or the
  // motions sheet rises from the status line (Picker.rising)
  readonly property var downSheet: win.spliceOf([keyHints, leader, picker.rising ? picker : null])
  readonly property var upSheet: win.spliceOf([picker.rising ? null : picker, pluginPanel, settingsSheet])

  StatusBar {
    id: status
    spliceInk: win.downSheet ? win.downSheet.cardInk : 0
    spliceX: win.downSheet ? win.downSheet.x + win.downSheet.drawnX - status.x : 0
    spliceW: win.downSheet ? win.downSheet.drawnW : 0
    tips: tips
    height: win.zen ? 0 : implicitHeight
    opacity: win.zen ? 0 : 1
    // only while folded away: the command line's completions hang above
    // the bar, and a clip there cut them off entirely
    clip: win.zen
    pluginUpdates: win.mgr && win.mgr.plugins ? win.mgr.plugins.count : 0
    onPluginsClicked: pluginPanel.open("updates")
    onDiagnosticsClicked: picker.open("diags")
    // the branch: delphi on this file's repository, when the shell has it
    // (PlatoManager.gitClient); fugitive's status otherwise
    onGitClicked: {
      const g = win.mgr ? win.mgr.gitClient : null;
      const f = String(st.file || "").replace(/^~/, Quickshell.env("HOME"));
      if (g && f !== "") g.show(f, "changes");
      else nvim.cmd("Git");
    }
    onLspClicked: win.ctx.lspMenu()
    onFormatClicked: win.ctx.formatMenu()
    treeShown: win.treeShown
    onTreeToggled: {
      if (!win.mgr) return;
      win.mgr.setTree(!win.mgr.treeShown);
      editor.forceActiveFocus();
    }
    // under the editor only: the tree runs the window's full height beside it.
    // Flush against the tree's hairline, as the tab strip is — not the
    // editor's left, which is inset for the current line's bar and left a
    // gap beside the tree (user, 2026-10-12: the two kept apart)
    anchors.left: sidebarBox.right
    anchors.leftMargin: sidebarBox.visible ? 1 : 0
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    ed: st
    client: nvim
    font.family: Zenon.faceFixed
    font.weight: Zenon.weight
    font.pixelSize: win.chromeSize - 2
    // the tree toggle's size (Zenon.face), and every glyph on the bar's
    // Four pixels down (user, 2026-10-08, two steps of 2), iconSize with it.
    glyphSize: win.chromeSize - 1
  }

  Picker {
    backdrop: editor   // frosted over it — see morpheus/Sheet
    id: picker
    // terminus' sheets hang from the chrome: here, the tab strip — and a
    // menu rises from the status bar (Picker.rising)
    fromTop: tabs.height
    toBottom: status.height
    dimLeft: picker.rising ? 0 : win.treeEdge
    // rising, it is the leader's twin: over the editor's column, spliced
    // out of the status line there (downSheet)
    anchors.fill: picker.rising ? keyWell : parent
    ed: st
    client: nvim
    ctx: win.ctx
    finder: win.mgr ? win.mgr.finder : null
    codeFamily: win.mgr ? win.mgr.fontFamily : Zenon.faceCode
    codeWeight: win.mgr ? win.mgr.fontWeight : Zenon.codeWeight
    history: win.mgr
    face.family: Zenon.faceFixed
    face.pixelSize: win.chromeSize
    onClosed: editor.forceActiveFocus()
  }

  PluginPanel {
    backdrop: editor   // frosted over it — see morpheus/Sheet
    id: pluginPanel
    dimLeft: win.treeEdge
    // terminus' sheets hang from the chrome: here, the tab strip
    fromTop: tabs.height
    plugins: win.mgr ? win.mgr.plugins : null
    filetype: st.filetype
    // Oracle's Font row: its family (with the Nerd cut) and weight
    face.family: Zenon.face
    face.weight: Zenon.weight
    face.pixelSize: win.chromeSize
    onClosed: editor.forceActiveFocus()
    onConfigure: (path) => nvim.openAt(path)
  }
  SettingsSheet {
    backdrop: editor   // frosted over it — see morpheus/Sheet
    id: settingsSheet
    dimLeft: win.treeEdge
    // terminus' sheets hang from the chrome: here, the tab strip
    fromTop: tabs.height
    settings: win.settings
    window: win
    face.family: Zenon.faceFixed
    face.pixelSize: win.chromeSize
    onClosed: editor.forceActiveFocus()
  }
  function showSettings() { settingsSheet.open(); }
  // a row of the tree, its properties — terminus' card, see PropsSheet
  // ── PICTURES INTO MARKDOWN ─────────────────────────────────────────────
  readonly property var imageTypes: ["image/png", "image/jpeg", "image/gif", "image/webp", "image/avif", "image/bmp"]
  // the Markdown file's own directory, "" for a buffer with no file
  function mdDir() {
    const f = st.file.replace(/^~/, Quickshell.env("HOME"));
    return f.lastIndexOf("/") > 0 ? f.slice(0, f.lastIndexOf("/")) : "";
  }
  // a link per file, its path from the Markdown file's directory when it is
  // under it, as it is otherwise
  function linkMedia(paths) {
    const dir = win.mdDir();
    const lines = (paths || []).map((p) => {
      const rel = dir !== "" && p.indexOf(dir + "/") === 0 ? p.slice(dir.length + 1) : p;
      const url = encodeURI(rel);
      const name = D.baseName(p).replace(/\.[^.]*$/, "").replace(/[\[\]]/g, "");
      return D.mediaKindOf(p) === "video" ? url : "![" + name + "](" + url + ")";
    });
    if (lines.length) nvim.request("insertBelow", { lines: lines });
  }
  // delphi's MediaDrop, by URL, as a helper only: its fetch and write, into
  // the Markdown file's directory; it takes no drops of its own
  Loader {
    id: mediaHelp
    active: st.filetype === "markdown"
    source: Qt.resolvedUrl("../delphi/MediaDrop.qml")
    onLoaded: {
      item.enabled = false;
      item.dir = Qt.binding(() => win.mdDir());
      item.media.connect((paths) => win.linkMedia(paths));
      item.failed.connect((why) => toasts.take({ kind: "wmsg", text: why }));
    }
  }
  // a picture on the clipboard, written beside the Markdown file and linked
  function pastePicture() {
    const dir = win.mdDir();
    if (st.filetype !== "markdown" || dir === "") {
      toasts.take({ kind: "wmsg", text: "Pictures go into a saved Markdown file" });
      return;
    }
    pasteProc.command = ["sh", "-c",
      't=$(wl-paste --list-types 2>/dev/null | grep -m1 "^image/") || exit 2; e=${t#image/}; [ "$e" = jpeg ] && e=jpg; '
      + 'f="$1/pasted-$(date +%Y%m%d-%H%M%S).$e"; wl-paste --no-newline --type "$t" > "$f" && [ -s "$f" ] && printf %s "$f"',
      "sh", dir];
    pasteProc.running = true;
  }
  Process {
    id: pasteProc
    stdout: StdioCollector { id: pasteOut }
    onExited: (code) => {
      if (code === 0 && pasteOut.text !== "") win.linkMedia([pasteOut.text]);
      else toasts.take({ kind: "wmsg", text: code === 2 ? "No picture on the clipboard" : "The picture could not be kept" });
    }
  }

  // ── THE SELECTION, TO A NOTE (user, 2026-10-27) ───────────────────────
  // A new Clio note (PlatoManager.notes): the file's name as its title, the
  // lines — Monostyled, but for prose (Markdown, plain text) — and where they
  // came from, file:line, under them.
  function toNote() {
    const clio = win.mgr ? win.mgr.notes : null;
    if (!clio) { toasts.take({ kind: "wmsg", text: "Clio is not in this shell" }); return; }
    nvim.request("selection", {}, (r) => {
      if (!r) return;
      const lines = st._list(r.lines).map(String);
      const f = String(r.file || "").replace(Quickshell.env("HOME"), "~");
      const name = f === "" ? "Untitled" : f.slice(f.lastIndexOf("/") + 1);
      const where = f === "" ? "" : f + ":" + r.l1 + (r.l2 > r.l1 ? "–" + r.l2 : "");
      const prose = ["markdown", "text", ""].indexOf(String(r.ft || "")) >= 0;
      clio.noteFromText(name, lines, where, !prose);
    });
  }

  // a #hex under the cursor, chosen again — or one put in (ColorSheet)
  ColorSheet {
    id: colorSheet
    backdrop: editor
    client: nvim
    dimLeft: win.treeEdge
    fromTop: tabs.height
    onClosed: editor.forceActiveFocus()
  }
  // only ON a color: one written in where the cursor stood split a word
  // (user, 2026-10-27: "promp#00f5fft")
  function pickColor() {
    nvim.request("colorAt", {}, (r) => {
      if (r && r.hex) colorSheet.openFor(r);
      else toasts.take({ kind: "wmsg", text: "Put the cursor on a #hex color first" });
    });
  }

  PropsSheet {
    backdrop: editor   // frosted over it — see morpheus/Sheet
    id: propsSheet
    dimLeft: win.treeEdge
    fromTop: tabs.height
    onClosed: (keysTo) => (keysTo || (win.treeShown ? sidebar : editor)).forceActiveFocus()
    onSaid: (t) => toasts.take({ kind: "props", text: t })
    onRenameWanted: (from, name) => sidebar.renamePath(from, name, (to) => {
      propsSheet.showPath(to);
      toasts.take({ kind: "props", text: "renamed to " + name });
    })
    // its "open with" list, on the tree's own menu
    onMenuWanted: (item, rows) =>
      sidebar.openRows(item.mapToItem(null, 0, item.height), rows, () => propsSheet.takeKeys())
  }

  // z=: what the word could be, and what to do with it (spell.lua)
  function spellMenu(ev) {
    const word = String(ev.word || "");
    const lua = (fn, w) => "lua require('plato.spell')." + fn + "(" + JSON.stringify(w) + ")";
    const rows = st._list(ev.items).map((w) => ({ label: w, detail: "", cmd: lua("use", w) }));
    rows.push({ label: "Add “" + word + "” to the dictionary", detail: "zg",
                cmd: "lua require('plato.spell').add(" + JSON.stringify(word) + ", true)" });
    rows.push({ label: "Ignore “" + word + "” this session", detail: "zG",
                cmd: "lua require('plato.spell').add(" + JSON.stringify(word) + ", false)" });
    picker.openMenu("Spelling of “" + word + "”", "\u{F04C6}", rows);
  }

  function showPlugins() { pluginPanel.open(); }
  function loadPlugin(name) {
    nvim.cmd("lua require('plato.plugins').loadOne(" + JSON.stringify(name) + ")");
  }
  function sendKeys(k) { nvim.input(k); }
  // A parser this window's engine offered and was told to build
  // (suggest.lua): built by the one manager, as the Parsers page builds
  // them, and said in the corner — started, then done or why not.
  property bool parserAsked: false
  function buildParsers(langs) {
    const pl = win.mgr ? win.mgr.plugins : null;
    if (!pl) return;
    if (pl.parserBusy) {
      toasts.take({ kind: "wmsg", text: "Another parser is building — try again from the plugins sheet's Parsers page (Space U)." });
      return;
    }
    win.parserAsked = true;
    pl.installParsers(langs);
    toasts.take({ kind: "progress", msgId: "plato-parsers", text: "Building the " + langs.join(", ") + " parser…" });
  }
  Connections {
    target: win.mgr ? win.mgr.plugins : null
    function onParserPhaseChanged() {
      const pl = win.mgr.plugins;
      if (!win.parserAsked || (pl.parserPhase !== "done" && pl.parserPhase !== "failed")) return;
      win.parserAsked = false;
      toasts.take({ kind: pl.parserPhase === "failed" ? "emsg" : "", msgId: "plato-parsers", text: pl.parserNote });
    }
  }
  function parsersAdded(langs) {
    nvim.cmd("lua require('plato.plugins').parsersAdded(vim.json.decode(" + JSON.stringify(JSON.stringify(langs)) + "))");
  }

  LeaderCard {
    backdrop: editor   // frosted over it — see morpheus/Sheet
    id: leader
    // up from the status bar, as the key hints come
    anchors.fill: keyWell
    fromTop: tabs.height
    fromBottom: true
    toBottom: status.height
    ctx: win.ctx
    face.family: Zenon.faceFixed
    face.pixelSize: win.chromeSize
    onClosed: if (!picker.shown) editor.forceActiveFocus()
  }

  Component.onCompleted: {
    editor.forceActiveFocus();
    if (win.openPath !== "") win.noteOpening();
  }
}
