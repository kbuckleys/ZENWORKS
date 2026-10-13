// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE RIGHT-CLICK MENU — the suite's card (morpheus/CardBody, every menu's),
// not Chromium's. A page's context menu request is taken (accepted, so
// Chromium draws nothing) and answered here, for what was under the pointer:
//
//   a link       open in a new tab · in a cloak tab · copy · save
//   a picture    open in a new tab · save · copy · copy its address
//   video/sound  save · copy its address
//   selected     copy · search for it
//   a field      the speller's words, then undo · redo · cut · copy ·
//                paste · paste as plain text · select all, each as the
//                field allows it
//   the page     back · forward · reload · save page · view source
//
// Every action is Chromium's own (triggerWebAction), so the clipboard, a
// download and the page's own undo history behave as they always do.
//
// THE SHELL'S MENU, NOT ONE DRAWN IN THE WINDOW (user, 2026-10-13: "wrong
// shadows, no frost, no animation"): the card is CardBody in a popup surface
// of its own (morpheus/surface/PopupSurface), as CardPopup hangs it — the
// compositor frosts it, it casts MenuShadow and fades and grows in as every
// menu does. Up / Down walk its rows, Return picks; a click anywhere else,
// Escape, or the page moving on puts it away.

import QtQuick
import QtWebEngine
import QtQuick.Window
import "../morpheus"
import "../morpheus/surface"
import "iris.js" as I

Item {
  id: menu
  // the window the card hangs from
  required property Window host

  // the tabs (Tabs.qml), for what opens a page
  required property var deck

  property var page: null
  property var rows: []            // CardBody's rows (kept while it fades)
  property var acts: []            // what each row does, by index
  property point at: Qt.point(0, 0)
  property bool open: false
  property int active: -1

  function close() {
    if (!menu.open) return;
    const p = menu.page;
    menu.open = false;
    menu.active = -1;
    menu.page = null;
    if (p) p.forceActiveFocus();
  }

  // ── BUILT FOR WHAT WAS CLICKED ─────────────────────────────────────
  function show(page, req, where) {
    req.accepted = true;
    const W = WebEngineView, rows = [], acts = [];
    const add = (text, icon, hint, act, on) => {
      rows.push({ text: text, icon: icon || "", hint: hint || "", enabled: on !== false });
      acts.push(act);
    };
    const sep = () => { if (rows.length && !rows[rows.length - 1].isSeparator) { rows.push({ isSeparator: true }); acts.push(null); } };
    const web = (a) => () => page.triggerWebAction(a);
    const tab = (url, cloak) => () => menu.deck.open(String(url), true, menu.deck.views.indexOf(page) + 1, cloak || page.cloaked);
    const link = String(req.linkUrl || ""), media = String(req.mediaUrl || "");
    const sel = String(req.selectedText || "").trim(), edit = req.isContentEditable, f = req.editFlags;

    if (edit && req.misspelledWord) {
      for (const w of (req.spellCheckerSuggestions || []).slice(0, 4))
        add(w, "", "", ((word) => () => page.replaceMisspelledWord(word))(w));
      sep();
    }
    if (link !== "") {
      add("Open link in new tab", "\u{F03CC}", "", tab(link));
      if (!page.cloaked) add("Open link in cloak tab", "\u{F05F9}", "", tab(link, true));
      add("Copy link address", "\u{F0337}", "", web(W.CopyLinkToClipboard));
      add("Save link as…", "\u{F01DA}", "", web(W.DownloadLinkToDisk));
      sep();
    }
    if (req.mediaType === ContextMenuRequest.MediaTypeImage) {
      add("Open image in new tab", "\u{F02E9}", "", tab(media));
      add("Save image", "\u{F01DA}", "", web(W.DownloadImageToDisk));
      add("Copy image", "\u{F018F}", "", web(W.CopyImageToClipboard));
      add("Copy image address", "\u{F0337}", "", web(W.CopyImageUrlToClipboard));
      sep();
    } else if (req.mediaType === ContextMenuRequest.MediaTypeVideo || req.mediaType === ContextMenuRequest.MediaTypeAudio) {
      add("Save " + (req.mediaType === ContextMenuRequest.MediaTypeVideo ? "video" : "audio"), "\u{F01DA}", "", web(W.DownloadMediaToDisk));
      add("Copy media address", "\u{F0337}", "", web(W.CopyMediaUrlToClipboard));
      sep();
    }
    if (edit) {
      add("Undo", "\u{F054C}", "Ctrl+Z", web(W.Undo), !!(f & ContextMenuRequest.CanUndo));
      add("Redo", "\u{F044E}", "Ctrl+Shift+Z", web(W.Redo), !!(f & ContextMenuRequest.CanRedo));
      sep();
      add("Cut", "\u{F0190}", "Ctrl+X", web(W.Cut), !!(f & ContextMenuRequest.CanCut));
      add("Copy", "\u{F018F}", "Ctrl+C", web(W.Copy), !!(f & ContextMenuRequest.CanCopy));
      add("Paste", "\u{F0192}", "Ctrl+V", web(W.Paste), !!(f & ContextMenuRequest.CanPaste));
      add("Paste as plain text", "\u{F0192}", "Ctrl+Shift+V", web(W.PasteAndMatchStyle), !!(f & ContextMenuRequest.CanPaste));
      add("Select all", "\u{F0486}", "Ctrl+A", web(W.SelectAll), !!(f & ContextMenuRequest.CanSelectAll));
    } else if (sel !== "") {
      add("Copy", "\u{F018F}", "Ctrl+C", web(W.Copy));
      // one line, whatever the selection spans (a name and a title below it
      // wrapped the row onto two, over "Copy")
      const flat = sel.replace(/\s+/g, " ");
      const shortSel = flat.length > 28 ? flat.slice(0, 27) + "…" : flat;
      add("Search for “" + shortSel + "”", "\u{F0349}", "", tab(I.SEARCH + encodeURIComponent(sel)));
    } else if (link === "" && media === "") {
      add("Back", "\u{F004D}", "Alt+Left", web(W.Back), page.canGoBack);
      add("Forward", "\u{F0054}", "Alt+Right", web(W.Forward), page.canGoForward);
      add("Reload", "\u{F0450}", "Ctrl+R", web(W.Reload));
      sep();
      add("Save page", "\u{F0193}", "", web(W.SavePage));
      add("View source", "\u{F0169}", "", web(W.ViewSource));
    }
    while (rows.length && rows[rows.length - 1].isSeparator) { rows.pop(); acts.pop(); }
    if (!rows.length) return;
    menu.page = page;
    menu.acts = acts;
    menu.rows = rows;
    menu.at = where;
    menu.active = -1;
    menu.open = true;
  }

  // ── THE CARD, ON A SURFACE OF ITS OWN ──────────────────────────────
  readonly property int pad: 36
  readonly property real cardW: Zenon.menuWidth + 60
  readonly property real cardH: menu.rows.reduce((h, r) => h + card.rowHeight(r), 0) + 2 * Zenon.menuCardPad + 2
  function step(by) {
    const n = menu.rows.length;
    let i = menu.active;
    for (let k = 0; k < n; ++k) {
      i = (i + by + n) % n;
      const r = menu.rows[i];
      if (r && !r.isSeparator && r.enabled !== false) { menu.active = i; return; }
    }
  }
  function pick(i) {
    const act = menu.acts[i];
    menu.close();
    if (act) act();
  }
  readonly property alias surface: surf
  PopupSurface {
    id: surf
    host: menu.host
    open: menu.open
    width: menu.cardW + 2 * menu.pad
    height: menu.cardH + 2 * menu.pad
    // the card's corner at the pointer, turned back from the window's right
    // and bottom edges
    at: Qt.point(Math.max(0, Math.min(menu.host.width - menu.cardW - 4, menu.at.x)) - menu.pad,
                 Math.max(0, Math.min(menu.host.height - menu.cardH - 4, menu.at.y)) - menu.pad)
    onDismissed: menu.close()
    onKeyPressed: (e) => {
      if (e.key === Qt.Key_Down) { e.accepted = true; menu.step(1); }
      else if (e.key === Qt.Key_Up) { e.accepted = true; menu.step(-1); }
      else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && menu.active >= 0) { e.accepted = true; menu.pick(menu.active); }
    }
    CardBody {
      id: card
      anchors.fill: parent
      pad: menu.pad
      model: menu.rows
      shade: surf.shade
      activeIndex: menu.active
      onChosen: (i) => menu.pick(i)
    }
  }
  // the page it was for, gone somewhere else
  Connections {
    target: menu.page
    ignoreUnknownSignals: true
    function onUrlChanged() { menu.close(); }
  }
}
