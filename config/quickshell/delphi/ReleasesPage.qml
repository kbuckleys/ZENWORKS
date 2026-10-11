// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// RELEASES — the forge repository's (GitHub, GitLab, Codeberg, or a server
// of your own): each tag with its title, its notes and the files attached,
// newest first; and a new one made (user, 2026-10-11: "access the releases
// in github and submit my own").
//
// A new release: its tag (the last one counted up), the branch it is made
// from, then its title and notes — the notes written for you: GitHub's own
// "Generate release notes" from the pull requests merged since the last
// release, elsewhere a changelog of the commits since the last tag. Either
// is only a start, there to edit. Draft and pre-release where the forge
// has them. The tag is made by the forge, on what it already has: a branch
// with commits not pushed is said so first.
//
//   ↑↓ releases · n new · w on the web · r refresh

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "delphi.js" as D
import "../terminus/terminus.js" as Terminus

Item {
  id: pg
  property var win: null
  readonly property var edgeViews: [list, body]
  readonly property var footViews: [list, body]

  readonly property var hub: pg.win ? pg.win.hub : null
  readonly property string hubFull: pg.hub ? pg.hub.full : ""
  readonly property var site: D.FORGES[pg.hub ? pg.hub.forge : "github"] || D.FORGES.github
  function op(name) { return (D.FORGES[pg.hub ? pg.hub.forge : "github"] || D.FORGES.github).id + name; }
  // GitLab (gitlab.com or a server of your own) has no drafts or pre-releases
  readonly property bool drafts: !!pg.hub && !/^gitlab/.test(pg.hub.forge)

  readonly property string title: "Releases"
  readonly property string subtitle: !pg.hub ? "Not on GitHub, GitLab or Codeberg"
    : pg.loading ? pg.hubFull + "  ·  asking " + pg.site.name + "…"
    : pg.hubFull + "  ·  " + (pg.rels.length === 0 ? "none yet" : pg.rels.length + (pg.rels.length === 1 ? " release" : " releases"))
  readonly property var hints: [["↑↓", "releases"], ["n", "new"], ["w", "web"], ["r", "refresh"]]
  readonly property var buttons: [
    { label: "On the web", visible: !!pg.rel, run: () => pg.web() },
    { label: "New release", ink: Zenon.cyan, primary: true, visible: !!pg.hub, run: () => pg.create() },
  ]
  function takeFocus() { if (pg.win) pg.win.focusKeys(); }

  property var rels: []
  property bool loading: false
  property string listError: ""
  property int sel: 0
  readonly property var rel: pg.sel >= 0 && pg.sel < pg.rels.length ? pg.rels[pg.sel] : null
  function reload() {
    if (!pg || !pg.win || !pg.hub) return;
    const asked = pg.hubFull;
    pg.loading = true;
    pg.win.mgr.call(pg.op("Releases"), null, { full: asked }, (ok, res, err) => { if (!pg || asked !== pg.hubFull) return;
      pg.loading = false;
      pg.listError = ok ? "" : D.errorText(err ? err.error : "");
      pg.rels = ok ? res : [];
      pg.sel = Math.max(0, Math.min(pg.sel, pg.rels.length - 1));
    });
  }
  Component.onCompleted: Qt.callLater(pg.reload)
  onHubFullChanged: { pg.rels = []; pg.reload(); }
  function web() { if (pg.rel && pg.rel.url) Quickshell.execDetached(["xdg-open", pg.rel.url]); }
  function moveTo(i) {
    if (pg.rels.length === 0) return;
    pg.sel = Math.max(0, Math.min(pg.rels.length - 1, i));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
  }

  // ── A NEW ONE ──────────────────────────────────────────────────────────
  function create() {
    if (!pg.hub) return;
    const b = pg.win.branch;
    const here = b && b.head ? b.head : "";
    pg.win.mgr.call("lastTag", pg.win.root, {}, (ok, last) => { if (!pg) return;
      const prev = ok ? last : "";
      const branches = pg.win.refs.local.map((l) => l.name);
      const unpushed = b && b.ahead > 0 ? b.ahead : 0;
      pg.win.ask({ title: "A new release of " + pg.hubFull, glyph: "", ink: Zenon.cyan,
        detail: (prev !== "" ? "The last tag here is " + prev + ". " : "No tags here yet. ")
          + pg.site.name + " makes the tag on the branch as it has it"
          + (unpushed > 0 ? " — " + here + " has " + unpushed + (unpushed === 1 ? " commit" : " commits") + " not pushed yet, which would not be in it." : "."),
        fields: [{ key: "tag", label: "Tag", value: D.nextVersion(prev), hint: "v1.0.0" },
                 { key: "target", label: "From", value: here, options: branches.length > 0 ? branches : [here] }],
        verb: "Next",
        then: (v) => pg.notes(v.tag.trim(), v.target, prev) });
    });
  }
  // the notes written for you, then the release itself asked about
  function notes(tag, target, prev) {
    if (tag === "") return;
    const write = (body, by) => pg.askRelease(tag, target, body, by, prev);
    const fromCommits = () => pg.win.mgr.call("changelog", pg.win.root, { since: prev, until: target }, (ok, cs) => {
      if (!pg) return;
      write(ok ? D.notesFrom(cs, prev) : "", ok && cs.length > 0 ? "commits" : "");
    });
    pg.win.act(pg.op("ReleaseNotes"), { full: pg.hubFull, tag: tag, target: target, previous: prev || null }, {
      repo: null, refresh: false, label: "Writing the notes",
      then: (r) => { if (!pg) return; if (r && r.body) write(r.body, r.by); else fromCommits(); },
      failed: () => { if (pg) fromCommits(); } });
  }
  function askRelease(tag, target, body, by, prev) {
    pg.win.ask({ title: "Release " + tag, glyph: "", ink: Zenon.cyan,
      detail: (by === "github" ? "The notes are GitHub's, from what was merged since " + (prev || "the start") + "."
              : by === "commits" ? "The notes are the commits since " + (prev || "the start") + "."
              : "Nothing to write the notes from — say what is in it.")
        + " Change anything before it goes.",
      fields: [{ key: "name", label: "Title", value: tag, hint: tag },
               { key: "body", label: "Notes", value: body, lines: true, optional: true, hint: "what is in it — markdown" }],
      toggles: pg.drafts ? [{ key: "draft", label: "A draft (only you see it, until published)", value: false },
                            { key: "prerelease", label: "A pre-release", value: false }] : [],
      verb: "Publish",
      then: (v) => pg.win.act(pg.op("CreateRelease"), {
          full: pg.hubFull, tag: tag, target: target, name: v.name.trim() || tag, body: v.body,
          draft: !!v.draft, prerelease: !!v.prerelease }, {
        repo: null, label: "Publishing " + tag, network: true, refresh: false,
        said: (v.draft ? "Saved " : "Released ") + tag,
        then: () => { if (!pg) return; pg.sel = 0; pg.reload(); pg.win.act("fetch", {}, { refresh: true }); } }) });
  }

  function key(e) {
    const k = e.key;
    if (e.modifiers & Qt.ControlModifier) return false;
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(pg.sel + 1); return true; }
    if (k === Qt.Key_N) { pg.create(); return true; }
    if (k === Qt.Key_W) { pg.web(); return true; }
    if (k === Qt.Key_R) { pg.reload(); return true; }
    return false;
  }

  // ── the list ───────────────────────────────────────────────────────────
  Item {
    id: left
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: pg.win && pg.win.splits.releases ? pg.win.splits.releases : Math.round(Math.min(440, pg.width * 0.36))
    ListView {
      id: list
      anchors.fill: parent
      clip: true
      topMargin: 10
      bottomMargin: 10
      boundsBehavior: Flickable.StopAtBounds
      model: pg.rels
      readonly property int rowH: Math.round(Zenon.px(15) * 3.3)
      SelectBar { view: list; host: pg.win; index: pg.sel; on: pg.rels.length > 0; rowH: list.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
      delegate: Item {
        id: rrow
        required property var modelData
        required property int index
        readonly property var r: rrow.modelData
        width: list.width
        height: list.rowH
        Text {
          id: rg
          x: 22
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: rrow.r.draft ? Zenon.muted : rrow.r.prerelease ? Zenon.yellow : rrow.index === 0 ? Zenon.green : Zenon.cyan
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(17)
        }
        Column {
          anchors.left: rg.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.rightMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 3
          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: D.esc(rrow.r.name) + (rrow.r.name !== rrow.r.tag ? "  <font color='" + Zenon.hex(Zenon.muted) + "'>" + D.esc(rrow.r.tag) + "</font>" : "")
            color: rrow.index === pg.sel ? Zenon.ink : Zenon.soft
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: [rrow.r.draft ? "draft" : rrow.r.prerelease ? "pre-release" : rrow.index === 0 ? "latest" : "",
                   rrow.r.author, rrow.r.when ? D.ago(D.secondsOf(rrow.r.when), Date.now()) : "",
                   rrow.r.assets.length > 0 ? rrow.r.assets.length + (rrow.r.assets.length === 1 ? " file" : " files") : ""]
              .filter((x) => x !== "").join("  ·  ")
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.features: { "tnum": 1 }
            font.pixelSize: Zenon.px(13)
          }
        }
        MouseArea {
          anchors.fill: parent
          onClicked: { pg.moveTo(rrow.index); pg.win.focusKeys(); }
          onDoubleClicked: pg.web()
        }
      }
      EmptyMark {
        anchors.centerIn: parent
        visible: pg.rels.length === 0 && !pg.loading && pg.listError === "" && !!pg.hub
        word: "No releases yet"
      }
    }
    ElasticScroll { anchors.fill: list; view: list }
    Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }
    Working { anchors.centerIn: list; z: 5; running: pg.loading; visible: pg.loading }
    Text {
      anchors.centerIn: parent
      width: parent.width - 48
      visible: !pg.hub || (pg.listError !== "" && !pg.loading)
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: !pg.hub ? "This repository has no remote on GitHub, GitLab or Codeberg" : pg.listError
      color: !pg.hub ? Zenon.muted : Zenon.red
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(15)
    }
  }

  // ── one release ────────────────────────────────────────────────────────
  Flickable {
    id: body
    anchors.left: left.right
    anchors.leftMargin: 1
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    visible: !!pg.rel
    clip: true
    contentWidth: width
    contentHeight: relCol.implicitHeight + 40
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: relCol
      x: 24
      y: 20
      width: body.width - 48
      spacing: 10
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: pg.rel ? pg.rel.name : ""
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(20)
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: !pg.rel ? "" : [pg.rel.tag, pg.rel.draft ? "a draft" : pg.rel.prerelease ? "a pre-release" : "",
          pg.rel.author ? "by " + pg.rel.author : "", pg.rel.when ? D.stamp(D.secondsOf(pg.rel.when)) : ""]
          .filter((x) => x !== "").join("  ·  ")
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      Rectangle { width: parent.width; height: 1; color: Zenon.border }
      TextEdit {
        width: parent.width
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.Wrap
        textFormat: pg.rel && pg.rel.body.trim() !== "" ? TextEdit.MarkdownText : TextEdit.PlainText
        text: !pg.rel ? "" : pg.rel.body.trim() === "" ? "No notes" : D.mdOf(pg.rel.body)
        color: pg.rel && pg.rel.body.trim() !== "" ? Zenon.ink : Zenon.muted
        selectionColor: Zenon.alpha(Zenon.cyan, 0.4)
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
        onLinkActivated: (link) => Quickshell.execDetached(["xdg-open", link])
      }
      // the files attached
      Text {
        visible: !!pg.rel && pg.rel.assets.length > 0
        text: "Files"
        color: Zenon.keyInk
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(14)
      }
      Repeater {
        model: pg.rel ? pg.rel.assets : []
        delegate: Item {
          id: arow
          required property var modelData
          width: relCol.width
          height: Zenon.px(15) * 2
          Text {
            id: an
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - asz.width - 12
            elide: Text.ElideMiddle
            text: arow.modelData.name
            color: Zenon.blue
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
            MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["xdg-open", arow.modelData.url]) }
          }
          Text {
            id: asz
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: [arow.modelData.size > 0 ? Terminus.formatSize(arow.modelData.size) : "",
                   arow.modelData.downloads >= 0 ? arow.modelData.downloads + (arow.modelData.downloads === 1 ? " download" : " downloads") : ""]
              .filter((x) => x !== "").join("  ·  ")
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.features: { "tnum": 1 }
            font.pixelSize: Zenon.px(13)
          }
        }
      }
    }
  }
  ElasticScroll { anchors.fill: body; view: body; visible: body.visible }
  Scrollbar { flick: body; visible: body.visible; anchors.right: body.right; anchors.top: body.top; anchors.bottom: body.bottom }

  SeamGrip {
    frame: pg
    at: left.width
    min: 260
    max: pg.width - 360
    onMoved: (p) => pg.win.setSplit("releases", p)
    onReset: pg.win.setSplit("releases", 0)
  }
}
