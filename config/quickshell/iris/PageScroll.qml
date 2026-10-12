// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A PAGE, AS THE SUITE'S SCROLLING SEES A VIEW — so morpheus' Elastic (the
// one feel: the accelerated wheel, the follow, the band) and its Scrollbar
// work a web page exactly as they work a list, with nothing of theirs copied.
// They ask a Flickable's questions; this answers them for the document:
//
//   contentY        where the document is scrolled, in CSS px. Written, the
//                   document goes there (window.scrollTo, in iris' own world);
//                   written past either end, the remainder is `band` (item
//                   px), which Page turns into the stretch at that edge.
//   contentHeight   the document's height (Chromium's contentsSize)
//   height, width   the page's, in CSS px (zoom counted)
//   moving          while it is being driven, for the scrollbar's autohide
//
// The document also scrolls by itself — keys, a link to an anchor, a page's
// own script — and Chromium says so (scrollPosition); that is taken up here
// whenever iris is not the one driving it.

import QtQuick
import QtWebEngine

QtObject {
  id: ps
  required property var page

  readonly property real zoom: Math.max(0.01, ps.page.zoomFactor)
  readonly property real width: ps.page.width / ps.zoom
  readonly property real height: ps.page.height / ps.zoom
  readonly property real contentWidth: ps.page.contentsSize.width
  readonly property real contentHeight: ps.page.contentsSize.height
  readonly property real contentX: 0
  readonly property real originX: 0
  readonly property real originY: 0
  readonly property real most: Math.max(0, ps.contentHeight - ps.height)
  // whether the document scrolls at all (a web app's usually does not: its
  // panels do, and Chromium keeps their wheel)
  readonly property bool scrolls: ps.most > 1

  property real contentY: 0
  // past the ends: how far the wheel has asked beyond them, in item px
  readonly property real band: (ps.contentY - Math.max(0, Math.min(ps.most, ps.contentY))) * ps.zoom
  property bool moving: false
  function cancelFlick() {}

  // ── HOW THE DOCUMENT IS MOVED ──────────────────────────────────────
  // `send(dy)`, handed in by the window: a precise wheel of that many item
  // px into Chromium, which scrolls on its compositor thread — smooth however
  // busy the page's own script is. (Asking the page to scrollTo, one call a
  // frame, ran on its main thread: on a heavy page the calls queued and
  // landed in bursts, 0 px one frame and 300 the next — the user's capture,
  // 2026-10-12.) Without a `send`, scrollTo all the same.
  property var send: null
  property real sent: -1
  property real drivenAt: 0
  onContentYChanged: {
    if (ps.taking) return;
    ps.drivenAt = Date.now();
    ps.moving = true;
    still.restart();
    const y = Math.round(Math.max(0, Math.min(ps.most, ps.contentY)));
    if (y === ps.sent) return;
    const from = ps.sent < 0 ? ps.page.scrollPosition.y : ps.sent;
    ps.sent = y;
    if (ps.send) ps.send((y - from) * ps.zoom);
    else ps.page.runJavaScript("window.scrollTo(0, " + y + ")", WebEngineScript.ApplicationWorld);
  }
  readonly property Timer still: Timer { interval: 400; onTriggered: ps.moving = false }

  // the document moved on its own: taken up, unless iris is driving it
  property bool taking: false
  readonly property Connections fromPage: Connections {
    target: ps.page
    function onScrollPositionChanged() {
      if (Date.now() - ps.drivenAt < 250) return;
      ps.taking = true;
      ps.contentY = ps.page.scrollPosition.y;
      ps.sent = Math.round(ps.contentY);
      ps.taking = false;
      ps.moving = true;
      still.restart();
    }
  }
}
