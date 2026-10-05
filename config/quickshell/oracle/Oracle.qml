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
import "oracle.js" as Ora

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
  property int barRadius: 8
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
  // Whether tiled windows are kept clear of the pill. Off, the pill floats
  // over whatever is underneath it and nothing on the desktop moves for it.
  property bool barReserveSpace: true

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
  // It must be a Nerd Font: every icon in this shell is a glyph in the
  // private use area, and a face without them draws a column of empty boxes.
  property string fontFamily: "JetBrainsMono Nerd Font"

  // The corner a MENU is cut with. Deliberately not the panels' radius: a
  // menu is a small card over your work and a panel is a large surface at an
  // edge, and the corner that suits one looks wrong on the other.
  property int menuRadius: 6

  // ── how it is painted ─────────────────────────────────────────────────
  // Alpha over black, both of them. Hyprland's blur has an `ignore_alpha`
  // threshold — 0.5 on this machine — so a surface taken past that stops being
  // blurred and becomes a flat panel. That is a legitimate thing to want; it
  // is just worth knowing which side of the line you are on.
  property real barOpacity: 0.50
  property real panelOpacity: 0.80
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
  property real menuOpacity: 0.60
  // Every scrollbar in the shell (morpheus/Scrollbar) fades out once the
  // list stops moving, and comes back on a scroll or under the pointer. Off,
  // the thumb is always faintly there, as it used to be.
  property bool scrollbarAutohide: true

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
  // how far the stack floats above the pill
  property int notifLift: 20
  // whether a music player's track change earns a row in the bell's history.
  // Off by default: the track name is already in the bar.
  property bool notifTrackMusic: false
  // Do not disturb: toasts are held back (a critical one still shows) and
  // everything still lands in the bell's history, unread.
  property bool notifSilent: false
  property int notifHistoryCap: 200
  property int notifRadius: 5
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
  property int notifIconRadius: 5
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
  // "$HOME/Pictures/Wallpapers" is a path that happens to be true on the
  // machine this was written on: the folder name is in no specification, so a
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
  // How hard the desktop behind the lock is blurred. See CerberusLock's
  // blurPipeline: the blur is done ONCE at capture by downsampling, blurring
  // and upsampling again, so this is the percentage the shot is reduced to —
  // smaller is blurrier, and the cost is paid at lock time rather than on
  // every frame.
  property int lockBlurStrength: 8
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
  readonly property var sections: [
    // FIRST, because it is the one that reaches everything else. Three of
    // these used to sit under Bar — the corner radius, the maximum width and
    // the screen clearance — which was where the code that reads them lives
    // rather than where they apply: every layer in the shell takes all three
    // through Zenon, not just the pill.
    { id: "look",   label: "Global",        icon: "\uF0AC",
      blurb: "what every component shares \u2014 the type, the corners, the surfaces" },
    { id: "display", label: "Display",      icon: "\uF108",
      blurb: "hyprland's monitors \u2014 resolution, refresh, scale, rotation" },
    { id: "input",  label: "Input",         icon: "\uF11C",
      blurb: "hyprland's keyboard, mouse, touchpad and tablet \u2014 layout, speed, focus" },
    { id: "bar",    label: "Bar",           icon: "",
      blurb: "morpheus — the pill and what it carries" },
    { id: "motion", label: "Motion",        icon: "",
      blurb: "how long everything in this shell takes" },
    { id: "notify", label: "Notifications", icon: "",
      blurb: "howler — toasts, and what the bell remembers" },
    { id: "paper",  label: "Background",    icon: "",
      blurb: "picasso — the background, screenshots and the color picker" },
    { id: "idle",   label: "Idle & Lock",   icon: "",
      blurb: "socordia and cerberus — being away from the machine" },
    { id: "time",   label: "Time & Weather", icon: "",
      blurb: "chronos — the clock, the calendar, the forecast" },
    { id: "system", label: "System",        icon: "",
      blurb: "zeus and the update count — what is measured, how often" },
    { id: "menu",   label: "Desktop Menu",  icon: "",
      blurb: "icarus — what right-clicking the desktop offers" },
    { id: "defaults", label: "Default Apps", icon: "\uF009",
      blurb: "what opens what \u2014 the terminal, the browser, every kind of file" },
    { id: "health", label: "Health",        icon: "\uF0F1",
      blurb: "a checkup of this shell \u2014 what an audit looks for" },
    { id: "about",  label: "About",         icon: "",
      blurb: "zenworks — this shell, and the whole of these settings" }
  ]

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
    { key: "barPosition", section: "bar", label: "Position", type: "enum",
      options: [ { value: "bottom", label: "Bottom" },
                 { value: "top",    label: "Top" } ],
      help: "Which edge the pill lives on. Every layer that opens out of it follows, and so do the toasts and the tooltips." },
    { key: "barMonitor", section: "bar", label: "Monitor", type: "enum",
      optionsFrom: "screens", open: true,
      help: "Which output the pill lives on. Automatic follows $QS_STATUS_SCREEN, then the first screen there is." },
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
      help: "Extra room kept clear above the pill, on top of its own height. Nothing happens here if the bar is not reserving space." },
    { key: "barBlur", section: "bar", alias: "blur transparency frosted glass background hyprland",
      label: "Blur behind", type: "bool",
      help: "Keeps the desktop behind the pill frosted as you make it see-through. hyprland will not blur under a pixel below alpha 0.5, and Bar opacity starts at exactly that — so without this, every step towards transparent hands the blur back and the desktop reads through sharp. The cost is the floor itself: with this on, Bar opacity under 0.52 has nowhere further to go." },
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
    { key: "barTooltips", section: "bar", label: "Hover tooltips", type: "bool",
      help: "The hover text on the bar's modules." },
    { key: "showTray", section: "bar", label: "System tray", type: "bool",
      help: "Hidden inside the workspace row until you hover it. Off, tray applications keep running with nowhere to appear." },
    { key: "barReserveSpace", section: "bar", label: "Reserve space", type: "bool",
      help: "Keep tiled windows clear of the pill. Off, it floats over them and nothing on the desktop moves for it." },

    // ── appearance ──
    // `pick` makes a text setting a button that opens terminus' picker
    // rather than a field to type into — see PickControl in the panel.
    { key: "fontFamily", section: "look", label: "Font", type: "text",
      pick: "font", placeholder: "JetBrainsMono Nerd Font",
      help: "Pick any cut of a Nerd Font in terminus — the family is read out of the file, and the shell picks the right cut per use. It must be a Nerd Font: every icon here is a glyph in one." },
    { key: "barRadius", section: "look", label: "Corner radius", type: "int",
      min: 0, max: 20, step: 1, unit: "px",
      help: "The pill, and every panel that opens out of it." },
    { key: "barMaxWidth", section: "look", label: "Maximum panel width", type: "int",
      min: 400, max: 2400, step: 20, unit: "px",
      help: "How wide any panel may grow. Always rounded down to an even number, so centering it lands on a whole pixel." },
    { key: "barScreenPad", section: "look", label: "Gap to screen edge", type: "int",
      min: 0, max: 48, step: 1, unit: "px",
      help: "How far the pill floats off whichever edge it lives on. Every layer that opens out of it follows, or they would not line up with it." },
    { key: "menuRadius", section: "look", label: "Menu corner radius", type: "int",
      min: 0, max: 16, step: 1, unit: "px",
      help: "Every menu on the desktop: icarus', the tray's, terminus' right-click menu, and the cards picasso and this panel open. Separate from the panels' radius — a small card over your work wants a different corner from a large surface at an edge." },
    { key: "barOpacity", section: "look", alias: "transparency translucency see-through morpheus pill bar background", label: "Bar opacity", type: "real",
      min: 0.1, max: 1, step: 0.05,
      help: "The morpheus pill's own background, and the small furniture painted to match it: tooltips, the now-playing card, chronos' day cells. Alpha over black, so lower is more transparent. Under 0.5 hyprland stops blurring behind the pill — unless Blur behind, in morpheus, is holding it at that floor." },
    { key: "panelOpacity", section: "look", alias: "transparency translucency see-through panel layer background", label: "Panel opacity", type: "real",
      min: 0.1, max: 1, step: 0.05,
      help: "The ground every layer that opens out of the pill is painted on. Alpha over black, so lower is more transparent." },
    { key: "menuOpacity", section: "look", alias: "transparency translucency see-through menu background", label: "Menu opacity", type: "real",
      // From where the frost starts. Below blurFloor (0.52) Zenon holds the
      // ground at the floor anyway, so the old 0.30 left a third of the
      // slider doing nothing at all.
      min: 0.55, max: 1, step: 0.05,
      help: "The ground under the rows of every menu — icarus', the tray's, picasso's, terminus' right-click menu, the dropdowns in here — and under terminus' quick look. Alpha over black, so lower is more transparent, and hyprland frosts what is behind it. Never lower than the point where that frost would stop." },
    { key: "shadowStrength", section: "look", label: "Panel shadow", type: "real",
      min: 0, max: 1, step: 0.05,
      help: "How far a layer lifts off the desktop. A layer sits near an edge, so too much of this reads as a black halo." },
    { key: "scrollbarAutohide", section: "look", alias: "scrollbar scroll bar hide overlay thumb", label: "Autohide scrollbars", type: "bool",
      help: "Every scrollbar in the shell fades away once the list stops moving, and comes back when you scroll or put the pointer on it. Off, the thumb is always there." },
    { key: "motionScale", section: "motion", label: "Animation speed", type: "real",
      min: 0, max: 2.5, step: 0.05, unit: "x",
      help: "Multiplies every duration in the shell. Zero means no animation at all." },
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
    { key: "notifLift", section: "notify", label: "Gap above the pill", type: "int",
      min: 0, max: 120, step: 2, unit: "px",
      help: "How far the toasts stand off the bar, on whichever edge it is." },
    { key: "notifTrackMusic", section: "notify", label: "Keep track changes", type: "bool",
      help: "Whether a music player's notifications earn a row in the bell's history." },
    { key: "notifSilent", section: "notify", alias: "dnd do not disturb quiet silence mute toasts howler", label: "Do not disturb", type: "bool",
      help: "Hold back toasts; they still count on the bell and wait in its history. A critical one still shows. Also in the bell's right-click menu." },
    { key: "notifHistoryCap", section: "notify", label: "History kept", type: "int",
      min: 10, max: 1000, step: 10,
      help: "How many notifications the bell remembers across restarts." },
    { key: "notifFontSize", section: "notify", label: "Text size", type: "int",
      min: 10, max: 28, step: 1, unit: "px" },
    { key: "notifTextAlign", section: "notify", label: "Text alignment", type: "enum",
      options: [ { value: "left",   label: "Left" },
                 { value: "center", label: "Center" },
                 { value: "right",  label: "Right" } ] },
    { key: "notifRadius", section: "notify", label: "Corner radius", type: "int",
      min: 0, max: 24, step: 1, unit: "px" },
    { key: "notifPadding", section: "notify", label: "Padding", type: "int",
      min: 0, max: 24, step: 1, unit: "px" },
    { key: "notifSpacing", section: "notify", label: "Gap between toasts", type: "int",
      min: 0, max: 24, step: 1, unit: "px" },
    { key: "notifIconRadius", section: "notify", label: "Icon corner radius", type: "int",
      min: 0, max: 40, step: 1, unit: "px" },
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
      pick: "directory", placeholder: "your pictures folder, then /Wallpapers",
      help: "Where picasso looks for backgrounds, chosen in terminus. Rescanned when this changes. Empty asks XDG for your pictures directory." },
    { key: "backgroundFit", section: "paper", label: "Fit", type: "enum",
      options: [ { value: "crop",    label: "Crop" },
                 { value: "fit",     label: "Fit" },
                 { value: "stretch", label: "Stretch" },
                 { value: "pad",     label: "Center" },
                 { value: "tile",    label: "Tile" } ],
      help: "How an image that is not the monitor's shape is made to fit it. The default — a monitor given its own fit in the picker keeps that one." },
    { key: "pickerScheme", section: "paper", alias: "colour color picker hyprpicker hex rgb hsl oklch",
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

    // ── idle & lock ──
    { key: "idleEnabled", section: "idle", label: "Idle timers", type: "bool",
      help: "Off, nothing happens however long you are away. The lock still works by hand." },
    { key: "idleLockSecs", section: "idle", label: "Lock after", type: "int",
      min: 0, max: 3600, step: 30, unit: "s",
      help: "Idle this long and the lock comes up. 0 never locks on its own." },
    { key: "idleScreenOffSecs", section: "idle", label: "Screens off after", type: "int",
      min: 0, max: 7200, step: 30, unit: "s",
      help: "Idle this long and every output is switched off; any input brings them back. 0 leaves them on." },
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
    // ── WHEN THE WAY OUT IS OFFERED, NOT HOW MANY TRIES YOU GET ──────
    // pam_faillock decides how many wrong passwords lock the account; this
    // decides when the lock shows the button that clears them. It used to
    // be labelled as though it were pam's number, and set above pam's it
    // only hid the button while pam was already refusing you. Cerberus now
    // reads pam's own deny and never waits past it — see failDeny there.
    { key: "lockFailLimit", section: "idle", label: "Offer a reset after", type: "int",
      min: 1, max: 20, step: 1, alias: "attempts lockout faillock wrong password",
      help: "Wrong passwords before the lock offers to clear them. Never later than the system's own lockout (pam_faillock), whatever this says." },
    { key: "lockWidgetMonitor", section: "idle", label: "Lock screen monitor",
      type: "enum", optionsFrom: "screens", open: true,
      help: "Which output carries the clock and the password field. Automatic uses the first screen there is." },
    { key: "lockBlurStrength", section: "idle", label: "Lock blur", type: "int",
      min: 1, max: 40, step: 1, unit: "%",
      help: "The desktop is shrunk to this, blurred, and blown back up — once, at lock time. Smaller is blurrier." },
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
    { key: "clock24h", section: "time", label: "24-hour clock", type: "bool" },
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
    { key: "menuShowPackages", section: "menu", label: "Package Manager", type: "bool",
      help: "Opens ceres on its package list." },
    { key: "menuShowApps", section: "menu", label: "Apps", type: "bool" },
    { key: "menuShowHome", section: "menu", label: "Home", type: "bool",
      help: "Browse the filesystem from inside the menu." },
    { key: "menuShowHidden", section: "menu", label: "Hidden files in Home", type: "bool",
      help: "Dotfiles in the Home cards. Ctrl+H or the header's right-click menu flips it from the menu itself." },
    { key: "menuHomePlaces", section: "menu", label: "Places in Home", type: "bool",
      help: "Home, your XDG folders and terminus' bookmarks above the listing — the ones not already in it." },
    { key: "menuHomeRemember", section: "menu", label: "Home remembers its folder", type: "int",
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
    { key: "infoDefaultsPath", section: "defaults", label: "Written to", type: "info",
      elideLeft: true,
      help: "A plain lua file the binds read, read back on every change — editing it by hand works too." },

    // ── the checkup ──
    // Readouts like the About rows, filled by oracle/doctor.sh — see
    // runCheckup. `health` names the row of Ora.readCheckup each one shows.
    { key: "actionCheckup", section: "health", label: "Checkup", type: "action",
      verb: "Run again",
      help: "Runs by itself when you open this section. Read-only: it looks, it never changes anything." },
    { key: "infoHealthTests", section: "health", label: "Tests", type: "info", health: "tests",
      help: "The shell's own test suite, the same one run after every script change." },
    { key: "infoHealthProbes", section: "health", label: "Leftover probes", type: "info", health: "probes",
      help: "Temporary debugging overrides that were never taken out. One once spawned hyprctl every 400ms." },
    { key: "infoHealthStale", section: "health", label: "Changed scripts", type: "info", health: "stale",
      help: "Scripts edited since the shell started. A reload can keep the old copy; a restart cannot." },
    { key: "infoHealthMemory", section: "health", label: "Memory", type: "info", health: "memory",
      help: "Resident size, against what a clean restart settles at." },
    { key: "infoHealthPollers", section: "health", label: "Child processes", type: "info", health: "pollers",
      help: "Watched for two seconds: what stays open, and what gets spawned while nothing is happening." },
    { key: "infoHealthLog", section: "health", label: "Log", type: "info", health: "log",
      help: "Errors and warnings since the shell started, from qs log." },

    // ── oracle itself ──
    // A READOUT, not a setting. "Where does this end up" is the first thing
    // anyone asks of a settings panel, and the answer was only discoverable by
    // reading the source — so the panel says it. `info` rows hold nothing, are
    // never written, and never count as changed; see Ora.stored.
    { key: "infoStatePath", section: "about", label: "Kept in", type: "info",
      // a path identifies itself by its END, so this one elides from the left
      elideLeft: true,
      help: "Only the settings you have changed are written. Delete this file and everything is back to its defaults." },
    // The names three of the settings above ask you to type. Having to run
    // hyprctl to find out what your own outputs are called, in order to fill
    // in a field in a settings panel, is the panel's failure rather than
    // yours.
    { key: "infoOutputs", section: "about", label: "Outputs", type: "info",
      help: "What to put in the monitor fields under Bar and Idle & Lock." },
    { key: "infoLaunched", section: "about", label: "Running since", type: "info",
      help: "When this shell last started." },
    { key: "actionReload", section: "about", label: "Reload from disk", type: "action",
      verb: "Reload",
      help: "Re-read oracle.json. Useful after editing it by hand." },
    // `context: true` — this one acts on the section you came here FROM, and
    // says which on its own button rather than making you remember. See
    // ActionControl, which is where that name is appended.
    { key: "actionResetSection", section: "about", label: "Reset one section",
      type: "action", verb: "Reset", context: true,
      help: "Put every setting in the section you were last in back to its default." },
    { key: "actionResetAll", section: "about", label: "Reset everything", type: "action",
      verb: "Reset all",
      help: "Every setting in every section back to its default." },
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
  readonly property var screenOptions: {
    const out = [{ value: "", label: "Automatic" }];
    const sc = Quickshell.screens;
    for (let i = 0; i < sc.length; ++i)
      out.push({ value: sc[i].name, label: sc[i].name });
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
      if (s.optionsFrom === "screens") c.options = root.screenOptions;
      if (Ora.stored(s)) {
        if (!root.defaultsTaken) d[s.key] = root[s.key];
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
    root.defaults = d;
    root.defaultsTaken = true;
    root.schema = out;
  }

  // a monitor came or went; the pickers have to say so
  onScreenOptionsChanged: if (root.defaultsTaken) root.buildSchema();

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
    if (key === "infoStatePath") return root.statePath;
    if (key === "infoMonitorsPath") return root.monitorsPath;
    if (key === "infoDefaultsPath") return root.defaultsPath;
    if (key === "infoInputPath") return root.inputPath;
    if (key.indexOf("inputHead:") === 0) return Ora.inputDeviceText(root.inputDevices, key.slice(10));
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
    if (!hs || !hs.health || root.checking) return "ok";
    const r = root.checkup[hs.health];
    return r ? r.level : "ok";
  }

  // ── THE CHECKUP ───────────────────────────────────────────────────────
  // What a clean restart settles at (2026-09-23, after ceres). Memory is
  // read as a drift from this, not as a number to remember.
  readonly property int rssBaselineKb: 1054396
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
      Quickshell.shellDir, "", String(since)];
    doctorProc.running = true;
  }

  Process {
    id: doctorProc
    stdout: StdioCollector {
      id: doctorOut
      onStreamFinished: {
        root.checkup = Ora.readCheckup(doctorOut.text, root.rssBaselineKb);
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
    return root[key];
  }

  function set(key, value) {
    const s = root.spec(key);
    if (!s || !Ora.stored(s)) return;
    if (s.display) { root.setDisplay(s, value); return; }
    if (s.appDefault) { root.setAppDefault(s, value); return; }
    if (s.input) { root.setInput(s, value); return; }
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
    for (let i = 0; i < root.schema.length; ++i) {
      const s = root.schema[i];
      if (!Ora.stored(s) || s.display || s.section !== section) continue;
      root.reset(s.key);
    }
  }

  // NOT the monitors, the default apps or the input devices. "Reset
  // everything" is oracle.json, and Reload from disk runs this before reading
  // the file back — neither should reach into hyprland and change a screen or
  // a keyboard layout, or into mimeapps.list. Those sections reset on their own.
  function resetAll() {
    for (let i = 0; i < root.schema.length; ++i) {
      const s = root.schema[i];
      if (Ora.stored(s) && !s.display && !s.appDefault && !s.input) root.reset(s.key);
    }
  }

  // How many settings in a section are no longer at their default. The sidebar
  // shows this, so a section that has been changed says so unopened.
  function changedIn(section) {
    const vals = ({});
    for (let i = 0; i < root.schema.length; ++i) {
      const s = root.schema[i];
      if (Ora.stored(s) && !s.display) vals[s.key] = root.get(s.key);
    }
    // A monitor that is not at "automatic" is not a setting someone moved
    // off its default — it is a monitor set up the way it has to be. Counting
    // it made every desk with a rotated screen read as modified, and made its
    // label a one-click way to rotate the screen back.
    return Ora.changedIn(root.schema.filter((s) => !s.display), vals, root.defaults, section);
  }

  // ── the actions ───────────────────────────────────────────────────────
  // `context` is whatever the panel was standing in when the row was clicked,
  // so "reset a section" can mean the one you are looking at without the
  // action needing a second control beside it.
  function run(key, context) {
    if (key === "actionCheckup") { root.runCheckup(); return; }
    if (key === "actionDisplayScan") { root.scanDisplays(); return; }
    if (key === "actionAppsScan") { root.scanApps(); return; }
    if (key === "actionInputScan") { root.scanInputDevices(); return; }
    if (key === "actionReload") { root.reloadFromDisk(); return; }
    if (key === "actionResetSection") { root.resetSection(context); return; }
    if (key === "actionResetAll") { root.resetAll(); return; }
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

  readonly property string monitorsPath:
    (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
      + "/hypr/lua/monitors.lua"

  // Each monitor's own ink, so its rows read as one group and the groups as
  // different monitors — and so its box in the Arrangement is the same color
  // as its settings below. Cyan and the orange are left out: they already
  // mean "selected" and "changed" in this panel.
  function displayAccent(name) {
    // Zenon's blue, magenta, green, sand and pink, written out: Oracle
    // cannot import Zenon, which imports Oracle.
    const inks = ["#9fcbfc", "#c8a4e0", "#b6e0a4", "#e0d8a4", "#eebebe"];
    for (let i = 0; i < root.displays.length; ++i)
      if (root.displays[i].name === name) return inks[i % inks.length];
    return "#6a707f";
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
    monitorsFile.setText(Ora.renderMonitorRules(entries, kept,
      Ora.extraStatements(monitorsFile.text())));
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

  readonly property string inputPath:
    (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
      + "/hypr/lua/input.lua"

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
    const k = Ora.appKind(key);
    return (k && k.preferred) || "";
  }

  readonly property string defaultsPath:
    (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
      + "/hypr/lua/defaults.lua"

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
      // A hand-edited file can have LOST a key as well as gained one, and
      // load() only applies what it finds — a setting deleted by hand would
      // otherwise keep whatever it currently held, which is not what the file
      // now says. Cleared first, so "reload" means the file and nothing else.
      root.resetAll();
      root.load();
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
    const own = root.schema.filter((s) => !s.display && !s.appDefault && !s.input);
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
  function load() {
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
    // `set barRadius 999` lands at the slider's own maximum rather than at 999.
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
        if (!Ora.stored(s) || s.display || s.appDefault || s.input || root.isDefault(s.key)) continue;
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
    root.scanDisplays();
    root.scanInputDevices();
    appsFirstScan.start();
  }
}
