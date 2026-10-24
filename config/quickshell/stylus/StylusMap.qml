// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A DRIVE'S PARTITIONS AS ONE BAR — Disk Utility's partition map: every
// partition where it lies on the drive, in a color of its own, the room
// between them left as track; under it the key, a partition at a time,
// with its size and filesystem. `hot` is a partition picked in the
// sidebar: the others step back. The bar and the key are the shell's own
// (terminus/UsageBar in stretches, UsageLegend), as a volume's is.
//
//     StylusMap { width: …; drive: d; hot: sw.part }

import QtQuick
import "../morpheus"
import "../terminus"
import "../terminus/terminus.js" as Terminus
import "stylus.js" as S

Column {
  id: map

  property var drive: null
  // the partition's device picked in the sidebar, "" for none
  property string hot: ""

  readonly property var segs: S.mapOf(map.drive)
  // the same colors the sidebar's dots wear (S.PART_INKS)
  function inkOf(seg) { return seg.ink < 0 ? Zenon.wash(0.08) : Zenon[S.PART_INKS[seg.ink % S.PART_INKS.length]]; }
  function isHot(seg) { return !!seg.part && seg.part.dev === map.hot; }

  spacing: 16

  UsageBar {
    width: parent.width
    height: 26
    segments: map.segs.filter((g) => !!g.part).map((g) => ({
      start: g.start, frac: g.frac, ink: map.inkOf(g), dim: map.hot !== "" && !map.isHot(g)
    }))
  }

  UsageLegend {
    width: parent.width
    items: map.segs.map((g) => ({
      name: S.partName(g.part),
      line: [Terminus.formatSize(g.part ? g.part.size : g.frac * map.drive.size), g.part ? g.part.fstype : ""]
        .filter((x) => x).join("  ·  "),
      ink: map.inkOf(g),
      hot: map.isHot(g)
    }))
  }
}
