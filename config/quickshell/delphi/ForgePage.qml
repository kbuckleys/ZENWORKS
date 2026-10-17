// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PULL REQUESTS and ISSUES — both pages, one file: which it is follows the
// window's page. Of the forge repository the checkout belongs to —
// GitHub, GitLab (merge requests) or Codeberg — (the
// window's `hub`: upstream's for a fork, else origin's).
//
// The list on the left, newest-moved first, open or closed; on the right
// the one chosen, whole — its words, then everything said on it in order
// (reviews among them: approved, changes asked for) — and under it a well
// to say something. A full review, comments on lines of the diff, is
// GitHub's page (w).
//
//   both     r say something · x close / reopen · w on the web · n new
//            s open / closed
//   pulls    c check it out here · m merge
//   the well ctrl return send · esc back

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "delphi.js" as D

Item {
  id: pg
  property var win: null
  // the views whose rows carry on up under the window's head, frosted
  // (DelphiWindow's ScrollEdges) — only those with nothing but controls
  // between them and the head: a view under a title would paint over it
  readonly property var edgeViews: [list, threadFlick]
  // the views that run down to the foot (the thread stops at the reply)
  readonly property var footViews: [list]

  readonly property string kind: pg.win && pg.win.page === "issues" ? "issues" : "pulls"
  readonly property bool pulls: pg.kind === "pulls"
  readonly property var hub: pg.win ? pg.win.hub : null
  readonly property string hubFull: pg.hub ? pg.hub.full : ""
  // the forge it is on, its own requests and words (delphi.js FORGES)
  readonly property var site: D.FORGES[pg.hub ? pg.hub.forge : "github"] || D.FORGES.github
  // from `hub` itself, never `site` — see GitHubPage.op
  function op(name) { return (D.FORGES[pg.hub ? pg.hub.forge : "github"] || D.FORGES.github).id + name; }
  readonly property string noun: pg.pulls ? pg.site.pull : "issue"

  readonly property string title: pg.pulls ? pg.site.pulls : "Issues"
  readonly property string subtitle: !pg.hub ? "Not on GitHub, GitLab or Codeberg"
    : pg.loading ? pg.hubFull + "  ·  asking " + pg.site.name + "…"
    : pg.hubFull + "  ·  " + pg.rows.length + " " + pg.showing
  readonly property var hints: pg.area === "reply" ? [["ctrl return", "send"], ["esc", "back"]]
    : (pg.pulls ? [["c", "check out"], ["m", "merge"]] : [])
      .concat([["r", "reply"], ["x", pg.open ? "close" : "reopen"], ["w", "web"], ["n", "new"], ["s", pg.showing === "open" ? "closed" : "open"]])
  readonly property bool open: !!pg.item && pg.item.state === "open"
  readonly property var buttons: !pg.hub ? [{ label: "Publish it", ink: Zenon.cyan, primary: true, run: () => pg.win.setPage("github") }]
    : pg.signInNeeded ? [{ label: "Sign in to " + pg.site.name, ink: Zenon.cyan, primary: true, run: () => { pg.win.mgr.set("forge", pg.site.id); pg.win.setPage("github"); } }]
    : [
      { label: pg.open ? "Close" : "Reopen", ink: pg.open ? Zenon.red : Zenon.accentMuted, visible: !!pg.item, run: () => pg.setOpen(!pg.open) },
      { label: "Merge", ink: Zenon.magenta, visible: pg.pulls && pg.open && !!pg.item && !pg.item.draft, run: () => pg.merge() },
      { label: "Check out", visible: pg.pulls && !!pg.item && pg.item.state !== "merged", run: () => pg.checkout() },
      { label: pg.pulls ? "New " + pg.site.pull : "New issue", ink: Zenon.cyan, primary: true, run: () => pg.pulls ? pg.newPull() : pg.newIssue() },
    ]
  function takeFocus() {
    if (pg.area === "reply") reply.claim();
    else if (pg.win) pg.win.focusKeys();
  }

  // ── the list ───────────────────────────────────────────────────────────
  property string showing: "open"      // open | closed
  // every one listed, and those shown: all, others' (whose author is not
  // you on this forge — what came in), or yours (user, 2026-10-11)
  property var allRows: []
  property string who: "all"          // all | others | mine
  property string me: ""              // the account here, from its Status
  readonly property var rows: pg.who === "all" || pg.me === "" ? pg.allRows
    : pg.allRows.filter((r) => pg.who === "mine" ? r.author === pg.me : r.author !== pg.me)
  onWhoChanged: { pg.sel = 0; pg.thread = null; if (pg.row) Qt.callLater(pg.loadThread); }
  function loadMe() {
    if (!pg.hub) { pg.me = ""; return; }
    const forge = pg.hub.forge;
    pg.win.mgr.call(pg.op("Status"), null, {}, (ok, st) => {
      if (pg && pg.hub && pg.hub.forge === forge) pg.me = ok && st.signedIn ? st.login : "";
    });
  }
  property bool loading: false
  property string listError: ""
  property bool signInNeeded: false
  property int sel: 0
  // the one to choose when the list next comes (one just opened)
  property int wanted: -1
  readonly property var row: pg.sel >= 0 && pg.sel < pg.rows.length ? pg.rows[pg.sel] : null
  property string area: "list"         // list | reply
  onAreaChanged: pg.takeFocus()

  function reload() {
    if (!pg.win || !pg.hub) { pg.allRows = []; pg.thread = null; return; }
    const full = pg.hubFull, kind = pg.kind, showing = pg.showing;
    pg.loading = true;
    pg.listError = "";
    // from `kind` itself: in onKindChanged, `pulls` may not have caught up
    pg.win.mgr.call(pg.op(kind === "pulls" ? "Pulls" : "Issues"), null, { full: full, state: showing }, (ok, rs, err) => {
      if (!pg) return;
      // an answer for a list no longer shown: the page moved on meanwhile
      if (kind !== pg.kind || showing !== pg.showing || full !== pg.hubFull) return;
      pg.loading = false;
      if (!ok) {
        pg.allRows = [];
        pg.thread = null;
        pg.signInNeeded = !!err && err.status === 401;
        pg.listError = pg.signInNeeded ? "Not signed in to " + pg.site.name : D.errorText(err ? err.error : "");
        return;
      }
      pg.signInNeeded = false;
      const keep = pg.wanted >= 0 ? pg.wanted : pg.row ? pg.row.number : -1;
      pg.wanted = -1;
      pg.allRows = rs;
      // the pull requests' checks, where the forge says which commit each is at
      if (pg.pulls) {
        const shas = rs.filter((r) => !!r.sha && r.state === "open").map((r) => r.sha);
        if (shas.length > 0) pg.win.mgr.ciAsk(pg.hub.forge, pg.hub.full, shas);
      }
      const i = pg.rows.findIndex((r) => r.number === keep);
      pg.sel = i >= 0 ? i : 0;
      if (pg.row) list.positionViewAtIndex(pg.sel, ListView.Contain);
      pg.loadThread();
    });
  }
  onKindChanged: { pg.allRows = []; pg.thread = null; pg.sel = 0; pg.area = "list"; pg.showing = "open"; pg.reload(); }
  onShowingChanged: { pg.allRows = []; pg.thread = null; pg.reload(); }
  onHubFullChanged: { pg.reload(); pg.loadMe(); }
  Component.onCompleted: { Qt.callLater(pg.reload); Qt.callLater(pg.loadMe); }

  function moveTo(i) {
    if (pg.rows.length === 0) return;
    pg.sel = Math.max(0, Math.min(pg.rows.length - 1, i));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
    // asked once the cursor rests, not for every row it passes
    threadWait.restart();
  }
  Timer { id: threadWait; interval: 160; onTriggered: pg.loadThread() }

  // ── a look at one without choosing it ──────────────────────────────────
  // Resting on a row other than the chosen one brings up a bubble
  // (terminus/Bubble): its title, state, who and when, labels, and the
  // start of what it says. The chosen one is already open beside it.
  property Item peekRow: null
  property var peek: null
  property bool peeking: false
  Timer { id: peekWait; interval: 450; onTriggered: pg.peeking = !!pg.peekRow }
  onSelChanged: pg.peeking = false

  // ── the one chosen ─────────────────────────────────────────────────────
  property var thread: null
  property bool threadLoading: false
  // the thread when it is the chosen row's; until it comes, the row itself
  readonly property bool whole: !!pg.thread && !!pg.row && pg.thread.number === pg.row.number
  readonly property var item: pg.whole ? pg.thread : pg.row
  function loadThread() {
    const r = pg.row;
    if (!r) { pg.thread = null; return; }
    const n = r.number, full = pg.hubFull;
    pg.threadLoading = true;
    // `pull`: GitLab numbers merge requests and issues apart
    pg.win.mgr.call(pg.op("Thread"), null, { full: full, number: n, pull: pg.pulls }, (ok, t, err) => {
      if (!pg || !pg.row || pg.row.number !== n || full !== pg.hubFull) return;
      pg.threadLoading = false;
      if (ok) {
        const fresh = !pg.thread || pg.thread.number !== n;
        pg.thread = t;
        if (fresh) threadFlick.contentY = 0;
      } else pg.win.say("Could not read #" + n + ": " + D.errorText(err ? err.error : ""), true);
    });
  }

  // ── doing things ───────────────────────────────────────────────────────
  function web() { if (pg.item) Quickshell.execDetached(["xdg-open", pg.item.url]); }

  function send() {
    const t = pg.item, body = reply.text.trim();
    if (!t || body === "") return;
    const n = t.number;
    pg.win.act(pg.op("Comment"), { full: pg.hubFull, number: n, body: body, pull: pg.pulls }, { repo: null, refresh: false, label: "Sending your comment on #" + n, network: true,
      then: (c) => { if (!pg) return;
        reply.text = "";
        pg.area = "list";
        if (pg.whole && pg.thread.number === n) {
          pg.thread = Object.assign({}, pg.thread, { said: pg.thread.said.concat([c]) });
          Qt.callLater(() => threadFlick.contentY = Math.max(0, threadFlick.contentHeight - threadFlick.height));
        }
        pg.win.say("Said on #" + n);
      } });
  }

  function setOpen(open) {
    const t = pg.item;
    if (!t || t.state === "merged") return;
    const go = () => pg.win.act(pg.op("SetState"), { full: pg.hubFull, number: t.number, open: open, pull: pg.pulls }, { repo: null, refresh: false,
      label: (open ? "Reopening #" : "Closing #") + t.number, network: true,
      said: (open ? "Reopened #" : "Closed #") + t.number, then: () => { if (pg) pg.reload(); } });
    if (open) { go(); return; }
    pg.win.confirm({ question: "Close #" + t.number + "?", glyph: D.forgeMark(t).glyph, ink: Zenon.red,
      detail: t.title + (pg.pulls ? "  ·  not merged — it can be reopened" : "  ·  it can be reopened"),
      verb: "Close", then: go });
  }

  // A pull request's commits, here: its own branch when it comes from this
  // repository (so a push goes back into it), pr-N for one from a fork
  function checkout() {
    const t = pg.item;
    if (!t || !t.pull) return;
    const same = t.headRepo === pg.hubFull;
    pg.win.act("pullCheckout", { remote: pg.hub.remote, number: t.number, branch: t.branch || null, same: same, refs: pg.site.refs }, {
      label: "Checking out #" + t.number, network: true,
      then: (res) => pg.win.say("On " + res.branch + (res.behind ? " — yours has moved apart from the pull request; left as it is" : ""), res.behind) });
  }

  function merge() {
    const t = pg.item;
    if (!t || !t.pull || t.state !== "open") return;
    if (t.draft) { pg.win.say("#" + t.number + " is a draft — mark it ready on " + pg.site.name + " first", true); return; }
    if (pg.whole && t.mergeable === false) {
      pg.win.say("#" + t.number + " conflicts with " + t.base + " — check it out and resolve them", true);
      return;
    }
    const go = (method, word) => pg.win.act(pg.op("Merge"), { full: pg.hubFull, number: t.number, method: method }, {
      repo: null, label: "Merging #" + t.number, network: true, refresh: false,
      then: () => { pg.win.say(word + " #" + t.number + " into " + t.base); if (pg) pg.reload(); pg.win.fetch(); } });
    pg.win.card_({ question: "Merge #" + t.number + " into " + t.base + "?", glyph: "", ink: Zenon.magenta,
      detail: t.title + (pg.whole ? "  ·  " + t.commits + (t.commits === 1 ? " commit" : " commits")
        + "  ·  +" + t.additions + " −" + t.deletions : "")
        + (pg.whole && t.mergeState === "blocked" ? "  ·  " + pg.site.name + " says it is blocked (a review or a check) — it may refuse" : ""),
      choices: [{ label: "Merge", ink: Zenon.magenta, run: () => go("merge", "Merged") },
                { label: "Squash", run: () => go("squash", "Squashed") },
                { label: "Rebase", run: () => go("rebase", "Rebased") },
                { label: "Cancel" }] });
  }

  function newIssue() {
    if (!pg.hub) return;
    pg.win.ask({ title: "A new issue on " + pg.hubFull, glyph: "",
      fields: [{ key: "title", label: "Title", hint: "What is wrong, or wanted" },
               { key: "body", label: "More", lines: true, optional: true, hint: "Steps, what you expected, what happened — markdown" }],
      verb: "Open issue",
      then: (v) => pg.win.act(pg.op("OpenIssue"), { full: pg.hubFull, title: v.title.trim(), body: v.body.trim() }, {
        repo: null, refresh: false, label: "Opening the issue", network: true,
        then: (r) => { pg.win.say("Opened #" + r.number); if (!pg) return; pg.wanted = r.number;
          if (pg.showing !== "open") pg.showing = "open"; else pg.reload(); } }) });
  }

  // Propose the branch you are on: into which of the repository's branches,
  // its title and words (the last commit's, to start from), a draft or not.
  // Pushed first when the forge does not have all of it yet.
  function newPull() {
    const b = pg.win.branch, hub = pg.hub, o = pg.win.origin;
    if (!hub) return;
    if (!b || !b.head) { pg.win.say("Not on a branch — switch to the one to propose", true); return; }
    // origin a fork of the hub: the head is said as "owner:branch"
    const fork = !!o && o.host === hub.host && o.full !== hub.full;
    const owner = fork ? o.full.split("/")[0] : "";
    const pushTo = (pg.win.remotes.find((r) => r.name === "origin") || pg.win.remotes[0] || {}).name;
    const unpushed = !b.upstream || b.ahead > 0;
    pg.win.act(pg.op("Branches"), { full: hub.full }, { repo: null, refresh: false, network: true,
      label: "Asking " + hub.full + " for its branches",
      failed: (err) => pg.win.fail("Could not ask " + pg.site.name, null, err),
      then: (br) => { if (!pg) return;
      const bases = br.branches.filter((n) => fork || n !== b.head);
      if (bases.length === 0) { pg.win.say("No other branch to propose it to", true); return; }
      pg.win.mgr.call("lastMessage", pg.win.root, {}, (ok2, m) => {
        if (!pg) return;
        const msg = ok2 ? String(m) : "";
        pg.win.ask({ title: "Propose " + b.head, glyph: "",
          detail: (fork ? owner + ":" : "") + b.head + "  →  " + hub.full + (unpushed ? "  ·  pushed first" : ""),
          fields: [{ key: "title", label: "Title", value: D.subjectOf(msg) },
                   { key: "body", label: "What it does", lines: true, optional: true,
                     value: msg.split("\n").slice(1).join("\n").trim(), hint: "Why, and what to look at — markdown" },
                   { key: "base", label: "Into", options: bases }],
          toggles: [{ key: "draft", label: "A draft — not ready for review yet", value: false }],
          verb: "Open " + pg.site.pull,
          then: (v) => {
            const go = () => pg.win.act(pg.op("OpenPull"), { full: hub.full, head: (fork ? owner + ":" : "") + b.head,
              base: v.base, title: v.title.trim(), body: v.body.trim(), draft: !!v.draft }, {
              repo: null, label: "Opening the " + pg.site.pull, network: true, refresh: false,
              then: (r) => { pg.win.say("Opened #" + r.number); if (!pg) return; pg.wanted = r.number;
                if (pg.showing !== "open") pg.showing = "open"; else pg.reload(); } });
            if (!unpushed) { go(); return; }
            pg.win.act("push", b.upstream ? {} : { remote: pushTo, branch: b.head, setUpstream: true },
                       { label: "Pushing " + b.head, network: true, then: go });
          } });
      });
    } });
  }

  function key(e) {
    const k = e.key;
    if (e.modifiers & Qt.ControlModifier) return false;
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(pg.sel + 1); return true; }
    if (k === Qt.Key_PageUp || k === Qt.Key_PageDown) {
      const d = (k === Qt.Key_PageUp ? -1 : 1) * threadFlick.height * 0.85;
      threadFlick.contentY = Math.max(0, Math.min(threadFlick.contentHeight - threadFlick.height, threadFlick.contentY + d));
      return true;
    }
    if (!pg.hub) return false;
    if (k === Qt.Key_S) { pg.showing = pg.showing === "open" ? "closed" : "open"; return true; }
    if (k === Qt.Key_N) { if (pg.pulls) pg.newPull(); else pg.newIssue(); return true; }
    if (!pg.item) return false;
    if (k === Qt.Key_R || k === Qt.Key_Return || k === Qt.Key_Enter) { pg.area = "reply"; return true; }
    if (k === Qt.Key_W) { pg.web(); return true; }
    if (k === Qt.Key_X) { pg.setOpen(!pg.open); return true; }
    if (pg.pulls && k === Qt.Key_C) { pg.checkout(); return true; }
    if (pg.pulls && k === Qt.Key_M) { pg.merge(); return true; }
    return false;
  }

  // ── the list ───────────────────────────────────────────────────────────
  Item {
    id: left
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: pg.win && pg.win.splits.forge ? pg.win.splits.forge : Math.round(Math.min(500, pg.width * 0.38))

    // open or closed, and whose: two small sets of choices side by side
    // (wrapping under each other only when the column is that narrow)
    Flow {
      id: seg
      // centered in the column; wrapping only when it is that narrow
      readonly property real want: openSeg.width + (whoSeg.visible ? 8 + whoSeg.width : 0)
      width: Math.min(parent.width - 24, want)
      x: Math.round((parent.width - width) / 2)
      y: 12
      spacing: 8
      visible: !!pg.hub
      Segments {
        id: openSeg
        options: [["open", "Open"], ["closed", "Closed"]]
        current: pg.showing
        onChose: (v) => pg.showing = v
      }
      // known once the account here is
      Segments {
        id: whoSeg
        visible: pg.me !== ""
        options: [["all", "All"], ["others", "Others"], ["mine", "Mine"]]
        current: pg.who
        onChose: (v) => pg.who = v
      }
    }
    // asking the forge: in the list's body, where the rows will be (user,
    // 2026-10-11 — beside the switches it read as one of them)
    Working {
      anchors.centerIn: list
      z: 5
      running: pg.loading
      visible: pg.loading
    }
    ListView {
      id: list
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: seg.bottom
      anchors.topMargin: 8
      anchors.bottom: parent.bottom
      clip: true
      bottomMargin: 8
      boundsBehavior: Flickable.StopAtBounds
      model: pg.rows
      readonly property int rowH: Math.round(Zenon.px(15) * 3.3)
      SelectBar { view: list; host: pg.win; index: pg.sel; on: pg.rows.length > 0; rowH: list.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
      delegate: Item {
        id: frow
        required property var modelData
        required property int index
        readonly property var r: frow.modelData
        readonly property var mark: D.forgeMark(frow.r)
        width: list.width
        height: list.rowH
        Text {
          id: fg
          x: 22
          width: 18
          anchors.verticalCenter: parent.verticalCenter
          text: frow.mark.glyph
          color: Zenon[frow.mark.ink]
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(16)
        }
        // its checks (CiDot), for an open pull request whose commit is known
        CiDot {
          id: prCi
          anchors.right: parent.right
          anchors.rightMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          c: { pg.win.mgr.ci; return frow.r.sha && pg.hub ? pg.win.mgr.ciOf(pg.hub.forge, pg.hub.full, frow.r.sha) : null; }
        }
        Column {
          anchors.left: fg.right
          anchors.leftMargin: 12
          anchors.right: prCi.visible ? prCi.left : parent.right
          anchors.rightMargin: prCi.visible ? 12 : 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 3
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: frow.r.title
            color: frow.index === pg.sel ? Zenon.ink : Zenon.accentSoft
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: "#" + frow.r.number + "  ·  " + frow.r.author + "  ·  " + D.ago(D.secondsOf(frow.r.updated), Date.now())
              + (frow.r.pull && frow.r.branch ? "  ·  " + frow.r.branch : "")
              + (frow.r.comments > 0 ? "  ·  " + frow.r.comments + (frow.r.comments === 1 ? " comment" : " comments") : "")
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.features: { "tnum": 1 }
            font.pixelSize: Zenon.px(13)
          }
        }
        MouseArea {
          anchors.fill: parent
          onClicked: { pg.area = "list"; pg.moveTo(frow.index); pg.win.focusKeys(); }
          onDoubleClicked: pg.web()
        }
        HoverHandler {
          onHoveredChanged: {
            if (hovered) { pg.peekRow = frow; pg.peek = frow.r; peekWait.restart(); }
            else if (pg.peekRow === frow) { pg.peekRow = null; peekWait.stop(); pg.peeking = false; }
          }
        }
      }
      EmptyMark {
        anchors.centerIn: parent
        visible: pg.rows.length === 0 && !pg.loading && pg.listError === "" && !!pg.hub
        word: "No " + pg.showing + " " + pg.noun + "s"
      }
    }
    ElasticScroll { anchors.fill: list; view: list }
    Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }

    // why there is no list: on no forge delphi knows, not signed in, or the forge failed
    Column {
      anchors.centerIn: parent
      width: parent.width - 60
      spacing: 14
      visible: !pg.hub || (pg.listError !== "" && !pg.loading)
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: !pg.hub ? "This repository has no remote on GitHub, GitLab or Codeberg" : pg.listError
        color: !pg.hub ? Zenon.accentMuted : Zenon.red
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
      DialogButton {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !!pg.hub && !pg.signInNeeded
        label: "Retry"
        onClicked: pg.reload()
      }
    }
  }
  // the seam between the list and the one chosen: dragged, it stays
  SeamGrip {
    frame: pg
    at: left.width
    min: 280
    max: pg.width - 380
    onMoved: (p) => pg.win.setSplit("forge", p)
    onReset: pg.win.setSplit("forge", 0)
  }

  // a pull request's or an issue's labels, as the forge colors them
  component Labels: Flow {
    id: labs
    property var labels: []
    spacing: 6
    visible: labs.labels.length > 0
    Repeater {
      model: labs.labels
      delegate: Rectangle {
        required property var modelData
        width: lab.implicitWidth + 18
        height: 22
        radius: height / 2
        color: Zenon.alpha(Qt.color(modelData.color), 0.18)
        border.width: 1
        border.color: Zenon.alpha(Qt.color(modelData.color), 0.6)
        Text {
          id: lab
          anchors.centerIn: parent
          text: modelData.name
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
    }
  }

  // ── the one chosen, whole ──────────────────────────────────────────────
  // a post: who, when, what — the description first, then each thing said
  component Post: Rectangle {
    id: post
    property string author: ""
    property string when: ""
    property string body: ""
    property string kind: "comment"     // comment | approved | changes | review | body
    width: parent ? parent.width : 0
    height: postCol.implicitHeight + 24
    radius: Zenon.windowRadius
    color: Zenon.wash(post.kind === "body" ? 0.05 : 0.03)
    border.width: 1
    border.color: post.kind === "approved" ? Zenon.alpha(Zenon.green, 0.5)
      : post.kind === "changes" ? Zenon.alpha(Zenon.yellow, 0.5) : Zenon.border
    Column {
      id: postCol
      x: 14
      y: 12
      width: parent.width - 28
      spacing: 8
      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.StyledText
        text: "<b>" + post.author + "</b>"
          + (post.kind === "approved" ? "  <font color='" + Zenon.green + "'>approved</font>"
            : post.kind === "changes" ? "  <font color='" + Zenon.yellow + "'>asked for changes</font>"
            : post.kind === "review" ? "  reviewed" : "")
          + "  <font color='" + Zenon.accentMuted + "'>·  " + D.ago(D.secondsOf(post.when), Date.now()) + "</font>"
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      // a Text, not a TextEdit: only a Text colors its links (a TextEdit
      // drew them in Qt's own blue)
      Text {
        width: parent.width
        visible: post.body.trim() !== "" || post.kind === "body"
        wrapMode: Text.Wrap
        textFormat: post.body.trim() === "" ? Text.PlainText : Text.MarkdownText
        text: post.body.trim() === "" ? "No description" : D.mdOf(post.body)
        color: post.body.trim() === "" ? Zenon.accentMuted : Zenon.accentSoft
        linkColor: Zenon.cyan
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
        onLinkActivated: (link) => Quickshell.execDetached(["xdg-open", link])
        HoverHandler { cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
      }
    }
  }

  Item {
    id: right
    anchors.left: left.right
    anchors.leftMargin: 1
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: replyBox.visible ? replyBox.top : parent.bottom

    Flickable {
      id: threadFlick
      anchors.fill: parent
      clip: true
      interactive: false
      contentWidth: width
      contentHeight: threadCol.implicitHeight + 40
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: threadCol
        x: 22
        y: 20
        width: threadFlick.width - 44
        spacing: 14
        visible: !!pg.item
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.StyledText
          text: pg.item ? pg.item.title.replace(/&/g, "&amp;").replace(/</g, "&lt;")
            + "  <font color='" + Zenon.accentMuted + "'>#" + pg.item.number + "</font>" : ""
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(20)
        }
        // its state, who opened it when, and for a pull request where to where
        Flow {
          width: parent.width
          spacing: 10
          Rectangle {
            readonly property var mark: D.forgeMark(pg.item)
            width: markRow.implicitWidth + 22
            height: 26
            radius: height / 2
            color: Zenon.alpha(Zenon[mark.ink], 0.14)
            border.width: 1
            border.color: Zenon.alpha(Zenon[mark.ink], 0.45)
            Row {
              id: markRow
              anchors.centerIn: parent
              spacing: 6
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.mark.glyph
                color: Zenon[parent.parent.mark.ink]
                font.family: Zenon.glyphFace
                font.pixelSize: Zenon.px(13)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.mark.word
                color: Zenon[parent.parent.mark.ink]
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(13)
              }
            }
          }
          Text {
            height: 26
            verticalAlignment: Text.AlignVCenter
            text: !pg.item ? "" : pg.item.author + " opened it " + D.ago(D.secondsOf(pg.item.created), Date.now())
              + (pg.item.pull && pg.item.branch ? "  ·  " + (pg.item.headRepo && pg.item.headRepo !== pg.hubFull ? pg.item.headRepo.split("/")[0] + ":" : "")
                + pg.item.branch + "  →  " + pg.item.base : "")
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
        }
        // a pull request's size, and whether it goes in cleanly
        Text {
          visible: pg.whole && pg.item.pull
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.StyledText
          text: !pg.whole || !pg.item.pull ? "" : pg.item.commits + (pg.item.commits === 1 ? " commit" : " commits")
            + "  ·  <font color='" + Zenon.green + "'>+" + pg.item.additions + "</font>"
            + " <font color='" + Zenon.red + "'>−" + pg.item.deletions + "</font>"
            + "  ·  " + pg.item.files + (pg.item.files === 1 ? " file" : " files")
            + (pg.item.state !== "open" ? ""
              : pg.item.mergeable === false ? "  ·  <font color='" + Zenon.red + "'>conflicts with " + pg.item.base + "</font>"
              : pg.item.mergeState === "blocked" ? "  ·  <font color='" + Zenon.yellow + "'>waiting on a review or a check</font>"
              : pg.item.mergeable === true ? "  ·  <font color='" + Zenon.green + "'>merges cleanly</font>" : "")
          color: Zenon.accentSoft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.features: { "tnum": 1 }
          font.pixelSize: Zenon.px(14)
        }
        Labels { width: parent.width; labels: pg.item ? pg.item.labels : [] }
        Post {
          visible: pg.whole
          author: pg.whole ? pg.item.author : ""
          when: pg.whole ? pg.item.created : ""
          body: pg.whole ? pg.item.body : ""
          kind: "body"
        }
        // GitLab keeps a discussion for those signed in, even when public
        Text {
          visible: pg.whole && !!pg.item.signInToRead
          width: parent.width
          wrapMode: Text.Wrap
          text: "Sign in to " + pg.site.name + " to read what was said on it."
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
        Repeater {
          model: pg.whole ? pg.item.said : []
          delegate: Post {
            required property var modelData
            author: modelData.author
            when: modelData.when
            body: modelData.body
            kind: modelData.kind
          }
        }
        Working {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: !pg.whole && pg.threadLoading
          running: visible
        }
      }
    }
    ElasticScroll { anchors.fill: threadFlick; view: threadFlick }
    Scrollbar { flick: threadFlick; anchors.right: threadFlick.right; anchors.top: threadFlick.top; anchors.bottom: threadFlick.bottom }
  }

  // ── saying something ───────────────────────────────────────────────────
  Item {
    id: replyBox
    anchors.left: left.right
    anchors.leftMargin: 1
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 150
    visible: pg.whole
    Rectangle { width: parent.width; height: 1; color: Zenon.border }
    MessageWell {
      id: reply
      x: 14
      y: 14
      width: parent.width - 28
      height: parent.height - 28
      footRoom: send.height + 8
      ghost: "Say something on #" + (pg.item ? pg.item.number : "") + " — markdown; ctrl return sends"
      passKeys: (e) => pg.win.key(e)
      onFocusedChanged: if (reply.focused) pg.area = "reply"
      onSubmitted: pg.send()
      onEscaped: pg.area = "list"
      onTabbed: pg.area = "list"
      // in the well's corner, a part of the field (user, 2026-10-11: beside
      // it, it sat there out of proportion to it)
      DialogButton {
        id: send
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        label: "Send"
        ink: Zenon.cyan
        ready: reply.text.trim() !== ""
        primary: reply.text.trim() !== ""
        onClicked: pg.send()
      }
    }
  }
  Bubble {
    id: peekBubble
    window: pg.win
    target: pg.peekRow
    shown: pg.peeking && !!pg.peek && !!pg.row && pg.peek.number !== pg.row.number && !pg.win.carding
    cardWidth: 440
    readonly property var mark: D.forgeMark(pg.peek)
    Text {
      width: 412
      wrapMode: Text.Wrap
      maximumLineCount: 3
      elide: Text.ElideRight
      text: pg.peek ? pg.peek.title : ""
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(15)
    }
    Text {
      width: 412
      wrapMode: Text.Wrap
      textFormat: Text.StyledText
      text: !pg.peek ? "" : "<font color='" + Zenon[peekBubble.mark.ink] + "'>" + peekBubble.mark.word + "</font>"
        + "  ·  #" + pg.peek.number + " by " + pg.peek.author + "  ·  " + D.ago(D.secondsOf(pg.peek.created), Date.now())
        + (pg.peek.pull && pg.peek.branch ? "  ·  " + pg.peek.branch + " → " + pg.peek.base : "")
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
    Labels { width: 412; labels: pg.peek ? pg.peek.labels : [] }
    Text {
      width: 412
      wrapMode: Text.Wrap
      maximumLineCount: 6
      elide: Text.ElideRight
      text: pg.peek ? (D.plainOf(pg.peek.excerpt) || "No description") : ""
      color: pg.peek && pg.peek.excerpt ? Zenon.accentSoft : Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
    Text {
      visible: !!pg.peek && pg.peek.comments > 0
      text: pg.peek ? pg.peek.comments + (pg.peek.comments === 1 ? " comment" : " comments") + "  ·  updated " + D.ago(D.secondsOf(pg.peek.updated), Date.now()) : ""
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
  }
}
