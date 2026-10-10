// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE OF THE PROPERTIES CARD'S PROBES (PropsCard.qml), answering only the
// selection it was asked about. Opening the card on B while `du` was still
// walking A used to be a no-op restart (`running = true` on a running
// Process), and A's size, counts and owner were then shown as B's. Each show()
// is a generation (`liveGen`); a probe remembers the generation it started
// for, stops the old run to make way, and `current` is false for an answer
// from an older one.

import QtQuick
import Quickshell.Io

Process {
  id: pp
  property int liveGen: 0
  property int gen: -1
  property int wantGen: -1
  property var wantCmd: null
  readonly property bool current: pp.gen === pp.liveGen
  onExited: if (pp.wantCmd && pp.wantGen !== pp.gen) Qt.callLater(pp.start)
  function ask(cmd) {
    pp.wantCmd = cmd;
    pp.wantGen = pp.liveGen;
    if (pp.running) { pp.running = false; return; }   // onExited starts it
    pp.start();
  }
  function start() {
    if (pp.running || !pp.wantCmd) return;
    pp.gen = pp.wantGen;
    pp.command = pp.wantCmd;
    pp.running = true;
  }
}
