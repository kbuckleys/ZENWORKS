#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE THEMES' SOURCE — every file in themes/ but catppuccin-latte and
# catppuccin-mocha (made by hand) is this script's output. To add a theme,
# add its palette to THEMES below and run:
#
#     scripts/genthemes.py
#
# A palette is the theme's own colours by what they ARE: ground (its
# darkest background), card, surface, ink (body text), muted (comments),
# dim, border, and the accents red orange yellow green cyan blue magenta,
# with pink, soft and keyInk optional. build() maps them onto Zenon's
# slots, which are named by what they DO:
#
#   - Zenon's `yellow` is its orange ("changed"), and `sand` the true
#     yellow, so a palette's orange goes to yellow and its yellow to sand.
#   - pink is Zenon's bright red: absent, the red lifted 40% towards ink.
#   - soft and keyInk, absent, are ink mixed towards muted.
#
# LIGHT THEMES ARE CHECKED FOR GLASS. Their palettes were drawn for an
# opaque page; on light glass a pale accent washes out, so any accent under
# 3:1 against ground is darkened just to 3:1 — and the script says which.
# Every theme is also checked for ink, keyInk, soft and muted contrast.
import json, os, sys

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "themes")

def h2rgb(h):
    h = h.lstrip("#")[-6:]
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def rgb2h(c):
    return "#" + "".join("%02x" % max(0, min(255, round(v))) for v in c)

def mix(a, b, t):
    A, B = h2rgb(a), h2rgb(b)
    return rgb2h(tuple(A[i] + (B[i] - A[i]) * t for i in range(3)))

def lum(h):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = h2rgb(h)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)

def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)

THEMES = {
 # ── Zenon Light ── Zenon's own light side, and the default light theme
 # (Oracle's Day theme). Zenon dark is not a file — it is the table in
 # morpheus/Zenon.qml — but its light twin is an ordinary theme. Same
 # neutral greys and the same hues, deepened by hand rather than walked
 # towards black by legible(): Zenon's pastels darkened that way go muddy.
 "zenon-light": dict(name="Zenon Light", mode="light",
   ground="#f3f3f1", card="#e9eaec", surface="#dcdfe4", ink="#1d2025", soft="#474d58", keyInk="#3a3f4b",
   muted="#666c7a", dim="#b9c3c3", border="#9aa3ad",
   red="#c4474e", orange="#c25f22", yellow="#8f7a1c", green="#4a8538", cyan="#337b7b",
   blue="#2f6fbe", magenta="#8550b6", pink="#bc5f72"),
 # ── Catppuccin ──
 "catppuccin-frappe": dict(name="Catppuccin Frappé", mode="dark",
   ground="#232634", card="#292c3c", surface="#414559", ink="#c6d0f5", soft="#a5adce", keyInk="#b5bfe2",
   muted="#838ba7", dim="#626880", border="#626880",
   red="#e78284", orange="#ef9f76", yellow="#e5c890", green="#a6d189", cyan="#81c8be",
   blue="#8caaee", magenta="#ca9ee6", pink="#f4b8e4"),
 "catppuccin-macchiato": dict(name="Catppuccin Macchiato", mode="dark",
   ground="#181926", card="#1e2030", surface="#363a4f", ink="#cad3f5", soft="#a5adcb", keyInk="#b8c0e0",
   muted="#8087a2", dim="#5b6078", border="#5b6078",
   red="#ed8796", orange="#f5a97f", yellow="#eed49f", green="#a6da95", cyan="#8bd5ca",
   blue="#8aadf4", magenta="#c6a0f6", pink="#f5bde6"),
 # ── Gruvbox ──
 "gruvbox-dark": dict(name="Gruvbox Dark", mode="dark",
   ground="#1d2021", card="#282828", surface="#3c3836", ink="#ebdbb2", soft="#a89984", keyInk="#bdae93",
   muted="#928374", dim="#665c54", border="#665c54",
   red="#fb4934", orange="#fe8019", yellow="#fabd2f", green="#b8bb26", cyan="#8ec07c",
   blue="#83a598", magenta="#d3869b"),
 "gruvbox-light": dict(name="Gruvbox Light", mode="light",
   ground="#f9f5d7", card="#f2e5bc", surface="#ebdbb2", ink="#3c3836", soft="#665c54", keyInk="#504945",
   muted="#7c6f64", dim="#bdae93", border="#a89984",
   red="#9d0006", orange="#af3a03", yellow="#b57614", green="#79740e", cyan="#427b58",
   blue="#076678", magenta="#8f3f71"),
 # ── Nord ──
 "nord": dict(name="Nord", mode="dark",
   ground="#242933", card="#2e3440", surface="#3b4252", ink="#e5e9f0", keyInk="#d8dee9",
   muted="#7b88a1", dim="#4c566a", border="#4c566a",
   red="#bf616a", orange="#d08770", yellow="#ebcb8b", green="#a3be8c", cyan="#88c0d0",
   blue="#81a1c1", magenta="#b48ead"),
 # ── Tokyo Night ──
 "tokyo-night": dict(name="Tokyo Night", mode="dark",
   ground="#16161e", card="#1a1b26", surface="#292e42", ink="#c0caf5", soft="#9aa5ce", keyInk="#a9b1d6",
   muted="#737aa2", dim="#3b4261", border="#414868",
   red="#f7768e", orange="#ff9e64", yellow="#e0af68", green="#9ece6a", cyan="#7dcfff",
   blue="#7aa2f7", magenta="#9d7cd8", pink="#bb9af7"),
 "tokyo-night-storm": dict(name="Tokyo Night Storm", mode="dark",
   ground="#1f2335", card="#24283b", surface="#292e42", ink="#c0caf5", soft="#9aa5ce", keyInk="#a9b1d6",
   muted="#737aa2", dim="#3b4261", border="#414868",
   red="#f7768e", orange="#ff9e64", yellow="#e0af68", green="#9ece6a", cyan="#7dcfff",
   blue="#7aa2f7", magenta="#9d7cd8", pink="#bb9af7"),
 "tokyo-night-day": dict(name="Tokyo Night Day", mode="light",
   ground="#e1e2e7", card="#e9e9ed", surface="#c4c8da", ink="#3760bf", soft="#68709a", keyInk="#6172b0",
   muted="#848cb5", dim="#a8aecb", border="#a8aecb",
   red="#f52a65", orange="#b15c00", yellow="#8c6c3e", green="#587539", cyan="#007197",
   blue="#2e7de9", magenta="#7847bd", pink="#9854f1"),
 # ── Rosé Pine ──
 "rose-pine": dict(name="Rosé Pine", mode="dark",
   ground="#191724", card="#1f1d2e", surface="#26233a", ink="#e0def4", soft="#908caa",
   muted="#6e6a86", dim="#403d52", border="#524f67",
   red="#eb6f92", orange="#f6c177", yellow="#f6c177", green="#31748f", cyan="#9ccfd8",
   blue="#9ccfd8", magenta="#c4a7e7", pink="#ebbcba"),
 "rose-pine-moon": dict(name="Rosé Pine Moon", mode="dark",
   ground="#232136", card="#2a273f", surface="#393552", ink="#e0def4", soft="#908caa",
   muted="#6e6a86", dim="#44415a", border="#56526e",
   red="#eb6f92", orange="#f6c177", yellow="#f6c177", green="#3e8fb0", cyan="#9ccfd8",
   blue="#9ccfd8", magenta="#c4a7e7", pink="#ea9a97"),
 "rose-pine-dawn": dict(name="Rosé Pine Dawn", mode="light",
   ground="#faf4ed", card="#fffaf3", surface="#f2e9e1", ink="#575279", soft="#797593",
   muted="#9893a5", dim="#cecacd", border="#cecacd",
   red="#b4637a", orange="#ea9d34", yellow="#ea9d34", green="#286983", cyan="#56949f",
   blue="#56949f", magenta="#907aa9", pink="#d7827e"),
 # ── Dracula ──
 "dracula": dict(name="Dracula", mode="dark",
   ground="#21222c", card="#282a36", surface="#44475a", ink="#f8f8f2",
   muted="#6272a4", dim="#525568", border="#525568",
   red="#ff5555", orange="#ffb86c", yellow="#f1fa8c", green="#50fa7b", cyan="#8be9fd",
   blue="#bd93f9", magenta="#bd93f9", pink="#ff79c6"),
 # ── One ──
 "one-dark": dict(name="One Dark", mode="dark",
   ground="#21252b", card="#282c34", surface="#3e4451", ink="#abb2bf",
   muted="#7f848e", dim="#4b5263", border="#4b5263",
   red="#e06c75", orange="#d19a66", yellow="#e5c07b", green="#98c379", cyan="#56b6c2",
   blue="#61afef", magenta="#c678dd"),
 "one-light": dict(name="One Light", mode="light",
   ground="#fafafa", card="#f0f0f1", surface="#e5e5e6", ink="#383a42",
   muted="#8e8f96", dim="#d3d3d5", border="#c3c3c6",
   red="#e45649", orange="#986801", yellow="#c18401", green="#50a14f", cyan="#0184bc",
   blue="#4078f2", magenta="#a626a4"),
 # ── Solarized ──
 "solarized-dark": dict(name="Solarized Dark", mode="dark",
   ground="#002b36", card="#04313c", surface="#073642", ink="#93a1a1", soft="#839496", keyInk="#839496",
   muted="#586e75", dim="#0e4552", border="#2a5561",
   red="#dc322f", orange="#cb4b16", yellow="#b58900", green="#859900", cyan="#2aa198",
   blue="#268bd2", magenta="#6c71c4", pink="#d33682"),
 "solarized-light": dict(name="Solarized Light", mode="light",
   ground="#fdf6e3", card="#f5efdc", surface="#eee8d5", ink="#586e75", soft="#657b83", keyInk="#586e75",
   muted="#93a1a1", dim="#ddd6c1", border="#c9c3ad",
   red="#dc322f", orange="#cb4b16", yellow="#b58900", green="#859900", cyan="#2aa198",
   blue="#268bd2", magenta="#6c71c4", pink="#d33682"),
 # ── Everforest ──
 "everforest-dark": dict(name="Everforest Dark", mode="dark",
   ground="#232a2e", card="#2d353b", surface="#343f44", ink="#d3c6aa", soft="#9da9a0",
   muted="#859289", dim="#4f585e", border="#4f585e",
   red="#e67e80", orange="#e69875", yellow="#dbbc7f", green="#a7c080", cyan="#83c092",
   blue="#7fbbb3", magenta="#d699b6"),
 "everforest-light": dict(name="Everforest Light", mode="light",
   ground="#fdf6e3", card="#f4f0d9", surface="#e6e2cc", ink="#5c6a72", soft="#829181",
   muted="#939f91", dim="#bdc3af", border="#bdc3af",
   red="#f85552", orange="#f57d26", yellow="#dfa000", green="#8da101", cyan="#35a77c",
   blue="#3a94c5", magenta="#df69ba"),
 # ── Kanagawa ──
 "kanagawa-wave": dict(name="Kanagawa Wave", mode="dark",
   ground="#16161d", card="#1f1f28", surface="#2a2a37", ink="#dcd7ba", soft="#c8c093",
   muted="#727169", dim="#363646", border="#54546d",
   red="#e46876", orange="#ffa066", yellow="#e6c384", green="#98bb6c", cyan="#7aa89f",
   blue="#7e9cd8", magenta="#957fb8", pink="#d27e99"),
 "kanagawa-dragon": dict(name="Kanagawa Dragon", mode="dark",
   ground="#0d0c0c", card="#181616", surface="#282727", ink="#c5c9c5", soft="#a6a69c",
   muted="#7a8382", dim="#393836", border="#625e5a",
   red="#c4746e", orange="#b6927b", yellow="#c4b28a", green="#87a987", cyan="#8ea4a2",
   blue="#8ba4b0", magenta="#8992a7", pink="#a292a3"),
 "kanagawa-lotus": dict(name="Kanagawa Lotus", mode="light",
   ground="#f2ecbc", card="#e5ddb0", surface="#e7dba0", ink="#545464", soft="#716e61",
   muted="#8a8980", dim="#d5cea3", border="#c7bf8f",
   red="#c84053", orange="#cc6d00", yellow="#77713f", green="#6f894e", cyan="#4e8ca2",
   blue="#4d699b", magenta="#624c83", pink="#b35b79"),
 # ── Ayu ──
 "ayu-dark": dict(name="Ayu Dark", mode="dark",
   ground="#0b0e14", card="#0f131a", surface="#131721", ink="#bfbdb6",
   muted="#626a73", dim="#273747", border="#2d3640",
   red="#f07178", orange="#ff8f40", yellow="#e6b450", green="#aad94c", cyan="#39bae6",
   blue="#59c2ff", magenta="#d2a6ff"),
 "ayu-mirage": dict(name="Ayu Mirage", mode="dark",
   ground="#171b24", card="#1f2430", surface="#242936", ink="#cccac2",
   muted="#707a8c", dim="#3a4152", border="#3a4152",
   red="#f28779", orange="#ffad66", yellow="#ffcc66", green="#d5ff80", cyan="#5ccfe6",
   blue="#73d0ff", magenta="#dfbfff"),
 "ayu-light": dict(name="Ayu Light", mode="light",
   ground="#fcfcfc", card="#f3f4f5", surface="#e7eaed", ink="#5c6166",
   muted="#8a9199", dim="#d8dce0", border="#c9ced3",
   red="#f07171", orange="#fa8d3e", yellow="#f2ae49", green="#86b300", cyan="#55b4d4",
   blue="#399ee6", magenta="#a37acc"),
 # ── GitHub ──
 "github-dark": dict(name="GitHub Dark", mode="dark",
   ground="#0d1117", card="#161b22", surface="#21262d", ink="#e6edf3",
   muted="#8b949e", dim="#30363d", border="#30363d",
   red="#ff7b72", orange="#ffa657", yellow="#d29922", green="#3fb950", cyan="#39c5cf",
   blue="#58a6ff", magenta="#d2a8ff", pink="#f778ba"),
 "github-light": dict(name="GitHub Light", mode="light",
   ground="#ffffff", card="#f6f8fa", surface="#eaeef2", ink="#1f2328",
   muted="#656d76", dim="#d0d7de", border="#d0d7de",
   red="#cf222e", orange="#bc4c00", yellow="#9a6700", green="#1a7f37", cyan="#1b7c83",
   blue="#0969da", magenta="#8250df", pink="#bf3989"),
 # ── Nightfox ──
 "nightfox": dict(name="Nightfox", mode="dark",
   ground="#131a24", card="#192330", surface="#212e3f", ink="#cdcecf", soft="#aeafb0",
   muted="#738091", dim="#29394f", border="#39506d",
   red="#c94f6d", orange="#f4a261", yellow="#dbc074", green="#81b29a", cyan="#63cdcf",
   blue="#719cd6", magenta="#9d79d6", pink="#d67ad2"),
 "dayfox": dict(name="Dayfox", mode="light",
   ground="#f6f2ee", card="#ede7e1", surface="#e4dcd4", ink="#3d2b5a", soft="#643f61",
   muted="#837a72", dim="#d3c7bb", border="#aab0ad",
   red="#a5222f", orange="#ac5402", yellow="#ac5402", green="#396847", cyan="#287980",
   blue="#2848a9", magenta="#6e33ce", pink="#a440b5"),
 # ── Monokai Pro ──
 "monokai-pro": dict(name="Monokai Pro", mode="dark",
   ground="#221f22", card="#2d2a2e", surface="#403e41", ink="#fcfcfa", soft="#c1c0c0", keyInk="#c1c0c0",
   muted="#939293", dim="#5b595c", border="#5b595c",
   red="#ff6188", orange="#fc9867", yellow="#ffd866", green="#a9dc76", cyan="#78dce8",
   blue="#78dce8", magenta="#ab9df2"),
 # ── Flexoki ──
 "flexoki-dark": dict(name="Flexoki Dark", mode="dark",
   ground="#100f0f", card="#1c1b1a", surface="#282726", ink="#cecdc3", soft="#878580",
   muted="#6f6e69", dim="#403e3c", border="#403e3c",
   red="#d14d41", orange="#da702c", yellow="#d0a215", green="#879a39", cyan="#3aa99f",
   blue="#4385be", magenta="#8b7ec8", pink="#ce5d97"),
 "flexoki-light": dict(name="Flexoki Light", mode="light",
   ground="#fffcf0", card="#f2f0e5", surface="#e6e4d9", ink="#100f0f", soft="#6f6e69",
   muted="#878580", dim="#cecdc3", border="#b7b5ac",
   red="#af3029", orange="#bc5215", yellow="#ad8301", green="#66800b", cyan="#24837b",
   blue="#205ea6", magenta="#5e409d", pink="#a02f6f"),
}

ADJUSTED = []

def legible(stem, key, h, ground, need=3.0):
    # Light palettes are drawn for an opaque page; on light glass a pale
    # accent washes out. Darken only as far as `need`, never further.
    if contrast(h, ground) >= need:
        return h
    t, out = 0.0, h
    while contrast(out, ground) < need and t < 1:
        t += 0.02
        out = mix(h, "#000000", t)
    ADJUSTED.append(f"{stem:22} {key:8} {h} -> {out} ({contrast(h, ground):.2f} -> {contrast(out, ground):.2f})")
    return out

def build(p, stem=""):
    light = p["mode"] == "light"
    if light:
        p = dict(p)
        for k in ("red", "orange", "yellow", "green", "cyan", "blue", "magenta", "pink"):
            if k in p:
                p[k] = legible(stem, k, p[k], p["ground"])
    soft = p.get("soft") or mix(p["ink"], p["muted"], 0.4)
    key = p.get("keyInk") or mix(p["ink"], p["muted"], 0.25)
    pink = p.get("pink") or mix(p["red"], p["ink"], 0.4)
    a = lambda alpha, h: "#%02x%s" % (round(alpha * 255), h.lstrip("#"))
    c = {
        "ground": p["ground"], "surface": p["surface"], "card": p["card"],
        "ink": p["ink"], "muted": p["muted"], "soft": soft, "keyInk": key,
        "red": p["red"], "green": p["green"], "yellow": p["orange"], "blue": p["blue"],
        "magenta": p["magenta"], "cyan": p["cyan"], "pink": pink, "sand": p["yellow"],
        "dim": p["dim"],
        "sparkFill": a(0.2, p["cyan"]),
        "border": a(0.4 if light else 0.3, p["border"]),
        "headBg": a(0.4, p["surface"]),
        "selBg": a(0.3, p["dim"]),
        "onAccent": p["ground"],
    }
    if light:
        c["wash"] = "#000000"
        c["shadow"] = "#000000"
    return {"name": p["name"], "mode": p["mode"], "colors": c}

warn = []
for stem, p in THEMES.items():
    t = build(p, stem)
    c = t["colors"]
    g = c["ground"]
    checks = [("ink", 4.5), ("keyInk", 3.5), ("soft", 3.0), ("muted", 2.4)] + \
             [(k, 2.6) for k in ("red", "green", "yellow", "blue", "magenta", "cyan", "sand")]
    for k, need in checks:
        r = contrast(c[k], g)
        if r < need:
            warn.append(f"{stem:22} {k:8} {c[k]} on {g}: {r:.2f} < {need}")
    with open(os.path.join(OUT, stem + ".json"), "w") as fh:
        json.dump(t, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
print(len(THEMES), "themes written")
print("\n".join(warn) if warn else "no contrast warnings")
print("adjusted for light glass:"); print("\n".join(ADJUSTED))
