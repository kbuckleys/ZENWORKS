// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

// The GPU's meter: SysMeter over Sysmon's reading. It hides when there is no
// GPU to report on (`present`, a fact about the machine, not about the
// text), and says "n/a" for one that cannot report its load (Intel).

import QtQuick
import "."

SysMeter {
  visible: Sysmon.gpuPresent
  usage: Sysmon.gpuUsage
  usageKnown: Sysmon.gpuUsageKnown
  tooltipText: Sysmon.gpuTip
  history: Sysmon.gpuHistory
  accent: Sysmon.gpuInk
}
