// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE AUR PACKAGE — a repository with a remote on aur.archlinux.org is a
// package's recipe (core/aur.py). This page sets what the AUR shows of it
// (its version, votes, popularity, an out-of-date flag) beside the recipe
// here, and takes the steps a release of it takes, in order:
//
//   v version   a new one (pkgrel 1), or the same again (pkgrel + 1)
//   c checksums the source fetched for them (updpkgsums)
//   s .SRCINFO  written from the PKGBUILD
//   b build     from the real source, then namcap on the recipe and the package
//   o           the package's page on the AUR
//
// Then commit and push, on Changes, as for any repository: the push is
// what publishes, and it stays yours.

import QtQuick
import "../morpheus"

Item {
  id: pg
  property var win: null
  readonly property var edgeViews: [pane]

  readonly property var a: pg.win ? pg.win.aur : null
  readonly property string title: pg.a ? pg.a.pkg : "AUR package"
  readonly property string subtitle: !pg.info ? "Reading the recipe…"
    : !pg.info.aur ? (pg.info.error !== "" ? pg.info.error : "Not on the AUR yet: the first push publishes it")
    : "On the AUR at " + pg.info.aur.version
  readonly property var hints: [["v", "version"], ["c", "checksums"], ["s", ".SRCINFO"], ["b", "build"], ["o", "AUR page"]]
  readonly property var buttons: [
    { label: "Version…", visible: !!pg.info, run: () => pg.setVersion() },
    { label: "Checksums", visible: !!pg.info, run: () => pg.sums() },
    { label: ".SRCINFO", visible: !!pg.info, run: () => pg.srcinfo() },
    { label: "Build and check", ink: Zenon.cyan, primary: true, visible: !!pg.info, run: () => pg.build() },
  ]
  function takeFocus() { if (pg.win) pg.win.focusKeys(); }

  property var info: null
  // the last build: { package, notes, namcap } or null
  property var built: null
  function reload() {
    if (!pg.win || pg.win.root === "") return;
    pg.win.mgr.call("aurInfo", pg.win.root, { pkg: pg.a ? pg.a.pkg : "" }, (ok, res, err) => { if (!pg) return;
      if (ok) pg.info = res;
      else pg.win.fail("The recipe could not be read", null, err);
    });
  }
  Component.onCompleted: Qt.callLater(pg.reload)
  Connections {
    target: pg.win
    function onRefsEpochChanged() { pg.reload(); }
  }

  readonly property var r: pg.info ? pg.info.recipe : null
  readonly property string here: pg.r ? pg.r.pkgver + "-" + pg.r.pkgrel : ""

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
    pg.win.act("aurBuild", {}, { label: "The build", network: true,
      then: (res) => {
        pg.built = res;
        pg.win.say(res.notes.length === 0 ? "Built, and namcap has nothing to say" : "Built — namcap has " + res.notes.length + " to read");
      } });
  }

  function key(e) {
    if (e.modifiers & Qt.ControlModifier) return false;
    const k = e.key;
    if (!pg.info) return false;
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
    ["Version", pg.info.aur.version, Zenon.ink],
    ["Flagged", pg.info.aur.outOfDate ? "Out of date since " + pg.when(pg.info.aur.outOfDate) : "No", pg.info.aur.outOfDate ? Zenon.red : Zenon.accentMuted],
    ["Votes", String(pg.info.aur.votes), Zenon.ink],
    ["Popularity", Number(pg.info.aur.popularity).toFixed(2), Zenon.ink],
    ["Maintainer", pg.info.aur.maintainer || "None — orphaned", pg.info.aur.maintainer ? Zenon.ink : Zenon.yellow],
    ["Last update", pg.when(pg.info.aur.modified), Zenon.ink],
  ]
  readonly property var hereRows: !pg.r ? [] : [
    ["Version", pg.here + (pg.info.aur && pg.info.aur.version === pg.here ? "   ·   as on the AUR"
      : pg.info.aur ? "   ·   not pushed yet" : ""), pg.info.aur && pg.info.aur.version !== pg.here ? Zenon.cyan : Zenon.ink],
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
        visible: !!pg.built
        topPadding: 8
        text: "Commit and push on Changes to publish it."
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
