// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE TAB'S PAGE — a WebEngineView on the normal profile. Tabs.qml makes and
// destroys these; only the tab being looked at is visible. A page that asks
// for a new tab or window (a middle click, target=_blank, window.open) hands
// the request to Tabs, which opens it beside this one.

import QtQuick
import QtWebEngine
import IrisHost

WebEngineView {
  id: page
  // the strip's id for it (TabBar keys its cells on this)
  property int tabId: 0
  signal wantsTab(var request)

  anchors.fill: parent
  visible: false
  profile: Iris.profile
  onNewWindowRequested: (request) => {
    if (Iris.selftest) Iris.report("page " + page.tabId + " asked for a new tab: " + request.requestedUrl
                                   + " (" + request.destination + ", user " + request.isUserInitiated + ")");
    page.wantsTab(request);
  }
}
