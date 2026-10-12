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

import QtQuick
import QtWebEngine
import "iris.js" as I

QtObject {
  id: deck
  // where the pages live, and how one is made (Page.qml)
  required property Item host
  required property Component page

  // the pages in strip order, and the index of the one looked at
  property var views: []
  property int current: -1
  property int serial: 0
  readonly property var here: deck.current >= 0 && deck.current < deck.views.length
    ? deck.views[deck.current] : null

  signal tabOrderChanged()
  signal emptied()

  // what the strip draws (reads each page's title and url, so a page's new
  // title redraws its tab)
  readonly property var tabs: deck.views.map((v, i) => ({
    id: v.tabId,
    name: I.tabName(v.title, v.url),
    path: I.shown(v.url),
    current: i === deck.current,
    // plato's own: an unsaved buffer, a pinned one — a page is neither
    modified: false,
    pin: 0
  }))

  onHereChanged: {
    for (const v of deck.views) v.visible = v === deck.here;
  }

  function indexOf(id) {
    for (let i = 0; i < deck.views.length; ++i)
      if (deck.views[i].tabId === id) return i;
    return -1;
  }

  // a new tab at `url` ("" for none yet), at `at` (the end by default);
  // looked at unless `background`. The page, for a request to open into.
  function open(url, background, at) {
    const v = deck.page.createObject(deck.host, { tabId: ++deck.serial });
    v.wantsTab.connect((request) => deck.adopt(request, v));
    const list = deck.views.slice();
    const i = at === undefined || at < 0 || at > list.length ? list.length : at;
    list.splice(i, 0, v);
    const was = deck.here;
    deck.views = list;
    if (!background || deck.current < 0) deck.current = i;
    else deck.current = list.indexOf(was);
    if (url) v.url = url;
    return v;
  }

  // a page asked for a new tab or window: beside it, and in the background
  // when that is what was asked (a middle click)
  function adopt(request, from) {
    const bg = request.destination === WebEngineNewWindowRequest.InNewBackgroundTab;
    const v = deck.open("", bg, deck.views.indexOf(from) + 1);
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
      deck.emptied();
      return;
    }
    // the tab looked at closed: its right-hand neighbour, else its left
    deck.current = v === was ? Math.min(i, list.length - 1) : list.indexOf(was);
    v.destroy();
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
  }

  // the next tab, or the previous (`step` -1), round the end
  function step(by) {
    const n = deck.views.length;
    if (n > 1) deck.current = (deck.current + by + n) % n;
  }

  // ── WHAT TabBar CALLS THEM ─────────────────────────────────────────
  function bufShow(id) { deck.show(id); }
  function bufClose(id, _force) { deck.close(id); }
}
