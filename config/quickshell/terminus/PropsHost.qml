// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A PLAIN HOST FOR THE PROPERTIES CARD (PropsCard.qml), for a window that is
// not terminus and has no listing, thumbnail pool or tags of its own to lend
// it — plato's tree. Everything the card asks of `host`: rows enriched with
// terminus' glyphs and inks, commands run (and the "open with" scan run
// again after), what opens the file and making one the default or taking it
// away. A picture shows itself; nothing else gets a picture.
//
//     PropsHost { id: propsHost; onSaid: (t) => toast(t) }
//     PropsCard { host: propsHost }
//
// `said` carries what the card would put in a status line: a warning, or a
// word once something is done.

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../morpheus/icons.js" as Icons
import "terminus.js" as Terminus

Item {
  id: host
  visible: false

  signal said(string text)

  function enrich(rows) { return Terminus.enrich(rows, Icons); }
  function warn(t) { host.said(t); }
  function inkFor(r) { return Terminus.inkOf(r); }

  // the card writes a word here when something is done
  property string status: ""
  onStatusChanged: if (host.status !== "") { host.said(host.status); host.status = ""; }

  // a command string, or terminus' { script, args }; one at a time, in order
  property var _queue: []
  function run(cmd) {
    host._queue = host._queue.concat([typeof cmd === "string" ? ["sh", "-c", cmd] : Terminus.shArgv(cmd)]);
    if (!runner.running) host._next();
  }
  function _next() {
    if (host._queue.length === 0) { host.rescan(); return; }
    runner.command = host._queue[0];
    host._queue = host._queue.slice(1);
    runner.running = true;
  }
  Process {
    id: runner
    onExited: (code) => {
      if (code !== 0) host.said("that did not work");
      host._next();
    }
  }

  // no tags here
  readonly property var tagMarks: ({})
  function tagInk(name) { return Zenon.cyan; }

  // no thumbnail pool: a picture Qt can open is drawn as itself ("i")
  function thumbKind(r) { return Terminus.isImage(r.name) ? "i" : ""; }
  function thumbHas(r) { return true; }
  function thumbJob(r, kind) { return r.path; }
  function thumbNow(job) {}
  readonly property var thumbFile: ({})

  // what opens it — terminus' scan (Terminus.appsCommand)
  property var openWithApps: []
  property string openWithDefault: ""
  property string openWithMime: ""
  property bool appsScanned: false
  property string appsPath: ""
  function findApps(path) {
    host.openWithApps = [];
    host.openWithDefault = "";
    host.openWithMime = "";
    host.appsScanned = !path;
    if (!path) return;
    apps.command = ["sh", "-c", Terminus.appsCommand(path)];
    apps.running = true;
  }
  function rescan() { if (host.appsPath !== "") host.findApps(host.appsPath); }
  function setDefaultApp(id) {
    if (!id || host.openWithMime === "") return;
    host.run(Terminus.setDefaultAppCommand(id, host.openWithMime));
    host.said("default set");
  }
  function removeApp(id) {
    if (!id || host.openWithMime === "") return;
    host.run(Terminus.removeAppCommand(id, host.openWithMime));
  }
  Process {
    id: apps
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        host.openWithApps = Terminus.parseApps(text);
        host.openWithMime = Terminus.parseAppsMime(text);
        host.openWithDefault = Terminus.parseAppsDefault(text);
        host.appsScanned = true;
      }
    }
  }
}
