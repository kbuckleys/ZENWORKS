// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A DISPATCH THAT MAY SHOW THE SPECIAL WORKSPACE ON PURPOSE — the bar's
// toggle, a notification raising its app. OffSpecial puts away a special
// that opens with nobody asking (a popup's grab ending refocuses a window
// left focused in it); this says "asked", in the same eval as the dispatch
// so nothing can come between them.
//
//     Quickshell.execDetached(OffSpecial.wanted('hl.dsp.workspace.toggle_special("special")'))

.pragma library

function wanted(dispatcher) {
  return ["hyprctl", "-q", "eval",
    "local z = rawget(_G, 'zenOffSpecial')\n"
    + "if z and z.want then z.want() end\n"
    + "hl.dispatch(" + dispatcher + ")\n"];
}
