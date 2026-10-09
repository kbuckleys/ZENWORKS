// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TERMINUS' windows, and the one voice that speaks for them.
//
// There can be several now, which is the whole reason this file exists: two
// TerminusWindows would mean two IpcHandlers claiming the same "Terminus" target,
// and only one of them would win. So the handler lives out here and picks a
// window to act on, and the windows themselves carry no ipc at all.
//
// Window 0 is the one SUPER+E toggles and the one the portal is handed to. The
// rest are spares you asked for with N, and they retire when you close them.

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../morpheus/lagnotes.js" as LagNotes
import "terminus.js" as Terminus
import "tags.js" as Tags
import "collections.js" as Coll

Scope {
  id: mgr

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────
  // picasso's arrangement (see PicassoViewer): written into
  // ~/.local/share/applications on startup when missing, with this
  // machine's path to bin/terminus. It is what makes terminus a file
  // manager the rest of the desktop can name — oracle's Default Apps hands
  // it inode/directory, so another application's "show in directory" lands
  // here. One already there is left alone.
  Process {
    running: true
    command: ["sh", "-c", Desktop.installCommand("terminus", {
      Type: "Application",
      Name: "Terminus",
      GenericName: "File Manager",
      Comment: "Browse and manage files, in ZENWORKS",
      Icon: "system-file-manager",
      Categories: ["System", "FileTools", "FileManager", "Utility", "Core"],
      Keywords: ["files", "folder", "directory", "file manager", "explorer"],
      Exec: Desktop.execLine(Quickshell.shellDir + "/terminus/bin/terminus", "%f"),
      Terminal: "false",
      StartupNotify: "false",
      MimeType: ["inode/directory"]
    })]
  }

  // Windows are CREATED, not modelled.
  //
  // The first version put an Instantiator over a JS array of ids and pushed a
  // new id onto it. Replacing the array makes the Instantiator rebuild every
  // delegate, not just add one — so the second press destroyed the window you
  // already had (recreating it hidden, which read as "it closed the first
  // one") and built the rest from scratch at the same time. Exactly the bug
  // reported.
  //
  // createObject touches nothing that already exists, which is the whole
  // requirement here. `wins` holds the live objects so a binding on it — the
  // ipc handler's `w` — re-evaluates when one arrives or leaves; a function
  // call in a binding would not have.
  property var wins: []
  property int nextId: 0

  // alexandria's manager, handed in by shell.qml: a font file's Install in
  // the row menu goes through its queue (no window of its own needed)
  property var fontBook: null

  // The yank buffer, held here rather than in a window, so the windows
  // acknowledge each other: copy in one, paste in another. It was per-window
  // before, which meant two terminus windows side by side could not hand a file
  // between them at all — the only route was a drag, and dragging out of a
  // quickshell surface does not currently work.
  property var clipboard: null
  // The paths the last paste MOVED: the system clipboard still names them,
  // and a second `p` must not try to move what is already gone.
  property var spentClip: []

  // ── THE WINDOW IS NOT COMPILED AT STARTUP ─────────────────────────────
  // An inline `Component { TerminusWindow {} }` names the type at file
  // scope, and naming it is what makes the engine compile it during the
  // shell's own load. TerminusWindow.qml is 23,000 lines; measured, that
  // compile is 3.4s of a 4.7s cold start, and the bar does not reach the
  // screen until 4.2s. Everything you actually look at when you log in was
  // queued behind a file manager that is not on screen.
  //
  // MEASURED, because the obvious fix is not the fix. Handing
  // Qt.createComponent Component.Asynchronous during the shell's load
  // changes nothing at all — the engine waits for components created while
  // it is still loading, so the bar still arrived at 4.2s. It is the
  // DEFERRAL that does the work; asynchronous is what stops the deferred
  // compile from freezing the shell when it does run.
  //
  // With both: bar on screen at 1.1s, and the compile running off the GUI
  // thread afterwards without dropping a frame (measured on a 100ms
  // heartbeat: no gap over 250ms for the whole 3.4s).
  property var winComp: null
  property bool compiling: false

  // Requests that arrived before the type was ready. Never blocked: a
  // shell that freezes for three seconds because you pressed SUPER+E is
  // worse than one that takes a moment to show a window, and the window
  // appearing late looks like an application starting, which it is.
  property var pending: []

  readonly property bool compReady:
    mgr.winComp !== null && mgr.winComp.status === Component.Ready

  // Started off the critical path. The delay is not a guess at how long
  // startup takes — it is there because a component created during the
  // root document's load is waited for however it was asked for.
  Timer {
    id: compileSoon
    interval: 1200
    running: true
    repeat: false
    onTriggered: mgr.beginCompile()
  }

  function beginCompile() {
    if (mgr.compReady || mgr.compiling) return;
    mgr.compiling = true;
    mgr.winComp = Qt.createComponent("TerminusWindow.qml",
                                     Component.Asynchronous);
    if (mgr.winComp.status === Component.Loading)
      mgr.winComp.statusChanged.connect(mgr.compileSettled);
    else
      mgr.compileSettled();
  }

  function compileSettled() {
    if (!mgr.winComp || mgr.winComp.status === Component.Loading) return;
    mgr.compiling = false;
    if (mgr.winComp.status === Component.Error) {
      console.error("terminus: " + mgr.winComp.errorString());
      mgr.pending = [];
      return;
    }
    const q = mgr.pending;
    mgr.pending = [];
    for (let i = 0; i < q.length; ++i) mgr.fulfil(q[i]);

    // ── AND THE FIRST WINDOW, BUILT NOW AND HIDDEN ────────────────────
    // This used to be the opposite: nothing was built until something
    // asked, on the reasoning that instantiating the tree costs 750ms on
    // the GUI thread even incubated, and that a freeze five seconds after
    // login is worse than a slow login, because you are using the machine
    // by then.
    //
    // REVERSED DELIBERATELY. That reasoning trades a cost you notice
    // rarely for one you notice every single time you open the file
    // manager, and the file manager is opened far more often than the
    // machine is logged into. Until the 750ms itself comes down, it is
    // better spent while you are still looking at a desktop that has only
    // just appeared. A longer cold start beats a longer SUPER+E.
    //
    // HIDDEN, and that part is measured: an idle VISIBLE terminus window
    // costs the shell some 19 CPU points, and hiding it returns the shell
    // to its 3.67% baseline. A window standing by costs nothing until it
    // is on screen.
    //
    // The ipc `spawn` already reuses window 0 while it is hidden — see its
    // note — so this is the window SUPER+E gets, not one it leaves behind.
    if (mgr.wins.length === 0) mgr.prebuild();
  }

  // ── AND BUILT IN THE BACKGROUND ───────────────────────────────────────
  // Still all at once after the compile, that hidden window 0 was the one
  // big freeze left in lag.log: 745–791 ms on every shell start, the bar and
  // every popup stopped a second after login (2026-10-09). Incubated
  // asynchronously, the engine builds it in slices between frames — on a
  // smaller window measured offscreen, 126 ms in one piece became nothing
  // over 12 ms while it built and one ~50 ms finish.
  //
  // Anyone who needs a window before it is done gets it finished on the
  // spot (settle): they are waiting, so that is the old cost at the old
  // moment, and window 0 stays window 0 — never a second one made beside a
  // build still in flight.
  property var incubator: null
  function prebuild() {
    if (mgr.incubator || !mgr.compReady) return;
    const t0 = Date.now();
    const inc = mgr.winComp.incubateObject(mgr, { winId: mgr.nextId++, mgr: mgr, bootPath: "" },
                                           Qt.Asynchronous);
    if (!inc) return;
    mgr.incubator = inc;
    if (inc.status !== Component.Loading) { mgr.adopt(inc, t0); return; }
    inc.onStatusChanged = () => mgr.adopt(inc, t0);
  }
  function adopt(inc, t0) {
    if (mgr.incubator !== inc || inc.status === Component.Loading) return;
    mgr.incubator = null;
    if (inc.status !== Component.Ready || !inc.object) {
      console.error("terminus: the background window could not be built");
      return;
    }
    LagNotes.mark("terminus window, in the background over", t0);
    const next = mgr.wins.slice();
    next.unshift(inc.object);
    mgr.wins = next;
  }
  function settle() {
    const inc = mgr.incubator;
    if (!inc) return;
    if (inc.status === Component.Loading) inc.forceCompletion();
    mgr.adopt(inc, Date.now());
  }

  // The blocking path, kept for the ONE caller that cannot wait: the
  // portal hands back a window synchronously or the request fails, and a
  // failed picker is an application writing its file somewhere else.
  function ensureComp() {
    if (mgr.compReady) return mgr.winComp;
    mgr.winComp = Qt.createComponent("TerminusWindow.qml");
    mgr.compiling = false;
    if (mgr.winComp.status === Component.Error)
      console.error("terminus: " + mgr.winComp.errorString());
    return mgr.winComp;
  }

  // SHOWN FIRST, THEN THE DESTINATION, and the order is not cosmetic —
  // see the note on the ipc `open`. Being shown is what clears the
  // restored session, so a goTo that happens before it is undone by the
  // reset that follows: asking to open ~/Pictures landed on home.
  function fulfil(req) {
    const w = mgr.makeFor(req.path);
    if (!w) return;
    // held until it has something to show — see revealWhenReady
    if (req.show) w.revealWhenReady();
  }

  // ── DIRECTORY SIZES, SHARED ───────────────────────────────────────────────
  // Measured once by whichever window got there first, and handed to every
  // window made after it, so a second window's size column arrives filled.
  // ── WHAT IS EXPANDED, ONCE, FOR EVERY WINDOW ───────────────────────────
  // The end of a long line of fixes. Each window kept its own copy of the
  // open branches, saved it inside the view preferences on a 400ms debounce,
  // only window 0's copy counted, it was restored only with "restore
  // session" on and only after an asynchronous existence sieve, and a
  // listing that landed in the wrong place could prune it. Any one of those
  // lost an expand.
  //
  // Now there is ONE record, here, of every directory that is expanded:
  //   - every pane of every window reads it and writes it (the directory
  //     realm — collections and tag pages keep their own, as before);
  //   - it is written to its own file the moment it changes, so a restart,
  //     a kill or a crash cannot lose the last change;
  //   - it is always restored — this is terminus' rule, not a session option;
  //   - nothing prunes it. A directory that has gone simply never matches a
  //     row; the file is capped at the most recent `treeCap`, oldest first.
  //   - collapsing a directory removes only that directory, so what was open
  //     beneath it comes back when it is opened again.
  // Keys are "k:" + path, insertion order = recency, as openDirs always was.
  readonly property int treeCap: 1000
  property var tree: ({})

  FileView {
    id: treeFile
    path: Quickshell.statePath("terminus-tree.json")
    blockLoading: true
    printErrors: false
  }

  function setTree(next) {
    const keys = Object.keys(next || {});
    let m = next;
    if (keys.length > mgr.treeCap) {
      m = ({});
      for (const k of keys.slice(-mgr.treeCap)) m[k] = true;
    }
    mgr.tree = m;
    treeFile.setText(JSON.stringify(Object.keys(m).map((k) => k.slice(2))) + "\n");
  }

  function loadTree() {
    let list = null;
    try { list = JSON.parse(String(treeFile.text() || "")); } catch (e) { list = null; }
    // First run: carry over what the view preferences were holding, so the
    // expands already made are not lost to the move.
    if (!Array.isArray(list)) {
      list = [];
      try {
        const v = JSON.parse(String(viewPrefs.text() || "{}"));
        if (v && Array.isArray(v.paneOpen))
          for (const side of v.paneOpen)
            if (Array.isArray(side)) for (const p of side) list.push(p);
      } catch (e) {}
    }
    const m = ({});
    for (const p of list) if (typeof p === "string" && p !== "") m["k:" + p] = true;
    mgr.setTree(m);
  }

  FileView {
    id: viewPrefs
    path: Quickshell.statePath("terminus-view.json")
    blockLoading: true
    printErrors: false
  }

  Component.onCompleted: mgr.loadTree()

  // Capped, newest kept: every directory ever measured used to stay for the
  // session, copied whole on each update and into each new window. A fresh
  // measurement moves to the back, so what goes first is the stalest.
  readonly property int sizesCap: 5000
  property var sharedSizes: ({})
  function noteSizes(got) {
    const next = Object.assign({}, mgr.sharedSizes);
    for (const k in got) { delete next[k]; next[k] = got[k]; }
    const keys = Object.keys(next);
    for (let i = 0; i < keys.length - mgr.sizesCap; ++i) delete next[keys[i]];
    mgr.sharedSizes = next;
  }

  // ── ONE SPARE, KEPT; THE REST LET GO ───────────────────────────────────
  // Closing a window only hides it, and nothing ever destroyed a spare — so
  // every SUPER+E over an open window left one more hidden terminus in
  // memory for the rest of the session (four, the day this was found). Now
  // one hidden spare is kept, ready to be re-aimed the next time a second
  // window is asked for, and any other is destroyed. Window 0 is never
  // touched: it is the keybind's and the portal's.
  // ── A CLICK ON THE DESKTOP PUTS TERMINUS' MENUS AWAY ─────────────────
  // A click on another program ends terminus' turn as the active window,
  // and the menu goes with it. A click on the bare desktop does not — the
  // desktop is not a window, so nothing changes hands, and the menu stayed
  // up over it. The desktop IS icarus' surface, though, so shell.qml hears
  // the press and passes it here.
  function dismissMenus() {
    for (const w of mgr.wins) if (w && w.shown) w.dismissMenus();
    if (mgr.pickerWin && mgr.pickerWin.shown) mgr.pickerWin.dismissMenus();
  }

  // ── WHERE YOU WERE LAST, IN ANY WINDOW ────────────────────────────────
  // A new window used to open wherever IT had been — window 0 at its own
  // old directory, a spare at home — rather than where you had been. Work in
  // a second window for an afternoon, close it, press SUPER+E, and you were
  // back wherever window 0 was left hours ago; only a restart, which replays
  // the saved session, brought the last place back. So every window reports
  // where it is standing, and an unaimed open goes there.
  property string lastCwd: ""
  function noteCwd(path) {
    // not the inside of a mounted archive: it is unmounted once nothing
    // stands in it, and reopening there would be reopening on an error
    if (path && path !== "" && path.indexOf("/terminus/archives/") < 0) mgr.lastCwd = path;
  }

  // What SUPER+E does, and the bar's jobs module. Never hides.
  //
  // Window 0 is reused while it is hidden, so the first press does not leave
  // an unreachable hidden window behind a visible new one; after that every
  // press is a new window — a hidden spare re-aimed if there is one.
  function reveal(path) {
    mgr.settle();
    const aimed = path && path !== "";
    const want = aimed ? path : mgr.lastCwd;
    const first = mgr.wins.length > 0 ? mgr.wins[0] : null;
    if (first && !first.shown) {
      // Shown first: the clean slate a disabled "restore session" performs
      // happens on the way in, and the destination should land after it.
      // Only navigated when the place differs — a window that is merely
      // hidden is still where it was, and showing it again is not a journey
      // (an unconditional goTo once walked restored tabs back to home).
      first.shown = true;
      if (want !== "" && want !== first.cwd) first.goTo(want);
      first.takeFocus();
      return first;
    }
    const sp = mgr.spare();
    if (sp) {
      sp.goTo(want !== "" ? want : Paths.home());
      sp.revealWhenReady();
      return sp;
    }
    return mgr.spawn(want);
  }

  function noteHidden(w) {
    if (!w || w.winId === 0 || w.winId < 0) return;
    Qt.callLater(mgr.keepOneSpare);
  }
  function keepOneSpare() {
    let kept = false;
    for (const x of mgr.wins.slice()) {
      if (!x || x.winId === 0 || x.shown || x.holdReveal) continue;
      if (!kept) { kept = true; continue; }
      mgr.retire(x.winId);
    }
  }
  // The hidden spare, if there is one.
  function spare() {
    mgr.settle();
    for (const x of mgr.wins)
      if (x && x.winId > 0 && !x.shown && !x.holdReveal) return x;
    return null;
  }

  // Asks for a window, now or as soon as there is one. Returns the window
  // when it could be made immediately, and null when the caller will have
  // to wait — which for every caller here means "say so and move on".
  function request(path, show) {
    mgr.settle();
    if (mgr.compReady) {
      const req = { path: path || "", show: show === true };
      const before = mgr.wins.length;
      mgr.fulfil(req);
      return mgr.wins.length > before ? mgr.wins[mgr.wins.length - 1] : null;
    }
    mgr.pending.push({ path: path || "", show: show === true });
    mgr.beginCompile();
    return null;
  }

  // THE DESTINATION IS HANDED TO THE WINDOW, not applied to it afterwards.
  // A window restores its session ASYNCHRONOUSLY — it shells out to check
  // which stored directories still exist — so a goTo from out here worked
  // and was undone about a second later, which read as the request being
  // ignored. bootPath is what the window consults once its own restore has
  // settled; see takeBoot over there.
  function makeFor(path) {
    mgr.settle();
    if (!mgr.compReady) return null;
    const t0 = Date.now();
    const w = mgr.winComp.createObject(mgr, {
      winId: mgr.nextId++, mgr: mgr, bootPath: path || ""
    });
    LagNotes.mark("terminus window", t0);
    if (!w) return null;
    const next = mgr.wins.slice();
    next.push(w);
    mgr.wins = next;
    return w;
  }

  // Window 0, or null. A FUNCTION and not a property on the handler: an
  // IpcHandler exposes its declared properties over ipc, and a var is a
  // QVariant, which cannot cross that boundary — declaring one there logged
  // "Type QVariant cannot be used across IPC" on every load.
  function win() { mgr.settle(); return mgr.wins.length > 0 ? mgr.wins[0] : null; }

  // ── A WINDOW TO ASK, WHICH IS NOT THE SAME AS ONE TO SHOW ─────────────
  // The tag index and the collections live on a window, and since nothing
  // is built at startup any more there may not be one — which quietly
  // broke `Terminus tag ~/notes.md work` from a script when the file
  // manager happened to be closed.
  //
  // So a query builds one if it has to, HIDDEN, and blocks to do it. This
  // is the one place blocking is right: the caller wants an answer on
  // standard output and there is nothing to show them in the meantime.
  // Nothing is shown, so nothing appears on screen for a script that only
  // wanted to read a tag.
  function dataWin() {
    mgr.settle();
    const w = mgr.win();
    if (w) return w;
    const comp = mgr.ensureComp();
    if (!comp || comp.status !== Component.Ready) return null;
    return mgr.makeFor("");
  }

  function spawn(path) {
    return mgr.request(path && path !== "" ? path : Paths.home(), true);
  }

  function retire(id) {
    mgr.settle();
    // the last window is kept: it is the one the keybind and the portal reach,
    // and a manager with nothing in it has nowhere to put the next request
    // and window 0 is never retired, whatever else is open — see the note
    // above on the spare: every session-level thing (tab restore, the saved
    // session, the archive sweep) is window 0's, and with it gone they all
    // stopped
    if (mgr.wins.length < 2 || id === 0) return;
    const keep = [];
    let doomed = null;
    for (const w of mgr.wins) {
      if (w && w.winId === id) doomed = w;
      else keep.push(w);
    }
    if (!doomed) return;
    mgr.wins = keep;
    doomed.destroy();
  }

  // ── the portal's own window ─────────────────────────────────────────────
  // A file dialog is not the same object as your file manager.
  //
  // The portal used to be handed window 0, and the cost of that was hidden in
  // plain sight: a "save as" from a browser navigated the terminus you were
  // browsing in, flipped it to columns view, and hid it once you answered. If
  // window 0 happened to be open already, `shown = true` changed nothing and
  // no dialog ever came forward.
  //
  // So a request gets a window of its own, made on demand and destroyed when
  // it answers. It is deliberately NOT in `wins`: `win()` must stay "window
  // 0", `windows()` lists what you opened, and retire()'s keep-the-last guard
  // must not count a dialog as your last file manager.
  property var pickerWin: null

  // WHERE YOU LAST SAVED SOMETHING, held HERE rather than on the dialog.
  //
  // The dialog is destroyed the moment it answers, and the preference write
  // behind it is debounced — so a value recorded on the window went to the
  // grave with it every single time, and the next save opened wherever the
  // asking program suggested all over again. The manager outlives every
  // picker, which is the whole reason it is the one holding this.
  property string lastSaveDir: ""

  // Recorded, and asked to be written down. Window 0 owns the preferences
  // file; a dialog has no business writing it and will not be alive to.
  function noteSaveDir(d) {
    if (!d || d === "") return;
    mgr.lastSaveDir = d;
    const w = mgr.win();
    if (w) w.persistPrefs();
  }

  function picker() {
    // A DEAD POINTER IS NOT A WINDOW. The dialog can go away by routes this
    // manager never hears about — the compositor closing it, a destroy that
    // raced a new request — and a destroyed QObject held in a `var` does not
    // become null, it simply throws the moment anything is read off it. So the
    // stale pointer was handed the next request, setting `portal` on it threw,
    // the portal was never answered and never will be, and no dialog could be
    // opened again for the life of the shell.
    //
    // Reading one property is the only way to ask "are you still there".
    if (mgr.pickerWin) {
      try {
        if (mgr.pickerWin.winId === -1) return mgr.pickerWin;
      } catch (e) {
        // fall through and build a fresh one
      }
      mgr.pickerWin = null;
    }
    // winId -1 so the window knows it is a dialog rather than a file manager
    const comp = mgr.ensureComp();
    if (!comp || comp.status !== Component.Ready) return null;
    const t0 = Date.now();
    mgr.pickerWin = comp.createObject(mgr, { winId: -1, mgr: mgr });
    LagNotes.mark("terminus picker", t0);
    return mgr.pickerWin;
  }

  // ── THE SAME DIALOG, ASKED FROM INSIDE THE SHELL ─────────────────────
  // What the portal gets, for a caller that is not an application: oracle
  // choosing a background directory or a font file. The answer comes back to
  // `reply` as an array of paths — empty for a cancel — rather than through
  // a file and a `.done` marker, because there is no wrapper script waiting
  // on the other end.
  //
  // Refused while a portal request is open: that dialog is somebody else's
  // question, and taking it over would leave their application waiting on an
  // answer that is never coming.
  //
  // `saveName`, when given, makes it a SAVE dialog — a name field filled with
  // it, in `start` — for picasso's Save New. The answer is the full path the
  // file should be written to; nothing is created here, the caller writes it.
  //
  // `multiple` lets the answer be every file marked, not just the first —
  // alexandria's Open a font, which installs a batch.
  function choose(directory, start, reply, saveName, multiple) {
    const w = mgr.picker();
    if (!w || w.picking) return false;
    const saving = typeof saveName === "string" && saveName !== "";
    w.portal = {
      multiple: !!multiple && !directory && !saving,
      directory: !!directory && !saving,
      save: saving,
      suggested: "",
      out: "",
      reply: reply
    };
    w.goTo(start && start !== "" ? start : Paths.home());
    w.setSaveName(saving ? saveName : "");
    w.setView(w.pickerView);
    w.dual = false;
    w.shown = true;
    w.claimFocus();
    return true;
  }

  function retirePicker() {
    const w = mgr.pickerWin;
    if (!w) return;
    mgr.pickerWin = null;
    w.shown = false;
    // Deferred: retirePicker is reached from inside the window's own
    // portalAnswer, and destroying an object while its method is still on the
    // stack is the one way to turn a working dialog into a crash.
    Qt.callLater(() => { if (w) w.destroy(); });
  }

  // The reply is written HERE, not in the window that was asked, because that
  // window is destroyed the moment it answers — a Process owned by it would be
  // torn down mid-write and the portal would sit forever waiting on a `.done`
  // marker that never arrived.
  //
  // Queued for the same reason zeus' mixer queues its pactl calls: the log
  // shows requests arriving a second apart, and a second answer must not
  // reset the command of a process still writing the first.
  property var replies: []

  Process {
    id: answerProc
    onExited: mgr.drainReplies()
  }

  // `create` is set for a SAVE, and it is not optional.
  //
  // termfilechooser STATS the path the wrapper hands back, and refuses it if
  // nothing is there:
  //
  //     [ERROR] filechooser: failed to stat '…/suggested.png':
  //             No such file or directory
  //
  // A save names a file that does not exist yet — that is what a save IS — so
  // every save request was answered with a path the portal then threw away,
  // and the application received response code 2: not "the user cancelled" but
  // "the dialog failed". Firefox answers that by downloading into its own
  // last-used directory on its own, which is where the half-written file that
  // started all of this was coming from.
  //
  // So the chosen path is brought into existence before it is handed over.
  // Nothing is created until you have said where — this runs on confirm, at
  // the path you picked, and it is the file the application is about to fill.
  function answerPortal(out, paths, create) {
    if (!out || out === "") return;
    const make = (create && paths.length > 0)
      ? "mkdir -p -- " + Strings.shellQuote(Terminus.dirname(paths[0]))
        + " 2>/dev/null; touch -- " + Strings.shellQuote(paths[0])
        + " 2>/dev/null; "
      : "";
    const body = paths.length === 0 ? ":"
      : make + "printf '%s\n' " + paths.map((p) => Strings.shellQuote(p)).join(" ")
        + " > " + Strings.shellQuote(out);
    // the marker last, and always: it is what the wrapper is waiting on
    mgr.replies.push(["sh", "-c",
      body + "; : > " + Strings.shellQuote(out + ".done")]);
    mgr.drainReplies();
  }

  function drainReplies() {
    if (mgr.replies.length === 0 || answerProc.running) return;
    answerProc.command = mgr.replies.shift();
    answerProc.running = true;
  }

  // One window from the start, hidden, so there is always something for the
  // keybind to reveal.
  // Guarded, because a reload does not always start from nothing: quickshell
  // reuses what it can, and this ran again on a manager that still held its
  // windows — leaving a second one hidden in `wins` that nothing could reach,
  // since spawn() only ever reuses window 0.
  // Nothing is built here any more — see the note on winComp. The compile
  // starts on the timer above, and the first window is built by whatever
  // first asks for one.

    IpcHandler {
        target: "Terminus"


      function toggle(): string {
        const w = mgr.win();
        // No window yet means the type is still compiling, or nothing has
        // asked for one. Either way "toggle" means "show me one".
        if (!w) return mgr.request("", true) ? "open" : "opening";
        w.shown = !w.shown;
        if (w.shown) { w.refresh(); w.takeFocus(); }
        return w.shown ? "open" : "closed";
      }

      function open(path: string): string {
        const w = mgr.win();
        if (!w)
          return mgr.request(path === "" ? Paths.home() : path, true)
            ? "open" : "opening";
        // SHOWN FIRST, THEN THE DESTINATION. Being shown is what clears the
        // session when "restore session" is off, and a clear that lands after
        // the navigation undoes it — `Terminus open ~/Documents` opened at
        // home. Asking for somewhere always beats the reset.
        w.shown = true;
        w.goTo(path === "" ? Paths.home() : path);
        w.takeFocus();
        return w.cwd;
      }

      // "Show in terminus" from another app (plato's tree, picasso): the
      // directory a path is in, with the cursor on it. Through reveal(),
      // SUPER+E's way — a hidden window, else the spare, else a new one —
      // never by re-aiming a window that is open on some other workspace,
      // which went there and showed nothing where the asking was done.
      // Named `reveal`, not `show`: `qs ipc call Terminus show …` never
      // arrives — qs reads `show` as its own subcommand and rejects the path.
      function reveal(path: string): string {
        if (path === "") return "usage: reveal <path>";
        // "dir/" (a trailing slash) is the directory itself, no cursor aim
        if (/\/$/.test(path)) {
          const d = path.replace(/\/+$/, "") || "/";
          const w0 = mgr.reveal(d);
          return w0 ? d : "opening";
        }
        const p = path;
        const cut = p.lastIndexOf("/");
        const dir = cut > 0 ? p.slice(0, cut) : "/";
        const w = mgr.reveal(dir);
        // armed: the listing that lands next puts the cursor on it
        if (w) {
          w.wantSel = p;
          // already standing there: no listing is coming to take the aim
          if (w.cwd === dir) w.landWanted();
        }
        return w ? dir : "opening";
      }

      // ── tags ──────────────────────────────────────────────────────
      // Scriptable for the same reason `open` is: a file manager that can
      // be driven from a shell is one that can be driven from anything.
      // `Terminus tag ~/notes.md work` from a script is the same gesture as
      // the sheet, and it is also how this was tested before it had a sheet.
      function tag(path: string, name: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        if (path === "" || name === "") return "usage: tag <path> <name>";
        w.toggleTagFor([path], name);
        return "ok";
      }

      function tags(path: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        if (path !== "") return w.tagsFor(path).join(",");
        // No path: every tag that is on something, with its count.
        const counts = Tags.tally(w.tagMarks);
        const out = [];
        for (const k in counts) out.push(k + " (" + counts[k] + ")");
        return out.sort().join("\n");
      }

      // Opens the tag picker over whatever is selected, which is the same
      // thing c t does from the keyboard.
      function tagsheet(): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        w.shown = true;
        w.openTagPicker();
        return "ok";
      }

      // Lists everything carrying a tag, the same page clicking it in the
      // sidebar opens. Escape in the window returns to where you were.
      function tagopen(name: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        if (name === "") return "usage: tagopen <name>";
        w.shown = true;
        w.openTag(name);
        return "ok";
      }

      // Lists the saved collections, or opens one by name.
      function collection(name: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        // allCollections, not collections: the built-in Recents is
        // synthesised rather than stored — see recentsCollection — so
        // the stored list does not contain it and `Terminus collection
        // Recents` quietly matched nothing.
        const all = w.allCollections;
        if (name === "") {
          const out = [];
          for (let i = 0; i < all.length; ++i)
            out.push(all[i].name + "  \u2014  " + Coll.describe(all[i]));
          return out.length > 0 ? out.join("\n") : "none saved";
        }
        for (let i = 0; i < all.length; ++i) {
          if (all[i].name.toLowerCase() === name.toLowerCase()) {
            w.shown = true;
            w.goToCollection(all[i].id);
            return "ok";
          }
        }
        return "no such collection";
      }

      // The search sheet, as `s` opens it: "find" (names), "grep"
      // (contents), or "" to reopen on the last search.
      function search(kind: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        w.shown = true;
        w.beginSearch(kind);
        return "ok";
      }

      // Opens the collection editor — blank, or on the named directory.
      function collectionedit(name: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        w.shown = true;
        if (name === "") { w.openCollectionEditor(-1); return "new"; }
        const all = w.collections;
        for (let i = 0; i < all.length; ++i)
          if (all[i].name.toLowerCase() === name.toLowerCase()) {
            w.openCollectionEditor(all[i].id);
            return "ok";
          }
        return "no such collection";
      }

      // Renames a tag everywhere it appears. Merges into an existing name.
      function tagrename(from: string, to: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        if (from === "" || to === "") return "usage: tagrename <from> <to>";
        w.renameTag(from, to);
        return "ok";
      }

      // Opens the properties card, optionally on its permissions page —
      // the same card alt+return opens.
      function properties(page: string): string {
        const w = mgr.win();
        if (!w) return "no window";
        w.shown = true;
        w.openProperties(page === "permissions" ? 1 : 0);
        return "ok";
      }

      // Rebuilds the cache from the disk. Takes a root so a test does not
      // have to sweep $HOME to check one directory.
      function tagscan(where: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        w.rebuildTagIndex(where === "" ? Paths.home() : where);
        return "scanning " + (where === "" ? Paths.home() : where);
      }

      function cwd(): string {
        const w = mgr.win();
        if (!w) return "no window"; return w.cwd; }

      // What SUPER+E does. Never hides: a keybind called "open the file
      // manager" that closes it half the time is a coin toss, which is what
      // `toggle` was once there could be more than one window.
      //
      // Window 0 is reused while it is hidden, so the first press does not
      // leave an unreachable hidden window behind a visible new one. After
      // that every press is a new window.
      function spawn(path: string): string {
        const w = mgr.reveal(path);
        return w ? "window " + w.winId : "opening";
      }

      // Close one by id. `windows` is how you find the id.
      function close(id: int): string {
        mgr.retire(id);
        return mgr.wins.length + " window(s) left";
      }

      function windows(): string {
        mgr.settle();
        // `wins` holds the window OBJECTS now, not ids — looking each one up
        // by treating it as an id printed the QML type name instead
        let s = mgr.wins.length + " window(s):";
        for (const x of mgr.wins) {
          if (!x) { s += " [gone]"; continue; }
          s += " [" + x.winId + (x.shown ? " shown " : " hidden ") + x.cwd + "]";
        }
        // The picker is not one of `wins`, but "is there a dialog up?" is
        // exactly the question this is here to answer.
        const p = mgr.pickerWin;
        if (p) s += " + picker[" + (p.shown ? "shown " : "hidden ") + p.cwd + "]";
        return s;
      }

      // What it currently is, for when something is not behaving and the
      // question is which half is wrong. Every other layer here carries one.
      function status(): string {
        // The picker when there is one, because that is the half that is
        // usually being asked about; window 0 otherwise.
        const w = mgr.pickerWin ? mgr.pickerWin : mgr.win();
        if (!w) return "no window";
        return "collOpen=" + w.collOpenId + " tagOpen=" + w.openTagName
          + " mode=" + w.searchMode
          + " visible=" + w.shown
          + " focus=" + w.active
          + " preview=" + w.previewKind
          + " dual=" + w.dual
          + " other=" + w.otherCwd + "@" + w.otherSel
          + " side=" + w.paneSide + " split=" + w.paneFrac.toFixed(3)
          // paneL and paneR are ids, which nothing outside the window can
          // reach — reading them threw and took the whole report with it.
          // act/pas are public; which is the left one follows from paneSide.
          + " views=" + JSON.stringify((w.dual && w.paneSide === 1)
              ? [w.pas.viewMode, w.act.viewMode] : [w.act.viewMode, w.pas.viewMode])
          + " renaming=" + w.renaming
          + " marked=" + w.markedCount
          + " view=" + w.viewMode
          // STILL PICKING UNTIL THE ANSWER IS ON DISK.
          //
          // The wrapper polls this to decide whether its dialog is still up,
          // and treats picking=false without a .done marker as "closed without
          // answering" — it then DELETES the marker and hands the application
          // an empty file, which every application reads as cancel.
          //
          // portalAnswer clears `portal` and only then queues the write, so
          // there was a window of a frame or two where the dialog was gone and
          // the answer had not been written yet. A poll landing in it cancelled
          // a save that had actually been confirmed, and the asking program
          // fell back to the file it had already written in the directory it
          // suggested — which is how a save aimed at one directory ended up as
          // a half-written file in the last one.
          //
          // An answer in flight counts as still picking. It is the same
          // question the wrapper is really asking: is there an answer coming.
          + " picking=" + (w.picking || mgr.replies.length > 0
                           || answerProc.running)
          + " cwd=" + w.cwd
          + " rows=" + w.view.length
          + " sel=" + w.sel;
      }

      // Which layout, by name. `v` cycles them from the keyboard; this is the
      // same switch for anything that wants to open terminus already in the view
      // that suits what it is opening — a picture directory in grid, say.
      // The portal's request, handed over by the wrapper script. Everything is a
      // string because that is what ipc arguments are; "1"/"0" is the shape
      // xdg-desktop-portal-termfilechooser already uses for its own flags.
      function pick(multiple: string, directory: string, save: string,
                    path: string, out: string): string {
        // Everything that can throw happens BEFORE any window state is
        // assigned, and that ORDER is the bug this once had.
        //
        // `portal` was set first and Terminus.basename called second — and
        // terminus.js was not imported in this file, so every SAVE request threw
        // a ReferenceError right there. The window was left hidden with
        // picking=true, no dialog appeared, and the next SUPER+E hit spawn()'s
        // "reuse the hidden first window" path and revealed the stale picker
        // instead of a file manager. The portal log said it plainly: every
        // save=0 request answered "picking", every save=1 answered nothing.
        //
        // A save request arrives with a suggested FILE; the others arrive with
        // a directory to start in. Landing in the file's parent with its name
        // already in the field is what every other save dialog does.
        const saving = save === "1";
        let start = path;
        let suggested = "";
        if (saving && path !== "") {
          suggested = Terminus.basename(path);
          start = Terminus.dirname(path);
          // ── THE PORTAL'S UNDERSCORE IS NOT PART OF THE NAME ─────────
          // termfilechooser makes a placeholder at the suggested path, and
          // when a file by that name is already there it appends "_" until
          // it is not — so a second save of the same download arrives as
          // "clip.mp4_". portal.log shows it exactly: every underscored
          // request follows a save of that same name into that same directory.
          // The field took it verbatim, and the file landed with an
          // extension nothing recognises.
          //
          // Stripped only where what is left has a real extension, so a
          // name that genuinely ends in "_" keeps it. Clobbering is the
          // dialog's to warn about now — see saveClash in the window.
          const clean = suggested.replace(/_+$/, "");
          if (clean !== suggested && /[^.]\.[^./]+$/.test(clean))
            suggested = clean;
        }

        let w = mgr.picker();
        if (!w) return "no window";
        // A request already open is ANSWERED — cancelled — before this one
        // takes the window. Overwriting `portal` dropped the first request's
        // `out`, so its .done file was never written and the application
        // that asked first waited on it for good. Asked for again after,
        // because answering can retire a dedicated picker window.
        if (w.picking) {
          w.portalCancel();
          w = mgr.picker();
          if (!w) return "no window";
        }
        // WHERE YOU LAST SAVED beats where the program suggests — see
        // lastSaveDir in the window. The NAME still comes from the request:
        // the program knows what the file should be called, it just has no
        // idea where you keep things.
        if (saving && mgr.lastSaveDir !== "") start = mgr.lastSaveDir;
        w.portal = {
          multiple: multiple === "1",
          directory: directory === "1",
          save: saving,
          // The path the REQUEST named, kept whole. The dialog opens somewhere
          // else more often than not — see lastSaveDir below — but the file the
          // asking application has already written is at this path, and the
          // window needs it to know what not to list. See portalGhost there.
          suggested: saving ? path : "",
          out: out
        };
        w.goTo(start === "" ? Paths.home() : start);
        w.setSaveName(suggested);
        // The view this dialog was last left in, not a fixed one. Columns
        // is still the default — pickerView starts there — but a picker
        // that you switched to list stays a list next time. See
        // pickerView in the window; it is a slot of its own so a dialog
        // can remember without touching what the file manager remembers.
        w.setView(w.pickerView);
        // and one pane: a dialog picks a file, it does not move files about
        w.dual = false;
        w.shown = true;
        // Not takeFocus/focusSaveField: forcing focus on the frame `visible`
        // is set is dropped on the floor, because the surface is not mapped
        // yet. claimFocus keeps trying, and knows a save dialog wants the
        // name field rather than the listing.
        w.claimFocus();
        return "picking";
      }

      function view(mode: string): string {
        const w = mgr.win();
        if (!w) return "no window";
        w.setView(mode);
        return w.viewMode;
      }
    }
}
