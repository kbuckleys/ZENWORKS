// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── ASKED FOR, NEVER SEEN ────────────────────────────────────────────
// The user (2026-10-11): ceres and oracle "sometimes do not load", with
// nothing in the log to say why. An open that has not put the window on
// screen 1.5 s later says what it found — the compile, the window, its
// screen, the monitor in focus — and builds a fresh window once, so the
// press still lands. The log line is the lead for the real cause.
//
// The manager (`owner`) calls arm([what was asked]) from open(); it needs
// shown, comp, win, pending, alive() and open(arg). One copy for both
// managers since 2026-10-24.

import QtQuick
import Quickshell.Hyprland

Timer {
  id: dog
  required property var owner
  property string tag: ""
  property var asked: null
  property bool rebuilt: false
  interval: 1500

  function arm(args) { dog.asked = args; dog.restart(); }

  readonly property bool shown: !!dog.owner && dog.owner.shown
  onShownChanged: if (dog.shown) { dog.asked = null; dog.rebuilt = false; }

  onTriggered: {
    const mgr = dog.owner;
    if (dog.asked === null || mgr.shown) { dog.asked = null; return; }
    const w = mgr.alive() ? mgr.win : null;
    const m = Hyprland.focusedMonitor;
    console.warn(dog.tag + ": asked to open, not on screen after 1.5 s —"
      + " comp " + (mgr.comp ? mgr.comp.status : "none")
      + " · window " + (w ? "alive" : mgr.win ? "dead" : "none")
      + (w ? " · visible " + w.visible + " · backing " + w.backingWindowVisible
           + " · screen " + (w.screen ? w.screen.name : "none") : "")
      + " · focused monitor " + (m ? m.name : "none")
      + " · pending " + JSON.stringify(mgr.pending)
      + (dog.rebuilt ? " · already rebuilt once, leaving it" : " · rebuilding"));
    if (dog.rebuilt) { dog.asked = null; return; }
    dog.rebuilt = true;
    const again = dog.asked;
    if (w) { try { w.destroy(); } catch (e) {} }
    mgr.win = null;
    mgr.open(again[0]);
  }
}
