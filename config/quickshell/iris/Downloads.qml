// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// IRIS' DOWNLOADS — into the download directory (xdg-user-dirs), and into the
// shell's Jobs drawer while they run, beside terminus' copies: started,
// progress at most once a second (terminus.js' own size and time-left
// wording), and how it ended. The drawer's stop comes back as a cancel.
// From either profile: a cloak tab's download is the user's file all the
// same, and lands where the others do.

import QtQuick
import QtWebEngine
import IrisHost
import "../terminus/terminus.js" as Terminus

QtObject {
  id: dl
  required property var normal
  required property var cloak

  property int serial: 0
  // key → { item, started, lastBytes, lastAt }; `running` counts them (a
  // map's insides changing notify no binding)
  property var live: ({})
  property int running: 0

  function take(item) {
    item.downloadDirectory = Iris.downloadDir;
    item.accept();
    const key = ++dl.serial;
    dl.live[key] = { item: item, started: Date.now(), lastBytes: 0, lastAt: Date.now() };
    dl.running++;
    Shell.send({ job: "start", key: key, name: item.downloadFileName, dest: item.downloadDirectory });
    item.stateChanged.connect(() => dl.ended(key));
    if (Iris.selftest) Iris.report("download started: " + item.downloadFileName + " → " + item.downloadDirectory);
  }

  function ended(key) {
    const d = dl.live[key];
    if (!d) return;
    const s = d.item.state;
    const state = s === WebEngineDownloadRequest.DownloadCompleted ? "done"
      : s === WebEngineDownloadRequest.DownloadCancelled ? "stopped"
      : s === WebEngineDownloadRequest.DownloadInterrupted ? "failed" : "";
    if (state === "") return;
    Shell.send({ job: "end", key: key, state: state });
    if (Iris.selftest) Iris.report("download " + state + ": " + d.item.downloadFileName
                                   + " (" + Terminus.formatSize(d.item.receivedBytes) + ")");
    delete dl.live[key];
    dl.running = Math.max(0, dl.running - 1);
  }

  // progress, once a second for every download running
  readonly property Timer ticker: Timer {
    interval: 1000
    repeat: true
    running: dl.running > 0
    onTriggered: {
      const now = Date.now();
      for (const key in dl.live) {
        const d = dl.live[key], it = d.item;
        const got = it.receivedBytes, all = it.totalBytes;
        const rate = (got - d.lastBytes) * 1000 / Math.max(1, now - d.lastAt);
        d.lastBytes = got;
        d.lastAt = now;
        Shell.send({ job: "progress", key: Number(key),
                     pct: all > 0 ? Math.round(got * 100 / all) : 0,
                     rate: rate > 0 ? Terminus.formatSize(Math.round(rate)) + "/s" : "",
                     eta: all > 0 ? Terminus.etaFrom(now - d.started, got, all) : "" });
      }
    }
  }

  readonly property Connections fromShell: Connections {
    target: Shell
    function onCancelAsked(key) {
      const d = dl.live[key];
      if (d) d.item.cancel();
    }
  }
  readonly property Connections fromNormal: Connections {
    target: dl.normal
    function onDownloadRequested(item) { dl.take(item); }
  }
  readonly property Connections fromCloak: Connections {
    target: dl.cloak
    function onDownloadRequested(item) { dl.take(item); }
  }
}
