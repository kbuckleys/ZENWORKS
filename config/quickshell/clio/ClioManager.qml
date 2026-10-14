// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CLIO'S NOTEBOOK — the notes app and the journal, beside the stickies.
// Apple's Notes and Journal in one window (ClioWindow): containers, tags,
// checklists, tables, pictures, sketches, locked notes; journal entries
// with moods, reflections, streaks and a calendar. The stickies stay what
// they are (Clio.qml, ClioBoard.qml) and show up in the window as the
// Stickies shelf: a note can be put on the desktop, a sticky taken into a
// container.
//
// THIS IS THE PART THAT IS ALWAYS IN THE SHELL, and it is small: the
// .desktop entry, the ipc (through Clio's own handler: `qs ipc call Clio
// open | journal | note`), the journal's reminder, and a window built on
// first use and let go when closed — plato's rule. The notes themselves
// are read when the window opens, from the backend (clio/core), which runs
// while the window is up.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../terminus"
import "../morpheus/lagnotes.js" as LagNotes
import "notes.js" as N
import "clio.js" as Scribe
import "../metis/metis.js" as Metis

Scope {
  id: mgr

  // terminus, handed in by shell.qml: its pickers and its opening of files
  property var fileManager: null
  // alexandria, to choose the notes' and the journal's typefaces
  property var fontBook: null

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────────
  // Not shipped: written on startup when missing, with this machine's path
  // (Desktop.installCommand), as every suite app's is.
  Process {
    running: true
    command: ["sh", "-c", Desktop.installCommand("clio", {
      Type: "Application",
      Name: "Clio",
      GenericName: "Notes",
      Comment: "Notes, checklists, a journal and the stickies on your desktop, in ZENWORKS",
      Icon: "accessories-text-editor",
      Categories: ["Office", "Utility"],
      Keywords: ["notes", "note", "journal", "diary", "sticky", "checklist", "todo", "memo", "write"],
      Exec: Desktop.execLine(Quickshell.shellDir + "/clio/bin/clio"),
      Terminal: "false",
      StartupNotify: "false",
    })]
  }

  Component.onCompleted: Clio.app = mgr

  // ── THE BACKEND ────────────────────────────────────────────────────────
  LineDaemon {
    id: line
    name: "clio"
    command: ["python3", Quickshell.shellDir + "/clio/bin/cliod"]
    protocol: 1
    goneText: "Clio's backend stopped"
    // the key went with it: every note it had opened is locked again
    onStopped: mgr.forgetOpen()
  }
  function call(op, args, done) {
    return line.request(op, { args: args || {} }, (ok, r, err) => { if (done) done(ok, r, err); });
  }

  // ── THE NOTEBOOK, IN MEMORY ────────────────────────────────────────────
  // Every note and entry, each with its `d` (notes.js derive): replaced
  // whole on every change, so whatever is bound to it follows.
  property var notes: []
  property var meta: N.cleanMeta({})
  readonly property var folders: mgr.meta.folders
  readonly property var journals: mgr.meta.journals
  readonly property var templates: mgr.meta.templates || []
  property bool loaded: false
  property bool loading: false
  property string root: ""
  // every note's pictures and files, in one directory they share
  readonly property string base: (mgr.root !== "" ? mgr.root : Clio.dir) + "/Attachments"
  // saves on their way to the disk: a reload waits for none
  property int _writing: 0
  // the lock: is a password set, and is it open now
  property bool hasPassword: false
  property string hint: ""
  property bool unlocked: false
  // sealed notes opened while unlocked: id → blocks
  property var opened: ({})
  signal reloaded()

  function load(then) {
    if (mgr.loading) return;
    mgr.loading = true;
    mgr.call("load", {}, (ok, r, err) => {
      mgr.loading = false;
      if (!ok) { console.warn("clio:", err ? err.error : "load failed"); return; }
      const list = [];
      for (const raw of r.notes) {
        const n = N.clean(raw);
        if (!n) continue;
        n.d = N.derive(n);
        list.push(n);
      }
      mgr.notes = list;
      mgr.meta = N.cleanMeta(r.meta);
      mgr.root = r.root;
      mgr.hasPassword = r.password;
      mgr.hint = r.hint || "";
      mgr.unlocked = r.unlocked;
      mgr.loaded = true;
      mgr.reloaded();
      if (then) then();
    });
  }
  // The Trash keeps what is in it until it is emptied, as terminus' does

  function noteOf(id) {
    for (const n of mgr.notes) if (n.id === id) return n;
    return null;
  }
  function put(n) {
    n.d = N.derive(mgr.opened[n.id] ? Object.assign({}, n, { blocks: mgr.opened[n.id] }) : n);
    const out = mgr.notes.slice();
    const i = out.findIndex((x) => x.id === n.id);
    if (i >= 0) out[i] = n; else out.push(n);
    mgr.notes = out;
  }

  // ── KEEPING ────────────────────────────────────────────────────────────
  // A note changed is put in memory at once and written a beat later — a
  // second change inside the beat is the same write.
  property var _pending: ({})
  function write(n) {
    const p = Object.assign({}, mgr._pending);
    p[n.id] = n;
    mgr._pending = p;
    writeTimer.restart();
  }
  Timer {
    id: writeTimer
    interval: 500
    onTriggered: mgr.flush()
  }
  function flush() {
    const p = mgr._pending;
    mgr._pending = ({});
    let held = false;
    for (const id in p) {
      const n = p[id];
      // one save of a note at a time: the next waits for the time on disk
      // the last one wrote (see saveOne, the sync guard)
      if (mgr._inflight[id]) { mgr._pending[id] = n; held = true; continue; }
      const sealed = !!n.locked;
      const out = N.stored(n);
      delete out.locked;
      if (sealed) {
        // a locked note is written sealed: its blocks are the ones opened
        const bs = mgr.opened[id];
        if (!bs) continue;      // not open: nothing new to write
        out.blocks = bs;
        delete out.sealed;
        out.title = n.d ? N.titleOf(Object.assign({}, n, { blocks: bs })) : out.title;
      }
      mgr.saveOne(id, out, sealed, n);
    }
    if (held) writeTimer.restart();
  }
  // one note to the disk, with the time its file had when read (`_disk`):
  // the backend writes it only if that is still the file's time. If the
  // file changed meanwhile (another machine), both are kept — what is here
  // as a copy beside it — and the one on disk is what is shown.
  property var _inflight: ({})
  signal conflicted(string id, string copy)
  function saveOne(id, out, sealed, n) {
    const now0 = mgr.noteOf(id);
    mgr._writing++;
    mgr._inflight[id] = true;
    mgr.call("save", { note: out, seal: sealed, expect: now0 && now0._disk ? now0._disk : 0 }, (ok, r, err) => {
      mgr._writing--;
      delete mgr._inflight[id];
      if (!ok) { mgr.failed("Could not save “" + (n.d ? n.d.title : "") + "”", err); return; }
      if (r.conflict) {
        const disk = N.clean(r.disk), copy = N.clean(r.copy);
        const o = Object.assign({}, mgr.opened);
        delete o[id];
        mgr.opened = o;
        delete mgr._pending[id];
        if (disk) mgr.put(disk);
        if (copy) mgr.put(copy);
        mgr.conflicted(id, copy ? copy.id : "");
        return;
      }
      const now = mgr.noteOf(id);
      if (now) now._disk = r.mtime;
      if (sealed && r.sealed && now) mgr.put(Object.assign({}, now, { sealed: r.sealed, blocks: null }));
    });
  }
  signal failure(string text)
  function failed(text, err) {
    const why = err && err.error ? err.error : "";
    console.warn("clio:", text, why);
    mgr.failure(text + (why ? " — " + why : ""));
  }

  // a note's blocks changed in the editor
  function setBlocks(id, blocks) {
    const n = mgr.noteOf(id);
    if (!n) return;
    const c = Object.assign({}, n, { modified: Date.now() });
    if (c.sealed) {
      const o = Object.assign({}, mgr.opened);
      o[id] = blocks;
      mgr.opened = o;
      c.locked = true;
    } else c.blocks = blocks;
    mgr.put(c);
    mgr.write(c);
  }
  // a field of a note (pinned, container, mood, date…), without touching
  // when it was last edited unless asked
  function setField(id, field, value, touch) {
    const n = mgr.noteOf(id);
    if (!n) return;
    const c = Object.assign({}, n);
    c[field] = value;
    if (touch) c.modified = Date.now();
    if (c.sealed) c.locked = true;
    mgr.put(c);
    if (c.sealed && !mgr.opened[id]) mgr.writeHead(c);
    else mgr.write(c);
  }
  // a sealed note not open: its head written, its sealed body as it was
  function writeHead(n) {
    const out = N.stored(n);
    delete out.locked;
    delete out.blocks;
    mgr.saveOne(n.id, out, false, n);
  }

  // ── MAKING, MOVING, LETTING GO ─────────────────────────────────────────
  property string startWith: "title"
  function newNote(folder, blocks) {
    const n = N.blankNote(folder || "", mgr.startWith);
    if (blocks && blocks.length) n.blocks = blocks;
    mgr.put(n);
    mgr.write(n);
    return n.id;
  }
  function newEntry(journal, date, prompt, blocks) {
    const n = N.blankEntry(journal || (mgr.journals[0] || {}).id || "journal", date, prompt);
    if (blocks && blocks.length) n.blocks = blocks;
    mgr.put(n);
    mgr.write(n);
    return n.id;
  }
  function duplicate(id) {
    const n = mgr.noteOf(id);
    if (!n || n.sealed) return "";
    const c = JSON.parse(JSON.stringify(N.stored(n)));
    c.id = N.newId(n.kind === "entry" ? "e" : "n");
    c.created = c.modified = Date.now();
    c.pinned = false;
    // its pictures and files the same ones: attachments are shared, and
    // stay while any note uses them
    mgr.put(c);
    mgr.write(c);
    return c.id;
  }
  function trash(id) { mgr.setField(id, "deleted", Date.now(), false); }
  function restore(id) {
    const n = mgr.noteOf(id);
    // a sticky deleted: back on the desktop where it stood, with its words
    if (n && n.fromDesktop && mgr.blocksOf(n)) {
      Clio.readd(Object.assign({}, n.fromDesktop, { text: N.stickyOf(mgr.blocksOf(n)) }));
      mgr.forget(id);
      return;
    }
    mgr.setField(id, "deleted", 0, false);
  }
  // a sticky to the Trash: a note with its words, remembering the rest
  function trashSticky(sid) {
    const i = Clio.indexOf(sid);
    if (i < 0) return "";
    const rec = Object.assign({}, Clio.notes[i]);
    const nid = mgr.newNote("", N.blocksOfSticky(rec.text));
    delete rec.text;
    mgr.setField(nid, "fromDesktop", rec, false);
    mgr.trash(nid);
    Clio.remove(sid);
    return nid;
  }
  // a note gone for good. Not called `destroy`: that name is every
  // QtObject's own, it won over this one, and it took the manager with it
  function forget(id) {
    mgr.notes = mgr.notes.filter((n) => n.id !== id);
    const p = Object.assign({}, mgr._pending);
    delete p[id];
    mgr._pending = p;
    mgr.call("remove", { id: id }, (ok, r, err) => { if (!ok) mgr.failed("Could not delete", err); });
  }
  function restoreAll() { for (const n of mgr.notes.slice()) if (n.deleted > 0) mgr.restore(n.id); }
  function emptyTrash() { for (const n of mgr.notes.slice()) if (n.deleted > 0) mgr.forget(n.id); }

  // ── TEMPLATES ──────────────────────────────────────────────────────────
  // a note kept to start others from (notes.js templateOf: no pictures or
  // files), and the one a day's journal entry starts from (`daily`)
  function addTemplate(name, blocks) {
    const t = { id: N.newId("t"), name: N.freeName(name || "Template", mgr.templates.map((x) => x.name)), blocks: N.templateOf(blocks) };
    mgr.setMeta({ templates: mgr.templates.concat([t]) });
    return t.id;
  }
  function deleteTemplate(id) { mgr.setMeta({ templates: mgr.templates.filter((t) => t.id !== id) }); }
  function setDaily(id) { mgr.setMeta({ daily: id || "" }); }
  function templateBlocks(id, ms) {
    const t = mgr.templates.find((x) => x.id === id);
    return t ? N.fillTemplate(t.blocks, ms || Date.now()) : null;
  }

  // ── FOLDERS AND JOURNALS ───────────────────────────────────────────────
  function writeMeta() { mgr._writing++; mgr.call("meta", { meta: mgr.meta }, (ok, r, err) => { mgr._writing--; if (!ok) mgr.failed("Could not save the containers", err); }); }
  // (a change of some of it: what is not named is kept as it was)
  function setMeta(m) { mgr.meta = N.cleanMeta(Object.assign({}, mgr.meta, m)); mgr.writeMeta(); }
  function addFolder(name, parent, query) {
    const f = { id: N.newId("f"), name: N.freeName(name || "New Container", mgr.folders.map((x) => x.name)), parent: parent || "" };
    if (query) f.query = query;
    mgr.setMeta({ folders: mgr.folders.concat([f]), journals: mgr.journals });
    return f.id;
  }
  function renameFolder(id, name) {
    mgr.setMeta({ folders: mgr.folders.map((f) => f.id === id ? Object.assign({}, f, { name: name }) : f), journals: mgr.journals });
  }
  function setFolderQuery(id, q) {
    mgr.setMeta({ folders: mgr.folders.map((f) => f.id === id ? Object.assign({}, f, { query: q }) : f), journals: mgr.journals });
  }
  function moveFolder(id, parent) {
    if (N.wouldLoop(mgr.folders, id, parent)) return false;
    mgr.setMeta({ folders: mgr.folders.map((f) => f.id === id ? Object.assign({}, f, { parent: parent }) : f), journals: mgr.journals });
    return true;
  }
  // a container deleted: its notes (and its subcontainers' notes) to the
  // Trash, as Apple's
  function deleteFolder(id) {
    const gone = N.subfolders(mgr.folders, id);
    for (const n of mgr.notes) if (n.kind === "note" && gone.indexOf(n.folder) >= 0 && !n.deleted) {
      const c = Object.assign({}, n, { deleted: Date.now(), folder: "" });
      if (c.sealed) c.locked = true;
      mgr.put(c);
      if (c.sealed && !mgr.opened[c.id]) mgr.writeHead(c); else mgr.write(c);
    }
    mgr.setMeta({ folders: mgr.folders.filter((f) => gone.indexOf(f.id) < 0), journals: mgr.journals });
  }
  function addJournal(name, hue) {
    const j = { id: N.newId("j"), name: N.freeName(name || "New Journal", mgr.journals.map((x) => x.name)), hue: hue || "cyan", locked: false };
    mgr.setMeta({ folders: mgr.folders, journals: mgr.journals.concat([j]) });
    return j.id;
  }
  function setJournal(id, fields) {
    mgr.setMeta({ folders: mgr.folders, journals: mgr.journals.map((j) => j.id === id ? Object.assign({}, j, fields) : j) });
  }
  function deleteJournal(id) {
    if (mgr.journals.length <= 1) return;
    for (const n of mgr.notes) if (n.kind === "entry" && n.journal === id && !n.deleted) mgr.trash(n.id);
    mgr.setMeta({ folders: mgr.folders, journals: mgr.journals.filter((j) => j.id !== id) });
  }
  function journalOf(id) { return mgr.journals.find((j) => j.id === id) || mgr.journals[0]; }

  // ── THE LOCK ───────────────────────────────────────────────────────────
  // A locked note is sealed on disk; unlocked (one password for every
  // note, as Apple's), its blocks are opened into `opened` and live only
  // in memory until Lock Now, the window closing, or the screen locking.
  function setPassword(pw, hint, old, done) {
    mgr.call("password", { password: pw, hint: hint || "", old: old || "" }, (ok, r, err) => {
      if (ok) { mgr.hasPassword = true; mgr.hint = hint || ""; mgr.unlocked = true; }
      if (done) done(ok, err);
    });
  }
  function unlock(pw, done) {
    mgr.call("unlock", { password: pw }, (ok, r, err) => {
      if (ok) { mgr.unlocked = true; lockTimer.restart(); }
      if (done) done(ok, err);
    });
  }
  function lockNow() {
    mgr.flush();
    mgr.call("lockNow", {}, () => {});
    mgr.forgetOpen();
  }
  function forgetOpen() {
    mgr.unlocked = false;
    mgr.opened = ({});
    // what was derived from opened blocks goes too
    mgr.notes = mgr.notes.map((n) => n.sealed ? Object.assign({}, n, { d: N.derive(n) }) : n);
  }
  // a sealed note's blocks, from the backend (unlocked first)
  function unseal(id, done) {
    if (mgr.opened[id]) { done(true, mgr.opened[id]); return; }
    mgr.call("unseal", { id: id }, (ok, r, err) => {
      if (!ok) { done(false, null, err); return; }
      const o = Object.assign({}, mgr.opened);
      o[id] = r.blocks;
      mgr.opened = o;
      const n = mgr.noteOf(id);
      if (n) mgr.put(Object.assign({}, n));
      lockTimer.restart();
      done(true, r.blocks);
    });
  }
  // a note locked: sealed under the password from now on
  function lockNote(id) {
    const n = mgr.noteOf(id);
    if (!n || n.sealed || !mgr.unlocked) return;
    const o = Object.assign({}, mgr.opened);
    o[id] = n.blocks;
    mgr.opened = o;
    const c = Object.assign({}, n, { locked: true, sealed: "pending", title: N.titleOf(n) });
    mgr.put(c);
    mgr.write(c);
  }
  // and the lock taken off: written plain again
  function unlockNote(id) {
    const n = mgr.noteOf(id);
    if (!n || !n.sealed) return;
    const bs = mgr.opened[id];
    if (!bs) return;
    const c = Object.assign({}, n, { blocks: bs });
    delete c.sealed;
    delete c.locked;
    delete c.title;
    const o = Object.assign({}, mgr.opened);
    delete o[id];
    mgr.opened = o;
    mgr.put(c);
    mgr.write(c);
  }
  function blocksOf(n) { return !n ? null : n.sealed ? mgr.opened[n.id] || null : n.blocks; }
  // locked again after a while unused (a setting; 0 never)
  property int lockAfter: 10
  Timer {
    id: lockTimer
    interval: Math.max(1, mgr.lockAfter) * 60000
    running: mgr.unlocked && mgr.lockAfter > 0
    onTriggered: mgr.lockNow()
  }
  function touchLock() { if (mgr.unlocked) lockTimer.restart(); }

  // ── FILES ──────────────────────────────────────────────────────────────
  function attach(id, path, done) {
    mgr.call("attach", { id: id, path: path }, (ok, r, err) => { if (!ok) mgr.failed("Could not attach " + path.replace(/.*\//, ""), err); done(ok ? r : null); });
  }
  function pasteImage(id, done) { mgr.call("pasteImage", { id: id }, (ok, r) => done(ok && !r.none ? r : null)); }
  function attachDir(id, name, done) { mgr.call("attachDir", { id: id, name: name }, (ok, r) => done(ok ? r : null)); }
  // the words in a picture of Clio's (tesseract), "" for none
  function ocr(src, done) { mgr.call("ocr", { src: src }, (ok, r) => done(ok ? r.text || "" : "")); }
  function copyText(t) { mgr.call("copyText", { text: t }, () => {}); }
  function exportNote(n, format, dir, done) {
    const bs = mgr.blocksOf(n);
    if (!bs) { done(false, "Unlock it first"); return; }
    const title = N.titleOf(n);
    const name = N.fileName(title, format === "markdown" ? "md" : format === "html" ? "html" : "txt");
    const stem = name.replace(/\.[^.]+$/, "");
    const files = bs.filter((b) => b.src).map((b) => [b.src, dir + "/" + stem + "/" + b.src]);
    const local = bs;
    const text = format === "markdown" ? N.markdownOf(local, encodeURIComponent(stem))
      : format === "html" ? N.pageOf(title, local, encodeURIComponent(stem))
      : N.textOf(local) + "\n";
    mgr.call("export", { path: dir + "/" + name, text: text, files: format === "text" ? [] : files },
             (ok, r, err) => done(ok, ok ? r.path : (err ? err.error : "")));
  }

  // ── MATH NOTES ─────────────────────────────────────────────────────────
  // A sum worked out by metis' own reading of it (Metis.prepare) and qalc
  // behind it — the same answer the calculator would give.
  function math(expr, done) {
    let prep;
    try { prep = Metis.prepare(expr, {}); } catch (e) { done(""); return; }
    if (!prep || prep.bad) { done(""); return; }
    if (prep.kind === "local") { done(String(prep.result || "")); return; }
    if (prep.kind !== "qalc" || !prep.expr) { done(""); return; }
    mathProc.queue.push({ prep: prep, done: done });
    mathProc.next();
  }
  Process {
    id: mathProc
    property var queue: []
    property var cur: null
    function next() {
      if (mathProc.running || mathProc.queue.length === 0) return;
      mathProc.cur = mathProc.queue.shift();
      const p = mathProc.cur.prep;
      mathProc.command = ["bash", "-c", Metis.calcScript(), "metis", p.expr, p.alt || "", p.target || ""];
      mathProc.running = true;
    }
    stdout: StdioCollector {
      id: mathOut
      waitForEnd: true
      onStreamFinished: {
        const c = mathProc.cur;
        mathProc.cur = null;
        if (c) {
          let r = {};
          try { r = Metis.readCalc(mathOut.text, c.prep); } catch (e) {}
          c.done(r && !r.bad && r.result ? String(r.result) : "");
        }
        Qt.callLater(mathProc.next);
      }
    }
  }

  // ── THE DESKTOP: CLIO'S STICKIES ───────────────────────────────────────
  // A sticky in the window is a note of kind "sticky", made fresh from
  // Clio.notes each time they change — they stay Clio's, and an edit here
  // is written back as the sticky's own text (notes.js stickyOf).
  readonly property var stickies: {
    const out = [];
    const all = Clio.notes;
    for (let i = all.length - 1; i >= 0; i--) {
      const s = all[i];
      const n = { id: "s:" + s.id, sticky: s.id, kind: "sticky", hue: s.hue, face: s.face || "", blocks: N.blocksOfSticky(s.text),
                  created: 0, modified: 0, deleted: 0, pinned: false, folder: "", order: i };
      n.d = N.derive(n);
      out.push(n);
    }
    return out;
  }
  function stickyOf(id) { return mgr.stickies.find((s) => s.id === id) || null; }
  function setStickyBlocks(id, blocks) {
    const s = mgr.stickyOf(id);
    if (s) Clio.set(s.sticky, "text", N.stickyOf(blocks));
  }
  // a note put on the desktop: a sticky with its words, the note to
  // the Trash (moved, as Apple's Move)
  function toDesktop(id) {
    const n = mgr.noteOf(id);
    const bs = mgr.blocksOf(n);
    if (!n || !bs) return "";
    const sid = Clio.addOnMain();
    Clio.set(sid, "text", N.stickyOf(bs));
    Clio.shown = true;
    mgr.trash(id);
    return "s:" + sid;
  }
  // and a sticky taken off it into a container
  function fromDesktop(id, folder) {
    const s = mgr.stickyOf(id);
    if (!s) return "";
    const nid = mgr.newNote(folder || "", s.blocks);
    Clio.remove(s.sticky);
    return nid;
  }
  function newSticky() { const sid = Clio.addOnMain(); Clio.shown = true; return "s:" + sid; }

  // ── SETTINGS ───────────────────────────────────────────────────────────
  property string sort: "modified"
  property string view: "list"           // list | gallery
  property bool groupByDate: true
  property bool sinkChecked: false
  property var scope: ({ shelf: "all" })
  property var shut: ({})
  property string journalFilter: ""
  property real textScale: 1
  // the typeface notes and journal entries are written in; "" is the
  // shell's own (Zenon.face), and follows it
  property string noteFace: ""
  property string journalFace: ""
  // the journal's reminder: on, at, on which days (0 Sunday … 6 Saturday)
  property bool remind: false
  property string remindAt: "21:00"
  property var remindDays: [0, 1, 2, 3, 4, 5, 6]
  property string remindedOn: ""
  FileView {
    id: stateFile
    path: Quickshell.statePath("clio-app.json")
    blockLoading: true
    printErrors: false
  }
  readonly property var _keys: ["sort", "view", "groupByDate", "sinkChecked", "scope", "shut", "journalFilter",
                                "textScale", "noteFace", "journalFace", "remind", "remindAt", "remindDays", "remindedOn", "told", "startWith", "lockAfter"]
  property bool _ready: false
  Component.onDestruction: if (keepTimer.running) mgr.keepNow()
  function readState() {
    try {
      const st = JSON.parse(stateFile.text() || "{}");
      for (const k of mgr._keys) if (st[k] !== undefined && typeof st[k] === typeof mgr[k]) mgr[k] = st[k];
    } catch (e) {}
    mgr._ready = true;
  }
  function set(key, value) {
    if (mgr[key] === value) return;
    mgr[key] = value;
    if (mgr._ready) keepTimer.restart();
  }
  function keepNow() {
    const o = {};
    for (const k of mgr._keys) o[k] = mgr[k];
    stateFile.setText(JSON.stringify(o));
  }
  Timer { id: keepTimer; interval: 400; onTriggered: mgr.keepNow() }

  // the face a note or an entry is written in; `journal` for entries
  function faceFor(journal) { return (journal ? mgr.journalFace : mgr.noteFace) || Zenon.face; }
  // alexandria opened to choose it: for every note, every entry, or the
  // one sticky (`n`, a note of kind "sticky" — its own face, as the board's
  // Typeface sets it)
  function chooseFace(journal, n) {
    if (!mgr.fontBook) return;
    if (n && n.kind === "sticky") {
      mgr.fontBook.pick({ title: "Font for this sticky", family: Clio.faceOf(n), weight: 400 },
                        (family) => Clio.set(n.sticky, "face", family));
      return;
    }
    const key = journal ? "journalFace" : "noteFace";
    mgr.fontBook.pick({ title: journal ? "Font for the journal" : "Font for notes", family: mgr.faceFor(journal), weight: 400 },
                      (family) => mgr.set(key, family));
  }

  // ── THE JOURNAL'S REMINDER ─────────────────────────────────────────────
  // Once a day, at its time, on its days, unless something was written
  // today already — a notification with a Write button.
  Timer {
    interval: 30000
    running: mgr.remind
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      const now = new Date();
      const today = N.dayKey(now.getTime());
      if (mgr.remindedOn === today || mgr.remindDays.indexOf(now.getDay()) < 0) return;
      const m = mgr.remindAt.match(/^(\d{1,2}):(\d{2})$/);
      if (!m || now.getHours() * 60 + now.getMinutes() < +m[1] * 60 + +m[2]) return;
      mgr.set("remindedOn", today);
      if (mgr.loaded && mgr.notes.some((n) => n.kind === "entry" && !n.deleted && N.dayKey(n.date) === today)) return;
      remindProc.command = ["notify-send", "-a", "clio", "-A", "write=Write", "Time to write", N.promptOfDay(Date.now())];
      remindProc.running = true;
    }
  }
  Process {
    id: remindProc
    stdout: StdioCollector {
      id: remindOut
      waitForEnd: true
      onStreamFinished: if (remindOut.text.trim() === "write") mgr.journal()
    }
  }

  // ── CHECKLIST REMINDERS ────────────────────────────────────────────────
  // An item with a time (its `due`) not ticked by then: a notification, once
  // (`told`, by note, time and words — so a reminder moved or reworded is
  // told again), with Open. The notebook is read a little after the shell
  // starts, so they are told whether the window has been opened or not.
  property var told: ({})
  Timer {
    interval: 15000
    running: true
    onTriggered: { if (!mgr._ready) mgr.readState(); if (!mgr.loaded) mgr.load(); }
  }
  Timer { interval: 30000; running: true; repeat: true; onTriggered: mgr.checkDue() }
  function checkDue() {
    if (!mgr.loaded || !mgr._ready) return;
    const now = Date.now();
    const all = mgr.notes.map((n) => n.sealed && mgr.opened[n.id] ? Object.assign({}, n, { blocks: mgr.opened[n.id] }) : n);
    const due = N.dueChecks(all, now, mgr.told);
    if (due.length === 0) return;
    // what was told a month ago is let go of
    const t = {};
    for (const k in mgr.told) if (+k.split("|")[1] > now - 30 * 86400000) t[k] = true;
    for (const d of due) {
      t[d.key] = true;
      const n = mgr.noteOf(d.id);
      notifier.createObject(mgr, { noteId: d.id,
        command: ["notify-send", "-a", "clio", "-A", "open=Open", "\u{F009F}  " + (d.h || "Reminder"),
                  "From “" + N.titleOf(n, "a note") + "” · " + N.dueText(d.due, now)] });
    }
    mgr.set("told", t);
  }
  Component {
    id: notifier
    Process {
      id: tell
      property string noteId: ""
      running: true
      stdout: StdioCollector {
        id: tellOut
        waitForEnd: true
        onStreamFinished: if (tellOut.text.trim() === "open") mgr.withWindow((w) => w.openNote(tell.noteId))
      }
      onExited: tell.destroy()
    }
  }

  // ── THE WINDOW ─────────────────────────────────────────────────────────
  // One, reused; floating (hypr/lua/rules.lua, title "clio").
  property var win: null
  property var _comp: null
  property var _waiting: []
  function _withComponent(fn) {
    if (mgr._comp && mgr._comp.status === Component.Ready) { fn(); return; }
    mgr._waiting.push(fn);
    if (mgr._comp) return;
    const comp = Qt.createComponent(Qt.resolvedUrl("ClioWindow.qml"), Component.Asynchronous);
    mgr._comp = comp;
    const settle = () => {
      if (comp.status === Component.Loading) return;
      const queued = mgr._waiting;
      mgr._waiting = [];
      if (comp.status !== Component.Ready) {
        console.warn("clio:", comp.errorString());
        mgr._comp = null;
        return;
      }
      for (const f of queued) f();
    };
    if (comp.status === Component.Loading) comp.statusChanged.connect(settle);
    else settle();
  }
  function withWindow(fn) {
    if (!mgr._ready) mgr.readState();
    mgr._withComponent(() => {
      let fresh = false;
      if (!mgr.win) {
        const t0 = Date.now();
        mgr.win = mgr._comp.createObject(mgr, { mgr: mgr });
        LagNotes.mark("clio window", t0);
        if (!mgr.win) return;
        fresh = true;
      }
      const go = () => {
        fn(mgr.win, fresh);
        mgr.win.visible = true;
        if (!fresh) Hyprland.dispatch('hl.dsp.focus({ window = "title:^(clio)$" })');
      };
      // A window opened afresh reads the notebook again, from where it is
      // written: what was copied in from another machine since shows up.
      // Not while anything of ours is still on its way to the disk.
      const settled = mgr._writing === 0 && Object.keys(mgr._pending).length === 0;
      if (!mgr.loaded || fresh && settled) mgr.load(go); else go();
    });
  }
  // its window closed: the notebook written, the lock shut, the type let go
  function retire(w) {
    mgr.flush();
    if (mgr.unlocked) mgr.lockNow();
    if (mgr.win === w) mgr.win = null;
    if (!mgr.win && mgr._waiting.length === 0) mgr._comp = null;
    line.release("window");
  }
  function hold() { line.hold("window"); }

  function open() { mgr.withWindow((w) => w.showUp()); }
  function journal() { mgr.withWindow((w) => w.newEntry()); }
  function today() { mgr.withWindow((w) => w.today()); }

  // ── QUICK NOTE ─────────────────────────────────────────────────────────
  // ClioCapture, made the first time it is asked for
  // (its component read then, not at the shell's start)
  property var _cap: null
  function capture() {
    if (!mgr._ready) mgr.readState();
    if (!mgr._cap) {
      const c = Qt.createComponent(Qt.resolvedUrl("ClioCapture.qml"));
      if (c.status !== Component.Ready) { console.warn("clio:", c.errorString()); return; }
      mgr._cap = c.createObject(mgr, { mgr: mgr });
    }
    if (mgr._cap) mgr._cap.show();
  }
  // said in the window when it is up
  function said(t) { if (mgr.win && mgr.win.visible) mgr.win.say(t); }
  // a note changed from outside the window (a quick note into today's
  // entry): the window shows it afresh if it is the one open
  signal changedHere(string id)
  // `blocks` added at the end of today's entry in the first journal — begun
  // (from the daily template) if it is not written yet, or locked
  function addToToday(blocks) {
    // what the window has typed and not yet kept, kept first
    if (mgr.win) mgr.win.commit();
    const j = (mgr.journals[0] || {}).id;
    const k = N.dayKey(Date.now());
    const e = mgr.notes.filter((n) => n.kind === "entry" && !n.deleted && !n.sealed && n.journal === j && N.dayKey(n.date) === k)
      .sort((a, b) => a.date - b.date)[0];
    if (e) {
      const bs = (e.blocks || []).slice();
      while (bs.length > 1 && bs[bs.length - 1].k === "body" && N.plain(bs[bs.length - 1].h).trim() === "") bs.pop();
      mgr.setBlocks(e.id, bs.concat(blocks));
      mgr.changedHere(e.id);
      mgr.said("Added to today's entry");
      return e.id;
    }
    const start = mgr.meta.daily ? mgr.templateBlocks(mgr.meta.daily) : [N.block("title", "")];
    const id = mgr.newEntry(j, 0, "", start.concat(blocks));
    mgr.said("Today's entry begun");
    return id;
  }
  function note() { mgr.withWindow((w) => w.newNote()); }
  // the stickies' own "Open in Clio": the Stickies shelf, on that one
  function openSticky(id) { mgr.withWindow((w) => w.openSticky("s:" + id)); }
}
