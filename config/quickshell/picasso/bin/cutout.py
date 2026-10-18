#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# PICASSO'S CUT-OUT (2026-10-18): the subject of a picture, its background
# gone. rembg has no prebuilt package (python-gradio, python-pymatting and
# python-asyncer compile from the AUR), so this runs the same models with only
# the official repos' python-onnxruntime-cpu, python-numpy, python-pillow and
# python-scipy.
#
#   cutout.py [--model isnet|u2net] [--plain] [--mask] [--progress] IN OUT
#   cutout.py --fetch [--model …]      the model fetched, nothing else (install)
#
# OUT is a PNG with alpha; exit 0 on success. The first run of a model fetches
# it from rembg's release assets (md5-checked, renamed into place whole) into
# ~/.u2net, where rembg looks too.
#
# THE MODEL'S VIEW IS rembg's, NOT A GUESS: input size, mean/std and the
# min-max of the output are read from rembg 2.0.72 (the AUR's) sessions/
# base.py normalize(), dis_general_use.py and u2net.py; 2.0.85 is the same.
# --plain is exactly rembg's `rembg i -m MODEL` (its mask, its naive cutout)
# and is how the two are compared (byte-identical on the test set). Without
# it, three steps go beyond it, each kept because edge crops showed it help:
#   1. the edge band's alpha from the photo's own colours (edge()), so the
#      backdrop leaves the gaps between hair and fur strands;
#   2. the model's near-0 haze and near-1 dither made exact (levels());
#   3. the colour of every soft edge pixel is the subject's, the backdrop's
#      bleed removed (colour(), blur fusion, Forte & Pitié 2021).
# A guided filter (He & Sun) was tried for 1 and dropped: it added wisps but
# also speckle from sensor noise, and could not reach the gaps.

import argparse
import hashlib
import os
import subprocess
import sys
import tempfile
import urllib.request

MODELS = {
    # name: (file, md5, size, mean, std, clip) — rembg's own values
    "isnet": ("isnet-general-use.onnx", "fc16ebd8b0c10d971d3513d564d01e29", 1024,
              (0.5, 0.5, 0.5), (1.0, 1.0, 1.0), False),
    "u2net": ("u2net.onnx", "60024c5c889badc19c04ad937298a77b", 320,
              (0.485, 0.456, 0.406), (0.229, 0.224, 0.225), True),
}
RELEASE = "https://github.com/danielgatis/rembg/releases/download/v0.0.0/"


# --progress: a line on stdout as each step ends — "@ FRACTION what now" —
# for the viewer's status band (viewer.js parseCutoutProgress). The fractions
# are the steps' shares of a run measured on this machine (6 cores, isnet,
# 4–36 MP), so the band moves when a step really ends, never at a guessed
# rate.
PROGRESS = False


def step(frac, what):
    if PROGRESS:
        print("@ %.3f %s" % (frac, what), flush=True)


def die(msg, code=1):
    print("cutout: " + msg, file=sys.stderr)
    sys.exit(code)


# ── the model file ────────────────────────────────────────────────────────
# rembg's places: U2NET_HOME (or $XDG_DATA_HOME/.u2net, or ~/.u2net), and
# 2.0.85's per-model directory under ~/.rembg — reused when there, written to
# the first.
def homes():
    legacy = os.path.expanduser(os.getenv(
        "U2NET_HOME", os.path.join(os.getenv("XDG_DATA_HOME", "~"), ".u2net")))
    xdg = os.getenv("XDG_DATA_HOME")
    new = os.path.expanduser(os.getenv(
        "REMBG_HOME", os.path.join(xdg, "rembg") if xdg else "~/.rembg"))
    return legacy, new


def model_path(name):
    fname, md5 = MODELS[name][0], MODELS[name][1]
    legacy, new = homes()
    stem = fname[:-5]
    for p in (os.path.join(legacy, fname), os.path.join(new, "models", stem, fname)):
        if os.path.isfile(p):
            return p
    os.makedirs(legacy, exist_ok=True)
    dest = os.path.join(legacy, fname)
    print("cutout: fetching " + fname + " (once)", file=sys.stderr)
    fd, part = tempfile.mkstemp(prefix=fname + ".", suffix=".part", dir=legacy)
    try:
        h = hashlib.md5()
        req = urllib.request.Request(RELEASE + fname, headers={"User-Agent": "picasso-cutout"})
        with urllib.request.urlopen(req, timeout=60) as r, os.fdopen(fd, "wb") as f:
            total, got, said = int(r.headers.get("Content-Length") or 0), 0, -1
            while True:
                b = r.read(1 << 20)
                if not b:
                    break
                h.update(b)
                f.write(b)
                got += len(b)
                pct = got * 100 // total if total else 0
                if pct != said:
                    said = pct
                    step(0.04 + 0.06 * pct / 100, "fetching its model, once \u00b7 %d%%" % pct)
        if h.hexdigest() != md5:
            die(fname + ": checksum mismatch, not kept")
        os.chmod(part, 0o644)
        os.replace(part, dest)
    finally:
        if os.path.exists(part):
            os.unlink(part)
    return dest


def session(name):
    import onnxruntime as ort
    ort.set_default_logger_severity(3)
    o = ort.SessionOptions()
    o.intra_op_num_threads = len(os.sched_getaffinity(0))
    o.inter_op_num_threads = 1
    o.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    o.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    return ort.InferenceSession(model_path(name), sess_options=o,
                                providers=["CPUExecutionProvider"])


# ── the picture ───────────────────────────────────────────────────────────
# Upright (EXIF), 8-bit RGB for the model, plus its own alpha when it has
# one. CMYK goes through its ICC profile when it carries one; 16-bit and
# float greys are scaled, not clipped. Anything Pillow cannot read
# (HEIC, AVIF, raw…) is first made a PNG by ImageMagick.
def load(path):
    from PIL import Image, ImageOps
    import numpy as np
    Image.MAX_IMAGE_PIXELS = 400_000_000
    try:
        im = Image.open(path)
        im.load()
    except Exception:
        fd, tmp = tempfile.mkstemp(suffix=".png")
        os.close(fd)
        try:
            r = subprocess.run(["magick", "--", path + "[0]", "-auto-orient", "-depth", "8", "png:" + tmp],
                               capture_output=True)
            if r.returncode != 0:
                die("cannot read " + path)
            im = Image.open(tmp)
            im.load()
        finally:
            os.unlink(tmp)
    im = ImageOps.exif_transpose(im)
    alpha = None
    if im.mode in ("I;16", "I;16B", "I;16L", "I;16N", "I", "F"):
        a = np.asarray(im, dtype=np.float64)
        hi = 65535.0 if im.mode != "F" else max(float(a.max()), 1e-6)
        if im.mode == "I" and a.max() <= 255:
            hi = 255.0
        im = Image.fromarray(np.clip(a / hi * 255 + 0.5, 0, 255).astype(np.uint8), "L")
    if im.mode == "CMYK":
        icc = im.info.get("icc_profile")
        if icc:
            try:
                import io
                from PIL import ImageCms
                src = ImageCms.ImageCmsProfile(io.BytesIO(icc))
                im = ImageCms.profileToProfile(im, src, ImageCms.createProfile("sRGB"), outputMode="RGB")
            except Exception:
                im = im.convert("RGB")
        else:
            im = im.convert("RGB")
    if im.mode == "P":
        im = im.convert("RGBA" if "transparency" in im.info else "RGB")
    if im.mode in ("LA", "La", "PA", "RGBa"):
        im = im.convert("RGBA")
    if im.mode == "RGBA":
        alpha = im.getchannel("A")
    return im, alpha


# ── the model, as rembg runs it ───────────────────────────────────────────
# rembg's normalize(): RGB, LANCZOS to the model's square, divided by its
# own maximum, (x − mean) / std, NCHW float32. predict(): channel 0 of the
# first output, min-max to 0..1.
def infer(sess, name, im):
    import numpy as np
    from PIL import Image
    size, mean, std = MODELS[name][2], MODELS[name][3], MODELS[name][4]
    a = np.array(im.convert("RGB").resize((size, size), Image.Resampling.LANCZOS))
    a = a / max(np.max(a), 1e-6)
    t = np.zeros((size, size, 3))
    for c in range(3):
        t[:, :, c] = (a[:, :, c] - mean[c]) / std[c]
    t = np.expand_dims(t.transpose((2, 0, 1)), 0).astype(np.float32)
    pred = sess.run(None, {sess.get_inputs()[0].name: t})[0][:, 0, :, :]
    ma, mi = np.max(pred), np.min(pred)
    return np.squeeze((pred - mi) / (ma - mi))


def rembg_mask(pred, name, size):
    # rembg's own: to uint8 by truncation (u2net clipped first), LANCZOS up
    import numpy as np
    from PIL import Image
    p = pred.clip(0, 1) if MODELS[name][5] else pred
    return Image.fromarray((p * 255).astype("uint8"), mode="L").resize(size, Image.Resampling.LANCZOS)


# ── beyond rembg ──────────────────────────────────────────────────────────
# Whole-picture work is done small and only the pixels that need it are
# touched at full size, so a 36-megapixel photo stays a few seconds and a few
# hundred MB over the model.
def shrink(get, H, W, s, ch):
    # the s×s block means of a full-size quantity (the last blocks may be
    # smaller), built a strip at a time; get(y0, y1) returns rows y0..y1
    import numpy as np
    h, w = -(-H // s), -(-W // s)
    out = np.empty((h, w) + ((ch,) if ch else ()), np.float32)
    cw = np.minimum(s, W - np.arange(0, W, s)).astype(np.float32)
    cw = cw.reshape((1, w) + ((1,) if ch else ()))
    step = s * max(1, 512 // s)
    for y0 in range(0, H, step):
        y1 = min(H, y0 + step)
        x = np.add.reduceat(np.asarray(get(y0, y1), np.float32), np.arange(0, y1 - y0, s), 0)
        x = np.add.reduceat(x, np.arange(0, W, s), 1)
        rh = np.minimum(s, (y1 - y0) - np.arange(0, y1 - y0, s)).astype(np.float32)
        out[y0 // s:y0 // s + x.shape[0]] = x / (rh.reshape((-1, 1) + ((1,) if ch else ())) * cw)
    return out


def box(x, r):
    from scipy.ndimage import uniform_filter
    size = (2 * r + 1, 2 * r + 1) + (1,) * (x.ndim - 2)
    return uniform_filter(x, size=size, mode="nearest")


def at(low, ys, xs, s):
    # a small map read at full-size pixels: its cell. The maps are means over
    # many cells, so nothing finer is there to interpolate.
    return low[ys // s, xs // s]


def edge(I8, m, L):
    # COLOUR-LINE ALPHA IN THE EDGE BAND. A trimap from the model: surely
    # subject (> 0.95) and surely background (< 0.05), each eroded by e; the
    # rest is the band. There, each pixel's own colour says how much of it is
    # subject: its place on the line from the nearby background colour B to
    # the nearby subject colour F, α = (I − B)·(F − B) / |F − B|². Trusted
    # only as far as F and B differ, both were seen close by, and the pixel
    # sits on that line, and it raises alpha only where the model saw some
    # subject; elsewhere the model's value stands. This is what
    # takes the backdrop out from between strands of hair and fur, which the
    # model's 1024-px view calls solid.
    import numpy as np
    from scipy.ndimage import minimum_filter
    H, W = m.shape
    e = max(4, round(L / 120))
    s = max(1, e // 6)
    ps = shrink(lambda a, b: m[a:b], H, W, s, 0)
    k = max(1, round(e / s))
    fg = minimum_filter((ps > 0.95).astype(np.uint8), size=2 * k + 1).astype(np.float32)
    bg = minimum_filter((ps < 0.05).astype(np.uint8), size=2 * k + 1).astype(np.float32)
    Is = shrink(lambda a, b: I8[a:b].astype(np.float32) / 255, H, W, s, 3)
    rr = max(1, round(2 * e / s))
    wf, wb = box(fg, rr), box(bg, rr)
    Fm = box(Is * fg[..., None], rr) / (wf[..., None] + 1e-6)
    Bm = box(Is * bg[..., None], rr) / (wb[..., None] + 1e-6)
    unk = (fg + bg) < 0.5
    unk = np.repeat(np.repeat(unk, s, 0), s, 1)[:H, :W]
    ys, xs = np.nonzero(unk)
    for i in range(0, len(ys), 1 << 21):      # a batch at a time: memory
        y, x = ys[i:i + (1 << 21)], xs[i:i + (1 << 21)]
        I = I8[y, x].astype(np.float32) / 255
        F, B = at(Fm, y, x, s), at(Bm, y, x, s)
        d = F - B
        dd = (d * d).sum(-1)
        ac = np.clip(((I - B) * d).sum(-1) / (dd + 1e-6), 0, 1)
        res = I - (B + ac[..., None] * d)
        conf = (dd / (dd + 0.06)) * np.exp(-(res * res).sum(-1) / 0.004)
        conf *= np.clip(at(wf, y, x, s) * 8, 0, 1) * np.clip(at(wb, y, x, s) * 8, 0, 1)
        p = m[y, x]
        # backdrop taken out freely; subject added only where the model saw
        # some (a dark blob in the bokeh is not fur)
        conf = np.where(ac > p, conf * np.clip(p / 0.15, 0, 1), conf)
        m[y, x] = p + conf * (ac - p)
    return m


def levels(m, lo=0.03, hi=0.97):
    # the model's near-0 haze and near-1 dither made exact
    import numpy as np
    m -= lo
    m *= 1 / (hi - lo)
    return np.clip(m, 0, 1, out=m)


def colour(I8, a, L):
    # THE SUBJECT'S OWN COLOUR AT SOFT EDGES. Forte & Pitié's blur fusion
    # (2021), twice: F = F̄ + α (I − α F̄ − (1 − α) B̄), the bars alpha-
    # weighted local means — a wide pass, then a narrow one on its result.
    # The means are smooth, so both are worked small; the photo's own pixel
    # brings the detail back, and only where alpha is soft. Elsewhere the
    # photo's pixel is the colour.
    import numpy as np
    H, W = a.shape
    out = I8.copy()
    ys, xs = np.nonzero((a > 0.004) & (a < 0.996))
    if not len(ys):
        return out
    eps = 1e-5
    r1 = max(8, round(L / 22))
    s1 = max(1, r1 // 8)
    A = shrink(lambda y0, y1: a[y0:y1], H, W, s1, 0)
    IA = shrink(lambda y0, y1: I8[y0:y1].astype(np.float32) / 255 * a[y0:y1, :, None], H, W, s1, 3)
    Ib = shrink(lambda y0, y1: I8[y0:y1].astype(np.float32) / 255, H, W, s1, 3)
    rr = max(1, round(r1 / s1))
    Ab = box(A, rr)[..., None]
    Fm1 = box(IA, rr) / (Ab + eps)
    Bm1 = box(Ib - IA, rr) / (1 - Ab + eps)
    r2 = max(1, r1 // 15)
    s2 = max(1, r2 // 3)
    # the narrow pass on the wide one's result, both read on s2's grid
    A2 = shrink(lambda y0, y1: a[y0:y1], H, W, s2, 0)[..., None]
    I2 = shrink(lambda y0, y1: I8[y0:y1].astype(np.float32) / 255, H, W, s2, 3)
    cy = np.minimum((np.arange(A2.shape[0]) * s2 + s2 // 2) // s1, Fm1.shape[0] - 1)
    cx = np.minimum((np.arange(A2.shape[1]) * s2 + s2 // 2) // s1, Fm1.shape[1] - 1)
    Fb, Bb = Fm1[cy][:, cx], Bm1[cy][:, cx]
    F1 = np.clip(Fb + A2 * (I2 - A2 * Fb - (1 - A2) * Bb), 0, 1)
    rr = max(1, round(r2 / s2))
    Ab = box(A2[..., 0], rr)[..., None]
    Fm2 = box(F1 * A2, rr) / (Ab + eps)
    Bm2 = box(Bb * (1 - A2), rr) / (1 - Ab + eps)
    I = I8[ys, xs].astype(np.float32) / 255
    al = a[ys, xs, None]
    Fm, Bm = at(Fm2, ys, xs, s2), at(Bm2, ys, xs, s2)
    out[ys, xs] = (np.clip(Fm + al * (I - al * Fm - (1 - al) * Bm), 0, 1) * 255 + 0.5).astype(np.uint8)
    return out


def main():
    ap = argparse.ArgumentParser(prog="cutout.py")
    ap.add_argument("--model", choices=sorted(MODELS), default="isnet")
    ap.add_argument("--plain", action="store_true", help="rembg's own result, nothing more")
    ap.add_argument("--mask", action="store_true", help="write only the mask")
    ap.add_argument("--no-edge", action="store_true", help="the model's edge as it is")
    ap.add_argument("--no-fg", action="store_true")
    ap.add_argument("--no-levels", action="store_true")
    ap.add_argument("--times", action="store_true", help="each step's seconds, on stderr")
    ap.add_argument("--level", type=int, default=1, help="PNG compression, 0-9")
    ap.add_argument("--progress", action="store_true", help="'@ FRACTION what' lines on stdout")
    ap.add_argument("--fetch", action="store_true", help="only make sure the model is here (the installer)")
    ap.add_argument("inp", nargs="?")
    ap.add_argument("out", nargs="?")
    o = ap.parse_args()
    if o.fetch:
        print(model_path(o.model))
        return
    if not o.inp or not o.out:
        ap.error("IN and OUT are needed")
    import time
    t0 = [time.monotonic()]

    global PROGRESS
    PROGRESS = o.progress
    # what each step's end means for the band: (done so far, what comes next)
    after = {"load": (0.04, "finding the subject"), "session": (0.10, "finding the subject"),
             "model": (0.42, "following its edges"), "upscale": (0.45, "following its edges"),
             "edge": (0.62, "taking the backdrop's colour out"), "colour": (0.80, "writing it"),
             "save": (1.0, "done")}

    def lap(what):
        if what in after:
            step(*after[what])
        if o.times:
            t = time.monotonic()
            print("cutout: %-8s %.2fs" % (what, t - t0[0]), file=sys.stderr)
            t0[0] = t
    import numpy as np
    from PIL import Image

    step(0.0, "reading the picture")
    img, alpha = load(o.inp)
    lap("load")
    rgb = img
    if alpha is not None:
        # the model and the edge see it on white, not its hidden colours
        rgb = Image.new("RGB", img.size, (255, 255, 255))
        rgb.paste(img.convert("RGB"), mask=alpha)
    sess = session(o.model)
    lap("session")
    pred = infer(sess, o.model, img if o.plain else rgb)
    lap("model")

    if o.plain:
        mask = rembg_mask(pred, o.model, img.size)
        if o.mask:
            mask.save(o.out, "PNG")
            return
        out = Image.composite(img, Image.new("RGBA", img.size, 0), mask)
        out.save(o.out, "PNG")
        return

    W, H = img.size
    L = max(W, H)
    m = np.asarray(Image.fromarray(pred.astype(np.float32), "F").resize((W, H), Image.Resampling.LANCZOS)).copy()
    np.clip(m, 0, 1, out=m)
    I8 = np.asarray(rgb.convert("RGB"))
    lap("upscale")
    if not o.no_edge:
        m = edge(I8, m, L)
        lap("edge")
    if not o.no_levels:
        m = levels(m)
    if alpha is not None:
        m *= np.asarray(alpha, np.float32) / 255
    if o.mask:
        Image.fromarray((m * 255 + 0.5).astype(np.uint8), "L").save(o.out, "PNG")
        return
    out = I8.copy() if o.no_fg else colour(I8, m, L)
    lap("colour")
    a8 = (m * 255 + 0.5).astype(np.uint8)
    del m
    Image.fromarray(np.dstack([out, a8]), "RGBA").save(o.out, "PNG", compress_level=o.level)
    lap("save")


if __name__ == "__main__":
    main()
