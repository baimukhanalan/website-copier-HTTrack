---
name: httrack-site-mirror
description: >-
  Mirror a public website to a local, path-preserving copy with HTTrack, then
  complete it for modern JS/WebGL/SPA sites that HTTrack alone renders blank.
  Use when the user wants to "mirror", "clone", "copy", "download", "archive",
  or "save a full copy of" a site — especially heavy Three.js/React/canvas or
  interaction-gated sites — or to extract a site's copy/strings and assets for
  analysis or a rebrand. One command (`scripts/grab.sh`) runs the whole pipeline.
  Covers HTTrack flags, macOS quirks (no `timeout`), recovering runtime-loaded
  and CDN assets, extracting text from minified bundles, and serving the result
  with correct MIME/CORS/SPA. Analysis/personal-copy only — not 1:1 re-hosting
  of someone else's branding.
---

# HTTrack site mirror (+ SPA completer)

Mirror a site to a local file tree you can read, grep, serve, and adapt.
HTTrack grabs HTML/CSS/JS and statically-linked assets. Modern JS-rendered sites
need two extra passes — this skill bundles both, behind one command.

## One command
```bash
scripts/grab.sh https://SITE --serve            # mirror -> complete -> serve
scripts/grab.sh https://SITE --capture --serve  # + drive the real page for gated assets
```
`grab.sh` runs: HTTrack mirror → `complete_mirror.py` (recover JS-built + CDN
assets) → optional Playwright capture → optional `serve.py`. See `--help`.

## When to use / not use
- **Use** for: snapshotting a landing page, pulling a site's copy + assets,
  studying/adapting a design, offline archive.
- **Heavy SPA / WebGL (Three.js, R3F, canvas)**: HTTrack copies the shell but
  interactive scenes render **blank** — the completer passes fix that. This is a
  fundamental limit of every non-JS crawler, not a flag mistake.
- **Don't** re-host someone else's branding 1:1. See **Guardrails**.

## Prerequisites
- `httrack` — `brew install httrack` / `apt install httrack` (verified 3.50-2).
- Python 3 (stdlib only) for the completer and the server.
- Node + Playwright only for `--capture`:
  `npm i -D playwright && npx playwright install chromium`.

## Steps (what grab.sh does, if you run them by hand)
1. **Mirror** — `scripts/mirror.sh https://SITE ./out`
   Flags: `-n --depth=3 --ext-depth=1 -c4 --disable-security-limits`. By default
   **pages stay on the start host, assets come from any host** (scope filter) so a
   stray external link can't trigger a runaway crawl; `--wide` disables it.
   **macOS has NO `timeout`** — bound a run with `--max-time` (HTTrack's own `-E`),
   never shell `timeout`.
2. **Sanity check** — a lone giant `main-*.js` + a `<canvas>` and almost no HTML
   text ⇒ it's a JS/WebGL SPA ⇒ do steps 3–4. (See `reference/clean-build.md` to
   strip HTTrack cruft like `hts-cache/`.)
3. **Recover runtime assets** — `scripts/complete_mirror.py --mirror ./out/SITE
   --base https://SITE [--cdn cdn.host ...]`. Parses the bundle for literal paths,
   `${...}` templates, and absolute/CDN URLs; probe-downloads, keeps 200s.
4. **Capture gated assets** (only if a scene is still blank) —
   `scripts/capture_playwright.js https://SITE ./out/SITE`. Drives headless
   Chromium, hooks the network below JS, writes every response. **Tune `drive()`**
   per site (gesture, tap-hold, scroll N stages); env: `CAP_SCROLLS`, `CAP_WAIT`.
5. **Serve (never `file://`)** — `scripts/serve.py 8899 --dir ./out/SITE --spa`.
   Fixes MIME for `.wasm/.mjs/.glb/.ktx2` + CORS + SPA routes; `python3 -m
   http.server` is NOT enough. `--coep` for SharedArrayBuffer/threaded WASM.

## Extract the site's copy / strings
```bash
scripts/extract_copy.sh ./out/SITE/assets/main-*.js
```
Canvas sites bake text into the bundle; this surfaces human copy (source map →
beautify → grep), filtering shader/minified noise. See `reference/extract-copy.md`.

## Guardrails (state when relevant)
- Mirror only sites you're allowed to copy; honor robots.txt (default) — `--ignore-robots`
  only for sites you own. Keep connections low; `--rate` to throttle.
- Capture for **analysis / study / personal offline copy**. Do **not** republish
  someone else's branding, logos, licensed fonts, or copyrighted content 1:1 —
  adapt the technique, ship original assets/copy.

## Files
- `scripts/grab.sh` — one-command pipeline (mirror → complete → capture → serve).
- `scripts/mirror.sh` — HTTrack wrapper (scoped, macOS-safe, cross-platform).
- `scripts/complete_mirror.py` — recover JS-built + CDN assets (stdlib only).
- `scripts/capture_playwright.js` — headless ground-truth capture (tune `drive()`).
- `scripts/extract_copy.sh` — pull readable copy from a minified bundle.
- `scripts/serve.py` — correct static server (MIME + CORS + SPA + optional COEP).
- `reference/*.md` — HTTrack flags, clean build, copy extraction, SPA pitfalls + tool landscape.
- `tests/run.sh` — e2e + unit test harness (`make test`).
