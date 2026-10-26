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
//
// ON SCREEN MEANS HYPRLAND HAS IT (2026-10-26). Qt can say visible and
// backed while the compositor never got a frame: eglSwapBuffers failed
// (0x300d, bad surface) on the first show, no buffer was committed, so no
// toplevel ever mapped — and every press after it only tried to focus a
// window that was not there. A toplevel of quickshell's titled `tag` is the
// proof. A window Qt shows and Hyprland has not mapped is given a second
// 1.5 s before it is rebuilt — a stall can hold a real map back that long
// (lag.log has seen 1.4 s) — and one still unmapped 3 s on is not waited
// for again: the next press rebuilds it there and then.

import QtQuick
import Quickshell.Hyprland

Timer {
  id: dog
  required property var owner
  property string tag: ""
  property var asked: null
  property bool rebuilt: false
  property bool waited: false
  property real armedAt: 0
  interval: 1500

  // Qt's word, and Hyprland's: shown is both
  readonly property bool qtShown: !!dog.owner && dog.owner.shown
  readonly property bool mapped: Hyprland.toplevels.values.some((t) => t.title === dog.tag
    && (!t.wayland || t.wayland.appId === "org.quickshell"))
  readonly property bool shown: dog.qtShown && dog.mapped
  // shown to Qt, not on screen: since when (0 when it is not)
  readonly property bool ghost: dog.qtShown && !dog.mapped
  property real ghostSince: 0
  onGhostChanged: dog.ghostSince = dog.ghost ? Date.now() : 0
  onShownChanged: if (dog.shown) { dog.asked = null; dog.rebuilt = false; dog.waited = false; }

  function arm(args) {
    dog.asked = args;
    dog.armedAt = Date.now();
    dog.waited = false;
    if (dog.ghostSince > 0 && Date.now() - dog.ghostSince >= 3000) {
      dog.waited = true;
      dog.stop();
      Qt.callLater(dog.fire);
    } else dog.restart();
  }

  onTriggered: dog.fire()

  function fire() {
    const mgr = dog.owner;
    if (dog.asked === null || dog.shown) { dog.asked = null; return; }
    if (dog.ghost && !dog.waited) { dog.waited = true; dog.restart(); return; }
    const w = mgr.alive() ? mgr.win : null;
    const m = Hyprland.focusedMonitor;
    console.warn(dog.tag + ": asked to open, not on screen after "
      + ((Date.now() - dog.armedAt) / 1000).toFixed(1) + " s —"
      + " comp " + (mgr.comp ? mgr.comp.status : "none")
      + " · window " + (w ? "alive" : mgr.win ? "dead" : "none")
      + (w ? " · visible " + w.visible + " · backing " + w.backingWindowVisible
           + " · screen " + (w.screen ? w.screen.name : "none")
           + " · mapped " + dog.mapped
           + (dog.ghostSince > 0 ? " · unmapped " + ((Date.now() - dog.ghostSince) / 1000).toFixed(1) + " s" : "") : "")
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
