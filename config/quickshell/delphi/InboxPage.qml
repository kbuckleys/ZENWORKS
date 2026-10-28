// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE INBOX (2026-10-28) — what every forge you are signed in to has for
// you, in one list, newest first: GitHub's notifications, GitLab's to-dos,
// Codeberg's (and your own servers') notifications. A review asked of you,
// a mention, a pull request on yours, an issue you follow.
//
//   return   open it: its repository here on its Pull requests or Issues
//            page when it is cloned, else its page on the web
//   w        on the web       d   done (read), and off the list
//   r        ask again
//
// Read on each opening of the page and on r; nothing polls.

import QtQuick
import "../morpheus"
import "../terminus"
import "delphi.js" as D

Item {
  id: pg
  property var win: null
  readonly property var edgeViews: [list]

  readonly property string title: "Inbox"
  readonly property string subtitle: pg.asking > 0 ? "Asking " + pg.asking + (pg.asking === 1 ? " forge…" : " forges…")
    : pg.rows.length === 0 ? (pg.signedIn.length === 0 ? "Not signed in to a forge" : "Nothing for you")
    : pg.rows.length + (pg.rows.length === 1 ? " thing" : " things") + " for you"
  readonly property var hints: [["return", "open"], ["w", "web"], ["d", "done"], ["r", "ask again"]]
  readonly property var buttons: [
    { label: "Done", visible: !!pg.row, run: () => pg.done(pg.row) },
    { label: "Ask again", ink: Zenon.cyan, primary: true, run: () => pg.reload() },
  ]
  function takeFocus() { if (pg.win) pg.win.focusKeys(); }

  property var rows: []
  property var signedIn: []
  property int asking: 0
  property int sel: 0
  readonly property var row: pg.sel >= 0 && pg.sel < pg.rows.length ? pg.rows[pg.sel] : null

  // every forge Delphi knows: signed in to it, its inbox. An ask again
  // while one is out starts over: the older answers (`gen`) are dropped,
  // or they landed twice and the count of forges asked went wrong
  property int gen: 0
  function reload() {
    const g = ++pg.gen;
    pg.rows = [];
    pg.signedIn = [];
    pg.asking = 0;
    for (const id of D.FORGE_ORDER) {
      const f = D.FORGES[id];
      pg.asking++;
      pg.win.mgr.call(id + "Status", null, {}, (ok, st) => {
        if (!pg || g !== pg.gen) return;
        if (!ok || !st || !st.signedIn) { pg.asking--; return; }
        pg.signedIn = pg.signedIn.concat([id]);
        pg.win.mgr.call(id + "Inbox", null, {}, (ok2, items, err) => {
          if (!pg || g !== pg.gen) return;
          pg.asking--;
          if (!ok2) { pg.win.say(f.name + ": " + (err && err.error ? err.error : "its inbox did not come"), true); return; }
          const mine = items.map((x) => Object.assign({ forge: id, forgeName: f.name, glyph: f.glyph }, x));
          pg.rows = pg.rows.concat(mine).sort((a, b) => String(b.when).localeCompare(String(a.when)));
        });
      });
    }
  }
  Component.onCompleted: Qt.callLater(pg.reload)

  function moveTo(i) {
    if (pg.rows.length === 0) return;
    pg.sel = Math.max(0, Math.min(pg.rows.length - 1, i));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
  }
  function web(r) { if (r && r.web) Strings.openLink(r.web); }
  function done(r) {
    if (!r) return;
    pg.win.mgr.call(r.forge + "InboxDone", null, { id: r.id }, (ok, res, err) => {
      if (!pg) return;
      if (!ok) { pg.win.say(err && err.error ? err.error : "It was not marked", true); return; }
      pg.rows = pg.rows.filter((x) => !(x.forge === r.forge && x.id === r.id));
      pg.sel = Math.min(pg.sel, pg.rows.length - 1);
    });
  }
  // here when it is cloned here: its repository on the page it belongs to
  function open(r) {
    if (!r) return;
    const site = D.FORGES[r.forge];
    const roots = pg.win.mgr.recents.map((x) => x.root);
    if (!site || !r.repo || (r.kind !== "pull" && r.kind !== "issue")) { pg.web(r); return; }
    pg.win.mgr.call("whereCloned", null, { host: site.host, full: r.repo, roots: roots }, (ok, res) => {
      if (!pg) return;
      if (!ok || !res.root) { pg.web(r); return; }
      pg.win.openRepo(res.root);
      pg.win.setPage(r.kind === "pull" ? "pulls" : "issues");
      pg.win.say("#" + r.number + " " + r.title);
    });
  }
  function ago(iso) {
    const t = Date.parse(iso);
    if (isNaN(t)) return "";
    const m = Math.round((Date.now() - t) / 60000);
    return m < 60 ? m + " min" : m < 1440 ? Math.round(m / 60) + " h" : Math.round(m / 1440) + " d";
  }
  readonly property var kindGlyph: ({ pull: "", issue: "", release: "", commit: "", ci: "", discussion: "", other: "" })

  function key(e) {
    const k = e.key;
    if (e.modifiers & Qt.ControlModifier) return false;
    if (k === Qt.Key_R) { pg.reload(); return true; }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(pg.sel + 1); return true; }
    if (!pg.row) return false;
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { pg.open(pg.row); return true; }
    if (k === Qt.Key_W) { pg.web(pg.row); return true; }
    if (k === Qt.Key_D || k === Qt.Key_Delete) { pg.done(pg.row); return true; }
    return false;
  }

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    topMargin: 8
    bottomMargin: 8
    boundsBehavior: Flickable.StopAtBounds
    model: pg.rows
    readonly property int rowH: Math.round(Zenon.px(15) * 3.2)
    SelectBar { view: list; host: pg.win; index: pg.sel; rowH: list.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
    delegate: Item {
      id: irow
      required property var modelData
      required property int index
      width: list.width
      height: list.rowH
      Text {
        id: kind
        x: 22
        width: Zenon.px(22)
        anchors.verticalCenter: parent.verticalCenter
        text: pg.kindGlyph[irow.modelData.kind] || pg.kindGlyph.other
        color: irow.modelData.kind === "pull" ? Zenon.magenta : irow.modelData.kind === "issue" ? Zenon.green : Zenon.cyan
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(16)
      }
      Column {
        anchors.left: kind.right
        anchors.leftMargin: 10
        anchors.right: when.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
          textFormat: Text.PlainText
          width: parent.width
          elide: Text.ElideRight
          text: irow.modelData.title
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(14)
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: irow.modelData.forgeName + "  ·  " + irow.modelData.repo + (irow.modelData.number ? " #" + irow.modelData.number : "")
            + (irow.modelData.reason ? "  ·  " + irow.modelData.reason : "")
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      Text {
        id: when
        anchors.right: parent.right
        anchors.rightMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        text: pg.ago(irow.modelData.when)
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
      MouseArea {
        anchors.fill: parent
        onClicked: { pg.sel = irow.index; pg.win.focusKeys(); }
        onDoubleClicked: pg.open(irow.modelData)
      }
    }
  }
  ElasticScroll { anchors.fill: list; view: list }
  Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }

  EmptyState {
    anchors.centerIn: list
    width: 460
    visible: pg.rows.length === 0 && pg.asking === 0
    text: pg.signedIn.length === 0 ? "Sign in to GitHub, GitLab or Codeberg on Accounts, and what they have for you comes here."
      : "Nothing for you — no reviews asked, no mentions, nothing new on what you follow."
  }
}
