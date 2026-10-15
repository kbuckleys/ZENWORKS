// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHICH PARU — the tagged release or the latest commit. Setup asks it once,
// before paru exists; Settings › Channels asks it again whenever you want the
// other one (user, 2026-10-11), so it is one piece rather than two copies
// that drift apart.
//
// THE SUITE'S SWITCH (user, 2026-10-14): terminus/Segments, two halves, each
// with its line of explanation under it (Segments' notes), as the cards had —
// the release marked recommended; paru-git is kept as the fallback it once
// had to be, when the release lagged and -git was the way to go.
//
// `choice` is what is picked, held by whoever asked; a pick says so through
// `picked`. `installed`, when given, is the paru on this machine now.

import QtQuick
import "../morpheus"
import "../terminus" as Term

Item {
  id: pick

  property string choice: "paru"
  property string installed: ""
  signal picked(string pkg)

  function note(pkg, line) { return line + (pick.installed === pkg ? "  \u00B7  installed" : ""); }

  implicitHeight: seg.height
  height: implicitHeight

  Term.Segments {
    id: seg
    width: pick.width
    even: true
    // the choice made plain, as the Flatpak sheet's (user, 2026-10-14)
    strong: true
    textSize: Zenon.px(16)
    ink: Zenon.accentKey
    options: [["paru", "Latest release \u00B7 recommended", pick.note("paru", "paru \u2014 each tagged version")],
              ["paru-git", "Latest commit", pick.note("paru-git", "paru-git \u2014 GitHub master, the fallback")]]
    current: pick.choice
    onChose: (v) => pick.picked(v)
  }
}
