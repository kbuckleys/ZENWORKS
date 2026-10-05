// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// USERDIRS — Pictures, Downloads and the rest, where this user keeps them.
//
// xdg-user-dirs writes them to ~/.config/user-dirs.dirs and exports them into
// the environment only if something in the session was set up to, so the file
// is the answer, the environment variable is the fallback for a session that
// exports one, and the spec's own default is the floor. The same order
// `xdg-user-dir` itself uses: it sources the file over whatever is exported.
//
// A singleton because reading a file wants a FileView, and Paths is
// deliberately nothing but string functions over the environment. It was
// picasso's alone, for Pictures only, until terminus needed the others.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "."

Singleton {
  id: root

  readonly property string desktop: root.dir(root.text, "DESKTOP", "Desktop")
  readonly property string documents: root.dir(root.text, "DOCUMENTS", "Documents")
  readonly property string downloads: root.dir(root.text, "DOWNLOAD", "Downloads")
  readonly property string music: root.dir(root.text, "MUSIC", "Music")
  readonly property string pictures: root.dir(root.text, "PICTURES", "Pictures")
  readonly property string videos: root.dir(root.text, "VIDEOS", "Videos")

  property string text: ""

  FileView {
    id: file
    path: Paths.userDirsFile()
    blockLoading: true
    printErrors: false
    onLoaded: root.text = String(file.text() || "")
  }
  // Read once here as well, synchronously: picasso decides which directory
  // to scan as it starts, and must not scan the fallback first.
  Component.onCompleted: root.text = String(file.text() || "")

  // The file is shell syntax — `XDG_PICTURES_DIR="$HOME/Pictures"` — so $HOME
  // is expanded by hand rather than by starting a shell to read six lines.
  // `text` is passed in so each binding above depends on it.
  function dir(text, key, fallback) {
    const m = new RegExp("^\\s*XDG_" + key + "_DIR\\s*=\\s*\"([^\"]*)\"", "m").exec(text);
    if (m) {
      const v = m[1].replace(/\$HOME/g, Paths.home()).replace(/\/+$/, "");
      if (v !== "") return v;
    }
    return Quickshell.env("XDG_" + key + "_DIR") || Paths.home() + "/" + fallback;
  }
}
