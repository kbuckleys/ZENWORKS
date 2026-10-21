// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE FOCUS CARD — a background lifted out of the picker's grid. The picture
// large on the left; on the right, in three tabs, everything that decides
// how it lands:
//
//   Place      which monitors, drawn to scale where they sit; spanning them
//              as one; the fit; which part a crop keeps; turn and mirror
//   Look       what fills the space around it; dim, blur, color, light,
//              contrast, tint — LookEditor, which the viewer's edit panel is too
//   Slideshow  keep going through the rest of them on a timer
//
// NOTHING CHANGES UNTIL APPLY. Every control here stages; the map shows the
// staged answer on each monitor with the same Scene the daemon paints with,
// so the preview is the background, not a sketch of it.
//
// It lives in the picker's own surface (so it grows out of the thumbnail
// that was clicked) and reads the picker for what it is about — see
// PicassoPopup's openFocus / stepFocus / closeFocus, which own the subject.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../morpheus"
import "../morpheus/controls" as Controls
import "../oracle"
import "picasso.js" as Art
import "../terminus/terminus.js" as Terminus
import "../terminus" as Term

Item {
  id: card

  // the picker this card belongs to, and the panel it sits over
  required property var picker
  required property Item panel

  readonly property color highlight: Zenon.cyan
  readonly property color dimColor: Zenon.accentMuted
  readonly property color fgColor: Zenon.white
  readonly property color entryColor: Zenon.pink

  // THE CARD'S TYPE IS TWO PIXELS UP from the picker's: it is read at arm's
  // length over a busy grid, and it is where the decisions are.
  readonly property int ts: 14          // body
  readonly property int tsSmall: 13     // labels under controls
  readonly property int tsName: 18      // the picture's name

  readonly property string path: card.picker.focusPath
  readonly property bool isColor: Art.isColor(card.path)
  readonly property string colorHex: Art.colorOf(card.path)

  // ── what is staged ────────────────────────────────────────────────────
  property var stageScreens: []
  // "" is "leave each monitor's fit alone"
  property string stageFit: ""
  // only the keys you have touched; a monitor keeps the rest of its own
  property var stageLook: ({})
  property bool stageSpan: false
  property string tab: "place"
  // "" or which color the picker is open for: "tint" or "backdrop"
  property string editing: ""

  property bool slideOn: false
  property int slideMinutes: 15
  property bool slideShuffle: false
  property string slidePool: "all"

  readonly property var screenNames: card.picker.screenNames
  readonly property bool multi: card.screenNames.length > 1
  readonly property bool allStaged: card.stageScreens.length === card.screenNames.length
  readonly property bool spanning: card.stageSpan && card.stageScreens.length >= 2

  // The look the controls show: the first staged monitor's own, with
  // whatever has been touched laid over it.
  readonly property string baseScreen: card.stageScreens.length > 0
    ? card.stageScreens[0] : card.picker.screenName
  readonly property var look: Art.lookOf(Object.assign(
    {}, card.baseLookOf(card.baseScreen), card.stageLook))

  // What a staged monitor starts from: its own look while it is showing this
  // picture already, else that look without the old picture's filters — what
  // applying it will leave (Picasso.freshLooks), so the preview tells the truth
  function baseLookOf(name) {
    const l = Picasso.lookFor(name);
    return card.path !== "" && Picasso.wallpaperFor(name) !== card.path ? Art.freshLook(l) : l;
  }
  function lookFor(name) {
    if (card.stageScreens.indexOf(name) < 0) return Picasso.lookFor(name);
    return Art.lookOf(Object.assign({}, card.baseLookOf(name), card.stageLook));
  }

  function setLook(key, value) {
    const next = Object.assign({}, card.stageLook);
    next[key] = value;
    card.stageLook = next;
  }

  function resetLook() {
    card.stageLook = Object.assign({}, Art.lookDefaults);
  }

  readonly property bool lookTouched: Object.keys(card.stageLook).length > 0

  // the desk the staged span would cover, in global coordinates
  readonly property var stagedSpan: {
    if (!card.spanning) return null;
    const sc = Quickshell.screens, r = [];
    for (let i = 0; i < sc.length; ++i)
      if (card.stageScreens.indexOf(sc[i].name) >= 0)
        r.push({ x: sc[i].x, y: sc[i].y, w: sc[i].width, h: sc[i].height });
    return Art.boundsOf(r);
  }

  function stagedFitFor(name) {
    if (card.stageFit !== "" && card.stageScreens.indexOf(name) >= 0) return card.stageFit;
    return Picasso.fitFor(name);
  }

  // the fit every staged monitor already shares, or "" when they differ
  readonly property string sharedFit: {
    let out = "";
    for (let i = 0; i < card.stageScreens.length; ++i) {
      const f = Picasso.fitFor(card.stageScreens[i]);
      if (out === "") out = f;
      else if (out !== f) return "";
    }
    return out;
  }
  readonly property string effFit: card.stageFit !== "" ? card.stageFit
    : (card.sharedFit !== "" ? card.sharedFit : Picasso.fitFor(card.baseScreen))

  readonly property string applyLabel: {
    if (card.stageScreens.length === 0) return "Pick a display";
    if (card.slideOn) return "Start slideshow";
    if (!card.multi) return "Set background";
    if (card.spanning) return card.allStaged ? "Span all displays"
                                             : "Span " + card.stageScreens.length + " displays";
    if (card.allStaged) return "Set on all displays";
    if (card.stageScreens.length === 1) return "Set on " + card.stageScreens[0];
    return "Set on " + card.stageScreens.length + " displays";
  }

  // Called by the picker each time the card opens: all monitors, nothing
  // touched, the slideshow's current answers if one is running.
  function reset() {
    card.waiting = false;
    card.busyText = "";
    waitCap.stop();
    card.stageScreens = card.screenNames.slice();
    card.stageFit = "";
    card.stageLook = ({});
    card.stageSpan = !!Picasso.span && Picasso.span.path === card.path;
    card.editing = "";
    card.tab = "place";
    const ss = Picasso.slideshow;
    card.slideOn = false;
    card.slideMinutes = ss ? ss.minutes : 15;
    card.slideShuffle = ss ? ss.shuffle : false;
    card.slidePool = ss && ss.query !== "" ? "filter" : "all";
    card.kbShown = false;
    card.kbRow = "";
    card.kbCol = 0;
    card.askDims();
  }

  function toggleScreen(name) {
    const next = card.stageScreens.slice();
    const i = next.indexOf(name);
    if (i >= 0) next.splice(i, 1);
    else next.push(name);
    // kept in the screens' own order, so "the first staged" is stable
    card.stageScreens = card.screenNames.filter((n) => next.indexOf(n) >= 0);
  }

  function toggleAllScreens() {
    card.stageScreens = card.allStaged ? [] : card.screenNames.slice();
  }

  // Choosing the fit that is already chosen lets go of it, back to "leave
  // each monitor as it is".
  function pickFit(fit) { card.stageFit = card.stageFit === fit ? "" : fit; }

  function turn(delta) { card.setLook("rotate", (card.look.rotate + delta + 360) % 360); }

  // THE PICKER STAYS OPEN; the card goes. See PicassoPopup.closeFocus.
  //
  // A scratch picture (the viewer's selection — see PicassoPopup.focusAdopt)
  // is written into its directory first, under a free name, and that file is
  // what is set: the scratch png lives in the runtime directory and would be
  // gone at the next boot.
  function apply() {
    if (card.path === "" || card.stageScreens.length === 0 || adoptProc.running || card.waiting) return;
    const ad = card.picker.focusAdopt;
    if (ad && ad.tmp === card.path) {
      card.busyText = "Writing it\u2026";
      adoptProc.command = Terminus.shArgv(Terminus.convertIntoCommand(ad.tmp, ad.dir, ad.name));
      adoptProc.running = true;
      return;
    }
    card.applyPath(card.path);
  }
  Process {
    id: adoptProc
    stdout: StdioCollector { id: adoptOut; waitForEnd: true }
    onExited: (code) => {
      const made = String(adoptOut.text || "").trim();
      // the card's close throws the scratch file away (dropAdopt)
      if (code === 0 && made !== "") card.applyPath(made);
      else card.busyText = "";
    }
  }

  // ── APPLIED, AND WAITED FOR ───────────────────────────────────────────
  // Setting the assignment is instant; the picture is not — a big file
  // takes a second or more to decode for each monitor. So the card stays,
  // Apply turned into the working dots (terminus/BusyButton, alexandria's),
  // until every monitor it was applied to says it is showing it
  // (Picasso.shown, reported by PicassoDaemon), and then goes.
  property bool waiting: false
  property string waitPath: ""
  property var waitNames: []
  property string busyText: ""
  readonly property bool busy: card.waiting || adoptProc.running
  readonly property bool arrived: card.waiting && Picasso.showing(card.waitNames, card.waitPath)
  // A tick later, not from inside the change: finishWait() clears `waiting`,
  // which `arrived` reads, and doing that while `arrived` is still notifying
  // was a binding loop. The card's own Timer, so it dies with the card.
  onArrivedChanged: if (card.arrived) arriveLater.restart()
  Timer { id: arriveLater; interval: 0; onTriggered: card.finishWait() }
  Connections {
    target: Picasso
    function onLastFailureChanged() {
      const f = Picasso.lastFailure;
      if (card.waiting && f && f.path === card.waitPath && card.waitNames.indexOf(f.screen) >= 0)
        card.finishWait();
    }
  }
  // a decode that never answers must not hold the card forever
  Timer { id: waitCap; interval: 30000; onTriggered: card.finishWait() }
  function finishWait() {
    if (!card.waiting) return;
    card.waiting = false;
    card.busyText = "";
    waitCap.stop();
    card.picker.closeFocus();
  }
  function applyPath(path) {
    const names = card.stageScreens.slice();
    if (path === "" || names.length === 0) return;

    if (card.spanning) Picasso.setSpan(path, names);
    else if (card.allStaged) Picasso.setAll(path);
    else for (const n of names) Picasso.setFor(n, path);

    if (card.stageFit !== "") {
      if (card.allStaged) Picasso.setFitAll(card.stageFit);
      else for (const n of names) Picasso.setFitFor(n, card.stageFit);
    }

    if (card.lookTouched)
      for (const n of names) Picasso.setLookFor(n, card.stageLook);

    if (card.slideOn) {
      Picasso.startSlideshow({
        minutes: card.slideMinutes,
        shuffle: card.slideShuffle,
        query: card.slidePool === "filter" ? card.picker.query : "",
        screens: card.allStaged ? [] : names,
        span: card.spanning
      });
    }
    card.waitPath = path;
    card.waitNames = names;
    card.busyText = card.slideOn ? "Starting\u2026" : "Applying\u2026";
    card.waiting = true;
    waitCap.restart();
    if (card.arrived) card.finishWait();
  }

  // ── natural sizes ─────────────────────────────────────────────────────
  // Centered and tiled depend on how big the picture really is, so the map
  // cannot draw them honestly from a thumbnail alone. identify reads the
  // header and nothing else; the answers are kept for the life of the shell.
  property var dims: ({})
  property var dimsQueue: []

  function askDims() {
    const want = [card.path];
    for (const n of card.screenNames) want.push(Picasso.wallpaperFor(n));
    const add = [];
    for (const p of want)
      if (p && !Art.isColor(p) && !(p in card.dims) && add.indexOf(p) < 0
          && card.dimsQueue.indexOf(p) < 0) add.push(p);
    if (add.length === 0) return;
    card.dimsQueue = card.dimsQueue.concat(add);
    if (!dimsProc.running) card.runDims();
  }

  function runDims() {
    if (card.dimsQueue.length === 0) return;
    dimsProc.command = ["sh", "-c",
      'for p; do printf \'%s\\t%s\\n\' "$(magick identify -format \'%w %h\' "$p[0]" 2>/dev/null)" "$p"; done',
      "sh"].concat(card.dimsQueue);
    card.dimsQueue = [];
    dimsProc.running = true;
  }

  Process {
    id: dimsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const next = Object.assign({}, card.dims);
        for (const line of String(text || "").split("\n")) {
          const tab = line.indexOf("\t");
          if (tab < 0) continue;
          const wh = line.slice(0, tab).split(" ");
          const w = parseInt(wh[0], 10), h = parseInt(wh[1], 10);
          next[line.slice(tab + 1)] = (w > 0 && h > 0) ? { w: w, h: h } : null;
        }
        card.dims = next;
      }
    }
    onRunningChanged: if (!running) Qt.callLater(card.runDims)
  }

  onPathChanged: if (card.picker.focusOpen) card.askDims()

  function fillOf(fit) {
    if (fit === "fit") return Image.PreserveAspectFit;
    if (fit === "stretch") return Image.Stretch;
    if (fit === "pad") return Image.Pad;
    if (fit === "tile") return Image.Tile;
    return Image.PreserveAspectCrop;
  }

  function sizeText(bytes) {
    if (!(bytes > 0)) return "";
    if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB";
    return Math.max(1, Math.round(bytes / 1024)) + " KB";
  }

  function pct(v) { return Math.round(v * 100) + "%"; }

  // ── THE KEYBOARD ──────────────────────────────────────────────────────
  // The card is a column of rows, and the arrows walk IT, not the grid
  // behind it: up and down move between rows, left and right change the
  // row you are on — pick the next fit, nudge a slider, walk the monitors.
  // Space presses what is lit; return applies from anywhere; escape backs
  // out. Page up and down, or the top row, browse to the next picture.
  //
  // The ring only appears once a key has been pressed. Drawn from the
  // start it would be a decoration on a card most people drive with the
  // pointer.
  property bool kbShown: false
  property string kbRow: ""
  property int kbCol: 0

  readonly property var tabKeys: ["place", "look", "slides"]
  readonly property var tints: Art.tintPresets
  readonly property var backdrops: Art.backdropKeys
  readonly property var intervals: [5, 15, 30, 60, 180, 720]

  // what the custom tint swatch holds: the tint itself when it is not one
  // of the presets, otherwise the last one made
  property string customTint: "#7a8cff"
  readonly property bool tintIsCustom:
    card.look.tint !== "" && card.tints.indexOf(card.look.tint) < 0

  // ── THE SHELL'S ACCENT (Oracle's Accent color) ────────────────────────
  // On the Look tab, but not part of the look: set at once, not staged.
  readonly property string accentNow: (Oracle.revision, String(Oracle.accentColor || ""))
  property string customAccent: card.accentNow
  onAccentNowChanged: {
    const own = Picasso.accentFor(card.path);
    if (card.accentNow !== "" && (!own || own.toLowerCase() !== card.accentNow))
      card.customAccent = card.accentNow;
  }
  // a drag in the picker settles before the shell re-colors (ColorFold)
  property string accentPending: ""
  Timer {
    id: accentSettle
    interval: 180
    onTriggered: { if (card.accentPending !== "") Oracle.set("accentColor", card.accentPending); card.accentPending = ""; }
  }
  function setAccent(hex) {
    Picasso.accentChosenFor = hex === "" ? "" : card.path;
    accentSettle.stop();
    card.accentPending = "";
    if (hex === "") Oracle.reset("accentColor"); else Oracle.set("accentColor", hex);
  }
  function dragAccent(hex) {
    Picasso.accentChosenFor = card.path;
    card.customAccent = hex;
    card.accentPending = hex;
    accentSettle.restart();
  }
  Connections {
    target: Picasso
    function onColorPicked(into, hex) {
      if (into !== "card:accent") return;
      card.customAccent = hex;
      card.setAccent(hex);
    }
  }
  readonly property var accentKinds: ["", "accent", "custom"]
  readonly property string accentKind: {
    if (card.accentNow === "") return "";
    const own = Picasso.accentFor(card.path);
    return own && own.toLowerCase() === card.accentNow ? "accent" : "custom";
  }
  function chooseAccentKind(k) {
    if (k === "") card.setAccent("");
    else if (k === "accent") card.setAccent((Picasso.accentFor(card.path) || "").toLowerCase());
    else card.setAccent(card.customAccent || Zenon.hex(Zenon.cyan));
  }

  function rows() {
    const out = ["browse", "tabs"];
    if (card.editing !== "") return out.concat(["buttons"]);
    if (card.tab === "place") {
      if (card.multi) out.push("displays", "span");
      if (!card.isColor) out.push("fit", "position", "turn");
    } else if (card.tab === "look") {
      if (!card.isColor) out.push("backdrop");
      out.push("dim", "vignette", "blur", "saturation", "brightness", "contrast",
               "tint", "tintAmount", "accent", "reset");
    } else {
      out.push("slideOn", "interval", "order");
      if (card.picker.query !== "") out.push("pool");
    }
    out.push("buttons");
    return out;
  }

  function kb(row, col) {
    return card.kbShown && card.kbRow === row && (col === undefined || card.kbCol === col);
  }

  function step(list, cur, d) {
    const i = Math.max(0, list.indexOf(cur));
    return list[Math.max(0, Math.min(list.length - 1, i + d))];
  }

  function nudge(key, d, lo, hi) {
    const v = Math.round((card.look[key] + d) * 100) / 100;
    card.setLook(key, Math.max(lo, Math.min(hi, v)));
  }

  function moveRow(d) {
    const r = card.rows();
    let i = r.indexOf(card.kbRow);
    if (i < 0) i = d > 0 ? 1 : r.length;
    card.kbRow = r[Math.max(0, Math.min(r.length - 1, i + d))];
    card.kbCol = card.kbRow === "buttons" ? 1 : 0;
  }

  function moveIn(d) {
    switch (card.kbRow) {
    case "browse": card.picker.stepFocus(d); break;
    case "tabs": card.tab = card.step(card.tabKeys, card.tab, d); card.editing = ""; break;
    case "displays":
      card.kbCol = Math.max(0, Math.min(card.screenNames.length - 1, card.kbCol + d)); break;
    case "span": card.stageSpan = !card.stageSpan; break;
    case "fit": card.stageFit = card.step(Picasso.fitModes, card.effFit, d); break;
    case "position": card.setLook("align", card.step(Art.alignKeys, card.look.align, d)); break;
    case "turn": card.kbCol = Math.max(0, Math.min(2, card.kbCol + d)); break;
    case "backdrop": card.setLook("backdrop", card.step(card.backdrops, card.look.backdrop, d)); break;
    case "dim": card.nudge("dim", d * 0.05, 0, 0.8); break;
    case "vignette": card.nudge("vignette", d * 0.05, 0, 1); break;
    case "blur": card.nudge("blur", d * 0.05, 0, 1); break;
    case "saturation": card.nudge("saturation", d * 0.1, -1, 1); break;
    case "brightness": card.nudge("brightness", d * 0.05, -1, 1); break;
    case "contrast": card.nudge("contrast", d * 0.05, -1, 1); break;
    case "tint": {
      const cur = card.tintIsCustom ? "custom" : card.look.tint;
      const nx = card.step(card.tints, cur, d);
      card.setLook("tint", nx === "custom" ? card.customTint : nx);
      break;
    }
    case "tintAmount": card.nudge("tintAmount", d * 0.05, 0, 1); break;
    case "accent": card.chooseAccentKind(card.step(card.accentKinds, card.accentKind, d)); break;
    case "slideOn": card.slideOn = !card.slideOn; break;
    case "interval": card.slideMinutes = card.step(card.intervals, card.slideMinutes, d); break;
    case "order": card.slideShuffle = d > 0; break;
    case "pool": card.slidePool = d > 0 ? "filter" : "all"; break;
    case "buttons": card.kbCol = Math.max(0, Math.min(1, card.kbCol + d)); break;
    }
  }

  function press() {
    switch (card.kbRow) {
    case "displays": card.toggleScreen(card.screenNames[card.kbCol]); break;
    case "span": card.stageSpan = !card.stageSpan; break;
    case "fit": card.pickFit(card.effFit); break;
    case "turn":
      if (card.kbCol === 0) card.turn(-90);
      else if (card.kbCol === 1) card.turn(90);
      else card.setLook("mirror", !card.look.mirror);
      break;
    case "backdrop": if (card.look.backdrop === "color") card.editing = "backdrop"; break;
    case "tint": if (card.tintIsCustom) card.editing = "tint"; break;
    case "accent": if (card.accentKind === "custom") card.editing = "accent"; break;
    case "reset": card.resetLook(); break;
    case "slideOn": card.slideOn = !card.slideOn; break;
    case "buttons": if (card.kbCol === 0) card.picker.closeFocus(); else card.apply(); break;
    // a row whose left and right already choose has nothing more for space
    // to do — and must never fall through to applying
    }
  }

  // Everything the card is shown. Returns whether it used the key; escape
  // is the picker's, which asks cancel() first.
  function handleKey(event) {
    const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
    if (mods) return false;
    const k = event.key;
    const first = !card.kbShown;
    card.kbShown = true;
    if (card.kbRow === "" || card.rows().indexOf(card.kbRow) < 0) {
      card.kbRow = card.rows()[2] || "buttons";
      card.kbCol = card.kbRow === "buttons" ? 1 : 0;
      // the first arrow only turns the ring on; it does not also move it
      if (first && (k === Qt.Key_Up || k === Qt.Key_Down || k === Qt.Key_Left || k === Qt.Key_Right))
        return true;
    }
    if (k === Qt.Key_Up) card.moveRow(-1);
    else if (k === Qt.Key_Down) card.moveRow(1);
    else if (k === Qt.Key_Left) card.moveIn(-1);
    else if (k === Qt.Key_Right) card.moveIn(1);
    else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
      // round and round, the way tab goes everywhere else
      const d = (k === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)) ? -1 : 1;
      const n = card.tabKeys.length;
      card.tab = card.tabKeys[(card.tabKeys.indexOf(card.tab) + d + n) % n];
      card.editing = "";
      card.kbRow = card.rows()[2] || "buttons";
      card.kbCol = 0;
    }
    else if (k === Qt.Key_PageUp || k === Qt.Key_BracketLeft) card.picker.stepFocus(-1);
    else if (k === Qt.Key_PageDown || k === Qt.Key_BracketRight) card.picker.stepFocus(1);
    else if (k === Qt.Key_Space) card.press();
    else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (card.editing !== "") card.editing = "";
      else if (card.kbRow === "buttons" && card.kbCol === 0) card.picker.closeFocus();
      else card.apply();
    }
    else return false;
    return true;
  }

  // escape, innermost first: the color being edited, then the card
  function cancel() {
    if (card.editing !== "") { card.editing = ""; return true; }
    return false;
  }

  // names for the controls that have none — see morpheus/WindowTip; a popup
  // hangs off the picker's layer surface as well as off a window
  WindowTip { id: cardTips; window: card.QsWindow.window }

  // ── pieces ────────────────────────────────────────────────────────────

  // A fit, drawn: a screen 26 wide and what the picture does inside it.
  component FitGlyph: Item {
    id: glyph
    property string mode: "crop"
    property color ink: card.dimColor
    implicitWidth: 26
    implicitHeight: 16
    readonly property color fill: Qt.rgba(glyph.ink.r, glyph.ink.g, glyph.ink.b, 0.55)

    // crop: the picture runs past both sides, and what is cut is ghosted
    Rectangle {
      visible: glyph.mode === "crop"
      x: -6; y: 0; width: glyph.width + 12; height: glyph.height
      radius: 1
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(glyph.ink.r, glyph.ink.g, glyph.ink.b, 0.3)
    }
    Item {
      anchors.fill: parent
      clip: true
      Rectangle {
        visible: glyph.mode === "crop" || glyph.mode === "stretch"
        anchors.fill: parent
        color: glyph.fill
      }
      Rectangle {
        visible: glyph.mode === "fit"
        anchors.centerIn: parent
        width: parent.width - 2; height: 9
        color: glyph.fill
      }
      Rectangle {
        visible: glyph.mode === "pad"
        anchors.centerIn: parent
        width: 11; height: 7
        color: glyph.fill
      }
      Grid {
        visible: glyph.mode === "tile"
        anchors.fill: parent
        anchors.margins: 1
        columns: 3
        spacing: 1
        Repeater {
          model: 6
          Rectangle { width: 7.3; height: 6.5; color: glyph.fill }
        }
      }
    }
    Text {
      visible: glyph.mode === "stretch"
      anchors.centerIn: parent
      text: ""
      color: Zenon.black
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(10)
    }
    Rectangle {
      anchors.fill: parent
      radius: Zenon.rad(2)
      color: "transparent"
      border.width: 1
      border.color: glyph.ink
    }
  }

  // the prev / next buttons over the preview
  component Step: Rectangle {
    id: stepBtn
    property int dir: 1
    property bool shown: false
    readonly property bool live: card.picker.focusIndex >= 0
      && card.picker.focusIndex + stepBtn.dir >= 0
      && card.picker.focusIndex + stepBtn.dir < card.picker.focusList.length
    width: 36
    height: 36
    radius: height / 2
    color: stepMa.pressed ? Qt.rgba(card.highlight.r, card.highlight.g, card.highlight.b, 0.35)
      : Zenon.hud(0.55)
    border.width: 1
    border.color: stepMa.pressed ? card.highlight : Zenon.border
    opacity: stepBtn.live && stepBtn.shown ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
    Text {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: stepBtn.dir < 0 ? -1 : 1
      text: stepBtn.dir < 0 ? "" : ""
      color: stepMa.pressed ? card.highlight : Zenon.white
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(15)
    }
    MouseArea {
      id: stepMa
      anchors.fill: parent
      hoverEnabled: true
      enabled: stepBtn.live
      onClicked: card.picker.stepFocus(stepBtn.dir)
    }
  }

  // ── the card ──────────────────────────────────────────────────────────
  visible: card.f > 0.001
  opacity: card.picker.contentFade

  // 0..1, how far the card has arrived
  property real f: card.picker.focusOpen ? 1 : 0
  Behavior on f {
    NumberAnimation {
      duration: card.picker.focusOpen ? Math.round(Zenon.slow * 1.8) : Zenon.normal
      easing.type: card.picker.focusOpen ? Zenon.ease : Easing.InCubic
    }
  }

  readonly property int pad: 18
  readonly property int sideW: 344
  // tall enough for the Look tab's column — LookEditor, with Light and
  // Contrast — to clear Cancel and Apply at the bottom
  readonly property int sideH: 578
  readonly property int infoH: 56
  readonly property int cardW: Math.min(980, card.width - 64)
  readonly property int cardH: card.sideH + card.pad * 2
  readonly property int previewW: card.cardW - card.pad * 3 - card.sideW
  readonly property int previewH: card.sideH - card.infoH

  // Not a scrim: nothing is dimmed, so the backgrounds the card is about stay
  // exactly as they look. It only catches the click outside the card, which
  // is "never mind", and the wheel, so the grid underneath does not scroll.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onClicked: card.picker.closeFocus()
    onWheel: (w) => { w.accepted = true; }
  }

  Item {
    id: cardWrap
    width: card.cardW
    height: card.cardH
    // OVER THE PICKER, lifted off it towards the middle of the screen, so it
    // reads as the grid's own card and not a dialog. Held on screen.
    readonly property int lift: 70
    // Alone — the viewer's setter, no grid under it — it is simply centered.
    x: Math.round(card.panel.x + (card.panel.width - cardWrap.width) / 2)
    y: card.picker.cardOnly ? Math.round((card.height - cardWrap.height) / 2)
      : Math.round(Math.max(24, Math.min(card.height - cardWrap.height - 24,
          card.panel.y + (card.panel.height - cardWrap.height) / 2
            + (Zenon.barTop ? cardWrap.lift : -cardWrap.lift))))
    opacity: Math.min(1, card.f * 1.6)

    // OUT OF THE THUMBNAIL: scaled about its middle and carried from the
    // clicked cell, and back into whichever one it has browsed to.
    readonly property real s: 0.28 + 0.72 * card.f
    transform: [
      Scale {
        origin.x: cardWrap.width / 2
        origin.y: cardWrap.height / 2
        xScale: cardWrap.s
        yScale: cardWrap.s
      },
      // Alone there is no thumbnail to come out of, so it grows in place,
      // from its own middle, and goes back the same way.
      Translate {
        x: card.picker.cardOnly ? 0
          : (card.picker.focusFrom.x - (cardWrap.x + cardWrap.width / 2)) * (1 - card.f)
        y: card.picker.cardOnly ? 0
          : (card.picker.focusFrom.y - (cardWrap.y + cardWrap.height / 2)) * (1 - card.f)
      }
    ]

    MenuShadow {
      panel: cardBg
      cornerRadius: Zenon.dialogRadius
    }

    Rectangle {
      id: cardBg
      x: 0
      y: 0
      width: cardWrap.width
      height: cardWrap.height
      radius: Zenon.dialogRadius
      color: Zenon.mix(Zenon.ground, Zenon.card, 0.6)
      border.width: 1
      border.color: Zenon.border

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: (w) => { w.accepted = true; }
      }

      // ── the picture ─────────────────────────────────────────────────
      ClippingRectangle {
        id: preview
        x: card.pad
        y: card.pad
        width: card.previewW
        height: card.previewH
        radius: Zenon.radiusCard
        // the letterbox wears the look's "Around it" (user, 2026-10-15: the
        // options showed nothing here) — black, a color, its own color,
        // or itself blurred (bdBlur, below)
        color: card.isColor ? card.colorHex
          : Art.groundOf(card.look, card.look.backdrop === "accent" ? Picasso.accentFor(card.path) : "")
        Behavior on color { ColorAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Image {
          id: bdBlurSrc
          anchors.fill: parent
          visible: false
          source: !card.isColor && card.look.backdrop === "blur" ? preview.thumbSrc : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize.width: 128
          sourceSize.height: 128
        }
        MultiEffect {
          anchors.fill: parent
          visible: bdBlurSrc.source.toString() !== "" && bdBlurSrc.status === Image.Ready
          source: bdBlurSrc
          blurEnabled: true
          blur: 1.0
          blurMax: 32
          brightness: -0.12
        }

        readonly property var row: card.picker.focusRow
        readonly property string thumbSrc: {
          if (card.isColor || card.path === "") return "";
          const t = preview.row ? preview.row.thumb : "";
          return t !== "" ? "file://" + t : Strings.fileUrl(card.path);
        }

        // THE PICTURE WEARS THE LOOK. Blur, color and tint are laid over it
        // here as they will be on the wall, scaled down with it — a blur of
        // forty pixels on a 2560 screen is nine on this preview.
        Item {
          id: pic
          anchors.fill: parent
          readonly property real unit: preview.width / Math.max(1, card.picker.screen
            ? card.picker.screen.width : 2560)
          layer.enabled: Art.lookNeedsFx(card.look)
          layer.effect: MultiEffect {
            blurEnabled: card.look.blur > 0
            blur: card.look.blur
            blurMax: Math.max(1, Math.round(64 * pic.unit))
            saturation: card.look.saturation
            // light and contrast, as the wall's Scene has them — left off
            // here, the two sliders moved nothing you could see
            brightness: card.look.brightness
            contrast: card.look.contrast
            colorization: card.look.tint !== "" ? card.look.tintAmount : 0
            colorizationColor: card.look.tint === "accent"
              ? (Picasso.accentFor(card.path) || "#808080")
              : (card.look.tint !== "" ? card.look.tint : "#808080")
          }

          Image {
            anchors.fill: parent
            visible: !card.isColor && full.status !== Image.Ready
            source: preview.thumbSrc
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }
          Image {
            id: full
            anchors.fill: parent
            visible: !card.isColor
            // Not a picture far bigger than the screen: Qt decodes a png
            // whole on the shell's one loader thread before scaling it, and
            // the daemon's own decode waited behind this one. The thumbnail
            // under it stands in (card.dims says how big, as soon as known).
            readonly property var nat: card.dims[card.path]
            source: card.isColor || card.path === "" || !full.nat || full.nat.w * full.nat.h > 40000000 ? ""
              : Strings.fileUrl(card.path)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.width: Math.ceil(preview.width * full.Screen.devicePixelRatio)
            sourceSize.height: Math.ceil(preview.height * full.Screen.devicePixelRatio)
            opacity: full.status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
          }

          // the vignette and the dim, over the picture only — not over the
          // letterbox, which is the card's, not the wall's
          Item {
            anchors.centerIn: parent
            width: full.status === Image.Ready ? full.paintedWidth : parent.width
            height: full.status === Image.Ready ? full.paintedHeight : parent.height
            Vignette {
              anchors.fill: parent
              amount: card.look.vignette
            }
            Rectangle {
              anchors.fill: parent
              color: "#000000"
              opacity: card.look.dim
            }
          }
        }

        // a color is its own preview: the hex, large, in whichever ink
        // reads against it
        Text {
          anchors.centerIn: parent
          visible: card.isColor
          text: card.colorHex
          color: Art.hexToHsv(card.colorHex).v > 0.6 && Art.hexToHsv(card.colorHex).s < 0.5
            ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(1, 1, 1, 0.45)
          font.family: Zenon.face
          font.weight: 600
          font.pixelSize: Zenon.px(32)
        }

        HoverHandler { id: previewHover }

        // the wheel browses, one picture per notch
        MouseArea {
          anchors.fill: parent
          property real acc: 0
          onWheel: (w) => {
            w.accepted = true;
            acc += w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x;
            while (acc >= 120) { acc -= 120; card.picker.stepFocus(-1); }
            while (acc <= -120) { acc += 120; card.picker.stepFocus(1); }
          }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: 10
          visible: card.picker.focusIndex >= 0
          width: countLabel.implicitWidth + 16
          height: 22
          radius: Zenon.radiusControl
          color: Zenon.hud(0.6)
          Text {
            id: countLabel
            anchors.centerIn: parent
            text: (card.picker.focusIndex + 1) + " / " + card.picker.focusList.length
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: card.ts
          }
          Ring { on: card.kb("browse") }
        }

        // already up somewhere — pink, the color of "in use"
        Rectangle {
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 10
          visible: card.picker.focusOn.length > 0
          width: onLabel.implicitWidth + 18
          height: 22
          radius: Zenon.radiusControl
          color: card.entryColor
          Text {
            id: onLabel
            anchors.centerIn: parent
            text: "  " + (!card.multi ? "current"
              : card.picker.focusOn.length === card.screenNames.length
                ? "On every display" : "On " + card.picker.focusOn.join(", "))
            color: Zenon.onAccent
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: card.tsSmall
          }
        }

        Step {
          dir: -1; shown: previewHover.hovered || card.kb("browse")
          anchors.left: parent.left; anchors.leftMargin: 10
          anchors.verticalCenter: parent.verticalCenter
        }
        Step {
          dir: 1; shown: previewHover.hovered || card.kb("browse")
          anchors.right: parent.right; anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // ── what it is ──────────────────────────────────────────────────
      Item {
        x: card.pad
        y: card.pad + card.previewH
        width: card.previewW
        height: card.infoH

        Column {
          anchors.left: parent.left
          anchors.right: meta.left
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: 3
          spacing: 1

          Text {
            width: parent.width
            text: card.isColor ? card.picker.colorName(card.colorHex) : Art.label(card.path)
            color: card.fgColor
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: card.tsName
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: {
              if (card.isColor) return card.colorHex;
              const r = Art.rel(card.path, Picasso.dir).split("/");
              r.pop();
              return r.length > 0 ? r.join(" / ") : Picasso.dir.split("/").pop();
            }
            color: card.dimColor
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: card.ts
            elide: Text.ElideMiddle
          }
        }

        Text {
          id: meta
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: 3
          text: {
            if (card.isColor) return "solid color";
            const d = card.dims[card.path];
            const parts = [];
            if (d) parts.push(d.w + " × " + d.h);
            const row = card.picker.focusRow;
            const sz = card.sizeText(row ? row.size : 0);
            if (sz !== "") parts.push(sz);
            return parts.join("   ·   ");
          }
          color: card.dimColor
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: card.ts
        }
      }

      // ── where it goes, and how ─────────────────────────────────────
      Item {
        id: side
        x: card.pad * 2 + card.previewW
        y: card.pad
        width: card.sideW
        height: card.sideH

        // the three tabs
        // the card's three pages: the suite's segmented switch
        Term.Segments {
          id: tabRow
          width: parent.width
          even: true
          textSize: card.ts
          options: [["place", "Place"], ["look", "Look"], ["slides", "Slideshow"]]
          current: card.tab
          // a dot on a page that has something staged in it
          dotted: (card.lookTouched ? ["look"] : []).concat(card.slideOn ? ["slides"] : [])
          onChose: (v) => { card.tab = v; card.editing = ""; }
          Ring { on: card.kb("tabs") }
        }

        // ── PLACE ────────────────────────────────────────────────────
        Item {
          id: placeTab
          anchors.top: tabRow.bottom
          anchors.topMargin: 22
          width: parent.width
          visible: card.tab === "place"

          Head {
            id: dispHead
            text: card.multi ? "Displays" : "Display"
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: dispHead.verticalCenter
            visible: card.multi
            text: card.allStaged ? "None" : "All"
            color: allMa.pressed ? card.highlight : card.dimColor
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: card.ts
            MouseArea {
              id: allMa
              anchors.fill: parent
              anchors.margins: -6
              hoverEnabled: true
              onClicked: card.toggleAllScreens()
            }
          }

          // THE DESK, TO SCALE, each monitor painted by the same Scene the
          // daemon uses with what it would show if Apply were pressed now.
          Rectangle {
            id: map
            anchors.top: dispHead.bottom
            anchors.topMargin: 8
            width: parent.width
            height: 140
            radius: Zenon.radiusCard
            color: Zenon.wash(0.025)
            border.width: 1
            border.color: Zenon.border

            readonly property var rects: {
              const out = [];
              const sc = Quickshell.screens;
              for (let i = 0; i < sc.length; ++i)
                out.push({ x: sc[i].x, y: sc[i].y, w: sc[i].width, h: sc[i].height });
              return out;
            }
            readonly property var bb: Art.boundsOf(map.rects) || { x: 0, y: 0, w: 1, h: 1 }
            readonly property real k:
              Math.min((map.width - 24) / map.bb.w, (map.height - 24) / map.bb.h)
            readonly property real ox: (map.width - map.bb.w * map.k) / 2
            readonly property real oy: (map.height - map.bb.h * map.k) / 2


            Repeater {
              model: Quickshell.screens
              delegate: Item {
                id: mon
                required property var modelData
                required property int index
                readonly property string name: mon.modelData.name
                readonly property bool staged: card.stageScreens.indexOf(mon.name) >= 0
                readonly property string shownPath: mon.staged
                  ? card.path : Picasso.wallpaperFor(mon.name)
                readonly property string fit: card.stagedFitFor(mon.name)
                readonly property var look: card.lookFor(mon.name)
                // a span, in this monitor's own coordinates, scaled to the map
                readonly property var spanRect: mon.staged
                  ? card.stagedSpan : Picasso.spanRectFor(mon.name)
                readonly property var target: mon.spanRect ? {
                  x: (mon.spanRect.x - mon.modelData.x) * map.k,
                  y: (mon.spanRect.y - mon.modelData.y) * map.k,
                  w: mon.spanRect.w * map.k, h: mon.spanRect.h * map.k
                } : null

                x: map.ox + (mon.modelData.x - map.bb.x) * map.k
                y: map.oy + (mon.modelData.y - map.bb.y) * map.k
                width: mon.modelData.width * map.k
                height: mon.modelData.height * map.k

                ClippingRectangle {
                  id: glass
                  anchors.fill: parent
                  anchors.margins: 2
                  radius: Zenon.radiusControl
                  color: Zenon.mix(Zenon.ground, Zenon.card, 0.4)
                  border.width: mon.staged ? 2 : 1
                  border.color: mon.staged ? card.highlight
                    : (monMa.pressed ? Qt.rgba(1, 1, 1, 0.35) : Zenon.border)
                  Behavior on border.color {
                    ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                  }

                  Scene {
                    id: monScene
                    anchors.fill: parent
                    opacity: mon.staged ? 1 : 0.4
                    Behavior on opacity {
                      NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease }
                    }
                    look: mon.look
                    target: mon.target
                    unit: map.k
                    solid: Art.colorOf(mon.shownPath)
                    thumb: card.picker.thumbOf[mon.shownPath] || ""
                    accent: (mon.look.backdrop === "accent" || mon.look.tint === "accent")
                      ? Picasso.accentFor(mon.shownPath) : ""

                    Image {
                      id: monImg
                      anchors.fill: parent
                      visible: monScene.solid === ""
                      readonly property var nat: card.dims[mon.shownPath]
                      readonly property bool natural:
                        (mon.fit === "pad" || mon.fit === "tile") && !!monImg.nat
                      readonly property string thumb: card.picker.thumbOf[mon.shownPath] || ""
                      source: mon.shownPath === "" || monScene.solid !== "" ? ""
                        : (monImg.thumb !== "" ? "file://" + monImg.thumb : Strings.fileUrl(mon.shownPath))
                      fillMode: card.fillOf(mon.fit)
                      horizontalAlignment: monScene.hAlign
                      verticalAlignment: monScene.vAlign
                      sourceSize: monImg.natural
                        ? Qt.size(Math.max(1, Math.round(monImg.nat.w * map.k)),
                                  Math.max(1, Math.round(monImg.nat.h * map.k)))
                        : Qt.size(Math.ceil(Math.max(monImg.width, monImg.height) * 2),
                                  Math.ceil(Math.max(monImg.width, monImg.height) * 2))
                      asynchronous: true
                    }
                  }
                }

                Rectangle {
                  anchors.left: glass.left
                  anchors.bottom: glass.bottom
                  anchors.margins: 4
                  width: Math.min(tag.implicitWidth + 10, glass.width - 8)
                  height: 18
                  radius: Zenon.rad(3)
                  color: Zenon.hud(0.7)
                  Text {
                    id: tag
                    anchors.centerIn: parent
                    width: Math.min(tag.implicitWidth, parent.width - 10)
                    elide: Text.ElideRight
                    text: (card.multi ? (mon.index + 1) + "  " : "") + mon.name
                    color: mon.staged ? card.highlight : Zenon.white
                    font.family: Zenon.face
                    font.weight: 600
                    font.pixelSize: Zenon.px(12)
                  }
                }

                Rectangle {
                  anchors.right: glass.right
                  anchors.top: glass.top
                  anchors.margins: 4
                  width: 16
                  height: 16
                  radius: height / 2
                  visible: card.multi
                  color: mon.staged ? card.highlight : Zenon.hud(0.6)
                  border.width: mon.staged ? 0 : 1
                  border.color: Zenon.wash(0.4)
                  Text {
                    anchors.centerIn: parent
                    visible: mon.staged
                    text: ""
                    color: Zenon.onAccent
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(9)
                  }
                }

                MouseArea {
                  id: monMa
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: card.multi
                  onClicked: card.toggleScreen(mon.name)
                }
                Ring { on: card.kb("displays", mon.index) }
              }
            }
          }

          // ONE PICTURE ACROSS THE DESK. Each monitor shows the slice that
          // falls where it actually sits, so a line in the picture carries
          // on straight from one screen onto the next.
          Controls.Check {
            height: 28
            id: spanSwitch
            anchors.top: map.bottom
            anchors.topMargin: 10
            width: parent.width
            visible: card.multi
            label: card.stageScreens.length < 2 ? "Span (pick two displays)"
              : "Span across " + (card.allStaged ? "all displays"
                                  : card.stageScreens.length + " displays")
            lit: card.stageSpan
            opacity: card.stageScreens.length < 2 ? 0.5 : 1
            kbOn: card.kb("span")
            onToggled: card.stageSpan = !card.stageSpan
          }

          Item {
            id: pictureOpts
            anchors.top: card.multi ? spanSwitch.bottom : map.bottom
            anchors.topMargin: 14
            width: parent.width
            height: 200
            // a color has no picture to fit, place or turn
            visible: !card.isColor

            Head { id: fitHead; text: "Fit" }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: fitHead.verticalCenter
              text: card.stageFit !== "" ? "Changing"
                : (card.sharedFit !== "" ? "keeping " + Picasso.fitLabels[card.sharedFit]
                                         : "Keeping each display's")
              color: card.stageFit !== "" ? card.highlight : card.dimColor
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: card.tsSmall
            }

            // ── SEGMENTS, PICTOGRAMS KEPT (user, 2026-10-14) ──────────
            // The suite's switch, each part with its FitGlyph over the word.
            // Lit is the fit in force; a staged one wears the dot as the
            // tabs do, and choosing it again unstages it (pickFit).
            Term.Segments {
              id: fitRow
              anchors.top: fitHead.bottom
              anchors.topMargin: 8
              width: pictureOpts.width
              even: true
              textSize: card.tsSmall
              weight: Font.Normal
              artH: 16
              art: Component {
                FitGlyph {
                  mode: parent ? parent.value : "crop"
                  ink: parent ? parent.ink : card.dimColor
                }
              }
              options: Picasso.fitModes.map((m) => [m, Picasso.fitLabels[m]])
              current: card.effFit
              dotted: card.stageFit !== "" ? [card.stageFit] : []
              onChose: (v) => card.pickFit(v)
              Ring { on: card.kb("fit") }
            }

            // which part of the picture a crop keeps — a picture of the
            // screen, nine places to click
            Head {
              id: posHead
              anchors.top: fitRow.bottom
              anchors.topMargin: 16
              text: "Keep"
            }
            Item {
              id: posBox
              anchors.top: posHead.bottom
              anchors.topMargin: 8
              width: posGrid.width
              height: posGrid.height
              Ring { on: card.kb("position") }
            }
            Grid {
              id: posGrid
              anchors.top: posHead.bottom
              anchors.topMargin: 8
              columns: 3
              spacing: 3
              Repeater {
                model: Art.alignKeys
                delegate: Rectangle {
                  id: cell
                  required property string modelData
                  readonly property bool on: card.look.align === cell.modelData
                  width: 22
                  height: 14
                  radius: Zenon.rad(3)
                  color: cell.on ? card.highlight
                    : (cellMa.pressed ? Zenon.wash(0.22) : Zenon.wash(0.07))
                  border.width: 1
                  border.color: cell.on ? card.highlight : Zenon.border
                  MouseArea {
                    id: cellMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: card.setLook("align", cell.modelData)
                  }
                }
              }
            }
            Text {
              anchors.left: posGrid.right
              anchors.leftMargin: 12
              anchors.verticalCenter: posGrid.verticalCenter
              width: 80
              text: ({ tl: "top left", t: "top", tr: "top right", l: "left", c: "centre",
                       r: "right", bl: "bottom left", b: "bottom", br: "bottom right" })[card.look.align]
              color: card.look.align !== "c" ? card.fgColor : card.dimColor
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: card.tsSmall
              wrapMode: Text.WordWrap
            }

            // turn and mirror
            Head {
              id: turnHead
              anchors.top: fitRow.bottom
              anchors.topMargin: 16
              anchors.left: turnRow.left
              text: "Turn"
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: turnHead.verticalCenter
              text: card.look.rotate + "°" + (card.look.mirror ? "  mirrored" : "")
              color: card.look.rotate !== 0 || card.look.mirror ? card.highlight : card.dimColor
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: card.tsSmall
            }
            Row {
              id: turnRow
              anchors.right: parent.right
              anchors.top: turnHead.bottom
              anchors.topMargin: 8
              spacing: 4
              Seg {
                id: turnL
                width: 52; height: 48
                kbOn: card.kb("turn", 0)
                onHit: card.turn(-90)
                Text {
                  anchors.centerIn: parent
                  text: ""
                  color: turnL.ink
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(16)
                }
              }
              Seg {
                id: turnR
                width: 52; height: 48
                kbOn: card.kb("turn", 1)
                onHit: card.turn(90)
                Text {
                  anchors.centerIn: parent
                  text: ""
                  color: turnR.ink
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(16)
                }
              }
              Seg {
                id: mirrorBtn
                width: 52; height: 48
                chosen: card.look.mirror
                kbOn: card.kb("turn", 2)
                onHit: card.setLook("mirror", !card.look.mirror)
                Text {
                  anchors.centerIn: parent
                  text: ""
                  color: mirrorBtn.ink
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(16)
                }
              }
            }
          }
        }

        // ── LOOK ─────────────────────────────────────────────────────
        Item {
          id: lookTab
          anchors.top: tabRow.bottom
          anchors.topMargin: 22
          width: parent.width
          visible: card.tab === "look" && card.editing === ""

          LookEditor {
            width: parent.width
            look: card.look
            path: card.path
            showBackdrop: !card.isColor
            // cropped or stretched, the picture covers the screen
            fills: card.effFit === "crop" || card.effFit === "stretch"
            kbRow: card.kbShown ? card.kbRow : ""
            customTint: card.customTint
            tips: cardTips
            onTouched: (key, value) => card.setLook(key, value)
            onResetLook: card.resetLook()
            onEditColor: (which) => card.editing = which
            showAccent: true
            accent: card.accentNow
            customAccent: card.customAccent
            onAccentChosen: (h) => card.setAccent(h)
            onPickAccent: Picasso.pickFor("card:accent")
          }
        }

        // ── choosing a color for the look ───────────────────────────
        Item {
          anchors.top: tabRow.bottom
          anchors.topMargin: 22
          width: parent.width
          height: 300
          visible: card.editing !== ""

          Head {
            id: edHead
            text: card.editing === "tint" ? "Tint color"
              : card.editing === "accent" ? "Accent color" : "Color around it"
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: edHead.verticalCenter
            text: "Done"
            color: doneMa.pressed ? card.highlight : card.fgColor
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: card.ts
            MouseArea {
              id: doneMa
              anchors.fill: parent
              anchors.margins: -6
              hoverEnabled: true
              onClicked: card.editing = ""
            }
          }
          ColorPicker {
            anchors.top: edHead.bottom
            anchors.topMargin: 12
            width: parent.width
            height: 250
            textSize: card.ts
            hex: card.editing === "tint"
              ? (card.tintIsCustom ? card.look.tint : card.customTint)
              : card.editing === "accent" ? (card.accentPending || card.accentNow || Zenon.hex(Zenon.cyan))
              : card.look.backdropColor
            onEdited: (h) => {
              if (card.editing === "tint") { card.customTint = h; card.setLook("tint", h); }
              else if (card.editing === "accent") card.dragAccent(h);
              else card.setLook("backdropColor", h);
            }
            onAccepted: card.editing = ""
            onCancelled: card.editing = ""
          }
        }

        // ── SLIDESHOW ────────────────────────────────────────────────
        Item {
          id: slideTab
          anchors.top: tabRow.bottom
          anchors.topMargin: 22
          width: parent.width
          visible: card.tab === "slides"

          Column {
            width: parent.width
            spacing: 8

            // one already running: what it is doing, and a way to stop it
            Rectangle {
              visible: Picasso.slideshow !== null
              width: parent.width
              height: 40
              radius: Zenon.windowRadius
              color: Qt.rgba(card.entryColor.r, card.entryColor.g, card.entryColor.b, 0.1)
              border.width: 1
              border.color: Qt.rgba(card.entryColor.r, card.entryColor.g, card.entryColor.b, 0.4)
              Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: stopBtn.left
                anchors.verticalCenter: parent.verticalCenter
                text: {
                  const ss = Picasso.slideshow;
                  if (!ss) return "";
                  return "  running · every " + card.minutesText(ss.minutes)
                    + (ss.shuffle ? " · shuffled" : "");
                }
                color: card.entryColor
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: card.ts
                elide: Text.ElideRight
              }
              Text {
                id: stopBtn
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "Stop"
                color: stopMa.pressed ? card.highlight : card.fgColor
                font.family: Zenon.face
                font.weight: 600
                font.pixelSize: card.ts
                MouseArea {
                  id: stopMa
                  anchors.fill: parent
                  anchors.margins: -6
                  hoverEnabled: true
                  onClicked: Picasso.stopSlideshow()
                }
              }
            }

            Controls.Check {
              height: 28
              width: parent.width
              label: "Change the picture on a timer"
              lit: card.slideOn
              kbOn: card.kb("slideOn")
              onToggled: card.slideOn = !card.slideOn
            }

            Column {
              width: parent.width
              spacing: 8
              opacity: card.slideOn ? 1 : 0.4
              enabled: card.slideOn

              Item { width: 1; height: 4 }
              Head { text: "Every" }
              Term.Segments {
                id: ivRow
                width: slideTab.width
                even: true
                textSize: card.ts
                options: card.intervals.map((m) => [String(m), card.minutesText(m)])
                current: String(card.slideMinutes)
                onChose: (v) => card.slideMinutes = parseInt(v, 10)
                Ring { on: card.kb("interval") }
              }

              Item { width: 1; height: 4 }
              Term.Segments {
                id: ordRow
                width: slideTab.width
                even: true
                textSize: card.ts
                options: [["order", "In order"], ["shuffle", "Shuffle"]]
                current: card.slideShuffle ? "shuffle" : "order"
                onChose: (v) => card.slideShuffle = v === "shuffle"
                Ring { on: card.kb("order") }
              }

              Item { width: 1; height: 4; visible: card.picker.query !== "" }
              Head { text: "From"; visible: card.picker.query !== "" }
              Term.Segments {
                id: poolRow
                visible: card.picker.query !== ""
                width: slideTab.width
                even: true
                textSize: card.ts
                options: [["all", "All " + Picasso.files.length],
                          ["filter", "\u201c" + card.picker.query + "\u201d  " + card.picker.filtered.length]]
                current: card.slidePool
                onChose: (v) => card.slidePool = v
                Ring { on: card.kb("pool") }
              }

              Text {
                width: parent.width
                topPadding: 6
                wrapMode: Text.WordWrap
                text: "Starts with this picture, on "
                  + (card.allStaged ? "every display" : card.stageScreens.join(", ") || "no display")
                  + (card.spanning ? ", spanned" : "")
                  + ". Displays, span, fit and look are set on the Place and Look tabs."
                color: card.dimColor
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: card.tsSmall
              }
            }
          }
        }

        // ── the way out ──────────────────────────────────────────────
        Row {
          id: buttons
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 4
          spacing: 8

          DialogButton {
            label: "Cancel"
            ink: card.dimColor
            onClicked: card.picker.closeFocus()
            Ring { on: card.kb("buttons", 0) }
          }
          Term.BusyButton {
            label: card.applyLabel
            ink: card.highlight
            primary: true
            ready: card.stageScreens.length > 0 && card.path !== ""
            busy: card.busy
            busyText: card.busyText
            busyInk: card.highlight
            onClicked: card.apply()
            Ring { on: card.kb("buttons", 1) }
          }
        }
      }
    }
  }

  function minutesText(m) {
    return m >= 60 ? (m / 60) + "h" : m + "m";
  }
}
