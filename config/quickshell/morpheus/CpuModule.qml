// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

// The CPU's meter: SysMeter over Sysmon's reading. Clicking it opens zeus
// (shell.qml) — it used to launch btop in a terminal, a second process
// reading the same /proc that Sysmon already reads.

import QtQuick
import "."

SysMeter {
  usage: Sysmon.cpuUsage
  tooltipText: Sysmon.cpuTip
  history: Sysmon.cpuHistory
  accent: Sysmon.cpuInk
}
