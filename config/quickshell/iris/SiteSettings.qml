// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A SITE'S SETTINGS — the bubble that hangs from the line's site chip (the
// lock at the address' left): how the page is connected, and what this site
// may do, each a choice of the suite's (terminus/Segments) and kept for the
// site (History's `sites`, keyed by its host without "www."):
//
//   content blocking   the shield on this site, or off (core/shield.py
//                      lets it through, requests and hiding alike)
//   autoplay           media plays on its own, or waits for a click
//   pop-ups            tabs it opens nobody clicked for: held back (the
//                      line offers them) or let through
//   permissions        notifications, location, camera, microphone, screen
//                      — Chromium's own answers for the origin, Allow / Ask /
//                      Block, changed here as the page's card would
//
// A cloak tab changes nothing kept: its choices act on the page and go with
// it. The bubble is terminus/BubbleSurface, a popup surface of its own, so
// it is frosted, shadowed and faded as the shell's bubbles are; a click
// anywhere else puts it away.

import QtQuick
import QtWebEngine
import "../morpheus"
import "../terminus" as Term
import IrisHost
import "iris.js" as I

Term.BubbleSurface {
  id: site
  grab: true
  cardWidth: 400
  fit: false
  onDismissed: site.shown = false

  property var page: null
  readonly property string url: site.page ? String(site.page.url) : ""
  readonly property string key: I.siteKey(site.url)
  readonly property bool secure: /^https:/i.test(site.url)
  readonly property bool cloaked: !!site.page && site.page.cloaked
  // what is set for it by hand, re-read as it opens and as it changes
  property var set: ({})
  property int epoch: 0

  function openFor(page, chip) {
    site.page = page;
    site.target = chip;
    site.reread();
    site.shown = true;
  }
  function reread() {
    site.set = site.key ? Iris.site(site.key) : {};
    site.epoch++;
  }
  function choose(k, v) {
    if (site.cloaked) {
      // a cloak tab's choice acts on its page alone
      const s = Object.assign({}, site.page.siteSet);
      s[k] = v;
      site.page.siteSet = s;
      site.page.settings.playbackRequiresUserGesture = s.autoplay === 0;
      site.set = s;
      return;
    }
    Iris.setSite(site.key, k, v);
    site.reread();
    if (site.page) site.page.applySite();
    // blocking changed: the page as it now should be
    if (k === "shield" && site.page) site.page.reload();
  }

  // ── PERMISSIONS, as Chromium has them for the origin ───────────────
  readonly property var kinds: [
    [WebEnginePermission.PermissionType.Notifications, "Notifications", "\u{F009A}"],
    [WebEnginePermission.PermissionType.Geolocation, "Location", "\u{F034E}"],
    [WebEnginePermission.PermissionType.MediaVideoCapture, "Camera", "\u{F0100}"],
    [WebEnginePermission.PermissionType.MediaAudioCapture, "Microphone", "\u{F036C}"],
    [WebEnginePermission.PermissionType.DesktopVideoCapture, "Screen sharing", "\u{F0379}"],
    [WebEnginePermission.PermissionType.ClipboardReadWrite, "Clipboard", "\u{F0147}"]
  ]
  function permission(type) {
    if (!site.page || !site.secure && !/^http:/i.test(site.url)) return null;
    site.epoch;
    return site.page.profile.queryPermission(site.page.url, type);
  }
  function stateOf(p) {
    if (!p) return "ask";
    const S = WebEnginePermission.State;
    return p.state === S.Granted ? "allow" : p.state === S.Denied ? "block" : "ask";
  }
  function setPermission(type, v) {
    const p = site.permission(type);
    if (!p) return;
    if (v === "allow") p.grant(); else if (v === "block") p.deny(); else p.reset();
    site.epoch++;
  }

  // ── WHAT IT SHOWS ──────────────────────────────────────────────────
  // the site and how it is reached
  Row {
    spacing: 10
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: site.secure ? "\u{F033E}" : "\u{F033F}"
      color: site.secure ? Zenon.cyan : Zenon.yellow
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(18)
    }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      Text {
        text: site.key || I.restOf(site.url)
        color: Zenon.white
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(15)
      }
      Text {
        text: site.secure ? "Secure connection" : "Not secure — sent over plain HTTP"
        color: site.secure ? Zenon.muted : Zenon.yellow
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
    }
  }

  Rectangle { width: 372; height: 1; color: Zenon.border }

  // one setting: its glyph and name, its choices at the right
  component Setting: Item {
    id: row
    property string glyph: ""
    property string label: ""
    property alias options: seg.options
    property alias current: seg.current
    signal chose(string value)
    width: 372
    height: seg.height + 2
    Text {
      id: g
      anchors.verticalCenter: parent.verticalCenter
      width: Zenon.px(20)
      text: row.glyph
      color: Zenon.keyInk
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(15)
    }
    Text {
      anchors.left: g.right
      anchors.leftMargin: 8
      anchors.right: seg.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      text: row.label
      elide: Text.ElideRight
      color: Zenon.white
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
    Term.Segments {
      id: seg
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textSize: Zenon.px(12)
      onChose: (v) => row.chose(v)
    }
  }

  Setting {
    glyph: "\u{F0565}"
    label: "Content blocking"
    options: [["1", "On"], ["0", "Off"]]
    current: site.set.shield === 0 ? "0" : "1"
    onChose: (v) => site.choose("shield", v === "1" ? -1 : 0)
  }
  Setting {
    glyph: "\u{F040A}"
    label: "Autoplay"
    options: [["1", "Allow"], ["0", "Block"]]
    current: site.set.autoplay === 0 ? "0" : "1"
    onChose: (v) => site.choose("autoplay", v === "1" ? -1 : 0)
  }
  Setting {
    glyph: "\u{F03CC}"
    label: "Pop-ups"
    options: [["1", "Allow"], ["0", "Block"]]
    current: site.set.popups === 1 ? "1" : "0"
    onChose: (v) => site.choose("popups", v === "1" ? 1 : -1)
  }

  Rectangle { width: 372; height: 1; color: Zenon.border }

  Repeater {
    model: site.kinds
    delegate: Setting {
      required property var modelData
      glyph: modelData[2]
      label: modelData[1]
      options: [["allow", "Allow"], ["ask", "Ask"], ["block", "Block"]]
      current: site.stateOf(site.permission(modelData[0]))
      onChose: (v) => site.setPermission(modelData[0], v)
    }
  }
}
