// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┘┴└─┘
// https://github.com/kbuckleys/
//
// Which player is the one that matters, and what it is playing. Three things
// ask — the transport glyph, the track name beside it, and the hover panel
// behind both — and they must never be describing different tracks.
//
// Polled rather than bound: picking the active player means scanning the list,
// and a binding over Mpris.players does not re-run when one of those players
// starts or stops. Once a player IS picked, its own properties are bound
// normally, so play/pause is instant.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
  id: root

  property var player: null
  property string title: ""
  property string artist: ""
  property string album: ""
  property string artUrl: ""

  readonly property bool active: root.player !== null
  readonly property bool playing: root.player ? root.player.isPlaying : false
  readonly property real length: root.player && root.player.lengthSupported ? root.player.length : 0
  readonly property bool canSeek: root.player ? root.player.canSeek : false
  // polled position — Mpris position does not push updates while playing,
  // so we poll the player every 500ms when active. Without this the seek
  // bar sits still even though the track advances.
  property real _polledPos: 0
  readonly property real position: root._polledPos
  //
  // ONLY WHILE PLAYING. It polled whenever a player with a length was up,
  // paused included — two bus calls a second for a number that cannot move,
  // and each one a chance to catch a player between tracks with no position
  // to give (spotifyd answers that with an error, which lands in the log).
  // A pause is still read once, as it stops, so the bar shows where it was
  // left; and every read now asks positionSupported first, which the one on
  // a state change did not.
  function readPos() {
    if (root.player && root.player.positionSupported)
      root._polledPos = root.player.position;
  }
  Timer {
    interval: 500
    running: root.active && root.length > 0 && root.playing
    repeat: true
    onTriggered: root.readPos()
    onRunningChanged: root.readPos()
  }
  onPlayerChanged: root._polledPos = root.player && root.player.positionSupported ? root.player.position : 0

  // A player that has gone away mid-call leaves playerctl as the fallback, so
  // the buttons still do something rather than silently failing.
  function previous() {
    if (root.player) root.player.previous();
    else Quickshell.execDetached(["playerctl", "previous"]);
  }

  function next() {
    if (root.player) root.player.next();
    else Quickshell.execDetached(["playerctl", "next"]);
  }

  function toggle() {
    if (root.player) root.player.togglePlaying();
    else Quickshell.execDetached(["playerctl", "play-pause"]);
  }

  function seek(pos) {
    if (root.player && root.canSeek) {
      // Mpris position is in seconds; clamp to length if known
      const p = Math.max(0, root.length > 0 ? Math.min(pos, root.length) : pos);
      root.player.position = p;
      // shown at once — while paused nothing polls to pick it up
      root._polledPos = p;
    } else {
      const sec = Math.round(pos);
      Quickshell.execDetached(["playerctl", "position", String(sec)]);
    }
  }

  function formatTime(s) {
    if (!isFinite(s) || s < 0) s = 0;
    const m = Math.floor(s / 60);
    const sec = Math.floor(s % 60);
    return m + ":" + (sec < 10 ? "0" + sec : String(sec));
  }

  // playing beats paused beats nothing
  function scan() {
    const players = Mpris.players.values;
    let paused = null;
    for (let i = 0; i < players.length; ++i) {
      const p = players[i];
      if (p.isPlaying) { root.adopt(p); return; }
      if (paused === null && p.playbackState === MprisPlaybackState.Paused) paused = p;
    }
    root.adopt(paused);
  }

  function adopt(p) {
    root.player = p ?? null;
    root.title  = p ? p.trackTitle  : "";
    root.artist = p ? p.trackArtist : "";
    root.album  = p ? p.trackAlbum  : "";
    root.artUrl = p ? p.trackArtUrl : "";
  }

  // Rescanned when something about a player changes, not on a clock: which
  // one is playing and what it is playing are both announced. callLater folds
  // the handful of signals one track change sends into a single scan.
  function rescan() { Qt.callLater(root.scan); }

  Instantiator {
    model: Mpris.players
    delegate: Connections {
      required property var modelData
      target: modelData
      function onPlaybackStateChanged() { root.rescan(); }
      function onIsPlayingChanged() { root.rescan(); }
      function onTrackTitleChanged() { root.rescan(); }
      function onTrackArtistChanged() { root.rescan(); }
      function onTrackAlbumChanged() { root.rescan(); }
      function onTrackArtUrlChanged() { root.rescan(); }
    }
    onObjectAdded: root.rescan()
    onObjectRemoved: root.rescan()
  }

  // A safety net for a player that changes without saying so; it was the
  // only mechanism when it ran every second.
  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.scan()
  }

  Component.onCompleted: root.scan()
}
