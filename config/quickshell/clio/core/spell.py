# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# SPELLING — hunspell, kept running in its pipe mode (`hunspell -a`, the ispell
# protocol), one process for the languages asked for. A line of words in, one
# answer per word out and a blank line after: `*` `+` `-` right, `& word n at:
# a, b` wrong with suggestions, `# word at` wrong with none. Every line sent is
# prefixed `^` so a word that starts with one of the protocol's command
# characters is read as a word.
#
# The answers are remembered per language set: a note is checked again on every
# pause in typing, and nearly all of its words were asked about already.

import glob
import os
import subprocess
import threading

DIRS = ["/usr/share/hunspell", "/usr/share/myspell/dicts", os.path.expanduser("~/.local/share/hunspell")]


def available():
    # every dictionary on this machine: [{ code, path }], a code once
    seen = {}
    for d in DIRS:
        for dic in sorted(glob.glob(os.path.join(d, "*.dic"))):
            code = os.path.basename(dic)[:-4]
            if code.startswith("hyph_") or code in seen:
                continue
            if os.path.exists(dic[:-4] + ".aff"):
                seen[code] = dic[:-4]
    return [{"code": c, "path": p} for c, p in seen.items()]


def default_langs():
    have = {d["code"] for d in available()}
    lang = (os.environ.get("LANG") or "en_US").split(".")[0]
    if lang in have:
        return [lang]
    for c in sorted(have):
        if c.split("_")[0] == lang.split("_")[0] and "-" not in c:
            return [c]
    return sorted(have)[:1]


class Speller:
    def __init__(self):
        self.lock = threading.Lock()
        self.proc = None
        self.langs = None
        self.cache = {}

    def _start(self, langs):
        self.stop()
        paths = {d["code"]: d["path"] for d in available()}
        use = [paths[c] for c in langs if c in paths]
        if not use:
            raise RuntimeError("no dictionary")
        self.proc = subprocess.Popen(["hunspell", "-a", "-i", "utf-8", "-d", ",".join(use)],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True, encoding="utf-8", bufsize=1)
        self.proc.stdout.readline()          # the banner
        self.langs = list(langs)
        self.cache = {}

    def stop(self):
        if self.proc:
            try:
                self.proc.kill()
            except OSError:
                pass
        self.proc = None

    def _ask(self, word):
        self.proc.stdin.write("^" + word + "\n")
        self.proc.stdin.flush()
        sugs = None
        while True:
            line = self.proc.stdout.readline()
            if line == "":
                raise RuntimeError("hunspell stopped")
            line = line.rstrip("\n")
            if line == "":
                break
            if line[0] == "&":
                head, _, tail = line.partition(": ")
                sugs = [s.strip() for s in tail.split(",") if s.strip()][:8]
            elif line[0] == "#":
                sugs = []
        return sugs

    def check(self, words, langs):
        # {word: [suggestions]} for the words that are wrong
        langs = list(langs or []) or default_langs()
        with self.lock:
            if self.proc is None or self.proc.poll() is not None or self.langs != langs:
                self._start(langs)
            bad = {}
            for w in words:
                w = str(w)
                if not w or len(w) > 60 or " " in w:
                    continue
                if w not in self.cache:
                    self.cache[w] = self._ask(w)
                if self.cache[w] is not None:
                    bad[w] = self.cache[w]
            return bad
