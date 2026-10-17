// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// LAZYCOMPONENT — a window type compiled the first time it is wanted.
//
// An app's window is not built until it is opened, and its type is not even
// compiled until then: compiled asynchronously, so a first open does not
// stall the shell. Whatever asks while it is still compiling is queued and
// run, in order, once it is ready. This was written out in six managers
// (delphi, alexandria, clio, calypso, plato, picasso's viewer), identical
// but for the file and the name in the warning.
//
// `comp` is the compiled type (createObject on it); a manager sets it back
// to null when its last window goes, so the next open compiles afresh.

import QtQuick

QtObject {
  id: root

  // the window's file, as Qt.resolvedUrl gives it from the manager
  property url source
  // what a failed compile is logged under
  property string tag: ""

  property var comp: null
  // the calls waiting on a compile still running
  property var waiting: []

  // the compile failed; the warning is already logged
  signal failed()

  // Run `fn` once the type is compiled, compiling it if nothing has yet.
  function withReady(fn) {
    if (root.comp && root.comp.status === Component.Ready) { fn(); return; }
    root.waiting.push(fn);
    if (root.comp) return;
    const comp = Qt.createComponent(root.source, Component.Asynchronous);
    root.comp = comp;
    const settle = () => {
      if (comp.status === Component.Loading) return;
      const queued = root.waiting;
      root.waiting = [];
      if (comp.status !== Component.Ready) {
        console.warn(root.tag + ":", comp.errorString());
        root.comp = null;
        root.failed();
        return;
      }
      for (const f of queued) f();
    };
    if (comp.status === Component.Loading) comp.statusChanged.connect(settle);
    else settle();
  }
}
