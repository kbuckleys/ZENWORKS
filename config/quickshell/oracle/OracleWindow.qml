// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ORACLE's face — the settings panel, drawn entirely from Oracle.schema.
//
// There is no per-setting UI anywhere in this file. A row knows it is a bool,
// a number, one of a list, a line of text or a button, and draws itself
// accordingly; which settings exist, what they are called and what they may be
// set to is Oracle's business alone. Adding a setting is a property and a spec
// over there, and nothing at all here.
//
// NOT A MORPH LAYER, and deliberately the only one in this shell that is not.
//
// Every other panel here is the pill wearing a different shape: it belongs to
// the bar, it opens where the bar is, and it closes back down into it. That is
// right for a thing you glance at — a calendar, a mixer, a notification list —
// because the bar is where you were already looking.
//
// Settings are not that. You come here to change the bar itself, and half the
// controls in here move the pill while you are holding them: the corner
// radius, the row height, the module switches, the animation speed. A panel
// that WAS the pill would have been resizing itself under the pointer on every
// one of those.
//
// So it is a WINDOW, the way ceres is: an ordinary toplevel titled "oracle"
// that hyprland floats. You move it, resize it and put it on another
// workspace with the same hands as anything else, and it can sit beside what
// you are changing instead of over it. OracleManager builds it on the monitor
// you are on and remembers its size.
//
// And because it is free, it is MOUSE-FIRST. The other layers are keyboard
// instruments with a hint strip along the bottom teaching you the chords —
// they are opened, used and dismissed in a second. This one is read and
// poked at. Every control answers to a click or a drag, there is a close
// button rather than a key to learn, and the strip of hints is gone.

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "."
import "oracle.js" as Ora
import "../morpheus"

FloatingWindow {
  id: popup

  title: "oracle"
  implicitWidth: 1000
  implicitHeight: popup.calcHeight()
  minimumSize: Qt.size(640, 420)
  color: popup.bgColor
  visible: false

  // the manager that built it — see OracleManager
  property var mgr: null

  // The size you left it at, handed back by the manager the next time it
  // builds one. Written once a resize settles.
  onWidthChanged: sizeSettle.restart()
  onHeightChanged: sizeSettle.restart()
  Timer {
    id: sizeSettle
    interval: 600
    onTriggered: if (popup.visible && popup.mgr) popup.mgr.noteSize(popup.width, popup.height)
  }

  property bool shown: false

  readonly property color bgColor: Zenon.layerBg
  readonly property color fgColor: Zenon.white
  readonly property color headColor: Zenon.cyan
  readonly property color dimColor: Zenon.muted
  // WHAT YOU ARE TOUCHING, and what has been CHANGED, are two different
  // facts and now wear two different colors.
  //
  // Everything interactive used to light up in the pink — a focused field, an
  // open dropdown, a pressed button, a grabbed knob — and against the dark
  // panel that reads as a red alert rather than as "this one is live". Cyan
  // is the accent the rest of the shell already uses for the thing in hand:
  // the section you are standing in, a slider's filled track, the lit cell in
  // the corner picker.
  //
  // A SECOND color is kept for the one job it is good at: marking a setting
  // that is no longer at its default. That is a STATE rather than an action,
  // it wants to be told apart from the cyan at a glance, and it appears in
  // exactly three places — the toolbar's per-section count, the "n changed"
  // badge in the head, and the dot at the start of a changed row.
  //
  // Yellow rather than the light red it was. Against this ground the pink
  // read as a warning — a changed setting is not a problem, it is a choice —
  // and yellow sits far enough from the cyan to separate at a glance without
  // claiming something has gone wrong. Not sand, which is the RAM meter's
  // and terminus' "modified" ink, and is close enough to the white text here
  // to lose the dot entirely.
  readonly property color highlight: Zenon.cyan
  readonly property color changedColor: Zenon.yellow
  readonly property color errColor: Zenon.red

  readonly property string face: Zenon.face

  // Whose shell this is. Written here rather than in the string below so the
  // name and the address it points at cannot drift apart.
  readonly property string authorName: "Buck"
  readonly property string authorUrl: "https://github.com/kbuckleys"

  // ── what is on screen ─────────────────────────────────────────────────
  // `section` is where you are standing; `query` suspends it. A search is the
  // case where you do not know which section a setting is filed under — that
  // is why you are typing — so a non-empty query searches all of them and the
  // toolbar goes quiet rather than lying about which one you are in.
  property string section: "bar"
  // The last section that actually HAS settings in it. "Reset one section"
  // lives in the about section, so `section` at the moment it is clicked is
  // always "about" — which holds nothing but actions, so the reset would be a
  // button that reliably does nothing. This is what it means instead: the
  // section you were in before you came here.
  property string lastRealSection: "bar"
  property string query: ""
  // the key of the text setting currently being typed into, "" for none. Only
  // ever one: a text row takes the keyboard from the search field while it is
  // open and gives it back on return or escape.
  property string editingKey: ""

  readonly property bool searching: popup.query !== ""

  // ── THE DROPDOWN ──────────────────────────────────────────────────────
  // One card, shared by every enum row, opened where the row's control is.
  // A card per row would be one layer-shell surface per enum setting — there
  // are eight of them — and only ever one can be open.
  //
  // `enumKey` is which setting it belongs to; "" is closed.
  property string enumKey: ""
  property point enumAt: Qt.point(0, 0)
  readonly property var enumSpec: popup.enumKey === ""
    ? null : Oracle.spec(popup.enumKey)

  // Where a corner value sits in the six-cell screen. Lives here rather than
  // in the control because both the closed chip and the open card draw it.
  function cornerCell(v) {
    const t = String(v) === "auto" ? Oracle.notifCorner(Zenon.barTop) : String(v);
    return { row: t.indexOf("top") === 0 ? 0 : 1,
             col: t.indexOf("-left") >= 0 ? 0
                : (t.indexOf("-right") >= 0 ? 2 : 1) };
  }

  // A spec that names a PLACE gets the grid; everything else gets the list.
  readonly property bool enumIsGrid:
    popup.enumSpec !== null && popup.enumSpec.pictogram === "corner"

  // the grid's current cell, and whether the non-place answer is the one
  readonly property bool enumAutoOn: {
    Oracle.revision;
    return popup.enumSpec !== null
      && String(Oracle.get(popup.enumSpec.key)) === "auto";
  }
  readonly property var enumCell: {
    Oracle.revision;
    if (!popup.enumSpec) return { row: -1, col: -1 };
    return popup.cornerCell(Oracle.get(popup.enumSpec.key));
  }

  // Turn a grid cell back into the value that names it. Derived from the
  // spec's own options rather than rebuilt from strings here, so the two
  // cannot describe different sets of corners.
  function valueForCell(r, c) {
    const sp = popup.enumSpec;
    if (!sp) return "";
    const opts = sp.options || [];
    for (let i = 0; i < opts.length; ++i) {
      const v = opts[i].value;
      if (v === "auto") continue;
      const cell = popup.cornerCell(v);
      if (cell.row === r && cell.col === c) return v;
    }
    return "";
  }

  readonly property var enumRows: {
    const sp = popup.enumSpec;
    if (!sp) return [];
    Oracle.revision;
    // A set of devices is ticks, not one choice — see Ora.deviceRows.
    if (sp.type === "devices")
      return Ora.deviceRows(Oracle.get(sp.key), Oracle.solaarDevices,
                            Oracle.solaarScanning);
    const now = Oracle.get(sp.key);
    const opts = sp.options || [];
    const out = [];
    for (let i = 0; i < opts.length; ++i) {
      out.push({ text: opts[i].label,
                 mark: opts[i].value === now,
                 cell: sp.pictogram === "corner"
                   ? popup.cornerCell(opts[i].value) : null });
    }
    return out;
  }

  function openEnumMenu(key, at) {
    popup.enumKey = key;
    popup.enumAt = at;
  }

  function closeEnumMenu() { popup.enumKey = ""; }

  // ── CHOOSING A PATH IN TERMINUS ───────────────────────────────────────
  // Handed in by shell.qml. The picker is a real toplevel window and this
  // panel is an overlay, so the panel steps aside while it is up — an
  // overlay would otherwise stand over the very dialog it opened — and comes
  // back, where it was, the moment an answer arrives.
  property var fileManager: null
  // the key being chosen for, "" for none
  property string pickingKey: ""

  function pickFor(spec, current) {
    if (!spec || !popup.fileManager || popup.pickingKey !== "") return;
    popup.closeEnumMenu();
    popup.editingKey = "";
    if (spec.pick === "font") {
      // Where the current face actually lives, so the picker opens beside
      // it rather than at home. fontconfig knows; nothing here has to guess
      // which of the three font directories it was installed into.
      popup.pickingKey = spec.key;
      fontDirProc.command = ["fc-match", "-f", "%{file}",
        String(current || spec.placeholder || "")];
      fontDirProc.running = true;
      return;
    }
    popup.beginPick(spec.key, true,
      current !== "" ? current : UserDirs.pictures,
      (p) => Oracle.set(spec.key, p));
  }

  function beginPick(key, directory, start, apply) {
    popup.pickingKey = key;
    const ok = popup.fileManager.choose(directory, start, (paths) => {
      popup.pickingKey = "";
      if (paths.length > 0) apply(paths[0]);
      popup.openPopup("");
    });
    if (!ok) { popup.pickingKey = ""; return; }
    popup.closePopup();
  }

  Process {
    id: fontDirProc
    stdout: StdioCollector {
      id: fontDirOut
      waitForEnd: true
      onStreamFinished: {
        const f = String(fontDirOut.text || "").trim();
        const dir = f.indexOf("/") >= 0 ? f.replace(/\/[^\/]*$/, "") : "";
        popup.beginPick("fontFamily", false,
          dir !== "" ? dir : Paths.dataDir() + "/fonts",
          (p) => {
            fontFamilyProc.command = ["fc-query", "-f", "%{family[0]}\n", p];
            fontFamilyProc.running = true;
          });
      }
    }
  }

  // A FILE, TURNED BACK INTO A FAMILY. What is stored is the family without
  // its cut — the shell adds " Propo" and " Mono" itself — so whichever of
  // the three files you picked, the answer is the same. The short "NF"
  // spellings Nerd Fonts also registers are read as the long one.
  Process {
    id: fontFamilyProc
    stdout: StdioCollector {
      id: fontFamilyOut
      waitForEnd: true
      onStreamFinished: {
        const fam = Ora.familyOf(fontFamilyOut.text);
        if (fam === "") return;
        // Not a Nerd Font is refused rather than applied: every icon in the
        // shell — this panel's included — would turn into an empty box, and
        // the way back would be through a panel you could no longer read.
        if (fam.indexOf("Nerd Font") < 0) {
          Quickshell.execDetached(["notify-send", "-a", "oracle",
            "Not a Nerd Font", fam + " has none of the shell's icons, so the font was left as it was."]);
          return;
        }
        Oracle.set("fontFamily", fam);
      }
    }
  }

  // With a query, every match in the panel; without one, the section's rows.
  readonly property var matches: Ora.filterSchema(Oracle.schema, popup.section, popup.query)

  // While searching, the sections the results are filed under — so the
  // toolbar can say where the matches live instead of dimming all of it.
  readonly property var hitSections: {
    const out = ({});
    if (!popup.searching) return out;
    for (let i = 0; i < popup.matches.length; ++i) out[popup.matches[i].section] = true;
    return out;
  }

  // A search narrowed to one section by clicking its tab, "" for all of them.
  // Clicking a tab mid-search used to throw the search away; now it keeps
  // what you typed and shows only that section's matches. If the query
  // changes so that the section has none left, the results widen again
  // rather than going blank.
  property string searchScope: ""

  readonly property var rows: {
    if (!popup.searching || popup.searchScope === ""
        || popup.hitSections[popup.searchScope] !== true)
      return popup.matches;
    return popup.matches.filter((r) => r.section === popup.searchScope);
  }

  // Cleared while narrowed: you land in the section you narrowed to, which
  // is the one you were looking at.
  onSearchingChanged: {
    if (popup.searching || popup.searchScope === "") return;
    const id = popup.searchScope;
    popup.searchScope = "";
    popup.goToSection(id);
  }

  // the hint strip along the bottom, as tall as every other layer's
  readonly property int hintH: 30
  readonly property int bodyH: 460
  // the section toolbar across the top of the body
  readonly property int tabsH: 72
  readonly property int tabsTop: 0
  readonly property int rowH: 64
  // the Arrangement's picture of the desk
  readonly property int arrangeH: 240
  // ── CONTROLS HANG OFF THE RIGHT EDGE ──────────────────────────────────
  // Every control ENDS at the same x, hard against the scrollbar, and each
  // one takes only the width it actually needs. Two things follow from that,
  // and both are the point:
  //
  //   they line up. A column of switches, buttons and dropdowns all flush
  //   right reads as one column, where before they sat in slots of three
  //   different widths all anchored right — so their left edges stepped in
  //   and out down the page.
  //
  //   and a switch gives its room back. A bool needs 44px; it used to
  //   reserve 300 and leave the description to elide against thin air. The
  //   label column runs to whatever the control did not take, so the short
  //   controls buy the long descriptions their space.
  //
  // The widest control decides nothing about the others — see controlSlot,
  // which measures the one it actually loaded.
  readonly property int controlW: 260

  function calcHeight() {
    return popup.tabsTop + popup.tabsH + 1 + popup.bodyH + popup.hintH;
  }

  // ── CLOSED BY THE COMPOSITOR ──────────────────────────────────────────
  // super+q closes the WINDOW, not this object: quickshell reports it as
  // `closed` and leaves `visible` saying true, so nothing would come back on
  // the next open. Closed from outside is closed from inside — see ceres.
  onClosed: popup.closePopup()

  // The section you are in, handed to the manager so a window rebuilt on
  // another monitor opens where this one was left.
  onSectionChanged: if (popup.mgr) popup.mgr.section = popup.section

  // ── THE CARDS' GRAB ───────────────────────────────────────────────────
  // A dropdown is its own layer surface, and a click away from it should put
  // it away. Held only while one is open: the window itself is an ordinary
  // window and needs no grab to keep the keyboard.
  readonly property var grabWindows: {
    const out = [popup];
    if (enumMenu.visible) out.push(enumMenu);
    if (cornerMenu.visible) out.push(cornerMenu);
    return out;
  }

  HyprlandFocusGrab {
    id: grab
    windows: popup.grabWindows
    active: popup.shown && popup.enumKey !== ""
    onCleared: popup.closeEnumMenu()
  }

  // A card opens at a point in THIS window — the chip's bottom-left — and
  // the compositor puts it on screen: see CardPopup, which is why that works
  // from a window at all.
  function openEnumMenuAt(key, local) {
    popup.openEnumMenu(key, local);
  }

  // ── open and close ────────────────────────────────────────────────────

  function openPopup(section) {
    const cold = !popup.visible;
    popup.shown = true;
    if (cold) {
      // What solaar can see is a fact about the desk right now, and the
      // devices row is the one place that shows it — asked again on every
      // open rather than trusted from startup. See Oracle.scanSolaar.
      Oracle.scanSolaar();
      // A settings window is not a launcher: it opens where it was left, so
      // that changing two things in one section is not two walks back to it.
      // Only the query is session state.
      popup.query = "";
      filterInput.text = "";
      popup.editingKey = "";
    }
    // Asked for by name (a keybind, icarus' Display settings): that is a
    // place to go, not a tab to narrow a search to, so any search ends here.
    if (section && section !== "") {
      popup.query = "";
      filterInput.text = "";
      popup.searchScope = "";
      popup.goToSection(section);
    }
    popup.visible = true;
    if (cold) {
      focusRetry.counter = 0;
      focusRetry.restart();
    }
    popup.syncFocus();
  }

  function closePopup() {
    popup.editingKey = "";
    popup.closeEnumMenu();
    popup.shown = false;
    popup.visible = false;
  }

  // The search field holds the keyboard so that typing works without clicking
  // into it first. That is not a keyboard interface — it is the one thing a
  // pointer cannot do for you, and everything else in here is a click.
  function syncFocus() {
    Qt.callLater(() => {
      if (!popup.shown) return;
      if (popup.editingKey === "") filterInput.forceActiveFocus();
    });
  }

  Timer {
    id: focusRetry
    interval: 60
    repeat: true
    property int counter: 0
    onTriggered: {
      if (!popup.shown) { stop(); return; }
      popup.syncFocus();
      if (filterInput.activeFocus) stop();
      if (focusRetry.counter++ > 12) stop();
    }
  }

  // ── moving about ──────────────────────────────────────────────────────

  // ── A SECTION AT A TIME, FROM THE KEYBOARD ────────────────────────────
  // The one chord this mouse-first panel keeps besides escape: ctrl+tab and
  // ctrl+page down step forward, with shift or page up stepping back — what
  // every tabbed window already answers to. Mid-search it walks only the
  // sections with matches, through "all of them" at the end of the ring.
  function stepSection(dir) {
    const ids = [];
    if (popup.searching) {
      ids.push("");
      for (const sec of Oracle.sections)
        if (popup.hitSections[sec.id] === true) ids.push(sec.id);
      const i = ids.indexOf(popup.searchScope);
      popup.searchScope = ids[((i < 0 ? 0 : i) + dir + ids.length) % ids.length];
      Qt.callLater(() => list.positionViewAtBeginning());
      return;
    }
    for (const sec of Oracle.sections) ids.push(sec.id);
    const i = ids.indexOf(popup.section);
    popup.goToSection(ids[((i < 0 ? 0 : i) + dir + ids.length) % ids.length]);
  }

  function goToSection(id) {
    // Mid-search, a tab narrows the results to its section and a second
    // click on it widens them back out. The query is left exactly as typed.
    if (popup.searching) {
      popup.searchScope = popup.searchScope === id ? "" : id;
      if (id === "display") Oracle.scanDisplays();
      popup.closeEnumMenu();
      Qt.callLater(() => list.positionViewAtBeginning());
      popup.syncFocus();
      return;
    }
    // Neither About nor Health holds a setting, so neither is a section
    // "Reset one section" could mean.
    if (popup.section !== "about" && popup.section !== "health")
      popup.lastRealSection = popup.section;
    popup.section = id;
    // The checkup runs on arrival — a Health page showing "not run yet" is
    // a page that makes you press a button to learn anything. Not again
    // within a minute: flicking between sections should not rerun it.
    if (id === "health" && Date.now() - Oracle.checkedAt > 60000) Oracle.runCheckup();
    // and the monitors are looked at again, in case one came or went while
    // nothing was watching — a dock, a KVM, a cable on its way out
    if (id === "display") Oracle.scanDisplays();
    popup.editingKey = "";
    popup.closeEnumMenu();
    Qt.callLater(() => list.positionViewAtBeginning());
    popup.syncFocus();
  }

  function sectionLabel(id) {
    for (let i = 0; i < Oracle.sections.length; ++i)
      if (Oracle.sections[i].id === id) return Oracle.sections[i].label;
    return id;
  }

  // ── controls ──────────────────────────────────────────────────────────
  // One component per kind of thing a setting can be. Each is handed its spec
  // and its live value and reports back through Oracle.set — none of them
  // keeps a copy of the value it is showing, so a reset or an IPC write lands
  // on screen with nothing needing to be told.
  //
  // None of them lights up on hover. A control that changes color when the
  // pointer merely passes over it is reporting where the mouse is, which you
  // already know; the reply that matters is the value moving, and every one of
  // these gives you that on the frame you click.

  // A track and a knob. The whole control is the hit area, because a switch
  // that only answers to its own 18 pixels is a switch you miss.
  component BoolControl: Item {
    id: sw
    property var spec: null
    property bool value: false
    width: 44
    height: 24

    Rectangle {
      id: track
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: 44
      height: 22
      radius: height / 2
      // ON is the same fact every other lit control reports — the thing in
      // hand — so it wears the same cyan rather than a green of its own. A
      // second accent that appears only on switches makes a column of them
      // read as a different kind of control from everything beside it.
      color: sw.value
        ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.30)
                      : Qt.rgba(1, 1, 1, 0.07)
      border.width: 1
      border.color: sw.value ? popup.highlight : Zenon.border
      Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      Behavior on border.color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      Rectangle {
        width: 16
        height: 16
        radius: 8
        y: 3
        x: sw.value ? track.width - width - 3 : 3
        color: sw.value ? popup.highlight : popup.dimColor
        Behavior on x { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
        Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      }
    }

    // only over the switch itself, not the whole empty column beside it
    MouseArea {
      anchors.fill: track
      anchors.margins: -10
      onClicked: Oracle.set(sw.spec.key, !sw.value)
    }
  }

  // A track, the part of it that is filled, a knob, and the reading. Dragging
  // anywhere on the track jumps to that point and then follows the pointer —
  // the knob is not a separate thing to grab, which on a 4px track it would
  // be far too easy to miss. The wheel steps it, for the settings where you
  // want one notch rather than a position.
  component NumControl: Item {
    id: sl
    property var spec: null
    property real value: 0
    width: popup.controlW
    height: 26
    // the reading is flush right and the track runs back from it

    readonly property real frac: sl.spec ? Ora.fraction(sl.spec, sl.value) : 0

    Rectangle {
      id: bar
      anchors.right: reading.left
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      width: 168
      height: 4
      radius: 2
      color: Qt.rgba(1, 1, 1, 0.10)

      Rectangle {
        width: Math.round(bar.width * sl.frac)
        height: parent.height
        radius: 2
        color: popup.headColor
      }

      Rectangle {
        width: 12
        height: 12
        radius: 6
        y: -4
        x: Math.round(bar.width * sl.frac) - 6
        color: drag.pressed ? popup.highlight : popup.headColor
        border.width: 1
        border.color: Zenon.border
        Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      }
    }

    Text {
      id: reading
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      // fixed, so the tracks line up too rather than each starting wherever
      // its own number happened to end
      width: 74
      horizontalAlignment: Text.AlignRight
      text: sl.spec ? Ora.display(sl.spec, sl.value) : ""
      color: popup.fgColor
      font.family: popup.face
      font.weight: Font.Medium
      font.pixelSize: 16
      elide: Text.ElideRight
    }

    MouseArea {
      id: drag
      // Reaches past the track vertically so a press a few pixels high or low
      // still lands on it, and past the left end so the zero position is
      // actually reachable rather than being half a knob outside the control.
      x: -6
      y: -8
      width: bar.width + 12
      height: sl.height + 16
      // the panel's mask has to stand down for this too — a slider dragged
      // past the panel's edge would lose the grab the same way
      onPressed: (m) => { popup.sliderDragging = true; drag.apply(m.x); }
      onPositionChanged: (m) => { if (drag.pressed) drag.apply(m.x); }
      onReleased: popup.sliderDragging = false
      onCanceled: popup.sliderDragging = false
      // The wheel belongs to the LIST everywhere except here, over the track
      // itself — a settings list you cannot scroll past a slider would be
      // worse than a slider you cannot wheel.
      onWheel: (w) => {
        Oracle.nudge(sl.spec.key, w.angleDelta.y > 0 ? 1 : -1);
        w.accepted = true;
      }
      function apply(mx) {
        Oracle.set(sl.spec.key, Ora.fromFraction(sl.spec, (mx - 6) / bar.width));
      }
    }
  }

  // A BUTTON THAT OPENS A LIST, not a ring you step through.
  //
  // A ring is fine for two or three values and hopeless past that: the toast
  // position has seven, and finding "Bottom left" meant clicking until it
  // came round, with no way to see what else was on offer. A dropdown shows
  // the whole set at once and takes one click to reach any of it.
  //
  // The chip still reports the current value, and still draws its pictogram
  // where the spec asks for one — so the closed control and the row you
  // picked in the open card are visibly the same thing.
  component EnumControl: Item {
    id: en
    property var spec: null
    property var value: null
    // a spec may ask for more room, for labels that are long by nature
    readonly property int chipW: (en.spec && en.spec.chipW) || 164
    width: en.chipW
    height: 26

    readonly property bool hasPicto: en.spec && en.spec.pictogram === "corner"
    readonly property bool open: en.spec && popup.enumKey === en.spec.key

    Rectangle {
      id: chip
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: en.chipW
      height: 26
      radius: 4
      color: (en.open || chipMa.pressed)
        ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.18)
        : Qt.rgba(1, 1, 1, 0.06)
      border.width: 1
      border.color: en.open ? popup.highlight : Zenon.border
      Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      Behavior on border.color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      // the same six-cell screen the card's rows draw
      Item {
        id: picto
        visible: en.hasPicto
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? 22 : 0
        height: 15

        readonly property var cell: en.hasPicto
          ? popup.cornerCell(en.value) : null

        Rectangle {
          anchors.fill: parent
          radius: 2
          color: "transparent"
          border.width: 1
          border.color: Zenon.border
        }

        Grid {
          anchors.fill: parent
          anchors.margins: 2
          columns: 3
          rows: 2
          spacing: 1
          Repeater {
            model: 6
            Rectangle {
              required property int index
              width: (picto.width - 6) / 3
              height: (picto.height - 5) / 2
              radius: 1
              readonly property bool lit: picto.cell
                && Math.floor(index / 3) === picto.cell.row
                && (index % 3) === picto.cell.col
              color: lit ? popup.headColor : Qt.rgba(1, 1, 1, 0.10)
              Behavior on color {
                ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
              }
            }
          }
        }
      }

      Text {
        anchors.left: en.hasPicto ? picto.right : parent.left
        anchors.leftMargin: en.hasPicto ? 8 : 10
        anchors.right: caret.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
        text: en.spec ? Ora.display(en.spec, en.value) : ""
        color: popup.fgColor
        font.family: popup.face
        font.weight: Font.Medium
        font.pixelSize: en.hasPicto ? 14 : 15
      }

      // the one mark that says this opens rather than cycles
      Text {
        id: caret
        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        // a chevron, written as an escape: the glyph itself was lost once already
        text: "\uF078"
        color: popup.dimColor
        font.family: popup.face
        font.pixelSize: 11
      }

      MouseArea {
        id: chipMa
        anchors.fill: parent
        onClicked: {
          if (en.open) { popup.closeEnumMenu(); return; }
          // the card hangs off the chip's bottom-left, in this window —
          // the compositor takes it from there (see CardPopup)
          popup.openEnumMenuAt(en.spec.key, chip.mapToItem(null, 0, chip.height + 4));
        }
        // the wheel still steps it, for the two-value ones where opening a
        // card to pick between Bottom and Top would be a ceremony
        onWheel: (w) => {
          Oracle.nudge(en.spec.key, w.angleDelta.y > 0 ? 1 : -1);
          w.accepted = true;
        }
      }
    }
  }

  // ── A SET OF DEVICES ──────────────────────────────────────────────────
  // The enum's chip, reading what the set resolves to, and opening the same
  // card — with ticks in it instead of one choice. See Ora.deviceRows.
  component DevicesControl: Item {
    id: dv
    property var spec: null
    width: 164
    height: 26
    readonly property bool open: dv.spec && popup.enumKey === dv.spec.key

    Rectangle {
      id: dvChip
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: 164
      height: 26
      radius: 4
      color: (dv.open || dvMa.pressed)
        ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.18)
        : Qt.rgba(1, 1, 1, 0.06)
      border.width: 1
      border.color: dv.open ? popup.highlight : Zenon.border
      Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      Behavior on border.color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: dvCaret.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: dv.spec
          ? (Oracle.revision, Ora.displayDevices(Oracle.get(dv.spec.key),
               Oracle.solaarDevices, Oracle.solaarScanned))
          : ""
        color: popup.fgColor
        font.family: popup.face
        font.weight: Font.Medium
        font.pixelSize: 15
      }

      Text {
        id: dvCaret
        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: "\uF078"
        color: popup.dimColor
        font.family: popup.face
        font.pixelSize: 11
      }

      MouseArea {
        id: dvMa
        anchors.fill: parent
        onClicked: {
          if (dv.open) { popup.closeEnumMenu(); return; }
          popup.openEnumMenuAt(dv.spec.key, dvChip.mapToItem(null, 0, dvChip.height + 4));
        }
      }
    }
  }

  // A line of text, edited in place. It does NOT write on every keystroke: a
  // half-typed path is a real path that picasso would go and scan, so the
  // value is committed on return or on losing focus, and escape puts back
  // whatever was there.
  component TextControl: Item {
    id: tx
    property var spec: null
    property string value: ""
    property bool editing: false
    width: popup.controlW
    height: 28

    onEditingChanged: {
      if (tx.editing) {
        field.text = tx.value;
        field.forceActiveFocus();
        field.selectAll();
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: 4
      color: tx.editing ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
      border.width: 1
      border.color: tx.editing ? popup.highlight : Zenon.border
      Behavior on border.color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      Text {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        visible: !tx.editing
        verticalAlignment: Text.AlignVCenter
        // From the LEFT: these are mostly paths, and the end of a path is the
        // part that tells you which one it is.
        elide: Text.ElideLeft
        // Empty is a real answer for most of these — no keyboard, no named
        // monitor, no folder chosen — and an em-dash says only "nothing here".
        // The placeholder says what happens instead, which is the thing you
        // actually want to know before deciding whether to type anything.
        text: tx.value !== "" ? tx.value
          : ((tx.spec && tx.spec.placeholder) ? tx.spec.placeholder : "—")
        color: tx.value === "" ? popup.dimColor : popup.fgColor
        font.family: popup.face
        font.pixelSize: 15
      }

      TextInput {
        id: field

        cursorDelegate: Caret { field: field }
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        visible: tx.editing
        verticalAlignment: TextInput.AlignVCenter
        color: popup.highlight
        selectionColor: Zenon.selBg
        selectedTextColor: popup.fgColor
        font.family: popup.face
        font.pixelSize: 15
        clip: true

        onAccepted: {
          Oracle.set(tx.spec.key, field.text);
          popup.editingKey = "";
          popup.syncFocus();
        }
        Keys.onEscapePressed: (e) => {
          e.accepted = true;
          popup.editingKey = "";
          popup.syncFocus();
        }
        // Losing focus is not canceling. Clicking elsewhere while a path is
        // half-typed should keep what was typed, the way any other text field
        // on this desktop behaves. Escape above is the one that discards, and
        // it has already cleared `editing` by the time this runs.
        onActiveFocusChanged: {
          if (!field.activeFocus && tx.editing) {
            Oracle.set(tx.spec.key, field.text);
            popup.editingKey = "";
          }
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: !tx.editing
      onClicked: popup.editingKey = tx.spec.key
    }
  }

  // ── A PATH YOU CHOOSE RATHER THAN TYPE ────────────────────────────────
  // A text setting whose spec says `pick`. Typing a path from memory is the
  // one job a file manager exists to spare you, and terminus is already
  // there — so the row is a button that opens its picker, and what you pick
  // is what is stored. See pickFor.
  component PickControl: Item {
    id: pk
    property var spec: null
    property string value: ""
    width: popup.controlW
    height: 28

    readonly property bool busy: pk.spec && popup.pickingKey === pk.spec.key

    Rectangle {
      id: pkBox
      anchors.fill: parent
      radius: 4
      color: (pk.busy || pkMa.pressed)
        ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.18)
        : Qt.rgba(1, 1, 1, 0.06)
      border.width: 1
      border.color: pk.busy ? popup.highlight : Zenon.border
      Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      Behavior on border.color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: pkGlyph.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        // A path from the left, like the text field it replaces: the end of
        // a path is the part that says which one it is. The placeholder is
        // a sentence, and reads from its start.
        elide: pk.value !== "" ? Text.ElideLeft : Text.ElideRight
        text: pk.value !== "" ? pk.value
          : ((pk.spec && pk.spec.placeholder) ? pk.spec.placeholder : "—")
        color: pk.value === "" ? popup.dimColor : popup.fgColor
        font.family: popup.face
        font.weight: Font.Medium
        font.pixelSize: 15
      }

      // what it opens: a folder, or a typeface
      Text {
        id: pkGlyph
        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: (pk.spec && pk.spec.pick === "font") ? "" : ""
        color: pk.busy ? popup.highlight : popup.dimColor
        font.family: popup.face
        font.pixelSize: 13
      }

      MouseArea {
        id: pkMa
        anchors.fill: parent
        enabled: !pk.busy
        onClicked: popup.pickFor(pk.spec, pk.value)
      }
    }
  }

  // A fact about the running shell, shown and not settable. Wider than the
  // other controls and elided from the LEFT, because the only one so far is a
  // path and the end of a path is the part that identifies it.
  component InfoControl: Item {
    id: nfo
    property var spec: null
    property string value: ""
    width: popup.controlW + 60
    height: 28

    Text {
      anchors.fill: parent
      verticalAlignment: Text.AlignVCenter
      // LEFT, like every control beside it. It was right-aligned against the
      // panel edge, which put a column of facts and a column of buttons on
      // two different margins.
      horizontalAlignment: Text.AlignRight
      // A path identifies itself by its end and a list of outputs by its
      // start, so which end gets cut is the spec's to say.
      elide: (nfo.spec && nfo.spec.elideLeft) ? Text.ElideLeft : Text.ElideRight
      text: nfo.value
      // A Health row that found something says so in color; every other
      // fact stays dim.
      color: {
        const lv = (Oracle.revision, nfo.spec ? Oracle.infoLevel(nfo.spec.key) : "ok");
        return lv === "bad" ? popup.errColor : lv === "warn" ? popup.changedColor : popup.dimColor;
      }
      font.family: popup.face
      font.pixelSize: 14
    }
  }

  component ActionControl: Item {
    id: ac
    property var spec: null
    // only as wide as its own button, so the description beside it gets the
    // rest — see controlSlot, which measures this
    width: btn.width
    height: 28

    Rectangle {
      id: btn
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(110, verb.implicitWidth + 28)
      height: 28
      radius: 4
      // PRESSED, not hovered. A button has to answer when you use it; it does
      // not have to announce itself when you pass by.
      color: btnMa.pressed
        ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.28)
        : Qt.rgba(1, 1, 1, 0.06)
      border.width: 1
      border.color: Zenon.border
      Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      Text {
        id: verb
        anchors.centerIn: parent
        // A context action names the section it would act on. Generic rather
        // than a special case for one key: any action may declare itself
        // context-bound, and the button then stops being a promise you have to
        // take on trust.
        text: {
          if (!ac.spec) return "";
          const v = ac.spec.verb || "Run";
          return ac.spec.context
            ? v + " " + popup.sectionLabel(popup.lastRealSection) : v;
        }
        color: popup.fgColor
        font.family: popup.face
        font.weight: Font.Medium
        font.pixelSize: 15
      }

      MouseArea {
        id: btnMa
        anchors.fill: parent
        onClicked: Oracle.run(ac.spec.key, popup.lastRealSection)
      }
    }
  }

  // ── THE HOVER TIP ─────────────────────────────────────────────────────
  // One, for the whole window, drawn inside it under the pointer: see resetMa.
  property string tipText: ""
  property point tipAt: Qt.point(0, 0)
  function showTip(text, at) { popup.tipText = text; popup.tipAt = at; }
  function moveTip(at) { popup.tipAt = at; }
  function hideTip() { popup.tipText = ""; }

  // ── the surface ───────────────────────────────────────────────────────

  // set by NumControl, which is created per row and cannot be reached by id
  property bool sliderDragging: false

  Item {
    id: panel
    anchors.fill: parent

    // the hover tip, above everything in the window, kept inside it
    Rectangle {
      id: rowTip
      z: 5000
      visible: popup.tipText !== ""
      width: tipLabel.implicitWidth + 20
      height: tipLabel.implicitHeight + 12
      x: Math.max(4, Math.min(panel.width - width - 4, popup.tipAt.x + 12))
      y: Math.max(4, Math.min(panel.height - height - 4, popup.tipAt.y + 18))
      color: Zenon.panelBg
      border.color: Zenon.border
      border.width: 1
      radius: 6

      Text {
        id: tipLabel
        anchors.centerIn: parent
        text: popup.tipText
        color: Zenon.white
        font.family: popup.face
        font.pixelSize: 14
      }
    }

    // A click anywhere hands the keyboard back to the search field, so typing
    // filters again after a control or a text field had it. Passive —
    // TakeOverForbidden means it watches the press without claiming it — so
    // every control underneath still gets the click that reached it.
    TapHandler {
      acceptedButtons: Qt.AllButtons
      grabPermissions: PointerHandler.TakeOverForbidden
      // ON RELEASE, NEVER ON PRESS. syncFocus() calls forceActiveFocus()
      // through Qt.callLater, so run at the start of a press it lands one
      // event-loop turn in — and a focus change there can cancel the pointer
      // grab of a drag that has only just begun.
      onPressedChanged: {
        if (pressed) return;
        if (filterInput.activeFocus) return;
        popup.syncFocus();
      }
    }

    // and a floor under the controls, so a press on bare panel is not a press
    // on the desktop behind it — and bare panel is exactly "somewhere else"
    // as far as an open dropdown is concerned
    MouseArea {
      anchors.fill: parent
      onClicked: popup.closeEnumMenu()
    }

    // ── AND OVER THE CONTROLS TOO, WHILE ONE IS OPEN ─────────────────
    // The floor above only hears bare panel. A click on another row's
    // toggle or slider went to that control — so it flipped a setting and
    // the dropdown stayed hanging off its chip. Clicking outside a menu
    // puts it away, everywhere on this desktop; the click that does it is
    // spent doing that, so nothing underneath is changed by accident.
    MouseArea {
      anchors.fill: parent
      z: 1000
      visible: popup.enumKey !== ""
      enabled: popup.enumKey !== ""
      acceptedButtons: Qt.AllButtons
      onPressed: (m) => { m.accepted = true; popup.closeEnumMenu(); }
    }

    // ClippingRectangle, not Rectangle + clip: true — Qt's own clip knows
    // nothing about the radius, so a square child painted to the panel's edge
    // fills in the rounded corners behind it.
    ClippingRectangle {
      id: bgRoot
      anchors.fill: parent
      // a ClippingRectangle insets its children by border.width on every side;
      // this hands the content its full box back
      anchors.margins: -bgRoot.border.width
      color: popup.bgColor
      // square and borderless: it is a window now, and hyprland draws a
      // window's corners, border and shadow itself
      radius: 0
      border.width: 0
      focus: true

      // ── the hint strip ─────────────────────────────────────────────
      // Along the bottom, as every other component in this suite has it:
      // the keys in the middle, what you have typed on the left, and how much of the shell is off its defaults on the
      // right. It also holds the search field, which is never seen — what
      // you type goes to it wherever the pointer is.
      Rectangle {
        id: hintBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: popup.hintH
        color: Zenon.hintBg
        z: 2

        Rectangle {
          anchors.top: parent.top
          width: parent.width
          height: 1
          color: Zenon.border
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 14
          anchors.right: hintKeys.left
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          textFormat: Text.StyledText
          text: {
            if (popup.searching) {
              const n = popup.rows.length;
              const q = String(popup.query).replace(/&/g, "&amp;").replace(/</g, "&lt;");
              return "<font color='" + popup.highlight + "'>" + q + "</font>  "
                + n + (n === 1 ? " match" : " matches");
            }
            // no section description: the settings say what they are, and
            // the strip is for what you are doing — here, what you typed,
            // which is otherwise shown nowhere
            return "";
          }
          color: popup.dimColor
          font.family: popup.face
          font.pixelSize: 13
        }

        HintRow {
          id: hintKeys
          anchors.centerIn: parent
          rows: popup.searching
            ? [["ctrl tab", "narrow"], ["esc", "clear"]]
            : [["type", "filter"], ["ctrl tab", "section"], ["esc", "close"]]
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          visible: popup.totalChanged > 0
          text: popup.totalChanged + " changed"
          color: popup.changedColor
          font.family: popup.face
          font.weight: Font.Medium
          font.pixelSize: 13
        }

        TextInput {
          id: filterInput

          cursorDelegate: Caret { field: filterInput }
          width: 1
          height: 1
          opacity: 0
          activeFocusOnTab: false
          // so escape reaches the one handler that decides what it means
          Keys.forwardTo: bgRoot

          onTextChanged: {
            popup.query = filterInput.text;
            Qt.callLater(() => list.positionViewAtBeginning());
          }

          function clear() {
            filterInput.text = "";
            popup.query = "";
          }
        }
      }

      Column {
        anchors.fill: parent

        // ── the body ─────────────────────────────────────────────────
        Item {
          width: parent.width
          // the whole window above the hint strip, so resizing the window
          // grows the list rather than leaving it floating in a margin
          height: parent.height - popup.hintH

          // ── the sections, as a toolbar ──────────────────────────────
          // Across the top, icon over name, the way the old System
          // Preferences laid out its panes — so the settings below get the
          // panel's whole width instead of what a sidebar left them. More
          // sections than fit simply scroll: drag it, or turn the wheel over
          // it, and the one you are in is always brought into view.
          Item {
            id: toolbar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            // the window's top edge is right above it now the head bar is
            // gone, so it is given the room below it again above it
            anchors.topMargin: popup.tabsTop
            height: popup.tabsH
            Flickable {
              id: tabFlick
              // edge to edge: the first and last tiles meet the window's
              // sides, the way the highlight meets its top and bottom
              anchors.fill: parent
              contentWidth: tabRow.width
              contentHeight: height
              flickableDirection: Flickable.HorizontalFlick
              boundsBehavior: Flickable.StopAtBounds
              clip: true
              // centred when it all fits, scrolled when it does not
              leftMargin: Math.max(0, (width - tabRow.width) / 2)

              Behavior on contentX {
                enabled: !tabFlick.dragging && !tabFlick.flicking
                NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease }
              }

              function reveal(item) {
                if (!item || tabRow.width <= width) return;
                const pad = 24;
                const x0 = item.x - pad, x1 = item.x + item.width + pad;
                if (x0 < contentX) contentX = Math.max(0, x0);
                else if (x1 > contentX + width)
                  contentX = Math.min(tabRow.width - width, x1 - width);
              }

              Row {
                id: tabRow
                height: parent.height
                spacing: 0

                Repeater {
                  id: tabRepeater
                  model: Oracle.sections

                  delegate: Item {
                    id: tab
                    required property var modelData
                    required property int index
                    width: Math.max(78, tabLabel.implicitWidth + 22)
                    height: tabRow.height
                    // While searching, a section with a match stays lit and
                    // the rest dim — dimmed rather than removed, because they
                    // are still where settings live, and a toolbar that
                    // vanished would make a search feel like a different screen.
                    readonly property bool hit: popup.hitSections[tab.modelData.id] === true
                    opacity: !popup.searching || tab.hit ? 1 : 0.35
                    Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

                    readonly property bool here: popup.searching
                      ? popup.searchScope === tab.modelData.id
                      : popup.section === tab.modelData.id
                    // Depends on revision for the same reason every row does:
                    // changedIn is a call, not a binding.
                    readonly property int nChanged: {
                      Oracle.revision;
                      return Oracle.changedIn(tab.modelData.id);
                    }

                    onHereChanged: if (here) Qt.callLater(() => tabFlick.reveal(tab))

                    // Only where you ARE. Nothing lights up under the pointer:
                    // the section you are standing in is a fact about the
                    // panel, and where the mouse happens to be is not.
                    // The whole tile, top to bottom and square, the way the old
                    // System Preferences marked the pane you were in: a column
                    // of the toolbar, not a chip floating inside it.
                    Rectangle {
                      anchors.fill: parent
                      color: tab.here ? Zenon.border : "transparent"
                      Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
                    }

                    // The icon over the name, as one group centred in the tile.
                    Column {
                      id: tabGroup
                      anchors.centerIn: parent
                      spacing: 4

                      // The icon, with room above it for the count on its
                      // shoulder, so the count is inside the group and not
                      // hanging out of the top of it.
                      Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        // A box the size of the DRAWING, not of the glyph's
                        // line: a Nerd Font's line box is far taller than its
                        // icons, and measuring the group by it made the
                        // highlight fill the tile and sit the pair off-centre.
                        width: tabIcon.implicitWidth
                        height: 24

                        Text {
                          id: tabIcon
                          anchors.centerIn: parent
                          text: tab.modelData.icon
                          color: tab.here || (popup.searching && tab.hit)
                            ? popup.headColor : popup.dimColor
                          font.family: popup.face
                          font.pixelSize: 21
                          Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
                        }

                        // A count, not a dot: "3" says how much of this
                        // section you have moved, and a dot would only have
                        // said "something". Worn on the icon's shoulder.
                        Text {
                          anchors.left: parent.right
                          anchors.leftMargin: 2
                          anchors.top: parent.top
                          visible: tab.nChanged > 0
                          text: String(tab.nChanged)
                          color: popup.changedColor
                          font.family: popup.face
                          font.weight: Font.DemiBold
                          font.pixelSize: 11
                        }
                      }

                      Text {
                        id: tabLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tab.modelData.label
                        color: tab.here || (popup.searching && tab.hit)
                          ? popup.fgColor : popup.dimColor
                        font.family: popup.face
                        font.weight: tab.here ? Font.DemiBold : Font.Medium
                        font.pixelSize: 13
                        Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: popup.goToSection(tab.modelData.id)
                    }
                  }
                }
              }
            }

            // The wheel, turned over the toolbar, scrolls it sideways: a
            // mouse has no horizontal wheel to speak of, and a row that only
            // scrolled by dragging would read as one that did not scroll.
            WheelHandler {
              target: null
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: (w) => {
                const d = w.angleDelta.x !== 0 ? w.angleDelta.x : w.angleDelta.y;
                const max = Math.max(0, tabRow.width - tabFlick.width);
                tabFlick.contentX = Math.max(0, Math.min(max, tabFlick.contentX - d));
              }
            }

            // Fades and chevrons at whichever ends have more beyond them, so
            // a section that is off the edge is visibly somewhere rather than
            // missing — and the chevron is a way to it, a page at a time.
            readonly property bool moreLeft: tabFlick.contentX > 1
            readonly property bool moreRight:
              tabFlick.contentX < tabRow.width - tabFlick.width - 1

            function page(dir) {
              const max = Math.max(0, tabRow.width - tabFlick.width);
              tabFlick.contentX = Math.max(0, Math.min(max,
                tabFlick.contentX + dir * tabFlick.width * 0.7));
            }

            component EdgeChevron: Item {
              id: edge
              property int dir: 1
              property bool shown: false
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: 44
              opacity: shown ? 1 : 0
              visible: opacity > 0.01
              Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

              Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0; color: edge.dir < 0 ? popup.bgColor : "transparent" }
                  GradientStop { position: 0.55; color: popup.bgColor }
                  GradientStop { position: 1; color: edge.dir < 0 ? "transparent" : popup.bgColor }
                }
              }

              Text {
                anchors.centerIn: parent
                // chevron left / right, as escapes like every other glyph here
                text: edge.dir < 0 ? "\uF053" : "\uF054"
                color: edgeMa.pressed ? popup.headColor : popup.fgColor
                font.family: popup.face
                font.pixelSize: 14
              }

              MouseArea {
                id: edgeMa
                anchors.fill: parent
                enabled: edge.shown
                onClicked: toolbar.page(edge.dir)
              }
            }

            EdgeChevron { anchors.left: parent.left; dir: -1; shown: toolbar.moreLeft }
            EdgeChevron { anchors.right: parent.right; dir: 1; shown: toolbar.moreRight }
          }

          Rectangle {
            id: tabRule
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: toolbar.bottom
            height: 1
            color: Zenon.border
          }

          // the settings themselves
          Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: tabRule.bottom
            anchors.bottom: parent.bottom

            // ── the mark ──────────────────────────────────────────
            // Only over the About section, and not while searching — a
            // search is a flat list across every section, and a banner
            // belonging to one of them sitting on top of it would be
            // claiming the whole list was about that section.
            Item {
              id: markBox
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              visible: popup.section === "about" && !popup.searching
              height: visible ? 132 : 0

              Column {
                anchors.centerIn: parent
                spacing: 0

                Repeater {
                  model: Oracle.mark
                  Text {
                    required property var modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData
                    color: popup.headColor
                    // MONO, not the propo face the rest of the panel is set
                    // in. The figure is three lines of exactly 24 columns and
                    // the whole of it is the grid lining up; a proportional
                    // face closes the gaps between the strokes and it stops
                    // being letters at all.
                    font.family: Zenon.faceMono
                    font.pixelSize: 17
                    // Box-drawing joins edge to edge, so the lines have to
                    // sit exactly one line-height apart or the verticals
                    // break between rows.
                    lineHeight: 1.0
                  }
                }

                // The byline belongs TO the mark, not under it — the gap
                // was reading as a separator between two unrelated things.
                Item { width: 1; height: 6 }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  // StyledText, not RichText: it is one anchor in one line
                  // and StyledText parses <a href> perfectly well, without
                  // pulling in a whole rich-text document to lay out.
                  textFormat: Text.StyledText
                  text: "a desktop suite by <a href=\"" + popup.authorUrl
                    + "\">" + popup.authorName + "</a>"
                  color: popup.dimColor
                  linkColor: popup.headColor
                  font.family: popup.face
                  font.pixelSize: 14

                  // The link opens in whatever the desktop uses for a URL.
                  // execDetached rather than Qt.openUrlExternally: this is a
                  // layer-shell surface with no QDesktopServices behind it,
                  // and xdg-open is what every other outward link in this
                  // shell already goes through.
                  onLinkActivated: (url) => Quickshell.execDetached(
                    ["xdg-open", url])

                  // A link that does not say it is one is a decoration. The
                  // cursor is the only affordance a single word has here, and
                  // it is worth the exception to the panel's no-cursor rule
                  // because nothing else on the page navigates anywhere.
                  HoverHandler {
                    cursorShape: parent.hoveredLink !== ""
                      ? Qt.PointingHandCursor : Qt.ArrowCursor
                  }
                }
              }

              // no rule under the credits — the settings panel draws no
              // horizontal separators, see the rows below
            }

            // ── KEEP THESE DISPLAY SETTINGS? ──────────────────────────
            // Over every section, not only Display: the question stands until
            // it is answered, wherever you went after asking it.
            Rectangle {
              id: confirmBar
              anchors.top: markBox.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              height: Oracle.displayPending ? 52 : 0
              visible: height > 0
              clip: true
              color: Qt.rgba(popup.changedColor.r, popup.changedColor.g,
                             popup.changedColor.b, 0.10)
              Behavior on height { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

              Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Zenon.border
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.right: confirmBtns.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: "Keep these display settings? Going back in "
                  + Oracle.displayCountdown + "s"
                color: popup.changedColor
                font.family: popup.face
                font.weight: Font.Medium
                font.pixelSize: 15
              }

              Row {
                id: confirmBtns
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Repeater {
                  model: [ { text: "Revert", keep: false }, { text: "Keep", keep: true } ]
                  Rectangle {
                    id: cb
                    required property var modelData
                    width: cbText.implicitWidth + 28
                    height: 28
                    radius: 4
                    color: cbMa.pressed
                      ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.25)
                      : cb.modelData.keep ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.14)
                      : Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: cb.modelData.keep ? popup.highlight : Zenon.border

                    Text {
                      id: cbText
                      anchors.centerIn: parent
                      text: cb.modelData.text
                      color: popup.fgColor
                      font.family: popup.face
                      font.weight: Font.Medium
                      font.pixelSize: 14
                    }

                    MouseArea {
                      id: cbMa
                      anchors.fill: parent
                      onClicked: cb.modelData.keep ? Oracle.keepDisplays() : Oracle.revertDisplays()
                    }
                  }
                }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: popup.rows.length === 0
              text: popup.searching ? "nothing matches “" + popup.query + "”"
                                    : "nothing to set here"
              color: popup.dimColor
              font.family: popup.face
              font.weight: Font.Medium
              font.pixelSize: 16
            }

            // The bar takes its width out of the list rather than floating
            // over it: a control sitting at the right edge of a row would
            // otherwise be under the thumb, and the sliders reach almost to
            // that edge. It is only there when there is something to scroll,
            // and the margin goes with it.
            Scrollbar {
              id: scroller
              flick: list
              anchors.right: parent.right
              anchors.top: confirmBar.bottom
              anchors.bottom: parent.bottom
              anchors.topMargin: 2
              anchors.bottomMargin: 2
            }

            ListView {
              id: list
              // Finder's rubber band and the smooth wheel notch, one rule for
              // the whole shell — see morpheus/Elastic.qml. Inside the view
              // rather than over it: it pins itself to the viewport.
              ElasticScroll { view: list }
              anchors.left: parent.left
              anchors.top: confirmBar.bottom
              anchors.bottom: parent.bottom
              anchors.right: scroller.scrollable ? scroller.left : parent.right
              clip: true
              model: popup.rows
              visible: popup.rows.length > 0
              boundsBehavior: Flickable.StopAtBounds

              delegate: Item {
                id: settingRow
                required property var modelData
                required property int index
                width: list.width
                height: settingRow.arrange ? popup.arrangeH : popup.rowH

                readonly property var spec: settingRow.modelData
                readonly property bool arrange: settingRow.spec.type === "arrange"

                // ── A MONITOR'S ROWS, AS ONE GROUP ───────────────────────
                // Two monitors' Resolution rows look exactly alike, so each
                // monitor wears its own ink: a tinted band behind its name,
                // and a stripe down the left of every row that belongs to it.
                readonly property bool monitorRow: settingRow.spec.display === true
                readonly property bool monitorHead: monitorRow && settingRow.spec.field === "about"
                readonly property color accent: settingRow.monitorRow
                  ? Oracle.displayAccent(settingRow.spec.monitor) : "transparent"

                Rectangle {
                  anchors.fill: parent
                  visible: settingRow.monitorHead
                  color: Qt.rgba(settingRow.accent.r, settingRow.accent.g, settingRow.accent.b, 0.10)
                }
                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: 3
                  visible: settingRow.monitorRow
                  color: settingRow.accent
                  opacity: settingRow.monitorHead ? 1 : 0.55
                }

                ArrangeView {
                  anchors.fill: parent
                  visible: settingRow.arrange
                  face: popup.face
                  fgColor: popup.fgColor
                  dimColor: popup.dimColor
                  highlight: popup.highlight
                }
                // get() is a function call and therefore not a dependency;
                // revision is the dependency taken in its place, so a reset or
                // an IPC write repaints this row without it being told.
                // Ora.stored: an action is a button and an info row is a
                // readout, and neither has a value to read back or to compare
                // against a default.
                readonly property bool holds: Ora.stored(settingRow.spec)
                readonly property var live: {
                  Oracle.revision;
                  return settingRow.holds
                    ? Oracle.get(settingRow.spec.key) : null;
                }
                readonly property bool moved: {
                  Oracle.revision;
                  // never a monitor's: see Oracle.changedIn
                  return settingRow.holds && !settingRow.spec.display
                    && !Oracle.isDefault(settingRow.spec.key);
                }

                // No hairline between rows — Buck's call: the rows' own
                // spacing and the two-line label already separate them.

                Column {
                  id: labels
                  visible: !settingRow.arrange
                  anchors.left: parent.left
                  // a monitor's settings step in under its name
                  anchors.leftMargin: settingRow.monitorRow && !settingRow.monitorHead ? 36 : 24
                  anchors.right: controlSlot.left
                  anchors.rightMargin: 18
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 2

                  Row {
                    spacing: 8
                    width: parent.width

                    // A changed setting says so in its own name. A dot in the
                    // gutter was a second thing to find; the label is already
                    // where the eye lands, and it is the widest target in the
                    // row, so it is also what you click to put the setting
                    // back. Nothing moves when it changes color.
                    Text {
                      id: rowLabel
                      // mid-search, where it matched is marked — see Ora.markMatch
                      textFormat: popup.searching ? Text.StyledText : Text.PlainText
                      text: popup.searching
                        ? Ora.markMatch(settingRow.spec.label, popup.query, popup.highlight)
                        : settingRow.spec.label
                      color: settingRow.moved ? popup.changedColor
                        : settingRow.monitorHead ? settingRow.accent : Zenon.white
                      font.family: popup.face
                      font.weight: settingRow.monitorHead ? Font.DemiBold : Font.Medium
                      font.pixelSize: 17

                      MouseArea {
                        id: resetMa
                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: settingRow.moved
                        hoverEnabled: enabled
                        onClicked: {
                          popup.hideTip();
                          Oracle.reset(settingRow.spec.key);
                        }
                        // The one thing hover still does, and it is not an
                        // effect — it is the only place the old value is
                        // written down, and without it the color says a
                        // setting moved but not from what, and gives no hint
                        // that the name is a way back. Drawn inside this
                        // window (see rowTip): a bar tooltip is a layer
                        // surface, and cannot know where a window is.
                        onContainsMouseChanged: {
                          if (!resetMa.containsMouse) { popup.hideTip(); return; }
                          popup.showTip("was " +
                            Ora.display(settingRow.spec, Oracle.defaults[settingRow.spec.key]) +
                            " \u00b7 click to put it back",
                            resetMa.mapToItem(panel, resetMa.mouseX, resetMa.mouseY));
                        }
                        onPositionChanged: (m) => {
                          if (resetMa.containsMouse)
                            popup.moveTip(resetMa.mapToItem(panel, m.x, m.y));
                        }
                      }

                    }

                    // Only while searching. Standing in a section the badge
                    // would say the name already at the top of the panel on
                    // every single row.
                    Rectangle {
                      visible: popup.searching
                      width: sectionBadge.implicitWidth + 12
                      height: 19
                      radius: 3
                      anchors.verticalCenter: parent.verticalCenter
                      color: Qt.rgba(1, 1, 1, 0.07)
                      Text {
                        id: sectionBadge
                        anchors.centerIn: parent
                        text: popup.sectionLabel(settingRow.spec.section)
                        color: popup.dimColor
                        font.family: popup.face
                        font.pixelSize: 12
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    visible: (settingRow.spec.help || "") !== ""
                    textFormat: popup.searching ? Text.StyledText : Text.PlainText
                    text: popup.searching
                      ? Ora.markMatch(settingRow.spec.help, popup.query, popup.highlight)
                      : (settingRow.spec.help || "")
                    elide: Text.ElideRight
                    // The help line is not a footnote — it is the half of the
                    // row that says what the setting actually does, and at 12
                    // against a 17px label it read as one.
                    color: popup.dimColor
                    font.family: popup.face
                    font.pixelSize: 14
                  }
                }

                Item {
                  id: controlSlot
                  visible: !settingRow.arrange
                  anchors.right: parent.right
                  anchors.rightMargin: 20
                  anchors.verticalCenter: parent.verticalCenter
                  // WHAT THE CONTROL ACTUALLY NEEDS, measured off the one
                  // that got loaded rather than reserved for the widest kind
                  // there is. This is what hands a bool row's 200 spare
                  // pixels to its description.
                  width: ctl.item ? ctl.item.width : popup.controlW
                  height: 30

                  Loader {
                    id: ctl
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: {
                      const t = settingRow.spec.type;
                      if (t === "bool") return boolComp;
                      if (t === "enum") return enumComp;
                      if (t === "devices") return devicesComp;
                      if (t === "text")
                        return settingRow.spec.pick ? pickComp : textComp;
                      if (t === "action") return actionComp;
                      if (t === "info") return infoComp;
                      return numComp;
                    }
                  }

                  Component { id: boolComp
                    BoolControl { spec: settingRow.spec
                                  value: settingRow.live === true } }
                  Component { id: numComp
                    NumControl { spec: settingRow.spec
                                 value: Number(settingRow.live) } }
                  Component { id: enumComp
                    EnumControl { spec: settingRow.spec; value: settingRow.live } }
                  Component { id: devicesComp
                    DevicesControl { spec: settingRow.spec } }
                  Component { id: textComp
                    TextControl { spec: settingRow.spec
                                  value: String(settingRow.live)
                                  editing: popup.editingKey === settingRow.spec.key } }
                  Component { id: pickComp
                    PickControl { spec: settingRow.spec
                                  value: String(settingRow.live) } }
                  Component { id: actionComp
                    ActionControl { spec: settingRow.spec } }
                  Component { id: infoComp
                    InfoControl { spec: settingRow.spec
                                  // revision AND shown: the first catches a
                                  // reload that moves the file, the second a
                                  // monitor plugged in while the panel was
                                  // closed — neither is a property, so
                                  // neither is a dependency on its own
                                  value: (Oracle.revision, popup.shown,
                                          Oracle.info(settingRow.spec.key)) } }
                }
              }
            }
          }
        }
      }

      // ── the one key ──────────────────────────────────────────────────
      // Escape, and nothing else. Everything this panel does is a click, and
      // a strip of chords along the bottom would have been teaching a
      // keyboard interface that is no longer here — but escape closing a
      // panel is not a chord, it is what escape does everywhere, and taking
      // it away would be its own surprise.
      Keys.onPressed: (event) => {
        if (!(event.modifiers & Qt.ControlModifier)) return;
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_PageDown) {
          event.accepted = true;
          popup.stepSection((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
        } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_PageUp) {
          event.accepted = true;
          popup.stepSection(-1);
        }
      }

      Keys.onEscapePressed: (event) => {
        event.accepted = true;
        // innermost first: put away what you have built up, and only close
        // once there is nothing left — the same cascade every layer uses
        if (popup.enumKey !== "") {
          popup.closeEnumMenu();
        } else if (popup.editingKey !== "") {
          popup.editingKey = "";
          popup.syncFocus();
        } else if (popup.searching) {
          filterInput.clear();
        } else {
          popup.closePopup();
        }
      }
    }
  }

  // How many settings, everywhere, are off their defaults. Bound here rather
  // than in the badge so the count is computed once per revision instead of
  // once per repaint of a Text.
  readonly property int totalChanged: {
    Oracle.revision;
    return Oracle.changedIn("");
  }



  // ── the dropdown ──────────────────────────────────────────────────────
  // icarus' card, shared by every enum row. It is a separate layer surface,
  // so it is in the focus grab above; without that, opening it would read as
  // a click outside the panel and take the panel down with it.
  CardPopup {
    id: enumMenu
    window: popup
    open: popup.enumKey !== "" && !popup.enumIsGrid
    at: popup.enumAt
    model: popup.enumRows
    // the narrowest it may be — the Menu width every other menu on the
    // desktop is cut to — and it grows to its longest option rather than
    // eliding one. See CardMenu.fit
    cardWidth: Zenon.menuWidth
    fit: true

    onChosen: (i) => {
      const sp = popup.enumSpec;
      if (!sp) return;
      // ── TICKS STAY OPEN ────────────────────────────────────────────
      // Choosing between options is one click and done; a set of devices
      // is as many clicks as you have devices, so the card stays up until
      // you click away or press escape.
      if (sp.type === "devices") {
        const row = popup.enumRows[i];
        if (!row) return;
        if (row.act === "auto") Oracle.set(sp.key, "auto");
        else if (row.act === "toggle")
          Oracle.set(sp.key, Ora.toggleDevice(Oracle.get(sp.key), row.name,
                                              Oracle.solaarDevices));
        else if (row.act === "rescan") Oracle.scanSolaar();
        return;
      }
      const opts = sp.options || [];
      if (i >= 0 && i < opts.length) Oracle.set(sp.key, opts[i].value);
      popup.closeEnumMenu();
    }
    onDismissed: popup.closeEnumMenu()
  }

  // The same dropdown for the settings that name a place: the screen itself,
  // with six cells you click. See CornerPicker.
  CornerPicker {
    id: cornerMenu
    window: popup
    open: popup.enumKey !== "" && popup.enumIsGrid
    at: popup.enumAt
    cellRow: popup.enumCell.row
    cellCol: popup.enumCell.col
    autoOn: popup.enumAutoOn
    autoLabel: "Follow bar"

    onPicked: (r, c) => {
      const v = popup.valueForCell(r, c);
      if (v !== "" && popup.enumSpec) Oracle.set(popup.enumSpec.key, v);
      popup.closeEnumMenu();
    }
    onPickedAuto: {
      if (popup.enumSpec) Oracle.set(popup.enumSpec.key, "auto");
      popup.closeEnumMenu();
    }
    onDismissed: popup.closeEnumMenu()
  }


}
