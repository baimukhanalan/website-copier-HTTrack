# Modern-site pitfalls + tool landscape

## Pitfalls that make a mirror render blank/broken (and fixes)

| Symptom | Cause | Fix |
|---|---|---|
| Blank page, stale content on reload | archived **service worker** (`sw.js`) intercepts `fetch` and serves from a Cache Storage that doesn't exist locally | delete `sw.js` from the mirror, or strip `navigator.serviceWorker.register(...)` from the HTML/bundle before serving |
| Relative URLs jump back to the live site | leftover `<base href="https://origin">` tag | remove/rewrite the `<base>` tag after capture |
| Modified/recompressed asset refuses to load | `integrity="sha384-…"` SRI on `<script>`/`<link>` | strip `integrity` (and `crossorigin`) attributes for any asset you edited |
| Section blank; whole scene missing | runtime-built asset URLs HTTrack never saw | `complete_mirror.py` then `capture_playwright.js` (steps 3–4) |
| Fonts/textures fail in console (CORS) | static server lacks `Access-Control-Allow-Origin` | serve via `scripts/serve.py` (adds `*`), or self-host fonts same-origin |
| Deep link `/about` 404s | SPA client-side route, no file on disk | `scripts/serve.py --spa` (falls back to `index.html`) |
| Duplicate files `foo.js?v=1`, `foo.js?v=2` | `?v=` cache-busting query strings | HTTrack `%q0` + path template + `-*?*` reject filters, or post-strip queries |
| CDN/cross-origin assets missing | HTTrack stays on the start domain | `-n`, raise `--ext-depth`, add `+cdn.host.com/*` / `+*.woff2` filters, or add the CDN as an extra seed |
| Still hitting the internet on replay | protocol-relative `//host/…` / absolute URLs `-K0` missed | grep the mirror for the original origin and rewrite the stragglers |

Post-crawl verification:
```bash
grep -rl 'https://ORIGINAL-ORIGIN' . 2>/dev/null   # any file still pointing live?
```

## Serving (never `file://`)
`file://` blocks ES modules, `fetch`, workers, and WASM (opaque origin). Use the
bundled server, which fixes MIME + CORS + SPA routes:
```bash
python3 scripts/serve.py 8899 --dir /abs/out/dir/SITE --spa
```
`python3 -m http.server` sends `application/octet-stream` for `.wasm`/`.mjs`
(browsers refuse module + `instantiateStreaming`) and has no CORS — avoid it for
WebGL/SPA. `npx serve -s` is an acceptable alternative (maps modules + SPA
fallback). COOP/COEP headers are only needed for SharedArrayBuffer/threaded WASM.

## Tool landscape — when something beats HTTrack
| Tool | Beats HTTrack at | Can't |
|---|---|---|
| **HTTrack / wget2** (+ this skill's extractors) | static design clone you'll edit & re-host; wget2 is faster (HTTP/2) | neither executes JS → blank JS-built sections |
| **monolith** | one page → a single self-contained `.html` (assets inlined as data: URIs) | no JS exec, no crawl, single page |
| **SingleFile / SingleFileZ** | saves the **rendered DOM after JS runs** → plain HTML of an SPA page | per-page; misses assets gated behind later interaction unless scripted |
| **Browsertrix Crawler** | **highest-fidelity** JS/SPA/lazy-asset capture (real Chromium, behaviors) → WACZ | output is WACZ/WARC needing a replayer (ReplayWeb.page/pywb), not editable files |
| **ArchiveBox** | durable multi-format archive + index (SingleFile, WARC, screenshot, PDF) | not a browseable re-hostable static design clone |
| **grab-site** | large polite crawls with fine ignore patterns → WARC | WARC output, no JS rendering |
| **Playwright/Puppeteer** (this skill's `capture_playwright.js`) | interaction-gated/WebGL: drive gestures, hook network, dump assets | you own the save/rewrite logic; brittle per-site scripting |

Rule of thumb: **editable static clone** → HTTrack/wget2 + extractors · **faithful
replay of a JS app** → Browsertrix (WACZ) · **one rendered page** → SingleFile ·
**one portable file** → monolith · **interaction-gated WebGL** → Playwright capture.
