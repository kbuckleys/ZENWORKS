// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// DIRECTORY COVERS, REMEMBERED — see FolderCover.qml.
//
// A library, so there is ONE of these for the whole shell: terminus' grid and
// picasso's gallery look at the same directories, and a cover worked out by one is
// the other's for free. Keyed by path and the directory's mtime, so a picture
// added or removed is a new key and the old answer is simply never asked for.
.pragma library

// "path|mtime" -> [file urls], [] for a directory with no pictures in it.
var cache = ({});

// The scans out right now, as leases: token -> when it was taken. A grid of
// forty directories arriving at once is forty finds and up to a hundred and sixty
// thumbnails; a cover waits its turn rather than all of them landing on the
// disk together.
//
// LEASES, NOT A COUNTER. A counter was decremented by the cover when its scan
// finished — and a live reload tears covers down mid-scan without that ever
// running. This library outlives the reload, so every interrupted scan left
// the counter one higher, and after a few reloads it sat at the limit for
// good: no cover anywhere would start, and every directory fell back to its
// glyph. A lease that nobody returns simply expires.
var leases = ({});
var MAX_BUSY = 3;
var LEASE_MS = 20000;
var nextToken = 1;

function take() {
  const now = Date.now();
  let n = 0;
  for (const k in leases) {
    if (now - leases[k] > LEASE_MS) delete leases[k];
    else ++n;
  }
  if (n >= MAX_BUSY) return 0;
  const t = nextToken++;
  leases[t] = now;
  return t;
}

function give(token) { if (token) delete leases[token]; }

// The pictures a cover is made of: the first four by name, which is the order
// the directory itself shows them in, so the cover is a preview of what opening
// it will look like. Hidden files are left out, as the listing leaves them.
var EXTS = ["jpg", "jpeg", "jpe", "png", "webp", "gif", "bmp", "avif", "jxl",
            "heic", "tif", "tiff"];

function scanCommand(dir, quote) {
  const names = EXTS.map((e) => "-iname '*." + e + "'").join(" -o ");
  return "find -L " + quote(dir) + " -mindepth 1 -maxdepth 1 -type f ! -name '.*' \\( "
    + names + " \\) -print0 2>/dev/null | sort -z | head -z -n 4 | tr '\\0' '\\n'";
}
