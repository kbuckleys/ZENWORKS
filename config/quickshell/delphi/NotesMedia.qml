// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A PICTURE OR A VIDEO IN A RELEASE'S NOTES (NotesView), as wide as the
// notes and no taller than half a screen. One on the forge is fetched by
// curl into the cache first, never by Qt's own network (its HTTP/2 took the
// shell down — morpheus/Net); a file of this computer (the editor's
// Preview, before the release is saved) is shown as it is. A video waits
// for a click to play, muted until you unmute it. One that cannot be had
// says so, with its address to open.

import QtQuick
import QtMultimedia
import "../morpheus"

Item {
  id: med
  property string kind: "image"   // or "video"
  property string url: ""
  property string alt: ""
  // a relative address is a file beside the Markdown that names it (plato's
  // preview hands its directory in, NotesView.base); `addr` is what is shown
  property string base: ""
  readonly property string addr: med.base === "" || med.url === "" || /^[a-z][a-z0-9+.-]*:/i.test(med.url)
    ? med.url
    : Strings.fileUrl(med.url.charAt(0) === "/" ? med.url : med.base + "/" + med.decoded(med.url))
  function decoded(u) { try { return decodeURI(u); } catch (e) { return u; } }

  readonly property bool local: /^file:\/\//i.test(med.addr)
  // fetched only from the web: notes are anyone's words, and curl would
  // take a gopher:// or a -K as readily (audit, 2026-10-27)
  readonly property bool web: /^https?:\/\/[^\s]+$/i.test(med.addr)
  // the file shown: the local one, or the cached copy once it is in
  property string file: med.local ? med.addr : ""
  property bool failed: !med.local && !med.web
  readonly property bool loading: !med.local && med.file === "" && !med.failed
  readonly property int maxH: 520

  // the frame's own size, kept to the notes' width and maxH
  readonly property real natW: med.kind === "video" ? (player.item ? player.item.vw : 0) : pic.sourceSize.width
  readonly property real natH: med.kind === "video" ? (player.item ? player.item.vh : 0) : pic.sourceSize.height
  readonly property real k: med.natW > 0 && med.natH > 0
    ? Math.min(1, med.width / med.natW, med.maxH / med.natH) : 0
  readonly property real boxW: med.k > 0 ? med.natW * med.k : (med.kind === "video" ? Math.min(med.width, 640) : 0)
  readonly property real boxH: med.k > 0 ? med.natH * med.k : (med.kind === "video" ? Math.min(med.width, 640) * 9 / 16 : 0)

  height: med.failed || med.loading ? 34 : med.boxH

  // ── THE FETCH: once per address, kept in the cache ──
  // named by the address; its extension kept, so the player knows the
  // kind (GitHub's own videos have none: an .mp4)
  readonly property string ext: {
    const m = /\.(\w{2,4})(?:[?#]|$)/.exec(med.addr.replace(/^\w+:\/\/[^\/]*/, ""));
    return m ? "." + m[1].toLowerCase() : med.kind === "video" ? ".mp4" : "";
  }
  readonly property string cacheFile: med.local ? ""
    : Paths.cacheDir() + "/delphi/media/" + Qt.md5(med.addr) + med.ext
  // the one fetch the suite has (morpheus/Net.fetch): http(s) only, kept
  Component.onCompleted: if (med.web)
    Net.fetch(med.addr, med.cacheFile, { timeout: 300, maxBytes: med.kind === "video" ? 300000000 : 40000000 },
      (ok) => { if (!med) return; if (ok) med.file = Strings.fileUrl(med.cacheFile); else med.failed = true; })


  // loading, or not to be had
  Row {
    visible: med.loading || med.failed
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8
    Working { running: med.loading; anchors.verticalCenter: parent.verticalCenter }
    Text {
      visible: med.failed
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.StyledText
      text: (med.kind === "video" ? "A video" : "A picture") + " that could not be fetched — "
        + "<a href=\"" + med.addr.replace(/"/g, "%22") + "\">open it</a>"
      color: Zenon.accentMuted
      linkColor: Zenon.link
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
      onLinkActivated: (u) => Strings.openLink(u)
      HoverHandler { cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }
  }

  // ── A PICTURE ──
  Image {
    id: pic
    visible: med.kind === "image" && status === Image.Ready
    width: med.boxW
    height: med.boxH
    source: med.kind === "image" ? med.file : ""
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    mipmap: true
    // no hairline round it (user, 2026-10-27): the picture as it is
    onStatusChanged: if (status === Image.Error) med.failed = true
  }

  // ── A VIDEO: a still until played ──
  Rectangle {
    visible: med.kind === "video" && !med.loading && !med.failed
    width: med.boxW
    height: med.boxH
    color: Zenon.shade(0.4)
    radius: Zenon.radiusControl
    border.width: 1
    border.color: Zenon.border
    clip: true
    Loader {
      id: player
      anchors.fill: parent
      active: med.kind === "video" && med.file !== ""
      sourceComponent: VideoClip {
        source: med.file
        autoPlay: false
        muted: vidMute.muted
        fillMode: VideoOutput.PreserveAspectFit
        onFailed: med.failed = true
        // its first frame, so the still is the video's
        Component.onCompleted: pause()
        onEnded: seekMs(0)
      }
    }
    // play and pause: the whole frame, the mark in its middle while still
    MouseArea {
      anchors.fill: parent
      onClicked: if (player.item) player.item.toggle()
    }
    Rectangle {
      visible: !!player.item && !player.item.going
      anchors.centerIn: parent
      width: 56; height: 56; radius: 28
      color: Zenon.shade(0.55)
      Text {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: 2
        text: ""
        color: Zenon.white
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(22)
      }
    }
    // the sound, off to begin with
    Rectangle {
      id: vidMute
      property bool muted: true
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 8
      width: 30; height: 30; radius: 15
      color: Zenon.shade(0.55)
      Text {
        anchors.centerIn: parent
        text: vidMute.muted ? "" : ""
        color: Zenon.white
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(13)
      }
      MouseArea { anchors.fill: parent; onClicked: vidMute.muted = !vidMute.muted }
    }
  }
}
