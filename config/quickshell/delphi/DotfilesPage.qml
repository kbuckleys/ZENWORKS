// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// DOTFILES — this repository's GNU Stow packages: each top-level directory
// laid out like your home (kitty/.config/kitty/kitty.conf goes to
// ~/.config/kitty/kitty.conf). For each, what stow would do — link, nothing
// (it is linked), or refuse over files of yours in the way — read from
// stow's own dry run, which changes nothing; one package file by file, in the
// tree terminus and plato use; and the command that does it, to copy.
//
// STOW IS NEVER RUN FROM HERE (user, 2026-10-10: stowing is theirs, by
// hand, as a series of tests). What this page writes is the one thing that
// is safe to: a config COPIED into a package (a), the original left exactly
// where and as it is — then Changes has it to commit.
//
//   ↑↓ packages · a copy into a package · c copy the command · t where they
//   go · return show the package in terminus

import QtQuick
import "../morpheus"
import "../terminus"
import "delphi.js" as D

Item {
  id: pg
  property var win: null
  readonly property var edgeViews: [list]

  readonly property string title: "Dotfiles"
  readonly property string subtitle: !pg.info ? "Asking stow…"
    : !pg.info.stow ? "stow is not installed"
    : pg.info.noTarget ? D.tilde(pg.target, pg.win.home) + " is not there"
    : pg.pkgs.length + (pg.pkgs.length === 1 ? " package" : " packages") + "  ·  into " + D.tilde(pg.target, pg.win.home)
      + (pg.info.stowrc ? "  ·  .stowrc" : "")
  readonly property var hints: [["↑↓", "packages"], ["a", "copy into a package"], ["c", "copy the command"],
                                ["t", "where they go"], ["return", "terminus"]]
  readonly property var buttons: [
    { label: "Where they go", run: () => pg.chooseTarget() },
    { label: "Copy into a package", ink: Zenon.cyan, primary: true, visible: !!pg.info && !!pg.info.stow, run: () => pg.copyIn() },
  ]
  function takeFocus() { if (pg.win) pg.win.focusKeys(); }

  // ── WHAT STOW SAYS ─────────────────────────────────────────────────────
  property var info: null
  readonly property var pkgs: pg.info && pg.info.packages ? pg.info.packages : []
  property int sel: 0
  readonly property var pkg: pg.sel >= 0 && pg.sel < pg.pkgs.length ? pg.pkgs[pg.sel] : null
  // where the packages go: chosen here for this repository, else what the
  // backend found (.stowrc, or home)
  readonly property string chosenTarget: pg.win && pg.win.mgr && pg.win.root !== "" ? pg.win.mgr.stowTargets[pg.win.root] || "" : ""
  readonly property string target: pg.info ? pg.info.target : pg.chosenTarget
  property bool loading: false
  function reload() {
    if (!pg.win || pg.win.root === "") return;
    const root = pg.win.root, want = pg.pkg ? pg.pkg.name : "";
    pg.loading = true;
    pg.win.mgr.call("stowPackages", root, pg.chosenTarget !== "" ? { target: pg.chosenTarget } : {}, (ok, res, err) => { if (!pg) return;
      pg.loading = false;
      if (root !== pg.win.root) return;
      if (!ok) { pg.win.fail("Could not read the packages", null, err); return; }
      pg.info = res;
      const i = res.packages.findIndex((p) => p.name === want);
      pg.sel = i >= 0 ? i : Math.max(0, Math.min(pg.sel, res.packages.length - 1));
      pg.loadPlan();
    });
  }
  property var plan: null
  function loadPlan() {
    const p = pg.pkg;
    if (!p || p.state === "empty" || !pg.info || !pg.info.stow) { pg.plan = null; return; }
    const name = p.name, root = pg.win.root;
    pg.win.mgr.call("stowPlan", root, { name: name, target: pg.target }, (ok, res) => { if (!pg) return;
      if (ok && pg.pkg && pg.pkg.name === name) pg.plan = res;
    });
  }
  Component.onCompleted: Qt.callLater(pg.reload)
  Connections {
    target: pg.win
    function onRepoEpochChanged() { pg.info = null; pg.plan = null; pg.reload(); }
  }
  // a commit, a checkout, a copy in: the files may have moved
  Connections {
    target: pg.win ? pg.win.mgr : null
    function onChanged(root, what) { if (pg.win && root === pg.win.root && what.indexOf("tree") >= 0) reloadWait.restart(); }
  }
  Timer { id: reloadWait; interval: 600; onTriggered: pg.reload() }

  function moveTo(i) {
    if (pg.pkgs.length === 0) return;
    pg.sel = Math.max(0, Math.min(pg.pkgs.length - 1, i));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
    pg.plan = null;
    planWait.restart();
  }
  Timer { id: planWait; interval: 120; onTriggered: pg.loadPlan() }

  // ── WHAT EACH STATE IS CALLED ──────────────────────────────────────────
  function stateWord(p) {
    if (!p) return "";
    if (p.state === "linked") return "linked";
    if (p.state === "tolink") return p.links.length === 1 ? "1 link to make" : p.links.length + " links to make";
    if (p.state === "conflicts") return p.conflicts.length === 1 ? "1 file in the way" : p.conflicts.length + " files in the way";
    if (p.state === "empty") return "empty";
    if (p.state === "error") return p.error || "stow said no";
    return "";
  }
  function stateInk(p) {
    if (!p) return Zenon.accentMuted;
    return p.state === "linked" ? Zenon.green : p.state === "tolink" ? Zenon.cyan
      : p.state === "conflicts" || p.state === "error" ? Zenon.red : Zenon.accentMuted;
  }
  function cmd(how) { return pg.pkg ? D.stowCommand(pg.win.root, pg.target, pg.pkg.name, how, pg.win.home) : ""; }
  // the command for the package as it stands: link it, or undo the links
  readonly property string mainHow: pg.pkg && pg.pkg.state === "linked" ? "unstow" : "stow"

  // ── WHAT CAN BE DONE HERE ──────────────────────────────────────────────
  function chooseTarget() {
    const fm = pg.win.mgr.fileManager;
    if (!fm) return;
    fm.choose(true, pg.target || pg.win.home, (paths) => {
      if (!pg || !paths || paths.length === 0) return;
      // home is what it would be anyway: kept as no choice at all
      pg.win.mgr.setStowTarget(pg.win.root, paths[0] === pg.win.home && !(pg.info && pg.info.stowrc) ? "" : paths[0]);
      pg.info = null;
      pg.reload();
    });
  }
  // A file or directory from where the packages go, copied into a package
  // at the same place under it. The original stays as it is: linking it
  // is the stow command's, run by hand.
  function copyIn() {
    const fm = pg.win.mgr.fileManager;
    if (!fm || !pg.info) return;
    const t = pg.target, cfg = t + "/.config";
    fm.choose(false, cfg, (paths) => {
      if (!pg || !paths || paths.length === 0) return;
      const outside = paths.filter((p) => p.indexOf(t + "/") !== 0);
      if (outside.length > 0) { pg.win.say("Only from inside " + D.tilde(t, pg.win.home) + ", where the packages go", true); return; }
      const first = D.baseName(paths[0]).replace(/^\.+/, "") || "dotfiles";
      pg.win.ask({ title: paths.length === 1 ? "Copy " + D.baseName(paths[0]) + " into a package" : "Copy " + paths.length + " into a package",
        glyph: "", ink: Zenon.cyan,
        detail: "Copied to the same place inside the package, so stow can link it back. Your "
          + (paths.length === 1 ? "original stays" : "originals stay") + " where " + (paths.length === 1 ? "it is" : "they are")
          + " — move " + (paths.length === 1 ? "it" : "them") + " aside and run the stow command, or use its --adopt form, when you are ready.",
        items: paths.map((p) => D.tilde(p, pg.win.home)),
        fields: [{ key: "package", label: "Package", value: pg.pkg && pg.pkg.state !== "empty" && paths.length > 1 ? pg.pkg.name : first, hint: "kitty" }],
        verb: "Copy",
        then: (v) => pg.copyEach(paths.slice(), v.package.trim(), 0) });
    }, "", false, true);
  }
  function copyEach(paths, name, n) {
    if (paths.length === 0) {
      pg.win.say(n === 0 ? "Already in " + name + " — nothing to copy" : "Copied " + n + (n === 1 ? " file" : " files") + " into " + name);
      pg.reload();
      return;
    }
    const p = paths.shift();
    pg.win.act("stowCopyIn", { src: p, "package": name, target: pg.target }, {
      label: "Copying " + D.baseName(p) + " into " + name,
      then: (res) => pg.copyEach(paths, name, n + res.copied),
      failed: (err) => { pg.win.fail("Could not copy " + D.baseName(p), null, err); pg.reload(); } });
  }

  function key(e) {
    const k = e.key;
    if (e.modifiers & Qt.ControlModifier) return false;
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(pg.sel + 1); return true; }
    if (k === Qt.Key_A) { pg.copyIn(); return true; }
    if (k === Qt.Key_T) { pg.chooseTarget(); return true; }
    if (!pg.pkg) return false;
    if (k === Qt.Key_C) { pg.win.copy(pg.cmd(pg.mainHow), "the stow command"); return true; }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { pg.win.reveal(pg.win.root + "/" + pg.pkg.name); return true; }
    return false;
  }

  // ── the packages ───────────────────────────────────────────────────────
  Item {
    id: left
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: pg.win && pg.win.splits.dotfiles ? pg.win.splits.dotfiles : Math.round(Math.min(420, pg.width * 0.36))

    ListView {
      id: list
      anchors.fill: parent
      clip: true
      topMargin: 10
      bottomMargin: 10
      boundsBehavior: Flickable.StopAtBounds
      model: pg.pkgs
      readonly property int rowH: Math.round(Zenon.px(15) * 3.4)
      SelectBar { view: list; host: pg.win; index: pg.sel; on: pg.pkgs.length > 0; rowH: list.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
      delegate: Item {
        id: prow
        required property var modelData
        required property int index
        readonly property var p: prow.modelData
        width: list.width
        height: list.rowH
        Text {
          id: pgl
          x: 24
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: pg.stateInk(prow.p)
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(19)
        }
        Column {
          anchors.left: pgl.right
          anchors.leftMargin: 14
          anchors.right: parent.right
          anchors.rightMargin: 24
          anchors.verticalCenter: parent.verticalCenter
          spacing: 3
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: prow.p.name
            color: prow.index === pg.sel ? Zenon.ink : Zenon.accentSoft
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(16)
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            // a directory with nothing dotted at its top is not laid out
            // like a home: said, as its state may not mean what it seems
            text: "<font color='" + pg.stateInk(prow.p) + "'>" + pg.stateWord(prow.p) + "</font>"
              + "  ·  " + prow.p.files + (prow.p.files === 1 ? " file" : " files")
              + (prow.p.dotted || prow.p.state === "empty" ? "" : "  ·  not laid out like a home")
            textFormat: Text.StyledText
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.features: { "tnum": 1 }
            font.pixelSize: Zenon.px(13)
          }
        }
        MouseArea {
          anchors.fill: parent
          onClicked: { pg.moveTo(prow.index); pg.win.focusKeys(); }
          onDoubleClicked: pg.win.reveal(pg.win.root + "/" + prow.p.name)
        }
      }
    }
    ElasticScroll { anchors.fill: list; view: list }
    Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }
    Working {
      anchors.centerIn: list
      z: 5
      running: pg.loading && !pg.info
      visible: running
    }
    // nothing to show: stow missing, or no packages
    Column {
      anchors.centerIn: parent
      width: parent.width - 48
      spacing: 14
      visible: !!pg.info && (!pg.info.stow || pg.pkgs.length === 0)
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: pg.info && !pg.info.stow
          ? "Reading what your packages would do takes GNU Stow"
          : "No packages here. A package is a directory laid out like your home — kitty/.config/kitty/kitty.conf — and Copy into a package makes one."
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
      DialogButton {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !!pg.info && !pg.info.stow
        label: pg.win && pg.win.mgr.installing && pg.win.mgr.installing.pkg === "stow" ? "Installing…" : "Install stow"
        ink: Zenon.cyan
        primary: true
        onClicked: pg.win.mgr.installTool("stow", "to read what your dotfiles would link", (ok) => { if (ok && pg) pg.reload(); })
      }
    }
  }

  // ── one package, file by file, and its command ─────────────────────────
  Item {
    id: right
    anchors.left: left.right
    anchors.leftMargin: 1
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    visible: !!pg.pkg && !!pg.info && pg.info.stow

    Text {
      id: planHead
      x: 20
      y: 16
      width: parent.width - 40
      elide: Text.ElideRight
      text: pg.pkg ? "<b>" + pg.pkg.name + "</b>   <font color='" + pg.stateInk(pg.pkg) + "'>" + pg.stateWord(pg.pkg) + "</font>" : ""
      textFormat: Text.StyledText
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(16)
    }
    Text {
      id: planWhy
      anchors.left: planHead.left
      anchors.right: planHead.right
      anchors.top: planHead.bottom
      anchors.topMargin: 6
      wrapMode: Text.Wrap
      text: !pg.pkg ? ""
        : pg.pkg.state === "linked" ? "Every file is a link into this repository: edit them where they are, and commit here."
        : pg.pkg.state === "conflicts" ? "Files of yours are where its links would go. Move them aside and stow — or stow with --adopt, which takes your files into the package first (then Changes shows how they differ from what was committed)."
        : pg.pkg.state === "tolink" ? "Stow would link these into " + D.tilde(pg.target, pg.win.home) + ". Nothing of yours is in the way."
        : pg.pkg.state === "empty" ? "Nothing in it yet."
        : ""
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }

    Rectangle {
      id: treeWell
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: planWhy.bottom
      anchors.bottom: cmdBox.top
      anchors.margins: 16
      radius: Zenon.windowRadius
      color: Zenon.wash(0.03)
      border.width: 1
      border.color: Zenon.border
      FileTree {
        anchors.fill: parent
        anchors.margins: 6
        window: pg.win
        rootPath: D.tilde(pg.target, pg.win ? pg.win.home : "")
        given: pg.plan ? pg.plan.files.map((f) => ({ path: f.path, state: f.state })) : []
        fontSize: Zenon.px(14)
        noteWidth: 110
        noteOf: (e) => e.isDir ? null
          : e.state === "linked" ? { text: "linked", ink: Zenon.green }
          : e.state === "inTheWay" ? { text: "in the way", ink: Zenon.red }
          : { text: "to link", ink: Zenon.cyan }
      }
    }

    // the command, to run by hand
    Rectangle {
      id: cmdBox
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 16
      height: cmdCol.implicitHeight + 24
      radius: Zenon.windowRadius
      color: Zenon.wash(0.05)
      border.width: 1
      border.color: Zenon.border
      Column {
        id: cmdCol
        x: 14
        y: 12
        width: parent.width - 28
        spacing: 10
        Repeater {
          model: !pg.pkg || pg.pkg.state === "empty" ? []
            : pg.pkg.state === "conflicts" ? [["stow", "Once those are moved aside"], ["adopt", "Or take them into the package, then link"]]
            : pg.pkg.state === "linked" ? [["unstow", "To remove its links (the files stay in the repository)"]]
            : [["stow", "To link it — run it yourself"]]
          delegate: Item {
            id: crow
            required property var modelData
            width: cmdCol.width
            height: cwhy.height + 6 + cline.height
            Text {
              id: cwhy
              width: parent.width
              text: crow.modelData[1]
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
            Text {
              id: cline
              anchors.top: cwhy.bottom
              anchors.topMargin: 6
              anchors.left: parent.left
              anchors.right: copyBtn.left
              anchors.rightMargin: 12
              wrapMode: Text.WrapAnywhere
              text: pg.cmd(crow.modelData[0])
              color: crow.modelData[0] === "adopt" ? Zenon.yellow : Zenon.ink
              font.family: Zenon.faceCode
              font.pixelSize: Zenon.px(14)
            }
            DialogButton {
              id: copyBtn
              anchors.right: parent.right
              anchors.verticalCenter: cline.verticalCenter
              label: "Copy"
              onClicked: pg.win.copy(pg.cmd(crow.modelData[0]), "the stow command")
            }
          }
        }
      }
    }
  }

  SeamGrip {
    frame: pg
    at: left.width
    min: 260
    max: pg.width - 380
    onMoved: (p) => pg.win.setSplit("dotfiles", p)
    onReset: pg.win.setSplit("dotfiles", 0)
  }
}
