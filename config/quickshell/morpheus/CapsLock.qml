// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CAPS LOCK — whether it is on, for every field that takes a password:
// cerberus' lock, ceres' sudo prompt, calypso's vault. A password refused
// because caps was on looks exactly like a wrong one, so each of them shows
// CapsGlyph while `on` is true.
//
// ASKED, NEVER POLLED. Caps can only change when the key is used, and every
// field here sees the key — so a field calls read() when it opens, and on
// Caps Lock's press AND its release. Both, because xkb locks the modifier on
// the press but unlocks it on the release of the next press: a read on the
// press that turns caps off still sees it on (measured in cerberus,
// 2026-09-24, four presses and four reads of "on").
//
// Asked of HYPRLAND, of its MAIN keyboard — the compositor's own xkb state,
// which is what decides what the field receives. Not the LEDs: /sys/class/leds
// has one node per device, numbered by input, renumbered on every replug.
//
// ONE READ AT A TIME. A read asked for while one is in flight waits for it
// and runs after, so no read is ever killed and the last ask always gets an
// answer.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  property bool on: false

  property bool again: false

  function read() {
    if (proc.running) { root.again = true; return; }
    proc.running = true;
  }

  Process {
    id: proc
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector {
      id: out
      onStreamFinished: {
        try {
          const kbs = JSON.parse(out.text).keyboards || [];
          const main = kbs.find((k) => k.main) || kbs[0];
          root.on = !!(main && main.capsLock);
        } catch (e) {}
        if (root.again) {
          root.again = false;
          root.read();
        }
      }
    }
  }
}
