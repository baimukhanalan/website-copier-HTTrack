# HTTrack flag cheat-sheet

Only the flags that matter in practice. Full list: `httrack --help` / `man httrack`.

## Core (used by mirror.sh)
| Flag | Purpose |
|---|---|
| `-O <dir>` | output directory (mirror lands in `<dir>/<host>/`) |
| `-n` | get "near" files — images/CSS referenced by a page even if off-rule |
| `--depth=N` | page-recursion depth from the seed URL |
| `--ext-depth=N` | how deep to follow links that leave the start domain |
| `-c N` | simultaneous connections (keep low; `-c4` is polite-ish) |
| `--disable-security-limits` | lift HTTrack's built-in rate/size caps — you take responsibility for load |
| `-q` / `-%v` | quiet / verbose live progress |
| `-E <seconds>` | **max mirror time** — the macOS-safe way to bound a run (NOT shell `timeout`) |

## Politeness / correctness
| Flag | Purpose |
|---|---|
| `-s0` | ignore robots.txt (ONLY if you own/are permitted the site; default honors it) |
| `-%P` | extended parsing — catch URLs in more JS/CSS contexts (still no JS execution) |
| `-F "<ua>"` | set User-Agent string |
| `-A <bytes/s>` | max transfer rate — throttle to be gentle |
| `-%c <N>` | max connections/second |
| `-mN` | max file size (bytes); pair with `--disable-security-limits` |

## Scope filters (`+`/`-` rules, quote them)
| Rule | Purpose |
|---|---|
| `-* +SITE/*` | mirror only this host, nothing off-site |
| `+*.css +*.js +*.woff2` | force-include asset types even if off-domain |
| `-*.html?*` | drop URL-query duplicate pages (`page.html?v=2`) |
| `+*cdn.example.com/*` | widen scope to a known asset CDN |
| `-*logout* -*?share=*` | skip destructive/duplicate links |

## Updating / resuming an existing mirror (don't re-download everything)
```bash
httrack --update   -O /abs/out/dir   # re-run in same dir; fetch only changed files (=-iC2)
httrack --continue -O /abs/out/dir   # finish an incomplete mirror (=-iC1)
httrack -i         -O /abs/out/dir   # resume an interrupted crawl from hts-cache/
```
HTTrack stores state in `<dir>/hts-cache/`; **keep it** to enable
update/continue/resume, delete it only for a clean deployable copy.

## Query-string de-duplication (`?v=` cache-busters)
| Flag | Purpose |
|---|---|
| `%q` (default) | append a short hash of the query string to the filename |
| `%q0` | **disable** query-hash in filenames — collapse `foo.js?v=1` & `?v=2` into one |
| `-N "%h%p/%n.%t"` | custom local path template (drop the query component) |

Combine `%q0` + a path template + `-*?*`-style reject filters to stop `?v=`
duplicates. Also useful: `-%L <seeds.txt>` (seed URLs from a file, one per line),
`-%S <rules.txt>` (big filter list from a file), `-p0` (scan without saving = dry
run), `-t` (HEAD-only test that links exist).

## Pitfalls
- `--disable-security-limits` without `-A`/`-c` can hammer a host — always pair
  with low connections and, ideally, a rate cap.
- HTTrack rewrites links for offline use by default; if you plan to re-serve on a
  real host, you may want the original absolute paths — verify before deploying.
