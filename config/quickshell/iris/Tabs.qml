// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// IRIS' TABS — the pages, in strip order, and which one is looked at.
//
// The strip is plato's (plato/editor/TabBar.qml, terminus' strip), so this is
// both what TabBar calls its `ed` and its `client`: the five things plato's
// hand it — `tabs` (id, name, path, current), `moveTab`, `tabOrderChanged`,
// `bufShow`, `bufClose` — under plato's names, since TabBar asks by them.
//
// A page is made when its tab opens and DESTROYED when it closes, never
// hidden and kept. Closing the last tab closes iris (`emptied`).
//
// CLOAK: a tab on the cloak profile (off the record) is marked in the strip
// with the mask glyph, and whatever it opens stays cloaked. It is never in
// the session, and Page keeps no history of it.
//
// ASLEEP: Chromium's own lifecycle, on its own advice (recommendedState). A
// page not looked at for `freezeAfter` is Frozen — no script runs, nothing
// paints, its memory kept — and after `discardAfter` Discarded: its memory
// given back, the page reloaded when next looked at. A page playing sound,
// or otherwise needed, Chromium never recommends either for.

import QtQuick
import QtWebEngine
import "iris.js" as I

QtObject {
  id: deck
  // where the pages live, how one is made (Page.qml), and the two profiles
  required property Item host
  required property Component page
  required property var normal
  required property var cloak

  // how a page's scroller moves it (the window's sendWheel), or null for
  // the page's own scrollTo
  property var sendWheel: null
  // how far a page stretches past its ends: Elastic's own factor
  property real stretchBy: 0.6
  property int freezeAfter: 2 * 60 * 1000
  property int discardAfter: 30 * 60 * 1000

  // the pages in strip order, and the index of the one looked at
  property var views: []
  property int current: -1
  property int serial: 0
  readonly property var here: deck.current >= 0 && deck.current < deck.views.length
    ? deck.views[deck.current] : null

  signal tabOrderChanged()
  signal emptied()
  // a page's right click, for the window's menu (PageMenu)
  signal menuAsked(var page, var request)
  // a page's question, for the window's card (PageDialog: `kind` names the
  // function there that answers it), its fullscreen, and its renderer gone
  signal answerAsked(var page, string kind, var request)
  signal fullScreenAsked(var page, bool on)
  signal crashed(var page, int status)
  signal printAsked(var page)
  signal tipAsked(var page, var request)
  // anything a saved session would say differently: a tab opened, closed,
  // moved, looked at, or gone somewhere else
  signal changed()

  readonly property string cloakMark: "\u{F05F9}"
  // what the strip draws (reads each page's title and url, so a page's new
  // title redraws its tab)
  readonly property var tabs: deck.views.map((v, i) => ({
    id: v.tabId,
    name: (v.cloaked ? deck.cloakMark + "  " : "")
      + (v.pendingUrl !== "" ? I.tabName(v.pendingTitle, v.pendingUrl) : I.tabName(v.title, v.url)),
    path: v.pendingUrl !== "" ? v.pendingUrl : I.shown(v.url),
    current: i === deck.current,
    // plato's own: an unsaved buffer, a pinned one — a page is neither
    modified: false,
    pin: 0
  }))

  onHereChanged: {
    for (const v of deck.views) {
      const seen = v === deck.here;
      // awake before it is shown: a frozen or discarded page cannot be
      if (seen && v.lifecycleState !== WebEngineView.LifecycleState.Active)
        v.lifecycleState = WebEngineView.LifecycleState.Active;
      v.visible = seen;
      if (!seen && !v.hiddenSince) v.hiddenSince = Date.now();
      if (seen) v.hiddenSince = 0;
    }
    deck.changed();
  }

  function indexOf(id) {
    for (let i = 0; i < deck.views.length; ++i)
      if (deck.views[i].tabId === id) return i;
    return -1;
  }

  // a new tab at `url` ("" for none yet), at `at` (the end by default),
  // looked at unless `background`, cloaked when `cloaked`; `title` with a
  // url makes it a restored tab, loaded only when first looked at. The page,
  // for a request to open into.
  function open(url, background, at, cloaked, title) {
    const lazy = title !== undefined && !!url;
    const v = deck.page.createObject(deck.host, {
      tabId: ++deck.serial,
      cloaked: !!cloaked,
      profile: cloaked ? deck.cloak : deck.normal,
      pendingUrl: lazy ? url : "",
      pendingTitle: lazy ? title : ""
    });
    v.wantsTab.connect((request) => deck.adopt(request, v));
    if (deck.sendWheel) v.scroller.send = deck.sendWheel;
    v.stretchBy = deck.stretchBy;
    v.wantsMenu.connect((request) => deck.menuAsked(v, request));
    v.wantsAnswer.connect((kind, request) => deck.answerAsked(v, kind, request));
    v.wantsFullScreen.connect((on) => deck.fullScreenAsked(v, on));
    v.wantsClose.connect(() => Qt.callLater(() => deck.close(v.tabId)));
    v.wantsPrint.connect(() => deck.printAsked(v));
    v.wantsTip.connect((request) => deck.tipAsked(v, request));
    v.crashed.connect((status) => deck.crashed(v, status));
    v.urlChanged.connect(deck.changed);
    v.titleChanged.connect(deck.changed);
    const list = deck.views.slice();
    const i = at === undefined || at < 0 || at > list.length ? list.length : at;
    list.splice(i, 0, v);
    const was = deck.here;
    deck.views = list;
    if (!background || deck.current < 0) deck.current = i;
    else deck.current = list.indexOf(was);
    if (url && !lazy) v.url = url;
    if (v !== deck.here) v.hiddenSince = Date.now();
    deck.changed();
    return v;
  }

  // a page asked for a new tab or window: beside it, cloaked if it is, and
  // in the background when that is what was asked (a middle click)
  function adopt(request, from) {
    const bg = request.destination === WebEngineNewWindowRequest.InNewBackgroundTab;
    const v = deck.open("", bg, deck.views.indexOf(from) + 1, from.cloaked);
    request.openIn(v);
  }

  function show(id) {
    const i = deck.indexOf(id);
    if (i >= 0) deck.current = i;
  }

  function close(id) {
    const i = deck.indexOf(id);
    if (i < 0) return;
    const was = deck.here;
    const v = deck.views[i];
    const list = deck.views.slice();
    list.splice(i, 1);
    deck.views = list;
    if (list.length === 0) {
      deck.current = -1;
      v.destroy();
      deck.changed();
      deck.emptied();
      return;
    }
    // the tab looked at closed: its right-hand neighbour, else its left
    deck.current = v === was ? Math.min(i, list.length - 1) : list.indexOf(was);
    v.destroy();
    deck.changed();
  }

  function moveTab(from, to) {
    if (from === to || from < 0 || to < 0 || from >= deck.views.length || to >= deck.views.length) {
      deck.tabOrderChanged();
      return;
    }
    const was = deck.here;
    const list = deck.views.slice();
    const v = list.splice(from, 1)[0];
    list.splice(to, 0, v);
    deck.views = list;
    deck.current = list.indexOf(was);
    deck.tabOrderChanged();
    deck.changed();
  }

  // the next tab, or the previous (`step` -1), round the end
  function step(by) {
    const n = deck.views.length;
    if (n > 1) deck.current = (deck.current + by + n) % n;
  }

  // ── THE SESSION ────────────────────────────────────────────────────
  // the tabs as a saved session: cloak tabs left out, blank ones too
  function sessionText() {
    const kept = [];
    let here = -1;
    for (const v of deck.views) {
      if (v.cloaked) continue;
      const url = v.pendingUrl !== "" ? v.pendingUrl : String(v.url);
      if (url === "" || url === "about:blank") continue;
      if (v === deck.here) here = kept.length;
      kept.push({ url: url, title: v.pendingUrl !== "" ? v.pendingTitle : v.title });
    }
    return JSON.stringify({ tabs: kept, current: here });
  }
  // a saved session's tabs, each loaded only when first looked at; true when
  // there was one
  function restore(text) {
    let s = null;
    try { s = JSON.parse(text || "null"); } catch (e) { return false; }
    if (!s || !Array.isArray(s.tabs) || s.tabs.length === 0) return false;
    for (const t of s.tabs)
      if (t && typeof t.url === "string" && t.url !== "") deck.open(t.url, true, undefined, false, t.title || "");
    const at = Math.max(0, Math.min(deck.views.length - 1, s.current | 0));
    deck.current = at;
    return deck.views.length > 0;
  }

  // ── ASLEEP ─────────────────────────────────────────────────────────
  readonly property Timer sleeper: Timer {
    interval: 30 * 1000
    repeat: true
    running: deck.views.length > 1
    onTriggered: deck.rest(Date.now())
  }
  function rest(now) {
    const L = WebEngineView.LifecycleState;
    for (const v of deck.views) {
      if (v === deck.here || !v.hiddenSince || v.pendingUrl !== "") continue;
      const idle = now - v.hiddenSince;
      if (idle >= deck.discardAfter && v.recommendedState === L.Discarded && v.lifecycleState !== L.Discarded)
        v.lifecycleState = L.Discarded;
      else if (idle >= deck.freezeAfter && v.recommendedState !== L.Active && v.lifecycleState === L.Active)
        v.lifecycleState = L.Frozen;
    }
  }

  // ── WHAT TabBar CALLS THEM ─────────────────────────────────────────
  function bufShow(id) { deck.show(id); }
  function bufClose(id, _force) { deck.close(id); }
}
