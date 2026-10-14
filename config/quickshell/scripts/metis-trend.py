#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# A CURRENCY'S LAST THREE MONTHS, for the line under a money answer in
# Metis. The rates are the ones qalc itself uses, one snapshot a week: a
# past day's rates never change, so each is fetched once and kept in the
# cache directory — for as long as the line can show it, then deleted.
# The newest point is qalc's own rates.json, so the line ends on the rate
# the answer was worked out with.
#
#   metis-trend.py <FROM> <TO> <cache dir> <qalc rates.json>
#
# Prints "YYYY-MM-DD value" lines, value being how many TO one FROM buys.
# A week that cannot be fetched is left out, and tried again a day later.
#
# BUILT TO OUTLIVE ITS SOURCE (user, 2026-10-14):
# - Where to fetch is read out of qalc's own library first: its "latest"
#   addresses with the date put in place of "latest". A qalc update that
#   moves to another host or API version moves this with it; the addresses
#   written here are only the fallback.
# - A snapshot is read whatever its base currency ({"date", "<base>": {…}}),
#   so a change of base breaks nothing.
# - If no snapshot host answers at all, the ECB's series (through
#   Frankfurter, one request) stands in for the currencies it covers.
# - Anything that fails leaves the line out; Metis answers without it.

import ctypes.util
import datetime
import glob
import json
import os
import re
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

WEEKS = 13
# kept a little past what is drawn, so a week's turn never refetches
KEEP_DAYS = (WEEKS + 2) * 7
FALLBACK = [
    "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{d}/v1/currencies/eur.min.json",
    "https://{d}.currency-api.pages.dev/v1/currencies/eur.min.json",
]
ECB = "https://api.frankfurter.dev/v1/{a}..{b}?base={f}&symbols={t}"
# said who is asking: some hosts refuse Python's own default (Frankfurter: 403)
AGENT = "metis-trend/1 (quickshell calculator)"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=6) as r:
        return json.loads(r.read())


def qalc_urls():
    # qalc's snapshot addresses as it ships them, "latest" made a date slot
    paths = []
    name = ctypes.util.find_library("qalculate")
    for d in ("/usr/lib", "/usr/lib64", "/usr/local/lib", "/usr/lib/x86_64-linux-gnu"):
        paths += glob.glob(os.path.join(d, "libqalculate.so*"))
    if name:
        paths.insert(0, name)
    for p in paths:
        try:
            with open(p if "/" in p else "/usr/lib/" + p, "rb") as f:
                data = f.read()
        except OSError:
            continue
        found = []
        # whole strings only, NUL to NUL: the library also holds fragments
        # of them run together ("…/currencrencies/eur.json")
        for m in re.finditer(rb"(?<=\x00)https://[\x21-\x7e]+?\.json(?=\x00)", data):
            u = m.group(0).decode("ascii", "ignore")
            if "latest" in u and "currenc" in u and u.count("latest") == 1:
                found.append(u.replace("latest", "{d}"))
        if found:
            return list(dict.fromkeys(found))
    return []


def days():
    # every seventh day counted from 1970-01-01, so the same dates come up
    # whichever day it is asked on and the cache is hit
    today = datetime.date.today() - datetime.timedelta(days=1)
    epoch = datetime.date(1970, 1, 1)
    last = today - datetime.timedelta(days=(today - epoch).days % 7)
    return [last - datetime.timedelta(weeks=w) for w in range(WEEKS)]


def table(obj):
    # {"base", "rates"} out of a snapshot, whatever currency it is based on
    if not isinstance(obj, dict):
        return None
    if isinstance(obj.get("rates"), dict) and isinstance(obj.get("base"), str):
        return {"base": obj["base"].lower(), "rates": obj["rates"]}
    for k, v in obj.items():
        if k != "date" and isinstance(v, dict) and len(v) > 10:
            return {"base": k.lower(), "rates": v}
    return None


def fetch(cache, day, urls):
    d = day.isoformat()
    path = os.path.join(cache, d + ".json")
    if os.path.exists(path):
        return
    miss = path + ".miss"
    if os.path.exists(miss) and time.time() - os.path.getmtime(miss) < 86400:
        return
    for url in urls:
        try:
            t = table(get(url.format(d=d)))
            if not t:
                continue
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(t, f)
            os.replace(tmp, path)
            return
        except Exception:
            continue
    open(miss, "w").close()


def ratio(t, a, b):
    rates, base = t["rates"], t["base"]
    ra = 1.0 if a == base else rates.get(a)
    rb = 1.0 if b == base else rates.get(b)
    if not isinstance(ra, (int, float)) or not isinstance(rb, (int, float)) or ra <= 0:
        return None
    return rb / ra


def prune(cache):
    # past what the line draws: gone, and so are leftovers of a killed run
    cut = datetime.date.today() - datetime.timedelta(days=KEEP_DAYS)
    for p in glob.glob(os.path.join(cache, "*")):
        name = os.path.basename(p)
        m = re.match(r"(\d{4}-\d{2}-\d{2})\.json", name)
        try:
            if m and datetime.date.fromisoformat(m.group(1)) < cut:
                os.remove(p)
            elif name.endswith(".tmp") and time.time() - os.path.getmtime(p) > 3600:
                os.remove(p)
            elif name.endswith(".miss") and time.time() - os.path.getmtime(p) > 86400:
                os.remove(p)
        except (OSError, ValueError):
            pass


def ecb(a, b, want):
    # the ECB's daily series for the span, one request, for when no snapshot
    # host answers; only the ~30 currencies it publishes
    try:
        url = ECB.format(a=want[-1].isoformat(), b=want[0].isoformat(), f=a.upper(), t=b.upper())
        series = get(url).get("rates", {})
        return {d: v[b.upper()] for d, v in series.items()
                if isinstance(v, dict) and isinstance(v.get(b.upper()), (int, float))}
    except Exception:
        return {}


def main():
    if len(sys.argv) < 5:
        return
    a, b, cache, qalc = sys.argv[1].lower(), sys.argv[2].lower(), sys.argv[3], sys.argv[4]
    os.makedirs(cache, exist_ok=True)
    prune(cache)
    want = days()
    urls = list(dict.fromkeys(qalc_urls() + FALLBACK))
    with ThreadPoolExecutor(max_workers=6) as pool:
        list(pool.map(lambda d: fetch(cache, d, urls), want))

    points = {}
    for day in want:
        try:
            with open(os.path.join(cache, day.isoformat() + ".json")) as f:
                t = table(json.load(f))
            v = ratio(t, a, b) if t else None
            if v:
                points[day.isoformat()] = v
        except Exception:
            pass
    if len(points) < 3:
        # every snapshot host gone: weekly points out of the ECB's days
        series = ecb(a, b, want)
        for day in want:
            near = [d for d in series if d <= day.isoformat()]
            if near:
                points[day.isoformat()] = series[max(near)]
    try:
        with open(qalc) as f:
            q = json.load(f)
        t = table(q)
        v = ratio(t, a, b) if t else None
        if v and isinstance(q.get("date"), str):
            points[q["date"]] = v
    except Exception:
        pass
    for d in sorted(points):
        print(d, "%.10g" % points[d])


main()
