// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PICTURES AND VIDEOS DROPPED IN FROM ANYWHERE (user, 2026-10-27: "drag and
// drop support so i can drop the images from external sources, just like
// other apps have it"). Over the release editor's notes. Whatever the drag
// carries becomes a file of this computer, which the notes take as a
// file:// line and saving the release sends to the forge
// (core rest.attach_media):
//   a file (terminus, a file manager)      as it is
//   a picture from a browser (its address)  fetched by curl
//   a picture as data (a screenshot tool)   written out
// into ~/.cache/delphi/dropped. Words dropped go in as words.
//
//   MediaDrop { anchors.fill: well; onMedia: (paths, at) => …; onWords: (t, at) => … }
//
// `at` is where it was dropped, in this item; `over` while a drag hovers,
// `busy` while a fetch is out.

import QtQuick
import Quickshell.Io
import "../morpheus"
import "delphi.js" as D

DropArea {
  id: drop
  signal media(var paths, point at)
  signal words(string text, point at)
  signal failed(string why)

  readonly property bool over: drop.containsDrag
  property int out: 0
  readonly property bool busy: drop.out > 0
  readonly property string dir: Paths.cacheDir() + "/delphi/dropped"

  readonly property var imageTypes: ["image/png", "image/jpeg", "image/gif", "image/webp", "image/avif", "image/bmp"]

  onEntered: (d) => { if (!d.hasUrls && !d.hasText && !drop.dataType(d)) d.accepted = false; }
  // the first picture type the drag offers as data, or ""
  function dataType(d) {
    const fs = d.formats || [];
    for (const t of drop.imageTypes) if (fs.indexOf(t) >= 0) return t;
    return "";
  }
  onDropped: (d) => {
    const at = Qt.point(d.x, d.y);
    const kind = drop.dataType(d);
    const got = D.dropSorted(d.hasUrls ? d.urls : [], d.hasText ? d.text : "", kind !== "");
    d.acceptProposedAction();
    if (got.files.length) drop.media(got.files, at);
    for (const u of got.web) drop.fetch(u, at);
    if (got.files.length || got.web.length) return;
    // no file and no address: the picture itself, as bytes
    if (kind !== "") {
      const buf = d.getDataAsArrayBuffer(kind);
      if (buf && buf.byteLength > 0) { drop.write(D.base64Of(buf), kind.split("/")[1].replace("jpeg", "jpg"), at); return; }
    }
    if (got.words.trim() !== "") drop.words(got.words, at);
  }

  // a web picture into the cache, named by its address; its extension from
  // what the server says it is when the address has none
  function fetch(url, at) {
    drop.out++;
    fetcher.createObject(drop, { at: at, url: url, running: true });
  }
  Component {
    id: fetcher
    Process {
      id: f
      property string url: ""
      property point at
      property string said: ""
      command: ["sh", "-c",
        'd=$1; mkdir -p "$d" || exit 1; f="$d/$(printf %s "$2" | md5sum | cut -c1-16)"; '
        + 't=$(curl -fsSL --max-time 120 --max-filesize 300000000 -o "$f.part" -w "%{content_type}" "$2") || { rm -f "$f.part"; exit 1; }; '
        + 'case $t in image/png*) e=png;; image/jpeg*) e=jpg;; image/gif*) e=gif;; image/webp*) e=webp;; image/avif*) e=avif;; '
        + 'image/svg*) e=svg;; video/mp4*) e=mp4;; video/webm*) e=webm;; video/quicktime*) e=mov;; '
        + '*) n=${2%%[?#]*}; e=${n##*.}; case $e in */*|"") rm -f "$f.part"; exit 2;; esac;; esac; '
        + 'mv -f "$f.part" "$f.$e" && printf %s "$f.$e"',
        "sh", drop.dir, f.url]
      stdout: StdioCollector { onStreamFinished: f.said = this.text }
      onExited: (code) => {
        drop.out--;
        if (code === 0 && f.said !== "") drop.media([f.said], f.at);
        else drop.failed(code === 2 ? "That address is not a picture or a video" : "The picture could not be fetched");
        f.destroy();
      }
    }
  }

  // a picture handed over as bytes, written out
  function write(b64, ext, at) {
    drop.out++;
    writer.createObject(drop, { at: at, input: b64, ext: ext, stdinEnabled: true, running: true });
  }
  Component {
    id: writer
    Process {
      id: w
      property point at
      property string input: ""
      property string ext: "png"
      property string said: ""
      command: ["sh", "-c",
        'd=$1; mkdir -p "$d" || exit 1; f="$d/dropped-$(date +%s%N).$2"; base64 -d > "$f" && [ -s "$f" ] && printf %s "$f"',
        "sh", drop.dir, w.ext]
      // written once it is really there (morpheus/Net's lesson)
      onStarted: { w.write(w.input); w.stdinEnabled = false; }
      stdout: StdioCollector { onStreamFinished: w.said = this.text }
      onExited: (code) => {
        drop.out--;
        if (code === 0 && w.said !== "") drop.media([w.said], w.at);
        else drop.failed("The dropped picture could not be kept");
        w.destroy();
      }
    }
  }
}
