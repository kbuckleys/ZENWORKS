// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SETTINGSMOVE — About's Export settings and Import settings (2026-10-21),
// the files half: Oracle only asks (exportAsked / importAsked), since it
// cannot reach terminus' picker or morpheus' writer.
//
// Export reads the files a bundle may hold (Ora.makeBundle) and saves one
// .json where you choose. Import reads one, says what is in it on a sheet,
// and only on Import writes it: what is here now first, to
// settings-before-import.json beside oracle.json, so any import can be
// taken back by importing that. The screen arrangement comes along only if
// ticked — another machine's screens are rarely this one's.

import QtQuick
import Quickshell
import Quickshell.Io
import "oracle.js" as Ora
import "../morpheus"
import "../morpheus/controls" as Controls
import "../terminus"

Item {
  id: move
  anchors.fill: parent
  property var fileManager: null

  readonly property string stateDir: Oracle.statePath.replace(/\/[^/]*$/, "")
  function absOf(rel) {
    if (rel === "oracle.json") return Oracle.statePath;
    if (rel.startsWith("hypr/")) return Oracle.hyprLuaDir + "/" + rel.slice(5);
    if (rel.startsWith("themes/")) return Quickshell.shellDir + "/" + rel;
    return "";
  }
  // what was done, said as a toast: the window has no line of its own
  function tell(t) { Quickshell.execDetached(["notify-send", "-a", "oracle", "Settings", t]); }

  Component { id: readerComp; FileView { blockLoading: true; printErrors: false } }
  function readText(path) {
    const f = readerComp.createObject(move, { path: path });
    const t = f && f.loaded ? f.text() : null;
    if (f) f.destroy();
    return t;
  }
  // what is here now, as a bundle's files
  function current() {
    const rels = ["oracle.json", "hypr/keys.lua", "hypr/wake.lua", "hypr/defaults.lua", "hypr/input.lua", "hypr/monitors.lua"]
      .concat(Oracle.themeOptions.filter((o) => o.custom).map((o) => "themes/" + o.value + ".json"));
    const files = {};
    for (const rel of rels) {
      const t = move.readText(move.absOf(rel));
      if (t !== null && t !== "") files[rel] = t;
    }
    return files;
  }

  AtomicWriter { id: writer; tag: "oracle-settings" }

  // ── EXPORT ──
  function exportNow() {
    if (!move.fileManager) { move.tell("Terminus is needed to choose where"); return; }
    Oracle.save();
    const day = Qt.formatDate(new Date(), "yyyy-MM-dd");
    move.fileManager.choose(false, Paths.home(), (paths) => {
      if (!paths || !paths.length) return;
      const out = /\.json$/i.test(paths[0]) ? paths[0] : paths[0] + ".json";
      writer.write(out, Ora.makeBundle(move.current(), new Date().toISOString()));
      move.tell("Settings exported to " + out.replace(/.*\//, ""));
    }, "zenworks-settings-" + day + ".json");
  }

  // ── IMPORT ──
  property var pending: null
  property bool withScreens: false
  property int pick: 0
  function importAsk() {
    if (!move.fileManager) { move.tell("Terminus is needed to choose the file"); return; }
    move.fileManager.choose(false, Paths.home(), (paths) => {
      if (!paths || !paths.length) return;
      const b = Ora.readBundle(move.readText(paths[0]) || "");
      if (!b.ok) { move.tell(b.why); return; }
      move.withScreens = false;
      move.pick = 0;
      move.pending = b;
    });
  }
  function importNow() {
    const b = move.pending;
    move.pending = null;
    if (!b) return;
    Oracle.save();
    // what is here now, first
    writer.write(move.stateDir + "/settings-before-import.json", Ora.makeBundle(move.current(), new Date().toISOString()));
    let n = 0;
    for (const rel in b.files) {
      if (rel === "hypr/monitors.lua" && !move.withScreens) continue;
      const to = move.absOf(rel);
      if (to === "") continue;
      writer.write(to, b.files[rel]);
      n++;
    }
    // once the writes have landed: the settings read back, hyprland told
    after.restart();
    move.tell(n + (n === 1 ? " file imported" : " files imported") + " · the old ones kept in settings-before-import.json");
  }
  Timer {
    id: after
    interval: 600
    onTriggered: {
      Oracle.reloadFromDisk();
      Oracle.scanThemes();
      Quickshell.execDetached(["hyprctl", "reload"]);
    }
  }

  Connections {
    target: Oracle
    function onExportAsked() { move.exportNow(); }
    function onImportAsked() { move.importAsk(); }
  }

  onPendingChanged: if (move.pending) Qt.callLater(() => sheetKeys.forceActiveFocus())
  // the sheet's keys: no field to hold them, so held here
  Item {
    id: sheetKeys
    Keys.onPressed: (e) => {
      e.accepted = true;
      if (e.key === Qt.Key_Escape) move.pending = null;
      else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) body.chose(move.pick);
      else if (e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Tab) move.pick = 1 - move.pick;
      else e.accepted = false;
    }
  }
  InputShield { visible: !!move.pending; onClicked: move.pending = null }
  Sheet {
    id: sheet
    shown: !!move.pending
    cardW: 480
    cardH: body.implicitHeight
    ConfirmBody {
      id: body
      width: parent.width
      question: "Import these settings?"
      glyph: "󰋺"
      glyphInk: Zenon.cyan
      detail: move.pending ? (move.pending.made !== "" ? "Exported " + Qt.formatDateTime(new Date(move.pending.made), "d MMM yyyy, hh:mm") + ". " : "")
        + "What is here now is kept first." : ""
      items: move.pending ? Ora.bundleWords(move.pending.files).filter((w) => w !== "Screen arrangement") : []
      choices: [{ label: "Import", ink: Zenon.cyan }, { label: "Cancel", ink: Zenon.accentMuted }]
      pick: move.pick
      onPicked: (i) => move.pick = i
      onChose: (i) => { if (i === 0) move.importNow(); else move.pending = null; }
      Item {
        width: parent.width
        height: visible ? 36 : 0
        visible: !!move.pending && ("hypr/monitors.lua" in move.pending.files)
        Controls.Check {
          x: 16
          anchors.verticalCenter: parent.verticalCenter
          label: "Screen arrangement too (from that machine)"
          lit: move.withScreens
          onToggled: move.withScreens = !move.withScreens
        }
      }
    }
  }
}
