// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE ICONS ARE JETBRAINSMONO'S, WHATEVER THE TEXT IS SET IN. Every icon in
// the shell is a Nerd Font glyph in the private use area. A Nerd Font family
// carries them itself; any other face (oracle's Font takes any family) does
// not, and Qt then takes each missing glyph from whichever font fontconfig
// offers first — some other Nerd Font, at another size and weight.
//
// So this writes one fontconfig rule, scoped to this process (fontconfig
// knows it as "quickshell") and to nothing else on the desktop: after the
// family asked for, JetBrainsMono Nerd Font Propo, before any other. Glyphs
// the chosen face has stay its own. Qt reads fontconfig once, at start, so
// the rule's first write counts from the next shell start; it is only ever
// rewritten when its text changes.
//
// A Loader in shell.qml, not a qmldir type.

import QtQuick
import Quickshell

Item {
  readonly property string file:
    (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
    + "/fontconfig/conf.d/60-quickshell-glyphs.conf"
  readonly property string text: [
    "<?xml version=\"1.0\"?>",
    "<!DOCTYPE fontconfig SYSTEM \"urn:fontconfig:fonts.dtd\">",
    "<!-- Written by quickshell (morpheus/GlyphFallback.qml): the shell's icons",
    "     come from JetBrainsMono Nerd Font whatever face its text is set in.",
    "     Only the quickshell process is affected. -->",
    "<fontconfig>",
    "  <match target=\"pattern\">",
    "    <test name=\"prgname\"><string>quickshell</string></test>",
    "    <edit name=\"family\" mode=\"append\" binding=\"strong\"><string>JetBrainsMono Nerd Font Propo</string></edit>",
    "  </match>",
    "</fontconfig>",
    ""].join("\n")

  Component.onCompleted: Quickshell.execDetached(["sh", "-c",
    "f=\"$1\"; printf '%s' \"$2\" | cmp -s - \"$f\" 2>/dev/null && exit 0; "
    + "mkdir -p \"${f%/*}\" && printf '%s' \"$2\" > \"$f.tmp\" && mv -f \"$f.tmp\" \"$f\"",
    "sh", file, text])
}
