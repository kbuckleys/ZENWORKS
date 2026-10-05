// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PLATO'S OWN SETTINGS — what its settings sheet (editor/SettingsSheet.qml)
// draws and changes. Kept here rather than in oracle: the editor's settings
// belong in the editor, a keystroke away from the text they change.
//
// ORACLE'S SHAPE, AND ORACLE'S ARITHMETIC. Each setting is a real property,
// so the windows bind to it and follow a change at once; `specs` describes
// the same set for the sheet to draw itself from; the defaults are read off
// the declarations before the file is loaded, never written twice. Coercing,
// stepping, reading out and writing the file are oracle.js's (coerce, nudge,
// display, serialize, parse) — one set of rules for every settings file in
// the shell.
//
// ONLY WHAT WAS CHANGED is written, to the shell's state directory as
// plato.json — absent means "whatever plato thinks", so a default improved
// later reaches an install that never touched it.
//
// CARRIED OVER FROM ORACLE. These lived in oracle's "Editor" section until
// 2026-10-03. With no plato.json yet, whatever oracle.json still holds for
// them is read once and written here; oracle drops the old keys on its own
// next save (its parse skips keys it no longer has).

import QtQuick
import Quickshell
import Quickshell.Io
import "../../oracle"
import "../../oracle/oracle.js" as Ora

QtObject {
  id: root

  // ── the text ───────────────────────────────────────────────────────
  property int fontSize: 14
  property string fontFamily: "JetBrainsMono Nerd Font"
  property string fontWeight: "semibold"

  // ── the cursor and motion ──────────────────────────────────────────
  property bool cursorBreathes: true
  property bool cursorGlides: true
  property bool smoothScroll: true
  property bool editFlash: true
  property bool stickyScroll: true
  property bool keyHints: true
  property bool minimap: true
  property bool animateLayout: true
  // zen mode's text column, in characters
  property int zenWidth: 100
  // zen mode keeps the cursor's line in the middle of the window
  property bool typewriter: false
  property bool indentGuides: true
  property bool jumpTrail: true

  // ── editing: nvim's options, sent to every engine ─────────────────
  property bool wrap: true
  property bool relativeNumbers: true
  property int tabWidth: 4
  property bool expandTab: true
  property int scrollOff: 8
  property bool smartCase: true
  property bool completeAsYouType: true
  property bool cmdlineAsYouType: true
  property bool trimOnSave: false
  property bool formatOnSave: false
  property bool saveOnBlur: false
  property bool reopenTabs: false
  // a file bigger than this opens with the extras off (large.lua)
  property int largeFileMB: 5
  // the window that opens on an empty buffer: recent files, pins, projects
  property bool startCard: true
  // `qs ipc call Plato capture`: the note it opens (strftime's % codes work)
  property string captureFile: "~/.local/share/quickshell/plato/scratch.md"

  // ── git ────────────────────────────────────────────────────────────
  property bool gitGutter: true
  property bool gitBlame: true

  // ── the file tree ──────────────────────────────────────────────────
  property bool treeShown: false
  property int treeWidth: 300
  property bool treeHidden: true

  // ── notifications ──────────────────────────────────────────────────
  property int notifyTimeout: 4000

  // Bumped on every write: the sheet's rows read through get(), which is no
  // binding dependency, and take this one instead (oracle's `revision`).
  property int revision: 0

  readonly property var sections: [
    { id: "text",    label: "Text",          icon: "\u{F0284}" },
    { id: "editing", label: "Editing",       icon: "\u{F03EB}" },
    { id: "motion",  label: "Cursor & motion", icon: "\u{F0B5B}" },
    { id: "git",     label: "Git",           icon: "\u{F02A2}" },
    { id: "tree",    label: "File tree",     icon: "\u{F0645}" },
    { id: "notify",  label: "Notifications", icon: "\u{F009A}" },
  ]

  readonly property var specs: [
    { key: "fontSize", section: "text", label: "Text size", type: "int",
      min: 10, max: 32, step: 1, unit: "px",
      help: "For every tab that has not been zoomed. Ctrl = and Ctrl - zoom the current tab only; Ctrl 0 brings it back to this." },
    { key: "fontFamily", section: "text", label: "Typeface", type: "text", pick: "font",
      help: "Any monospaced face installed: plato lays its text out on a grid of equal cells." },
    { key: "fontWeight", section: "text", label: "Weight", type: "enum",
      options: [ { value: "regular",  label: "Regular" },
                 { value: "medium",   label: "Medium" },
                 { value: "semibold", label: "SemiBold" },
                 { value: "bold",     label: "Bold" } ],
      help: "How heavy the text is drawn. Bold syntax stays a step heavier." },

    { key: "wrap", section: "editing", label: "Wrap long lines", type: "bool",
      help: "Off, a long line runs off the right and the view follows the cursor sideways." },
    { key: "relativeNumbers", section: "editing", label: "Relative line numbers", type: "bool",
      help: "Count the lines above and below from the cursor's. Off, every line shows its own number." },
    { key: "tabWidth", section: "editing", label: "Indent width", type: "int",
      min: 1, max: 8, step: 1, unit: "",
      help: "Columns a tab stop and one level of indent take. A file's own modeline or LSP settings still win." },
    { key: "expandTab", section: "editing", label: "Indent with spaces", type: "bool",
      help: "Tab inserts spaces. Off, it inserts a real tab." },
    { key: "scrollOff", section: "editing", label: "Lines kept around the cursor", type: "int",
      min: 0, max: 20, step: 1, unit: "",
      help: "How close the cursor may come to the top or bottom before the view scrolls." },
    { key: "smartCase", section: "editing", label: "Smart case search", type: "bool",
      help: "A search in lower case ignores case; one with a capital in it does not." },
    { key: "completeAsYouType", section: "editing", label: "Complete as you type", type: "bool",
      help: "The completion menu opens by itself in insert mode. Off, Ctrl-N and Ctrl-Space still open it." },
    { key: "cmdlineAsYouType", section: "editing", label: "Command line suggestions", type: "bool",
      help: "Commands, paths and options are offered under : as you type; Tab moves through them." },
    { key: "trimOnSave", section: "editing", label: "Trim trailing spaces on save", type: "bool",
      help: "Whitespace at the ends of lines is removed when a file is written. Markdown's two-space breaks are kept." },
    { key: "formatOnSave", section: "editing", label: "Format on save", type: "bool",
      help: "The file is formatted before it is written: by its language's own formatter (stylua, shfmt, prettier, ruff) when one is installed, otherwise by the language server when it knows how." },
    { key: "saveOnBlur", section: "editing", label: "Save when the window loses focus", type: "bool",
      help: "Every file with unsaved changes is written when you switch to another window. A new buffer with no file is left alone." },
    { key: "reopenTabs", section: "editing", label: "Reopen a project's tabs", type: "bool",
      help: "The first file opened in a window brings back the other files you had open in its project. Space R does it on demand." },
    { key: "largeFileMB", section: "editing", label: "Large file threshold", type: "int",
      min: 1, max: 200, step: 1, unit: "MB",
      help: "A file bigger than this opens with syntax colour, language servers, git, the minimap, guides and the other extras off, so it stays quick to move through." },
    { key: "startCard", section: "editing", label: "Start card", type: "bool",
      help: "An empty window lists your recent files, pinned files and projects; 1 to 9 opens one." },
    { key: "captureFile", section: "editing", label: "Quick capture note", type: "text",
      help: "The file `qs ipc call Plato capture` opens in a small window of its own. strftime's % codes make it a daily note: ~/notes/%Y-%m-%d.md." },
    { key: "keyHints", section: "editing", label: "Hint what can come next", type: "bool",
      help: "Pause halfway through a command — after g, z, [ or ], ctrl w, a register, or d, c and y waiting for a motion — and a card lists what can follow. It never takes a key." },

    { key: "cursorBreathes", section: "motion", label: "Breathing cursor", type: "bool",
      help: "The cursor fades in and out while it sits still, as the shell's caret does. Off, it stays solid." },
    { key: "cursorGlides", section: "motion", label: "Gliding cursor", type: "bool",
      help: "The cursor eases from where it was to where it went, so the eye can follow a jump." },
    { key: "smoothScroll", section: "motion", label: "Smooth scrolling", type: "bool",
      help: "The text glides to a new scroll position rather than jumping there." },
    { key: "editFlash", section: "motion", label: "Flash yanks and deletes", type: "bool",
      help: "What was yanked lights up for a moment; what was deleted fades away where it was." },
    { key: "stickyScroll", section: "motion", label: "Sticky scroll", type: "bool",
      help: "The lines that open the function or block you are scrolled into stay pinned over the top of the text. A click goes to one." },
    { key: "minimap", section: "motion", label: "Minimap", type: "bool",
      help: "The file in miniature down the right edge, with what is on screen outlined. Click or drag it to go there. Hidden when the window is narrow." },
    { key: "animateLayout", section: "motion", label: "Animate splits and tabs", type: "bool",
      help: "Splits slide to their new size; a tab grows into the strip and shrinks out of it." },
    { key: "indentGuides", section: "motion", label: "Indent guides", type: "bool",
      help: "A line down each level of indentation, drawn as the file tree draws its own; the block the cursor is in is drawn brighter." },
    { key: "jumpTrail", section: "motion", label: "Jump trail", type: "bool",
      help: "A jump of more than a few lines (gg, G, a search, go to definition) leaves a brief streak from where the cursor was." },
    { key: "typewriter", section: "motion", label: "Typewriter scrolling in zen", type: "bool",
      help: "In zen mode the cursor's line stays in the middle of the window and the text moves past it." },
    { key: "zenWidth", section: "motion", label: "Zen mode text width", type: "int",
      min: 60, max: 200, step: 4, unit: "",
      help: "How many characters wide zen mode's centred column is (Space z)." },

    { key: "gitGutter", section: "git", label: "Changes in the gutter", type: "bool",
      help: "A bar down the gutter's edge where lines were added (green) or changed (yellow) since the last commit, and a red wedge where some were deleted. Also on the scrollbar." },
    { key: "gitBlame", section: "git", label: "Blame the cursor's line", type: "bool",
      help: "Who last changed the line you are on, and when, at its end — a moment after the cursor stops." },

    { key: "treeShown", section: "tree", label: "Show the file tree", type: "bool",
      help: "Your home directory down the left of every window, opened to the file you are editing. | shows and focuses it, and puts it away." },
    { key: "treeWidth", section: "tree", label: "Width", type: "int",
      min: 180, max: 700, step: 10, unit: "px",
      help: "Also set by dragging the tree's edge." },
    { key: "treeHidden", section: "tree", label: "Show hidden files", type: "bool",
      help: "Dotfiles in the tree. . switches it while the tree has the keys." },

    { key: "notifyTimeout", section: "notify", label: "Message timeout", type: "int",
      min: 1000, max: 15000, step: 500, unit: "ms",
      help: "How long a message stays in the corner. Warnings stay half as long again, errors twice as long; output of several lines waits for a key." },
  ]

  function spec(key) {
    for (let i = 0; i < root.specs.length; ++i) if (root.specs[i].key === key) return root.specs[i];
    return null;
  }
  function get(key) { return root[key]; }
  function set(key, value) {
    const s = root.spec(key);
    if (!s) return;
    const v = Ora.coerce(s, value);
    if (Ora.same(root[key], v)) return;
    root[key] = v;
    root.revision++;
    saveTimer.restart();
  }
  function nudge(key, dir) {
    const s = root.spec(key);
    if (s) root.set(key, Ora.nudge(s, root[key], dir));
  }
  function reset(key) { root.set(key, root.defaults[key]); }
  function isDefault(key) { return Ora.same(root[key], root.defaults[key]); }
  function display(key) { return Ora.display(root.spec(key), root[key]); }

  // ── the file ───────────────────────────────────────────────────────
  property var defaults: ({})
  readonly property string path: Quickshell.statePath("plato.json")

  property Timer saveTimer: Timer {
    // a slider dragged is a burst of sets: one write at the end of it
    interval: 400
    onTriggered: root.save()
  }
  function save() {
    const vals = ({});
    for (const s of root.specs) vals[s.key] = root[s.key];
    root.file.setText(Ora.serialize(root.specs, vals, root.defaults));
  }
  function load(text) {
    const j = Ora.parse(root.specs, text);
    for (const k in j) root[k] = j[k];
    root.revision++;
  }

  property FileView file: FileView {
    path: root.path
    blockLoading: true
    printErrors: false
  }
  // oracle's file, read once for the settings plato used to keep there
  property FileView oracleFile: FileView {
    path: Oracle.statePath
    blockLoading: true
    printErrors: false
  }
  readonly property var _fromOracle: ({
    platoFontSize: "fontSize", platoFontFamily: "fontFamily", platoFontWeight: "fontWeight",
    platoTreeShown: "treeShown", platoTreeWidth: "treeWidth", platoWrap: "wrap",
    platoRelativeNumbers: "relativeNumbers",
  })

  Component.onCompleted: {
    const d = ({});
    for (const s of root.specs) d[s.key] = root[s.key];
    root.defaults = d;
    const mine = String(root.file.text() || "").trim();
    if (mine !== "") { root.load(mine); return; }
    let old = null;
    try { old = JSON.parse(String(root.oracleFile.text() || "").trim() || "{}"); } catch (e) {}
    if (!old) return;
    const carried = ({});
    for (const k in root._fromOracle) if (k in old) carried[root._fromOracle[k]] = old[k];
    if (Object.keys(carried).length === 0) return;
    root.load(JSON.stringify(carried));
    root.save();
  }
}
