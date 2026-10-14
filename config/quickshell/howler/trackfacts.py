# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# TRACKFACTS — what a track toast says about the song beyond its name, for a
# player that does not say it in the toast. spoot wrote its marks into the
# body; Spotify's own client writes "Artist — Album" and nothing else, and its
# MPRIS metadata has no explicit flag and no lyrics either. So they are asked
# for here, once per track, from places that need no account:
#
#   explicit  Spotify's public embed page for the track, which carries the
#             flag in its page data. Only for a Spotify track id.
#   lyrics    LRCLIB, by title, artist, album and length — the lookup spoot
#             itself made. An instrumental counts as none.
#
#   python3 -I trackfacts.py TRACKID URL TITLE ARTIST ALBUM SECONDS
#
# One line of JSON out: {"explicit": true|false|null, "lyrics": true|false|null}.
# null is "could not tell", which the toast draws as nothing — never as "no".
# Stdlib only.

import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "howler/1 (quickshell; https://github.com/kbuckleys/)"


def spotify_id(trackid, url):
    for s in (trackid, url):
        m = re.search(r"(?:spotify[:/]track[:/]|open\.spotify\.com/track/)([A-Za-z0-9]{22})", s or "")
        if m:
            return m.group(1)
    return ""


def fetch(url, timeout=8):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def explicit(tid):
    if not tid:
        return None
    try:
        page = fetch("https://open.spotify.com/embed/track/" + tid)
    except Exception:
        return None
    # THE TRACK'S OWN FLAG, not the first one on the page: the embed carries
    # the entity first, but the id beside it is what makes that certain.
    m = re.search(r'"id":"%s".{0,4000}?"isExplicit":(true|false)' % tid, page, re.S)
    if not m:
        m = re.search(r'"isExplicit":(true|false)', page)
    return None if not m else m.group(1) == "true"


def has_lyrics(row):
    return bool(row) and not row.get("instrumental") and bool(
        (row.get("plainLyrics") or "").strip() or (row.get("syncedLyrics") or "").strip())


def lyrics(title, artist, album, secs):
    if not title or not artist:
        return None
    q = {"track_name": title, "artist_name": artist}
    if album:
        q["album_name"] = album
    if secs > 0:
        q["duration"] = str(int(round(secs)))
    # LRCLIB answers "busy" now and then; two more tries cover it.
    for attempt in range(3):
        try:
            return has_lyrics(json.loads(fetch("https://lrclib.net/api/get?" + urllib.parse.urlencode(q))))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                break
            if e.code < 500:
                return None
        except Exception:
            return None
        time.sleep(1 + attempt)
    else:
        return None
    # NOT FOUND EXACTLY is not "no lyrics": the album or the length differ by
    # a little more often than the song is missing. A search by name decides.
    try:
        rows = json.loads(fetch("https://lrclib.net/api/search?" + urllib.parse.urlencode(
            {"track_name": title, "artist_name": artist})))
    except Exception:
        return None
    return any(has_lyrics(r) for r in rows if isinstance(r, dict))


def main(argv):
    a = (argv + [""] * 6)[:6]
    try:
        secs = float(a[5] or 0)
    except ValueError:
        secs = 0
    print(json.dumps({
        "explicit": explicit(spotify_id(a[0], a[1])),
        "lyrics": lyrics(a[2], a[3], a[4], secs),
    }))


if __name__ == "__main__":
    main(sys.argv[1:])
