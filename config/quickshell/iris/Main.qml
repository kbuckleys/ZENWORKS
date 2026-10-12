// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// IRIS' WINDOW — the tab strip, the address bar, the pages. Built of the
// suite's own parts, not copies of them:
//
//   the strip      plato/editor/TabBar (terminus' strip), fed by Tabs.qml;
//                  hidden while there is one tab, as plato's is
//   the bar        the window's ground (Zenon.layerBg), so the active tab
//                  runs on into it as terminus' does into its path bar;
//                  back / forward / reload are morpheus/TransportKey, the
//                  address line is terminus/BulkField
//   the pages      Page.qml, one per tab, made and destroyed with it
//
//   Ctrl+T new tab · Ctrl+W close · Ctrl+L / F6 the address line ·
//   Ctrl+Tab / Ctrl+Shift+Tab next / previous · Ctrl+R / F5 reload ·
//   Alt+Left / Alt+Right back / forward · Escape in the line puts it back
//
// IRIS_SELFTEST="<url> <url> …" loads each page in turn in one tab, reports
// the shield's numbers for each, works the tabs (open, switch, move, close),
// reports which renderer WebGL got and that the profiles are still there,
// and quits.

import QtQuick
import QtQuick.Window
import QtWebEngine
import "../morpheus"
import "../plato/editor" as Plato
import "../terminus" as Term
import IrisHost
import "iris.js" as I

Window {
  id: win
  width: 1280; height: 860
  visible: true
  title: deck.here && deck.here.title ? deck.here.title + " — Iris" : "Iris"
  color: "transparent"

  readonly property font face: Qt.font({ family: Zenon.face, weight: Zenon.weight, pixelSize: Zenon.px(14) })

  Tabs {
    id: deck
    host: pages
    page: Component { Page { } }
    onEmptied: Qt.quit()
  }

  // ── THE STRIP ──────────────────────────────────────────────────────
  Plato.TabBar {
    id: strip
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    ed: deck
    client: deck
    face: win.face
  }

  // ── THE BAR ────────────────────────────────────────────────────────
  Rectangle {
    id: bar
    anchors.top: strip.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 42
    color: Zenon.layerBg

    Row {
      id: keys
      anchors.left: parent.left
      anchors.leftMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 16
      TransportKey {
        glyph: "\u{F004D}"
        size: Zenon.px(18)
        enabled: !!deck.here && deck.here.canGoBack
        ink: enabled ? Zenon.white : Zenon.muted
        onActivated: deck.here.goBack()
      }
      TransportKey {
        glyph: "\u{F0054}"
        size: Zenon.px(18)
        enabled: !!deck.here && deck.here.canGoForward
        ink: enabled ? Zenon.white : Zenon.muted
        onActivated: deck.here.goForward()
      }
      TransportKey {
        // stop while loading, reload otherwise
        glyph: deck.here && deck.here.loading ? "\u{F0156}" : "\u{F0450}"
        size: Zenon.px(18)
        enabled: !!deck.here
        onActivated: deck.here.loading ? deck.here.stop() : deck.here.reload()
      }
    }

    Term.BulkField {
      id: address
      anchors.left: keys.right
      anchors.leftMargin: 16
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      textSize: Zenon.px(14)
      ghost: "Search or type an address"
      onAccepted: win.go(address.text)
      // Escape: what was typed goes, the page's address comes back
      Keys.onEscapePressed: { win.showAddress(true); win.toPage(); }
    }

    // how far the page has loaded, along the bar's foot
    Rectangle {
      anchors.bottom: parent.bottom
      height: 2
      width: deck.here ? parent.width * deck.here.loadProgress / 100 : 0
      visible: !!deck.here && deck.here.loading
      color: Zenon.cyan
      Behavior on width { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase } }
    }
    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: 1
      color: Zenon.border
    }
  }

  // ── THE PAGES ──────────────────────────────────────────────────────
  Item {
    id: pages
    anchors.top: bar.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
  }

  // go where the line says: an address, or a search (iris.js)
  function go(typed) {
    const url = I.toUrl(typed);
    if (url === "" || !deck.here) return;
    deck.here.url = url;
    win.toPage();
  }
  // the line shows the page's address — unless it is being typed in, or
  // `force` (Escape)
  function showAddress(force) {
    if (force || !address.focused) address.text = I.shown(deck.here ? deck.here.url : "");
  }
  function toPage() { if (deck.here) deck.here.forceActiveFocus(); }
  // a new tab: blank, and the line ready for it
  function newTab() { deck.open("about:blank"); address.claim(); }

  Connections {
    target: deck
    function onHereChanged() { win.showAddress(true); if (!address.focused) win.toPage(); }
  }
  Connections {
    target: deck.here
    ignoreUnknownSignals: true
    function onUrlChanged() { win.showAddress(false); }
  }

  Shortcut { sequence: "Ctrl+T"; onActivated: win.newTab() }
  Shortcut { sequence: "Ctrl+W"; onActivated: if (deck.here) deck.close(deck.here.tabId) }
  Shortcut { sequences: ["Ctrl+L", "F6"]; onActivated: address.claim() }
  Shortcut { sequence: "Ctrl+Tab"; onActivated: deck.step(1) }
  Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: deck.step(-1) }
  Shortcut { sequences: ["Ctrl+R", "F5"]; onActivated: if (deck.here) deck.here.reload() }
  Shortcut { sequence: "Alt+Left"; onActivated: if (deck.here) deck.here.goBack() }
  Shortcut { sequence: "Alt+Right"; onActivated: if (deck.here) deck.here.goForward() }

  Component.onCompleted: {
    if (Iris.selftest) { test.begin(); return; }
    const start = Iris.startUrl;
    deck.open(start && start !== "about:blank" ? start : "about:blank");
    if (!start || start === "about:blank") address.claim();
  }

  // ── self-test ──────────────────────────────────────────────────────────
  QtObject {
    id: test
    readonly property var pages: Iris.startUrl.split(/\s+/).filter(s => s)
    property int at: 0
    property var before: ({ seen: 0, blocked: 0, spent: 0 })
    property var page: null
    function begin() {
      test.page = deck.open(test.pages[0]);
      test.page.loadingChanged.connect((req) => {
        if (req.status === WebEngineView.LoadSucceededStatus) settle.restart();
        else if (req.status === WebEngineView.LoadFailedStatus)
          Iris.report("load failed: " + req.url + " " + req.errorString);
      });
    }
    // the shell's Zenon as iris wears it, and the toolkit pieces iris builds on
    function toolkit() {
      Iris.report("zenon theme " + Zenon.themeName + "  cyan " + Zenon.hex(Zenon.cyan)
                  + "  ground " + Zenon.hex(Zenon.ground) + "  face " + Zenon.face + "  fast " + Zenon.fast);
      for (const f of ["morpheus/Elastic", "morpheus/ElasticScroll", "morpheus/TabGlass", "morpheus/Frost",
                       "morpheus/ScrollEdge", "morpheus/DialogButton", "morpheus/Sheet", "terminus/BubbleCard"]) {
        const c = Qt.createComponent("../" + f + ".qml");
        Iris.report("toolkit " + f + ": " + (c.status === Component.Ready ? "ok" : c.errorString().trim()));
      }
    }
    // the tabs, worked as a hand would: two more, switch, carry one, close
    function workTabs() {
      const names = () => deck.tabs.map(t => (t.current ? "*" : "") + t.name).join(" | ");
      Iris.report("tabs start: " + names() + "  strip " + strip.height + "px  line \"" + address.text + "\"");
      deck.open("about:blank");
      deck.open("data:text/html,<title>Third</title>", true);
      Iris.report("tabs opened: " + names());
      deck.step(1);
      Iris.report("tabs stepped: " + names());
      deck.moveTab(2, 0);
      Iris.report("tabs moved: " + names());
      deck.close(deck.here.tabId);
      Iris.report("tabs closed one: " + names() + "  line \"" + address.text + "\"");
      win.go("arch linux wiki");
      Iris.report("typed words go to: " + (deck.here.url + "").slice(0, 40));
    }
    function finish() {
      test.page.runJavaScript(
        "(() => { const g = document.createElement('canvas').getContext('webgl2');" +
        " if (!g) return 'no webgl2';" +
        " const d = g.getExtension('WEBGL_debug_renderer_info');" +
        " return d ? g.getParameter(d.UNMASKED_RENDERER_WEBGL) : g.getParameter(g.RENDERER); })()",
        r => {
          Iris.report("webgl renderer: " + r);
          // the profiles still there at the end (they once were collected)
          Iris.report("profiles alive: " + (Iris.profile !== null && Iris.profile.storageName === "iris")
                      + " / cloak off the record: " + (Iris.cloak !== null && Iris.cloak.offTheRecord));
          Qt.quit();
        });
    }
  }

  Timer {
    id: settle
    interval: 6000
    onTriggered: {
      if (test.at === 0) test.toolkit();
      const s = Iris.shieldStats();
      const n = s.seen - test.before.seen, us = s.meanUs * s.seen - test.before.spent;
      Iris.report(test.pages[test.at] + "  requests " + n + "  blocked " + (s.blocked - test.before.blocked)
                  + "  mean " + (n ? (us / n).toFixed(1) : 0) + "us  worst-so-far " + s.worstUs + "us");
      test.before = { seen: s.seen, blocked: s.blocked, spent: s.meanUs * s.seen };
      if (++test.at < test.pages.length) { test.page.url = test.pages[test.at]; return; }
      test.workTabs();
      test.finish();
    }
  }

  Timer {
    interval: 90000; running: Iris.selftest
    onTriggered: { Iris.report("self-test timed out"); Qt.quit(); }
  }
}
