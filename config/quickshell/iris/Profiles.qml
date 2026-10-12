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
  }
}
