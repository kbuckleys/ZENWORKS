// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE AUR PACKAGE — a repository with a remote on aur.archlinux.org is a
// package's recipe (core/aur.py). This page sets what the AUR shows of it
// (its version, votes, popularity, an out-of-date flag) beside the recipe
// here, and takes the steps a release of it takes. Release (r) takes them
// all, in order, ticked off as they go and stopped at the first that fails
// (user, 2026-10-26: one pass, not four buttons and a trip to Changes):
//
//   the tag     on the source (the PKGBUILD's url=): checksums of a tag not
//               pushed yet are of the wrong tarball, or none. Not there:
//               asked whether to go on (a project may tag otherwise). A
//               url= that is no repository (a home page): not checked.
//   v version   a new one (pkgrel 1), or the same again (pkgrel + 1) — left
//               as it is when that release is not on the AUR yet
//   c checksums the source fetched for them (updpkgsums)
//   s .SRCINFO  written from the PKGBUILD
//   b build     from the real source, then namcap on the recipe and the package
//
// Each step has its key too. Publish (p) commits the recipe and pushes it
// to the AUR, behind a card: the push is public at once, so it is asked,
// never part of Release; before it, the SSH keys are looked at, so a push
// that has no key for the AUR says so before it starts, not after the
// commit. The AUR's RPC and pages lag a push by minutes;
// the page says so and asks again every 30 s until they catch up.
//
//   o           the package's page on the AUR

import QtQuick
import "../morpheus"
import "delphi.js" as D

Item {
  id: pg
  property var win: null
  readonly property var edgeViews: [pane]

  readonly property var a: pg.win ? pg.win.aur : null
  onAChanged: if (pg.a) pg.reload()
  readonly property string title: pg.a ? pg.a.pkg : "AUR package"
  readonly property string subtitle: !pg.info ? "Reading the recipe…"
    : !pg.info.aur ? (pg.info.error !== "" ? pg.info.error : "Not on the AUR yet: the first push publishes it")
    : "On the AUR at " + pg.info.aur.version
  readonly property var hints: [["r", "release"], ["p", "publish"], ["v", "version"], ["c", "checksums"], ["s", ".SRCINFO"], ["b", "build"], ["o", "AUR page"]]
  readonly property var buttons: [
    { label: "Build and check", visible: !!pg.info && !pg.running, run: () => pg.build() },
    { label: "Publish…", ink: Zenon.cyan, primary: pg.ready, visible: !!pg.info && !pg.running && pg.ready, run: () => pg.publish() },
    { label: "Release…", ink: Zenon.cyan, primary: !pg.ready, visible: !!pg.info && !pg.running, run: () => pg.release() },
  ]
  function takeFocus() { if (pg.win) pg.win.focusKeys(); }

  property var info: null
  // the last build: { package, notes, namcap } or null
  property var built: null
  // quiet: the lag watch's asking again — a failure there is not a card
  function reload(quiet) {
    // no AUR remote: the window is between repositories (one opened from
    // here, its remotes not read yet), and this page is on its way out
    if (!pg.win || pg.win.root === "" || !pg.a) return;
    pg.win.mgr.call("aurInfo", pg.win.root, { pkg: pg.a ? pg.a.pkg : "" }, (ok, res, err) => { if (!pg) return;
      if (ok) pg.info = res;
      else if (!quiet) pg.win.fail("The recipe could not be read", null, err);
    });
  }
  Component.onCompleted: Qt.callLater(pg.reload)
  // a release of the source just published on its Releases page, followed
  // here (ReleasesPage.offerAur): its version released once the recipe is read
  // — taken a moment later, by the page that stays: the window can make
  // this page twice while it moves between repositories, and the first,
  // gone by then, would have taken it with it
  onInfoChanged: if (pg.info && pg.win && pg.win.mgr.aurWant) Qt.callLater(pg.takeWant)
  function takeWant() {
    const w = pg.win ? pg.win.mgr.aurWant : null;
    if (!pg.info || !w || w.root !== pg.win.root || pg.running) return;
    pg.win.mgr.aurWant = null;
    pg.releaseOf(w.version);
  }
  Connections {
    target: pg.win
    function onRefsEpochChanged() { pg.reload(); }
  }

  readonly property var r: pg.info ? pg.info.recipe : null
  readonly property string here: pg.r ? pg.r.pkgver + "-" + pg.r.pkgrel : ""
  readonly property string shown: pg.info && pg.info.aur ? pg.info.aur.version : ""

  // ── WHERE THE PUSH IS ──────────────────────────────────────────────────
  // The AUR takes master only. Pushed = its copy of master (as last fetched
  // or pushed) is the commit here; the AUR showing another version then is
  // its lag, not a push that went wrong.
  readonly property var head: pg.win ? pg.win.branch : null
  readonly property string remoteSha: {
    if (!pg.win || !pg.a) return "";
    const e = pg.win.refs.remote.find((x) => x.name === pg.a.remote + "/master");
    return e ? e.sha : "";
  }
  readonly property bool pushed: !!pg.head && !!pg.head.oid && pg.remoteSha === pg.head.oid
  // only a recipe with nothing changed since that commit: one whose new
  // version is not committed yet has its old commit on the AUR, and
  // nothing there to catch up with (user, 2026-10-26)
  readonly property bool lagging: !!pg.r && pg.pushed && !pg.dirty && pg.shown !== pg.here
  // the recipe has something the AUR has not: changed here, or committed
  // and not pushed — what Publish is for
  readonly property bool dirty: !!pg.win && !!pg.win.st && (pg.win.st.staged.length + pg.win.st.unstaged.length) > 0
  readonly property bool ready: !!pg.r && pg.r.srcinfo === "ok" && pg.shown !== pg.here && (pg.dirty || !pg.pushed)
  Timer {
    interval: 30000
    repeat: true
    running: pg.lagging && pg.visible && pg.lagTries < 40
    onTriggered: { pg.lagTries++; pg.reload(true); }
  }
  property int lagTries: 0
  onLaggingChanged: if (pg.lagging) pg.lagTries = 0; else if (pg.lagTries > 0 && pg.shown === pg.here) pg.win.say("The AUR shows " + pg.here + " now")

  function setVersion() {
    pg.win.ask({ title: "The version", glyph: "",
      detail: "A new version starts at release 1. The same version again counts the release up: a change to the recipe only.",
      fields: [{ key: "version", label: "Version", value: pg.r ? pg.r.pkgver : "", hint: "0.0.6" }],
      verb: "Set",
      then: (v) => pg.win.act("aurVersion", { version: v.version.trim() }, { label: "Setting the version",
        then: (res) => { pg.win.say("Now " + res.pkgver + "-" + res.pkgrel + " — checksums next"); pg.reload(); } }) });
  }
  function sums() {
    pg.win.act("aurSums", {}, { label: "Fetching for the checksums", network: true,
      said: "Checksums updated", then: () => pg.reload() });
  }
  function srcinfo() {
    pg.win.act("aurSrcinfo", {}, { label: "Writing .SRCINFO", said: ".SRCINFO written", then: () => pg.reload() });
  }
  function build() {
    pg.built = null;
    pg.win.act("aurBuild", {}, { label: "Building", network: true,
      then: (res) => {
        pg.built = res;
        pg.win.say(!res.namcap ? "Built — namcap is not installed, so nothing was checked"
          : res.notes.length === 0 ? "Built, and namcap has nothing to say" : "Built — namcap has " + res.notes.length + " to read");
      } });
  }

  // ── RELEASE: EVERY STEP, IN ORDER ──────────────────────────────────────
  // run = { version, steps: [{ id, label, state: wait|run|ok|skip|bad, note }] }
  property var run: null
  readonly property bool running: !!pg.run && pg.run.steps.some((x) => x.state === "run" || x.state === "wait")
    && !pg.run.steps.some((x) => x.state === "bad")
  function mark(id, state, note) {
    if (!pg.run) return;
    pg.run = { version: pg.run.version, steps: pg.run.steps.map((x) => x.id === id
      ? { id: x.id, label: x.label, state: state, note: note !== undefined ? note : x.note } : x) };
  }
  function release() {
    if (pg.running) return;
    const ask = (tags) => {
      const newest = tags.length > 0 ? tags[0].replace(/^[vV]/, "") : "";
      pg.win.ask({ title: "Release a version", glyph: "\uF303",
        detail: "Checks the tag is on the source, sets the version, fetches the checksums, writes .SRCINFO, then builds and checks the package. Nothing is published: Publish does that, after.",
        fields: [{ key: "version", label: "Version", value: newest || (pg.r ? pg.r.pkgver : ""),
                   hint: newest !== "" ? "the newest tag is " + tags[0] : "0.0.6" }],
        verb: "Release",
        then: (v) => pg.releaseOf(v.version.trim()) });
    };
    pg.win.act("aurTag", { version: "" }, { label: "Reading the tags", network: true, refresh: false,
      then: (res) => ask(res.tags), failed: () => ask([]) });
  }
  function releaseOf(v) {
    if (v === "") return;
    // the same version, a release of it not on the AUR yet: that release
    // is still the one being made (a second Release does not count it up)
    const keep = !!pg.r && v === pg.r.pkgver && pg.shown !== pg.here;
    pg.built = null;
    pg.run = { version: v, steps: [
      { id: "tag", label: "Tag", state: "wait", note: "" },
      { id: "version", label: "Version", state: "wait", note: "" },
      { id: "sums", label: "Checksums", state: "wait", note: "" },
      { id: "srcinfo", label: ".SRCINFO", state: "wait", note: "" },
      { id: "build", label: "Build", state: "wait", note: "" },
    ] };
    // a failed build's first line says only that: its last lines with it
    const failed = (id) => (err) => {
      const l = D.errorText(String(err && err.error || "")).split("\n").filter((x) => x.trim() !== "");
      pg.mark(id, "bad", l.length > 6 ? [l[0]].concat(l.slice(-5)).join("\n") : l.join("\n"));
    };
    const stopped = (id) => () => pg.mark(id, "bad", "Stopped");
    const step = (id, op, args, label, after) => {
      pg.mark(id, "run");
      pg.win.act(op, args, { label: label, network: id === "tag" || id === "sums" || id === "build",
        failed: failed(id), stopped: stopped(id),
        then: (res) => { if (!pg || !pg.run) return; after(res); } });
    };
    const rest = () => {
      const sums = () => step("sums", "aurSums", {}, "Fetching for the checksums", () => {
        pg.mark("sums", "ok", "Fetched fresh");
        step("srcinfo", "aurSrcinfo", {}, "Writing .SRCINFO", () => {
          pg.mark("srcinfo", "ok", "Written from the PKGBUILD");
          step("build", "aurBuild", {}, "Building", (b) => {
            pg.built = b;
            pg.mark("build", "ok", !b.namcap ? "Built — namcap is not installed"
              : b.notes.length === 0 ? "Built, and namcap has nothing to say" : "Built — namcap has " + b.notes.length + " to read");
            pg.reload();
            pg.win.say("Ready to publish " + pg.here + " — p, or Publish");
          });
        });
      });
      if (keep) { pg.mark("version", "skip", pg.here + ", as it is: not on the AUR yet"); sums(); }
      else step("version", "aurVersion", { version: v }, "Setting the version", (res) => {
        pg.mark("version", "ok", res.pkgver + "-" + res.pkgrel);
        sums();
      });
    };
    step("tag", "aurTag", { version: v }, "Checking the tag", (res) => {
      if (!res.checked) { pg.mark("tag", "skip", res.why + " — not checked"); rest(); return; }
      if (res.tag !== "") { pg.mark("tag", "ok", res.tag + " is on " + res.url); rest(); return; }
      // not there: most likely not pushed yet — but a project may tag its
      // versions otherwise (release-1.2), so it is asked, not refused
      // marked stopped while asked: a card put away (Esc) is a Stop
      pg.mark("tag", "bad", "No tag " + v + " on " + res.url + " — tag and push the source first");
      pg.win.card_({ question: "No tag " + v + " on the source", glyph: "\uF303", ink: Zenon.yellow,
        detail: res.url + " has no tag " + v + (res.tags.length > 0 ? " (its newest is " + res.tags[0] + ")" : "")
          + ". If it is not pushed yet, the checksums would be of the wrong files, or none. Tagged otherwise, go on.",
        choices: [{ label: "Stop", ink: Zenon.cyan },
                  { label: "Go on anyway", ink: Zenon.yellow, run: () => { pg.mark("tag", "skip", "No tag " + v + " — gone on without it"); rest(); } }] });
    });
  }

  // ── PUBLISH: THE COMMIT AND THE PUSH ───────────────────────────────────
  function publish() {
    if (!pg.r || !pg.a) return;
    if (pg.r.srcinfo !== "ok") { pg.win.say(".SRCINFO is not in step with the PKGBUILD — write it first (s)", true); return; }
    if (!pg.head || !pg.head.head) { pg.win.say("Not on a branch — nothing to push", true); return; }
    pg.win.mgr.call("sshStatus", null, {}, (ok, st) => { if (!pg) return; pg.publishWith(ok ? st : null); });
  }
  // What ssh will offer the AUR, from the keys page's own reading: a key
  // set up for it in ~/.ssh/config, one of ssh's default names, or one in
  // the agent. None: said before anything is committed, with the way to
  // make one. One whose passphrase will be asked: said on the card.
  readonly property var defaultKeys: ["id_rsa", "id_ecdsa", "id_ecdsa_sk", "id_ed25519", "id_ed25519_sk"]
  function publishWith(st) {
    const keys = st ? st.keys.filter((k) => k.private) : [];
    const forAur = keys.filter((k) => k.hosts.indexOf("aur.archlinux.org") >= 0);
    const offered = forAur.length > 0 ? forAur : keys.filter((k) => pg.defaultKeys.indexOf(k.name) >= 0 || k.loaded);
    if (st && offered.length === 0) {
      pg.win.card_({ question: "No SSH key for the AUR", glyph: "\uF43D", ink: Zenon.yellow,
        detail: "The AUR takes pushes over SSH only, with a key added to your AUR account (My Account → SSH Public Key). Make one, or pick one you have, on SSH keys.",
        choices: [{ label: "SSH keys", ink: Zenon.cyan, run: () => pg.win.setPage("keys") },
                  { label: "Push anyway", ink: Zenon.accentMuted, run: () => pg.publishAsk("") }] });
      return;
    }
    const asks = offered.length > 0 && offered.every((k) => k.passphrase && !k.loaded);
    pg.publishAsk(asks ? " Your key's passphrase is asked for during the push." : "");
  }
  function publishAsk(note) {
    const name = pg.r.pkgname || pg.a.pkg;
    const words = pg.r.pkgrel === "1" ? name + " " + pg.r.pkgver : name + " " + pg.here;
    pg.win.ask({ title: "Publish " + name + " " + pg.here, glyph: "\uF303", ink: Zenon.cyan,
      detail: "Commits the recipe and pushes it to the AUR. The push is public at once: paru and yay offer it within minutes."
        + (pg.shown !== "" ? " The AUR has " + pg.shown + " now." : " It is the package's first push.") + note,
      fields: [{ key: "message", label: "Commit message", value: words }],
      verb: "Publish",
      then: (v) => pg.win.act("aurCommit", { message: v.message }, { label: "Committing the recipe",
        then: (res) => {
          if (!res.committed && pg.pushed) { pg.win.say("Nothing to publish — the AUR has this commit"); return; }
          const b = pg.head.head;
          pg.win.pushShow([pg.a.remote]);
          pg.win.act("push", { remote: pg.a.remote, branch: b === "master" ? "master" : b + ":master", setUpstream: !pg.head.upstream },
            { label: "Pushing to the AUR", network: true,
              said: "Pushed " + pg.here + " — the AUR shows it in a few minutes",
              stopped: () => pg.win.pushEnd(false, true), done: (ok) => { pg.win.pushEnd(ok); if (ok) pg.run = null; } });
        } }) });
  }

  function key(e) {
    if (e.modifiers & Qt.ControlModifier) return false;
    const k = e.key;
    if (!pg.info) return false;
    if (k === Qt.Key_R) { pg.release(); return true; }
    if (k === Qt.Key_P) { pg.publish(); return true; }
    if (pg.running && (k === Qt.Key_V || k === Qt.Key_C || k === Qt.Key_S || k === Qt.Key_B)) {
      pg.win.say("A release is under way", true);
      return true;
    }
    if (k === Qt.Key_V) { pg.setVersion(); return true; }
    if (k === Qt.Key_C) { pg.sums(); return true; }
    if (k === Qt.Key_S) { pg.srcinfo(); return true; }
    if (k === Qt.Key_B) { pg.build(); return true; }
    if (k === Qt.Key_O && pg.a) { Qt.openUrlExternally(pg.a.web); return true; }
    return false;
  }

  function when(secs) {
    return secs ? new Date(secs * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat) : "";
  }
  // [label, value, ink] rows for one side
  readonly property var aurRows: !pg.info || !pg.info.aur ? [] : [
    ["Version", pg.info.aur.version + (pg.lagging ? "   ·   catching up with " + pg.here : ""), pg.lagging ? Zenon.yellow : Zenon.ink],
    ["Flagged", pg.info.aur.outOfDate ? "Out of date since " + pg.when(pg.info.aur.outOfDate) : "No", pg.info.aur.outOfDate ? Zenon.red : Zenon.accentMuted],
    ["Votes", String(pg.info.aur.votes), Zenon.ink],
    ["Popularity", Number(pg.info.aur.popularity).toFixed(2), Zenon.ink],
    ["Maintainer", pg.info.aur.maintainer || "None — orphaned", pg.info.aur.maintainer ? Zenon.ink : Zenon.yellow],
    ["Last update", pg.when(pg.info.aur.modified), Zenon.ink],
  ]
  readonly property var hereRows: !pg.r ? [] : [
    ["Version", pg.here + (pg.shown === pg.here ? "   ·   as on the AUR"
      : pg.lagging ? "   ·   pushed — the AUR shows it in a few minutes"
      : pg.info.aur || pg.dirty || !pg.pushed ? "   ·   not pushed yet" : ""),
      pg.shown === pg.here ? Zenon.ink : pg.lagging ? Zenon.yellow : Zenon.cyan],
    [".SRCINFO", pg.r.srcinfo === "ok" ? "In step with the PKGBUILD" : pg.r.srcinfo === "missing" ? "Missing — write it"
      : pg.r.srcinfo === "stale" ? "Behind the PKGBUILD — write it" : "Could not be checked",
      pg.r.srcinfo === "ok" ? Zenon.accentMuted : Zenon.yellow],
    ["Tools", ["makepkg", "updpkgsums", "namcap"].filter((t) => !pg.info.tools[t]).length === 0 ? "makepkg, updpkgsums, namcap"
      : "Missing: " + ["makepkg", "updpkgsums", "namcap"].filter((t) => !pg.info.tools[t]).join(", ") + " (pacman-contrib, namcap)",
      ["makepkg", "updpkgsums", "namcap"].every((t) => pg.info.tools[t]) ? Zenon.accentMuted : Zenon.yellow],
  ]

  Flickable {
    id: pane
    anchors.fill: parent
    contentHeight: body.implicitHeight + 40
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: body
      x: 28
      y: 20
      width: pane.width - 56
      spacing: 6

      SectionLabel { text: "On the AUR" }
      Repeater {
        model: pg.aurRows
        delegate: Row {
          required property var modelData
          spacing: 16
          Text { width: Zenon.px(15) * 8; text: modelData[0]; color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(14) }
          Text { text: modelData[1]; color: modelData[2]; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(15) }
        }
      }
      Text {
        visible: !!pg.info && !pg.info.aur
        text: pg.info && pg.info.error !== "" ? pg.info.error : "Nothing yet — the first push publishes it."
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      Text {
        visible: !!pg.a
        text: pg.a ? pg.a.web : ""
        color: Zenon.link
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(pg.a.web) }
      }

      Item { width: 1; height: 14 }
      SectionLabel { text: "Here" }
      Repeater {
        model: pg.hereRows
        delegate: Row {
          required property var modelData
          spacing: 16
          Text { width: Zenon.px(15) * 8; text: modelData[0]; color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(14) }
          Text { text: modelData[1]; color: modelData[2]; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(15) }
        }
      }

      Item { width: 1; height: 14; visible: !!pg.run }
      SectionLabel { visible: !!pg.run; text: pg.run ? "Release " + pg.run.version : "" }
      Repeater {
        model: pg.run ? pg.run.steps : []
        delegate: Row {
          id: srow
          required property var modelData
          spacing: 16
          readonly property color mark: modelData.state === "ok" ? Zenon.green : modelData.state === "bad" ? Zenon.red
            : modelData.state === "run" ? Zenon.cyan : Zenon.accentMuted
          Text { width: Zenon.px(15) * 8; text: srow.modelData.label; color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(14) }
          Text {
            width: Zenon.px(15) * 1.4
            text: srow.modelData.state === "ok" ? "\uF00C" : srow.modelData.state === "bad" ? "\uF00D"
              : srow.modelData.state === "run" ? "\uF192" : srow.modelData.state === "skip" ? "\uF068" : "\uF10C"
            color: srow.mark
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(14)
          }
          Text {
            width: body.width - Zenon.px(15) * 9.4 - 32
            wrapMode: Text.Wrap
            text: srow.modelData.note !== "" ? srow.modelData.note : srow.modelData.state === "run" ? "Under way…" : ""
            color: srow.modelData.state === "bad" ? Zenon.red : srow.modelData.state === "wait" ? Zenon.accentMuted : Zenon.ink
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
        }
      }

      Item { width: 1; height: 14; visible: !!pg.built }
      SectionLabel { visible: !!pg.built; text: pg.built ? "Built: " + pg.built.package : "" }
      Text {
        visible: !!pg.built
        width: body.width
        wrapMode: Text.Wrap
        text: !pg.built ? "" : !pg.built.namcap ? "namcap is not installed, so nothing was checked."
          : pg.built.notes.length === 0 ? "namcap has nothing to say." : pg.built.notes.join("\n")
        color: pg.built && pg.built.notes.length > 0 ? Zenon.yellow : Zenon.accentMuted
        font.family: Zenon.faceMono
        font.pixelSize: Zenon.px(13)
      }
      Text {
        topPadding: 8
        text: pg.ready ? "Publish (p) commits the recipe and pushes it to the AUR." : ""
        visible: !!pg.built && pg.ready
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }
  }
  ElasticScroll { anchors.fill: pane; view: pane }
  Scrollbar { flick: pane; anchors.right: pane.right; anchors.top: pane.top; anchors.bottom: pane.bottom }
}
