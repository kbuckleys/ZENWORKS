// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A RELEASE'S NOTES, AS THE FORGE SHOWS THEM — the Releases page's reading
// of one, and the editor's Preview (ReleaseEditor), one view for both.
//
// The words go to NotesText; a picture or a video on a line of its own is
// drawn as itself between them, as GitHub does (user, 2026-10-27) —
// NotesMedia, from D.notesParts.

import QtQuick
import "../morpheus"
import "delphi.js" as D

Column {
  id: view
  // the notes, as written; "" shows `empty` instead
  property string body: ""
  property string empty: "No notes"
  property int textSize: Zenon.px(17)
  // where a relative picture's address starts (a Markdown file's own
  // directory, in plato's preview); "" for none — a release's notes
  property string base: ""

  readonly property var parts: D.notesParts(view.body)
  spacing: 10

  NotesText {
    visible: view.parts.length === 0
    width: view.width
    body: ""
    empty: view.empty
    textSize: view.textSize
  }
  Repeater {
    model: view.parts
    delegate: Loader {
      id: part
      required property var modelData
      width: view.width
      sourceComponent: part.modelData.kind === "text" ? wordsComp : mediaComp
      Component {
        id: wordsComp
        NotesText { width: part.width; body: part.modelData.text; textSize: view.textSize }
      }
      Component {
        id: mediaComp
        NotesMedia { width: part.width; kind: part.modelData.kind; url: part.modelData.url; alt: part.modelData.alt; base: view.base }
      }
    }
  }
}
