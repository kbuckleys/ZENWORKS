// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SYSMON'S ARITHMETIC: the mounts it lists under zeus' graphs, and the units
// those and the rates are written in.

"use strict";

const T = "\t";
const line = (...f) => f.join(T);

module.exports = {
  module: "morpheus/helpers.js",
  cases: (H, t) => {
    const text = [
      line("/dev/nvme0n1p2", "btrfs", "1000", "400", "600", "40", "nvme0n1p2", "/var/log"),
      line("/dev/nvme0n1p2", "btrfs", "1000", "400", "600", "40", "nvme0n1p2", "/"),
      line("/dev/nvme0n1p2", "btrfs", "1000", "400", "600", "40", "nvme0n1p2", "/home"),
      line("/dev/mapper/data", "ext4", "5000", "4600", "400", "92", "dm-0", "/mnt/my data"),
      line("/dev/sda1", "vfat", "0", "0", "0", "0", "sda1", "/boot"),
      "junk",
      ""
    ].join("\n");
    const m = H.parseMounts(text);
    t.eq("one entry per source", m.length, 2);
    t.eq("btrfs subvolumes collapse to the shortest mount", m[0].target, "/");
    t.eq("the device behind a mapper name", m[1].dev, "dm-0");
    t.eq("a mount point with a space survives", m[1].target, "/mnt/my data");
    t.eq("numbers are numbers", m[1].used, 4600);
    t.eq("the percent", m[1].pct, 92);
    t.eq("an empty filesystem is not listed", m.some((d) => d.dev === "sda1"), false);
    t.eq("nothing in, nothing out", H.parseMounts(""), []);

    t.eq("a size", H.sizeFormat(1500000), "1.5MB");
    t.eq("a big one", H.sizeFormat(1917657247744), "1.9TB");
    t.eq("a rate is a size per second", H.powFormat(2100000), "2.1MB/s");
    t.eq("nothing is zero", H.powFormat(-5), "0.0B/s");
  }
};
