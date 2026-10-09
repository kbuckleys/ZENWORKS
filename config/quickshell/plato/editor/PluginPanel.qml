// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The plugin manager: what is installed, and what vim.pack would update.
//
// A view of core/Plugins.qml, which does the work for every window (and
// feeds the status line's indicator). Three pages, Tab between them:
//
//   INSTALLED   every plugin in plato/nvim/plugins.json
//     a           add one: owner/repo, or a git URL — cloned, and loaded
//                 into this window at once
//     Space       switch it off (kept on disk, not loaded) or on again
//     c / Enter   configure: its Lua file, opened in plato
//     d d         remove it, from the list and the disk
//
//   UPDATES     each plugin with an update, and the commits it would bring
//     Enter / u   update the plugin under the cursor
//     U           update every one listed
//     Space / →   show or hide a plugin's commits
//     r           check again
//
//   PARSERS     every language nvim-treesitter has a grammar for (the
//               current file's first, then those built, then the rest).
//               Typing filters it (fuzzy, by name), so its verbs are ctrl:
//     Enter       build it (or build it again at its pinned revision)
//     ctrl u      rebuild every one that is behind its pin
//     ctrl d ×2   remove one
//     ctrl r      list again
//     Esc         clear the filter (a second Esc closes)
//
//   Esc         close (or leave the name being typed)
//
// An update or install rewrites plato/nvim/nvim-pack-lock.json, so the same
// versions are what the next machine gets too.
//
// A terminus sheet (PlatoSheet), hanging from the tab strip like every
// other card in plato.

import QtQuick
import Quickshell
import "../../morpheus"
import "../../terminus"
import "pack.js" as Pack
import "../../terminus/terminus.js" as Terminus

PlatoSheet {
  id: panel

  required property font face

  signal closed()
  // a plugin's configuration file, to open in the editor
  signal configure(string path)

  // core/Plugins.qml — the one manager every window shares; this is a view
  // of it
  required property var plugins

  onDismissed: panel.close()
  // "installed" | "updates" | "parsers"
  property string page: "installed"
  // the file being edited, so its language comes first on the parsers page
  property string filetype: ""
  property string parserFilter: ""
  readonly property bool pbusy: panel.plugins ? panel.plugins.parserBusy : false
  readonly property string phase: panel.plugins ? panel.plugins.phase : ""
  readonly property bool busy: panel.plugins ? panel.plugins.busy : false
  readonly property var report: panel.plugins ? panel.plugins.report
    : ({ updates: [], errors: [], same: [], error: "" })
  readonly property string note: panel.plugins ? panel.plugins.note : ""
  property int sel: 0
  property var expanded: ({})
  // the name being typed for `a`, and a removal waiting for its second d
  property bool adding: false
  property string armed: ""
  property string problem: ""

  // Opening looks for updates again unless the answer is a minute old or
  // less: the indicator that brought you here may be showing one from hours
  // ago. Opened by the indicator, it opens on the updates.
  function open(page) {
    panel.shown = true;
    panel.page = page === "parsers" ? "parsers"
      : page === "updates" || (page === undefined && panel.report.updates.length > 0)
      ? "updates" : "installed";
    panel.parserFilter = "";
    field.text = "";
    if (panel.page === "parsers" && panel.plugins) panel.plugins.listParsers(panel.filetype);
    panel.sel = 0;
    panel.expanded = ({});
    panel.adding = false;
    panel.armed = "";
    panel.problem = "";
    panel.focusPage();
    if (panel.plugins && Date.now() - panel.plugins.checkedAt > 60 * 1000) panel.plugins.check();
  }
  // THE PARSERS PAGE FILTERS AS YOU TYPE: its field is always there and
  // holds the keys; its verbs move to ctrl (see parserKey). The other pages
  // keep their letters.
  readonly property bool filtering: panel.page === "parsers"
  function focusPage() {
    if (panel.filtering) field.forceActiveFocus(); else keys.forceActiveFocus();
  }
  onPageChanged: {
    if (!panel.filtering) { panel.parserFilter = ""; field.text = ""; }
    if (panel.shown) panel.focusPage();
  }
  function close() {
    panel.shown = false;
    panel.closed();
  }

  // ── the rows of the page shown ─────────────────────────────────────
  readonly property var rows: {
    const out = [];
    if (panel.page === "parsers") {
      if (!panel.plugins) return out;
      const want = panel.plugins.parserWant;
      const q = panel.parserFilter.toLowerCase();
      // typed: terminus' fuzzy score over the name, a name that starts with
      // it first; nothing typed: this file's, then built, bundled, the rest
      const score = (p) => q === "" ? 0 : Terminus.fuzzyScore(p.lang, q) + (p.lang.indexOf(q) === 0 ? 1000 : 0);
      const list = panel.plugins.parsers.filter((p) => q === "" || Terminus.fuzzyScore(p.lang, q) >= 0)
        .map((p) => ({ p: p, sc: score(p) }));
      const rank = (p) => p.lang === want ? 0 : p.installed ? 1 : p.bundled ? 2 : 3;
      list.sort((a, b) => (b.sc - a.sc) || (rank(a.p) - rank(b.p)) || (a.p.lang < b.p.lang ? -1 : 1));
      for (const e of list) out.push({ kind: "parser", x: e.p, want: e.p.lang === want });
      return out;
    }
    if (panel.page === "installed") {
      if (!panel.plugins) return out;
      const upd = {};
      for (const u of panel.report.updates) upd[u.name] = true;
      for (const p of panel.plugins.installed)
        out.push({ kind: "installed", p: p, update: upd[p.name] === true,
                   configured: panel.plugins.configured[p.name] === true });
      return out;
    }
    for (const u of panel.report.updates) {
      out.push({ kind: "plugin", u: u });
      if (panel.expanded[u.name])
        for (const c of u.commits) out.push({ kind: "commit", c: c });
    }
    for (const e of panel.report.errors) out.push({ kind: "error", e: e });
    return out;
  }
  function selPlugin() {
    for (let i = panel.sel; i >= 0; --i)
      if (panel.rows[i] && panel.rows[i].kind === "plugin") return panel.rows[i].u;
    return null;
  }
  function selParser() {
    const r = panel.rows[panel.sel];
    return r && r.kind === "parser" ? r.x : null;
  }
  function outdated() {
    return panel.plugins ? panel.plugins.parsers.filter((p) => p.installed && p.built !== p.revision)
      .map((p) => p.lang) : [];
  }
  function selInstalled() {
    const r = panel.rows[panel.sel];
    return r && r.kind === "installed" ? r.p : null;
  }
  function toggle(u) {
    const e = Object.assign({}, panel.expanded);
    e[u.name] = !e[u.name];
    panel.expanded = e;
  }
  function configureSel() {
    const p = panel.selInstalled();
    if (!p || !panel.plugins) return;
    panel.plugins.ensureConfig(p.name, () => {
      panel.configure(panel.plugins.configFile(p.name));
      panel.close();
    });
  }
  function submitAdd() {
    const text = field.text;
    const err = panel.plugins ? panel.plugins.install(text) : "";
    panel.problem = err;
    if (err !== "") return;
    panel.adding = false;
    field.text = "";
    keys.forceActiveFocus();
    // to the new one, at the end of the list
    Qt.callLater(() => { panel.sel = Math.max(0, panel.rows.length - 1); });
  }

  // ── the sheet ──────────────────────────────────────────────────────
  readonly property bool fieldShown: panel.adding || panel.filtering
  readonly property int shownRows: Math.min(14, Math.max(4, panel.rows.length + (panel.fieldShown ? 1 : 0)))
  cardW: 820
  cardH: head.height + panel.shownRows * panel.rowH + 12
  hints: panel.adding ? [["↵", "install"], ["esc", "cancel"]]
    : panel.page === "parsers"
      ? [["type", "filter"], ["↵", "build"], ["ctrl u", "rebuild old"], ["ctrl d ×2", "remove"],
         ["tab", "installed"], ["esc", panel.parserFilter !== "" ? "clear" : "close"]]
    : panel.page === "installed"
      ? [["a", "add"], ["space", "on / off"], ["c", "configure"], ["d d", "remove"],
         ["tab", "updates"], ["esc", "close"]]
      : [["↵", "update"], ["U", "all"], ["space", "commits"],
         ["r", "check"], ["tab", "installed"], ["esc", "close"]]

  // ── the head: the two pages, and what is happening ─────────────────
  Item {
    id: head
    width: parent.width
    height: 46
    Row {
      x: 10
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4
      Repeater {
        model: [{ id: "installed", label: "Installed" }, { id: "updates", label: "Updates" },
                { id: "parsers", label: "Parsers" }]
        Item {
          id: tab
          required property var modelData
          readonly property bool on: panel.page === tab.modelData.id
          width: tabText.implicitWidth + 24
          height: 30
          Rectangle {
            anchors.fill: parent
            radius: 5
            color: tab.on ? Zenon.wash(0.07) : tabHover.hovered ? Zenon.wash(0.04) : "transparent"
          }
          Text {
            id: tabText
            anchors.centerIn: parent
            font: panel.face
            color: tab.on ? Zenon.white : Zenon.muted
            text: tab.modelData.label + (tab.modelData.id === "updates" && panel.report.updates.length > 0
              ? "  " + panel.report.updates.length : "")
          }
          HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
          TapHandler {
            onTapped: {
              panel.page = tab.modelData.id; panel.sel = 0; panel.armed = "";
              if (panel.page === "parsers" && panel.plugins && panel.plugins.parsers.length === 0)
                panel.plugins.listParsers(panel.filetype);
              panel.focusPage();
            }
          }
        }
      }
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width * 0.55)
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignRight
      font: panel.face
      color: panel.page === "parsers"
        ? (panel.armed !== "" ? Zenon.yellow : panel.plugins && panel.plugins.parserPhase === "failed" ? Zenon.red : Zenon.muted)
        : panel.problem !== "" || panel.phase === "failed" ? Zenon.red
        : panel.armed !== "" ? Zenon.yellow : Zenon.muted
      text: {
        if (panel.page === "parsers") {
          if (panel.armed !== "") return "ctrl d again removes " + panel.armed;
          const pl = panel.plugins;
          if (!pl) return "";
          if (pl.parserPhase === "listing") return "listing…";
          if (pl.parserPhase === "building" || pl.parserPhase === "done" || pl.parserPhase === "failed")
            return pl.parserNote;
          const n = pl.parsers.filter((p) => p.installed).length;
          const old = panel.outdated().length;
          return (panel.parserFilter !== "" ? panel.rows.length + " of " + pl.parsers.length + "  ·  " : "")
            + n + " built" + (old > 0 ? "  ·  " + old + " behind their pin" : "")
            + (pl.parserCli ? "" : "  ·  no tree-sitter CLI");
        }
        if (panel.problem !== "") return panel.problem;
        if (panel.armed !== "") return "d again removes " + panel.armed;
        const n = panel.report.updates.length;
        switch (panel.phase) {
          case "checking": return "checking for updates…";
          case "applying": return panel.note;
          case "failed": return panel.note || panel.report.error || "failed";
          case "done": return panel.note;
          default:
            if (panel.page === "installed") {
              const c = panel.plugins ? panel.plugins.installed.length : 0;
              return c + (c === 1 ? " plugin" : " plugins");
            }
            return n === 0 ? "everything is up to date"
              : n + (n === 1 ? " plugin has" : " plugins have") + " updates";
        }
      }
    }
    Rectangle {
      anchors.bottom: parent.bottom
      x: 8
      width: parent.width - 16
      height: 1
      color: Zenon.border
    }
  }

  ListView {
    id: list
    // the shell's wheel and touchpad feel (morpheus Elastic), a few rows a notch
    ElasticScroll { view: list; step: panel.rowH * 4 }
    anchors.top: head.bottom
    anchors.topMargin: 6
    x: 0
    width: parent.width
    height: (panel.shownRows - (panel.fieldShown ? 1 : 0)) * panel.rowH
    clip: true
    model: panel.rows
    currentIndex: panel.sel
    boundsBehavior: Flickable.StopAtBounds
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
    // terminus' cursor: one bar sliding under the rows
    SelectBar { view: list; index: panel.sel; rowH: panel.rowH; on: !panel.adding }


    delegate: Item {
      id: item
      required property var modelData
      required property int index
      readonly property bool chosen: item.index === panel.sel && !panel.adding
      readonly property var r: item.modelData
      width: list.width
      height: panel.rowH


      // installed: on or off, the name, where it comes from
      Text {
        visible: item.r.kind === "installed" || item.r.kind === "parser"
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: panel.face.pixelSize
        color: (item.r.kind === "installed" && item.r.p.enabled) || (item.r.kind === "parser" && item.r.x.installed)
          ? Zenon.green : item.r.kind === "parser" && item.r.x.bundled ? Zenon.blue : Zenon.muted
        text: (item.r.kind === "installed" && item.r.p.enabled) || (item.r.kind === "parser" && (item.r.x.installed || item.r.x.bundled))
          ? "●" : "○"
      }
      Text {
        x: item.r.kind === "installed" || item.r.kind === "parser" ? 34 : item.r.kind === "commit" ? 40 : 10
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - right.implicitWidth - 30
        elide: Text.ElideRight
        textFormat: Text.PlainText
        font: panel.face
        color: item.r.kind === "error" ? Zenon.red
          : item.r.kind === "commit" ? (item.r.c.dir === "in" ? Zenon.white : Zenon.muted)
          : item.r.kind === "installed" && !item.r.p.enabled ? Zenon.muted
          : item.r.kind === "parser" && !item.r.x.installed && !item.r.x.bundled && !item.r.want ? Zenon.muted
          : Zenon.white
        text: {
          const r = item.r;
          if (r.kind === "installed") return r.p.name;
          if (r.kind === "parser") return r.x.lang;
          if (r.kind === "plugin") return (panel.expanded[r.u.name] ? "▾ " : "▸ ") + r.u.name;
          if (r.kind === "commit") return (r.c.dir === "in" ? "+ " : "− ") + r.c.msg;
          return "✗ " + r.e.name + " — " + r.e.text.split("\n")[0];
        }
      }
      Text {
        id: right
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        font: panel.face
        color: Zenon.muted
        visible: item.r.kind !== "error"
        text: {
          const r = item.r;
          if (r.kind === "parser") {
            const x = r.x, bits = [];
            if (r.want) bits.push("this file");
            if (x.installed) bits.push(x.built !== x.revision ? "behind its pin" : "built");
            else if (x.bundled) bits.push("comes with nvim");
            if (x.generate && !(panel.plugins && panel.plugins.parserCli)) bits.push("needs the tree-sitter CLI");
            if (x.requires && x.requires.length) bits.push("with " + Array.from(x.requires).join(", "));
            bits.push(String(x.revision).slice(0, 7));
            return bits.join("  ·  ");
          }
          if (r.kind === "installed")
            return (r.update ? "update  ·  " : "") + (r.configured ? "configured  ·  " : "")
              + r.p.src.replace(/^https:\/\/github\.com\//, "");
          if (r.kind === "plugin") return Pack.summary(r.u) + (r.u.branch ? "  ·  " + r.u.branch : "");
          if (r.kind === "commit") return r.c.sha;
          return "";
        }
      }
      MouseArea {
        anchors.fill: parent
        onClicked: {
          panel.sel = item.index;
          panel.armed = "";
          panel.focusPage();
          if (item.r.kind === "plugin") panel.toggle(item.r.u);
        }
        onDoubleClicked: if (item.r.kind === "installed") panel.configureSel()
      }
    }

    // an empty page says why, never a blank card
    Column {
      visible: panel.rows.length === 0 && !panel.adding
      anchors.centerIn: parent
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        font: panel.face
        color: Zenon.muted
        text: {
          if (panel.page === "installed") return "no plugins yet — a adds one";
          if (panel.page === "updates") {
            if (panel.phase === "checking") return "checking for updates…";
            if (panel.phase === "failed") return "the check failed — r tries again";
            const at = panel.plugins ? panel.plugins.checkedAt : 0;
            return "no updates — everything is up to date"
              + (at > 0 ? "  ·  checked " + Qt.formatTime(new Date(at), "hh:mm") : "");
          }
          const pl = panel.plugins;
          if (pl && pl.parserPhase === "listing") return "listing…";
          if (panel.parserFilter !== "") return "no language matches \u201C" + panel.parserFilter + "\u201D";
          return "";
        }
      }
    }
  }

  // the name of a plugin to add, typed in place under the list
  Rectangle {
    id: adder
    visible: panel.fieldShown
    anchors.top: list.bottom
    x: 8
    width: parent.width - 16
    height: panel.rowH
    radius: 4
    color: Zenon.alpha(Zenon.card, 0.98)
    border.width: 1
    border.color: panel.filtering && !field.activeFocus ? Zenon.border : Zenon.cyan
    TextInput {
      id: field
      anchors.fill: parent
      anchors.leftMargin: 12
      anchors.rightMargin: 12
      verticalAlignment: TextInput.AlignVCenter
      font: panel.face
      color: Zenon.white
      selectionColor: Qt.rgba(Zenon.magenta.r, Zenon.magenta.g, Zenon.magenta.b, 0.5)
      cursorDelegate: Caret { field: field }
      clip: true
      Keys.onPressed: (event) => {
        if (panel.filtering) { panel.parserKey(event); return; }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { panel.submitAdd(); event.accepted = true; }
        else if (event.key === Qt.Key_Escape) {
          panel.adding = false; panel.problem = ""; keys.forceActiveFocus();
          event.accepted = true;
        }
      }
      onTextChanged: {
        panel.problem = "";
        if (panel.filtering) { panel.parserFilter = field.text.trim().toLowerCase(); panel.sel = 0; }
      }
    }
    Text {
      visible: field.text === ""
      anchors.verticalCenter: parent.verticalCenter
      x: 12
      font: panel.face
      color: Zenon.muted
      text: panel.filtering ? "type to filter languages" : "owner/repo, or a git URL"
    }
  }


  // the parsers page's keys, from its filter field: what is typed filters,
  // the rest moves and acts
  function parserKey(event) {
    const k = event.key;
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
    const n = panel.rows.length;
    const x = panel.selParser();
    const wasArmed = panel.armed;
    event.accepted = true;
    if (!(ctrl && k === Qt.Key_D)) panel.armed = "";
    if (k === Qt.Key_Escape) {
      if (field.text !== "") field.text = ""; else panel.close();
    } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
      panel.page = k === Qt.Key_Backtab ? "updates" : "installed";
      panel.sel = 0;
    } else if (k === Qt.Key_Down || (ctrl && (k === Qt.Key_J || k === Qt.Key_N))) {
      panel.sel = Math.min(Math.max(0, n - 1), panel.sel + 1);
    } else if (k === Qt.Key_Up || (ctrl && (k === Qt.Key_K || k === Qt.Key_P))) {
      panel.sel = Math.max(0, panel.sel - 1);
    } else if (k === Qt.Key_PageDown) panel.sel = Math.min(Math.max(0, n - 1), panel.sel + 10);
    else if (k === Qt.Key_PageUp) panel.sel = Math.max(0, panel.sel - 10);
    else if (panel.pbusy && (k === Qt.Key_Return || k === Qt.Key_Enter || ctrl)) return;
    else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && x) panel.plugins.installParsers([x.lang]);
    else if (ctrl && k === Qt.Key_U) panel.plugins.installParsers(panel.outdated());
    else if (ctrl && k === Qt.Key_D && x && x.installed) {
      if (wasArmed === x.lang) { panel.plugins.removeParsers([x.lang]); panel.armed = ""; }
      else panel.armed = x.lang;
    }
    else if (ctrl && k === Qt.Key_R) panel.plugins.listParsers(panel.filetype);
    else event.accepted = false;
  }

  Item {
    id: keys
    focus: panel.shown
    Keys.onPressed: (event) => {
      event.accepted = true;
      const n = panel.rows.length;
      const k = event.key, t = event.text;
      const wasArmed = panel.armed;
      panel.armed = "";
      if (k === Qt.Key_Escape) { panel.close(); return; }
      if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
        const order = ["installed", "updates", "parsers"];
        const i = order.indexOf(panel.page);
        panel.page = order[(i + (k === Qt.Key_Backtab ? 2 : 1)) % 3];
        panel.sel = 0;
        if (panel.page === "parsers" && panel.plugins && panel.plugins.parsers.length === 0)
          panel.plugins.listParsers(panel.filetype);
        return;
      }
      if (k === Qt.Key_Down || t === "j") { panel.sel = Math.min(Math.max(0, n - 1), panel.sel + 1); return; }
      if (k === Qt.Key_Up || t === "k") { panel.sel = Math.max(0, panel.sel - 1); return; }
      if (t === "g") { panel.sel = 0; return; }
      if (t === "G") { panel.sel = Math.max(0, n - 1); return; }

      if (panel.filtering) { field.forceActiveFocus(); return; }

      if (panel.page === "installed") {
        const p = panel.selInstalled();
        if (t === "a" && !panel.busy) {
          panel.adding = true;
          panel.problem = "";
          field.text = "";
          field.forceActiveFocus();
        }
        else if (k === Qt.Key_Space && p) panel.plugins.setEnabled(p.name, !p.enabled);
        else if ((t === "c" || k === Qt.Key_Return || k === Qt.Key_Enter) && p) panel.configureSel();
        else if (t === "d" && p && !panel.busy) {
          if (wasArmed === p.name) panel.plugins.remove(p.name);
          else panel.armed = p.name;
        }
        else if (t === "r" && panel.plugins) panel.plugins.check();
        else event.accepted = false;
        return;
      }

      if (k === Qt.Key_Space || k === Qt.Key_Right || t === "l") {
        const u = panel.selPlugin();
        if (u) panel.toggle(u);
      }
      else if (panel.busy) return;
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || t === "u") {
        const u = panel.selPlugin();
        if (u) panel.plugins.apply([u.name]);
      }
      else if (t === "U") panel.plugins.apply(panel.report.updates.map((u) => u.name));
      else if (t === "r") panel.plugins.check();
      else event.accepted = false;
    }
  }
}
