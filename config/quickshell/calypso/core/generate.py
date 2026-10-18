# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# NEW PASSWORDS, AND HOW STRONG ONE IS — calypso's own generator, the same
# for every platform (1Password's has letters, words and PINs; so has this).
# `secrets` only: the OS's own randomness, never `random`.
#
#   make({ mode: chars|words|pin, length, upper, lower, digits, symbols,
#          ambiguous, words, separator, capitalize, number }) → { value, bits }
#   strength(text) → { bits, score 0–4, word }
#
# Words come from /usr/share/dict/words (the `words` package) — lowercase,
# 3 to 8 letters, plain a–z; the window offers to install it (Ceres) when it
# is missing and words are asked for.

import math
import re
import secrets
import string

DICT = "/usr/share/dict/words"
AMBIGUOUS = set("Il1O0o|`'\"")
SYMBOLS = "!@#$%^&*-_=+?.:;,~"

_words = None


def words():
    global _words
    if _words is None:
        out = set()
        try:
            with open(DICT, encoding="utf-8", errors="ignore") as f:
                for w in f:
                    w = w.strip()
                    if 3 <= len(w) <= 8 and w.isascii() and w.isalpha() and w.islower():
                        out.add(w)
        except OSError:
            pass
        _words = sorted(out)
    return _words


def have_words():
    return len(words()) >= 2048


def make(opts):
    mode = opts.get("mode") or "chars"
    if mode == "pin":
        n = max(4, min(int(opts.get("length") or 6), 32))
        v = "".join(secrets.choice(string.digits) for _ in range(n))
        return {"value": v, "bits": round(n * math.log2(10), 1)}
    if mode == "words":
        pool = words()
        if len(pool) < 2048:
            raise ValueError("no word list: install the words package")
        n = max(3, min(int(opts.get("words") or 4), 12))
        sep = str(opts.get("separator") if opts.get("separator") is not None else "-")[:3]
        picked = [secrets.choice(pool) for _ in range(n)]
        if opts.get("capitalize"):
            picked = [w.capitalize() for w in picked]
        bits = n * math.log2(len(pool))
        if opts.get("number"):
            i = secrets.randbelow(n)
            picked[i] = picked[i] + str(secrets.randbelow(10))
            bits += math.log2(10 * n)
        return {"value": sep.join(picked), "bits": round(bits, 1)}
    n = max(4, min(int(opts.get("length") or 20), 128))
    sets = []
    if opts.get("lower", True):
        sets.append(string.ascii_lowercase)
    if opts.get("upper", True):
        sets.append(string.ascii_uppercase)
    if opts.get("digits", True):
        sets.append(string.digits)
    if opts.get("symbols", True):
        sets.append(SYMBOLS)
    if not sets:
        sets = [string.ascii_lowercase]
    if not opts.get("ambiguous", False):
        sets = ["".join(c for c in s if c not in AMBIGUOUS) for s in sets]
    pool = "".join(sets)
    # one of every kind asked for, then the rest from all, then shuffled —
    # rejection, not a fix-up, so every password is equally likely
    while True:
        v = "".join(secrets.choice(pool) for _ in range(n))
        if n < len(sets) or all(any(c in s for c in v) for s in sets):
            break
    return {"value": v, "bits": round(n * math.log2(len(pool)), 1)}


COMMON = {"password", "123456", "qwerty", "letmein", "welcome", "admin", "iloveyou",
          "monkey", "dragon", "football", "baseball", "abc123", "111111", "sunshine",
          "master", "shadow", "princess", "trustno1", "passw0rd", "login", "starwars"}


def strength(text):
    """A plain estimate: the size of the alphabet used, raised to the length,
    less what common shapes give away (repeats, runs, a known password,
    a word with a number on it)."""
    t = str(text or "")
    if not t:
        return {"bits": 0, "score": 0, "word": "empty"}
    pool = 0
    if re.search(r"[a-z]", t):
        pool += 26
    if re.search(r"[A-Z]", t):
        pool += 26
    if re.search(r"[0-9]", t):
        pool += 10
    if re.search(r"[^A-Za-z0-9]", t):
        pool += 33
    length = len(t)
    # a character the same as the last, or one step on from it, adds little
    for i in range(1, len(t)):
        if t[i] == t[i - 1] or abs(ord(t[i]) - ord(t[i - 1])) == 1:
            length -= 0.6
    bits = max(0.0, length) * math.log2(max(pool, 2))
    low = t.lower()
    if low in COMMON or re.sub(r"[0-9!@#$.]+$", "", low) in COMMON:
        bits = min(bits, 10)
    if re.fullmatch(r"[A-Za-z]+[0-9]{1,4}[!@#$.]?", t):
        bits = min(bits, 30)
    # words joined by a separator: counted as words, if that says more
    parts = [p for p in re.split(r"[-_. ]", t) if p]
    if len(parts) >= 3 and all(p.isalpha() for p in parts):
        bits = max(bits, len(parts) * 12.0)
    score = 0 if bits < 28 else 1 if bits < 40 else 2 if bits < 60 else 3 if bits < 80 else 4
    return {"bits": round(bits, 1), "score": score,
            "word": ["very weak", "weak", "fair", "strong", "very strong"][score]}
