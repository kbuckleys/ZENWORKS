#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# machine.py — ABOUT THIS COMPUTER, read from the machine itself: the
# fold-out under Oracle's About row. It replaced fastfetch (user,
# 2026-10-25: "you can do better than fastfetch"), which knew less — no
# memory sticks, no drives, no firmware, no display sizes — and whose JSON
# changed shape under us between versions.
#
#   machine.py            one JSON object on stdout
#
#   { os: { id, idLike, name }, model, summary,
#     sections: [ { name, rows: [ { k, v, frac?, note? } ] } ] }
#
# `frac` (0..1) is a share drawn as a bar (memory, swap, a filesystem);
# `note` is a second, dimmer line. The distro's logo is picked in oracle.js
# from `os`, and Quickshell's version is added there (qs --version).
#
# EVERYTHING UNPRIVILEGED. Memory sticks come from udev's database (systemd
# reads the DMI tables as root at boot and leaves them world-readable), GPU
# names from hwdata's pci.ids, the rest from /proc, /sys, os-release and
# hyprctl. Anything a machine does not have — a battery, Secure Boot, a
# sensor — is a row left out, never a row that says "unknown". Standard
# library only.

import glob
import json
import math
import os
import re
import subprocess
import time


def read(path, default=""):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().strip()
    except OSError:
        return default


def run(argv, timeout=3):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def num(s, default=None):
    try:
        return int(str(s).strip())
    except (TypeError, ValueError):
        return default


# what firmware writes where a value belongs
JUNK = re.compile(r"^(to be filled.*|default string|system product name|system manufacturer|"
                  r"not specified|not applicable|none|n/a|o\.e\.m\.?|oem|x\.x|0+|123456789|unknown)$", re.I)


def real(s):
    s = (s or "").strip()
    return "" if not s or JUNK.match(s) else s


def size(n, si=False):
    # memory in binary units; a drive in the decimal ones on its box
    base, units = (1000, ["B", "KB", "MB", "GB", "TB", "PB"]) if si else (1024, ["B", "KiB", "MiB", "GiB", "TiB", "PiB"])
    v, i = float(n or 0), 0
    while v >= base and i < len(units) - 1:
        v /= base
        i += 1
    if i == 0:
        return "%d %s" % (v, units[0])
    # a round figure says so: 32 GiB, 2 TB, not 32.0
    if abs(v - round(v)) < 0.05:
        return "%d %s" % (round(v), units[i])
    return ("%.0f %s" if v >= 100 else "%.1f %s") % (v, units[i])


def used_of(used, total):
    return "%s of %s (%d%%)" % (size(used), size(total), round(used / total * 100)) if total else ""


def span(seconds):
    s = int(seconds)
    d, s = divmod(s, 86400)
    h, s = divmod(s, 3600)
    m = s // 60
    out = []
    if d:
        out.append("%d day%s" % (d, "" if d == 1 else "s"))
    if h:
        out.append("%d hour%s" % (h, "" if h == 1 else "s"))
    if m or not out:
        out.append("%d min%s" % (m, "" if m == 1 else "s"))
    return ", ".join(out)


def ymd(t):
    return time.strftime("%B %-d, %Y", time.localtime(t))


def temp_of(hwmon_dir, label_want=None):
    # the first temperature (or the one labelled `label_want`), in °C
    for inp in sorted(glob.glob(os.path.join(hwmon_dir, "temp*_input"))):
        if label_want:
            if not read(inp.replace("_input", "_label")).startswith(label_want):
                continue
        v = num(read(inp))
        if v is not None and v > 0:
            return round(v / 1000)
    return None


def hwmons():
    return {p: read(os.path.join(p, "name")) for p in glob.glob("/sys/class/hwmon/hwmon*")}


# ── pci.ids ─────────────────────────────────────────────────────────────
PCI_IDS = ["/usr/share/hwdata/pci.ids", "/usr/share/misc/pci.ids", "/usr/share/pci.ids"]


def pci_names(wanted):
    """{(vendor, device, subvendor, subdevice)} -> (vendor, device, subvendor) names, one pass."""
    vendors, devices, subs = {}, {}, {}
    want_v = {w[0] for w in wanted} | {w[2] for w in wanted}
    path = next((p for p in PCI_IDS if os.path.exists(p)), None)
    if not path:
        return vendors, devices, subs
    ven = dev = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            if line.startswith("C "):
                break  # the device classes, after every vendor
            if not line.startswith("\t"):
                ven = line[:4].lower()
                dev = None
                if ven in want_v:
                    vendors[ven] = line[4:].strip()
            elif ven in want_v and not line.startswith("\t\t"):
                dev = line[1:5].lower()
                devices[(ven, dev)] = line[5:].strip()
            elif ven in want_v and dev:
                parts = line.strip().split(None, 2)
                if len(parts) == 3:
                    subs[(ven, dev, parts[0].lower(), parts[1].lower())] = parts[2]
    return vendors, devices, subs


def short_vendor(v):
    v = re.sub(r"\[(.*?)\]", r"\1", v or "")
    for long, short in (("Advanced Micro Devices", "AMD"), ("NVIDIA", "NVIDIA"), ("Intel", "Intel"),
                        ("ASUSTeK", "ASUS"), ("Gigabyte", "Gigabyte"), ("Micro-Star", "MSI"),
                        ("Sapphire", "Sapphire"), ("PC Partner", "Zotac"), ("ZOTAC", "Zotac"),
                        ("eVga", "EVGA"), ("EVGA", "EVGA"), ("Palit", "Palit"), ("XFX", "XFX"),
                        ("PowerColor", "PowerColor"), ("Tul Corporation", "PowerColor"),
                        ("Hewlett-Packard", "HP"), ("Lenovo", "Lenovo"), ("Dell", "Dell"),
                        ("Apple", "Apple"), ("Acer", "Acer"), ("Samsung", "Samsung")):
        if long.lower() in v.lower():
            return short
    return re.sub(r",? (Corporation|Corp\.?|Inc\.?|Co\., Ltd\.?|Ltd\.?|Technology|Computer)\b.*$", "", v).strip()


def gpu_name(dev):
    # "GB206 [GeForce RTX 5060 Ti]" is a codename and the name on the box
    m = re.search(r"\[(.*)\]", dev or "")
    name = m.group(1) if m else (dev or "")
    # AMD's list several boxes in the one bracket: "Radeon RX 6700/6700 XT / 6800M"
    return name.split(" / ")[0].strip()


# ── THE SECTIONS ────────────────────────────────────────────────────────

def os_release():
    out = {}
    for line in read("/etc/os-release").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k] = v.strip().strip('"')
    return out


def system(osr):
    rows = []
    dmi = lambda f: real(read("/sys/class/dmi/id/" + f))
    vendor = short_vendor(dmi("sys_vendor") or dmi("board_vendor"))
    product = dmi("product_name") or dmi("board_name")
    family = dmi("product_version") if dmi("sys_vendor").lower().startswith("lenovo") else ""
    model = " ".join(x for x in (vendor, family or product) if x)
    # a desktop's "product" is often its motherboard — say which
    chassis = num(read("/sys/class/dmi/id/chassis_type"), 0)
    kind = {3: "desktop", 4: "desktop", 6: "desktop", 7: "tower", 8: "laptop", 9: "laptop", 10: "laptop",
            13: "all-in-one", 14: "laptop", 30: "tablet", 31: "laptop", 32: "laptop", 35: "mini PC",
            36: "mini PC"}.get(chassis, "")
    if model:
        board = dmi("board_name")
        note = "%s board" % board if board and board not in model else ""
        rows.append({"k": "Model", "v": model + (" (%s)" % kind if kind else ""), **({"note": note} if note else {})})

    bios = " ".join(x for x in (short_vendor(dmi("bios_vendor")), dmi("bios_version")) if x)
    bdate = dmi("bios_date")
    m = re.match(r"(\d\d)/(\d\d)/(\d{4})", bdate)
    if m:
        bdate = time.strftime("%B %-d, %Y", time.strptime(bdate, "%m/%d/%Y"))
    if bios:
        rows.append({"k": "Firmware", "v": bios + (" · " + bdate if bdate else "")})

    if os.path.isdir("/sys/firmware/efi"):
        sb = ""
        for f in glob.glob("/sys/firmware/efi/efivars/SecureBoot-*"):
            try:
                with open(f, "rb") as fh:
                    b = fh.read()
                sb = "Secure Boot on" if len(b) >= 5 and b[4] == 1 else "Secure Boot off"
            except OSError:
                pass
        rows.append({"k": "Boot", "v": "UEFI" + (" · " + sb if sb else "")})
    else:
        rows.append({"k": "Boot", "v": "BIOS (legacy)"})

    rows.append({"k": "OS", "v": " ".join(x for x in (osr.get("PRETTY_NAME") or osr.get("NAME", "Linux"),
                                                          os.uname().machine) if x)})
    rows.append({"k": "Kernel", "v": os.uname().release})

    # installed: pacman's first line, else when the root filesystem was made
    installed = None
    try:
        with open("/var/log/pacman.log", encoding="utf-8", errors="replace") as f:
            m = re.match(r"\[(\d{4}-\d\d-\d\d)", f.readline())
            if m:
                installed = time.mktime(time.strptime(m.group(1), "%Y-%m-%d"))
    except OSError:
        pass
    if installed is None:
        installed = num(run(["stat", "-c", "%W", "/"]).strip())
        if not installed:
            installed = None
    if installed:
        days = int((time.time() - installed) // 86400)
        rows.append({"k": "Installed", "v": ymd(installed), "note": "%d day%s ago" % (days, "" if days == 1 else "s")})

    up = read("/proc/uptime").split()
    if up:
        boot = time.time() - float(up[0])
        rows.append({"k": "Uptime", "v": span(float(up[0])), "note": "since " + time.strftime("%a %-I:%M %p", time.localtime(boot))})

    parts = []
    if os.path.isdir("/var/lib/pacman/local"):
        n = len([d for d in os.listdir("/var/lib/pacman/local") if d != "ALPM_DB_VERSION"])
        aur = len(run(["pacman", "-Qqm"]).split())
        parts.append("%d pacman" % n + (" (%d from the AUR)" % aur if aur else ""))
    if os.path.exists("/usr/bin/flatpak"):
        fp = len(run(["flatpak", "list", "--app", "--columns=application"], timeout=5).split())
        if fp:
            parts.append("%d Flatpak" % fp)
    for cmd, label in ((["dpkg-query", "-f", ".\n", "-W"], "dpkg"), (["rpm", "-qa"], "rpm")):
        if os.path.exists("/usr/bin/" + cmd[0]):
            n = len(run(cmd).split())
            if n:
                parts.append("%d %s" % (n, label))
    if parts:
        rows.append({"k": "Packages", "v": " · ".join(parts)})
    return model, rows


def desktop():
    rows = []
    v = {}
    try:
        v = json.loads(run(["hyprctl", "version", "-j"]) or "{}")
    except ValueError:
        pass
    if v.get("version") or v.get("tag"):
        rows.append({"k": "Hyprland", "v": v.get("version") or v.get("tag", "").lstrip("v")})
    qt = os.path.realpath("/usr/lib/libQt6Core.so.6")
    m = re.search(r"\.so\.(\d+\.\d+\.\d+)$", qt)
    if m:
        rows.append({"k": "Qt", "v": m.group(1)})
    sess = os.environ.get("XDG_SESSION_TYPE", "")
    if sess:
        rows.append({"k": "Session", "v": sess.capitalize() if sess != "x11" else "X11"})
    loc = os.environ.get("LC_ALL") or os.environ.get("LANG") or ""
    if loc:
        rows.append({"k": "Locale", "v": loc})
    return rows


def processor(mons):
    rows = []
    info = read("/proc/cpuinfo")
    name = ""
    m = re.search(r"^model name\s*:\s*(.+)$", info, re.M)
    if m:
        name = m.group(1)
    elif re.search(r"^Hardware\s*:\s*(.+)$", info, re.M):
        name = re.search(r"^Hardware\s*:\s*(.+)$", info, re.M).group(1)
    # "Intel(R) Core(TM) i5-9400F CPU @ 2.90GHz" -> "Intel Core i5-9400F"
    clean = re.sub(r"\((R|TM|tm|r)\)", "", name)
    clean = re.sub(r"\s+@.*$", "", clean)
    clean = re.sub(r"\b(CPU|Processor|\d+-Core)\b", "", clean)
    clean = re.sub(r"\s+", " ", clean).strip()
    if clean:
        rows.append({"k": "Name", "v": clean})
    threads = os.cpu_count() or 0
    cores = len({(a, b) for a, b in re.findall(r"^physical id\s*:\s*(\d+)\n(?:.*\n)*?core id\s*:\s*(\d+)", info, re.M)})
    if not cores:
        cores = len(set(glob.glob("/sys/devices/system/cpu/cpu[0-9]*/topology/core_id"))) and \
            len({read(p) for p in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/topology/core_cpus_list")})
    if threads:
        c = "%d core%s" % (cores, "" if cores == 1 else "s") if cores else ""
        t = "%d thread%s" % (threads, "" if threads == 1 else "s")
        rows.append({"k": "Cores", "v": " · ".join(x for x in (c, t) if x) if cores != threads else c or t})
    mx = max([num(read(p), 0) for p in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq")] or [0])
    if mx:
        base = num(read("/sys/devices/system/cpu/cpu0/cpufreq/base_frequency"), 0)
        rows.append({"k": "Clock", "v": "up to %.2f GHz" % (mx / 1e6)
                     + (" · base %.2f GHz" % (base / 1e6) if base and base != mx else "")})
    for p, n in mons.items():
        t = None
        if n == "coretemp":
            t = temp_of(p, "Package")
        elif n in ("k10temp", "zenpower"):
            t = temp_of(p, "Tctl") or temp_of(p, "Tdie")
        elif n == "cpu_thermal":
            t = temp_of(p)
        if t:
            rows.append({"k": "Temperature", "v": "%d °C" % t})
            break
    return clean, rows


def graphics(mons):
    rows = []
    cards = []
    for dev in sorted(glob.glob("/sys/bus/pci/devices/*")):
        cls = read(dev + "/class")
        if not cls.startswith("0x03"):
            continue
        cards.append(dev)
    ids = [tuple(read(d + "/" + f)[2:].lower() for f in ("vendor", "device", "subsystem_vendor", "subsystem_device"))
           for d in cards]
    vendors, devices, subs = pci_names(ids)
    first = ""
    for dev, (ven, did, sv, sd) in zip(cards, ids):
        vname = short_vendor(vendors.get(ven, ""))
        name = gpu_name(devices.get((ven, did), "")) or "device %s:%s" % (ven, did)
        if vname and not name.lower().startswith(vname.lower()):
            name = vname + " " + name
        first = first or name
        maker = short_vendor(vendors.get(sv, "")) if sv and sv != ven else ""
        driver = os.path.basename(os.path.realpath(dev + "/driver")) if os.path.exists(dev + "/driver") else ""
        ver = read("/sys/module/%s/version" % driver) if driver else ""
        bits = []
        if driver:
            bits.append("%s driver" % driver + (" " + ver if ver else ""))
        vram = num(read(dev + "/mem_info_vram_total"), 0)
        if vram:
            bits.append(size(vram) + " VRAM")
        if maker:
            bits.insert(0, "made by " + maker)
        t = None
        for p, n in mons.items():
            if os.path.realpath(p + "/device") == os.path.realpath(dev):
                t = temp_of(p)
        if t:
            bits.append("%d °C" % t)
        rows.append({"k": "Name", "v": name, **({"note": " · ".join(bits)} if bits else {})})
    return first, rows


JEDEC = {"859b": "Crucial", "802c": "Micron", "2c00": "Micron", "80ce": "Samsung", "ce00": "Samsung",
         "80ad": "SK hynix", "ad00": "SK hynix", "04cd": "G.Skill", "cd04": "G.Skill", "029e": "Corsair",
         "9e02": "Corsair", "0198": "Kingston", "9801": "Kingston", "04ef": "Team Group", "ef04": "Team Group",
         "04cb": "ADATA", "cb04": "ADATA", "0443": "Ramaxel", "4304": "Ramaxel", "8551": "Qimonda",
         "0283": "Goodram", "8983": "Hynix", "80c2": "Nanya", "830b": "Nanya", "0b03": "Nanya",
         "0502": "Patriot", "8502": "Patriot", "0a07": "Kingmax", "8a9b": "Lexar", "0136": "Elpida"}


def memory():
    rows = []
    mem = {}
    for line in read("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        mem[k] = num(v.split()[0] if v.split() else "", 0) * 1024
    total = mem.get("MemTotal", 0)
    used = total - mem.get("MemAvailable", 0)

    # the sticks, from udev's copy of the DMI tables
    props = {}
    for line in run(["udevadm", "info", "-q", "property", "-p", "/devices/virtual/dmi/id"]).splitlines():
        k, _, v = line.partition("=")
        props[k] = v
    sticks, slots = [], 0
    for i in range(64):
        pre = "MEMORY_DEVICE_%d_" % i
        if pre + "LOCATOR" not in props:
            if i > 8:
                break
            continue
        slots += 1
        if props.get(pre + "PRESENT") == "0" or not num(props.get(pre + "SIZE"), 0):
            continue
        maker = props.get(pre + "MANUFACTURER", "")
        maker = JEDEC.get(maker.lower(), "") if re.fullmatch(r"[0-9A-Fa-f]{4}", maker) else real(maker)
        sticks.append({
            "size": num(props.get(pre + "SIZE"), 0),
            "type": real(props.get(pre + "TYPE", "")),
            "speed": num(props.get(pre + "CONFIGURED_SPEED_MTS")) or num(props.get(pre + "SPEED_MTS")),
            "where": props.get(pre + "LOCATOR", ""),
            "maker": maker,
            "part": real(props.get(pre + "PART_NUMBER", "").strip()),
            "form": real(props.get(pre + "FORM_FACTOR", "")),
        })
    fitted = sum(s["size"] for s in sticks)
    head = size(fitted or total)
    kinds = {s["type"] for s in sticks if s["type"]}
    speeds = {s["speed"] for s in sticks if s["speed"]}
    if len(kinds) == 1:
        head += " " + kinds.pop()
    if len(speeds) == 1:
        head += " · %d MT/s" % speeds.pop()
    note = []
    if sticks and slots:
        note.append("%d of %d slot%s filled" % (len(sticks), slots, "" if slots == 1 else "s"))
    cap = num(props.get("MEMORY_ARRAY_MAX_CAPACITY"), 0)
    if cap and cap > fitted:
        note.append("takes up to " + size(cap))
    rows.append({"k": "Total", "v": head, **({"note": " · ".join(note)} if note else {})})
    if total:
        rows.append({"k": "In use", "v": used_of(used, total), "frac": used / total})
    for s in sticks:
        v = " ".join(x for x in (size(s["size"]), s["type"]) if x) + (" · " + s["maker"] if s["maker"] else "")
        note = " · ".join(x for x in (s["where"], s["part"]) if x)
        rows.append({"k": "Module", "v": v, **({"note": note} if note else {})})

    for line in read("/proc/swaps").splitlines()[1:]:
        f = line.split()
        if len(f) < 4:
            continue
        stot, sused = num(f[2], 0) * 1024, num(f[3], 0) * 1024
        if not stot:
            continue
        name = os.path.basename(f[0])
        kind = "compressed in memory" if name.startswith("zram") else ("file" if f[1] == "file" else "partition")
        rows.append({"k": "Swap", "v": used_of(sused, stot), "frac": sused / stot, "note": "%s · %s" % (name, kind)})
    return fitted or total, rows


REAL_FS = {"ext2", "ext3", "ext4", "btrfs", "xfs", "f2fs", "vfat", "exfat", "ntfs", "ntfs3", "fuseblk",
           "zfs", "bcachefs", "jfs", "reiserfs", "hfsplus", "apfs"}


def storage(mons):
    rows = []
    for blk in sorted(glob.glob("/sys/block/*")):
        name = os.path.basename(blk)
        if re.match(r"(loop|ram|zram|dm-|md|sr|fd)", name) or read(blk + "/removable") == "1":
            continue
        n = num(read(blk + "/size"), 0) * 512
        if not n:
            continue
        model = real(read(blk + "/device/model")) or real(read(blk + "/device/name"))
        if name.startswith("nvme"):
            kind = "NVMe SSD"
        elif name.startswith("mmcblk"):
            kind = "eMMC" if read(blk + "/device/type") == "MMC" else "SD card"
        else:
            kind = "hard drive" if read(blk + "/queue/rotational") == "1" else "SSD"
            if "usb" in os.path.realpath(blk):
                kind = "USB " + kind
        bits = [kind]
        fw = real(read(blk + "/device/firmware_rev")) or real(read(blk + "/device/rev"))
        if fw:
            bits.append("firmware " + fw)
        for p, nm in mons.items():
            dev = os.path.realpath(p + "/device")
            if nm in ("nvme", "drivetemp") and (dev == os.path.realpath(blk + "/device")
                                               or dev == os.path.realpath(blk + "/device/device")):
                t = temp_of(p)
                if t:
                    bits.append("%d °C" % t)
        rows.append({"k": "Drive", "v": "%s · %s" % (model or name, size(n, si=True)), "note": " · ".join(bits)})

    seen = set()
    for line in read("/proc/mounts").splitlines():
        f = line.split()
        if len(f) < 3 or f[2] not in REAL_FS or not f[0].startswith("/dev/"):
            continue
        mnt = f[1].replace("\\040", " ")
        if f[0] in seen:
            continue
        seen.add(f[0])
        try:
            st = os.statvfs(mnt)
        except OSError:
            continue
        tot = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        if not tot:
            continue
        usedb = tot - st.f_bfree * st.f_frsize
        # what is left to use, as a file manager says it
        rows.append({"k": mnt, "v": "%s free of %s" % (size(free), size(tot)), "frac": usedb / tot,
                     "note": "%s · %s" % (os.path.basename(f[0]), "ntfs" if f[2] == "ntfs3" else f[2])})
    return rows


def displays():
    rows = []
    try:
        mons = json.loads(run(["hyprctl", "monitors", "all", "-j"]) or "[]")
    except ValueError:
        mons = []
    for m in mons:
        if m.get("disabled"):
            continue
        w, h = m.get("width", 0), m.get("height", 0)
        portrait = m.get("transform", 0) % 2 == 1
        if portrait:
            w, h = h, w
        maker = short_vendor(m.get("make", ""))
        model = real(m.get("model", ""))
        name = " ".join(x for x in (maker, model) if x) or m.get("name", "")
        pw, ph = m.get("physicalWidth", 0), m.get("physicalHeight", 0)
        inch = math.hypot(pw, ph) / 25.4 if pw and ph else 0
        v = "%d×%d" % (w, h)
        if m.get("refreshRate"):
            v += " @ %d Hz" % round(m["refreshRate"])
        bits = [m.get("name", "")]
        if inch >= 5:
            bits.append('%d"' % round(inch))
        if portrait:
            bits.append("portrait")
        sc = m.get("scale", 1)
        if sc and abs(sc - 1) > 0.01:
            bits.append("scaled ×%g" % round(sc, 2))
            v += " (looks like %d×%d)" % (round(w / sc), round(h / sc))
        if m.get("vrr"):
            bits.append("variable refresh")
        rows.append({"k": name, "v": v, "note": " · ".join(b for b in bits if b)})
    return rows


def network():
    rows = []
    addrs = {}
    try:
        for i in json.loads(run(["ip", "-j", "addr"]) or "[]"):
            v4 = [a["local"] for a in i.get("addr_info", []) if a.get("family") == "inet"]
            v6 = [a["local"] for a in i.get("addr_info", []) if a.get("family") == "inet6"
                  and a.get("scope") == "global"]
            addrs[i.get("ifname")] = (v4, v6)
    except (ValueError, KeyError):
        pass
    for path in sorted(glob.glob("/sys/class/net/*")):
        nm = os.path.basename(path)
        if not os.path.exists(path + "/device"):
            continue  # loopback, bridges, VPNs, containers
        wifi = os.path.isdir(path + "/wireless") or os.path.isdir(path + "/phy80211")
        state = read(path + "/operstate")
        v4, v6 = addrs.get(nm, ([], []))
        bits = [nm]
        if state == "up":
            sp = num(read(path + "/speed"), -1)
            if sp and sp > 0:
                bits.append(("%g Gb/s" % (sp / 1000)) if sp >= 1000 else "%d Mb/s" % sp)
        mac = read(path + "/address")
        if mac:
            bits.append(mac)
        v = (v4[0] if v4 else v6[0] if v6 else "connected") if state == "up" else "not connected"
        rows.append({"k": "Wi-Fi" if wifi else "Ethernet", "v": v, "note": " · ".join(bits)})
    return rows


def power():
    rows = []
    for p in sorted(glob.glob("/sys/class/power_supply/*")):
        if read(p + "/type") != "Battery" or read(p + "/scope") == "Device":
            continue  # a mouse's battery is the mouse's
        cap = num(read(p + "/capacity"))
        status = read(p + "/status").lower()
        full = num(read(p + "/energy_full")) or num(read(p + "/charge_full"))
        design = num(read(p + "/energy_full_design")) or num(read(p + "/charge_full_design"))
        cycles = num(read(p + "/cycle_count"))
        bits = []
        if full and design:
            bits.append("health %d%%" % round(full / design * 100))
        if cycles:
            bits.append("%d cycles" % cycles)
        maker = " ".join(x for x in (real(read(p + "/manufacturer")), real(read(p + "/model_name"))) if x)
        if maker:
            bits.append(maker)
        if cap is not None:
            rows.append({"k": "Battery", "v": "%d%%" % cap + (" · " + status if status and status != "unknown" else ""),
                         "frac": cap / 100, **({"note": " · ".join(bits)} if bits else {})})
    return rows


def main():
    osr = os_release()
    mons = hwmons()
    model, sys_rows = system(osr)
    cpu, cpu_rows = processor(mons)
    gpu, gpu_rows = graphics(mons)
    memtot, mem_rows = memory()
    sections = [
        {"name": "System", "rows": sys_rows},
        {"name": "Desktop", "rows": desktop()},
        {"name": "Processor", "rows": cpu_rows},
        {"name": "Graphics", "rows": gpu_rows},
        {"name": "Memory", "rows": mem_rows},
        {"name": "Storage", "rows": storage(mons)},
        {"name": "Displays", "rows": displays()},
        {"name": "Network", "rows": network()},
        {"name": "Power", "rows": power()},
    ]
    name = osr.get("PRETTY_NAME") or osr.get("NAME") or "Linux"
    print(json.dumps({
        "os": {"id": osr.get("ID", ""), "idLike": osr.get("ID_LIKE", ""), "name": name},
        "model": model,
        "summary": " · ".join(x for x in (name, cpu, gpu.replace("NVIDIA ", "").replace("AMD ", "") if gpu else "",
                                          size(memtot) if memtot else "") if x),
        "sections": [s for s in sections if s["rows"]],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
