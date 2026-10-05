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
import "../terminus/terminus.js" as Terminus
import "editor/actions.js" as Actions
import "../morpheus/icons.js" as Icons

FloatingWindow {
  id: win

  // A fixed title, for the window rules: `plato` is what hyprland matches on.
  // The file being edited is in the status line instead.
  title: win.capture ? "plato-capture" : "plato"
  color: Zenon.layerBg
  implicitWidth: win.capture ? 760 : 1100
  implicitHeight: win.capture ? 460 : 800
  minimumSize: Qt.size(480, 240)

  property var mgr: null
  property string sessionId: ""
  // rebuilt after a reload: the nvim is already running, find it again
  property bool reconnect: false
  // a file to open once nvim is listening
  property string openPath: ""
  // QUICK CAPTURE (PlatoManager.capture): a small window on one note, the
  // cursor at its end, no tree; whatever is typed is saved when it loses
  // focus, and the note's directory is made if it is not there
  property bool capture: false
  // and any more asked for before it was
  property var _later: []

  function openFile(path) {
    // opened from outside (terminus, artemis, `plato f`): the tree goes there
    sidebar.follow(path, false);
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
  // bridge keeps any unsaved buffer in plato's rescue folder and says so in
  // a notification, rather than losing it.
  onClosed: win.finish(true)

  EditorState {
    id: st
    // the settings' "Current line number colour", one of zenon's
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
      markdown: {
        render: s.mdRender, rawLine: s.mdRawLine, headings: s.mdHeadings, inline: s.mdInline,
        lists: s.mdLists, code: s.mdCode, tables: s.mdTables, quotes: s.mdQuotes, rules: s.mdRules,
      },
    });
  }

  // ── ZEN MODE ───────────────────────────────────────────────────────
  // Space z: the tree, the tabs and the status line put away, the text in a
  // centred column (the settings' "Zen mode text width"), and everything
  // but the cursor's paragraph faded back (nvim says which lines that is:
  // view.lua's `para`). Per window, and not kept: it is a mood, not a
  // setting. Esc does not leave it; Space z does.
  property bool zen: false
  onZenChanged: { win.pushOptions(); zenSlide.restart(); }

  // ── SAVED WHEN YOU LOOK AWAY ───────────────────────────────────────
  // With the setting on, every modified file with a name is written as the
  // window loses focus (silently: a new buffer has nowhere to go).
  readonly property bool focused: editor.Window.active
  onFocusedChanged: {
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
  readonly property int fontSize: win.mgr ? (win.mgr.zooms, win.mgr.sizeFor(win.tabKey)) : 16
  readonly property int chromeSize: win.mgr ? win.mgr.chromeSize : 16

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
  onTreeShownChanged: win.makeRoom(win.treeShown)
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
  // (see makeRoom).
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
    // window has gained (see keepW); otherwise it slides on its own
    width: win.keepW >= 0 ? Math.max(0, Math.min(win.treeTarget, win.width - win.keepW))
      : win.treeShown && !win.zen ? win.treeTarget : 0
    Behavior on width {
      // a drag of the edge follows the pointer, not an easing; nor does a
      // tree that is following the window's own resize (`following`, its
      // own flag — see releaseFollow for why it is not keepW)
      enabled: (!win.mgr || win.mgr.liveTreeWidth < 0) && !win.following
      NumberAnimation { id: treeSlide; duration: Zenon.normal * 2; easing.type: Zenon.travelEase }
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
      // and in the tree's own colour
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
      fontSize: win.chromeSize - 1
      // its bar's glyphs as big as the status line's beside it: the tree
      // toggle and the root marker (StatusBar's iconSize)
      toolbarGlyphSize: Math.round((win.chromeSize - 1 + 4) * 1.25)
      window: win
      onFileActivated: (p) => { nvim.openAt(p); editor.forceActiveFocus(); }
      onDismissed: editor.forceActiveFocus()
      onPathChanged: (from, to) => nvim.request("renamed", { from: from, to: to })
    }
  }

  // ── THE WINDOW MAKES ROOM FOR ITS TREE, AS TERMINUS' DOES FOR ITS SPLIT
  // The same logic, through the same functions (terminus.js splitRoom and
  // splitRoomDispatches — see the notes on `fitSplit` in TerminusWindow):
  // showing the tree in a floating window widens it by the tree, as far as
  // the monitor allows, and hiding it gives exactly that back, from the left
  // edge so the editor holds still — pushed inward only if the monitor's
  // edge is in the way, never recentred. Tiled, fullscreen or maximized,
  // the layout owns the size and nothing happens. Hyprland does the resize, because a mapped
  // Quickshell window ignores a new implicitWidth.
  //
  // `treeGrew` is what was added, so a hide gives back only that. Each
  // request says what it was for (`fitFor`) and resizes at most once
  // (`fitPending`): a quick show-hide must not land the show's answer after
  // the hide and ratchet the window wider, the bug terminus' split had.
  //
  // Only the window the toggle happened in: the tree is shown or hidden in
  // every plato window at once (oracle's setting), and the others keep their
  // size and make room inside.
  property int treeGrew: 0
  property int treeWant: 0
  property bool fitFor: false
  property bool fitPending: false
  // ONE ANIMATION, NOT TWO. The tree used to slide on its own clock while
  // Hyprland animated the window's resize and move on another; every
  // frame the editor sat somewhere different inside a window that was
  // somewhere different on screen, and the text shook left and right. Now,
  // while the window is resized for the tree, the editor keeps its width
  // (keepW: the window's width less the tree, at the toggle) and the tree is
  // exactly what the window has gained or not yet given back. -1: not
  // following; released once the window lands, or after a ceiling.
  property real keepW: -1
  property bool following: false
  property int fitTarget: 0
  // IN THIS ORDER. Releasing used to be keepW = -1 alone, which in one
  // stroke switched the slide back on AND moved the tree's target — and
  // which of the two Qt applied first was not ours to choose. Target
  // first, and the tree jumped: in a tiled or maximized window (where
  // no resize ever comes, and every toggle ends here) it vanished on a
  // hide and the editor leapt sideways, then crept back. The slide is
  // switched on first, then the target moves.
  function releaseFollow() {
    win.following = false;
    win.keepW = -1;
    followCeiling.stop();
  }

  // whether the layout owns the size (tiled, maximized, fullscreen): known
  // before a toggle, so the tree in such a window slides at once — see
  // terminus/LayoutProbe.qml
  LayoutProbe { id: layout; title: win.title }
  Timer { id: followCeiling; interval: 1500; onTriggered: win.releaseFollow() }
  // LANDED: THE OTHER ORDER. The window's width arrives here before the
  // tree's binding has seen it, so the tree still holds its width from
  // before the resize (0 opening, the full width closing); switching the
  // slide on first eased it from that all over again, and the editor took
  // the whole window for a moment. With the slide still off, the tree goes
  // straight to the width the window just gained (terminus' sidebar too).
  onWidthChanged: if (win.keepW >= 0 && win.fitTarget > 0 && Math.abs(win.width - win.fitTarget) < 1) {
    win.keepW = -1;
    win.following = false;
    followCeiling.stop();
  }
  function makeRoom(shown) {
    if (!editor.Window.active) return;
    // the layout owns the size: no resize will come, the tree just slides
    if (layout.laidOut) { win.treeGrew = 0; return; }
    if (shown) {
      if (win.treeGrew > 0) return;
      win.treeWant = win.width + Math.round(win.treeTarget) + 1;
    } else if (win.treeGrew > 0) win.treeWant = win.width - win.treeGrew;
    else return;
    win.following = true;
    win.keepW = win.width - sidebarBox.width;
    win.fitTarget = 0;
    followCeiling.restart();
    win.fitFor = shown;
    win.fitPending = true;
    fitProc.running = false;
    fitProc.running = true;
  }
  Process {
    id: fitProc
    command: ["sh", "-c", "hyprctl -j activewindow; echo '@@mons'; hyprctl -j monitors"]
    stdout: StdioCollector {
      id: fitOut
      onStreamFinished: {
        if (!win.fitPending) return;
        // asked for a state we have since toggled out of
        if (win.fitFor !== win.treeShown) { win.fitPending = false; return; }
        const parts = fitOut.text.split("@@mons");
        let w = null, mons = null;
        try { w = JSON.parse(parts[0]); mons = JSON.parse(parts[1]); } catch (e) { win.releaseFollow(); return; }
        // the window the toggle happened in is the focused one; anything
        // else answering here is not ours to resize
        if (!w || w.class !== "org.quickshell" || w.title !== win.title) { win.releaseFollow(); return; }
        win.fitPending = false;
        layout.note(w);
        const room = Terminus.splitRoom(w, mons, win.treeWant, 16, 480, "left");
        // no resize coming (tiled, or no room): the tree slides as before
        if (!room) win.releaseFollow();
        else {
          win.fitTarget = w.size[0] + room.dw;
          Terminus.splitRoomDispatches(w.address, room).forEach((d) => Hyprland.dispatch(d));
        }
        win.treeGrew = win.fitFor && room ? room.dw : 0;
      }
    }
  }

  // the tree's edge: a hairline, and a handle to drag it wider or narrower
  Rectangle {
    visible: sidebarBox.visible
    // over the editor, which overlaps the handle's right half
    z: 10
    anchors.left: sidebarBox.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 1
    color: Zenon.border
    MouseArea {
      anchors.fill: parent
      anchors.leftMargin: -3
      anchors.rightMargin: -3
      cursorShape: Qt.SplitHCursor
      // A DRAG INTO THE TREE MUST STAY A DRAG. Its rows each carry a
      // DragHandler and its list is a Flickable, and either took the pointer
      // from this the moment it crossed into them: the edge stopped mid-drag.
      preventStealing: true
      onPositionChanged: (m) => {
        if (!pressed || !win.mgr) return;
        const x = mapToItem(win.contentItem, m.x, 0).x;
        win.mgr.dragTree(Math.round(Math.max(180, Math.min(700, win.width * 0.5, x))));
      }
      onReleased: if (win.mgr) win.mgr.dropTree()
    }
  }

  // ── UNDER THE BARS ─────────────────────────────────────────────────
  // The editor's windows lay their frost here (see WindowView): before the
  // tab strip and the status line, so both draw over it, and over the
  // window's own ground.
  Item {
    id: edgeHost
    anchors.fill: parent
  }

  TabBar {
    id: tabs
    spliceInk: win.upSheet ? win.upSheet.cardInk : 0
    spliceX: win.upSheet ? win.upSheet.x + win.upSheet.drawnX - tabs.x : 0
    spliceW: win.upSheet ? win.upSheet.drawnW : 0
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
    exec: (argv) => Quickshell.execDetached(argv),
    toggleTree: () => win.toggleTree(),
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

  // zen's column: the configured width in cells, plus the gutter, centred
  readonly property real zenMargin: !win.zen ? 0 : Math.max(0, (win.width - sidebarBox.width
    - ((win.settings ? win.settings.zenWidth : 100) + 10) * editor.cellW) / 2)
  // THE EDITOR'S INSET, ON EVERY SIDE THAT MEETS THE WINDOW: the gap above
  // the first line is also the gap beside it, so the current line's bar
  // sits off the window's edges by the same amount all round
  readonly property int editorInset: 6
  EditorView {
    id: editor
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
    onContextRequested: (x, y) => contextMenu.open(x, y)
    anchors.left: sidebarBox.right
    anchors.right: parent.right
    anchors.top: tabs.bottom
    anchors.bottom: status.top
    anchors.topMargin: win.editorInset
    ed: st
    client: nvim
    edgeHost: edgeHost
    topBar: tabs
    bottomBar: status
    fileDir: win.ctx.here()
    fontSize: win.fontSize
    fontFamily: win.mgr ? win.mgr.fontFamily : Zenon.faceFixed
    fontWeight: win.mgr ? win.mgr.fontWeight : Font.DemiBold
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
    if (!win.settings || !win.settings.startCard || win.capture || !nvim.ready) return false;
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
  Item {
    id: startCard
    anchors.centerIn: editor
    width: Math.min(editor.width - 48, 640)
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
    FontMetrics { id: headMetrics; font.family: Zenon.face; font.pixelSize: 12 }
    readonly property var fit: {
      const d = win.startData;
      const avail = editor.height - 32;
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
        font.family: Zenon.faceFixed
        font.pixelSize: 22
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
          Text {
            font.family: Zenon.face
            font.pixelSize: 12
            font.letterSpacing: 1
            color: Zenon.muted
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
                radius: 5
                color: entryHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
              }
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Text {
                  width: 22
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                  font.family: Zenon.faceMono
                  font.pixelSize: 17
                  color: entry.project ? Zenon.blue : Zenon.white
                  text: entry.project ? "\u{F024B}" : Icons.glyphFor({ name: entry.name, isDir: false })
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  font.family: Zenon.face
                  font.pixelSize: 15
                  font.weight: 600
                  color: Zenon.white
                  text: entry.name
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, section.width * 0.55)
                  elide: Text.ElideMiddle
                  font.family: Zenon.face
                  font.pixelSize: 13
                  color: Zenon.muted
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
              HoverHandler { id: entryHover; cursorShape: Qt.PointingHandCursor }
              TapHandler {
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
      Flow {
        id: startHints
        visible: startCard.fit.hints
        width: startCol.width
        spacing: 18
        topPadding: 6
        Repeater {
          model: [["space f", "find a file"], ["space space", "open…"], ["space n", "blank tab"], ["space /", "search"], ["i", "just type"]]
          Row {
            required property var modelData
            spacing: 6
            KeyCap { anchors.verticalCenter: parent.verticalCenter; label: modelData[0]; fontSize: 11 }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              font.family: Zenon.face
              font.pixelSize: 12
              color: Zenon.muted
              text: modelData[1]
            }
          }
        }
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
    keys: ["text/uri-list"]
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
      radius: 4
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
  function spliceOf(list) {
    let best = null;
    for (const s of list)
      if (s && s.cardInk > (best ? best.cardInk : 0.001)) best = s;
    return best;
  }
  readonly property var downSheet: win.spliceOf([keyHints, leader])
  readonly property var upSheet: win.spliceOf([picker, pluginPanel, settingsSheet])

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
    onGitClicked: nvim.cmd("Git")
    onLspClicked: win.ctx.lspMenu()
    onFormatClicked: win.ctx.formatMenu()
    treeShown: win.treeShown
    onTreeToggled: {
      if (!win.mgr) return;
      win.mgr.setTree(!win.mgr.treeShown);
      editor.forceActiveFocus();
    }
    // under the editor only: the tree runs the window's full height beside it
    anchors.left: editor.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    ed: st
    client: nvim
    font.family: Zenon.faceFixed
    font.pixelSize: win.chromeSize - 2
    // the tree toggle's size (Zenon.face); the bar's mono glyphs are drawn
    // a quarter larger (iconSize), which is where they read the same
    glyphSize: win.chromeSize - 1 + 4
  }

  Picker {
    backdrop: editor   // frosted over it — see morpheus/Sheet
    id: picker
    // terminus' sheets hang from the chrome: here, the tab strip
    fromTop: tabs.height
    ed: st
    client: nvim
    ctx: win.ctx
    finder: win.mgr ? win.mgr.finder : null
    codeFamily: win.mgr ? win.mgr.fontFamily : Zenon.faceFixed
    history: win.mgr
    face.family: Zenon.faceFixed
    face.pixelSize: win.chromeSize
    onClosed: editor.forceActiveFocus()
  }

  PluginPanel {
    backdrop: editor   // frosted over it — see morpheus/Sheet
    id: pluginPanel
    // terminus' sheets hang from the chrome: here, the tab strip
    fromTop: tabs.height
    plugins: win.mgr ? win.mgr.plugins : null
    filetype: st.filetype
    face.family: Zenon.faceFixed
    face.pixelSize: win.chromeSize
    onClosed: editor.forceActiveFocus()
    onConfigure: (path) => nvim.openAt(path)
  }
  SettingsSheet {
    backdrop: editor   // frosted over it — see morpheus/Sheet
    id: settingsSheet
    // terminus' sheets hang from the chrome: here, the tab strip
    fromTop: tabs.height
    settings: win.settings
    window: win
    face.family: Zenon.faceFixed
    face.pixelSize: win.chromeSize
    onClosed: editor.forceActiveFocus()
  }
  function showSettings() { settingsSheet.open(); }

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

  Component.onCompleted: editor.forceActiveFocus()
}
