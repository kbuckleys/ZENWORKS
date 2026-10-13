// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// IRIS' TWO PROFILES, made the way Qt 6.9+ asks: a WebEngineProfilePrototype
// is configured whole and THEN made into a profile, so nothing about where it
// keeps things can change under a page that is already using it.
//
//   normal   cookies, cache, history of its own, under the data and cache
//            directories host.py hands in
//   cloak    no storage name: off the record — Chromium keeps it in memory
//            and writes nothing, and it is gone when iris closes
//
// host.py builds this before the window, sets the shield on both (filtering
// is never off, cloak included) and hands them to the window as Iris.profile
// and Iris.cloak.

import QtQuick
import QtWebEngine
import IrisHost
import "../morpheus"
import "iris.js" as I

QtObject {
  required property string dataDir
  required property string cacheDir

  readonly property WebEngineProfilePrototype normalMade: WebEngineProfilePrototype {
    storageName: "iris"
    persistentStoragePath: dataDir + "/profile"
    cachePath: cacheDir + "/web"
    persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
  }
  readonly property WebEngineProfilePrototype cloakMade: WebEngineProfilePrototype { }

  // made once both prototypes are complete: asked for inside a binding, the
  // prototype was still being built and gave back nothing
  property WebEngineProfile normal: null
  property WebEngineProfile cloak: null
  Component.onCompleted: {
    normal = normalMade.instance();
    cloak = cloakMade.instance();
    for (const p of [normal, cloak]) {
      p.userScripts.insert(look());
      // a page's notification, as the desktop's own: notify-send, so howler
      // keeps it like any application's (only sites allowed to may send)
      p.presentNotification.connect((n) => { Iris.notify(n.title, n.message, String(n.origin)); n.show(); });
    }
  }

  // ── HOW EVERY PAGE WEARS THE SUITE ─────────────────────────────────
  // One style sheet, laid in iris' world before the page has a <head>, so
  // it is never seen otherwise:
  //
  //   the document's scrollbar   hidden: the suite's (morpheus/Scrollbar) is
  //                              drawn over the page instead. Body too, and
  //                              !important — a page's own scrollbar styling
  //                              brought Chromium's back beside the suite's
  //   a panel's own scrollbar    thin, in the suite's thumb and track
  //                              (Scrollbar's keyInk on nothing), where the
  //                              page has not styled its own
  //   selected text              the suite's selection (terminus' fields:
  //                              Zenon.selBg), the page's own ink kept
  //
  // In Zenon's colours of the moment: a new theme lays a new sheet, for every
  // page opened after it.
  function look() {
    const s = WebEngine.script();
    s.name = "iris-look";
    s.injectionPoint = WebEngineScript.DocumentCreation;
    s.worldId = WebEngineScript.ApplicationWorld;
    s.runsOnSubFrames = true;
    const css = "html{scrollbar-width:none !important}"
      // the face for text a page gives none (core/host.py's page faces);
      // :where() weighs nothing, so any face a page names wins
      + ":where(html){font-family:\"SF Pro Text\",sans-serif}"
      + "html::-webkit-scrollbar{display:none !important;width:0 !important;height:0 !important}"
      + ":where(*){scrollbar-width:thin;scrollbar-color:" + Zenon.hex(Zenon.keyInk) + " transparent}"
      + "::selection{background-color:" + rgba(Zenon.selBg) + "}";
    // the document's rules only in the top document: a frame's own
    // document is a panel, and keeps its (thin) bar
    s.sourceCode = I.sheetJs() + "(() => { const top = window === window.top;"
      + " const css = " + JSON.stringify(css) + ";"
      + " const add = () => __irisSheet('iris-look', top ? css : css.replace(/^html[^}]*}html[^}]*}/, ''));"
      + " if (document.documentElement) add();"
      + " else new MutationObserver((m, o) => { if (document.documentElement) { o.disconnect(); add(); } })"
      + ".observe(document, { childList: true }); })();";
    return s;
  }
  function rgba(c) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a.toFixed(3) + ")";
  }
  function relook() {
    for (const p of [normal, cloak]) {
      if (!p) continue;
      for (const old of p.userScripts.find("iris-look")) p.userScripts.remove(old);
      p.userScripts.insert(look());
    }
  }
  readonly property Connections themed: Connections {
    target: Zenon
    function onSelBgChanged() { relookSoon.restart(); }
    function onKeyInkChanged() { relookSoon.restart(); }
  }
  readonly property Timer relookSoon: Timer { interval: 200; onTriggered: relook() }
}
