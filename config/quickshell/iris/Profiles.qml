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
      p.userScripts.insert(bareScrollbar());
      // a page's notification, as the desktop's own: notify-send, so howler
      // keeps it like any application's (only sites allowed to may send)
      p.presentNotification.connect((n) => { Iris.notify(n.title, n.message, String(n.origin)); n.show(); });
    }
  }

  // ── THE DOCUMENT'S OWN SCROLLBAR, HIDDEN ───────────────────────────
  // The suite's (morpheus/Scrollbar) is drawn over the page instead; a
  // panel inside a page keeps its own. Laid in iris' world, before the page
  // has a <head>, so it is never seen.
  function bareScrollbar() {
    const s = WebEngine.script();
    s.name = "iris-scrollbar";
    s.injectionPoint = WebEngineScript.DocumentCreation;
    s.worldId = WebEngineScript.ApplicationWorld;
    s.runsOnSubFrames = false;
    s.sourceCode = "(() => { const css = 'html{scrollbar-width:none !important}html::-webkit-scrollbar{display:none !important}';"
      + " const add = () => { const st = document.createElement('style'); st.textContent = css;"
      + " (document.head || document.documentElement).appendChild(st); };"
      + " if (document.documentElement) add();"
      + " else new MutationObserver((m, o) => { if (document.documentElement) { o.disconnect(); add(); } })"
      + ".observe(document, { childList: true }); })();";
    return s;
  }
}
