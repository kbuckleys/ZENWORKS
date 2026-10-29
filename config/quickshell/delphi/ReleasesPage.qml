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
import "../morpheus"
import "../morpheus/controls" as Controls
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
  readonly property bool drafts: !!pg.hub && !pg.draftless(pg.hub)
  function draftless(h) { return /^gitlab/.test(h.forge); }

  // ── THE SAME RELEASE ON THE OTHER FORGES (user, 2026-10-26) ────────────
  // The repository's other forge remotes, each a tick in the editor (edit
  // .also, by hubKeyOf): ticked to begin with only when the repository is
  // kept in sync across them (Push's "Keep them all in sync") — another
  // remote may be a project you only follow. A draft goes to none that has
  // no drafts: there it would be public.
  readonly property var others: pg.hubs.filter((h) => pg.hubKeyOf(h) !== pg.hubKey)
  function hubKeyOf(h) { return h.forge + " " + h.full; }
  function opOf(h, name) { return (D.FORGES[h.forge] || D.FORGES.github).id + name; }
  function siteOf(h) { return D.FORGES[h.forge] || D.FORGES.github; }
  function alsoOf(e) {
    return !e || !e.also ? [] : pg.others.filter((h) => e.also.indexOf(pg.hubKeyOf(h)) >= 0 && !(e.draft && pg.draftless(h)));
  }
  function setAlso(h, on) {
    if (!pg.edit) return;
    const k = pg.hubKeyOf(h), a = (pg.edit.also || []).filter((x) => x !== k);
    pg.setEdit("also", on ? a.concat([k]) : a);
  }
  readonly property var alsoAtFirst: pg.win && pg.win.syncing ? pg.others.map(pg.hubKeyOf) : []

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
    // the list asked again (r): a release made or changed on the web, or in
    // another of Delphi's windows, without waiting (user, 2026-10-25) —
    // the refresh glyph, no words, as Hestia's
    { label: "\u{F0450}", glyph: true, visible: !!pg.hub, ready: !pg.loading, run: () => pg.reload() },
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
  // every file of a release: the ones uploaded, then the forge's own
  // archives of the tag ("Source code (zip)"), as the forge's page has them
  function filesOf(r) { return r ? r.assets.concat(r.sources || []) : []; }
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
  function web() { if (pg.rel && pg.rel.url) Strings.openLink(pg.rel.url); }
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
                  draft: false, prerelease: false, wasDraft: false, prev: prev, by: "", file: "",
                  unpushed: b && b.ahead > 0 ? b.ahead : 0, also: pg.alsoAtFirst, was: "" };
      pg.writeNotes();
    });
  }
  function editRel(r) {
    if (!r) return;
    pg.edit = { mode: "edit", id: r.id, tag: r.tag, target: r.target, name: r.name, body: r.body,
                draft: r.draft, prerelease: r.prerelease, wasDraft: r.draft, prev: "", by: "", file: "", unpushed: 0,
                also: pg.alsoAtFirst, was: r.tag };
  }
  function setEdit(k, v) {
    if (!pg.edit) return;
    const e = Object.assign({}, pg.edit);
    e[k] = v;
    pg.edit = e;
  }
  function cancelEdit() { pg.edit = null; Qt.callLater(pg.takeFocus); }
  // The notes written for you: the repository's changelog where it has a
  // section for the tag (CHANGELOG.md and its kin, core changelog_notes),
  // else GitHub's own, else the commits since the last tag. Into the notes
  // as they are — asked for again, they replace.
  property bool writing: false
  function writeNotes() {
    const e = pg.edit;
    if (!e || e.tag.trim() === "") return;
    const tag = e.tag.trim(), target = e.target, prev = e.prev;
    const put = (body, by, file) => { if (!pg || !pg.edit || pg.edit.tag.trim() !== tag) return;
      pg.writing = false;
      const n = Object.assign({}, pg.edit, { body: body, by: by, file: file || "" });
      pg.edit = n;
      editor.reset();
    };
    const fromCommits = () => pg.win.mgr.call("changelog", pg.win.root, { since: prev, until: target || "HEAD" }, (ok, cs) => {
      if (!pg) return;
      put(ok ? D.notesFrom(cs, prev) : "", ok && cs.length > 0 ? "commits" : "");
    });
    const fromForge = () => pg.win.mgr.call(pg.op("ReleaseNotes"), null, { full: pg.hubFull, tag: tag, target: target, previous: prev || null },
      (ok, r) => { if (!pg) return; if (ok && r && r.body) put(r.body, r.by); else fromCommits(); });
    pg.writing = true;
    pg.win.mgr.call("changelogNotes", pg.win.root, { tag: tag }, (ok, r) => { if (!pg) return;
      if (ok && r.body !== "") put(r.body, "changelog", r.file); else fromForge(); });
  }
  function save() {
    const e = pg.edit;
    if (!e || e.tag.trim() === "") return;
    const tag = e.tag.trim(), name = (e.name || "").trim() || tag;
    const args = { full: pg.hubFull, tag: tag, name: name, body: e.body, draft: !!e.draft, prerelease: !!e.prerelease,
                   // what may be uploaded from the notes (ReleaseEditor.noteMedia)
                   media: e.media || [] };
    if (e.mode === "new") args.target = e.target; else args.id = e.id;
    const also = pg.alsoOf(e);
    const here = () => pg.win.act(pg.op(e.mode === "new" ? "CreateRelease" : "UpdateRelease"), args, {
      repo: null, network: true, refresh: false,
      label: (e.mode === "new" ? (e.draft ? "Saving " : "Publishing ") : "Saving ") + tag + (also.length > 0 ? " on " + pg.site.name : ""),
      said: also.length > 0 ? "" : e.mode === "new" ? (e.draft ? "Saved the draft of " + tag : "Released " + tag) : "Saved " + tag,
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
        const after = () => { if (pg && e.mode === "new" && !e.draft && !e.prerelease) pg.offerAur(tag); };
        if (also.length > 0) pg.spread(e, args, also, after); else after();
      } });
    // a new release on more than one forge: the tag made here and pushed
    // to each first, so every forge has it on the same commit — left to
    // each forge, each would tag its own copy of the branch. A draft makes
    // no tag until published, so it is left to the forges.
    if (e.mode === "new" && !e.draft && also.length > 0) pg.tagEverywhere(tag, e.target, [pg.hub].concat(also), here);
    else here();
  }
  function tagEverywhere(tag, target, hubs, then) {
    const push = (i) => {
      if (!pg) return;
      if (i >= hubs.length) { then(); return; }
      pg.win.act("push", { remote: hubs[i].remote, branch: "refs/tags/" + tag },
        { label: "Pushing " + tag + " to " + pg.siteOf(hubs[i]).name, network: true, refresh: false, then: () => push(i + 1) });
    };
    if ((pg.win.refs.tags || []).some((t) => t.name === tag)) push(0);
    else pg.win.act("tagCreate", { name: tag, rev: target || "HEAD", message: tag },
                    { label: "Tagging " + tag, refresh: false, then: () => push(0) });
  }
  // the release on each other forge in turn, one that fails not stopping
  // the rest; said at the end, all of them at once. An edit finds the
  // release there by its tag (as it was), and makes it where it is missing.
  function spread(e, args, hubs, after) {
    const done = [pg.site.name], bad = [];
    const finish = () => {
      if (!pg) return;
      const verb = e.mode === "new" ? (e.draft ? "Saved the draft of " : "Released ") : "Saved ";
      if (bad.length === 0) pg.win.say(verb + args.tag + " on " + D.andList(done));
      else pg.win.card_({ question: args.tag + " is not on " + D.andList(bad.map((b) => b.name)), glyph: "\uF412", ink: Zenon.yellow,
        detail: (done.length > 0 ? "It is on " + D.andList(done) + ". " : "") + "Try those again from their own Releases page, or on the web.",
        items: bad.map((b) => b.name + ": " + D.errorText(b.err).split("\n")[0]),
        choices: [{ label: "OK", ink: Zenon.cyan }] });
      after();
    };
    const next = (i) => {
      if (!pg) return;
      if (i >= hubs.length) { finish(); return; }
      const h = hubs[i], site = pg.siteOf(h);
      const one = Object.assign({}, args, { full: h.full });
      const failed = (err) => { bad.push({ name: site.name, err: err ? String(err.error || "") : "" }); next(i + 1); };
      const make = () => {
        const c = Object.assign({}, one, { target: e.mode === "new" ? e.target : one.tag });
        delete c.id;
        pg.win.act(pg.opOf(h, "CreateRelease"), c, { repo: null, network: true, refresh: false,
          label: "Publishing " + one.tag + " on " + site.name, failed: failed, then: () => { done.push(site.name); next(i + 1); } });
      };
      if (e.mode === "new") { make(); return; }
      pg.win.mgr.call(pg.opOf(h, "Releases"), null, { full: h.full }, (ok, list, err) => {
        if (!pg) return;
        if (!ok) { failed(err); return; }
        const there = list.find((r) => r.tag === (e.was || one.tag));
        if (!there) { make(); return; }
        pg.win.act(pg.opOf(h, "UpdateRelease"), Object.assign({}, one, { id: there.id }), { repo: null, network: true, refresh: false,
          label: "Saving " + one.tag + " on " + site.name, failed: failed, then: () => { done.push(site.name); next(i + 1); } });
      });
    };
    next(0);
  }

  // ── AND ITS AUR PACKAGE ────────────────────────────────────────────────
  // A release published: Delphi's repositories looked through for an AUR
  // package made from this one (core aur.packages_for — its url= or a
  // source= is one of these remotes). There is one: offered, the release
  // of it run on its AUR page with this version (mgr.aurWant). Publishing
  // it there stays a step of its own.
  function offerAur(tag) {
    const roots = pg.win.mgr.recents.map((r) => r.root).filter((r) => r !== pg.win.root);
    const urls = pg.win.remotes.map((r) => r.fetch || r.push);
    if (roots.length === 0 || urls.length === 0) return;
    const v = tag.replace(/^[vV](?=\d)/, "");
    pg.win.mgr.call("aurFor", null, { roots: roots, urls: urls }, (ok, found) => {
      if (!pg || !ok || found.length === 0) return;
      pg.win.card_({ question: "Release " + D.andList(found.map((p) => p.pkg)) + " " + v + " on the AUR too?", glyph: "\uF303", ink: Zenon.cyan,
        detail: "Its recipe opens on its AUR page, where the release runs: the tag checked, the version set, checksums, .SRCINFO and a build. Publishing it is a step of its own, after.",
        choices: found.slice(0, 3).map((p) => ({ label: found.length > 1 ? "Release " + p.pkg : "Release it", ink: Zenon.cyan,
                   run: () => { pg.win.mgr.aurWant = { root: p.root, version: v }; pg.win.openRepo(p.root); pg.win.setPage("aur"); } }))
          .concat([{ label: "Not now", ink: Zenon.accentMuted }]) });
    });
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
                   pg.filesOf(rrow.r).length > 0 ? pg.filesOf(rrow.r).length + (pg.filesOf(rrow.r).length === 1 ? " file" : " files") : ""]
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
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: pg.rel ? pg.rel.name : ""
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(20)
      }
      Text {
        textFormat: Text.PlainText
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
      // the notes, as the forge shows them — code chips, heading lines
      // and all (NotesView, the editor's Preview too)
      NotesView {
        id: notesText
        width: parent.width
        body: pg.rel ? pg.rel.body : ""
        textSize: editor.notesPx
      }
      // the files attached
      Text {
        visible: pg.filesOf(pg.rel).length > 0
        text: "Files"
        color: Zenon.accentKey
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(14)
      }
      // in the box a list stands in (morpheus' ListFrame), as Oracle's
      Item {
        visible: pg.filesOf(pg.rel).length > 0
        width: relCol.width
        height: fileList.height + 12
        Controls.ListFrame { anchors.fill: parent }
        Column {
          id: fileList
          x: 6
          y: 6
          width: parent.width - 12
          Repeater {
            model: pg.filesOf(pg.rel)
            delegate: Item {
              id: arow
              required property var modelData
              width: fileList.width
              height: Zenon.px(15) * 2
              Text {
                textFormat: Text.PlainText
                id: an
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - asz.width - 32
                elide: Text.ElideMiddle
                text: arow.modelData.name
                color: Zenon.blue
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
                // a GitLab release's links are whatever its author typed:
                // web addresses only (Strings.openLink)
                MouseArea { anchors.fill: parent; onClicked: Strings.openLink(arow.modelData.url) }
              }
              Text {
                textFormat: Text.PlainText
                id: asz
                anchors.right: parent.right
                anchors.rightMargin: 10
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
