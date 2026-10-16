#!/usr/bin/env python3
"""
complete_mirror.py — Fill the gap HTTrack (and any non-JS crawler) leaves behind.

WHY THIS EXISTS
---------------
HTTrack / wget / wget2 copy HTML + CSS + JS, but they do NOT execute JavaScript.
Modern WebGL / SPA sites build asset URLs at runtime from data that lives inside
the JS bundle, e.g.:

    fetch(`assets/logos/companies/${company.logo}.webp`)
    loader.load(`assets/origami/${names[i]}.glb`)
    video.src = `assets/videos/${card.video}`

Those files are only requested after user interaction, so a static crawler never
sees them and the corresponding section of the mirror renders blank/broken.

WHAT THIS TOOL DOES
-------------------
1. STATIC PASS   — regex-extracts every literal `assets/...ext` path from the JS
                   bundle(s) and downloads any that are missing.
2. TEMPLATE PASS — finds dynamic templates  PREFIX/${...}.EXT  and probe-downloads
                   candidate tokens (array literals, object fields, generic pool),
                   keeping HTTP 200s.
3. ABSOLUTE PASS — captures absolute asset URLs (https://host/...ext) that point at
                   the base origin or any --cdn host, and downloads them preserving
                   a <host>/<path> layout.

It preserves the on-disk path layout so the result is served as-is from a static
server (serve.py) with no rewriting.

USAGE
-----
    python3 complete_mirror.py --mirror DIR --base https://site \
        [--cdn cdn.site.com ...] [--ext avif mp3 ...] \
        [--js assets/main.js ...] [--dry-run] [--jobs 8]

For interaction-gated sites where even probing misses assets, use the companion
capture_playwright.js which drives the real page and dumps every network response.
"""
import argparse, concurrent.futures as cf, os, re, sys, urllib.request, urllib.error

DEFAULT_EXTS = ("webp avif glb png jpg jpeg gif svg otf ttf woff woff2 mp4 webm mov "
                "mp3 wav ogg json hdr exr ktx2 basis gltf bin wasm draco").split()

# a plausible asset FILENAME token: starts alnum, only filename-safe chars, has a letter
RE_SAFE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_.\-]{0,60}$')


def build_res(exts):
    alt = "|".join(exts)
    static = re.compile(r'(?:assets|vendor|static|media|public|dist|build)/[A-Za-z0-9_./-]+\.(?:%s)' % alt)
    template = re.compile(
        r'((?:assets|vendor|static|media|public|dist|build)/[A-Za-z0-9_./-]*)'
        r'\$\{([^}]*)\}([A-Za-z0-9_./-]*\.(?:%s))' % alt)
    absurl = re.compile(r'(https?)://([A-Za-z0-9.\-]+(?::\d+)?)(/[A-Za-z0-9_./-]+\.(?:%s))' % alt)
    return static, template, absurl


def safe(tok):
    tok = tok.strip()
    return bool(tok) and "/" not in tok and RE_SAFE.match(tok) and re.search(r'[A-Za-z]', tok) \
        and tok.count(".") <= 1 and not re.match(r'^[0-9.]+(px|deg|em|rem|s|ms|vh|vw)?$', tok)


def values_of_field(blob, field):
    """Collect object-field values:  logo:`google`  video:"x.mp4"  name:'y'."""
    out = set()
    for q in ("`", '"', "'"):
        out |= set(re.findall(r'%s:\s*%s([^%s]+)%s' % (re.escape(field), q, q, q), blob))
    return {v for v in out if safe(v)}


def values_of_array(blob, name):
    """Collect string elements of an array literal:  NAME=[`a`,`b`,...]."""
    out = set()
    for m in re.finditer(r'\b%s\s*=\s*\[([^\]]*)\]' % re.escape(name), blob):
        out |= set(re.findall(r'[`"\']([^`"\']+)[`"\']', m.group(1)))
    return {v for v in out if safe(v)}


def log(*a): print(*a, file=sys.stderr, flush=True)


def discover_js(mirror):
    found = []
    for root, _, files in os.walk(mirror):
        for f in files:
            if f.endswith(".js") or f.endswith(".mjs"):
                found.append(os.path.join(root, f))
    return found


def fetch(url, dest, dry):
    if os.path.exists(dest):
        return ("skip", dest)
    if dry:
        return ("would", url)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 mirror-completer"})
        with urllib.request.urlopen(req, timeout=30) as r:
            if getattr(r, "status", 200) != 200:
                return ("miss", url)
            data = r.read()
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        with open(dest, "wb") as fh:
            fh.write(data)
        return ("got", url)
    except urllib.error.HTTPError as e:
        return ("http:%s" % e.code, url)
    except Exception as e:  # noqa
        return ("err:%s" % type(e).__name__, url)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mirror", required=True)
    ap.add_argument("--base", required=True, help="origin, e.g. https://site.com")
    ap.add_argument("--cdn", action="append", default=[], help="extra host to also fetch from (repeatable)")
    ap.add_argument("--ext", nargs="*", default=None, help="extra file extensions to recover")
    ap.add_argument("--js", nargs="*", default=None)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--jobs", type=int, default=8)
    args = ap.parse_args()

    exts = list(DEFAULT_EXTS) + (args.ext or [])
    RE_STATIC, RE_TEMPLATE, RE_ABS = build_res(exts)
    EXT_ALT = "|".join(exts)

    base = args.base.rstrip("/")
    base_host = re.sub(r'^https?://', '', base).split("/")[0]
    allowed_hosts = set([base_host] + [h.replace("https://", "").replace("http://", "").strip("/") for h in args.cdn])

    js_files = args.js and [os.path.join(args.mirror, j) if not os.path.isabs(j) else j for j in args.js]
    js_files = js_files or discover_js(args.mirror)
    # also scan the mirror's HTML/CSS for literal asset refs
    extra_text = []
    for root, _, files in os.walk(args.mirror):
        for f in files:
            if f.endswith((".html", ".htm", ".css")):
                extra_text.append(os.path.join(root, f))
    if not js_files and not extra_text:
        log("No JS/HTML/CSS found under", args.mirror); sys.exit(1)
    log("Scanning %d JS + %d HTML/CSS file(s); hosts: %s" % (len(js_files), len(extra_text), ", ".join(sorted(allowed_hosts))))

    blob = ""
    for j in (js_files + extra_text):
        try:
            blob += open(j, encoding="utf-8", errors="replace").read() + "\n"
        except Exception as e:
            log("  (skip %s: %s)" % (j, e))

    static = set(RE_STATIC.findall(blob))
    templates = set(RE_TEMPLATE.findall(blob))
    absolutes = set(RE_ABS.findall(blob))  # (host, /path.ext)

    generic = set()
    for field in set(re.findall(r'([A-Za-z_$][A-Za-z0-9_$]*)\s*:\s*[`"\']', blob)):
        generic |= values_of_field(blob, field)

    # (url, dest) jobs. Same-origin relative paths -> base + rel, dest under mirror.
    jobs = {}
    def add_rel(rel):
        rel = rel.lstrip("/")
        jobs[base + "/" + rel] = os.path.join(args.mirror, rel)

    for rel in static:
        add_rel(rel)
    for prefix, expr, suffix in templates:
        m = re.search(r'\.(%s)$' % EXT_ALT, suffix)
        ext = "." + m.group(1)
        mid = suffix[:-len(ext)]
        vals = set()
        fm = re.search(r'\.([A-Za-z_$][A-Za-z0-9_$]*)\b', expr)
        am = re.search(r'\b([A-Za-z_$][A-Za-z0-9_$]*)\s*\[', expr)
        if fm:
            vals |= values_of_field(blob, fm.group(1))
        if am:
            vals |= values_of_array(blob, am.group(1))
        if not vals:
            vals = {v for v in generic if safe(v)}
        for tok in vals:
            add_rel("%s%s%s%s" % (prefix, tok, mid, ext))
    # absolute URLs on allowed hosts -> preserve scheme, lay out <host>/<path>
    abs_added = 0
    for scheme, host, path in absolutes:
        if host in allowed_hosts:
            url = scheme + "://" + host + path
            if host == base_host:
                jobs[url] = os.path.join(args.mirror, path.lstrip("/"))
            else:
                jobs[url] = os.path.join(args.mirror, host, path.lstrip("/"))
            abs_added += 1

    log("Static: %d | templates: %d | absolute(on-host): %d | generic pool: %d | total jobs: %d"
        % (len(static), len(templates), abs_added, len(generic), len(jobs)))

    counts = {}
    items = sorted(jobs.items())
    with cf.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        for status, what in ex.map(lambda kv: fetch(kv[0], kv[1], args.dry_run), items):
            k = status.split(":")[0]
            counts[k] = counts.get(k, 0) + 1
            if status in ("got", "would"):
                log("  [%s] %s" % (status, what))

    log("\nSummary:", ", ".join("%s=%d" % kv for kv in sorted(counts.items())) or "(nothing to do)")


if __name__ == "__main__":
    main()
