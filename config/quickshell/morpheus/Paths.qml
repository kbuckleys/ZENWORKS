// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PATHS — where this user's things live, read from the environment once.
//
// home() had five identical definitions across the layers' .js files and
// cacheDir() three. All eight were byte-for-byte the same, which is the
// harmless end of duplication — but it is still eight places to edit the day
// one of them should have honored XDG_HOME, and eight places for the next
// reader to check before believing any of them.
//
// A SINGLETON for the same reason Strings is one: a layer's .js cannot import
// a shared library without losing the QML document's scope, and losing that
// scope is losing `Quickshell.env` — which is the only thing these functions
// do. A singleton the host document imports stays in reach.

pragma Singleton

import QtQuick
import Quickshell

QtObject {
  function home() {
    return Quickshell.env("HOME");
  }

  // XDG's own fallbacks, spelled out rather than assumed: a machine that sets
  // XDG_CACHE_HOME somewhere other than ~/.cache is entitled to be obeyed.
  function cacheDir() {
    return Quickshell.env("XDG_CACHE_HOME") || Paths.home() + "/.cache";
  }

  function tmpDir() {
    return Quickshell.env("TMPDIR") || "/tmp";
  }

  // Private to this user and cleared at logout; for scratch files that should
  // not sit under a guessable name in a shared /tmp.
  function runtimeDir() {
    return Quickshell.env("XDG_RUNTIME_DIR") || Paths.tmpDir();
  }

  // Where applications, the trash and other shared data live.
  function dataDir() {
    return Quickshell.env("XDG_DATA_HOME") || Paths.home() + "/.local/share";
  }

  // Where state that should outlive a cache lives: Zenworks' own notes for
  // ./uninstall (zenworks/) are here.
  function stateDir() {
    return Quickshell.env("XDG_STATE_HOME") || Paths.home() + "/.local/state";
  }

  // Where other programs' configuration lives, for the times this shell reads
  // someone else's file rather than its own — hermes takes its icon map
  // straight out of the yazi flavor instead of keeping a second copy of it.
  function configDir() {
    return Quickshell.env("XDG_CONFIG_HOME") || Paths.home() + "/.config";
  }

  // The user directories (Pictures, Downloads, ...) are NOT environment
  // variables the way the ones above are: xdg-user-dirs writes them to this
  // file. UserDirs reads it, because reading a file wants a FileView and this
  // singleton is deliberately nothing but string functions.
  function userDirsFile() {
    return Paths.configDir() + "/user-dirs.dirs";
  }

  // A long-running watcher's argv (inotifywait -m, udevadm monitor, gdbus
  // monitor...), run through scripts/tether so it dies with this shell even
  // when the shell is SIGKILLed; without it each shell that went left its
  // watchers running under init. Every such Process takes its command from
  // here; python backends use morpheus/py/tether.py.
  function tether(argv) {
    return [Quickshell.shellDir + "/scripts/tether"].concat(argv);
  }
}
