// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE AUR, NOT ONE PACKAGE OF IT (user, 2026-10-28: "make delphi the best
// git/aur powerhouse it can be"), as "Account" under the AUR heading: the
// account is the one your AUR SSH key signs in as, so there is only ever
// one. Three things a packager comes here for:
//
//   Yours    the packages your AUR account keeps (its own list-repos, over
//            SSH: asked the first time it is shown, so a key's passphrase
//            card comes when you ask, not when the page opens); each one
//            opened here, or cloned. Each is checked against its source
//            (2026-10-28): a newer version tag there says so, and opening
//            the package starts its Release at that version
//   Search   the AUR, by name and description; a package opened, cloned,
//            voted for, or read on the web
//   New      a package from a repository (core/aurnew.py): Delphi reads the
//            source — its build system, version, license, description and
//            what it depends on — you correct what it got wrong, and the
//            recipe is made in a new repository with its AUR remote. The
//            package's own page then takes it: checksums, a build, namcap,
//            the first push.
//
//   n new package   / search   y yours   return open or clone
//   v vote          o the AUR's page

import QtQuick
import "../morpheus"
import "../terminus"
import "delphi.js" as D

Item {
  id: pg
  property var win: null
  readonly property var edgeViews: [list]

  readonly property string title: "AUR account"
  readonly property string subtitle: pg.tab === "yours"
    ? (pg.mine === null ? "The packages your AUR account keeps" : pg.mine.length + (pg.mine.length === 1 ? " package" : " packages") + " kept by you"
       + (pg.newerCount > 0 ? "  ·  " + pg.newerCount + " to update" : ""))
    : pg.searched === "" ? "Search the AUR" : pg.found.length + " for “" + pg.searched + "”"
  readonly property var hints: [["n", "new package"], ["/", "search"], ["y", "yours"], ["return", "open"], ["v", "vote"], ["o", "on the web"]]
  readonly property var buttons: [
    { label: pg.mine === null ? "Ask the AUR" : "Check again", visible: pg.tab === "yours", run: () => pg.mine === null ? pg.loadMine() : pg.checkUpstream() },
    { label: "New package…", ink: Zenon.cyan, primary: true, run: () => pg.newPackage() },
  ]
  function takeFocus() { if (pg.tab === "search" && pg.searched === "") pg.claimField(); else if (pg.win) pg.win.focusKeys(); }

  property string tab: "yours"
  property var mine: null           // [name] — null until asked
  property var found: []
  property string searched: ""
  property bool asking: false
  property int sel: 0
  // what the AUR and each source say of yours: name → { version, upstream, newer, outOfDate, votes }
  property var checked: ({})
  readonly property int newerCount: (pg.mine || []).filter((n) => pg.checked[n] && pg.checked[n].newer).length
  readonly property var rows: pg.tab === "yours"
    ? (pg.mine || []).map((n) => Object.assign({ name: n }, pg.checked[n] || {}))
        .sort((a, b) => (b.newer ? 1 : 0) - (a.newer ? 1 : 0) || (b.outOfDate ? 1 : 0) - (a.outOfDate ? 1 : 0) || a.name.localeCompare(b.name))
    : pg.found
  readonly property var row: pg.sel >= 0 && pg.sel < pg.rows.length ? pg.rows[pg.sel] : null

  function loadMine() {
    pg.asking = true;
    pg.win.act("aurSsh", { cmd: "list-repos", args: [] }, { repo: null, label: "Asking the AUR", network: true, refresh: false,
      then: (res) => { pg.mine = res.lines.map((l) => l.trim()).filter((l) => /^[a-z0-9@._+-]+$/.test(l)).sort(); pg.sel = 0; pg.checkUpstream(); },
      done: () => { pg.asking = false; } });
  }
  // the AUR's version of each against the newest version tag on its source
  function checkUpstream() {
    if (!pg.mine || pg.mine.length === 0) return;
    pg.win.act("aurOutdated", { names: pg.mine }, { repo: null, label: "Checking the sources", network: true, refresh: false,
      then: (res) => {
        const m = {};
        for (const r of res) m[r.base || r.name] = r;
        pg.checked = m;
        if (pg.newerCount > 0) pg.win.say(pg.newerCount + (pg.newerCount === 1 ? " package has" : " packages have") + " a newer version upstream");
      } });
  }
  function search(text) {
    const t = String(text || "").trim();
    if (t.length < 2) { pg.win.say("Two letters at least", true); return; }
    pg.asking = true;
    pg.win.mgr.call("aurSearch", null, { text: t }, (ok, res, err) => {
      if (!pg) return;
      pg.asking = false;
      if (!ok) { pg.win.fail("The search did not work", null, err); return; }
      pg.searched = t;
      pg.found = res;
      pg.sel = 0;
      pg.win.focusKeys();
    });
  }
  function moveTo(i) {
    if (pg.rows.length === 0) return;
    pg.sel = Math.max(0, Math.min(pg.rows.length - 1, i));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
  }
  function base(r) { return r.base || r.name; }

  // OPEN: its clone here, or a card — clone it, read it on the web
  function open(r) {
    if (!r) return;
    const roots = pg.win.mgr.recents.map((x) => x.root);
    pg.win.mgr.call("whereCloned", null, { host: "aur.archlinux.org", full: pg.base(r), roots: roots }, (ok, res) => {
      if (!pg) return;
      if (ok && res.root) {
        // newer upstream: the package page releases that version as it opens
        if (r.newer && r.upstream) pg.win.mgr.aurWant = { root: res.root, version: r.upstream };
        pg.win.openRepo(res.root);
        pg.win.setPage("aur");
        return;
      }
      pg.win.card_({ question: r.name, glyph: "", ink: Zenon.ink,
        detail: (r.description ? r.description + "  ·  " : "") + (r.version ? r.version + "  ·  " : "") + "Not cloned here yet.",
        choices: [{ label: "Clone", ink: Zenon.cyan, run: () => pg.clone(r) },
                  { label: "On the web", run: () => pg.web(r) },
                  { label: "Cancel" }] });
    });
  }
  // over SSH when it is yours (a push needs it), else read-only https
  function clone(r) {
    const name = pg.base(r);
    const mineToo = (pg.mine || []).indexOf(name) >= 0;
    pg.win.ask({ title: "Clone " + name, glyph: "",
      detail: mineToo ? "Over SSH: it is yours, so pushes go back to the AUR."
        : "Read it before you build it: a PKGBUILD runs as you. Over https — to push to it you would need to be its maintainer.",
      fields: [{ key: "into", label: "Into the directory", value: pg.win.home + "/aur/", path: true }],
      verb: "Clone",
      then: (v) => {
        const dest = v.into.trim().replace(/\/$/, "") + "/" + name;
        const url = mineToo ? "ssh://aur@aur.archlinux.org/" + name + ".git" : "https://aur.archlinux.org/" + name + ".git";
        pg.win.act("clone", { url: url, dest: dest }, { repo: null, label: "Cloning " + name, network: true, refresh: false,
          said: "Cloned into " + D.tilde(dest, pg.win.home), then: () => { pg.win.openRepo(dest); pg.win.setPage("aur"); } });
      } });
  }
  function web(r) { if (r) Strings.openLink("https://aur.archlinux.org/packages/" + r.name); }
  function vote(r) {
    if (!r) return;
    pg.win.act("aurSsh", { cmd: "vote", args: [pg.base(r)] }, { repo: null, label: "Voting", network: true, refresh: false,
      said: "Voted for " + pg.base(r) });
  }

  // ── A NEW PACKAGE, FROM A REPOSITORY ───────────────────────────────────
  // 1 which repository (this one, when it is not a recipe already);
  // 2 what Delphi read from it, to correct; 3 names checked, then made
  function newPackage() {
    const roots = pg.win.mgr.recents.map((r) => r.root).filter((r) => r !== "");
    const first = pg.win.root !== "" && !pg.win.aur ? pg.win.root : (roots[0] || "");
    pg.win.ask({ title: "A new AUR package", glyph: "",
      detail: "From a repository's source: its build files are read, never run, for what the package needs. Nothing is published until you push it.",
      fields: [{ key: "path", label: "The source", value: first, path: true }],
      verb: "Read it", hold: true, busyText: "Reading…",
      then: (v, finish) => {
        const path = v.path.trim();
        pg.win.mgr.call("aurScan", null, { path: path }, (ok, sc, err) => {
          if (!pg) return;
          if (!ok) { finish(err && err.error ? err.error : "It could not be read"); return; }
          finish(true);
          pg.draft(sc);
        });
      } });
  }
  function list_(xs) { return (xs || []).join(" "); }
  function words(s) { return String(s || "").split(/[\s,]+/).map((x) => x.trim()).filter((x) => x !== ""); }
  function draft(sc) {
    const kinds = sc.kinds.map((k) => [k, k === "git" ? "-git: the latest commit" : "A release: " + (sc.version || "its version")]);
    pg.win.ask({ title: "The package", glyph: "",
      detail: (sc.notes.length ? sc.notes.join("\n") + "\n" : "") + "Built with " + sc.systems.join(", ")
        + ". Dependencies are Arch's package names, space-separated; each is looked up before the recipe is made.",
      fields: [
        { key: "kind", label: "Kind", options: kinds },
        { key: "name", label: "Name", value: sc.name },
        { key: "version", label: "Version", value: sc.version, optional: true },
        { key: "description", label: "Description", value: sc.description },
        { key: "source", label: "Source", value: sc.source || sc.url, hint: "https://…" },
        { key: "url", label: "Home page", value: sc.url, optional: true },
        { key: "license", label: "License (SPDX)", value: sc.license, hint: "MIT" },
        { key: "system", label: "Built with", options: [sc.systems[0]].concat(["cargo", "python", "npm", "go", "meson", "cmake", "autotools", "make", "copy"]
            .filter((x) => x !== sc.systems[0])).map((x) => [x, x]) },
        { key: "depends", label: "Depends on", value: pg.list_(sc.depends), optional: true },
        { key: "makedepends", label: "Built with (makedepends)", value: pg.list_(sc.makedepends), optional: true },
        { key: "dest", label: "The recipe's directory", value: pg.win.home + "/aur/" + sc.name, path: true }
      ],
      verb: "Make it", hold: true, busyText: "Checking the names…",
      then: (v, finish) => {
        const kind = v.kind;
        const name = v.name.trim() + (kind === "git" && !/-git$/.test(v.name.trim()) ? "-git" : "");
        const spec = { kind: kind, name: name, version: v.version.trim(), description: v.description.trim(),
                       source: v.source.trim(), url: v.url.trim() || v.source.trim(), license: v.license.trim(),
                       system: v.system, binary: sc.binary, tag: sc.tag, arch: sc.arch,
                       depends: pg.words(v.depends), makedepends: pg.words(v.makedepends), optdepends: sc.optdepends };
        pg.win.mgr.call("aurAvailable", null, { name: name }, (ok, free, err) => {
          if (!pg) return;
          if (!ok) { finish(err && err.error ? err.error : "The AUR did not answer"); return; }
          if (!free.free) { finish(free.why); return; }
          pg.win.mgr.call("aurResolve", null, { names: spec.depends.concat(spec.makedepends) }, (ok2, where) => {
            if (!pg) return;
            const none = ok2 ? where.filter((w) => w.where === "none").map((w) => w.name) : [];
            if (none.length) { finish("Not a package anywhere: " + none.join(", ") + " — correct or remove them"); return; }
            const aurDeps = ok2 ? where.filter((w) => w.where === "aur").map((w) => w.name) : [];
            pg.win.mgr.call("aurCreate", null, { spec: spec, dest: v.dest.trim() }, (ok3, made, err3) => {
              if (!pg) return;
              if (!ok3) { finish(err3 && err3.error ? err3.error : "It was not made"); return; }
              finish(true);
              pg.win.openRepo(made.root);
              pg.win.setPage("aur");
              pg.win.say(aurDeps.length ? "Made — " + aurDeps.join(", ") + " come from the AUR too. Release (r) next"
                                        : "Made — Release (r) fetches its checksums and builds it");
            });
          });
        });
      } });
  }

  function key(e) {
    const k = e.key;
    if (e.modifiers & Qt.ControlModifier) return false;
    if (k === Qt.Key_N) { pg.newPackage(); return true; }
    if (k === Qt.Key_Slash) { pg.tab = "search"; Qt.callLater(pg.claimField); return true; }
    if (k === Qt.Key_Y) { pg.tab = "yours"; if (pg.mine === null && !pg.asking) pg.loadMine(); return true; }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(pg.sel + 1); return true; }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { pg.open(pg.row); return true; }
    if (k === Qt.Key_V) { pg.vote(pg.row); return true; }
    if (k === Qt.Key_O) { pg.web(pg.row); return true; }
    return false;
  }

  // ── IN THE WINDOW'S TOP BAR, at its right end (user, 2026-10-28) ────
  // the search first, then which list; the window draws it (headTools)
  property var field: null
  function claimField() { if (pg.field) pg.field.claim(); }
  property Component headTools: Component {
    Row {
      spacing: 10
      BulkField {
        id: fieldIn
        visible: pg.tab === "search"
        anchors.verticalCenter: parent.verticalCenter
        width: 240
        height: Math.round(Zenon.px(14) * 2.3)
        ghost: "Search the AUR"
        clearable: true
        onAccepted: pg.search(fieldIn.text)
        Component.onCompleted: pg.field = fieldIn
        Component.onDestruction: if (pg && pg.field === fieldIn) pg.field = null
      }
      Segments {
        anchors.verticalCenter: parent.verticalCenter
        options: [["yours", "Yours"], ["search", "Search"]]
        current: pg.tab
        onChose: (v) => { pg.tab = v; pg.sel = 0; if (v === "search") Qt.callLater(pg.claimField); else pg.win.focusKeys(); }
      }
    }
  }

  ListView {
    id: list
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: 8
    anchors.bottom: parent.bottom
    clip: true
    bottomMargin: 8
    boundsBehavior: Flickable.StopAtBounds
    model: pg.rows
    readonly property int rowH: Math.round(Zenon.px(15) * 3.2)
    SelectBar { view: list; host: pg.win; index: pg.sel; rowH: list.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
    delegate: Item {
      id: arow
      required property var modelData
      required property int index
      width: list.width
      height: list.rowH
      Column {
        x: 22
        width: parent.width - 44 - side.width
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
          textFormat: Text.PlainText
          width: parent.width
          elide: Text.ElideRight
          text: arow.modelData.name + (arow.modelData.version ? "  " + arow.modelData.version : "")
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(14)
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: text !== ""
          elide: Text.ElideRight
          text: arow.modelData.description || ""
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      Text {
        id: side
        anchors.right: parent.right
        anchors.rightMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        readonly property bool yours: pg.tab === "yours"
        visible: text !== ""
        text: side.yours
          ? (arow.modelData.newer ? arow.modelData.version + "  →  " + arow.modelData.upstream + " upstream"
             : arow.modelData.outOfDate ? arow.modelData.version + " · flagged out of date"
             : arow.modelData.version ? arow.modelData.version + (arow.modelData.upstream ? " · up to date" : "") : "")
          : !arow.modelData.maintainer ? "orphaned · " + arow.modelData.votes + " votes"
          : arow.modelData.maintainer + " · " + arow.modelData.votes + " votes" + (arow.modelData.outOfDate ? " · out of date" : "")
        color: side.yours ? (arow.modelData.newer || arow.modelData.outOfDate ? Zenon.yellow : Zenon.accentMuted)
          : !arow.modelData.maintainer || arow.modelData.outOfDate ? Zenon.yellow : Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
      MouseArea {
        anchors.fill: parent
        onClicked: { pg.sel = arow.index; pg.win.focusKeys(); }
        onDoubleClicked: pg.open(arow.modelData)
      }
    }
  }
  ElasticScroll { anchors.fill: list; view: list }
  Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }

  EmptyState {
    anchors.centerIn: list
    width: 460
    visible: pg.rows.length === 0
    text: pg.tab === "yours"
      ? (pg.asking ? "Asking the AUR…" : pg.mine === null ? "Ask the AUR (y) for the packages your account keeps — over SSH, with your AUR key."
         : "Your account keeps no packages yet. New package (n) makes one from a repository.")
      : pg.asking ? "Searching…" : pg.searched === "" ? "Search by name or description, then return." : "Nothing on the AUR for that"
  }
}
