// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TILE NAME — a filename under a thumbnail, wrapped to two lines and, when it
// will not fit in two, shortened in the MIDDLE so the extension survives:
// "wallhaven-7pzw…59.jpg".
//
// Qt cannot do this itself. ElideMiddle only works on a single line; given
// wrapping and a line limit it quietly does nothing, so a long name was cut
// wherever the second line ran out — "wallhaven-7pzw59-", the extension gone
// and no ellipsis to say anything was missing. So the shortening is done
// here, against a hidden twin of the label that is laid out with the same
// width and font and asked how many lines a candidate takes.
//
// Shared by terminus' grid and picasso's gallery, which had the same bug.
//
// `lead` and `trail` are markup that rides along with the name (terminus'
// git, bookmark and link marks) and are never shortened; the name is escaped,
// since the label is StyledText.

import QtQuick
import "../morpheus"

Text {
  id: label

  property string name: ""
  property string lead: ""
  property string trail: ""
  property int lines: 2

  // What the name is drawn as: itself, or its shortened form.
  property string shown: name

  textFormat: Text.StyledText
  wrapMode: Text.Wrap
  maximumLineCount: label.lines
  // A last resort only — fit() should always have left it nothing to do.
  elide: Text.ElideRight
  text: label.lead + Strings.escapeHtml(label.shown) + label.trail

  // The twin. No line limit, so lineCount is the truth.
  Text {
    id: probe
    visible: false
    width: label.width - label.leftPadding - label.rightPadding
    textFormat: Text.StyledText
    wrapMode: label.wrapMode
    font: label.font
  }

  function takes(s) {
    probe.text = label.lead + Strings.escapeHtml(s) + label.trail;
    return probe.lineCount;
  }

  function fit() {
    const name = label.name;
    if (label.width <= 0 || name === "" || label.takes(name) <= label.lines) {
      label.shown = name;
      return;
    }
    // The extension is kept whole when there is one worth keeping: short,
    // and not the whole name (".bashrc" has no extension, it IS the name).
    const dot = name.lastIndexOf(".");
    const ext = (dot > 0 && name.length - dot <= 6) ? name.slice(dot) : "";
    const stem = ext === "" ? name : name.slice(0, dot);
    // A few characters of the stem's end ride with the extension, the way
    // Finder does it: "IMG_20…0412.jpg" tells two siblings apart where
    // "IMG_20….jpg" would not.
    const cut = (n) => {
      const t = Math.min(4, Math.floor(n / 3));
      return stem.slice(0, n - t) + "…" + stem.slice(stem.length - t) + ext;
    };
    // The most of the stem that still fits. Line count is monotone in n
    // (one more character never takes fewer lines), so a binary search.
    let lo = 0, hi = stem.length - 1;
    while (lo < hi) {
      const mid = Math.ceil((lo + hi) / 2);
      if (label.takes(cut(mid)) <= label.lines) lo = mid; else hi = mid - 1;
    }
    label.shown = cut(lo);
  }

  // Batched: a resize, a font change and a new name arriving together are
  // one fit, not three.
  //
  // On a Timer of its own rather than Qt.callLater: a tile destroyed with a
  // fit still queued (a folder changed, a window closed) had the call run
  // on a label whose context was already gone — "takes is not a function",
  // ten at a time in the log. The Timer goes with the label, and its fit
  // with it.
  Timer { id: refit; interval: 0; onTriggered: label.fit() }
  onNameChanged: refit.restart()
  onWidthChanged: refit.restart()
  onLeadChanged: refit.restart()
  onTrailChanged: refit.restart()
  onFontChanged: refit.restart()
  Component.onCompleted: label.fit()
}
