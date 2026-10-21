// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// VIDEOCLIP — Qt's player and its picture, for whoever plays a video: picasso's
// viewer and argus' editor. It was picasso's alone (its vidComp); argus wanted
// the same player, so it lives here (2026-10-20).
//
//     VideoClip { source: Strings.fileUrl(path); muted: m; onEnded: …; onFailed: (msg) => … }
//
// What it says: vw, vh (the frame as encoded), position, duration (ms),
// going (playing). What it does: play(), pause(), toggle(), seekBy(ms),
// seekTo(fraction), seekMs(ms). `autoPlay` starts it as soon as it can.

import QtQuick
import QtMultimedia

Item {
  id: vc

  property url source: ""
  property bool muted: false
  property bool autoPlay: true
  property int fillMode: VideoOutput.Stretch

  readonly property real vw: vout.sourceRect.width
  readonly property real vh: vout.sourceRect.height
  readonly property int position: mp.position
  readonly property int duration: mp.duration
  readonly property bool going: mp.playbackState === MediaPlayer.PlayingState
  readonly property bool ready: mp.mediaStatus === MediaPlayer.LoadedMedia
    || mp.mediaStatus === MediaPlayer.BufferedMedia || mp.mediaStatus === MediaPlayer.EndOfMedia

  signal ended()
  signal failed(string message)

  function play() { mp.play(); }
  function pause() { mp.pause(); }
  function toggle() { if (vc.going) mp.pause(); else mp.play(); }
  function seekMs(ms) { mp.position = Math.max(0, Math.min(mp.duration, Math.round(ms))); }
  function seekBy(ms) { vc.seekMs(mp.position + ms); }
  function seekTo(f) { mp.position = Math.max(0, Math.min(1, f)) * mp.duration; }

  MediaPlayer {
    id: mp
    source: vc.source
    videoOutput: vout
    audioOutput: AudioOutput { muted: vc.muted }
    onMediaStatusChanged: if (mp.mediaStatus === MediaPlayer.EndOfMedia) vc.ended()
    onErrorOccurred: (err, msg) => vc.failed(msg)
    Component.onCompleted: if (vc.autoPlay) mp.play()
  }
  VideoOutput { id: vout; anchors.fill: parent; fillMode: vc.fillMode }
}
