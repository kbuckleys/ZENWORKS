#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE PLACES METIS KNOWS BY NAME, built once. metis.js carries a short table
# of the cities people name most; everything else — Ontario, Lyon, Porto,
# any of the 30,000 cities of 15,000 people or more, every province, state
# and country — is in the index this writes, read with awk when a question
# names a place the table does not have.
#
# From GeoNames (https://www.geonames.org), CC BY 4.0: cities15000,
# admin1CodesASCII and countryInfo, downloaded here, boiled down, and thrown
# away. Run once — Metis runs it itself when the index is missing — and
# never again unless the index is deleted.
#
#   metis-places.py <out.tsv>
#
# One place a line, in the order a lookup should meet them, so the first
# match is the one meant:
#   key  kind  name  region  cc  country  lat  lon  tz  population  via  alt
# kind is c (city), r (province or state) or n (country); a region or a
# country stands at its biggest city, or its capital, and `via` names it.
# alt is 1 for a name the place is also known by (Bombay, Peking, Köln's
# Cologne): every place's own name comes before every other name, so
# "venice" is Venice and not a Dayton that is also called that somewhere.

import io
import os
import sys
import tempfile
import urllib.request
import zipfile

BASE = "https://download.geonames.org/export/dump/"
UA = {"User-Agent": "zenworks-metis/1.0 (https://github.com/kbuckleys/)"}


def fetch(name):
    req = urllib.request.Request(BASE + name, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def clean(s):
    # a tab or a newline inside a name would break the line it is on
    return " ".join(str(s).split())


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: metis-places.py <out.tsv>")
    out = sys.argv[1]

    with zipfile.ZipFile(io.BytesIO(fetch("cities15000.zip"))) as z:
        cities_txt = z.read("cities15000.txt").decode("utf-8")
    admin_txt = fetch("admin1CodesASCII.txt").decode("utf-8")
    country_txt = fetch("countryInfo.txt").decode("utf-8")

    # "CA.08" → "Ontario"
    admin = {}
    for line in admin_txt.splitlines():
        f = line.split("\t")
        if len(f) >= 3:
            admin[f[0]] = clean(f[2] or f[1])

    # "CA" → ("Canada", "Ottawa", population)
    countries = {}
    for line in country_txt.splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) >= 8:
            try:
                pop = int(f[7] or 0)
            except ValueError:
                pop = 0
            countries[f[0]] = (clean(f[4]), clean(f[5]), pop)

    cities = []
    for line in cities_txt.splitlines():
        f = line.split("\t")
        if len(f) < 19:
            continue
        try:
            pop = int(f[14] or 0)
            lat, lon = float(f[4]), float(f[5])
        except ValueError:
            continue
        cc = f[8]
        cities.append({
            "name": clean(f[1]), "ascii": clean(f[2]), "alts": f[3],
            "lat": lat, "lon": lon, "cc": cc, "tz": f[17], "pop": pop,
            "region": admin.get(cc + "." + f[10], ""),
            "country": countries.get(cc, ("", "", 0))[0],
        })

    rows = []

    # rank decides between places with one name; population is what is shown
    def row(key, kind, c, pop, rank, via="", alt=0):
        rows.append((key.lower(), kind, c["name"], c["region"], c["cc"], c["country"],
                     "%.4f" % c["lat"], "%.4f" % c["lon"], c["tz"], pop, via, alt, rank))

    for c in cities:
        own = {c["name"].lower(), c["ascii"].lower()}
        keys = set()
        # English names for the bigger ones: Munich for München, Cologne
        # for Köln. Only plain-letter words — the list also holds codes and
        # transliterations no one types.
        if c["pop"] >= 100000:
            for a in c["alts"].split(","):
                a = a.strip()
                if 3 <= len(a) <= 40 and all(ch.isascii() and (ch.isalpha() or ch in " -'.") for ch in a) \
                        and not a.isupper():
                    keys.add(a.lower())
        for k in own:
            if k:
                row(k, "c", c, c["pop"], c["pop"])
        for k in keys - own:
            if k:
                row(k, "c", c, c["pop"], c["pop"], alt=1)

    # a province or state: where its biggest city is
    best = {}
    total = {}
    for c in cities:
        if not c["region"]:
            continue
        k = (c["cc"], c["region"])
        total[k] = total.get(k, 0) + c["pop"]
        if k not in best or c["pop"] > best[k]["pop"]:
            best[k] = c
    # ranked just under its own biggest city: "sao paulo" is the city, not
    # the state of 54 million around it
    for k, c in best.items():
        r = dict(c, name=k[1], region=k[1])
        row(k[1], "r", r, total[k], c["pop"] - 1, c["name"])

    # a country: where its capital is, or its biggest city
    by_cc = {}
    for c in cities:
        by_cc.setdefault(c["cc"], []).append(c)
    for cc, (name, capital, pop) in countries.items():
        cs = by_cc.get(cc)
        if not name or not cs:
            continue
        cap = next((c for c in cs if capital and capital in (c["name"], c["ascii"])), None) \
            or max(cs, key=lambda c: c["pop"])
        r = dict(cap, name=name, region="")
        p = pop or sum(c["pop"] for c in cs)
        row(name, "n", r, p, p, cap["name"])

    rows.sort(key=lambda r: (r[11], -r[12]))

    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(out)) or ".")
    with os.fdopen(fd, "w", encoding="utf-8") as w:
        w.write("# Places for metis, from GeoNames (https://www.geonames.org), CC BY 4.0\n")
        w.write("# key\tkind\tname\tregion\tcc\tcountry\tlat\tlon\ttz\tpopulation\tvia\talt\n")
        for r in rows:
            w.write("\t".join(str(x) for x in r[:12]) + "\n")
    os.replace(tmp, out)


if __name__ == "__main__":
    main()
