// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ORACLE — the one place this shell keeps an answer it was asked for.
//
// Every layer in here already had its own settings; what none of them had was
// a way to CHANGE one. A toast timeout was a readonly property in Howler, the
// idle lock was a literal inside socordia's listener array, the pill's corner
// was a token in Zenon — each of them correct, each of them requiring a text
// editor and a shell restart. This is the same set of numbers with a dial on
// the front of it.
//
// THE SHAPE, and why it is this shape:
//
//   Each setting is a REAL QML PROPERTY, not a row in a map. That is the whole
//   reason the wiring elsewhere is one line per setting: Howler says
//   `timeoutNormal: Oracle.notifTimeout` and is done — a binding, so changing
//   it here reaches the next toast without anything being told to reload. A
//   map would have made every consumer call a function, and a function call is
//   not a dependency: nothing would have updated until something else happened
//   to change.
//
//   `specs` is the same set again, described rather than valued: what a
//   setting is called, what it does, what kind of thing it is, and what range
//   it may take. That is what the panel draws itself from, so adding a setting
//   is a property and a spec and no UI at all.
//
//   The DEFAULTS are not written twice. They are read off the properties
//   themselves at startup, before the file is loaded — the declaration IS the
//   default, and there is no second copy of 4000 to drift away from the first.
//
// WHAT IS WRITTEN TO DISK is only what has been changed. See Ora.serialize:
// a file holding every default would quietly pin an install to the day it was
// first opened, and never see a default improved afterwards.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "oracle.js" as Ora
import "../morpheus/hypr.js" as Hypr
import "../morpheus/undo"

Singleton {
  id: root

  // Bumped on every write. The panel's rows read their value through get(),
  // which is a function call and therefore NOT a binding dependency — this is
  // the dependency they take instead, so a row repaints when its setting
  // changes underneath it (a reset, the file being reloaded, another row's
  // action). Nothing outside the panel needs it: everything else binds to the
  // properties directly and is updated by QML itself.
  property int revision: 0

  // ── the bar ───────────────────────────────────────────────────────────
  // morpheus, and the pill it lives in. The sizes are read through Zenon, so
  // every layer that measures itself against the bar follows them too.

  // The pill will not grow past this however much a layer asks for. 1000 is
  // what every layer was written against.
  property int barMaxWidth: 1000
  property int barTextSize: 18

  property int barSlot: 32
  property int barGap: 8
  // How far the pill floats off the bottom of the screen, and how much room
  // is kept between it and the windows above it. TWO NUMBERS, because they
  // are two different gaps: one is under the pill and one is over it, and
  // wanting the bar tucked against the edge while still breathing away from
  // your windows is a perfectly ordinary thing to want.
  property int barScreenPad: 6
  property int barWindowGap: 0
  property bool barBlur: true

  // Which edge the whole shell hangs off. Every layer opens out of the pill,
  // so this moves all of them together — along with the toast stack and the
  // direction a tooltip opens in. See Zenon.barTop, which is what they all
  // actually read.
  property string barPosition: "bottom"
  // the pill's end caps, and a module's own breathing room inside its slot
  property int barPadBar: 12
  property int barPadModule: 4
  // Which output the pill lives on, by name. Empty means the one
  // QS_STATUS_SCREEN names, and failing that the first screen there is — the
  // same order shell.qml has always resolved it in.
  property string barMonitor: ""
  // THE MAIN MONITOR: what every "Automatic" monitor means — the pill, Follow
  // Background, the lock screen's widgets, a window with no focused output to
  // open on. Empty is the leftmost screen (pickScreen says why not the first).
  property string mainMonitor: ""
  // Whether tiled windows are kept clear of the pill. Off, the pill floats
  // over whatever is underneath it and nothing on the desktop moves for it.
  property bool barReserveSpace: true
  // Autohide: the pill slides off its edge until the pointer touches that
  // edge (or a layer opens out of it), and while it is set nothing is
  // reserved for it — windows run under it, whatever Reserve space says.
  property bool barAutohide: false

  // The workspace strip (morpheus/WorkspaceStrip): a moment of the screen's
  // workspaces, low on it, every time the workspace changes.
  property bool workspaceStrip: true

  // What the pill actually shows. Each of these is the module's own `active`
  // ANDed with the switch, so turning one off is the same motion the module
  // already makes when it has nothing to say — it eases to zero width and the
  // pill shrink-wraps around what is left.
  property bool showUpdates: true
  property bool showNotifications: true
  property bool showWorkspaces: true
  property bool showClock: true
  property bool showNetwork: true
  property bool showGpu: true
  property bool showCpu: true
  property bool showMemory: true
  property bool showVolume: true
  property bool showNowPlaying: true
  property bool showStatus: true
  // hermes' connection icon; also turned off from the icon's own menu
  property bool showHermes: true
  // The system tray, which lives inside the workspace row and is revealed by
  // hovering it. Off, tray applications keep running and simply have nowhere
  // to appear.
  property bool showTray: true
  // The hover text on the bar's modules. Off, the bar is silent and you are
  // relying on the readings themselves — which for the meters is most of the
  // information anyway.
  property bool barTooltips: true

  // ── WHAT EVERY COMPONENT SHARES ───────────────────────────────────────
  // The Nerd Font FAMILY, without the cut. Zenon derives the three the shell
  // actually uses — " Propo" for labels, " Mono" for the lock's clock and the
  // mark, and the bare name for the column-aligned tables — because they have
  // to be one family or a panel looks like two fonts.
  //
  // Any family: a Nerd Font gets its three cuts, any other face is used as
  // it is — and either way the icons (glyphs in the private use area) are
  // JetBrainsMono Nerd Font's, through the fontconfig fallback rule
  // morpheus/GlyphFallback writes for this process.
  // SF Pro Text since 2026-10-08, the user's call, after a day on SF Pro
  // Display; Medium 16 the default since 2026-10-11, which every menu row
  // follows too (CardBody, terminus/RowMenu). The icons stay JetBrainsMono's
  // (GlyphFallback)
  property string fontFamily: "SF Pro Text"
  // the cut, as a CSS weight — see Zenon.weight. Medium is the default.
  property string fontWeight: "500"
  // the shell's text size — see Zenon.px, which every label's size goes
  // through. 16 is the size everything was drawn at before it existed, so
  // the default moves nothing.
  property int fontSize: 16
  // THE MONOSPACED FACE: whatever lays text out on a grid — kitty, plato,
  // code and file previews, logs, the system's "monospace". SF Mono SemiBold,
  // which kitty and plato wore before oracle set them (2026-10-17). Its size
  // is kitty's and the system's (in px; they read points, 3/4 of it), not
  // plato's — the editor keeps a size and a zoom of its own.
  property string monoFamily: "SF Mono"
  property string monoWeight: "600"
  property int monoSize: 16
  // lexi's text over the shell's, in pixels either way (lexi already draws
  // four larger) — its own size, as plato's editor and terminus' zoom have
  // theirs. Ctrl +/- in lexi, or here.
  property int lexiTextStep: 0

  // The palette every component paints with — see Zenon, which reads it.
  // "zenon" is the shell's own and needs no file; any other name is
  // themes/<name>.json, and whatever that file leaves out, or gets wrong,
  // is Zenon's.
  property string theme: "zenon"
  // what the Theme row offers: Zenon, then every file in themes/ (Ora.themeOptions);
  // a light one carries the light mark
  property var themeOptions: Ora.themeOptions("")

  // ── FOLLOW BACKGROUND ─────────────────────────────────────────────
  // The theme made from a background (picasso/FollowBackground). Its tone:
  // "auto" reads the picture's brightness, or always dark, or always light.
  property string followMode: "auto"
  // how much of the background's color the grounds and text take, 0..1
  property real followVivid: 0.5
  // whose background: "" is the first monitor (the leftmost)
  property string followMonitor: ""
  // a slideshow on that monitor changes the theme with every picture
  property bool followSlideshow: true

  // ── FOLLOW THE SUN ────────────────────────────────────────────────
  // What Follow Daytime wears by day and by night (any theme but itself,
  // Follow Background included). Sunrise and sunset are chronos' forecast's;
  // without one, 07:00 and 19:00.
  property string themeDay: "zenon-light"
  property string themeNight: "zenon"

  // ── ACCENT COLOR ──────────────────────────────────────────────────
  // "#rrggbb" laid over whatever theme is worn — Zenon, a file, Follow
  // Background, Follow Daytime's day and night alike — as its accent (the
  // cyan slot; Zenon.cyan). "" is the theme's own.
  property string accentColor: ""
  // a new background (the main monitor's, as Follow Background reads it)
  // puts the accent back to the theme's — picasso/FollowBackground
  property bool accentResetOnBackground: false
  // The Save button: the window asks for a name (nameFollowRequested, a
  // sheet pre-filled with followSuggest — the picture's name, which
  // picasso/FollowBackground keeps here), then saveFollowRequested carries
  // it to FollowBackground, which writes the palette to themes/. Oracle
  // cannot reach Zenon or picasso itself.
  property string followSuggest: ""
  signal nameFollowRequested()
  signal saveFollowRequested(string name)

  // ── WHERE YOUR OWN FILES LIVE ──────────────────────────────────────
  // The shell itself may sit read-only in /usr/share/zenworks (the AUR
  // package), or be a working copy; what you make or change goes under
  // ~/.config/zenworks either way — saved themes (themes/), the Hyprland
  // files these settings write (hypr/), Plato's editor, kitty's colors.
  // Shipped files stay beside the shell and are only read.
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  readonly property string zenworksDir: root.configHome + "/zenworks"
  readonly property string themesDir: root.zenworksDir + "/themes"

  // Delete on a CUSTOM theme's row in the Theme list (OracleWindow): to the
  // trash, not gone — a slip is one restore away. Whatever was wearing it
  // (the theme, Follow Daytime's day or night) goes back to its default.
  function deleteTheme(stem) {
    const opt = root.themeOptions.find((o) => o.value === stem);
    if (!opt || !opt.custom) return;
    if (root.theme === stem) root.set("theme", "zenon");
    if (root.themeDay === stem) root.set("themeDay", root.defaults.themeDay || "zenon-light");
    if (root.themeNight === stem) root.set("themeNight", root.defaults.themeNight || "zenon");
    themeDel.command = ["sh", "-c", "gio trash -- \"$1\" 2>/dev/null || rm -f -- \"$1\"",
                        "sh", root.themesDir + "/" + stem + ".json"];
    themeDel.running = true;
  }
  Process { id: themeDel; onExited: root.scanThemes() }

  // ── THE INSTALLED FONTS ──────────────────────────────────────────────
  // The Font row's families, from fontconfig (Ora.fontFamilies). Scanned at
  // startup and on entering the look section, like the themes.
  property var fontFamilies: []
  // the Monospace font row's: fontconfig's fixed-width families only
  property var monoFamilies: []
  function scanFonts() {
    if (!fontsProc.running) fontsProc.running = true;
    if (!monoFontsProc.running) monoFontsProc.running = true;
  }
  // ── A FONT INSTALLED WHILE THE SHELL RUNS ────────────────────────────
  // fontconfig sees it at once (fc-list is a new process each time), but
  // Qt read the installed fonts ONCE, at start: picked, a new family drew in
  // the fallback until a restart. So a family that was not there at the
  // first scan has its files handed to Qt as application fonts (a
  // FontLoader each), after which it draws like any other.
  property var _startFamilies: null
  property var _loadedFamilies: ({})
  function _registerNew(fams) {
    if (root._startFamilies === null) {
      const s = {};
      for (const f of fams) s[f] = true;
      root._startFamilies = s;
      return;
    }
    const fresh = fams.filter((f) => !root._startFamilies[f] && !root._loadedFamilies[f]);
    if (fresh.length === 0 || fontFilesProc.running) return;
    const seen = Object.assign({}, root._loadedFamilies);
    for (const f of fresh) seen[f] = true;
    root._loadedFamilies = seen;
    fontFilesProc.command = ["sh", "-c",
      "for f in \"$@\"; do fc-list \"$f\" file; done", "sh"].concat(fresh);
    fontFilesProc.running = true;
  }
  Process {
    id: fontFilesProc
    stdout: StdioCollector {
      id: fontFilesOut
      waitForEnd: true
      onStreamFinished: {
        const files = String(fontFilesOut.text).split("\n")
          .map((l) => l.replace(/:\s*$/, "").trim()).filter((l) => l !== "");
        for (const f of files)
          Qt.createQmlObject("import QtQuick; FontLoader { source: " + JSON.stringify("file://" + f) + " }",
                             root, "newFont");
      }
    }
  }
  Process {
    id: fontsProc
    command: ["fc-list", ":", "family"]
    stdout: StdioCollector {
      id: fontsOut
      waitForEnd: true
      onStreamFinished: {
        root.fontFamilies = Ora.fontFamilies(fontsOut.text);
        root._registerNew(String(fontsOut.text).split("\n")
          .map((l) => l.split(",")[0].trim()).filter((l) => l !== ""));
      }
    }
  }
  Process {
    id: monoFontsProc
    // 100 is mono, 90 dual-width (CJK-wide mono faces)
    command: ["sh", "-c", "fc-list :spacing=100 family; fc-list :spacing=90 family"]
    stdout: StdioCollector {
      id: monoFontsOut
      waitForEnd: true
      onStreamFinished: root.monoFamilies = Ora.fontFamilies(monoFontsOut.text)
    }
  }
  onFontFamiliesChanged: if (root.defaultsTaken) root.buildSchema()
  onMonoFamiliesChanged: if (root.defaultsTaken) root.buildSchema()
  // a family row's weight, for the font book and a picked file's cut
  readonly property var weightKeyOf: ({ fontFamily: "fontWeight", monoFamily: "monoWeight" })

  function scanThemes() {
    if (!themeProc.running) themeProc.running = true;
  }

  Process {
    id: themeProc
    // one line per file: its stem, a tab, the file flattened to one line —
    // the shipped ones, then yours (one of yours by a shipped one's name is
    // the one worn, see Zenon's ownFile, so the shipped one is left out)
    command: ["sh", "-c",
      "for f in \"$1\"/*.json \"$2\"/*.json; do [ -f \"$f\" ] || continue; s=\"$(basename \"$f\" .json)\"; "
      + "[ \"${f%/*}\" = \"$1\" ] && [ -f \"$2/$s.json\" ] && continue; "
      + "printf '%s\\t' \"$s\"; tr '\\n' ' ' < \"$f\"; echo; done",
      "sh", Quickshell.shellDir + "/themes", root.themesDir]
    stdout: StdioCollector {
      id: themeOut
      waitForEnd: true
      onStreamFinished: root.themeOptions = Ora.themeOptions(themeOut.text)
    }
  }
  onThemeOptionsChanged: if (root.defaultsTaken) root.buildSchema()

  // THE ONE CORNER (user, 2026-10-21). Every rounded thing in the suite —
  // buttons, rows, cards, dialogs, menus, the pill, toasts, the OSD, scroll
  // thumbs — and hyprland's own windows take their radius from this. It is a
  // window's corner; Zenon's radius scale keeps each size's proportion to it,
  // so 5 is the look the suite had before, and 0 is square everywhere. There
  // used to be four (bar, menu, toast, toast icon) and none reached a window.
  property int cornerRadius: 5

  // ── how it is painted ─────────────────────────────────────────────────
  // Alpha over black, both of them. Hyprland's blur has an `ignore_alpha`
  // threshold — 0.5 on this machine — so a surface taken past that stops being
  // blurred and becomes a flat panel. That is a legitimate thing to want; it
  // is just worth knowing which side of the line you are on.
  // the user's own setting as the default (user, 2026-10-17)
  property real barOpacity: 0.9
  property real panelOpacity: 0.90
  // How heavy a shadow a layer casts, and a menu. They are deliberately two
  // numbers: a layer sits near an edge and a shadow loud enough to lift it off
  // the desktop reads as a black halo, while a menu floats over a window and
  // the same number reads as no shadow at all.
  property real shadowStrength: 0.60
  // A menu's own ground — and quick look's, which is the same kind of
  // surface. It was opaque by default; menus are frosted now, at quick
  // look's 0.60, as a blanket rule: every menu is its own layer or popup
  // surface, and hyprland frosts what is behind those. Zenon holds it
  // above the blur floor whatever this says.
  // Defaults 0.90 panel / 0.80 menu since 2026-10-09 (user's call).
  property real menuOpacity: 0.80
  // Every scrollbar in the shell (morpheus/Scrollbar) fades out once the
  // list stops moving, and comes back on a scroll or under the pointer. Off,
  // the thumb is always faintly there, as it used to be.
  property bool scrollbarAutohide: true
  // ScrollEdge: rows past a list's edge, frosted under the bar over them.
  // Off, every list stops at its edge and nothing is captured or blurred.
  property bool scrollFrost: true
  property bool menuShadows: true
  // morpheus/Elastic's rubber band past a list's ends (user, 2026-10-14):
  // on by default; off, the wheel and the fingers stop dead at the edge
  property bool elasticScroll: true
  // the cursor glides from row to row in every list (morpheus/CursorBand,
  // terminus' SelectBar); off, it jumps. One switch for the shell, not one
  // per app (user, 2026-10-19); on by default
  property bool cursorSlide: true
  // how much of the background's accent the glass is laid in (Zenon.glassBase)
  property real wallpaperTint: 0
  // RECORDING (argus.lua asks for these through `qs ipc call Argus
  // recPrefs`, 2026-10-22): a countdown first; which sound goes in; a
  // bigger pointer and the camera in a corner while it records
  property int recCountdown: 3
  property string recAudio: "system"
  property bool recBigPointer: false
  property bool recCamera: false
  property string recCameraCorner: "bottomRight"

  // ── motion ────────────────────────────────────────────────────────────
  // One multiplier over Zenon's three durations, so the whole shell speeds up
  // or slows down together and the layers cannot fall out of step with the
  // pill they are morphing out of. Zero is not a degenerate case here: it is
  // the setting for a machine where every animation is one frame.
  property real motionScale: 1.0
  property bool arrivalEnabled: true
  property int arrivalDuration: 750
  // The deadline the session's first animation aims at — see Arrival, where
  // the measurements behind 2200 are written down.
  property int arrivalDeadline: 2200

  // ── notifications ─────────────────────────────────────────────────────
  // howler's ported mako config, with the parts worth changing brought out.
  property int notifTimeout: 4000
  property int notifTimeoutLow: 4000
  // mako's `[urgency=critical] default-timeout=0`. Off, a critical
  // notification expires on the ordinary timeout like anything else.
  property bool notifCriticalSticky: true
  property int notifMaxVisible: 5
  property bool notifIcons: true
  // The album art is the thing you recognize a track toast by from across
  // the room, and it was sitting small inside a wide gutter. Ninety-six
  // against a twelve-pixel inset fills the card's height the way mako's
  // max-icon-size does.
  property int notifIconSize: 96
  // A FLOOR, NOT A WIDTH. The card measures its own text and takes what it
  // needs; this is only how narrow it is allowed to get, so a two-word
  // notification still reads as a panel. Four hundred made it the width of
  // everything instead, which is the opposite of fitting.
  property int notifWidth: 200
  property int notifMaxWidth: 800
  // A SCREENSHOT OR A RECORDING IS ITS PICTURE. That toast is the capture
  // and nothing else, so it wants room to be recognized in rather than the
  // width its words would earn — this wide, unless maximum width says less,
  // and narrower still when a tall capture would pass the maximum height.
  property int notifCaptureWidth: 480
  // how far the stack floats above the pill
  property int notifLift: 20
  // whether a music player's track change earns a row in the bell's history.
  // Off by default: the track name is already in the bar.
  property bool notifTrackMusic: false
  // the bell with nothing in its history: kept on the bar (the default), or
  // folded away until something arrives. Also in the bell's right-click menu.
  property bool notifBellAlways: true
  // Do not disturb: toasts are held back (a critical one still shows) and
  // everything still lands in the bell's history, unread.
  property bool notifSilent: false
  // FOCUS (2026-10-21): quiet without being asked — while a chronos timer
  // counts, and in quiet hours (whole hours, crossing midnight as 22 → 7).
  // Critical notifications come through, as through Do not disturb.
  property bool notifFocusTimers: false
  // and while the window in front is full screen (2026-10-25): a game, a
  // film; on leaving it, one toast says how many came in
  property bool notifQuietFullscreen: true
  property bool notifQuietHours: false
  property int notifQuietFrom: 22
  property int notifQuietTo: 7
  property int notifHistoryCap: 200
  // The card's gutter on every side, and the icon's from the text. Five put
  // the longest line of a list six pixels off the border; a toast is a panel
  // and reads like one at a dozen.
  property int notifPadding: 12
  // the space between two stacked toasts
  property int notifSpacing: 2
  property int notifFontSize: 16
  // mako's text-alignment
  property string notifTextAlign: "center"
  // nothing shorter than this, so a one-word notification still reads as a
  // panel rather than as a strip
  property int notifMinHeight: 64
  // mako: markup=1 — whether an application's <b> and <i> are honored or
  // shown as the characters they are
  property bool notifMarkup: true

  // ── THE PALETTE, OFFERED AS CHOICES ───────────────────────────────────
  // Names only. Oracle cannot import Zenon — Zenon imports Oracle — and does
  // not need to: what a row offers is a list of names, and the component
  // drawing the thing is what turns a name into a color. Shared, so every
  // "which color" row anywhere in this file offers the same set in the same
  // order rather than each listing the palette again.
  readonly property var inkOptions: [
    { value: "white",   label: "White" },
    { value: "muted",   label: "Muted" },
    { value: "surface", label: "Surface" },
    { value: "red",     label: "Red" },
    { value: "green",   label: "Green" },
    { value: "yellow",  label: "Yellow" },
    { value: "blue",    label: "Blue" },
    { value: "magenta", label: "Magenta" },
    { value: "cyan",    label: "Cyan" },
    { value: "pink",    label: "Pink" },
    { value: "sand",    label: "Sand" }
  ]

  // ── what a toast is made of ───────────────────────────────────────────
  // NAMED OUT OF THE PALETTE, not written as hex. Every one of these is a
  // zenon color, so a toast cannot be set to something the rest of the
  // desktop has never heard of, and changing the palette moves the toasts
  // with it. It also means no new kind of control: these are enums, and
  // oracle already draws enums.
  property string notifAccent: "red"
  property string notifTitleInk: "white"
  property string notifBodyInk: "muted"
  // The card's own black. Its own setting rather than the shell's panel
  // opacity: a toast sits over whatever happens to be on screen and has to
  // stay readable against it, which is not the same job a panel has.
  property real notifBgOpacity: 0.70

  // ── and how it arrives ────────────────────────────────────────────────
  // `slide` is what it has always done: in from the edge it is pinned to.
  // `fade` stays put. `scale` grows from just under full size, which reads
  // as the toast being placed rather than thrown.
  property string notifAnimStyle: "slide"
  // How far a sliding toast travels. The vertical throw is shorter than the
  // sideways one by the ratio the two were first tuned at (36 against 64),
  // so one number moves both and keeps the proportion.
  property int notifSlide: 64
  // Against the shell's own motion setting rather than instead of it: 1.0 is
  // whatever zenon says normal is, so turning the desktop's motion down
  // still reaches the toasts.
  property real notifAnimSpeed: 1.0
  // A critical toast casts its accent past its border.
  property bool notifGlow: true
  property int notifGlowReach: 28
  // A per-toast ceiling, not a height: a short notification stays short.
  property int notifMaxHeight: 400
  // WHICH CORNER, not which end. mako's `anchor` had both axes and so does
  // this: the toasts used to be pinned to whichever edge the bar was on, and
  // wanting them at the top of the screen with the bar at the bottom is a
  // perfectly ordinary thing to want.
  //
  // "auto" keeps the old behavior — follow the bar — and stays the default,
  // because a stack at the far end of the screen from the thing that counts
  // them reads as a different application's.
  property string notifPosition: "auto"

  // ── the background ────────────────────────────────────────────────────
  // EMPTY BY DEFAULT, and that is the point. A default of
  // "$HOME/Pictures/Backgrounds" is a path that happens to be true on the
  // machine this was written on: the directory name is in no specification, so a
  // default naming it would be wrong on every machine that spells it
  // differently — while still being written into everyone's settings as
  // though it had been chosen.
  //
  // Empty means "ask XDG", which picasso does — see Picasso.defaultDir, which
  // reads the pictures directory out of user-dirs.dirs. A path is stored here
  // only once somebody has actually chosen one.
  property string backgroundDir: ""
  // The DEFAULT fit. A monitor can be given its own in picasso's context
  // menu, and picasso keeps those beside the per-monitor images; this is what
  // every monitor that has not been given one uses.
  property string backgroundFit: "crop"
  // What the color picker writes a color as. The wheel changes it while
  // the picker is up, and it is remembered — the format you copy in is
  // usually the format you copy in next time.
  property string pickerScheme: "hex"
  // how far past the screen the background is drawn, which is the room the
  // arrival's zoom has to move in
  property real backgroundZoom: 1.08

  // ── idle, and the lock ────────────────────────────────────────────────
  // socordia's ported hypridle listeners. Each timeout is counted by the
  // compositor through ext-idle-notify, so these are deadlines rather than
  // polling intervals and a change takes effect on the next idle period.
  property bool idleEnabled: true
  property int idleLockSecs: 300
  property int idleScreenOffSecs: 600
  property int idleKeyboardSecs: 300
  // ── WHICH LIGHTS GO OUT ───────────────────────────────────────────────
  // The devices whose lighting solaar dims when you go idle. It was one
  // keyboard, typed in by name — but solaar drives mice, headsets and
  // whatever is paired to a receiver as well, and nobody should have to
  // know how `solaar config` spells their hardware.
  //
  // "auto" by default: the first device solaar reports that has brightness
  // control, which on most desks is the only one. Nothing is named in the
  // source, so no desk's hardware ships as everybody's; with no solaar or
  // no such device, auto is simply nothing. See Ora.coerce for the shape.
  property string idleLightDevices: "auto"

  // What solaar can see, as Ora.parseSolaarShow reads it. Asked once when the
  // shell starts and again when the settings panel opens — `solaar show` takes
  // a few seconds and devices come and go, so neither a poll nor a single
  // startup read would do.
  property var solaarDevices: []
  property bool solaarScanning: false
  property bool solaarScanned: false

  function scanSolaar() {
    if (solaarProc.running) return;
    root.solaarScanning = true;
    solaarProc.running = true;
  }

  Process {
    id: solaarProc
    // Absent solaar is not an error: `command -v` fails quietly and the list
    // stays empty, which is exactly what "no devices" should look like.
    command: ["sh", "-c", "command -v solaar >/dev/null && solaar show 2>/dev/null"]
    stdout: StdioCollector {
      id: solaarOut
      waitForEnd: true
      onStreamFinished: {
        root.solaarDevices = Ora.parseSolaarShow(solaarOut.text);
        root.solaarScanning = false;
        root.solaarScanned = true;
      }
    }
  }

  // The names the idle timer acts on, "auto" resolved against what was found.
  function lightDevices() {
    return Ora.lightDevices(root.idleLightDevices, root.solaarDevices);
  }
  property bool idleInhibitPlayback: true

  property bool lockHideCursor: true
  property real lockShade: 0.6
  property int lockFailLimit: 3
  // How hard the live desktop behind the lock is frosted: Hyprland's blur
  // passes while locked (at Cerberus' frostSize). Every window's
  // blur gets it for the length of the lock — see CerberusLock's frost.
  // 5 (hyprlock's) was too frosty live (user, 2026-10-14)
  property int lockFrost: 4
  property int lockClockSize: 18
  property int lockDateSize: 14
  // How wide the password field is, as a fraction of the monitor.
  property real lockFieldWidth: 0.20
  // Which output carries the lock's clock and widgets. Empty for the first
  // screen there is — again, not a particular monitor's name, which is the
  // most machine-specific thing a default could be.
  property string lockWidgetMonitor: ""

  // ── time and weather ──────────────────────────────────────────────────
  property bool clock24h: true
  // A second hand is a second of work every second — the clock re-renders at
  // 1Hz instead of once a minute — so it is off unless asked for.
  property bool clockSeconds: false
  property bool weatherFahrenheit: false
  property int weatherRefreshMins: 15
  // Off, nothing is fetched and nothing is geolocated — the forecast pane says
  // it is switched off rather than sitting empty and blaming the network.
  property bool weatherEnabled: true
  // CALENDAR REMINDERS (chronos, khal; 2026-10-21): this many minutes before
  // a timed event its notification comes (all-day ones at 09:00 on the
  // day); -1 is none
  property int calRemindLead: 10
  property int calSyncMins: 15
  // SCREEN TIME (kairos, 2026-10-21): how long each app had you, counted on
  // this machine only; idle past this many minutes stops the count
  property bool screenTime: true
  property int screenTimeIdleMins: 3
  // BREAKS (kairos, 2026-10-22): after this many minutes at the screen
  // without one, a notification says to look away; idle or the lock is a break
  property bool screenBreaks: false
  property int screenBreakMins: 20
  // How stale a forecast may get before opening the pane re-fetches it.
  property int weatherStaleMins: 10

  // ── what the machine is doing ─────────────────────────────────────────
  // Sysmon feeds both the bar's meters and zeus' graphs from one set of
  // samples, so this is the rate for both.
  property int sysmonInterval: 1000
  property int sysmonNetInterval: 3000
  // ── THE GPU GETS ITS OWN RATE ──────────────────────────────────────────
  // On an nvidia card the reading costs a whole nvidia-smi — 25-50ms of CPU,
  // most of it initializing NVML again — which at the shared one-second rate
  // was the single most expensive thing the bar did. Utilization and
  // temperature do not move fast enough to be worth that every second.
  property int sysmonGpuInterval: 2000
  // how many samples the graphs keep. Two minutes at 1Hz.
  property int sysmonSpan: 120
  property int updateCheckMins: 60
  property bool updateNotify: true
  property bool ceresNews: true
  // which of zeus' four views it lands on when opened without being told
  property string zeusDefaultView: "graphs"
  // How often the kill list re-reads the process table while it is open.
  // Nothing polls when it is not.
  property int zeusProcInterval: 2500

  // ── the desktop menu ──────────────────────────────────────────────────
  property bool menuShowFiles: true
  property bool menuShowPackages: true
  property bool menuShowApps: true
  property bool menuShowHome: true
  // What the Home cards show and where they start. Hidden files are off by
  // default: at home they were most of the card, sorted above everything else.
  property bool menuShowHidden: false
  property bool menuHomePlaces: true
  // Minutes the Home cards stay where you left them; 0 always starts at home.
  property int menuHomeRemember: 5
  property bool menuShowRecent: true
  property int menuRecentCount: 12
  property bool menuShowTrash: true
  property bool menuShowBackground: true
  property bool menuShowDisplay: true
  // The one row on the desktop menu that had no switch of its own.
  property bool menuShowNote: true
  property int menuWidth: 220
  property int menuRowHeight: 30

  // ── how the panel describes itself ────────────────────────────────────
  // The order here is the order the sidebar reads, and it is deliberate: the
  // things you look at all day first, the things you set once at the end.
  // `group`: the sidebar's heading over it (sectionGroups), in order
  readonly property var sections: [
    // ── APPEARANCE: what everything wears ──
    // Theme & color, Fonts and Surfaces were one page, "Global" (user,
    // 2026-10-27: "oracle feels chaotic"); Follow Background's rows came
    // over from Background. The id stays "look", so a remembered section
    // still opens here.
    { id: "look", group: "looks", label: "Theme & color", icon: "\uF1FC",
      blurb: "the palette \u2014 the theme, Follow Daytime and Follow Background, the accent" },
    { id: "fonts", group: "looks", label: "Fonts", icon: "\uF031",
      blurb: "the type every component reads \u2014 the font, the monospace, their sizes" },
    { id: "surfaces", group: "looks", label: "Surfaces", icon: "\uF24D",
      blurb: "what every layer is made of \u2014 the corners, the width, opacity, shadows and frost" },
    { id: "motion", group: "looks", label: "Motion", icon: "",
      blurb: "how long everything takes, and how scrolling feels" },
    { id: "paper", group: "looks", label: "Background", icon: "",
      blurb: "picasso \u2014 the background, where it comes from and how it fits" },
    // ── DESKTOP: the windows and what sits around them ──
    { id: "display", group: "desktop", label: "Display", icon: "\uF108",
      blurb: "hyprland's monitors \u2014 resolution, refresh, scale, rotation" },
    { id: "windows", group: "desktop", label: "Windows", icon: "\uF2D2",
      blurb: "hyprland's window rules \u2014 how each app's windows open \u2014 what starts at login, and the workspace strip" },
    { id: "bar", group: "desktop", label: "Bar", icon: "",
      blurb: "morpheus — the pill and what it carries" },
    { id: "menu", group: "desktop", label: "Desktop menu", icon: "",
      blurb: "icarus — what right-clicking the desktop offers" },
    // ── INPUT ──
    { id: "input", group: "input", label: "Keyboard & mouse", icon: "\uF11C",
      blurb: "hyprland's keyboard, mouse, touchpad and tablet \u2014 layout, speed, focus" },
    { id: "keys", group: "input", label: "Shortcuts", icon: "\uDB81\uDE33",
      blurb: "hyprland's key binds \u2014 what each chord does, and which chord it is" },
    // ── ALERTS & TIME: what calls for you, and when ──
    { id: "notify", group: "alerts", label: "Notifications", icon: "",
      blurb: "howler — toasts, and what the bell remembers" },
    { id: "time", group: "alerts", label: "Time & weather", icon: "",
      blurb: "chronos — the clock, the calendar, the forecast" },
    { id: "screentime", group: "alerts", label: "Screen time", icon: "\uF253",
      blurb: "kairos \u2014 what is counted, and the reminders to take a break" },
    { id: "idle", group: "alerts", label: "Idle & lock", icon: "",
      blurb: "socordia and cerberus — being away from the machine" },
    // ── CAPTURE ──
    { id: "capture", group: "capture", label: "Screenshots & recordings", icon: "\uF030",
      blurb: "argus and the color picker \u2014 the countdown, the sound, the camera, the picker's format" },
    // ── THIS COMPUTER: set once, looked at seldom ──
    { id: "system", group: "computer", label: "System", icon: "",
      blurb: "zeus and the update count — what is measured, how often" },
    { id: "defaults", group: "computer", label: "Default apps", icon: "\uF009",
      blurb: "what opens what \u2014 the terminal, the browser, every kind of file" },
    { id: "health", group: "computer", label: "Health", icon: "\uF0F1",
      blurb: "a checkup of this shell \u2014 what an audit looks for" },
    { id: "about", group: "computer", label: "About", icon: "",
      blurb: "zenworks — this shell, and the whole of these settings" }
  ]

  // the sidebar's headings (user, 2026-10-27: a sidebar, as macOS' System
  // Settings has; then related items together under more of them)
  readonly property var sectionGroups: ({ looks: "Appearance", desktop: "Desktop", input: "Input",
                                          alerts: "Alerts & time", capture: "Capture", computer: "This computer" })

  // ── THE MARK ──────────────────────────────────────────────────────────
  // The banner at the head of every file in this shell, which spells
  // "zenworks" in box-drawing characters. It is written here as escapes and
  // not as the characters themselves for a practical reason: every tool that
  // has touched this repository — editors, heredocs, terminals — has at some
  // point mangled a pasted box-drawing or private-use glyph, and an escape
  // sequence is seven ASCII characters that cannot be mangled by any of them.
  //
  // Three lines of exactly 24 columns, so it MUST be set in a monospace face
  // and not the propo one the rest of the panel uses — the whole figure is
  // built out of the grid lining up.
  readonly property var mark: [
    "\u250C\u2500\u2510\u250C\u2500\u2510\u250C\u2510\u250C\u252C \u252C\u250C\u2500\u2510\u252C\u2500\u2510\u252C\u250C\u2500\u250C\u2500\u2510",
    "\u250C\u2500\u2518\u251C\u2524 \u2502\u2502\u2502\u2502\u2502\u2502\u2502 \u2502\u251C\u252C\u2518\u251C\u2534\u2510\u2514\u2500\u2510",
    "\u2514\u2500\u2518\u2514\u2500\u2518\u2518\u2514\u2518\u2514\u2534\u2518\u2514\u2500\u2518\u2534\u2514\u2500\u2534 \u2534\u2514\u2500\u2518"
  ]

  // Every setting, described. `fallback` is filled in at startup from the
  // property's own declared value — see buildSchema.
  readonly property var specs: [
    // ── display ──
    // Only the two rows every machine has. The monitors' own rows are built
    // from whatever is plugged in — see displaySpecs.
    { key: "actionDisplayScan", section: "display", label: "Monitors", type: "action",
      verb: "Detect",
      help: "Looks again for what is plugged in. Runs by itself when you open this section." },
    { key: "infoMonitorsPath", section: "display", label: "Written to", type: "info",
      elideLeft: true,
      help: "A plain hyprland file, read back on every change — editing it by hand works too. Monitors with nothing changed get no rule and fall to the catch-all at its top." },
    { key: "mainMonitor", section: "display", label: "Main monitor", type: "enum",
      optionsFrom: "screens", open: true, chipW: 208, plainAuto: true,
      alias: "default first primary monitor screen display output",
      help: "The monitor the shell means by Automatic: the pill, Follow Background, the lock screen's clock and field, and windows opened with no monitor in focus go here unless their own setting names another. Automatic is the leftmost screen. Unplugged, it falls back to the leftmost until it is back." },
    // the screens going off, and what brings them back — here rather than
    // on a shortcut (user, 2026-10-20), so idle and the bind share them
    { key: "idleScreenOffSecs", section: "display", label: "Screens off after", type: "int",
      min: 0, max: 7200, step: 30, unit: "s", alias: "idle dpms sleep blank",
      help: "Idle this long and every output is switched off. 0 leaves them on. Needs Idle timers, under Idle & lock." },
    { key: "wakeBy", section: "display", label: "Wake by", type: "enum", segments: true, hyprFile: "wake",
      hyprDefault: "mouse", alias: "wake screens dpms mouse key press",
      options: [ { value: "key",   label: "Key press" },
                 { value: "mouse", label: "Mouse or key press" } ],
      help: "What turns the screens back on, after idle or Lock and suspend screen. Kept in ~/.config/zenworks/hypr/lua/wake.lua." },
    // ── input ──
    // The fixed rows; the devices' own are built in inputSpecs, where the
    // layouts and the screens this machine has are on hand.
    { key: "actionInputScan", section: "input", label: "Devices", type: "action",
      verb: "Detect",
      help: "Looks again for what is plugged in. Runs by itself when you open this section." },
    { key: "infoInputPath", section: "input", label: "Written to", type: "info",
      elideLeft: true,
      help: "A plain lua file hyprland reads when it starts, read back on every change \u2014 editing it by hand works too." },
    // ── bar ──
    { key: "barPosition", section: "bar", label: "Position", type: "enum", segments: true, art: "bar",
      options: [ { value: "bottom", label: "Bottom" },
                 { value: "top",    label: "Top" } ],
      help: "Which edge the pill lives on. Every layer that opens out of it follows, and so do the toasts and the tooltips." },
    { key: "barMonitor", section: "bar", label: "Monitor", type: "enum",
      optionsFrom: "screens", autoEnv: "QS_STATUS_SCREEN", open: true, chipW: 208,
      help: "Which output the pill lives on. Automatic follows $QS_STATUS_SCREEN, then the main monitor (Display) — so a monitor switched off and back on gets the pill back." },
    { key: "barSlot", section: "bar", label: "Row height", type: "int",
      min: 24, max: 48, step: 1, unit: "px",
      help: "The slot every bar module stands in." },
    { key: "barTextSize", section: "bar", label: "Text size", type: "int",
      min: 12, max: 26, step: 1, unit: "px",
      help: "The bar's own type size, read through BarText." },
    { key: "barGap", section: "bar", label: "Module spacing", type: "int",
      min: 0, max: 20, step: 1, unit: "px",
      help: "The space between two neighboring modules." },
    { key: "barPadBar", section: "bar", label: "End caps", type: "int",
      min: 0, max: 32, step: 1, unit: "px",
      help: "How far the first and last module sit in from the pill's ends." },
    { key: "barPadModule", section: "bar", label: "Module padding", type: "int",
      min: 0, max: 16, step: 1, unit: "px",
      help: "A module's own breathing room inside its slot." },
    { key: "barWindowGap", section: "bar", label: "Gap to windows", type: "int",
      min: 0, max: 64, step: 1, unit: "px",
      help: "Extra room kept clear above the pill, on top of its own height and the gap it keeps from the screen edge. Nothing happens here if the bar is not reserving space." },
    { key: "barOpacity", section: "bar", alias: "bar opacity transparency translucency see-through morpheus pill background", label: "Opacity", type: "real",
      min: 0.1, max: 1, step: 0.05,
      help: "The morpheus pill's own background, and the small furniture painted to match it: tooltips, the now-playing card, chronos' day cells. Alpha over black, so lower is more transparent. With Blur behind on, in morpheus, it goes no lower than 0.52, where hyprland\u2019s blur stops." },
    { key: "barBlur", section: "bar", alias: "blur transparency frosted glass background hyprland",
      label: "Blur behind", type: "bool",
      help: "The desktop behind the pill, frosted. Off, it shows through sharp at any Opacity. On, Opacity is held at 0.52 at the least — under that hyprland stops blurring." },
    { key: "showUpdates", section: "bar", label: "Pending updates", type: "bool",
      help: "The count of packages waiting, at the far left." },
    { key: "showNotifications", section: "bar", label: "Notification bell", type: "bool",
      help: "The unread count, which opens howler." },
    { key: "showWorkspaces", section: "bar", label: "Workspaces", type: "bool",
      help: "The workspace row, and the system tray hidden behind it." },
    { key: "showClock", section: "bar", label: "Clock", type: "bool",
      help: "The seven-segment clock, which opens the calendar." },
    { key: "showNetwork", section: "bar", label: "Network meter", type: "bool",
      help: "Throughput up and down." },
    { key: "showGpu", section: "bar", label: "GPU meter", type: "bool" },
    { key: "showCpu", section: "bar", label: "CPU meter", type: "bool" },
    { key: "showMemory", section: "bar", label: "Memory meter", type: "bool" },
    { key: "showVolume", section: "bar", label: "Volume", type: "bool" },
    { key: "showNowPlaying", section: "bar", label: "Now playing", type: "bool",
      help: "The track name, and the green wash the pill takes on with it." },
    { key: "showStatus", section: "bar", label: "Microphone & recording", type: "bool",
      help: "The privacy indicators at the right end." },
    { key: "showHermes", section: "bar", alias: "hermes network wifi wi-fi ethernet bluetooth vpn connection icon",
      label: "Connections", type: "bool",
      help: "Hermes' icon: the network, and Bluetooth and the VPN while they are connected. A click opens its quick panel. Its right-click menu can hide it too; this brings it back." },
    { key: "barTooltips", section: "bar", label: "Hover tooltips", type: "bool",
      help: "The hover text on the bar's modules." },
    { key: "showTray", section: "bar", label: "System tray", type: "bool",
      help: "Hidden inside the workspace row until you hover it. Off, tray applications keep running with nowhere to appear." },
    { key: "barReserveSpace", section: "bar", label: "Reserve space", type: "bool",
      help: "Keep tiled windows clear of the pill. Off, it floats over them and nothing on the desktop moves for it. Autohide overrides it." },
    { key: "barAutohide", section: "bar", alias: "autohide auto hide hidden reveal slide away dock overlay",
      label: "Autohide", type: "bool",
      help: "The pill slides off the screen edge and comes back when the pointer touches that edge, or when something opens out of it. Nothing is reserved for it while it is set: windows run under it. Also in the bar's right-click menu." },

    // ── appearance ──
    // `pick` makes a text setting a button that opens terminus' picker
    // rather than a field to type into — see PickControl in the panel.
    // ONE ROW with Follow Background's tone (the user asked): the tone's
    // dropdown stands beside the theme only while the theme IS Follow
    // Background (`also` + the tone's `onlyWhen`)
    { key: "theme", section: "look", alias: "colours colors palette dark light scheme zenon daytime follow background tone auto",
      label: "Theme", type: "enum", optionsFrom: "themes", also: ["followMode"], open: true, chipW: 208,
      help: "The palette every component paints with. Zenon is the shell's own and the default; the rest are files in themes/, and anything a theme leaves out is Zenon's. A theme you saved yourself can be deleted: point at it in the list and press Delete." },
    { key: "themeDay", section: "look", alias: "follow daytime the sun day light theme sunrise",
      label: "Follow Daytime by day", type: "enum", optionsFrom: "themesNoSun", open: true, chipW: 208,
      help: "Only while the theme is Follow Daytime: what it wears from sunrise to sunset. The times are the weather's; with the weather off, 07:00 to 19:00." },
    { key: "themeNight", section: "look", alias: "follow daytime the sun night dark theme sunset",
      label: "Follow Daytime by night", type: "enum", optionsFrom: "themesNoSun", open: true, chipW: 208,
      help: "Only while the theme is Follow Daytime: what it wears from sunset to sunrise." },
    // A color of your own for the accent, over any theme (user, 2026-10-20).
    // Folds open on a color picker (ColorFold); shown again under Background
    // (`alsoIn`), beside Follow Background, whose accent it also replaces.
    { key: "accentColor", section: "look", alsoIn: "paper", alsoAfter: "followVivid", fold: "color",
      also: ["accentResetOnBackground"],
      alias: "accent colour color highlight custom manual picker tint theme",
      label: "Accent color", type: "color", none: "Theme's own",
      help: "The color the shell highlights with, whatever theme is worn, Follow Background and Follow Daytime included. Click to pick one; put it back and the theme's own returns." },
    // drawn as the Accent color row's checkbox (`within`), not a row of its own
    { key: "accentResetOnBackground", section: "look", within: "accentColor",
      alias: "accent colour color reset background wallpaper change",
      label: "Reset with background", type: "bool",
      help: "A new background puts the accent back to the theme's own." },
    // with the other theme rows, not under Background (user, 2026-10-12):
    // what it makes is a theme, and it lands in the Theme list above
    // (marked there with U+F2C0, its light mark kept — Ora.themeOptions)
    { key: "actionSaveFollow", section: "look", alias: "follow background save keep freeze theme wallpaper",
      label: "Keep this Follow Background", type: "action", verb: "Save",
      help: "Saves the palette Follow Background is wearing now as a theme of its own, named after the picture, so it outlives the background. It appears in Theme straight away." },
    // drawn as the Font row's second dropdown (`within`), not a row of its own
    { key: "fontWeight", section: "fonts", within: "fontFamily", alias: "font weight bold semibold light regular medium thickness",
      label: "Font weight", type: "enum",
      options: [ { value: "300", label: "Light" },
                 { value: "400", label: "Regular" },
                 { value: "500", label: "Medium" },
                 { value: "600", label: "SemiBold" },
                 { value: "700", label: "Bold" } ],
      help: "How heavy the shell's text is where it does not ask for a weight of its own; bold labels stay bold. Picking a font file sets this to that file's cut." },
    // drawn as the Font row's size stepper (`within`), not a row of its own
    { key: "fontSize", section: "fonts", within: "fontFamily", label: "Font size", type: "int",
      min: 12, max: 24, step: 1, unit: "px",
      help: "How large the shell's text is, everywhere but the bar (its own Text size) and the places with a size of their own." },
    // ONE ROW (the user asked): the family, then its weight and its size
    // (`also` — the specs drawn beside this one, in order). The book button
    // before the family opens Alexandria to choose from (`book`).
    { key: "fontFamily", section: "fonts", label: "Font", type: "enum",
      optionsFrom: "fontFamilies", also: ["fontWeight", "fontSize"], book: true, chipW: 230, open: true,
      alias: "font family typeface nerd weight bold semibold light regular medium thickness size alexandria book",
      help: "The shell's typeface and how heavy its text is — and hyprland's, GTK's, and what every other application asks for as sans-serif. Any installed family will do: the icons always come from JetBrainsMono Nerd Font (from the next shell start, the first time), and a Nerd Font gets the right cut of it per use. Bold labels stay bold whatever the weight." },
    // THE MONOSPACED FACE, one row like Font's: family, weight, size
    { key: "monoWeight", section: "fonts", within: "monoFamily", alias: "monospace mono font weight bold semibold light regular medium",
      label: "Monospace weight", type: "enum",
      options: [ { value: "300", label: "Light" },
                 { value: "400", label: "Regular" },
                 { value: "500", label: "Medium" },
                 { value: "600", label: "SemiBold" },
                 { value: "700", label: "Bold" } ],
      help: "How heavy fixed-width text is. Bold in a terminal stays a step heavier." },
    { key: "monoSize", section: "fonts", within: "monoFamily", label: "Monospace size", type: "int",
      min: 10, max: 32, step: 1, unit: "px",
      help: "kitty's text and the system's monospace size. Plato keeps a size of its own." },
    { key: "monoFamily", section: "fonts", label: "Monospace font", type: "enum",
      optionsFrom: "monoFamilies", also: ["monoWeight", "monoSize"], book: true, chipW: 230, open: true,
      alias: "monospace mono fixed width code terminal kitty plato editor typeface family weight size",
      help: "The face for text laid out on a grid: kitty, plato, code and file previews, logs, and what every other application asks for as monospace. Only fixed-width families are listed." },
    { key: "lexiTextStep", section: "fonts", alias: "lexi dictionary translate translation font text size zoom",
      label: "Lexicon text", type: "int", min: -8, max: 12, step: 1, unit: "px",
      help: "Lexi's text, larger or smaller than where it starts. Ctrl + and Ctrl − in lexi do the same, and Ctrl 0 puts it back." },
    // what these make, drawn: a panel and a menu over a striped ground
    // (OracleWindow's SurfaceSample) — a menu's opacity and shadow are
    // otherwise seen only with a menu open
    { key: "surfacesSample", section: "surfaces", type: "sample", label: "Sample",
      alias: "preview sample surfaces panel menu card" },
    { key: "cornerRadius", section: "surfaces", label: "Corner rounding", type: "int",
      min: 0, max: 16, step: 1, unit: "px",
      alias: "corner radius rounding round rounded square button scrollbar thumb menu pill bar panel dialog card toast notification osd window hyprland",
      help: "Every rounded corner: hyprland's windows, and in the shell every button, row, card, dialog, menu, scroll thumb, the pill and its panels, toasts and the OSD. This is a window's corner; the rest keep their proportion to it, so a dialog stays rounder than a button. 0 is square everywhere; pills and circles stay round." },
    { key: "barMaxWidth", section: "surfaces", label: "Maximum panel width", type: "int",
      min: 400, max: 2400, step: 20, unit: "px",
      help: "How wide any panel may grow. Always rounded down to an even number, so centering it lands on a whole pixel." },
    { key: "barScreenPad", section: "surfaces", label: "Gap to screen edge", type: "int",
      min: 0, max: 48, step: 1, unit: "px",
      help: "How far the pill floats off whichever edge it lives on. Every layer that opens out of it follows, or they would not line up with it." },
    { key: "panelOpacity", section: "surfaces", alias: "transparency translucency see-through panel layer background", label: "Panel opacity", type: "real",
      min: 0.1, max: 1, step: 0.05,
      help: "The ground every layer that opens out of the pill is painted on. Alpha over black, so lower is more transparent." },
    { key: "menuOpacity", section: "surfaces", alias: "transparency translucency see-through menu background", label: "Menu opacity", type: "real",
      // From where the frost starts. Below blurFloor (0.52) Zenon holds the
      // ground at the floor anyway, so the old 0.30 left a third of the
      // slider doing nothing at all.
      min: 0.55, max: 1, step: 0.05,
      help: "The ground under the rows of every menu — icarus', the tray's, picasso's, terminus' right-click menu, the dropdowns in here — and under terminus' quick look. Alpha over black, so lower is more transparent, and hyprland frosts what is behind it. Never lower than the point where that frost would stop." },
    { key: "shadowStrength", section: "surfaces", label: "Panel shadow", type: "real",
      min: 0, max: 1, step: 0.05,
      help: "How far a layer lifts off the desktop. A layer sits near an edge, so too much of this reads as a black halo." },
    { key: "menuShadows", section: "surfaces", label: "Menu and sheet shadows", type: "bool",
      alias: "menu sheet dialog dropdown context right-click shadow drop shadow",
      help: "The shadow every menu and sheet casts: icarus', the tray's, terminus' right-click menu, the dropdowns in here, and the sheets that drop over a window. Off, they sit flat on what is behind them." },
    // hyprland's own, kept in hypr/lua/effects.lua — see Ora's EFFECTS
    { key: "hyprShadows", section: "surfaces", label: "Window shadows", type: "bool",
      hyprFile: "effects", fx: "shadows", hyprDefault: true, alias: "hyprland window shadow drop shadow decoration",
      help: "The soft shadow hyprland draws under every window. Kept in ~/.config/zenworks/hypr/lua/effects.lua." },
    { key: "scrollFrost", section: "surfaces", alias: "scroll edge frost blur ghost rows under bar toolbar fade",
      label: "Frost under bars", type: "bool",
      help: "Rows scrolled past a list's edge carry on under the bar above it (or below it), blurred and fading out. Off, a list simply stops at its edge." },
    { key: "elasticScroll", section: "motion", alias: "elastic rubber band bounce overscroll scroll edge stretch",
      label: "Elastic scrolling", type: "bool",
      help: "Scrolling past the end of a list stretches it a little and springs back, as macOS does, and a fling bounces off the end. Off, every list stops dead at its edge." },
    { key: "cursorSlide", section: "motion", alias: "sliding cursor glide selection highlight row move jump",
      label: "Sliding cursor", type: "bool",
      help: "The highlight on a list's chosen row glides to the next one as you move, in every app and panel. Off, it jumps straight there." },
    { key: "scrollbarAutohide", section: "motion", alias: "scrollbar scroll bar hide overlay thumb", label: "Autohide scrollbars", type: "bool",
      help: "Every scrollbar in the shell fades away once the list stops moving, and comes back when you scroll or put the pointer on it. Off, the thumb is always there." },
    { key: "motionScale", section: "motion", label: "Animation speed", type: "real",
      min: 0, max: 2.5, step: 0.05, unit: "x",
      help: "Multiplies every duration in the shell. Zero means no animation at all." },
    { key: "hyprAnimations", section: "motion", label: "Window animations", type: "bool",
      hyprFile: "effects", fx: "animations", hyprDefault: true, alias: "hyprland window workspace animation slide fade popin motion",
      help: "Hyprland's windows popping in and out, workspaces sliding, and the shell's layers fading as they open and close. Off, all of it is instant. Kept in ~/.config/zenworks/hypr/lua/effects.lua." },
    { key: "arrivalEnabled", section: "motion", label: "Play the arrival", type: "bool",
      help: "The pill's slide and the background's zoom, once, when the session starts." },
    { key: "arrivalDuration", section: "motion", label: "Arrival length", type: "int",
      min: 150, max: 2000, step: 50, unit: "ms",
      help: "How long the bar's entrance takes, once it starts." },
    { key: "arrivalDeadline", section: "motion", label: "Arrival deadline", type: "int",
      min: 0, max: 5000, step: 100, unit: "ms",
      help: "How long after launch the arrival aims to land. A deadline, not a wait." },

    // ── notifications ──
    { key: "notifTimeout", section: "notify", label: "Timeout", type: "int",
      min: 0, max: 30000, step: 500, unit: "ms",
      help: "How long an ordinary notification stays up when it names no timeout of its own." },
    { key: "notifTimeoutLow", section: "notify", label: "Low urgency timeout", type: "int",
      min: 0, max: 30000, step: 500, unit: "ms",
      help: "The same, for notifications an application marks as unimportant. 0 keeps them up." },
    { key: "notifCriticalSticky", section: "notify", label: "Critical stays up", type: "bool",
      help: "A critical notification never expires on its own and waits to be dismissed." },
    { key: "notifMaxVisible", section: "notify", label: "Toasts on screen", type: "int",
      min: 1, max: 10, step: 1,
      help: "How many stack above the pill before the rest wait their turn." },
    { key: "notifIcons", section: "notify", label: "Show icons", type: "bool",
      help: "An app's icon, or the album art a music notification carries." },
    { key: "notifIconSize", section: "notify", label: "Icon size", type: "int",
      min: 24, max: 128, step: 4, unit: "px",
      help: "The application's icon or image, beside the text." },
    { key: "notifWidth", section: "notify", label: "Minimum width", type: "int",
      min: 200, max: 900, step: 20, unit: "px", pairMax: "notifMaxWidth",
      help: "A toast grows with its text from here." },
    { key: "notifMaxWidth", section: "notify", label: "Maximum width", type: "int",
      min: 300, max: 1600, step: 20, unit: "px", pairMin: "notifWidth",
      help: "Where it stops growing and wraps instead. Never narrower than the minimum." },
    { key: "notifCaptureWidth", section: "notify", label: "Capture width", type: "int",
      min: 240, max: 1200, step: 20, unit: "px",
      help: "A screenshot or recording toast is the capture itself, this wide. Maximum width still has the last word." },
    { key: "notifLift", section: "notify", label: "Gap above the pill", type: "int",
      min: 0, max: 120, step: 2, unit: "px",
      help: "How far the toasts stand off the bar, on whichever edge it is." },
    { key: "notifTrackMusic", section: "notify", label: "Keep track changes", type: "bool",
      help: "Whether a music player's notifications earn a row in the bell's history." },
    { key: "notifBellAlways", section: "notify", alias: "bell hide empty history visible", label: "Bell with no history", type: "bool",
      help: "On, the bell stays on the bar when its history is empty. Off, it folds away until a notification arrives (or Do not disturb is on). Also in the bell's right-click menu." },
    { key: "notifSilent", section: "notify", alias: "dnd do not disturb quiet silence mute toasts howler", label: "Do not disturb", type: "bool",
      help: "Hold back toasts; they still count on the bell and wait in its history. A critical one still shows. Also in the bell's right-click menu." },
    { key: "notifFocusTimers", section: "notify", alias: "focus pomodoro timer quiet dnd do not disturb chronos",
      label: "Quiet while a timer runs", type: "bool",
      help: "Do not disturb, on by itself while a Chronos timer counts down, and off again when none does. A timer finishing still shows. Also in the bell's right-click menu." },
    { key: "notifQuietFullscreen", section: "notify", alias: "focus full screen fullscreen game video film movie quiet dnd do not disturb",
      label: "Quiet while full screen", type: "bool",
      help: "Hold toasts back while the window in front fills the screen — a game, a film. They wait in the bell; leaving full screen, one toast says how many came in. A critical one still shows." },
    { key: "notifQuietHours", section: "notify", alias: "focus night sleep quiet hours schedule dnd do not disturb",
      label: "Quiet hours", type: "bool",
      help: "Do not disturb every day between the two hours below; past midnight works (22 to 7). Critical notifications still show." },
    { key: "notifQuietFrom", section: "notify", alias: "quiet hours start from evening", label: "Quiet from", type: "int",
      min: 0, max: 23, step: 1, unit: ":00",
      help: "The hour quiet hours begin, when they are on." },
    { key: "notifQuietTo", section: "notify", alias: "quiet hours end until morning", label: "Quiet until", type: "int",
      min: 0, max: 23, step: 1, unit: ":00",
      help: "The hour they end. The same as the start is never." },
    { key: "notifHistoryCap", section: "notify", label: "History kept", type: "int",
      min: 10, max: 1000, step: 10,
      help: "How many notifications the bell remembers across restarts." },
    { key: "notifFontSize", section: "notify", label: "Text size", type: "int",
      min: 10, max: 28, step: 1, unit: "px" },
    { key: "notifTextAlign", section: "notify", label: "Text alignment", type: "enum", segments: true, art: "align",
      options: [ { value: "left",   label: "Left" },
                 { value: "center", label: "Center" },
                 { value: "right",  label: "Right" } ] },
    { key: "notifPadding", section: "notify", label: "Padding", type: "int",
      min: 0, max: 24, step: 1, unit: "px" },
    { key: "notifSpacing", section: "notify", label: "Gap between toasts", type: "int",
      min: 0, max: 24, step: 1, unit: "px" },
    { key: "notifMarkup", section: "notify", label: "Honor markup", type: "bool",
      help: "Whether an application's bold and italic are rendered, or shown as the characters they are." },

    { key: "notifBgOpacity", section: "notify", alias: "toast colour color transparency translucent opacity howler", label: "Background", type: "real",
      min: 0.0, max: 1.0, step: 0.05,
      help: "How solid the card is over whatever is behind it." },
    { key: "notifTitleInk", section: "notify", label: "Title color", type: "enum",
      options: root.inkOptions },
    { key: "notifBodyInk", section: "notify", label: "Body color", type: "enum",
      options: root.inkOptions },
    { key: "notifAccent", section: "notify", alias: "toast colour color critical urgent accent glow howler", label: "Critical color", type: "enum",
      options: root.inkOptions,
      help: "The ink a critical notification wears — its title, and the light it casts. Its border is every border's: see Zenon.border." },
    { key: "notifGlow", section: "notify", label: "Critical glows", type: "bool",
      help: "Whether a critical toast casts its color past its border." },
    { key: "notifGlowReach", section: "notify", label: "Glow reach", type: "int",
      min: 0, max: 64, step: 2, unit: "px" },

    { key: "notifAnimStyle", section: "notify", alias: "toast animation motion slide fade scale howler", label: "Arrival", type: "enum",
      options: [ { value: "slide", label: "Slide" },
                 { value: "fade",  label: "Fade" },
                 { value: "scale", label: "Scale" } ],
      help: "Slide comes in from the edge the stack is pinned to. Fade stays put. Scale grows into place." },
    { key: "notifSlide", section: "notify", label: "Slide distance", type: "int",
      min: 0, max: 200, step: 4, unit: "px" },
    { key: "notifAnimSpeed", section: "notify", label: "Animation speed", type: "real",
      min: 0.25, max: 3.0, step: 0.05, unit: "\u00d7",
      help: "Against the shell's own motion setting, so turning that down still reaches the toasts." },
    { key: "notifPosition", section: "notify", label: "Position", type: "enum",
      // drawn as a six-cell grid with the chosen corner lit — see the
      // EnumControl, which renders `pictogram` specs itself
      pictogram: "corner",
      options: [ { value: "auto",          label: "Follow bar" },
                 { value: "top-left",      label: "Top left" },
                 { value: "top-center",    label: "Top" },
                 { value: "top-right",     label: "Top right" },
                 { value: "bottom-left",   label: "Bottom left" },
                 { value: "bottom-center", label: "Bottom" },
                 { value: "bottom-right",  label: "Bottom right" } ],
      help: "Which corner of the screen the toasts stack in. Follow bar puts them on whichever edge the pill is on." },
    { key: "notifMaxHeight", section: "notify", label: "Maximum height", type: "int",
      min: 80, max: 900, step: 20, unit: "px", pairMin: "notifMinHeight",
      help: "A ceiling per toast, not a height — a short one stays short." },
    { key: "notifMinHeight", section: "notify", label: "Minimum height", type: "int",
      min: 24, max: 200, step: 4, unit: "px", pairMax: "notifMaxHeight",
      help: "So a one-word notification still reads as a panel rather than as a strip." },

    // ── background ──
    { key: "backgroundDir", section: "paper", label: "Location", type: "text",
      pick: "directory", placeholder: "your pictures directory, then /Backgrounds",
      help: "Where picasso looks for backgrounds, chosen in terminus. Rescanned when this changes. Empty asks XDG for your pictures directory." },
    { key: "backgroundFit", section: "paper", label: "Fit", type: "enum", segments: true, art: "fit",
      options: [ { value: "crop",    label: "Crop" },
                 { value: "fit",     label: "Fit" },
                 { value: "stretch", label: "Stretch" },
                 { value: "pad",     label: "Center" },
                 { value: "tile",    label: "Tile" } ],
      help: "How an image that is not the monitor's shape is made to fit it. The default — a monitor given its own fit in the picker keeps that one." },
    { key: "pickerScheme", section: "capture", alias: "colour color picker hyprpicker hex rgb hsl oklch",
      label: "Picker format", type: "enum",
      options: [ { value: "hex",   label: "HEX" },
                 { value: "rgb",   label: "RGB" },
                 { value: "hsl",   label: "HSL" },
                 { value: "hsv",   label: "HSV" },
                 { value: "oklch", label: "OKLCH" },
                 { value: "cmyk",  label: "CMYK" } ],
      help: "How the color picker writes a color to the clipboard. The scroll wheel changes it while the picker is up." },
    { key: "backgroundZoom", section: "paper", label: "Overscan", type: "real",
      min: 1.0, max: 1.4, step: 0.01, unit: "x",
      help: "How far past the screen the image is drawn — the room the arrival's zoom moves in." },

    // ── Follow Background: the theme made from the background ──
    // drawn in the Theme row (`within`), and only while that row says
    // Follow Background (`onlyWhen`: [key, value])
    { key: "followMode", section: "look", within: "theme", onlyWhen: ["theme", "follow"],
      alias: "follow background wallpaper dynamic theme tone dark light auto sun daytime",
      label: "Follow Background tone", type: "enum",
      options: [ { value: "auto",  label: "Auto" },
                 { value: "dark",  label: "Dark" },
                 { value: "light", label: "Light" },
                 { value: "sun",   label: "Daytime" } ],
      help: "Only while the theme is Follow Background. Auto reads how bright the background is; Daytime is light from sunrise to sunset and dark after." },
    { key: "followVivid", section: "look", alias: "follow background wallpaper colour color saturation vivid",
      label: "Follow Background color", type: "real", min: 0, max: 1, step: 0.05,
      help: "Only while the theme is Follow Background. How much of the background's color the panels and text take: low is nearly neutral, high is tinted through." },
    { key: "followMonitor", section: "look", alias: "follow background wallpaper monitor screen display",
      label: "Follow Background monitor", type: "enum", optionsFrom: "screens", open: true, chipW: 208,
      help: "Whose background the theme is made from. Automatic is the main monitor (Display). The background tint follows the same one." },
    { key: "followSlideshow", section: "look", alias: "follow background wallpaper slideshow",
      label: "Follow the slideshow", type: "bool",
      help: "A slideshow on that monitor changes the theme with every picture. Off, the theme stays with the picture the slideshow started on." },
    { key: "wallpaperTint", section: "paper", alias: "tint wallpaper accent colour color glass background",
      label: "Background tint", type: "real", min: 0, max: 0.3, step: 0.02,
      help: "Lays the glass in a little of the background's own color, so the pill and its panels read as lit by what is behind them. Zero is the theme's plain ground." },
    // ── recording (argus) ──
    { key: "recCountdown", section: "capture", alias: "record recording screen video countdown delay argus wf-recorder",
      label: "Recording countdown", type: "int", min: 0, max: 10, step: 1, unit: "s",
      help: "Seconds counted down in the middle of the screen before a recording starts, so it does not open on the shortcut being pressed. 0 starts at once." },
    { key: "recAudio", section: "capture", alias: "record recording sound audio microphone mic voice argus",
      label: "Recording sound", type: "enum", segments: true,
      options: [ { value: "none", label: "None" }, { value: "system", label: "System" },
                 { value: "mic", label: "Microphone" }, { value: "both", label: "Both" } ],
      help: "What is heard in a recording: what the machine plays, your microphone (the default input), both mixed, or silence." },
    { key: "recBigPointer", section: "capture", alias: "record recording cursor pointer highlight bigger argus",
      label: "Bigger pointer while recording", type: "bool",
      help: "The pointer at twice its size while a recording runs, so it is easy to follow in the video; back to normal when it stops." },
    { key: "recCamera", section: "capture", alias: "record recording webcam camera face bubble argus",
      label: "Camera while recording", type: "bool",
      help: "Your webcam in a round bubble in a corner of the screen while a recording runs, so it is in the video. Needs a camera." },
    { key: "recCameraCorner", section: "capture", alias: "record recording webcam camera corner argus",
      label: "Camera corner", type: "enum", segments: true, art: "corner",
      options: [ { value: "topLeft", label: "Top left" }, { value: "topRight", label: "Top right" },
                 { value: "bottomLeft", label: "Bottom left" }, { value: "bottomRight", label: "Bottom right" } ],
      help: "Where the camera bubble sits." },
    // ── idle & lock ──
    { key: "idleEnabled", section: "idle", label: "Idle timers", type: "bool",
      help: "Off, nothing happens however long you are away. The lock still works by hand." },
    { key: "idleLockSecs", section: "idle", label: "Lock after", type: "int",
      min: 0, max: 3600, step: 30, unit: "s",
      help: "Idle this long and the lock comes up. 0 never locks on its own." },
    { key: "idleKeyboardSecs", section: "idle", label: "Device lighting off after", type: "int",
      min: 0, max: 3600, step: 30, unit: "s",
      help: "How long before the lighting on the devices below goes dark. 0 leaves it on." },
    { key: "idleLightDevices", section: "idle", alias: "keyboard backlight solaar logitech mouse rgb lighting",
      label: "Dim lighting on", type: "devices",
      help: "The Logitech devices, through solaar, whose lighting is dimmed when you go idle and brought back to where it was when you return. Auto is the first one that has lighting to dim." },
    { key: "idleInhibitPlayback", section: "idle", label: "Stay awake while playing", type: "bool",
      help: "Anything playing audio, holding an idle inhibitor, or publishing a media session holds the timers off." },
    { key: "lockHideCursor", section: "idle", label: "Hide the cursor", type: "bool",
      help: "On the lock screen." },
    { key: "lockShade", section: "idle", label: "Lock dimming", type: "real",
      min: 0, max: 1, step: 0.05,
      help: "How far the blurred desktop is darkened behind the lock." },
    { key: "lockFrost", section: "idle", label: "Lock frost", type: "int",
      min: 1, max: 8, step: 1, alias: "blur lock screen frosted",
      help: "How heavily the desktop behind the lock is blurred. Higher is more frosted." },
    // ── WHEN THE WAY OUT IS OFFERED, NOT HOW MANY TRIES YOU GET ──────
    // pam_faillock decides how many wrong passwords lock the account; this
    // decides when the lock shows the button that clears them. It used to
    // be labeled as though it were pam's number, and set above pam's it
    // only hid the button while pam was already refusing you. Cerberus now
    // reads pam's own deny and never waits past it — see failDeny there.
    { key: "lockFailLimit", section: "idle", label: "Offer a reset after", type: "int",
      min: 1, max: 20, step: 1, alias: "attempts lockout faillock wrong password",
      help: "Wrong passwords before the lock offers to clear them. Never later than the system's own lockout (pam_faillock), whatever this says." },
    { key: "lockWidgetMonitor", section: "idle", label: "Lock screen monitor",
      type: "enum", optionsFrom: "screens", open: true, chipW: 208,
      help: "Which output carries the clock and the password field. Automatic uses the main monitor (Display)." },
    { key: "lockClockSize", section: "idle", label: "Lock clock size", type: "int",
      min: 8, max: 48, step: 1, unit: "pt",
      help: "The time above the password field." },
    { key: "lockDateSize", section: "idle", label: "Lock date size", type: "int",
      min: 6, max: 36, step: 1, unit: "pt",
      help: "The date under it." },
    { key: "lockFieldWidth", section: "idle", label: "Password field width", type: "real",
      min: 0.1, max: 0.6, step: 0.01,
      help: "As a fraction of the monitor's width. It never goes below 240px whatever this says." },

    // ── time & weather ──
    { key: "clock24h", section: "time", label: "24-hour clock", type: "bool", sample: "clock" },
    { key: "clockSeconds", section: "time", label: "Show seconds", type: "bool",
      help: "The clock then repaints once a second rather than once a minute." },
    { key: "weatherFahrenheit", section: "time", label: "Fahrenheit", type: "bool",
      help: "Every temperature chronos shows, in °F instead of °C." },
    { key: "weatherEnabled", section: "time", label: "Fetch the forecast", type: "bool",
      help: "Off, nothing is fetched and nothing is geolocated." },
    { key: "weatherRefreshMins", section: "time", label: "Forecast refresh", type: "int",
      min: 5, max: 180, step: 5, unit: "min",
      help: "How often the forecast is fetched while the shell runs." },
    { key: "weatherStaleMins", section: "time", label: "Refetch when older than", type: "int",
      min: 1, max: 120, step: 1, unit: "min",
      help: "Opening the forecast re-fetches it if what is cached is older than this." },
    { key: "calRemindLead", section: "time", alias: "calendar reminder alarm notify khal event before minutes",
      label: "Remind me before", type: "int", min: -1, max: 120, step: 5, unit: "min",
      help: "How long before a calendar event its reminder comes (all-day events at 09:00 on the day). -1 is no reminders." },
    { key: "calSyncMins", section: "time", alias: "calendar sync vdirsyncer caldav online google nextcloud",
      label: "Calendar sync", type: "int", min: 5, max: 240, step: 5, unit: "min",
      help: "How often an online calendar set up through vdirsyncer is synced. Nothing happens without one." },
    { key: "screenTime", section: "screentime", alias: "screen time kairos usage apps focus tracking privacy",
      label: "Screen time", type: "bool",
      help: "Count how long each app is in front of you, kept on this machine only. Shown in Screen Time; a finished Chronos timer says what its time went to." },
    { key: "screenTimeIdleMins", section: "screentime", alias: "screen time idle away kairos",
      label: "Stop counting after idle", type: "int", min: 1, max: 30, step: 1, unit: "min",
      help: "No key or mouse for this long and screen time stops counting. A playing video holds it off." },
    { key: "screenBreaks", section: "screentime", alias: "break rest eyes 20 20 20 look away reminder kairos screen time",
      label: "Remind me to take breaks", type: "bool",
      help: "After a stretch at the screen, a notification says to look at something far away for 20 seconds. Stepping away past the idle time above counts as a break. Quiet while Focus is on." },
    { key: "screenBreakMins", section: "screentime", alias: "break rest eyes interval kairos",
      label: "Break every", type: "int", min: 10, max: 120, step: 5, unit: "min",
      help: "How long at the screen before the break reminder. Per-app daily limits are set in Screen Time." },

    // ── system ──
    { key: "sysmonInterval", section: "system", label: "Sample rate", type: "int",
      min: 250, max: 5000, step: 250, unit: "ms",
      help: "How often CPU, GPU, memory and disk are read. The bar's meters and zeus' graphs share these samples." },
    { key: "sysmonGpuInterval", section: "system", alias: "gpu nvidia poll rate sample", label: "GPU sample rate", type: "int",
      min: 500, max: 10000, step: 250, unit: "ms",
      help: "How often the GPU is asked. On nvidia each reading costs a full nvidia-smi, so this is deliberately slower than the rest." },
    { key: "sysmonNetInterval", section: "system", label: "Interface check", type: "int",
      min: 1000, max: 30000, step: 500, unit: "ms",
      help: "How often the network interface and address are re-read. Throughput is sampled at the rate above." },
    { key: "sysmonSpan", section: "system", label: "Graph history", type: "int",
      min: 30, max: 600, step: 10,
      help: "How many samples zeus' graphs keep." },
    { key: "updateCheckMins", section: "system", label: "Check for updates", type: "int",
      min: 5, max: 1440, step: 5, unit: "min",
      help: "How often pending package updates are counted for the bar." },
    { key: "updateNotify", section: "system", label: "Announce updates", type: "bool",
      help: "A toast the first time a new set of pending updates appears." },
    { key: "ceresNews", section: "system", label: "Arch news", type: "bool",
      help: "Reads archlinux.org's news and shows what is new since your last upgrade before the next one." },
    { key: "zeusProcInterval", section: "system", label: "Process list refresh", type: "int",
      min: 500, max: 15000, step: 250, unit: "ms",
      help: "How often the kill list re-reads the process table while it is open. Nothing polls when it is not." },
    { key: "zeusDefaultView", section: "system", label: "Zeus opens on", type: "enum",
      options: [ { value: "graphs", label: "Graphs" },
                 { value: "list",   label: "Processes" },
                 { value: "net",    label: "Connections" },
                 { value: "sound",  label: "Sound" } ],
      help: "Which view the system panel lands on when opened without being told. Clicking a meter still goes to what that meter is about." },

    // ── desktop menu ──
    { key: "menuWidth", section: "menu", label: "Menu width", type: "int",
      min: 160, max: 400, step: 10, unit: "px",
      help: "The desktop menu's cards and every submenu that hangs off them, the tray menu, and the dropdowns in here. Terminus' right-click menu measures itself against its own rows instead, because its entries carry key hints." },
    { key: "menuRowHeight", section: "menu", label: "Row height", type: "int",
      min: 22, max: 48, step: 1, unit: "px",
      help: "Every row in every menu — icarus', the tray's, terminus' right-click menu, and the cards picasso and this panel open." },
    { key: "menuShowFiles", section: "menu", label: "Files", type: "bool",
      help: "Opens terminus at the directory the desktop is showing." },
    { key: "menuShowPackages", section: "menu", label: "Store", type: "bool",
      help: "Opens ceres on its Store." },
    { key: "menuShowApps", section: "menu", label: "Apps", type: "bool" },
    { key: "menuShowHome", section: "menu", label: "Home", type: "bool",
      help: "Browse the filesystem from inside the menu." },
    { key: "menuShowHidden", section: "menu", label: "Hidden files in Home", type: "bool",
      help: "Dotfiles in the Home cards. Ctrl+H or the header's right-click menu flips it from the menu itself." },
    { key: "menuHomePlaces", section: "menu", label: "Places in Home", type: "bool",
      help: "Home, your XDG directories and terminus' bookmarks above the listing — the ones not already in it." },
    { key: "menuHomeRemember", section: "menu", label: "Home remembers its directory", type: "int",
      min: 0, max: 60, step: 1, unit: "min",
      help: "How long the Home cards reopen where you left them. 0 always starts at home." },
    { key: "menuShowRecent", section: "menu", label: "Recent places", type: "bool",
      help: "What artemis has learned you open, as a submenu." },
    { key: "menuRecentCount", section: "menu", label: "Recent places shown", type: "int",
      min: 3, max: 24, step: 1,
      help: "How many places the Recent submenu lists." },
    { key: "menuShowTrash", section: "menu", label: "Trash", type: "bool" },
    { key: "menuShowBackground", section: "menu", label: "Set background", type: "bool" },
    { key: "menuShowDisplay", section: "menu", label: "Display settings", type: "bool",
      help: "Opens this panel at Display, for the monitors." },
    { key: "menuShowNote", section: "menu", label: "New note", type: "bool",
      help: "The row that makes a sticky note on the desktop." },

    // ── default apps ──
    // The two fixed rows. The rest are built from what is installed — see
    // defaultsSpecs.
    { key: "actionAppsScan", section: "defaults", label: "Applications", type: "action",
      verb: "Detect",
      help: "Looks again for what is installed and what opens what. Runs by itself when you open this section." },
    // the zsh setup Zenworks ships, also offered once at the first start
    // (OracleManager's ZshSetup, which answers zshAsked)
    { key: "actionZsh", section: "defaults", alias: "zsh shell terminal prompt p10k powerlevel10k zshrc login shell",
      label: "Terminal setup", type: "action", verb: "Use Zenworks' zsh",
      help: "zsh with a fast prompt, suggestions and fuzzy completion. What is missing is installed, your own ~/.zshrc and ~/.p10k.zsh are kept as *.before-zenworks, and zsh becomes your login shell (it asks for your password)." },
    { key: "infoDefaultsPath", section: "defaults", label: "Written to", type: "info",
      elideLeft: true,
      help: "A plain lua file the binds read, read back on every change — editing it by hand works too." },

    // ── shortcuts ──
    // The fixed row. The binds' own are read out of binds.lua — see keysSpecs.
    { key: "infoKeysPath", section: "keys", label: "Written to", type: "info",
      elideLeft: true,
      help: "Only the chords moved off binds.lua's own, read back on every change — editing either by hand works too. Click a chord, then press the new one: Esc keeps it, Backspace turns it off. No two binds may share a chord." },

    // ── windows ──
    // Two rows that fold open into their lists: WindowRules.qml and
    // StartupApps.qml (fold "rules", "startup"). The lists live in hypr
    // files Oracle writes and reads back — see Ora's WINDOW RULES, STARTUP.
    { key: "workspaceStrip", section: "windows", alias: "workspace strip switcher osd overview numbers switch",
      label: "Workspace strip", type: "bool",
      help: "Every time the workspace changes, its number and the apps on each workspace show low on the screen for a moment." },
    // hyprland's windows, kept in hypr/lua/effects.lua beside the shadows
    // and animations — see Ora's EFFECTS (2026-10-25)
    { key: "hyprGapsOut", section: "windows", label: "Outer gaps", type: "int", min: 0, max: 40, step: 1, unit: "px",
      hyprFile: "effects", fx: "gaps_out", hyprDefault: 8, alias: "gaps margin space edge screen tiling padding",
      help: "Room between tiled windows and the screen's edges. Kept in ~/.config/zenworks/hypr/lua/effects.lua." },
    { key: "hyprGapsIn", section: "windows", label: "Inner gaps", type: "int", min: 0, max: 20, step: 1, unit: "px",
      hyprFile: "effects", fx: "gaps_in", hyprDefault: 2, alias: "gaps space between windows tiling padding",
      help: "Room between one tiled window and the next. Hyprland counts it on each side, so two windows stand twice this apart." },
    { key: "hyprSpecialGaps", section: "windows", label: "Special workspace gaps", type: "int", min: 0, max: 120, step: 2, unit: "px",
      hyprFile: "effects", fx: "special_gaps", hyprDefault: 30, alias: "special workspace scratchpad gaps margin edge",
      help: "How far the special workspace's windows stand in from the screen's edges (Super+` shows it)." },
    { key: "hyprBorder", section: "windows", label: "Border width", type: "int", min: 0, max: 5, step: 1, unit: "px",
      hyprFile: "effects", fx: "border_size", hyprDefault: 1, alias: "border outline frame thickness",
      help: "The line round every window, in the theme's colors. 0 draws none." },
    { key: "hyprLayout", section: "windows", label: "Tiling layout", type: "enum", segments: true, art: "layout",
      hyprFile: "effects", fx: "layout", hyprDefault: "dwindle", alias: "layout tiling dwindle master scrolling columns",
      options: [ { value: "dwindle", label: "Dwindle" }, { value: "master", label: "Master" }, { value: "scrolling", label: "Scrolling" } ],
      help: "How new windows share a workspace. Dwindle splits the space each time; Master keeps one big window and stacks the rest; Scrolling sets them side by side in a strip you scroll through. A workspace switched with the layout bind keeps its own." },
    { key: "hyprResizeBorder", section: "windows", label: "Resize from edges", type: "bool",
      hyprFile: "effects", fx: "resize_on_border", hyprDefault: false, alias: "resize drag edge border corner mouse",
      help: "Drag a window's edge or corner to resize it, as on other desktops. Super and the right button works either way." },
    { key: "hyprDimInactive", section: "windows", label: "Dim unfocused windows", type: "real", min: 0, max: 0.5, step: 0.05,
      hyprFile: "effects", fx: "dim_inactive", hyprDefault: 0, alias: "dim inactive unfocused darken focus",
      help: "Darken every window but the one you are in, by this much. 0 leaves them as they are." },
    { key: "hyprInactiveOpacity", section: "windows", label: "Unfocused opacity", type: "real", min: 0.5, max: 1, step: 0.05,
      hyprFile: "effects", fx: "inactive_opacity", hyprDefault: 1, alias: "opacity transparent see through inactive unfocused",
      help: "How see-through the windows you are not in are. 1 is solid." },
    { key: "infoWindowRules", section: "windows", label: "Window rules", type: "info",
      fold: "rules",
      alias: "window rule rules float floating size workspace opacity transparent pin blur maximize fullscreen idle inhibit app class",
      help: "How an app's windows open: floating and at what size, centered, on which workspace, how opaque, pinned, without blur, kept awake. Click to unfold. Kept in ~/.config/zenworks/hypr/lua/windows.lua." },
    { key: "infoStartup", section: "windows", label: "Startup apps", type: "info",
      fold: "startup",
      alias: "startup autostart login boot launch start exec apps programs",
      help: "What starts when you log in, besides the shell's own. Click to unfold. Kept in ~/.config/zenworks/hypr/lua/startup.lua; a change counts from the next login." },

    // ── the checkup ──
    // Readouts like the About rows, filled by oracle/doctor.sh — see
    // runCheckup. `health` names the row of Ora.readCheckup each one shows.
    // `fold: "tools"` unfolds into ToolsPanel: what is missing, and its package
    // (prebuilt, from the repos or an AUR binary — see Ora.TOOLS).
    { key: "actionCheckup", section: "health", label: "Checkup", type: "action",
      verb: "Rerun",
      help: "Runs by itself when you open this section. Read-only: it looks, it never changes anything." },
    { key: "infoHealthTests", section: "health", label: "Tests", type: "info", health: "tests",
      help: "The shell's own test suite, the same one run after every script change." },
    { key: "infoHealthProbes", section: "health", label: "Leftover probes", type: "info", health: "probes",
      help: "Temporary debugging overrides that were never taken out. One once spawned hyprctl every 400ms." },
    { key: "infoHealthStale", section: "health", label: "Changed scripts", type: "info", health: "stale",
      help: "Scripts edited since the shell started. A reload can keep the old copy; a restart cannot." },
    { key: "infoHealthMemory", section: "health", label: "Memory", type: "info", health: "memory",
      help: "Resident size, against what a fresh start settles at — measured two minutes after each restart with nothing opened." },
    { key: "infoHealthStack", section: "health", label: "Qt and Hyprland", type: "info", health: "stack",
      help: "Qt, quickshell and Hyprland now, against what the last clean preflight ran on. After an update, run scripts/preflight.sh." },
    { key: "infoHealthTools", section: "health", label: "Tools", type: "info", health: "tools",
      fold: "tools",
      help: "The programs the shell calls out to, and the packages they come from. Click to unfold." },
    { key: "infoHealthPollers", section: "health", label: "Child processes", type: "info", health: "pollers",
      help: "Watched for two seconds: what stays open, and what gets spawned while nothing is happening." },
    { key: "infoHealthLog", section: "health", label: "Log", type: "info", health: "log",
      help: "Errors and warnings since the shell started, from qs log." },

    // ── oracle itself ──
    // A READOUT, not a setting. "Where does this end up" is the first thing
    // anyone asks of a settings panel, and the answer was only discoverable by
    // reading the source — so the panel says it. `info` rows hold nothing, are
    // never written, and never count as changed; see Ora.stored.
    // ABOUT THIS COMPUTER (user, 2026-10-12: "something like fastfetch"):
    // a readout that folds open (`fold`) into the machine's facts — the
    // summary on the row, the lot underneath. Read by oracle/machine.py
    // since 2026-10-25 (fastfetch knew less). See readComputer.
    { key: "infoComputer", section: "about", label: "About this computer", type: "info",
      fold: "computer",
      alias: "fastfetch neofetch system hardware cpu gpu memory ram kernel distro os host uptime packages specs firmware bios drives storage displays battery",
      help: "The machine under the shell: hardware, firmware, drives, displays. Click to unfold." },
    { key: "infoStatePath", section: "about", label: "Kept in", type: "info",
      // a path identifies itself by its END, so this one elides from the left
      elideLeft: true,
      help: "Only the settings you have changed are written. Delete this file and everything is back to its defaults." },
    // The names three of the settings above ask you to type. Having to run
    // hyprctl to find out what your own outputs are called, in order to fill
    // in a field in a settings panel, is the panel's failure rather than
    // yours.
    { key: "infoOutputs", section: "about", label: "Outputs", type: "info",
      help: "What the monitor pickers under Bar and Idle & lock offer, as Quickshell sees them right now." },
    { key: "infoLaunched", section: "about", label: "Running since", type: "info",
      help: "When this shell last started." },
    { key: "actionReload", section: "about", label: "Reload from disk", type: "action",
      verb: "Reload",
      help: "Re-read oracle.json. Useful after editing it by hand." },
    // `context: true` — this one acts on the section you came here FROM, and
    // says which on its own button rather than making you remember. See
    // ActionControl, which is where that name is appended.
    // the window does the files (Oracle cannot reach morpheus or terminus'
    // picker): exportAsked / importAsked, see OracleWindow
    { key: "actionExport", section: "about", alias: "export backup save settings file move another machine",
      label: "Export settings", type: "action", verb: "Export\u2026",
      help: "Every setting, your shortcuts, default apps, input and screen setup, and the themes you saved, in one file. No notes, screen time or passwords." },
    { key: "actionImport", section: "about", alias: "import restore load settings file backup",
      label: "Import settings", type: "action", verb: "Import\u2026",
      help: "Settings from an exported file, shown before anything changes. What is here now is kept first, so an import can be undone by importing that." },
    { key: "actionResetSection", section: "about", label: "Reset one section",
      type: "action", verb: "Reset", context: true,
      help: "Put every setting in the section you were last in back to its default." },
    { key: "actionResetAll", section: "about", label: "Reset everything", type: "action",
      verb: "Reset all",
      help: "Every setting in every section back to its default." },
    { key: "actionUpdate", section: "about", alias: "update upgrade new version zenworks package aur",
      label: "Check for updates", type: "action", verb: "Open Ceres",
      help: "Zenworks is a package now, so it updates with everything else: Ceres' Updates lists a new version beside the rest. Your settings live in ~/.config/zenworks and are never touched by an update." },
    { key: "actionRestart", section: "about", label: "Restart the shell", type: "action",
      verb: "Restart",
      help: "For the few settings that only take effect on a fresh start." }
  ]

  // ── THE OUTPUTS, AS THEY ARE RIGHT NOW ───────────────────────────────
  // Three settings name a monitor, and until now all three were text fields
  // you had to type a name into — having first gone and found out what your
  // own outputs are called. This is that list, live: it follows monitors
  // being plugged in and out, so it can never be a set of names written down
  // by somebody with a different desk.
  //
  // "" first, meaning let the shell decide. It is the default for all three
  // and the only one that is correct on every machine.
  // ── WHAT "AUTOMATIC" MEANS FOR A MONITOR ─────────────────────────────
  // The screen named, if it is here; otherwise the one furthest left, then
  // highest. It was "the first screen in Quickshell's list", and that list
  // is in the order outputs ARRIVED — a monitor switched off and on again
  // comes back at the end, so the pill (and the lock's clock) moved to the
  // other screen for good on the first round trip. Where a screen sits on
  // the desk does not change when it blinks.
  // Then the main monitor (mainMonitor), if it is plugged in — `plain`
  // skips it, for the main monitor's own Automatic.
  function pickScreen(name, plain) {
    const sc = Quickshell.screens;
    let best = null, main = null;
    for (let i = 0; i < sc.length; ++i) {
      const s = sc[i];
      if (name && s.name === name) return s;
      if (!plain && root.mainMonitor !== "" && s.name === root.mainMonitor) main = s;
      if (!best || s.x < best.x || (s.x === best.x && s.y < best.y)) best = s;
    }
    return main || best;
  }

  // The monitor Hyprland has in focus, as a screen; with none in focus, the
  // main one (Display). What a window opened from a key or the bar lands on.
  // Was written out in ceres', oracle's and picasso's capture managers.
  function focusedScreen() {
    const m = Hyprland.focusedMonitor;
    if (m) for (const s of Quickshell.screens) if (s.name === m.name) return s;
    return root.pickScreen("");
  }

  readonly property var screenOptions: {
    const out = [{ value: "", label: "Automatic" }];
    const sc = Quickshell.screens;
    for (let i = 0; i < sc.length; ++i)
      out.push({ value: sc[i].name, label: sc[i].name });
    return out;
  }

  // The list for one picker, its Automatic saying which screen that is
  // right now — "Automatic" alone read as a fixed choice, and gave no hint
  // that it had quietly come to mean another monitor.
  function screenOptionsFor(spec) {
    const auto = root.pickScreen(spec.autoEnv ? Quickshell.env(spec.autoEnv) : "", spec.plainAuto === true);
    const out = root.screenOptions.slice();
    if (auto) out[0] = { value: "", label: "Automatic \u00b7 " + auto.name };
    return out;
  }

  // specs with each one's default folded in, which is what the panel reads.
  // Built once at startup rather than declared, because the defaults come from
  // the properties above and cannot be known before they exist.
  property var schema: []

  // key -> the value the property was declared with
  property var defaults: ({})

  // Rebuilt whenever the live options change, which is why the DEFAULTS are
  // captured only once. Re-reading them here on a later pass would take
  // whatever the settings currently are as their defaults — so plugging in a
  // monitor would quietly redefine "default" as "whatever you have set", and
  // every reset after that would be a no-op.
  property bool defaultsTaken: false

  function buildSchema() {
    const d = root.defaultsTaken ? root.defaults : ({});
    const out = [];
    for (let i = 0; i < root.specs.length; ++i) {
      const s = root.specs[i];
      // a shallow copy, so `specs` stays exactly what was written above and
      // the panel never edits the description it is drawing from
      const c = ({});
      for (const k in s) c[k] = s[k];
      // a list that is a fact about this machine rather than about this shell
      if (s.optionsFrom === "screens") c.options = root.screenOptionsFor(s);
      if (s.optionsFrom === "themes") c.options = root.themeOptions;
      if (s.optionsFrom === "themesNoSun") c.options = root.themeOptions.filter((o) => o.value !== "sun");
      if (s.optionsFrom === "fontFamilies" || s.optionsFrom === "monoFamilies") {
        // the one worn is listed even when fontconfig has not answered yet
        const all = root[s.optionsFrom];
        const worn = root[s.key];
        const fams = all.indexOf(worn) < 0 && worn !== "" ? [worn].concat(all) : all;
        c.options = fams.map((f) => ({ value: f, label: f.replace(/ Nerd Font$/, "") }));
      }
      if (Ora.stored(s)) {
        // a hypr file's setting may already hold the file's value here
        if (!root.defaultsTaken) d[s.key] = s.hyprFile ? s.hyprDefault : root[s.key];
        c.fallback = d[s.key];
      }
      out.push(c);
    }
    // The default apps' rows, after the section's own two. Their default is
    // "leave it to the system", except the terminal, which the binds need.
    const as = root.defaultsSpecs();
    for (let i = 0; i < as.length; ++i) {
      d[as[i].key] = root.appFallback(as[i].kind);
      as[i].fallback = d[as[i].key];
      out.push(as[i]);
    }
    // The monitors' rows. Their defaults are the catch-all rule's, fixed in
    // Ora, so they are set on every pass rather than captured once.
    const ds = root.displaySpecs();
    for (let i = 0; i < ds.length; ++i) {
      if (Ora.stored(ds[i])) {
        d[ds[i].key] = Ora.displayDefault(ds[i].field);
        ds[i].fallback = d[ds[i].key];
      }
      out.push(ds[i]);
    }
    // The input devices' rows. Their defaults are hyprland's own, fixed in Ora.
    const is = root.inputSpecs();
    for (let i = 0; i < is.length; ++i) {
      if (Ora.stored(is[i])) {
        d[is[i].key] = Ora.inputDefault(is[i].field);
        is[i].fallback = d[is[i].key];
      }
      out.push(is[i]);
    }
    // Input methods' rows, under the devices'. Their defaults are fixed.
    const ims = root.imSpecs();
    for (let i = 0; i < ims.length; ++i) {
      if (Ora.stored(ims[i])) d[ims[i].key] = ims[i].fallback;
      out.push(ims[i]);
    }
    // The binds' rows. Their defaults are binds.lua's own chords.
    const ks = root.keysSpecs();
    for (let i = 0; i < ks.length; ++i) {
      if (Ora.stored(ks[i])) {
        d[ks[i].key] = ks[i].bindDefault;
        ks[i].fallback = d[ks[i].key];
      }
      out.push(ks[i]);
    }
    root.defaults = d;
    root.defaultsTaken = true;
    root.schema = out;
  }

  // a monitor came or went; the pickers have to say so
  onScreenOptionsChanged: if (root.defaultsTaken) root.buildSchema();
  // the languages added, or one on its way: their rows come and go
  onImListChanged: if (root.defaultsTaken) root.buildSchema();
  onImPendingChanged: if (root.defaultsTaken) root.buildSchema();

  // "auto" resolved against where the bar actually is. Oracle cannot import
  // Zenon — Zenon imports Oracle — so the caller passes in what it knows.
  function notifCorner(barAtTop) {
    const p = root.notifPosition;
    if (p === "auto") return (barAtTop ? "top" : "bottom") + "-center";
    return p;
  }

  // What a read-only row shows. Not a property, because these are facts about
  // the running shell rather than settings — there is nothing to store, reset
  // or compare, and giving them a property would have put them in the file.
  function info(key) {
    const hs = root.spec(key);
    if (hs && hs.health) {
      if (root.checking) return "checking\u2026";
      const r = root.checkup[hs.health];
      return r ? r.text : "not run yet";
    }
    if (key === "infoComputer") {
      if (root.computerReading && !root.computer) return "reading\u2026";
      if (!root.computer) return "";
      return root.computer.ok ? root.computer.summary : root.computer.why;
    }
    if (key === "infoWindowRules") return Ora.windowRulesSummary(root.windowRules, root.shippedRules);
    if (key === "infoStartup") {
      const n = root.startupApps.length, on = root.startupApps.filter((a) => a.on).length;
      return n === 0 ? "the shell's own" : on + " of " + n + (n === 1 ? " app" : " apps") + " on";
    }
    if (key === "infoStatePath") return root.statePath;
    if (key === "infoMonitorsPath") return root.monitorsPath;
    if (key === "infoDefaultsPath") return root.defaultsPath;
    if (key === "infoInputPath") return root.inputPath;
    if (key === "infoKeysPath") return root.keysPath;
    // a group's head: how many it holds, and how many of those you moved
    if (key.indexOf("keysHead:") === 0) {
      const g = root.bindList.filter((b) => b.group === key.slice(9));
      const moved = g.filter((b) => root.keyValues["bind:" + b.id] !== b.chord).length;
      return g.length + (g.length === 1 ? " bind" : " binds") + (moved ? " \u00b7 " + moved + " changed" : "");
    }
    if (key.indexOf("inputHead:") === 0) return Ora.inputDeviceText(root.inputDevices, key.slice(10));
    if (key === "imHead") return root.imWaiting ? "installing…" : root.imOn ? "on" : "off";
    if (key.indexOf("display:") === 0) {
      const m = root.displayByName(key.split(":")[1]);
      if (!m) return "";
      if (m.disabled) return "off";
      return m.width + "\u00d7" + m.height + " \u00b7 " + Ora.rateText(m.refresh)
        + " Hz \u00b7 " + Math.round(m.scale * 100) + "%";
    }
    if (key === "infoOutputs") {
      const sc = Quickshell.screens;
      const out = [];
      for (let i = 0; i < sc.length; ++i)
        out.push(sc[i].name + " " + sc[i].width + "\u00d7" + sc[i].height);
      return out.length ? out.join("   ") : "none";
    }
    if (key === "infoLaunched") {
      const d = Quickshell.launchTime;
      return d ? Qt.formatDateTime(d, "ddd d MMM, HH:mm") : "";
    }
    return "";
  }

  // "ok", "warn" or "bad" — how a Health row is colored. Everything else
  // is a plain fact and reads "ok".
  function infoLevel(key) {
    const hs = root.spec(key);
    // "" for a plain fact, or a check with no answer yet: only a reading
    // the checkup actually made is colored, green included
    if (!hs || !hs.health || root.checking) return "";
    const r = root.checkup[hs.health];
    return r ? r.level : "";
  }

  // ── THE CHECKUP ───────────────────────────────────────────────────────
  // Memory is read as a drift from what a fresh start settles at, measured
  // by morpheus/LagWatch into settle.json (see Ora.settledBaseline). This
  // constant is only the stand-in until the first measurement: the idle
  // size in lag.log after the restarts of 2026-10-18 (~900 MiB).
  readonly property int rssFallbackKb: 921600
  FileView {
    id: settleFile
    path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/quickshell/settle.json"
    blockLoading: true
    printErrors: false
  }
  property var checkup: ({})
  property bool checking: false
  property double checkedAt: 0

  function runCheckup() {
    if (root.checking) return;
    root.checking = true;
    root.revision++;
    const since = Quickshell.launchTime ? Math.floor(Quickshell.launchTime.getTime() / 1000) : 0;
    // The pid is left to the script: it is started straight from here, so
    // its $PPID is this shell.
    doctorProc.command = ["bash", Quickshell.shellDir + "/oracle/doctor.sh",
      Quickshell.shellDir, "", String(since), Ora.toolNames()];
    doctorProc.running = true;
  }

  // ── ABOUT THIS COMPUTER ───────────────────────────────────────────────
  // machine.py's JSON and quickshell's version, read once on the first visit
  // to About and again after five minutes (uptime, memory and disks move).
  property var computer: null
  property bool computerReading: false
  property double computerAt: 0
  function readComputer(force) {
    if (root.computerReading) return;
    if (!force && root.computer && Date.now() - root.computerAt < 300000) return;
    root.computerReading = true;
    root.revision++;
    computerProc.running = true;
  }
  Process {
    id: computerProc
    command: ["bash", "-c",
      "python3 -I \"$1\" 2>/dev/null; printf '\\n@@QS@@\\n'; qs --version 2>/dev/null | head -1",
      "_", Quickshell.shellDir + "/oracle/machine.py"]
    stdout: StdioCollector {
      id: computerOut
      onStreamFinished: {
        const t = computerOut.text;
        const cut = t.indexOf("@@QS@@");
        const c = Ora.readComputer(cut >= 0 ? t.slice(0, cut) : t, cut >= 0 ? t.slice(cut + 6).trim() : "");
        if (!c.ok) c.why = "The machine could not be read.";
        root.computer = c;
        root.computerAt = Date.now();
        root.computerReading = false;
        root.revision++;
      }
    }
  }

  Process {
    id: doctorProc
    stdout: StdioCollector {
      id: doctorOut
      onStreamFinished: {
        settleFile.reload();
        root.checkup = Ora.readCheckup(doctorOut.text,
          Ora.settledBaseline(settleFile.text(), root.rssFallbackKb));
        root.checkedAt = Date.now();
        root.checking = false;
        root.revision++;
      }
    }
  }

  function spec(key) {
    for (let i = 0; i < root.schema.length; ++i)
      if (root.schema[i].key === key) return root.schema[i];
    return null;
  }

  // The panel's read. A function rather than a binding for the obvious reason
  // — the key is not known until the row exists — which is what `revision` is
  // for on the other side.
  function get(key) {
    if (String(key).indexOf("display:") === 0) return root.displayValues[key];
    if (String(key).indexOf("default:") === 0) return root.appDefaults[key];
    if (String(key).indexOf("input:") === 0) return root.inputValues[key];
    if (String(key).indexOf("im:") === 0) return root.imValue(key);
    if (String(key).indexOf("bind:") === 0) return root.keyValues[key];
    return root[key];
  }

  // ── UNDO AND REDO (user, 2026-10-27) ──────────────────────────────────
  // Every change to a setting, from the panel or from anywhere else that
  // sets one (the bell's Do not disturb, Lexi's text size), is a step:
  // { key: the value it left }. A burst on one key — a slider dragged, the
  // wheel over a chip — joins into one step, and a reset of a page or of
  // everything is one step for all it touched. The monitors are not in it:
  // they have their own keep-or-revert question. morpheus/undo's UndoStack.
  UndoStack { id: history }
  readonly property bool canUndo: history.canUndo
  readonly property bool canRedo: history.canRedo
  property var _step: null           // the step being gathered, while open
  property int _stepDepth: 0
  property bool _replaying: false
  property string _lastKey: ""
  property double _lastAt: 0
  function _beginStep() { if (root._stepDepth++ === 0) root._step = ({}); }
  function _endStep() {
    if (--root._stepDepth > 0) return;
    const step = root._step;
    root._step = null;
    const keys = Object.keys(step || {});
    if (keys.length === 0) return;
    const now = Date.now();
    const joins = keys.length === 1 && keys[0] === root._lastKey && now - root._lastAt < 1200;
    root._lastKey = keys.length === 1 ? keys[0] : "";
    root._lastAt = now;
    history.record(step, joins);
  }
  function _note(key, old) {
    if (root._replaying || !root._step || key in root._step) return;
    root._step[key] = old;
  }
  // back (dir -1) or forward (1) a step: the label of the first setting it
  // touched, "" when there was none
  function stepHistory(dir) {
    const list = dir < 0 ? history.past : history.future;
    if (list.length === 0) return "";
    const top = list[list.length - 1];
    const now = ({});
    for (const k in top) now[k] = root.get(k);
    const s = dir < 0 ? history.undo(now) : history.redo(now);
    if (s === undefined) return "";
    root._replaying = true;
    try { for (const k in s) root.set(k, s[k]); } finally { root._replaying = false; }
    root._lastKey = "";
    const first = root.spec(Object.keys(s)[0]);
    const n = Object.keys(s).length;
    return (first ? first.label : Object.keys(s)[0]) + (n > 1 ? " and " + (n - 1) + " more" : "");
  }
  function undo() { return root.stepHistory(-1); }
  function redo() { return root.stepHistory(1); }

  function set(key, value) {
    const s = root.spec(key);
    if (!s || !Ora.stored(s)) return;
    root._beginStep();
    try { root._set(s, key, value); } finally { root._endStep(); }
  }
  function _set(s, key, value) {
    if (!s.display && !Ora.same(root.get(key), Ora.coerce(s, value))) root._note(key, root.get(key));
    if (s.display) { root.setDisplay(s, value); return; }
    if (s.appDefault) { root.setAppDefault(s, value); return; }
    if (s.input) { root.setInput(s, value); return; }
    if (s.im) { root.setIm(s, value); return; }
    if (s.bindKey) { root.setBind(s, value); return; }
    if (s.hyprFile === "effects") { root.setEffect(key, value); return; }
    if (s.hyprFile) { root.setWakeBy(value); return; }
    const v = Ora.coerce(s, value);
    if (Ora.same(root[key], v)) return;
    root[key] = v;
    root.revision++;
    saveTimer.restart();
    // ── A MINIMUM NEVER PASSES ITS MAXIMUM ───────────────────────────
    // Two sliders with overlapping ranges could describe a toast whose
    // minimum width was wider than its maximum. The one you are NOT
    // moving gives way, so the one you are moving does what you asked.
    if (s.pairMax && root[s.pairMax] < v) root.set(s.pairMax, v);
    if (s.pairMin && root[s.pairMin] > v) root.set(s.pairMin, v);
  }

  function nudge(key, dir) {
    const s = root.spec(key);
    if (!s) return;
    root.set(key, Ora.nudge(s, root.get(key), dir));
  }

  function isDefault(key) {
    return Ora.same(root.get(key), root.defaults[key]);
  }

  function reset(key) {
    if (key in root.defaults) root.set(key, root.defaults[key]);
  }

  function resetSection(section) {
    root._beginStep();
    try { root._resetSection(section); } finally { root._endStep(); }
  }
  function _resetSection(section) {
    for (let i = 0; i < root.schema.length; ++i) {
      const s = root.schema[i];
      // the monitors too: each goes through setDisplay, so the lot is one
      // write and one "keep these settings?", and comes back by itself
      if (!Ora.stored(s) || s.section !== section) continue;
      root.reset(s.key);
    }
  }

  // NOT the monitors, the default apps or the input devices. "Reset
  // everything" is oracle.json, and Reload from disk runs this before reading
  // the file back — neither should reach into hyprland and change a screen or
  // a keyboard layout, or into mimeapps.list. Those sections reset on their own.
  function resetAll() {
    root._beginStep();
    try { root._resetAll(); } finally { root._endStep(); }
  }
  function _resetAll() {
    for (let i = 0; i < root.schema.length; ++i) {
      const s = root.schema[i];
      if (Ora.stored(s) && !s.display && !s.appDefault && !s.input && !s.bindKey && !s.hyprFile) root.reset(s.key);
    }
  }

  // How many settings in a section are no longer at their default. The sidebar
  // shows this, so a section that has been changed says so unopened.
  //
  // A monitor that is not at "automatic" is not a setting someone moved off
  // its default — it is a monitor set up the way it has to be. Counting it
  // made every desk with a rotated screen read as modified, and made its
  // label a one-click way to rotate the screen back. (Hence `!s.display`.)
  //
  // EVERY SECTION AT ONCE, once a revision. Each sidebar tab asked for its
  // own section, and each ask read every setting in the schema: the whole
  // schema once per tab on every change — 25–38 ms a time, inside the
  // handlers that bump the revision (qmlprofiler, 2026-10-09). The rule is
  // oracle.js changedIn's, in one pass.
  readonly property var changedCounts: {
    root.revision;
    const out = { "": 0 };
    for (let i = 0; i < root.schema.length; ++i) {
      const s = root.schema[i];
      if (s.display || !Ora.stored(s)) continue;
      if (Ora.same(root.get(s.key), root.defaults[s.key])) continue;
      out[""]++;
      out[s.section] = (out[s.section] || 0) + 1;
    }
    return out;
  }
  function changedIn(section) {
    return root.changedCounts[section || ""] || 0;
  }

  // ── the actions ───────────────────────────────────────────────────────
  // `context` is whatever the panel was standing in when the row was clicked,
  // so "reset a section" can mean the one you are looking at without the
  // action needing a second control beside it.
  signal updateAsked()
  signal exportAsked()
  signal importAsked()
  signal zshAsked()
  // the first start's cheat sheet (ZshSetup, which keeps welcome.json),
  // and whether the sheet is up (KeysSheet says) — the terminal question
  // waits for it to close
  // ── ZENWORKS' VERSION, for About (user, 2026-10-25) ───────────────────
  // The installed package's (pacman), or a working copy's git description
  // when this shell runs from one — Ora.versionText says it. Read once, at
  // start: a version changes only with a new start.
  property string zenworksVersion: ""
  Process {
    id: versionProc
    running: true
    command: ["sh", "-c",
      "case $1 in /usr/share/zenworks/*) printf 'pkg %s\\n' \"$(pacman -Q zenworks 2>/dev/null | cut -d' ' -f2)\" ;;"
      + " *) printf 'git %s\\n' \"$(git -C \"$1\" describe --tags --long --dirty 2>/dev/null)\" ;; esac",
      "_", Quickshell.shellDir]
    stdout: StdioCollector { onStreamFinished: root.zenworksVersion = Ora.versionText(this.text) }
  }

  signal keysSheetAsked()
  property bool keysSheetOpen: false
  // then its second card, Make it yours (WelcomeLook), the same way
  signal welcomeLookAsked()
  property bool welcomeLookOpen: false
  // An action still out from its last press: its button dims and ignores
  // another (the panel's ActionControl reads this).
  function actionBusy(key) {
    return key === "actionCheckup" ? root.checking : false;
  }
  function run(key, context) {
    if (key === "actionCheckup") { root.runCheckup(); return; }
    if (key === "actionDisplayScan") { root.scanDisplays(); return; }
    if (key === "actionAppsScan") { root.scanApps(); return; }
    if (key === "actionInputScan") { root.scanInputDevices(); return; }
    if (key === "actionImSettings") { root.imSettings(); return; }
    if (key === "actionReload") { root.reloadFromDisk(); return; }
    if (key === "actionSaveFollow") { root.nameFollowRequested(); return; }
    if (key === "actionResetSection") { root.resetSection(context); return; }
    if (key === "actionResetAll") { root.resetAll(); return; }
    // the shell's side opens Ceres' Updates (OracleManager: Oracle cannot
    // reach Ceres itself)
    if (key === "actionUpdate") { root.updateAsked(); return; }
    if (key === "actionExport") { root.exportAsked(); return; }
    if (key === "actionImport") { root.importAsked(); return; }
    if (key === "actionZsh") { root.zshAsked(); return; }
    if (key === "actionRestart") {
      // Through scripts/restart.sh, in a shell that has already been
      // detached, so the replacement is never a child of the instance it
      // replaces. The same line icarus' session menu uses. Not `qs kill`:
      // see restart.sh for why a clean exit is the one thing a restart
      // must not ask for here.
      // Quoted: a config path with a space in it would otherwise split. By
      // hand, as Strings.shellQuote does it — morpheus reads this singleton,
      // so importing morpheus here would be a cycle.
      const dir = "'" + String(Quickshell.shellDir).replace(/'/g, "'\\''") + "'";
      Quickshell.execDetached(["sh", "-c", dir + "/scripts/restart.sh"]);
      return;
    }
  }

  // ── DISPLAYS ──────────────────────────────────────────────────────────
  // What is plugged in, from hyprctl — Quickshell's screens do not carry the
  // modes a monitor can run in, and the disabled ones are not screens at all.
  // The values are kept in hypr/lua/monitors.lua, not in oracle.json: see
  // Ora's DISPLAYS for why, and for the file's shape.
  property var displays: []
  property var monitorRules: []
  // key ("display:DP-1:mode") -> value, rebuilt from the file and the monitors
  property var displayValues: ({})

  readonly property string monitorsPath: root.hyprLuaDir + "/monitors.lua"

  // Each monitor's own ink, so its rows read as one group and the groups as
  // different monitors — and so its box in the Arrangement is the same color
  // as its settings below. Cyan and the orange are left out: they already
  // mean "selected" and "changed" in this panel.
  // The Zenon SLOT, not the color: Oracle cannot import Zenon, which
  // imports Oracle, so the caller reads it — Zenon[Oracle.displayAccent(n)]
  // — and a theme recolors the monitors with everything else.
  function displayAccent(name) {
    const inks = ["blue", "magenta", "green", "sand", "pink"];
    for (let i = 0; i < root.displays.length; ++i)
      if (root.displays[i].name === name) return inks[i % inks.length];
    return "muted";
  }

  function displayByName(name) {
    for (let i = 0; i < root.displays.length; ++i)
      if (root.displays[i].name === name) return root.displays[i];
    return null;
  }

  function ruleFor(mon) {
    // the last matching rule wins, as it does in hyprland
    let hit = null;
    for (let i = 0; i < root.monitorRules.length; ++i)
      if (Ora.ruleMatches(root.monitorRules[i].output, mon)) hit = root.monitorRules[i];
    return hit;
  }

  function displaySpecs() {
    const out = [];
    // The picture of the desk, once there is more than one screen to arrange.
    if (root.arrangeRects.length >= 2)
      out.push({ key: "displayArrange", section: "display", type: "arrange",
        label: "Arrangement", alias: "monitor screen layout position arrange left right above below",
        help: "Drag a screen to where it sits on your desk. It snaps against the others, and lines up with them when you drop it close." });
    for (let i = 0; i < root.displays.length; ++i) {
      const m = root.displays[i];
      const p = "display:" + m.name + ":";
      const alias = "monitor screen output display " + m.name + " " + m.desc;
      const row = (field, extra) => {
        const c = { key: p + field, section: "display", display: true,
                    monitor: m.name, field: field, alias: alias };
        for (const k in extra) c[k] = extra[k];
        return c;
      };
      out.push(row("about", { label: m.name, type: "info",
        help: m.model || m.desc || "a monitor" }));
      out.push(row("enabled", { label: "Enabled", type: "bool",
        help: "Off, hyprland leaves it dark and moves its workspaces away. The last screen that is on cannot be turned off here." }));
      out.push(row("mode", { label: "Resolution & refresh", type: "enum", open: true,
        chipW: 208,
        options: Ora.modeOptions(m),
        help: "Preferred is what the monitor itself asks for." }));
      out.push(row("scale", { label: "Scale", type: "enum", open: true,
        options: Ora.scaleOptions(m),
        help: "Only the scales that divide this screen into whole pixels — hyprland rounds any other to one of these anyway." }));
      out.push(row("transform", { label: "Rotation", type: "enum",
        options: Ora.transformOptions(),
        help: "Turned a quarter at a time, for a screen stood on its side." }));
      out.push(row("position", { label: "Position", type: "enum", open: true,
        options: Ora.positionOptions(),
        help: "Where it goes against the other screens. Automatic lays them out left to right; Arrangement above places it exactly." }));
      out.push(row("vrr", { label: "Adaptive sync", type: "enum",
        options: Ora.vrrOptions(),
        help: "VRR, FreeSync, G-Sync. Fullscreen only keeps it off the desktop, where some panels flicker with it." }));
    }
    return out;
  }

  // the file and the monitors, folded into one value per row
  function syncDisplayValues() {
    const vals = ({});
    for (let i = 0; i < root.displays.length; ++i) {
      const m = root.displays[i];
      const v = Ora.displayValues(root.ruleFor(m), m);
      for (const k in v) vals["display:" + m.name + ":" + k] = v[k];
    }
    root.displayValues = vals;
    root.revision++;
  }

  // The lit monitors as the rectangles they cover on the desktop, from what
  // hyprland reports — the live layout, whatever put it there.
  readonly property var arrangeRects: {
    const out = [];
    for (let i = 0; i < root.displays.length; ++i) {
      const m = root.displays[i];
      if (m.disabled) continue;
      const sz = Ora.logicalSize(m);
      out.push({ name: m.name, x: m.x, y: m.y, w: sz.w, h: sz.h });
    }
    return out;
  }

  // Every screen's position at once, from the Arrangement view: one write,
  // one reload, one "keep these settings?".
  function setDisplayPositions(rects) {
    const next = ({});
    for (const k in root.displayValues) next[k] = root.displayValues[k];
    let moved = false;
    for (const r of rects) {
      const k = "display:" + r.name + ":position";
      const v = r.x + "x" + r.y;
      if (next[k] === v) continue;
      next[k] = v;
      moved = true;
    }
    if (!moved) return;
    if (root.displayBefore === null) root.displayBefore = root.displayValues;
    root.displayValues = next;
    root.revision++;
    monitorsSaveTimer.restart();
  }

  function setDisplay(s, value) {
    const v = Ora.coerce(s, value);
    if (Ora.same(root.displayValues[s.key], v)) return;
    // never the last lit screen: there would be no way back to this panel
    if (s.field === "enabled" && v === false) {
      let lit = 0;
      for (let i = 0; i < root.displays.length; ++i)
        if (root.displayValues["display:" + root.displays[i].name + ":enabled"] !== false) ++lit;
      if (lit <= 1) {
        Quickshell.execDetached(["notify-send", "-a", "oracle", "Display",
          "That is the only screen that is on, so it stays on."]);
        return;
      }
    }
    const next = ({});
    for (const k in root.displayValues) next[k] = root.displayValues[k];
    // the last state you said yes to, kept until you say yes to this one
    if (root.displayBefore === null) root.displayBefore = root.displayValues;
    next[s.key] = v;
    root.displayValues = next;
    root.revision++;
    monitorsSaveTimer.restart();
  }

  function writeMonitors() {
    const entries = [];
    for (let i = 0; i < root.displays.length; ++i) {
      const m = root.displays[i];
      const v = ({});
      for (const f of ["enabled", "mode", "scale", "transform", "position", "vrr"])
        v[f] = root.displayValues["display:" + m.name + ":" + f];
      entries.push({ mon: m, values: v });
    }
    // rules for screens that are not here are carried through as they were
    const kept = root.monitorRules.filter((r) => r.output !== ""
      && !root.displays.some((m) => Ora.ruleMatches(r.output, m)));
    const text = Ora.renderMonitorRules(entries, kept,
      Ora.extraStatements(monitorsFile.text()));
    monitorsFile.setText(text);
    // ── WHAT WAS JUST WRITTEN IS WHAT THE RULES ARE NOW ─────────────
    // A FileView never reads back its own write: watchChanges sees the
    // file move, the reload it asks for is dropped, and `loaded` does not
    // fire (measured, 2026-10-08). So monitorRules stayed whatever the
    // file said BEFORE, the rescan after hyprland's reload folded those
    // stale rules back into displayValues, and every chip snapped back to
    // the old value while the screen showed the new one — and the next
    // change wrote the stale ones out again. Parsed from the text itself.
    root.monitorRules = Ora.parseMonitorRules(text);
    // a change of yours starts the clock; a revert, which has nothing
    // before it, does not
    if (root.displayBefore !== null) {
      root.displayCountdown = root.displayConfirmSecs;
      confirmTimer.restart();
    }
    // hyprland's own autoreload may or may not be watching a required file;
    // asking is cheap and makes the change land either way
    reloadHypr.restart();
  }

  // ── KEEP THESE SETTINGS? ─────────────────────────────────────────────
  // A mode, a scale, a rotation or "off" can leave a screen you cannot read —
  // and the control that would undo it is on that screen. So every change
  // is provisional: it goes back by itself unless you keep it, the way every
  // desktop has done it since the old System Preferences. Here rather than
  // in the window, so closing the window does not cancel the way back.
  readonly property int displayConfirmSecs: 15
  property var displayBefore: null
  readonly property bool displayPending: root.displayBefore !== null
  property int displayCountdown: 0

  Timer {
    id: confirmTimer
    interval: 1000
    repeat: true
    onTriggered: {
      if (--root.displayCountdown <= 0) root.revertDisplays();
    }
  }

  function keepDisplays() {
    confirmTimer.stop();
    root.displayBefore = null;
    root.revision++;
  }

  function revertDisplays() {
    confirmTimer.stop();
    monitorsSaveTimer.stop();
    if (root.displayBefore === null) return;
    root.displayValues = root.displayBefore;
    root.displayBefore = null;
    root.revision++;
    root.writeMonitors();
  }

  Timer {
    id: monitorsSaveTimer
    // a wheel run through a list of modes is a burst of sets; the screen
    // should change once, where it stopped
    interval: 600
    onTriggered: root.writeMonitors()
  }

  Timer {
    id: reloadHypr
    interval: 150
    onTriggered: {
      Quickshell.execDetached(["hyprctl", "reload"]);
      rescanTimer.restart();
    }
  }

  // the header rows read the live mode, which has only just changed
  Timer {
    id: rescanTimer
    interval: 1200
    onTriggered: root.scanDisplays()
  }

  function scanDisplays() {
    if (displayProc.running) return;
    displayProc.running = true;
  }

  Process {
    id: displayProc
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      id: displayOut
      waitForEnd: true
      onStreamFinished: {
        const found = Ora.parseHyprMonitors(displayOut.text);
        if (found.length === 0) return;   // not under hyprland, or it failed
        root.displays = found;
        root.syncDisplayValues();
        root.buildSchema();
      }
    }
  }

  FileView {
    id: monitorsFile
    path: root.monitorsPath
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      root.monitorRules = Ora.parseMonitorRules(monitorsFile.text());
      root.syncDisplayValues();
    }
    onLoadFailed: {
      root.monitorRules = [];
      root.syncDisplayValues();
    }
  }

  // a monitor plugged in or pulled out
  Connections {
    target: Quickshell
    function onScreensChanged() { root.scanDisplays(); }
  }


  // ── SHORTCUTS ─────────────────────────────────────────────────────────
  // hyprland's binds. binds.lua is the list — ids, labels, groups and the
  // default chords — and keys.lua, written here, the chords moved off them.
  // See Ora's SHORTCUTS for both files' shape.
  // the Hyprland files these settings write — yours, read by hyprland.lua
  // before the shipped ones of the same name (see hypr/hyprland.lua)
  readonly property string hyprLuaDir: root.zenworksDir + "/hypr/lua"
  // what ships beside the shell (/usr/share/zenworks, or a working copy's
  // config/): only read. Its Hyprland config gives binds.lua and
  // windowdefaults.lua; its kitty config is included by yours.
  readonly property string shippedDir: Quickshell.shellDir.replace(/\/[^\/]+\/?$/, "")
  readonly property string hyprShippedDir: root.shippedDir + "/hypr"
  readonly property string keysPath: root.hyprLuaDir + "/keys.lua"
  // hypr/lua/wake.lua: "key" or "mouse" — see Ora's WAKE
  // "mouse" by default (user, 2026-10-21)
  property string wakeBy: "mouse"
  function setWakeBy(v) {
    const by = v === "key" ? "key" : "mouse";
    if (by === root.wakeBy) return;
    root.wakeBy = by;
    root.revision++;
    wakeFile.setText(Ora.renderWakeLua(by));
    reloadHypr.restart();
  }

  // ── INPUT METHODS ── fcitx5, see Ora's INPUT METHODS. On/off is
  // hypr/lua/inputmethod.lua; the languages and the switch key are fcitx5's
  // own profile and config, read back so its configtool and these rows agree.
  property bool imOn: false
  property var imList: []                     // the profile's items, in order
  property string imKey: Ora.IM_KEY_DEFAULT
  property var imPackages: []                 // which of fcitx5's are installed
  property bool imWaiting: false              // Ceres is installing for a row
  property string imPending: ""               // that row's engine, "" for fcitx5 alone
  // the row whose tick is a turning ring while Ceres installs for it
  readonly property string imBusyKey: root.imWaiting ? (root.imPending !== "" ? "im:" + root.imPending : "im:on") : ""
  readonly property string imDir: root.configHome + "/fcitx5"
  signal imInstallAsked(var pkgs, string why)

  function imLayoutNow() {
    return Ora.imLayout(root.inputValues["input:kb_layout"], root.inputValues["input:kb_variant"]);
  }
  function imValue(key) {
    if (key === "im:on") return root.imOn;
    if (key === "im:key") return root.imKey;
    if (key === "im:add") return "";
    return root.imList.indexOf(key.slice(3)) >= 0;
  }
  function imEngine(im) {
    return Ora.IM_ENGINES.find((e) => e.im === im) || null;
  }
  function imRefresh() {
    imClassicFile.reload();
    imProfileFile.reload();
    imConfigFile.reload();
    if (!imPkgProc.running) imPkgProc.running = true;
  }
  // Written through sh, as fcitx5 has no directory until something writes
  // one, and in a .tmp first so fcitx5 never reads half a file. `then`:
  // "reload" tells a running fcitx5 to read it again, "start" (re)starts it.
  // A START STOPS THE OLD ONE BEFORE WRITING: fcitx5 saves its profile as it
  // exits, and one without the new engine loaded saved over ours, leaving
  // only the keyboard (2026-10-26) — so it is gone first, then the file.
  // A start also writes classicui.conf's text tray icon (Ora.imClassicUi).
  function imWrite(path, text, then) {
    const start = then === "start";
    Quickshell.execDetached(["sh", "-c",
      "put() { mkdir -p \"${2%/*}\" && printf %s \"$1\" > \"$2.tmp\" && mv -f \"$2.tmp\" \"$2\"; }; "
      + "if [ \"$2\" = start ] && fcitx5-remote --check; then fcitx5-remote -e; i=0; "
      + "while pgrep -u \"$(id -u)\" -x fcitx5 >/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done; fi; "
      + "put \"$1\" \"$3\" || exit 1; [ -n \"$5\" ] && put \"$4\" \"$5\"; "
      + "case $2 in reload) fcitx5-remote --check -r ;; start) fcitx5 -d --replace ;; esac; exit 0",
      "imwrite", text, then || "", path,
      start ? Ora.imClassicUi(imClassicFile.text()) : "", start ? root.imDir + "/conf/classicui.conf" : ""]);
  }

  function setIm(s, value) {
    const v = Ora.coerce(s, value);
    if (Ora.same(root.imValue(s.key), v)) return;
    if (s.key === "im:key") {
      root.imKey = v;
      root.revision++;
      root.imWrite(root.imDir + "/config", Ora.setImKey(imConfigFile.text(), v), "reload");
      return;
    }
    if (s.key === "im:on") { if (v) root.imTurnOn(null); else root.imTurnOff(); return; }
    if (s.key === "im:add") { const e = root.imEngine(v); if (e) root.imTurnOn(e); return; }
    if (v) { root.imTurnOn(s.engine); return; }
    root.imList = Ora.imItems(root.imList, root.imLayoutNow(), s.engine.im, false);
    root.revision++;
    root.imWrite(root.imDir + "/profile", Ora.renderImProfile(root.imLayoutNow(), root.imList), "reload");
  }
  // fcitx5 and an engine are installed the first time a row asks for them,
  // through Ceres (OracleManager answers imInstallAsked with imInstalled)
  function imTurnOn(engine) {
    if (root.imWaiting) { root.revision++; return; }
    const need = Ora.IM_BASE.concat(engine ? [engine.pkg] : [])
      .filter((p) => root.imPackages.indexOf(p) < 0);
    if (need.length > 0) {
      root.imWaiting = true;
      root.imPending = engine ? engine.im : "";
      root.revision++;
      root.imInstallAsked(need, engine ? "to type " + engine.label : "for input methods");
      return;
    }
    root.imApply(engine);
  }
  function imInstalled(ok) {
    const engine = root.imEngine(root.imPending);
    root.imWaiting = false;
    root.imPending = "";
    root.revision++;
    if (!imPkgProc.running) imPkgProc.running = true;
    if (ok) root.imApply(engine, true);
  }
  // `fresh`: something was just installed. fcitx5 loads its engines only as
  // it starts, and a reload does not look again (2026-10-26: Pinyin
  // installed under a running fcitx5 left Ctrl+Space nothing to switch to)
  function imApply(engine, fresh) {
    const layout = root.imLayoutNow();
    root.imList = Ora.imItems(root.imList, layout, engine ? engine.im : "", !!engine);
    const starting = !root.imOn;
    root.imOn = true;
    root.revision++;
    root.imWrite(root.imDir + "/profile", Ora.renderImProfile(layout, root.imList),
      starting || fresh ? "start" : "reload");
    if (starting) {
      imFile.setText(Ora.renderImLua(true));
      reloadHypr.restart();
    }
  }
  // the environment base.lua set stays until you log out; with fcitx5 gone,
  // apps fall back to typing as they always did
  function imTurnOff() {
    root.imOn = false;
    root.revision++;
    imFile.setText(Ora.renderImLua(false));
    Quickshell.execDetached(["sh", "-c", "fcitx5-remote --check -e; exit 0"]);
    reloadHypr.restart();
  }
  function imSettings() {
    if (root.imPackages.indexOf("fcitx5-configtool") < 0) {
      Quickshell.execDetached(["notify-send", "-a", "oracle", "Input methods",
        "Turn on Input methods first: that installs fcitx5 and its settings."]);
      return;
    }
    Quickshell.execDetached(["fcitx5-configtool"]);
  }

  // the rows, after the devices'
  function imSpecs() {
    const out = [
      { key: "imHead", section: "input", type: "info", label: "Input methods",
        alias: "input methods fcitx fcitx5 ime ibus chinese japanese korean vietnamese thai pinyin",
        help: "For languages a keyboard layout cannot type. fcitx5 turns what you type into the language's characters, with a list to choose from. Apps already open need a restart to use it." },
      { key: "im:on", section: "input", type: "bool", im: true, fallback: false, label: "Use input methods",
        alias: "fcitx fcitx5 ime",
        help: "Starts fcitx5 now and at every login. Installs it the first time (it asks for your password). Kept in ~/.config/zenworks/hypr/lua/inputmethod.lua." },
    ];
    // the languages you added, in fcitx5's order (one being installed shows
    // its ring here), then the dropdown that adds another
    const added = root.imList.slice();
    if (root.imPending !== "" && added.indexOf(root.imPending) < 0) added.push(root.imPending);
    for (const im of added) {
      const e = root.imEngine(im);
      if (!e) continue;
      out.push({ key: "im:" + e.im, section: "input", type: "bool", im: true, engine: e, fallback: true,
        label: e.label, alias: "input method language " + e.im,
        help: "Untick to take it off the list. Switch between it and your keyboard with the switch key. Kept in ~/.config/fcitx5/profile." });
    }
    out.push({ key: "im:add", section: "input", type: "enum", im: true, fallback: "",
      label: "Add a language", options: Ora.imAddable(added), chipW: 220,
      alias: "input method language chinese japanese korean vietnamese thai hindi tamil bengali arabic persian amharic khmer tibetan " + Ora.IM_ENGINES.map((e) => e.label.toLowerCase()).join(" "),
      help: "Installs what the language needs the first time (it asks for your password), then adds it to the switch key's list." });
    out.push({ key: "im:key", section: "input", type: "enum", im: true, fallback: Ora.IM_KEY_DEFAULT,
      label: "Switch key", options: Ora.IM_KEYS, alias: "input method trigger toggle",
      help: "Switches between your keyboard and the languages above while typing." });
    out.push({ key: "actionImSettings", section: "input", type: "action", verb: "Open",
      label: "More settings", alias: "fcitx5 configtool input method",
      help: "fcitx5's own settings: more languages, the candidate list, punctuation." });
    return out;
  }
  // hypr/lua/effects.lua: hyprland's shadows and animations, and the
  // windows' gaps, border, layout, edges, dim and opacity — see Ora's
  // EFFECTS. Each setting's spec names its field (`fx`).
  property bool hyprShadows: true
  property bool hyprAnimations: true
  property int hyprGapsOut: 8
  property int hyprGapsIn: 2
  property int hyprSpecialGaps: 30
  property int hyprBorder: 1
  property string hyprLayout: "dwindle"
  property bool hyprResizeBorder: false
  property real hyprDimInactive: 0
  property real hyprInactiveOpacity: 1
  readonly property var effectSpecs: root.specs.filter((s) => s.hyprFile === "effects")
  function effectValues() {
    const out = {};
    for (const s of root.effectSpecs) out[s.fx] = root[s.key];
    return out;
  }
  function setEffect(key, v) {
    const val = Ora.coerce(root.spec(key), v);
    if (Ora.same(root[key], val)) return;
    root[key] = val;
    root.revision++;
    effectsFile.setText(Ora.renderEffectsLua(root.effectValues()));
    reloadHypr.restart();
  }
  // hypr/lua/windows.lua: your window rules, in order — see Ora's WINDOW RULES
  property var windowRules: []
  readonly property string windowsPath: root.hyprLuaDir + "/windows.lua"
  // hypr/lua/windowdefaults.lua: the suite's own rules, read, never written —
  // a change to one is a stand-in in windowRules (Ora.windowRulesPatched)
  property var shippedRules: []
  // every change is the whole list; the panel edits a copy and hands it back
  function setWindowRules(list) {
    root.windowRules = (list || []).map(Ora.normWindowRule);
    root.revision++;
    windowsFile.setText(Ora.renderWindowsLua(root.windowRules));
    reloadHypr.restart();
  }
  // hypr/lua/startup.lua: your startup apps — see Ora's STARTUP. Read at
  // login only, so no reload: a change counts from the next one.
  property var startupApps: []
  readonly property string startupPath: root.hyprLuaDir + "/startup.lua"
  function setStartupApps(list) {
    root.startupApps = (list || []).map(Ora.normStartup);
    root.revision++;
    startupFile.setText(Ora.renderStartupLua(root.startupApps));
  }
  // what binds.lua declares: [{ id, chord, label, group }]
  property var bindList: []
  // "bind:<id>" -> the chord in force ("" off)
  property var keyValues: ({})
  // what keys.lua holds, by id
  property var keysRaw: ({})
  // hyprctl binds -j, for the binds other files make — see Ora.chordTaken
  property var liveBinds: []
  // the row waiting for a chord, while hyprland sits in the empty submap
  property string capturing: ""
  // a chord refused as a dupe: { key, text } for the row to show inline,
  // until the next try or six seconds pass
  property var bindRefusal: null
  Timer {
    id: refusalTimer
    interval: 6000
    onTriggered: root.bindRefusal = null
  }

  function keysSpecs() {
    const out = [];
    let group = null;
    for (const b of root.bindList) {
      if (b.group !== group) {
        group = b.group;
        // a head the group's binds fold under, each group in its own frame —
        // see the panel's foldGroup
        out.push({ key: "keysHead:" + group, section: "keys", type: "info", foldGroup: group,
          label: Ora.bindGroupLabel(group), help: "", alias: group.toLowerCase() });
      }
      out.push({ key: "bind:" + b.id, section: "keys", type: "chord", bindKey: true, inGroup: b.group,
        bindId: b.id, bindDefault: b.chord, label: b.label,
        alias: "shortcut keybind key bind chord " + Ora.bindGroupLabel(b.group) + " " + b.chord.toLowerCase() });
    }
    return out;
  }

  // the two files, folded into one chord per bind
  function syncKeyValues() {
    const vals = ({});
    for (const b of root.bindList) {
      const v = root.keysRaw[b.id];
      vals["bind:" + b.id] = typeof v === "string" ? Ora.normChord(v) : b.chord;
    }
    root.keyValues = vals;
    root.revision++;
  }

  // id -> chord, for Ora.chordTaken
  function bindChords() {
    const out = ({});
    for (const b of root.bindList) out[b.id] = root.keyValues["bind:" + b.id];
    return out;
  }

  // NO DUPES: a chord another bind answers to is refused, and says whose
  function setBind(s, value) {
    const v = Ora.normChord(value);
    if (Ora.same(root.keyValues[s.key], v)) return;
    const who = Ora.chordTaken(v, s.bindId, root.bindList, root.bindChords(), root.liveBinds);
    if (who !== "") {
      // said in the row itself, under its name — see OracleWindow's labels
      root.bindRefusal = { key: s.key,
        text: Ora.chordCaps(v).join(" ") + " is already " + who + ". Nothing was changed." };
      refusalTimer.restart();
      root.revision++;
      return;
    }
    root.bindRefusal = null;
    const next = ({});
    for (const k in root.keyValues) next[k] = root.keyValues[k];
    next[s.key] = v;
    root.keyValues = next;
    root.revision++;
    keysSaveTimer.restart();
  }

  function writeKeys() {
    const out = ({});
    for (const b of root.bindList) out[b.id] = root.keyValues["bind:" + b.id];
    keysFile.setText(Ora.renderKeysLua(out, root.bindList));
    // FileView's own write never fires loaded: what it now says, by hand
    const raw = ({});
    for (const b of root.bindList) if (out[b.id] !== b.chord) raw[b.id] = out[b.id];
    root.keysRaw = raw;
    reloadHypr.restart();
    liveBindsTimer.restart();
  }

  Timer {
    id: keysSaveTimer
    interval: 300
    onTriggered: root.writeKeys()
  }

  // ── WAITING FOR A CHORD ──
  // Hyprland acts on Super+K before any window sees it, so while a row waits
  // it is held in binds.lua's "oracle-keys" submap, which binds nothing, and
  // put back the moment the chord lands, the wait is called off, or ten
  // seconds pass — a submap left on would leave every bind dead.
  function beginCapture(key) {
    if (root.capturing === "") Hyprland.dispatch(Hypr.submap("oracle-keys"));
    root.capturing = key;
    root.bindRefusal = null;
    captureTimeout.restart();
  }
  function endCapture(chord) {
    if (root.capturing === "") return;
    const key = root.capturing;
    root.capturing = "";
    captureTimeout.stop();
    Hyprland.dispatch(Hypr.submap("reset"));
    if (chord !== undefined && chord !== null) root.set(key, chord);
  }
  Timer {
    id: captureTimeout
    interval: 10000
    onTriggered: root.endCapture()
  }

  function scanLiveBinds() {
    if (!liveBindsProc.running) liveBindsProc.running = true;
  }
  Timer {
    id: liveBindsTimer
    // after hyprland's reload has made the new binds
    interval: 1200
    onTriggered: root.scanLiveBinds()
  }
  Process {
    id: liveBindsProc
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector {
      id: liveBindsOut
      onStreamFinished: {
        try { root.liveBinds = JSON.parse(liveBindsOut.text); } catch (e) { root.liveBinds = []; }
      }
    }
  }

  FileView {
    id: bindsFile
    path: root.hyprShippedDir + "/lua/binds.lua"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      root.bindList = Ora.parseBindsLua(bindsFile.text());
      root.syncKeyValues();
      if (root.defaultsTaken) root.buildSchema();
      liveBindsTimer.restart();
    }
  }

  FileView {
    id: wakeFile
    path: root.hyprLuaDir + "/wake.lua"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    // FileView's own write never fires loaded: setWakeBy sets wakeBy itself
    onLoaded: {
      const by = Ora.parseWakeLua(wakeFile.text());
      if (by !== root.wakeBy) { root.wakeBy = by; root.revision++; reloadHypr.restart(); }
    }
    onLoadFailed: root.wakeBy = "mouse"
  }

  FileView {
    id: imFile
    path: root.hyprLuaDir + "/inputmethod.lua"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    // FileView's own write never fires loaded: imApply/imTurnOff set imOn
    onLoaded: {
      const on = Ora.parseImLua(imFile.text());
      if (on !== root.imOn) { root.imOn = on; root.revision++; }
    }
    onLoadFailed: root.imOn = false
  }
  FileView {
    id: imProfileFile
    path: root.imDir + "/profile"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { root.imList = Ora.parseImProfile(imProfileFile.text()).items; root.revision++; }
    onLoadFailed: root.imList = []
  }
  FileView {
    id: imConfigFile
    path: root.imDir + "/config"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { root.imKey = Ora.parseImKey(imConfigFile.text()); root.revision++; }
    onLoadFailed: root.imKey = Ora.IM_KEY_DEFAULT
  }
  // read only to keep what the configtool put beside PreferTextIcon;
  // watched, so a start never writes back an older copy of it
  FileView {
    id: imClassicFile
    path: root.imDir + "/conf/classicui.conf"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
  }
  Process {
    id: imPkgProc
    command: ["pacman", "-Qq"].concat(Ora.IM_BASE, Ora.IM_ENGINES.map((e) => e.pkg)
      .filter((p, i, all) => all.indexOf(p) === i))
    stdout: StdioCollector {
      id: imPkgOut
      onStreamFinished: root.imPackages = imPkgOut.text.split("\n").filter((l) => l !== "")
    }
  }

  FileView {
    id: effectsFile
    path: root.hyprLuaDir + "/effects.lua"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    // FileView's own write never fires loaded: setEffect sets the pair itself
    onLoaded: {
      const fx = Ora.parseEffectsLua(effectsFile.text());
      let changed = false;
      for (const s of root.effectSpecs) {
        if (Ora.same(root[s.key], fx[s.fx])) continue;
        root[s.key] = fx[s.fx];
        changed = true;
      }
      if (!changed) return;
      root.revision++;
      reloadHypr.restart();
    }
    onLoadFailed: { for (const s of root.effectSpecs) root[s.key] = s.hyprDefault; }
  }

  // FileView's own write never fires loaded: the setters set the list themselves
  FileView {
    id: windowsFile
    path: root.windowsPath
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      const rules = Ora.parseWindowsLua(windowsFile.text());
      if (JSON.stringify(rules) === JSON.stringify(root.windowRules)) return;
      root.windowRules = rules;
      root.revision++;
      reloadHypr.restart();
    }
    onLoadFailed: root.windowRules = []
  }
  FileView {
    id: shippedFile
    path: root.hyprShippedDir + "/lua/windowdefaults.lua"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { root.shippedRules = Ora.parseWindowDefaults(shippedFile.text()); root.revision++; }
    onLoadFailed: root.shippedRules = []
  }
  FileView {
    id: startupFile
    path: root.startupPath
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      const apps = Ora.parseStartupLua(startupFile.text());
      if (JSON.stringify(apps) === JSON.stringify(root.startupApps)) return;
      root.startupApps = apps;
      root.revision++;
    }
    onLoadFailed: root.startupApps = []
  }

  FileView {
    id: keysFile
    path: root.keysPath
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      const raw = Ora.parseDefaultsLua(keysFile.text());
      const before = JSON.stringify(root.keysRaw);
      root.keysRaw = raw;
      root.syncKeyValues();
      // a hand edit lands without waiting for a login; our own write, read
      // back, is what keysRaw already said
      if (JSON.stringify(raw) !== before) reloadHypr.restart();
    }
    onLoadFailed: { root.keysRaw = ({}); root.syncKeyValues(); }
  }

  // ── INPUT ─────────────────────────────────────────────────────────────
  // Every input setting hyprland has. The values are kept in
  // hypr/lua/input.lua, not in oracle.json: see Ora's INPUT for why, and for
  // the file's shape. Applied by reloading hyprland, which reads the file
  // through base.lua.
  // key ("input:kb_layout") -> value, as the file says
  property var inputValues: ({})
  // what the file holds, every key — hand-written ones included, so a write
  // from here carries them through
  property var inputRaw: ({})
  property bool inputLoaded: false
  // the layouts and variants xkeyboard-config knows (Ora.parseXkbList)
  property var xkb: ({ layouts: [], variants: ({}) })
  // what is plugged in, by group (Ora.inputDevices) — the headers say it
  property var inputDevices: ({})

  readonly property string inputPath: root.hyprLuaDir + "/input.lua"

  // A header row for each group, as each monitor has one, then the group's
  // fields as Ora describes them; a field's options that are facts about this
  // machine are filled in from here.
  function inputSpecs() {
    const out = [];
    const ctx = {
      xkb: root.xkb,
      layout: root.inputValues["input:kb_layout"] || "us",
      screens: root.displays.map((m) => m.name),
    };
    for (const g of Ora.inputGroups()) {
      out.push({ key: "inputHead:" + g.id, section: "input", type: "info",
        label: g.label, help: g.help, alias: g.label.toLowerCase() + " " + g.help });
      for (const f of Ora.inputFields()) {
        if (f.group !== g.id) continue;
        const c = { key: "input:" + f.key, section: "input", input: true, field: f.key };
        for (const k in f) if (["key", "group", "def"].indexOf(k) < 0) c[k] = f[k];
        if (typeof f.options === "string") c.options = Ora.inputOptions(f.options, ctx);
        out.push(c);
      }
    }
    return out;
  }

  // the file, folded into one value per row; a key it lacks is hyprland's
  // default, and a value of the wrong kind is coerced like any other
  function syncInputValues(raw) {
    const vals = ({});
    for (const k of Ora.inputKeys()) {
      const s = root.spec("input:" + k);
      const v = raw[k] === undefined ? Ora.inputDefault(k) : raw[k];
      vals["input:" + k] = s ? Ora.coerce(s, v) : v;
    }
    root.inputRaw = raw;
    root.inputValues = vals;
    root.revision++;
  }

  function setInput(s, value) {
    const v = Ora.coerce(s, value);
    if (Ora.same(root.inputValues[s.key], v)) return;
    // a layout xkb does not know would leave the keyboard ignoring the file
    const wrong = Ora.inputCheck(root.xkb, s.field, v, root.inputValues["input:kb_layout"]);
    if (wrong !== "") {
      Quickshell.execDetached(["notify-send", "-a", "oracle", "Keyboard", wrong + " Nothing was changed."]);
      root.revision++;
      return;
    }
    const next = ({});
    for (const k in root.inputValues) next[k] = root.inputValues[k];
    next[s.key] = v;
    // a variant belongs to its layout; another layout's would be refused
    if (s.field === "kb_layout") next["input:kb_variant"] = "";
    root.inputValues = next;
    root.revision++;
    // the variants offered are the new layout's
    if (s.field === "kb_layout") root.buildSchema();
    inputSaveTimer.restart();
  }

  function writeInput() {
    const out = ({});
    for (const k in root.inputRaw) out[k] = root.inputRaw[k];
    for (const k of Ora.inputKeys()) out[k] = root.inputValues["input:" + k];
    root.inputRaw = out;
    inputFile.setText(Ora.renderInputLua(out));
    reloadHypr.restart();
  }

  Timer {
    id: inputSaveTimer
    // a slider dragged is a burst of sets; hyprland reloads once, at the end
    interval: 500
    onTriggered: root.writeInput()
  }

  FileView {
    id: inputFile
    path: root.inputPath
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      const raw = Ora.parseInputLua(inputFile.text());
      const first = !root.inputLoaded;
      const before = root.inputValues;
      root.inputLoaded = true;
      root.syncInputValues(raw);
      if (first) return;
      // a hand edit lands without waiting for a login; our own write, read
      // back, changes nothing and has reloaded already
      for (const k in root.inputValues)
        if (!Ora.same(before[k], root.inputValues[k])) { reloadHypr.restart(); return; }
    }
    onLoadFailed: { root.inputLoaded = true; root.syncInputValues(({})); }
  }

  // xkeyboard-config's list, once: it changes when the package does
  FileView {
    id: xkbFile
    path: "/usr/share/X11/xkb/rules/evdev.lst"
    blockLoading: true
    printErrors: false
    onLoaded: {
      root.xkb = Ora.parseXkbList(xkbFile.text());
      if (root.defaultsTaken) root.buildSchema();
    }
  }

  function scanInputDevices() {
    root.imRefresh();
    if (inputDevProc.running) return;
    inputDevProc.running = true;
  }

  Process {
    id: inputDevProc
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector {
      id: inputDevOut
      onStreamFinished: {
        root.inputDevices = Ora.inputDevices(inputDevOut.text);
        root.revision++;
      }
    }
  }

  // ── DEFAULT APPS ──────────────────────────────────────────────────────
  // What is installed and what opens what, from oracle/defaults.sh. The
  // values are kept in hypr/lua/defaults.lua, not in oracle.json: see Ora's
  // DEFAULT APPLICATIONS for why, and for the file's shape.
  property var appScan: ({ apps: [], current: ({}), terminal: "", bins: [] })
  property bool appsScanned: false
  // key ("default:images") -> value, as the file says
  property var appDefaults: ({})
  // what the file holds, every key — hand-written ones included, so a write
  // from here carries them through
  property var defaultsRaw: ({})
  // the values last handed to gio and xdg-terminals.list, so the file being
  // read back after our own write is not applied a second time
  property var appliedDefaults: ({})
  property bool defaultsLoaded: false

  // What the rest of the shell reads: cynosure runs commands in the terminal,
  // and picasso offers the image editor.
  readonly property string terminal: root.appDefaults["default:terminal"] || "kitty"
  readonly property string imageEditor: root.appDefaults["default:image_editor"] || ""
  readonly property string imageEditorName: {
    const a = Ora.appById(root.appScan.apps, root.imageEditor);
    return a ? a.name : root.imageEditor.replace(/\.desktop$/, "");
  }

  // the five programs, then the kinds — the file's own order
  readonly property var programKeys: ["terminal", "browser", "editor", "sysmon", "image_editor"]
  function defaultsKeys() {
    return root.programKeys.concat(Ora.appKinds().map((k) => k.id).filter((k) => k !== "browser"));
  }

  // What a row holds before anybody chooses. Only these are worked out from
  // the machine; a kind is the system's answer, or this shell's own app.
  function appFallback(key) {
    if (key === "terminal") return Ora.terminalFallback(root.appScan.apps);
    if (key === "editor") return Ora.editorFallback(root.appScan.apps, root.appScan.bins);
    if (key === "sysmon") return "zeus";
    // a kind's pinned app, if this machine has it; System if not
    const k = Ora.appKind(key);
    const p = (k && k.preferred) || "";
    return p !== "" && Ora.appById(root.appScan.apps, p) ? p : "";
  }

  readonly property string defaultsPath: root.hyprLuaDir + "/defaults.lua"

  function defaultsSpecs() {
    const out = [];
    const apps = root.appScan.apps;
    const row = (kind, extra) => {
      const c = { key: "default:" + kind, section: "defaults", appDefault: true,
                  kind: kind, type: "enum", open: true, chipW: 208 };
      for (const k in extra) c[k] = extra[k];
      return c;
    };
    out.push(row("terminal", { label: "Terminal",
      alias: "terminal emulator console shell kitty foot alacritty",
      options: Ora.terminalOptions(apps),
      help: "What Super+Return opens, and what every terminal application — nvim, btop, anything opened from a file or from cynosure — is run inside." }));
    const kinds = Ora.appKinds();
    const kindRow = (k) => row(k.id, { label: k.label, alias: "default app open with " + k.alias,
      options: Ora.appOptions(k, apps, root.appScan.current[k.probe]),
      help: (k.help ? k.help + " " : "")
        + "System leaves it to whatever already opens it." });
    out.push(kindRow(kinds[0]));   // the browser, beside the terminal
    out.push(row("editor", { label: "Editor",
      alias: "editor EDITOR VISUAL plato nvim vim nano helix git commit sudoedit",
      options: Ora.editorOptions(apps, root.appScan.bins),
      help: "$EDITOR and $VISUAL — what git, sudoedit and crontab open a file in. Plato is this shell's own: they wait for its tab to close. A terminal one opens inside the terminal they were run from. Reaches what hyprland starts from now on; a shell already open keeps the old one." }));
    out.push(row("sysmon", { label: "System monitor",
      alias: "system monitor task manager processes btop htop zeus",
      options: Ora.sysmonOptions(apps, root.appScan.bins),
      help: "What Super+Shift+S opens. Zeus is this shell's own — the same panel as Super+K. A terminal one runs in the terminal above." }));
    out.push(row("image_editor", { label: "Image editor",
      alias: "image editor gimp krita photo paint edit picture",
      options: Ora.imageEditorOptions(apps),
      help: "Not a default for any picture — Images is. Picasso offers it in its menu, as Edit in …, for the picture you are looking at." }));
    for (let i = 1; i < kinds.length; ++i) out.push(kindRow(kinds[i]));
    return out;
  }

  function scanApps() {
    if (appsProc.running) return;
    appsProc.command = ["bash", Quickshell.shellDir + "/oracle/defaults.sh"]
      .concat(Ora.appProbes()).concat(["--"]).concat(Ora.knownBins());
    appsProc.running = true;
  }

  // Not at startup itself: the scan reads every desktop entry there is, and
  // the first seconds of the session belong to the arrival.
  Timer {
    id: appsFirstScan
    interval: 5000
    onTriggered: root.scanApps()
  }

  Process {
    id: appsProc
    stdout: StdioCollector {
      id: appsOut
      waitForEnd: true
      onStreamFinished: {
        const first = !root.appsScanned;
        root.appScan = Ora.readDefaultsScan(appsOut.text);
        root.appsScanned = true;
        root.buildSchema();
        root.revision++;
        if (first) root.reconcileDefaults();
      }
    }
  }

  // ── THE FILE WINS, ONCE A SESSION ────────────────────────────────────
  // Whatever defaults.lua names is put back at the start of a session if
  // something else moved it in the meantime — an install that registered
  // itself, a file edited while the shell was not running. Only then: a
  // default chosen later in terminus' Open with is a choice too, and undoing
  // it every time this section opened would be the panel arguing with you.
  function reconcileDefaults() {
    // A machine with no defaults.lua gets one, so the binds have a terminal
    // that is actually installed — and a file from before a row existed gets
    // that row, at its fallback, worked out now that the scan has said what
    // is here.
    const missing = root.defaultsKeys().filter((k) => !(k in root.defaultsRaw));
    if (!root.defaultsLoaded || missing.length > 0) {
      const next = ({});
      for (const k in root.appDefaults) next[k] = root.appDefaults[k];
      for (const k of missing) next["default:" + k] = root.appFallback(k);
      root.appDefaults = next;
      root.writeDefaults();
    }
    const kinds = Ora.appKinds();
    for (let i = 0; i < kinds.length; ++i) {
      const id = root.appDefaults["default:" + kinds[i].id];
      if (id && root.appScan.current[kinds[i].probe] !== id) root.applyAppDefault(kinds[i].id, id);
    }
    const term = Ora.terminalEntry(root.appDefaults["default:terminal"], root.appScan.apps);
    if (term !== "" && root.appScan.terminal !== term) root.applyAppDefault("terminal", root.appDefaults["default:terminal"]);
  }

  // the file → the rows' values, every key filled
  // A key the file does not have yet is its fallback; one it has as "" is a
  // choice — "leave it to the system" — except for the three the binds have
  // to have something to run.
  function syncAppDefaults(raw) {
    const vals = ({});
    const must = ["terminal", "editor", "sysmon"];
    for (const k of root.defaultsKeys()) {
      const v = typeof raw[k] === "string" ? raw[k].trim() : null;
      vals["default:" + k] = v === null || (v === "" && must.indexOf(k) >= 0)
        ? root.appFallback(k) : v;
    }
    root.defaultsRaw = raw;
    root.appDefaults = vals;
    root.revision++;
  }

  function setAppDefault(s, value) {
    const v = Ora.coerce(s, value);
    if (Ora.same(root.appDefaults[s.key], v)) return;
    // these have to be something: the binds run them
    if (["terminal", "editor", "sysmon"].indexOf(s.kind) >= 0 && String(v).trim() === "") return;
    const next = ({});
    for (const k in root.appDefaults) next[k] = root.appDefaults[k];
    next[s.key] = v;
    root.appDefaults = next;
    root.revision++;
    root.applyAppDefault(s.kind, v);
    defaultsSaveTimer.restart();
  }

  // ── HANDING A CHOICE TO THE DESKTOP ──────────────────────────────────
  // `gio mime`, one type at a time, for the reason terminus' Open with uses
  // it (see setDefaultAppCommand there): it writes [Added Associations] as
  // well as the default, which is the half gio's own lookups can see. The
  // types go in as arguments, so nothing here is quoted by hand.
  //
  // "" — back to the system — changes nothing: whatever opens it now goes on
  // opening it, and the file simply stops saying so.
  function applyAppDefault(kind, value) {
    const next = ({});
    for (const k in root.appliedDefaults) next[k] = root.appliedDefaults[k];
    next[kind] = value;
    root.appliedDefaults = next;
    if (value === "") return;
    if (kind === "terminal") {
      const id = Ora.terminalEntry(value, root.appScan.apps);
      if (id === "") return;
      // first in xdg-terminals.list, the rest kept below it in their order
      Quickshell.execDetached(["sh", "-c",
        'f="${XDG_CONFIG_HOME:-$HOME/.config}/xdg-terminals.list"; '
        + '{ printf "%s\\n" "$1"; [ -f "$f" ] && grep -vxF "$1" "$f"; true; } > "$f.part" && mv -f "$f.part" "$f"',
        "sh", id]);
    } else {
      // the programs are the binds' and picasso's, read from the file alone
      const k = Ora.appKind(kind);
      if (!k) return;
      const types = Ora.typesFor(k, Ora.appById(root.appScan.apps, value));
      Quickshell.execDetached(["sh", "-c",
        'id=$1; shift; for m; do gio mime "$m" "$id" >/dev/null 2>&1; done',
        "sh", value].concat(types));
    }
    appsRescan.restart();
  }

  // the "System · …" labels say what opens it now, which has just changed
  Timer {
    id: appsRescan
    interval: 1500
    onTriggered: root.scanApps()
  }

  Timer {
    id: defaultsSaveTimer
    interval: 400
    onTriggered: root.writeDefaults()
  }

  function writeDefaults() {
    const out = ({});
    for (const k in root.defaultsRaw) out[k] = root.defaultsRaw[k];
    for (const k of root.defaultsKeys()) {
      const v = root.appDefaults["default:" + k];
      out[k] = v === undefined ? root.appFallback(k) : v;
    }
    // the binds and the environment read these when hyprland loads them
    const binds = ["terminal", "browser", "editor", "sysmon"]
      .some((k) => out[k] !== root.defaultsRaw[k]);
    root.defaultsRaw = out;
    defaultsFile.setText(Ora.renderDefaultsLua(out));
    root.defaultsLoaded = true;
    // the binds read the terminal and the browser when hyprland loads them
    if (binds) reloadHypr.restart();
  }

  FileView {
    id: defaultsFile
    path: root.defaultsPath
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      const raw = Ora.parseDefaultsLua(defaultsFile.text());
      const first = !root.defaultsLoaded;
      root.defaultsLoaded = true;
      root.syncAppDefaults(raw);
      // At startup the file is only READ — reconcileDefaults decides, once
      // the scan has said what the system uses now. After that, a change
      // made by hand is applied like one made here.
      const kinds = root.defaultsKeys();
      if (first) {
        const a = ({});
        for (const k of kinds) a[k] = root.appDefaults["default:" + k];
        root.appliedDefaults = a;
        return;
      }
      let binds = false;
      for (const k of kinds) {
        const v = root.appDefaults["default:" + k];
        if (root.appliedDefaults[k] === v) continue;
        root.applyAppDefault(k, v);
        if (["terminal", "browser", "editor", "sysmon"].indexOf(k) >= 0) binds = true;
      }
      // a hand edit to what the binds read lands without waiting for a login
      if (binds) reloadHypr.restart();
    }
    onLoadFailed: root.syncAppDefaults(({}))
  }

  // ── persistence ───────────────────────────────────────────────────────
  // The same FileView + debounced setText shape chronos, picasso and artemis
  // use. blockLoading, because the first frame of the shell is drawn from
  // these values and a bar that arrives at its defaults and then jumps to
  // yours a frame later is worse than a few milliseconds at startup.
  readonly property string statePath: Quickshell.statePath("oracle.json")

  FileView {
    id: stateFile
    path: root.statePath
    blockLoading: true
    printErrors: false
    // RELOAD IS ASYNCHRONOUS, and blockLoading does not change that — it
    // governs the FIRST read, not a later reload. The first version of the
    // reload action called reload() and then load() on the very next line,
    // which read the text that was already there: editing the file by hand and
    // pressing Reload did nothing at all, silently and repeatably. Measured by
    // writing the file from a subprocess and watching the values not move.
    //
    // So the apply happens HERE, when the bytes have actually arrived, and the
    // action below only asks for them.
    onLoaded: {
      if (!root._reloadWanted) return;
      root._reloadWanted = false;
      // a file that cannot be read changes nothing: kept aside, and said
      if (!Ora.parses(stateFile.text())) { root.keepBroken(true); return; }
      // A hand-edited file can have LOST a key as well as gained one, and
      // load() only applies what it finds — a setting deleted by hand would
      // otherwise keep whatever it currently held, which is not what the file
      // now says. Cleared first, so "reload" means the file and nothing else.
      root.resetAll();
      root.load();
      // the file is what holds now: nothing before it to go back to
      history.clear();
    }
  }

  // Set while a reload is in flight, so onLoaded can tell one apart from the
  // read that happens at startup and from the reads our own setText provokes.
  property bool _reloadWanted: false

  function reloadFromDisk() {
    root._reloadWanted = true;
    stateFile.reload();
  }

  Timer {
    id: saveTimer
    // A slider dragged across its range is a burst of sets; this writes once
    // at the end of the gesture rather than on every pixel of it.
    interval: 400
    onTriggered: root.save()
  }

  function save() {
    const vals = ({});
    const own = root.schema.filter((s) => !s.display && !s.appDefault && !s.input && !s.bindKey && !s.hyprFile);
    for (let i = 0; i < own.length; ++i) {
      const s = own[i];
      if (Ora.stored(s)) vals[s.key] = root[s.key];
    }
    stateFile.setText(Ora.serialize(own, vals, root.defaults));
  }

  // Applies the file over whatever is currently held. It is not a full
  // restore on its own — see actionReload, which clears first — because at
  // startup there is nothing to clear and a reset pass would write the file
  // back out for no reason.
  // oracle.json that is not JSON: a copy kept beside it before anything
  // writes over it, and a notice (Strings.keepAside). On a reload nothing
  // else happens; at startup the shell goes on at its defaults.
  function keepBroken(reloading) { Strings.keepAside(root.statePath, "oracle"); }

  function load() {
    if (!Ora.parses(stateFile.text())) root.keepBroken(false);
    const j = Ora.parse(root.schema, stateFile.text());
    // ── THE OLD KEYBOARD NAME, CARRIED OVER ──────────────────────────
    // idleKeyboardName was one device, typed in. It is now one entry of
    // idleLightDevices; parse drops keys the schema no longer has, so it
    // is read out of the raw file here, once, and the next save writes
    // the new key and leaves the old one behind.
    if (!("idleLightDevices" in j)) {
      let raw = null;
      try { raw = JSON.parse(String(stateFile.text() || "{}")); } catch (e) { raw = null; }
      if (raw && typeof raw.idleKeyboardName === "string") {
        const name = raw.idleKeyboardName.trim();
        j.idleLightDevices = name === "" ? "" : name;
        saveTimer.restart();
      }
    }
    for (const k in j) {
      if (Ora.same(root[k], j[k])) continue;
      root[k] = j[k];
    }
    root.revision++;
  }

  // The STORE's ipc. The panel has its own handler under "Oracle", so that
  // `qs ipc call Oracle toggle` reads the way it does for every other layer in
  // this shell; this one is the half a script talks to.
  IpcHandler {
    target: "OracleSettings"

    // `qs ipc call OracleSettings get notifTimeout`, for a script that wants
    // to read one without parsing the file.
    function get(key: string): string {
      const s = root.spec(key);
      if (!s) return "no such setting: " + key;
      if (!Ora.stored(s)) return root.info(key);
      return String(root.get(key));
    }

    // and the write, which takes the same coercion every other path does — so
    // `set cornerRadius 999` lands at the slider's own maximum rather than at 999.
    function set(key: string, value: string): string {
      const s = root.spec(key);
      if (!s || !Ora.stored(s)) return "no such setting: " + key;
      root.set(key, s.type === "bool"
        ? (value === "1" || value.toLowerCase() === "true" || value.toLowerCase() === "on")
        : (s.type === "int" || s.type === "real") ? Number(value) : value);
      return key + " = " + String(root.get(key));
    }

    // the two answers to "keep these display settings?"
    function keepDisplay(): string { root.keepDisplays(); return "kept"; }
    function revertDisplay(): string { root.revertDisplays(); return "reverted"; }

    function reset(key: string): string {
      if (key === "" || key === "all") { root.resetAll(); return "reset everything"; }
      root.reset(key);
      return key + " = " + String(root.get(key));
    }

    // every setting that is not at its default, one per line
    function changed(): string {
      const out = [];
      for (let i = 0; i < root.schema.length; ++i) {
        const s = root.schema[i];
        if (!Ora.stored(s) || s.display || s.appDefault || s.input || s.bindKey || s.hyprFile || root.isDefault(s.key)) continue;
        out.push(s.key + " = " + String(root[s.key])
          + "  (default " + String(root.defaults[s.key]) + ")");
      }
      return out.length === 0 ? "everything is at its default" : out.join("\n");
    }
  }

  // buildSchema BEFORE load, and load before anything else has had a chance to
  // write: the defaults are the properties as declared, so they have to be
  // read while that is still what they are.
  Component.onCompleted: {
    root.buildSchema();
    root.load();
    root.scanSolaar();
    root.scanThemes();
    root.scanFonts();
    root.scanDisplays();
    root.scanInputDevices();
    appsFirstScan.start();
  }
}
