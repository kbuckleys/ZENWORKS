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
  readonly property var edgeViews: pg.edit ? [] : [list, body]
  readonly property var footViews: pg.edit ? [] : [list, body]

  // the window's hub, unless it has releases turned off (a 404): then the
  // next of the repository's forge remotes that has them (D.hubsOf)
  readonly property var hubs: { pg.win && pg.win.mgr ? pg.win.mgr.servers : null; return pg.win ? D.hubsOf(pg.win.remotes) : []; }
  readonly property string hubsKey: pg.hubs.map((h) => h.forge + " " + h.full).join("\n")
  onHubsKeyChanged: pg.hubAt = 0
  property int hubAt: 0
  readonly property var hub: pg.hubs.length > 0 ? pg.hubs[Math.min(pg.hubAt, pg.hubs.length - 1)] : null
  readonly property string hubFull: pg.hub ? pg.hub.full : ""
  readonly property string hubKey: pg.hub ? pg.hub.forge + " " + pg.hub.full : ""
  readonly property var site: D.FORGES[pg.hub ? pg.hub.forge : "github"] || D.FORGES.github
  function op(name) { return (D.FORGES[pg.hub ? pg.hub.forge : "github"] || D.FORGES.github).id + name; }
  // GitLab (gitlab.com or a server of your own) has no drafts or pre-releases
  readonly property bool drafts: !!pg.hub && !/^gitlab/.test(pg.hub.forge)

  readonly property string title: pg.edit ? (pg.edit.mode === "new" ? "New release" : "Editing " + pg.edit.tag) : "Releases"
  readonly property string subtitle: pg.edit ? pg.hubFull
    : !pg.hub ? "Not on GitHub, GitLab or Codeberg"
    : pg.loading ? pg.hubFull + "  ·  asking " + pg.site.name + "…"
    : pg.hubFull + (pg.hubs.length > 1 ? " on " + pg.site.name : "") + "  ·  " + (pg.rels.length === 0 ? "none yet" : pg.rels.length + (pg.rels.length === 1 ? " release" : " releases"))
  readonly property var hints: pg.edit ? [["ctrl return", pg.edit.mode === "new" ? "publish" : "save"], ["esc", "back"], ["tab", "next field"]]
    : [["↑↓", "releases"], ["n", "new"], ["e", "edit"], ["w", "web"], ["r", "refresh"]]
  readonly property var buttons: pg.edit ? [
    { label: "Cancel", run: () => pg.cancelEdit() },
    { label: pg.edit.mode === "new" ? (pg.edit.draft ? "Save the draft" : "Publish") : (pg.edit.wasDraft && !pg.edit.draft ? "Publish" : "Save"),
      ink: Zenon.cyan, primary: true, ready: pg.edit.tag.trim() !== "", run: () => pg.save() },
  ] : [
    { label: "Delete", ink: Zenon.red, visible: !!pg.rel, run: () => pg.remove() },
    { label: "Edit", visible: !!pg.rel, run: () => pg.editRel(pg.rel) },
    { label: "On the web", visible: !!pg.rel, run: () => pg.web() },
    { label: "New release", ink: Zenon.cyan, primary: true, visible: !!pg.hub, run: () => pg.create() },
  ]
  function takeFocus() {
    if (pg.edit) { if (!editor.typing) editor.claim(); return; }
    if (pg.win) pg.win.focusKeys();
  }

  property var rels: []
  property bool loading: false
  property string listError: ""
  property int sel: 0
  readonly property var rel: pg.sel >= 0 && pg.sel < pg.rels.length ? pg.rels[pg.sel] : null
  function reload() {
    if (!pg || !pg.win || !pg.hub) return;
    const asked = pg.hubKey, keep = pg.rel ? pg.rel.tag : "";
    pg.loading = true;
    pg.win.mgr.call(pg.op("Releases"), null, { full: pg.hubFull }, (ok, res, err) => { if (!pg || asked !== pg.hubKey) return;
      pg.loading = false;
      // releases off on this forge: on to the next remote's
      if (!ok && err && err.status === 404 && pg.hubAt + 1 < pg.hubs.length) { pg.hubAt++; return; }
      pg.listError = ok ? "" : D.errorText(err ? err.error : "");
      if (!ok) { pg.rels = []; return; }
      // one just made or changed here, which the forge's list may not have
      // caught up with yet: kept as it was answered, until the list has it
      const fresh = pg.pending.filter((p) => !res.some((r) => r.tag === p.tag && (r.body === p.body && r.name === p.name)));
      pg.pending = fresh;
      pg.rels = fresh.concat(res.filter((r) => !fresh.some((p) => p.tag === r.tag)));
      const i = keep !== "" ? pg.rels.findIndex((r) => r.tag === keep) : -1;
      pg.sel = i >= 0 ? i : Math.max(0, Math.min(pg.sel, pg.rels.length - 1));
    });
  }
  Component.onCompleted: Qt.callLater(pg.reload)
  onHubKeyChanged: { pg.rels = []; pg.edit = null; pg.reload(); }
  function web() { if (pg.rel && pg.rel.url) Quickshell.execDetached(["xdg-open", pg.rel.url]); }
  function moveTo(i) {
    if (pg.rels.length === 0) return;
    pg.sel = Math.max(0, Math.min(pg.rels.length - 1, i));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
  }

  // ── WRITING ONE: A PAGE OF ITS OWN (user, 2026-10-11: the sheet was too
  // tight for release notes) ─────────────────────────────────────────────
  // `edit` is the release being written — a new one, or one there is — and
  // while it is, the page is its editor (ReleaseEditor below): tag, the
  // branch it is made from, title, draft and pre-release, and the notes,
  // written or previewed. What is saved lands in the list at once
  // (`pending`), not when the forge's list next mentions it.
  property var edit: null
  property var pending: []
  function create() {
    if (!pg.hub) return;
    const b = pg.win.branch;
    const here = b && b.head ? b.head : "";
    pg.win.mgr.call("lastTag", pg.win.root, {}, (ok, last) => { if (!pg) return;
      const prev = ok ? last : "";
      pg.edit = { mode: "new", id: null, tag: D.nextVersion(prev), target: here, name: "", body: "",
                  draft: false, prerelease: false, wasDraft: false, prev: prev, by: "",
                  unpushed: b && b.ahead > 0 ? b.ahead : 0 };
      pg.writeNotes();
    });
  }
  function editRel(r) {
    if (!r) return;
    pg.edit = { mode: "edit", id: r.id, tag: r.tag, target: r.target, name: r.name, body: r.body,
                draft: r.draft, prerelease: r.prerelease, wasDraft: r.draft, prev: "", by: "", unpushed: 0 };
  }
  function setEdit(k, v) {
    if (!pg.edit) return;
    const e = Object.assign({}, pg.edit);
    e[k] = v;
    pg.edit = e;
  }
  function cancelEdit() { pg.edit = null; Qt.callLater(pg.takeFocus); }
  // The notes written for you: GitHub's own, else the commits since the
  // last tag. Into the notes as they are — asked for again, they replace.
  property bool writing: false
  function writeNotes() {
    const e = pg.edit;
    if (!e || e.tag.trim() === "") return;
    const tag = e.tag.trim(), target = e.target, prev = e.prev;
    const put = (body, by) => { if (!pg || !pg.edit || pg.edit.tag.trim() !== tag) return;
      pg.writing = false;
      const n = Object.assign({}, pg.edit, { body: body, by: by });
      pg.edit = n;
      editor.reset();
    };
    const fromCommits = () => pg.win.mgr.call("changelog", pg.win.root, { since: prev, until: target || "HEAD" }, (ok, cs) => {
      if (!pg) return;
      put(ok ? D.notesFrom(cs, prev) : "", ok && cs.length > 0 ? "commits" : "");
    });
    pg.writing = true;
    pg.win.mgr.call(pg.op("ReleaseNotes"), null, { full: pg.hubFull, tag: tag, target: target, previous: prev || null },
      (ok, r) => { if (!pg) return; if (ok && r && r.body) put(r.body, r.by); else fromCommits(); });
  }
  function save() {
    const e = pg.edit;
    if (!e || e.tag.trim() === "") return;
    const tag = e.tag.trim(), name = (e.name || "").trim() || tag;
    const args = { full: pg.hubFull, tag: tag, name: name, body: e.body, draft: !!e.draft, prerelease: !!e.prerelease };
    if (e.mode === "new") args.target = e.target; else args.id = e.id;
    pg.win.act(pg.op(e.mode === "new" ? "CreateRelease" : "UpdateRelease"), args, {
      repo: null, network: true, refresh: false,
      label: (e.mode === "new" ? (e.draft ? "Saving " : "Publishing ") : "Saving ") + tag,
      said: e.mode === "new" ? (e.draft ? "Saved the draft of " + tag : "Released " + tag) : "Saved " + tag,
      then: (r) => {
        if (!pg) return;
        // in the list now, as the forge answered it
        pg.pending = [r].concat(pg.pending.filter((p) => p.tag !== r.tag));
        pg.rels = [r].concat(pg.rels.filter((x) => x.tag !== r.tag && (e.mode !== "edit" || x.id !== e.id)));
        pg.sel = 0;
        pg.edit = null;
        relaxed.restart();
        if (e.mode === "new") pg.win.act("fetch", {}, { refresh: true });
        Qt.callLater(pg.takeFocus);
      } });
  }
  // the forge's list asked again a moment later, when it has caught up
  Timer { id: relaxed; interval: 4000; onTriggered: pg.reload() }
  function remove() {
    const r = pg.rel;
    if (!r) return;
    pg.win.confirm({ question: "Delete the release " + r.name + "?", glyph: "\uF412", ink: Zenon.red,
      detail: "Its notes and the files attached go from " + pg.site.name + ". The tag " + r.tag + " stays — delete it from Branches if you want it gone too.",
      verb: "Delete",
      then: () => pg.win.act(pg.op("DeleteRelease"), { full: pg.hubFull, id: r.id, tag: r.tag }, {
        repo: null, network: true, refresh: false, label: "Deleting " + r.name, said: "Deleted " + r.name,
        then: () => { if (!pg) return; pg.pending = pg.pending.filter((p) => p.tag !== r.tag);
                      pg.rels = pg.rels.filter((x) => x.tag !== r.tag); pg.sel = Math.min(pg.sel, pg.rels.length - 1); relaxed.restart(); } }) });
  }

  function key(e) {
    const k = e.key;
    if (pg.edit) {
      if ((e.modifiers & Qt.ControlModifier) && (k === Qt.Key_Return || k === Qt.Key_Enter)) { pg.save(); return true; }
      if (k === Qt.Key_Escape) { pg.cancelEdit(); return true; }
      return false;
    }
    if (e.modifiers & Qt.ControlModifier) return false;
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(pg.sel + 1); return true; }
    if (k === Qt.Key_N) { pg.create(); return true; }
    if (k === Qt.Key_E) { pg.editRel(pg.rel); return true; }
    if (k === Qt.Key_W) { pg.web(); return true; }
    if (k === Qt.Key_R) { pg.reload(); return true; }
    return false;
  }

  // ── the list ───────────────────────────────────────────────────────────
  Item {
    id: left
    visible: !pg.edit
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
          color: rrow.r.draft ? Zenon.accentMuted : rrow.r.prerelease ? Zenon.yellow : rrow.index === 0 ? Zenon.green : Zenon.cyan
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
            text: D.esc(rrow.r.name) + (rrow.r.name !== rrow.r.tag ? "  <font color='" + Zenon.hex(Zenon.accentMuted) + "'>" + D.esc(rrow.r.tag) + "</font>" : "")
            color: rrow.index === pg.sel ? Zenon.ink : Zenon.accentSoft
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: [rrow.r.draft ? "Draft" : rrow.r.prerelease ? "Pre-release" : rrow.index === 0 ? "Latest" : "",
                   rrow.r.author, rrow.r.when ? D.ago(D.secondsOf(rrow.r.when), Date.now()) : "",
                   rrow.r.assets.length > 0 ? rrow.r.assets.length + (rrow.r.assets.length === 1 ? " file" : " files") : ""]
              .filter((x) => x !== "").join("  ·  ")
            color: Zenon.accentMuted
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
      EmptyState {
        anchors.centerIn: parent
        visible: pg.rels.length === 0 && !pg.loading && pg.listError === "" && !!pg.hub
        text: "No releases yet"
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
      color: !pg.hub ? Zenon.accentMuted : Zenon.red
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
    visible: !!pg.rel && !pg.edit
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
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      Rectangle { width: parent.width; height: 1; color: Zenon.border }
      TextEdit {
        palette.link: Zenon.link   // the theme's, not the system's blue
        width: parent.width
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.Wrap
        textFormat: pg.rel && pg.rel.body.trim() !== "" ? TextEdit.MarkdownText : TextEdit.PlainText
        text: !pg.rel ? "" : pg.rel.body.trim() === "" ? "No notes" : D.mdLinesOf(pg.rel.body)
        color: pg.rel && pg.rel.body.trim() !== "" ? Zenon.ink : Zenon.accentMuted
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
        color: Zenon.accentKey
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
            color: Zenon.accentMuted
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
    visible: !pg.edit
    frame: pg
    at: left.width
    min: 260
    max: pg.width - 360
    onMoved: (p) => pg.win.setSplit("releases", p)
    onReset: pg.win.setSplit("releases", 0)
  }

  ReleaseEditor {
    id: editor
    anchors.fill: parent
    visible: !!pg.edit
    page: pg
  }
}
