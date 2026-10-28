// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TIDY'S WINDOW — one page of cards, System Journal's overview in shape,
// running up under the head and down under the hints, frosted (ScrollEdge):
//
//   Package cache     old versions of what is installed, and of what is not
//   Unused packages   installed as a dependency, needed by nothing now
//   System journal    shrunk to the last 200 MiB
//   Caches            ~/.cache, a directory each, ticked to go
//   Downloads         big, or old and not small
//   Duplicates        the same bytes twice in your own directories; the
//                     oldest copy of each is never ticked
//   Trash             where everything above goes; emptied in Terminus
//
//   ctrl r   ask again      esc   closes

import QtQuick
import Quickshell
import "../morpheus"
import "../morpheus/controls" as Ctl
import "../terminus"
import "../hermes"
import "../terminus/terminus.js" as Terminus
import "hygieia.js" as H

FloatingWindow {
  id: tw
  title: "hygieia"
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: 1040
  implicitHeight: 820
  minimumSize: Qt.size(760, 520)

  property var mgr: null
  readonly property var ov: tw.mgr ? tw.mgr.overview : H.parseOverview("")
  readonly property string home: Quickshell.env("HOME")
  readonly property real now: Date.now() / 1000

  onVisibleChanged: if (!tw.visible) Qt.callLater(() => { if (tw.mgr) tw.mgr.retire(tw); tw.destroy(); })
  onClosed: tw.visible = false
  Component.onCompleted: if (tw.mgr) tw.mgr.scan()

  readonly property int headH: 60
  readonly property Item headItem: head
  readonly property Item footItem: foot

  // ── WHAT IS TICKED: path -> true ────────────────────────────────────
  property var pickCaches: ({})
  property var pickDl: ({})
  property var pickDupes: ({})
  function flip(name, path) {
    const next = Object.assign({}, tw[name]);
    if (next[path]) delete next[path]; else next[path] = true;
    tw[name] = next;
  }
  function picked(name) { return Object.keys(tw[name]); }
  readonly property var dupeGroups: tw.mgr ? tw.mgr.dupes : []
  onDupeGroupsChanged: tw.pickDupes = H.dupePicks(tw.dupeGroups)
  // a scan again drops what is gone from the ticks
  onOvChanged: {
    const keep = (picks, list) => { const out = {}; for (const x of list) if (picks[x.path]) out[x.path] = true; return out; };
    tw.pickCaches = keep(tw.pickCaches, tw.ov.caches.dirs);
    tw.pickDl = keep(tw.pickDl, tw.ov.downloads.files);
  }
  function bytesOf(list, picks) { return list.filter((x) => picks[x.path]).reduce((a, x) => a + x.bytes, 0); }
  function size(n) { return Terminus.formatSize(n); }

  // ── WHAT WAS JUST DONE, SAID ONCE ─────────────────────────────────────
  Connections {
    target: tw.mgr
    function onSaid(words, bad) { saidBox.say(words, bad); }
  }
  readonly property bool busy: !!tw.mgr && tw.mgr.busy !== ""

  // ── FOR GOOD, ASKED TWICE ───────────────────────────────────────────
  // A Delete button's first click arms it (its label asks); a second
  // within a few seconds does it. `arming` names which button is armed.
  property string arming: ""
  Timer { id: disarm; interval: 4000; onTriggered: tw.arming = "" }
  function twice(kind, go) {
    if (tw.arming === kind) { tw.arming = ""; disarm.stop(); go(); return; }
    tw.arming = kind;
    disarm.restart();
  }

  Item {
    id: keys
    focus: true
    Keys.onPressed: (e) => {
      e.accepted = true;
      if (e.key === Qt.Key_Escape) { tw.visible = false; return; }
      if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_R) { tw.mgr.scan(); return; }
      e.accepted = false;
    }
  }

  Item {
    id: stage
    anchors.fill: parent
    Rectangle { z: -1; anchors.fill: parent; color: Zenon.layerBg }

    // ── the head ─────────────────────────────────────────────────────────
    Item {
      id: head
      z: 3
      anchors.left: parent.left
      anchors.right: parent.right
      height: tw.headH
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
      Column {
        x: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
          text: "Tidy"
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(17)
        }
        Text {
          text: !tw.ov.known ? (tw.mgr && tw.mgr.scanning ? "Looking…" : "")
            : H.reclaimable(tw.ov) > 0 ? tw.size(H.reclaimable(tw.ov)) + " could be given back without a second look"
            : "Nothing that needs a second look"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      BusyButton {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: 32
        glyph: true
        label: "\u{F0450}"
        busy: !!tw.mgr && tw.mgr.scanning
        onClicked: tw.mgr.scan()
      }
    }

    // ── the page ─────────────────────────────────────────────────────────
    Item {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: head.bottom
      anchors.bottom: foot.top

      Flickable {
        id: pageFlick
        anchors.fill: parent
        contentHeight: col.implicitHeight + 48
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
          id: col
          x: 28
          y: 24
          width: body.width - 56
          spacing: 16

          // ── the package cache ───────────────────────────────────────
          HermesCard {
            glyph: "\u{F03D6}"
            glyphInk: H.pkgcacheBytes(tw.ov.pkgcache) > 0 ? Zenon.cyan : Zenon.accentMuted
            title: "Package cache"
            note: tw.ov.known ? tw.size(tw.ov.pkgcache.bytes) + " in /var/cache/pacman/pkg" : ""
            Words {
              text: !tw.ov.pkgcache.tool
                ? "Every package pacman ever downloaded is kept, every version of it. paccache (pacman-contrib) clears the old ones."
                : H.pkgcacheOld(tw.ov.pkgcache).count + tw.ov.pkgcache.gone.count === 0 ? "Only the newest version of each package is kept. Nothing to clear."
                : [H.pkgcacheOld(tw.ov.pkgcache).count ? H.pkgcacheOld(tw.ov.pkgcache).count + " older versions of installed packages (" + tw.size(H.pkgcacheOld(tw.ov.pkgcache).bytes) + ")" : "",
                   tw.ov.pkgcache.gone.count ? tw.ov.pkgcache.gone.count + " of packages no longer installed (" + tw.size(tw.ov.pkgcache.gone.bytes) + ")" : ""]
                  .filter((x) => x).join(", and ") + ". The newest of each stays, to go back to."
            }
            Actions {
              DialogButton {
                visible: !tw.ov.pkgcache.tool && tw.ov.known
                label: "Install pacman-contrib"
                ink: Zenon.cyan
                primary: true
                ready: !tw.busy
                onClicked: tw.mgr.asRoot("pkg", ["pacman-contrib"], "for Tidy's package cache", [])
              }
              DialogButton {
                visible: tw.ov.pkgcache.tool && H.pkgcacheOld(tw.ov.pkgcache).count + tw.ov.pkgcache.gone.count > 0
                label: "Clear " + tw.size(H.pkgcacheBytes(tw.ov.pkgcache))
                ink: Zenon.cyan
                primary: true
                ready: !tw.busy
                onClicked: tw.mgr.asRoot("pkg", [], "clear old packages from the cache",
                  H.pkgcacheSteps(tw.ov.pkgcache.gone.count > 0))
              }
            }
          }

          // ── unused packages ─────────────────────────────────────────
          HermesCard {
            glyph: "\u{F03D6}"
            glyphInk: tw.ov.orphans.length ? Zenon.cyan : Zenon.accentMuted
            title: "Unused packages"
            note: tw.ov.orphans.length ? tw.ov.orphans.length + " · " + tw.size(H.orphanBytes(tw.ov.orphans)) : tw.ov.known ? "none" : ""
            Words {
              visible: tw.ov.orphans.length > 0
              text: "Installed only because something else needed them, and nothing does now."
            }
            Repeater {
              model: tw.ov.orphans
              delegate: Line {
                required property var modelData
                name: modelData.name
                sub: ""
                bytes: modelData.bytes
              }
            }
            Actions {
              visible: tw.ov.orphans.length > 0
              DialogButton {
                label: "Remove " + tw.ov.orphans.length + (tw.ov.orphans.length === 1 ? " package" : " packages")
                ink: Zenon.cyan
                primary: true
                ready: !tw.busy
                onClicked: tw.mgr.asRoot("orphans", [], "remove packages nothing needs",
                  H.orphanSteps(tw.ov.orphans.map((o) => o.name)))
              }
            }
          }

          // ── the journal ────────────────────────────────────────────
          HermesCard {
            glyph: "\u{F09EE}"
            glyphInk: H.journalSpare(tw.ov.journal.bytes) > 0 ? Zenon.cyan : Zenon.accentMuted
            title: "System journal"
            note: tw.ov.known ? tw.size(tw.ov.journal.bytes) : ""
            Words {
              text: H.journalSpare(tw.ov.journal.bytes) > 0
                ? "Every log written since the oldest kept. Shrinking it keeps the newest 200 MiB, which is what System Journal shows when something goes wrong."
                : "Under 200 MiB. Nothing to shrink."
            }
            Actions {
              visible: H.journalSpare(tw.ov.journal.bytes) > 0
              DialogButton {
                label: "Shrink to 200 MiB"
                ink: Zenon.cyan
                primary: true
                ready: !tw.busy
                onClicked: tw.mgr.asRoot("journal", [], "shrink the system journal", H.journalSteps())
              }
            }
          }

          // ── caches ─────────────────────────────────────────────────
          HermesCard {
            glyph: "\u{F00E8}"
            glyphInk: Zenon.accentMuted
            title: "Caches"
            note: tw.ov.known ? tw.size(tw.ov.caches.bytes) + " in ~/.cache" : ""
            Words {
              text: "What apps keep to be quicker next time; they make it again when it is gone. Close an app before clearing its own."
            }
            // above the list, which runs long: the buttons stay in reach
            Actions {
              bottomPadding: 8
              DialogButton {
                label: tw.picked("pickCaches").length ? "Move " + tw.size(tw.bytesOf(tw.ov.caches.dirs, tw.pickCaches)) + " to the trash" : "Move to the trash"
                ink: Zenon.cyan
                primary: tw.picked("pickCaches").length > 0
                ready: !tw.busy && tw.picked("pickCaches").length > 0
                onClicked: { const p = tw.picked("pickCaches"); tw.mgr.trash(p, p.length === 1 ? "1 cache" : p.length + " caches"); }
              }
              DeleteButton {
                kind: "caches"
                count: tw.picked("pickCaches").length
                bytes: tw.bytesOf(tw.ov.caches.dirs, tw.pickCaches)
                onConfirmed: { const p = tw.picked("pickCaches"); tw.mgr.erase(p, p.length === 1 ? "1 cache" : p.length + " caches"); }
              }
              // anything ticked: untick it all; nothing ticked: tick it all
              DialogButton {
                readonly property var shown: tw.ov.caches.dirs.filter((d) => d.bytes >= 1048576)
                visible: shown.length > 1
                label: tw.picked("pickCaches").length > 0 ? "Deselect all" : "Select all"
                ready: !tw.busy
                onClicked: {
                  const next = {};
                  if (tw.picked("pickCaches").length === 0) for (const d of shown) next[d.path] = true;
                  tw.pickCaches = next;
                }
              }
            }
            Repeater {
              model: tw.ov.caches.dirs.filter((d) => d.bytes >= 1048576)
              delegate: Line {
                required property var modelData
                tick: true
                lit: !!tw.pickCaches[modelData.path]
                name: modelData.name
                sub: ""
                bytes: modelData.bytes
                onFlipped: tw.flip("pickCaches", modelData.path)
              }
            }
          }

          // ── downloads ──────────────────────────────────────────────
          HermesCard {
            glyph: "\u{F01DA}"
            glyphInk: Zenon.accentMuted
            title: "Downloads"
            note: tw.ov.known ? (tw.ov.downloads.files.length ? tw.ov.downloads.files.length + " big or old" : "nothing big or old") : ""
            Words {
              visible: tw.ov.downloads.files.length > 0
              text: "Over 100 MB, or untouched for half a year and over 10 MB. A row's name shows it in Terminus."
            }
            Repeater {
              model: tw.ov.downloads.files
              delegate: Line {
                required property var modelData
                tick: true
                lit: !!tw.pickDl[modelData.path]
                name: H.baseName(modelData.path)
                sub: H.where(modelData.path, tw.home) + " · " + H.ageWords(modelData.mtime, tw.now)
                bytes: modelData.bytes
                onFlipped: tw.flip("pickDl", modelData.path)
                onOpened: tw.mgr.reveal(modelData.path)
              }
            }
            Actions {
              visible: tw.ov.downloads.files.length > 0
              DialogButton {
                label: tw.picked("pickDl").length ? "Move " + tw.size(tw.bytesOf(tw.ov.downloads.files, tw.pickDl)) + " to the trash" : "Move to the trash"
                ink: Zenon.cyan
                primary: tw.picked("pickDl").length > 0
                ready: !tw.busy && tw.picked("pickDl").length > 0
                onClicked: { const p = tw.picked("pickDl"); tw.mgr.trash(p, p.length === 1 ? "1 file" : p.length + " files"); }
              }
              DeleteButton {
                kind: "dl"
                count: tw.picked("pickDl").length
                bytes: tw.bytesOf(tw.ov.downloads.files, tw.pickDl)
                onConfirmed: { const p = tw.picked("pickDl"); tw.mgr.erase(p, p.length === 1 ? "1 file" : p.length + " files"); }
              }
            }
          }

          // ── duplicates ─────────────────────────────────────────────
          HermesCard {
            glyph: "\u{F0191}"
            glyphInk: tw.dupeGroups.length ? Zenon.cyan : Zenon.accentMuted
            title: "Duplicates"
            note: !tw.mgr ? "" : tw.mgr.dupesScanning ? "Comparing…"
              : tw.mgr.dupesAsked ? (tw.dupeGroups.length ? tw.dupeGroups.length + " files copied · " + tw.size(H.dupeWaste(tw.dupeGroups)) + " twice" : "none") : ""
            Words {
              text: tw.mgr && tw.mgr.dupesAsked && tw.dupeGroups.length
                ? "The same bytes more than once, 1 MB and up. The oldest of each is kept and not ticked; one copy always stays."
                : "Files of 1 MB and up in Downloads, Documents, Pictures, Videos, Music and Desktop, compared byte for byte."
            }
            Repeater {
              model: tw.dupeGroups
              delegate: Column {
                id: grp
                required property var modelData
                width: parent ? parent.width : 0
                Line {
                  name: H.baseName(grp.modelData.paths[0].path)
                  sub: grp.modelData.paths.length + " copies"
                  bytes: grp.modelData.bytes
                  head: true
                }
                Repeater {
                  model: grp.modelData.paths
                  delegate: Line {
                    required property var modelData
                    tick: true
                    indent: 18
                    lit: !!tw.pickDupes[modelData.path]
                    name: H.where(modelData.path, tw.home) + "/" + H.baseName(modelData.path)
                    sub: lit ? H.ageWords(modelData.mtime, tw.now) : "kept · " + H.ageWords(modelData.mtime, tw.now)
                    bytes: -1
                    onFlipped: tw.pickDupes = H.safePicks(tw.dupeGroups, (() => { const n = Object.assign({}, tw.pickDupes); if (n[modelData.path]) delete n[modelData.path]; else n[modelData.path] = true; return n; })())
                    onOpened: tw.mgr.reveal(modelData.path)
                  }
                }
              }
            }
            Actions {
              BusyButton {
                label: tw.mgr && tw.mgr.dupesAsked ? "Look again" : "Look for copies"
                busy: !!tw.mgr && tw.mgr.dupesScanning
                onClicked: tw.mgr.scanDupes()
              }
              DialogButton {
                visible: tw.picked("pickDupes").length > 0
                label: "Move " + tw.picked("pickDupes").length + (tw.picked("pickDupes").length === 1 ? " copy" : " copies") + " to the trash"
                ink: Zenon.cyan
                primary: true
                ready: !tw.busy
                onClicked: { const p = Object.keys(H.safePicks(tw.dupeGroups, tw.pickDupes)); tw.mgr.trash(p, p.length === 1 ? "1 copy" : p.length + " copies"); }
              }
              DeleteButton {
                kind: "dupes"
                count: tw.picked("pickDupes").length
                bytes: -1
                onConfirmed: { const p = Object.keys(H.safePicks(tw.dupeGroups, tw.pickDupes)); tw.mgr.erase(p, p.length === 1 ? "1 copy" : p.length + " copies"); }
              }
            }
          }

          // ── the trash ──────────────────────────────────────────────
          HermesCard {
            glyph: "\u{F0A7A}"
            glyphInk: Zenon.accentMuted
            title: "Trash"
            note: tw.ov.known ? (tw.ov.trash.items ? tw.size(tw.ov.trash.bytes) + " · " + tw.ov.trash.items + (tw.ov.trash.items === 1 ? " item" : " items") : "empty") : ""
            Words {
              text: "Everything Tidy moves goes here, so nothing is gone until the trash is emptied. The room comes back then. When the disk is too full to wait, Delete beside a list skips the trash."
            }
            Actions {
              DialogButton {
                label: "Open the trash"
                ready: tw.ov.trash.dir !== ""
                onClicked: tw.mgr.openTrash()
              }
              DialogButton {
                visible: tw.ov.trash.items > 0
                label: tw.arming === "empty" ? "Empty it for good? Click again" : "Empty the trash"
                ink: Zenon.red
                primary: tw.arming === "empty"
                ready: !tw.busy
                onClicked: tw.twice("empty", () => tw.mgr.emptyTrash())
              }
            }
          }
        }
      }
      ElasticScroll { anchors.fill: pageFlick; view: pageFlick }
      ScrollEdge { view: pageFlick; follow: true; chromeTop: -tw.headH }
      ScrollEdge { view: pageFlick; below: true; follow: true; bar: foot }
      Scrollbar { flick: pageFlick; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom }
    }

    Ctl.Said {
      anchors.horizontalCenter: body.horizontalCenter
      anchors.bottom: foot.top
      anchors.bottomMargin: 18
      z: 5
      maxWidth: 620
      id: saidBox
      lasts: 3600
    }

    HintBar {
      id: foot
      z: 3
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      rows: [["ctrl r", "look again"], ["esc", "close"]]
    }
  }

  // ── a card's pieces ───────────────────────────────────────────────────
  // Delete, for good: red, and asks once more before it does (tw.twice)
  component DeleteButton: DialogButton {
    id: del
    property string kind: ""
    property int count: 0
    property real bytes: -1
    signal confirmed()
    visible: del.count > 0
    label: tw.arming === del.kind
      ? "Delete " + (del.bytes >= 0 ? tw.size(del.bytes) : del.count === 1 ? "it" : del.count) + " for good? Click again"
      : "Delete"
    ink: Zenon.red
    primary: tw.arming === del.kind
    ready: !tw.busy
    onClicked: tw.twice(del.kind, () => del.confirmed())
  }
  component Words: Text {
    width: parent ? parent.width - 36 : 0
    x: 18
    bottomPadding: 8
    wrapMode: Text.Wrap
    color: Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(14)
  }
  component Actions: Row {
    x: 18
    topPadding: 6
    spacing: 8
  }
  // a row: a box to tick (or not), a name to click (shows it in Terminus,
  // when `opened` is answered), what it is, its size
  component Line: Item {
    id: ln
    property bool tick: false
    property bool lit: false
    property bool head: false
    property real indent: 0
    property string name: ""
    property string sub: ""
    property real bytes: 0
    signal flipped()
    signal opened()
    width: parent ? parent.width : 0
    height: 32
    Ctl.Check {
      id: lnBox
      visible: ln.tick
      x: 18 + ln.indent
      anchors.verticalCenter: parent.verticalCenter
      lit: ln.lit
      onToggled: ln.flipped()
    }
    Text {
      textFormat: Text.PlainText
      id: lnName
      x: ln.tick ? lnBox.x + lnBox.width + 10 : 18 + ln.indent
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, ln.width * 0.55 - x)
      elide: Text.ElideMiddle
      text: ln.name
      color: ln.head ? Zenon.ink : ln.tick && !ln.lit ? Zenon.accentMuted : Zenon.white
      font.family: Zenon.face
      font.weight: ln.head ? Font.DemiBold : Zenon.weight
      font.pixelSize: Zenon.px(15)
      TapHandler { onTapped: ln.opened() }
    }
    Text {
      anchors.left: lnName.right
      anchors.leftMargin: 12
      anchors.right: lnSize.left
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: ln.sub
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
    Text {
      id: lnSize
      anchors.right: parent.right
      anchors.rightMargin: 18
      anchors.verticalCenter: parent.verticalCenter
      text: ln.bytes >= 0 ? tw.size(ln.bytes) : ""
      color: Zenon.accentMuted
      font.family: Zenon.faceMono
      font.pixelSize: Zenon.px(13)
    }
  }
}
