// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

// Memory's meter: SysMeter over Sysmon's reading (/proc/meminfo is read once,
// there). Its tooltip is plain text, shown once a total has been read.

import QtQuick
import "."

SysMeter {
  usage: Sysmon.memUsage
  tooltipText: Sysmon.memTip
  history: Sysmon.memHistory
  accent: Sysmon.memInk
  styled: false
  tipWhen: Sysmon.memTotal > 0
}
