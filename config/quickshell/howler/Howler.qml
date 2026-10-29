// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HOWLER — the notification daemon, and the only thing in this shell that
// talks to the freedesktop server. The toasts, the OSD and the bell's panel
// all read this; none of them owns a notification.
//
// WHAT LIVES WHERE. `live` is the server's own list — what is on screen right
// now, and what a dismiss acts on. `history` is a plain array of rows written
// to disk, which outlives both the notification and the session. They are
// deliberately different shapes: a Notification is an object owned by the
// server with methods and a lifetime, and a row is a fact about something
// that happened.
//
// THE PRESENTATION CONSTANTS ARE MAKO'S, ported one for one when this
// replaced it, and every one of them now reads out of oracle — so a setting
// is a binding away from the next toast rather than an edit and a reload.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Qt.labs.folderlistmodel
import "../oracle"
import "../morpheus"
import "../chronos"
import "howler.js" as Wolf
import "../morpheus/offspecial.js" as Off
import "../morpheus/hypr.js" as Hypr

Singleton {
  id: root

  // ── what is on screen ───────────────────────────────────────────────────
  readonly property var live: server.trackedNotifications

  // ── what is remembered ──────────────────────────────────────────────────
  // Newest first, so the panel draws it in the order it reads and the cap
  // takes from the end. Rows are plain objects — see Wolf.serialize for what
  // is allowed to be in one.
  property var history: []
  // Since the last time the panel was opened. The bell reads this.
  property int unread: 0

  // ── WHAT THIS SHELL SAYS TO ITSELF ──────────────────────────────────────
  // The app name ceres announces updates under — see Ceres.appName, which
  // passes exactly this to -a. Named here rather than matched inline so the
  // two ends of the arrangement can be found from either side.
  readonly property string selfUpdateApp: "ceres"
  // Oracle's sample toast, sent while the Notifications page is changed
  // (OracleWindow.sampleToast): shown even under Do not disturb — you are
  // looking for it — one at a time, and never kept in the bell
  readonly property string sampleApp: "oracle-sample"

  // ── mako's config, as settings ──────────────────────────────────────────
  readonly property int maxVisible:   Oracle.notifMaxVisible
  readonly property bool iconsEnabled: Oracle.notifIcons
  readonly property int iconSize:     Oracle.notifIconSize
  // Oracle's one Corner rounding, through Zenon's scale: a toast is a row
  readonly property int iconRadius:   Zenon.windowRadius
  readonly property int radius:       Zenon.windowRadius
  readonly property int padding:      Oracle.notifPadding
  // THE SIDES GET TWICE THE TOP. A card is wider than it is tall and a
  // gutter that reads as generous above a line of text reads as none at
  // all beside it — the bar's own tooltip is 20 and 10 for the same
  // reason. One knob still, doubled where it is spent horizontally.
  readonly property int hPadding:     Oracle.notifPadding * 2
  // AND THE PICTURE GETS HALF. Text needs air around it to stay off a
  // border; a picture has its own edge and only wants to be inside one.
  readonly property int iconPadding:  Math.round(Oracle.notifPadding / 2)
  readonly property int glowReach:    Oracle.notifGlowReach
  readonly property bool glowOn:      Oracle.notifGlow

  // ── A NAME OUT OF ORACLE, A COLOR OUT OF ZENON ────────────────────────
  // Oracle offers the palette by name because it cannot import Zenon; this is
  // the other half of that. An unknown name falls back to white rather than
  // to nothing — a toast drawn in "transparent" would be a notification you
  // could not read, which is a worse answer than the wrong color.
  function ink(name) {
    switch (String(name)) {
      case "white":   return Zenon.white;
      case "muted":   return Zenon.muted;
      case "surface": return Zenon.surface;
      case "red":     return Zenon.red;
      case "green":   return Zenon.green;
      case "yellow":  return Zenon.yellow;
      case "blue":    return Zenon.blue;
      case "magenta": return Zenon.magenta;
      case "cyan":    return Zenon.cyan;
      case "pink":    return Zenon.pink;
      case "sand":    return Zenon.sand;
    }
    return Zenon.white;
  }

  readonly property color accent:    Howler.ink(Oracle.notifAccent)
  readonly property color titleInk:  Howler.ink(Oracle.notifTitleInk)
  readonly property color bodyInk:   Howler.ink(Oracle.notifBodyInk)
  // Black at the chosen strength, which is what panelBgDeep was at a fixed
  // 0.70. Its own knob because a toast sits over whatever happens to be on
  // screen, which is not the job a panel has.
  readonly property color bg: Zenon.floor(Zenon.glass(Oracle.notifBgOpacity))

  // ── AND HOW IT ARRIVES ─────────────────────────────────────────────────
  // Zenon's own durations, scaled. Multiplied rather than replaced so the
  // shell's one motion setting still reaches the toasts — turn the desktop's
  // motion down and these come down with it.
  readonly property int openMs:
    Math.max(1, Math.round(Zenon.normal * Oracle.notifAnimSpeed))
  readonly property int closeMs:
    Math.max(1, Math.round(Zenon.fast * Oracle.notifAnimSpeed))
  // Only a slide travels. The vertical throw keeps the proportion the two
  // were first tuned at — 36 against 64 — so one number moves both.
  readonly property real slideBy:
    Oracle.notifAnimStyle === "slide" ? Oracle.notifSlide : 0
  readonly property real slideByV:
    Math.round(Howler.slideBy * 0.5625)
  // Where `scale` starts from. Far enough under one to read as growth,
  // near enough that the text is never illegibly small on the way in.
  readonly property real growFrom:
    Oracle.notifAnimStyle === "scale" ? 0.88 : 1.0
  readonly property int margin:       Oracle.notifSpacing
  // 1px, as every border is — see Zenon.border. Kept as a name because the
  // toast's layout reserves room for it in four places.
  readonly property int borderSize:   1
  readonly property int fontSize:     Oracle.notifFontSize
  readonly property int minHeight:    Oracle.notifMinHeight
  readonly property int maxHeight:    Oracle.notifMaxHeight
  readonly property int width:        Oracle.notifWidth
  readonly property int maxWidth:     Oracle.notifMaxWidth
  readonly property int captureWidth: Math.min(Oracle.notifMaxWidth, Oracle.notifCaptureWidth)
  readonly property int lift:         Oracle.notifLift
  readonly property bool markup:      Oracle.notifMarkup

  // Named in oracle rather than numbered — "center" is a thing a person can
  // choose, Text.AlignHCenter is a flag that happens to be 4 — so the
  // translation happens here, where Text is already in scope.
  readonly property int textAlign: {
    if (Oracle.notifTextAlign === "left") return Text.AlignLeft;
    if (Oracle.notifTextAlign === "right") return Text.AlignRight;
    return Text.AlignHCenter;
  }

  // mako's `[urgency=critical] default-timeout=0`. Off, a critical
  // notification expires on the ordinary timeout like anything else.
  function timeoutFor(urgency) {
    if (urgency === NotificationUrgency.Critical)
      return Oracle.notifCriticalSticky ? 0 : Oracle.notifTimeout;
    if (urgency === NotificationUrgency.Low) return Oracle.notifTimeoutLow;
    return Oracle.notifTimeout;
  }

  // ── WHICH NOTIFICATIONS CAME FROM A MUSIC PLAYER ───────────────────────
  // Matched against the MPRIS players actually running rather than against a
  // list of application names: the players that exist are knowable, and a
  // hardcoded list is wrong the moment somebody installs a different one.
  //
  // The answer is kept ON THE ROW, because it is a fact about the moment the
  // notification arrived — the player may well have exited by the time
  // anything reads the history back.
  function playerFor(notif) {
    const p = root.mprisFor(notif);
    if (!p) return "";
    const id = String(p.identity || "");
    return id !== "" ? id : String(notif.appName || "").toLowerCase();
  }

  // THE PLAYER ITSELF, for a toast that wants to drive it or draw its cover.
  // Spotify's own client sends a track toast with no picture and no transport
  // — "Artist — Album" and a Skip button — so both come from here instead.
  function mprisFor(notif) {
    if (!notif) return null;
    const entry = String(notif.desktopEntry || "");
    const name = String(notif.appName || "").toLowerCase();
    const summary = String(notif.summary || "");
    const players = Mpris.players ? Mpris.players.values : [];
    for (let i = 0; i < players.length; ++i) {
      const p = players[i];
      if (!p) continue;
      const id = String(p.identity || "");
      // THE TRACK ITSELF IS THE MATCH, and it has to be — the client that
      // sends the notification and the one that owns the MPRIS name are
      // routinely different programs. Measured here: spoot posts the
      // notification, spotifyd holds the bus name, and no amount of comparing
      // those two names will ever agree. What they do agree on is the song.
      if (summary !== "" && String(p.trackTitle || "") === summary) return p;
      if (entry !== "" && String(p.desktopEntry || "") === entry) return p;
      if (id !== "" && id.toLowerCase() === name) return p;
    }
    return null;
  }

  // ── WHAT A TRACK IS, BEYOND ITS NAME ────────────────────────────────────
  // Explicit and has-lyrics, asked of the network once per track by
  // trackfacts.py — spoot wrote these into its toast, nothing else does. Kept
  // by track for the session: a toast for the same song twice asks once.
  // A key holds `true` while its question is out, then the answer.
  property var facts: ({})
  property var factsQueue: []

  function factsKey(p) {
    if (!p) return "";
    const md = p.metadata || {};
    const tid = String(md["mpris:trackid"] || "");
    if (tid.indexOf("spotify") >= 0) return tid;
    const t = String(p.trackTitle || "");
    return t === "" ? "" : t + "\u0001" + String(p.trackArtist || "");
  }

  // Returns the key, so a toast can read root.facts[key] as it fills in.
  function askFacts(p) {
    const key = root.factsKey(p);
    if (key === "" || root.facts[key] !== undefined) return key;
    const md = p.metadata || {};
    const f = Object.assign({}, root.facts);
    f[key] = true;
    root.facts = f;
    root.factsQueue = root.factsQueue.concat([{ key: key, argv: [
      String(md["mpris:trackid"] || ""), String(md["xesam:url"] || ""),
      String(p.trackTitle || ""), String(p.trackArtist || ""),
      String(p.trackAlbum || ""),
      String(p.lengthSupported && p.length > 0 ? p.length : 0)
    ] }]);
    root.nextFacts();
    return key;
  }

  function nextFacts() {
    if (factsProc.running || root.factsQueue.length === 0) return;
    const job = root.factsQueue[0];
    root.factsQueue = root.factsQueue.slice(1);
    factsProc.key = job.key;
    factsProc.command = ["python3", "-I",
      Quickshell.shellDir + "/howler/trackfacts.py"].concat(job.argv);
    factsProc.running = true;
  }

  Process {
    id: factsProc
    property string key: ""
    stdout: StdioCollector {
      onStreamFinished: {
        let got = null;
        try { got = JSON.parse(this.text); } catch (e) { got = null; }
        const f = Object.assign({}, root.facts);
        f[factsProc.key] = got && typeof got === "object" ? got : {};
        root.facts = f;
      }
    }
    onExited: Qt.callLater(root.nextFacts)
  }

  // The marks a toast draws for a track, in the order spoot drew them:
  // liked, explicit, lyrics. Nothing at all until something is known.
  function factMarks(key) {
    const f = key !== "" ? root.facts[key] : null;
    if (!f || typeof f !== "object") return "";
    const out = [];
    if (f.liked === true) out.push(String.fromCodePoint(0xf02d1));
    if (f.explicit === true) out.push(String.fromCodePoint(0xf0b0c));
    if (f.lyrics === true) out.push(String.fromCodePoint(0xf0bc2));
    return out.join("  ");
  }

  // ── OPENING A PLAYER FROM ITS TOAST ─────────────────────────────────────
  // What a click on a track means when the sender attached no `default` of
  // its own. Its window is brought forward if it has one; Raise is asked as
  // well, which is what shows a player that was closed to the tray.
  function raisePlayer(p) {
    if (!p) return;
    if (p.canRaise) p.raise();
    const entry = String(p.desktopEntry || "").replace(/[^A-Za-z0-9._-]/g, "");
    if (entry !== "")
      // the player may live in the special: showing it is wanted here
      // (OffSpecial)
      Quickshell.execDetached(Off.wanted(Hypr.focusWindow(Hypr.byClass(entry))));
  }

  // ── A RECORDING'S FRAME, KEPT ───────────────────────────────────────────
  // The recorder writes its frame to the runtime directory, which is wiped at
  // logout — so a recording's row would lose its picture on the next boot.
  // Copied here as the row is made, and dropped once no row names it (see
  // `frames`). A screenshot needs none of this: its picture is its file.
  readonly property string framesDir: Paths.cacheDir() + "/quickshell/howler-frames"
  // The row keeps both: the original for the rest of this session (the copy
  // may not have landed when the panel first asks for it), the copy after.
  function keepFrame(src) {
    if (src.charAt(0) !== "/" || src.indexOf(root.framesDir + "/") === 0) return "";
    const dest = root.framesDir + "/" + Date.now() + "-" + src.split("/").pop();
    Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && cp -f "$2" "$3"',
      "sh", root.framesDir, src, dest]);
    return dest;
  }

  // ONCE, AT START: every frame in the directory that no row names is gone.
  // Listed here rather than by a shell glob, and removed by exact path — the
  // only things this can delete are pngs directly inside framesDir.
  FolderListModel {
    id: frames
    folder: "file://" + root.framesDir
    nameFilters: ["*.png"]
    showDirs: false
    showHidden: false
    property bool pruned: false
    onStatusChanged: if (status === FolderListModel.Ready) root.pruneFrames()
  }
  function pruneFrames() {
    if (frames.pruned || !root.historyRead || frames.status !== FolderListModel.Ready) return;
    frames.pruned = true;
    const keep = {};
    for (let i = 0; i < root.history.length; ++i) {
      keep[String(root.history[i].captureKept || "")] = true;
      keep[String(root.history[i].capturePicture || "")] = true;
    }
    const gone = [];
    for (let i = 0; i < frames.count; ++i) {
      const f = root.framesDir + "/" + frames.get(i, "fileName");
      if (!keep[f]) gone.push(f);
    }
    if (gone.length > 0) Quickshell.execDetached(["rm", "-f", "--"].concat(gone));
  }

  // THE COVER, ONLY ONCE THE PLAYER IS ON THIS TRACK. A toast can come in
  // ahead of the player's metadata — skip quickly and Spotify's toast for
  // the new song arrives while MPRIS still names the old one. mprisFor then
  // matches by player name, and its trackArtUrl is the LAST song's cover,
  // which the new toast and its row wore for good (user, 2026-10-17). So
  // the art is taken only while the titles agree; the toast's catchArt
  // takes it when they come to (and hands it to the row: rowArt).
  function artFor(notif) {
    const p = root.mprisFor(notif);
    if (!p || String(p.trackTitle || "") !== String(notif.summary || "")) return "";
    return String(p.trackArtUrl || "");
  }
  // the cover caught after arrival, into the history row that went without
  function rowArt(notif, art) {
    if (!notif || !art) return;
    for (let i = 0; i < root.history.length; ++i) {
      const r = root.history[i];
      if (r.id !== notif.id || r.summary !== String(notif.summary || "")) continue;
      if (r.image) return;
      const h = root.history.slice();
      h[i] = Object.assign({}, r, { image: art });
      root.history = h;
      saveTimer.restart();
      return;
    }
  }

  // ── A CALENDAR REMINDER'S COLOR (2026-10-28) ───────────────────────
  // Chronos sends the event's hue (Clio's stickies' seven) in
  // x-howler-event; the toast and its history row both draw it, in the
  // theme's own ink. "" for a hue it does not know: no reminder look.
  function eventInk(hue) {
    switch (String(hue || "")) {
      case "sand": return Zenon.sand;
      case "yellow": return Zenon.yellow;
      case "green": return Zenon.green;
      case "cyan": return Zenon.cyan;
      case "blue": return Zenon.blue;
      case "magenta": return Zenon.magenta;
      case "pink": return Zenon.pink;
    }
    return Zenon.cyan;
  }
  // "2026-10-28" → a Date (today when it does not read)
  function eventDayOf(iso) {
    const m = /^(\d{4})-(\d\d)-(\d\d)/.exec(String(iso || ""));
    return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : new Date();
  }

  // A NOTIFICATION'S OWN ICON, as an image source: a file by its path or
  // its file:// address (Claude sends file:///usr/lib/…/icon.png), a
  // themed name only when the theme has it — asked straight of
  // image://icon, a missing name came back as Qt's magenta and black
  // checkerboard (Oracle's "utilities-terminal", 2026-10-28). "" for none.
  // what stands in for an icon that is named and cannot be had — a theme
  // without it, a file that will not load: oct-question (user, 2026-10-28:
  // "instead of getting rid of the checkerboard, replace it")
  readonly property string missingGlyph: "\uF420"
  function iconSource(icon) {
    const s = String(icon || "");
    if (s === "") return "";
    if (s.indexOf("file://") === 0) return s;
    if (s.indexOf("/") === 0) return "file://" + s;
    return Quickshell.iconPath(s, true);
  }
  // A NOTIFICATION'S IMAGE, the same way: notify-send -i sends its icon as
  // the image-path hint too, which Quickshell hands over as image://icon/
  // <name or path> — Qt's checkerboard when there is no such thing. Through
  // iconSource instead, so a missing one is no image (and the question mark)
  function imageSource(image) {
    const s = String(image || "");
    if (s.indexOf("image://icon/") !== 0) return s;
    return root.iconSource(decodeURIComponent(s.slice("image://icon/".length)));
  }

  function rowOf(notif) {
    // A track with no picture of its own keeps its player's cover, as the
    // toast draws it. A web address survives a restart (Wolf.localImage),
    // which a provider handle would not.
    return {
      id: notif.id,
      time: Date.now(),
      appName: String(notif.appName || ""),
      appIcon: String(notif.appIcon || ""),
      image: root.imageSource(notif.image) || root.artFor(notif),
      // the image as sent, so a missing one still earns the question mark
      // (notify-send -i names its icon only as the image)
      rawImage: String(notif.image || ""),
      summary: String(notif.summary || ""),
      body: String(notif.body || ""),
      urgency: notif.urgency,
      desktopEntry: String(notif.desktopEntry || ""),
      mprisPlayer: root.playerFor(notif),
      // THE PICTURE A CAPTURE IS, by path. Its `image` is a provider handle
      // that dies with the toast, and a path in `image` is thrown away on
      // the way to disk (Wolf.keepable) — so a screenshot's row had no
      // picture at all. These are the capture's own files, which outlive
      // the session; see Wolf.capturePicture.
      capture: String((notif.hints || {})["x-howler-capture"] || ""),
      captureFile: String((notif.hints || {})["x-howler-file"] || ""),
      capturePicture: String((notif.hints || {})["x-howler-picture"] || ""),
      captureKept: root.keepFrame(String((notif.hints || {})["x-howler-picture"] || "")),
      // a calendar reminder's hue and day, so its history row keeps the
      // toast's look (the hints themselves are not kept)
      eventHue: String((notif.hints || {})["x-howler-event"] || ""),
      eventDay: String((notif.hints || {})["x-howler-day"] || "")
    };
  }

  // ── the server ──────────────────────────────────────────────────────────
  NotificationServer {
    id: server
    // Survive a config reload: editing a QML file should not silently swallow
    // whatever is on screen at the time.
    keepOnReload: true
    actionsSupported: true
    actionIconsSupported: true
    bodySupported: true
    bodyMarkupSupported: true
    imageSupported: true
    persistenceSupported: true
    // A CAPTURE SAYS SO IN ITS HINTS — what kind (`shot` or `video`), which
    // file, and for a recording which picture of it — and is drawn as its picture with buttons of its own. The
    // server drops every hint it was not asked to keep, so these are named.
    // Chronos' reminders name their hue and day the same way (dropped
    // until audit 2026-10-28d: the reminder look never showed)
    extraHints: ["x-howler-capture", "x-howler-file", "x-howler-picture", "x-howler-event", "x-howler-day"]

    onNotification: (notif) => {
      // TRACKED FIRST. An untracked notification is closed the moment this
      // handler returns, so nothing downstream would ever see it.
      notif.tracked = true;
      if (!Oracle.showNotifications) { notif.dismiss(); return; }

      // DO NOT DISTURB. Held back here, at the door, rather than hidden by
      // the stack: the stack is the server's own model, and filtering a copy
      // of it is what lost the toasts their animations once. Expired on the
      // next turn — not now: the server has not taken it into its model yet,
      // and closing it inside this handler would hand the model a dead one.
      // The stack draws a hushed toast as nothing for that one turn. A
      // critical one is the exception, as it is everywhere else.
      // the sample before it replaces any still up: one at a time
      const sample = notif.appName === root.sampleApp;
      if (sample) {
        const up = root.live ? root.live.values : [];
        for (const n of up) if (n && n !== notif && n.appName === root.sampleApp) Qt.callLater(() => n.expire());
      }
      if (root.quiet && !sample && notif.urgency !== NotificationUrgency.Critical) {
        if (root.focusState.fullscreen) root.heldInFullscreen = root.heldInFullscreen + 1;
        const h = Object.assign({}, root.hushed);
        h[notif.id] = true;
        root.hushed = h;
        Qt.callLater(() => notif.expire());
      }

      const row = root.rowOf(notif);
      // AFTER the model has taken it. Called straight from here, trim counts
      // the list as it was a moment ago — the notification being handled is
      // not in trackedNotifications yet — so it always left one too many on
      // screen: measured 3 showing with maxVisible at 2. Scheduled before the
      // early returns below, because those toasts are on screen too and the
      // cap was not being enforced for them.
      Qt.callLater(root.trim);
      // A track change is already spelled out in the bar, so by default it
      // toasts and is then forgotten rather than filling the bell with a
      // playlist.
      if (row.mprisPlayer !== "" && !Oracle.notifTrackMusic) return;

      // AND SO IS AN UPDATE COUNT, for the same reason and more strongly: this
      // one is not an application talking to you, it is this shell talking to
      // itself. The count is already on the bar and the full list is already
      // in its tooltip, so the bell was keeping a running tally of something
      // that is on screen anyway — and re-announcing it every time the number
      // moved, which on a rolling distribution is most days.
      //
      // It still TOASTS. The arrival is worth saying once; it is the keeping
      // that was wrong.
      if (row.appName === root.selfUpdateApp) return;
      if (row.appName === root.selfSummaryApp) return;
      if (sample) return;

      const h = root.history.slice();
      h.unshift(row);
      while (h.length > Oracle.notifHistoryCap) h.pop();
      root.history = h;
      root.unread = root.unread + 1;
      saveTimer.restart();
    }
  }

  // ── what the panels and the bar ask for ─────────────────────────────────
  // mako's max-visible, enforced where the list lives rather than by the view
  // slicing a copy. The stack can then be driven by the server's OWN model —
  // which is what makes a toast's arrival and departure animatable at all: a
  // JS array handed to a ListView is replaced wholesale on every change, and
  // a view that is reset has nothing to add or remove.
  function trim() {
    const v = root.live ? root.live.values : [];
    for (let i = 0; i < v.length - root.maxVisible; ++i)
      if (v[i]) v[i].expire();
  }

  function dismissAll() {
    // Backwards: dismissing mutates the list being walked.
    const v = root.live ? root.live.values : [];
    for (let i = v.length - 1; i >= 0; --i) if (v[i]) v[i].dismiss();
  }

  function clearHistory() {
    root.history = [];
    root.unread = 0;
    saveTimer.restart();
  }

  function markRead() { root.unread = 0; }

  // ── do not disturb ──────────────────────────────────────────────────────
  // The switch is oracle's (it survives a restart); the bell's right click,
  // the panel's glyph and `qs ipc call Howler silent` all flip that one
  // setting.
  readonly property bool silent: Oracle.notifSilent
  function toggleSilent() { Oracle.set("notifSilent", !Oracle.notifSilent); }

  // ── focus: quiet without being asked ────────────────────────────────────
  // Do not disturb above is the switch you flip; these are the two times
  // the bell goes quiet by itself (2026-10-21) — while a chronos timer
  // counts (Oracle's notifFocusTimers) and in quiet hours. `quiet` is what
  // holds a toast back; `quietWhy` says which, for the bell's tooltip.
  property int minuteOfDay: 0
  Timer {
    interval: 30000
    repeat: true
    running: Oracle.notifQuietHours
    triggeredOnStart: true
    onTriggered: { const d = new Date(); root.minuteOfDay = d.getHours() * 60 + d.getMinutes(); }
  }
  // FULL SCREEN (2026-10-25): the focused workspace has a full-screen
  // window. What it held back is counted, and said in one toast on leaving.
  // (=== true: the workspace can be there a moment before its flags are)
  readonly property bool fullscreenOn: !!Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen === true
  property int heldInFullscreen: 0
  onFullscreenOnChanged: {
    if (root.fullscreenOn || root.heldInFullscreen === 0) return;
    const n = root.heldInFullscreen;
    root.heldInFullscreen = 0;
    // words alone (user, 2026-10-26): the icon it asked for is not in every
    // icon theme, and a missing one drew as a black and magenta checkerboard
    Quickshell.execDetached(["notify-send", "--app-name=" + root.selfSummaryApp,
      n === 1 ? "1 notification came in" : n + " notifications came in",
      "While you were full screen. They are in the bell."]);
  }
  // the summary is the bell talking about itself: shown, not kept
  readonly property string selfSummaryApp: "Howler"
  readonly property var focusState: Wolf.focus({
    dnd: Oracle.notifSilent,
    timers: Oracle.notifFocusTimers, timerRunning: Chronos.anyRunning,
    fullscreen: Oracle.notifQuietFullscreen, fullscreenOn: root.fullscreenOn,
    hours: Oracle.notifQuietHours, fromH: Oracle.notifQuietFrom, toH: Oracle.notifQuietTo,
    minutesOfDay: root.minuteOfDay
  })
  readonly property bool quiet: root.focusState.quiet
  readonly property string quietWhy: root.focusState.why

  // ── the system bell (Hyprland 0.57) ─────────────────────────────────────
  // A terminal's BEL (xdg-system-bell) — not this bell, the panel. Hyprland
  // 0.57 began playing it itself; base.lua sets misc.bell_sound = "none" and
  // the sound is played here instead, so it keeps quiet whenever toasts do.
  // The same canberra theme sound Hyprland would have played. A program that
  // rings in a loop is heard at most four times a second.
  property real lastRing: 0
  Connections {
    target: Hyprland
    function onRawEvent(ev) {
      if (ev.name !== "bell" || root.quiet) return;
      const now = Date.now();
      if (now - root.lastRing < 250) return;
      root.lastRing = now;
      Quickshell.execDetached(["canberra-gtk-play", "-i", "bell", "-d", "Zenworks bell"]);
    }
  }
  function toggleFocusTimers() { Oracle.set("notifFocusTimers", !Oracle.notifFocusTimers); }
  function toggleQuietHours() { Oracle.set("notifQuietHours", !Oracle.notifQuietHours); }
  // Ids held back this session, so the stack can draw them as nothing for the
  // one turn they are in its model. Ids restart every session, and so does
  // this.
  property var hushed: ({})

  // The bell's panel carries its own switch for this, because deciding that a
  // playlist should stop filling the history is a thing you decide WHILE
  // looking at a history full of playlist. The setting is oracle's; this is
  // the same setting, reachable from where the problem is.
  readonly property bool trackMusic: Oracle.notifTrackMusic
  // Through Oracle.set, like every other setting: assigning the property
  // directly skipped the save and the revision bump, so the toggle was gone
  // at the next restart and oracle's own panel never saw it change.
  function toggleMusicTracking() {
    Oracle.set("notifTrackMusic", !Oracle.notifTrackMusic);
  }

  // ── WHAT A CAPTURE TOAST'S BUTTONS DO ───────────────────────────────────
  // Through each program's own IPC, the way clio and the viewer reach
  // terminus — howler asks, and the program that owns the verb does it. A
  // picture opens in picasso's viewer; a recording in whatever the desktop
  // plays video with, since nothing in this shell does.
  function captureOpen(kind, file) {
    if (file === "") return;
    Quickshell.execDetached(kind === "shot"
      ? ["qs", "ipc", "call", "Picasso", "view", file]
      : ["xdg-open", file]);
  }
  function captureReveal(file) {
    if (file !== "") Quickshell.execDetached(["qs", "ipc", "call", "Terminus", "reveal", file]);
  }
  // a recording, cut in argus' editor
  function captureEdit(file) {
    if (file !== "") Quickshell.execDetached(["qs", "ipc", "call", "Argus", "edit", file]);
  }
  function captureAnnotate(file) {
    if (file !== "") Quickshell.execDetached(["qs", "ipc", "call", "Picasso", "annotate", file]);
  }

  // ── OPENING A HISTORY ROW ───────────────────────────────────────────────
  // What a click on a toast opens, for a row of the bell's panel — which no
  // longer has the toast, and usually not the notification either. In order:
  // a capture opens its file; a notification still on the server answers as
  // its toast would (its `default`, else its first action); a track raises
  // its player; anything else brings its application's window forward, or
  // starts it when there is none. Returns whether it found anything to open.
  function openRow(row) {
    if (!row) return false;
    if (row.capture !== "" && row.captureFile !== "") {
      root.captureOpen(row.capture, row.captureFile);
      return true;
    }
    const v = root.live ? root.live.values : [];
    for (let i = 0; i < v.length; ++i) {
      const n = v[i];
      if (!n || n.id !== row.id || String(n.summary || "") !== row.summary) continue;
      const acts = n.actions || [];
      let a = null;
      for (let j = 0; j < acts.length; ++j)
        if (String(acts[j].identifier || "") === "default") a = acts[j];
      if (!a && acts.length > 0 && row.mprisPlayer === "") a = acts[0];
      if (a) { a.invoke(); return true; }
    }
    if (row.mprisPlayer && row.mprisPlayer !== "") {
      const ps = Mpris.players ? Mpris.players.values : [];
      for (let i = 0; i < ps.length; ++i)
        if (ps[i] && String(ps[i].identity || "") === row.mprisPlayer) {
          root.raisePlayer(ps[i]);
          return true;
        }
    }
    return root.focusOrLaunch(row.desktopEntry || String(row.appName || "").toLowerCase());
  }

  // its window forward if it has one (class, any case), else its .desktop
  function focusOrLaunch(entry) {
    const e = String(entry || "").replace(/[^A-Za-z0-9._-]/g, "");
    if (e === "") return false;
    const focus = Off.wanted(Hypr.focusWindow(Hypr.byClass(e))).map(Strings.shellQuote).join(" ");
    Quickshell.execDetached(["sh", "-c",
      "if hyprctl clients -j | jq -e --arg c \"$1\" "
      + "'any(.[]; (.class | ascii_downcase) == ($c | ascii_downcase))' >/dev/null 2>&1; then "
      + focus + "; else\n" + Desktop.launchCommand(e, "") + "fi",
      "sh", e]);
    return true;
  }

  // ONE row. A notification id is the server's, and the server numbers from
  // 1 again every session — so a history spanning restarts holds several
  // rows with the same id, and forgetting "by id" deleted all of them. The id
  // and the moment it arrived together name exactly one.
  function forget(row) {
    if (!row) return;
    const h = [];
    for (let i = 0; i < root.history.length; ++i) {
      const r = root.history[i];
      if (r === row || (r.id === row.id && r.time === row.time)) continue;
      h.push(r);
    }
    root.history = h;
    saveTimer.restart();
  }

  // ── persistence ─────────────────────────────────────────────────────────
  // Debounced, because a burst of notifications is one write rather than one
  // per row — and the rule about which images may be written down lives in
  // Wolf, applied on the way out AND on the way back in.
  FileView {
    id: stateFile
    path: Quickshell.statePath("howler-history.json")
    blockLoading: true
    printErrors: false
    // NO onLoaded. FileView re-reads after a write, and that reload can land
    // with a snapshot older than what is in memory — which clobbers the list
    // it was supposed to be persisting. Measured: three rows saved, one row
    // left. It is read ONCE below and memory is the truth from then on, which
    // is the shape chronos uses for the same reason.
  }

  Timer {
    id: saveTimer
    interval: 400
    onTriggered: stateFile.setText(Wolf.serialize(root.history))
  }

  // The prune waits on this: a listing that landed before the history was
  // read would have found every frame unnamed.
  property bool historyRead: false
  Component.onCompleted: {
    root.history = Wolf.parse(stateFile.text());
    root.historyRead = true;
    root.pruneFrames();
  }
}
