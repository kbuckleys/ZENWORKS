// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE CHECKBOX MOVED to morpheus/controls/Check.qml (2026-10-18), where
// Oracle's Tools can use it too. This file only forwards to it, because
// ceres/qmldir still names it and a qmldir change waits for a restart.
// After one: drop the `Check` line from ceres/qmldir and this file, and add
// `import "../morpheus/controls"` to ConfigView, SetupView, CeresWindow and
// StoreView.

import "../morpheus/controls" as Controls

Controls.Check {}
