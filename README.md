<div align="center">

# 🕸️ website-copier-HTTrack

### Copy *any* website to your laptop — **including the ones HTTrack leaves blank.**

Modern sites are 3D, animated, interactive. Classic mirrors (`httrack`, `wget`)
copy the HTML and quit — the Three.js scenes, the lazy-loaded models, the
fonts from a CDN all come back **empty**. This fixes that, in **one command.**

```bash
scripts/grab.sh https://example.com --serve
```

`mirror → recover JS-built assets → (optionally) drive the real page → serve it right`

**macOS + Linux · pure stdlib core · no account, no cloud, 25 passing tests.**

</div>

---

## Why this exists

HTTrack is brilliant — but it **doesn't run JavaScript.** A modern WebGL/SPA site
builds its asset URLs *at runtime*:

```js
fetch(`assets/logos/${company.logo}.webp`)   // ← HTTrack never sees these
loader.load(`assets/models/${name}.glb`)     //   so the whole scene is blank
```

Those files load only after a scroll or a click, so a static crawler records
**none** of them. You get the skeleton and a broken, empty page. Every non-JS
tool (`wget2`, `monolith`, `SingleFile`) fails the same way.

**website-copier-HTTrack** closes the gap with three automatic passes on top of
HTTrack, then serves the result the way a real browser needs it.

## What you get

| | |
|---|---|
| 🧩 **Recovers runtime assets** | Parses the JS bundle for literal paths, `${...}` templates (arrays + object fields), and absolute/CDN URLs — then downloads what HTTrack missed. |
| 🎭 **Drives the real page** | Optional headless-Chromium capture hooks the network *below* JavaScript and performs the site's gestures/scrolls, grabbing truly interaction-gated files. |
| 🚦 **Won't run away** | Pages stay on the start host; assets come from anywhere. A stray footer link can't drag you into crawling half the internet. |
| 🍎 **macOS-safe** | No reliance on `timeout` (absent on macOS) — bound a run with HTTrack's own `--max-time`. |
| 🧰 **Serves it correctly** | A drop-in server with the right MIME for `.wasm/.mjs/.glb/.ktx2`, CORS, and SPA-route fallback. `python3 -m http.server` silently breaks all of these. |
| ✍️ **Extracts the copy** | Canvas sites bake their text into the bundle — pull the real headlines/CTAs out for analysis or a rebrand. |
| ✅ **Actually tested** | 25 end-to-end + unit tests (`make test`), real downloads against a local origin, no mocks. |

## Quick start

```bash
# 1. install httrack (the only hard dependency besides python3)
brew install httrack            # macOS
sudo apt install httrack        # Debian/Ubuntu

# 2. clone + make the scripts runnable
git clone https://github.com/baimukhanalan/website-copier-HTTrack.git
cd website-copier-HTTrack && ./install.sh

# 3. copy a site and open it locally
scripts/grab.sh https://your-target.com --serve
#   → http://localhost:8899/
```

That's it. For a heavy interactive site, add `--capture` (needs Node + Playwright)
to drive the real page and vacuum up the gated assets:

```bash
npm i -D playwright && npx playwright install chromium
scripts/grab.sh https://your-target.com --capture --serve
```

## How it works

```
  grab.sh
    │
    ├─ 1. httrack ............ HTML + CSS + JS + statically-linked assets
    │                          (scoped: pages on-host, assets from anywhere)
    ├─ 2. complete_mirror.py . recover runtime/CDN assets from the JS bundle
    │                          (static paths · ${templates} · absolute URLs)
    ├─ 3. capture_playwright . [optional] drive the real page, hook the network,
    │                          save every response — immune to URL templating
    └─ 4. serve.py ........... correct MIME + CORS + SPA fallback, over http://
```

Each tool also stands alone — use only the pass you need.

## Commands

| Command | What it does |
|---|---|
| `scripts/grab.sh <url> [--serve] [--capture] [--wide] [--cdn host]` | the whole pipeline, one line |
| `scripts/mirror.sh <url> <out> [--max-time N] [--rate B]` | just the scoped HTTrack mirror |
| `scripts/complete_mirror.py --mirror DIR --base URL [--cdn host]` | recover JS-built + CDN assets |
| `scripts/capture_playwright.js <url> <out>` | ground-truth capture (tune via `CAP_*` env) |
| `scripts/serve.py <port> --dir DIR --spa [--coep]` | serve a mirror the way browsers need |
| `scripts/extract_copy.sh <bundle.js>` | pull the real on-screen copy from a minified bundle |

Run any with `--help`. Full flag notes live in [`reference/`](reference/).

## Example

```bash
$ scripts/grab.sh https://example.com --out ./mirror --serve
>> URL=https://example.com  OUT=./mirror  depth=3 ext=1 conn=4 robots=honor
>> httrack ... -* +example.com/* +*.css +*.js +*.glb ...
>> complete_mirror.py (recovering JS-built assets)
   Static: 3 | templates: 2 | absolute(on-host): 1 | total jobs: 6
   [got] assets/models/profile.glb
>> done: 14 files in ./mirror/example.com
>> serving ./mirror/example.com at http://localhost:8899/
```

## When something else is the better tool

Honest guidance — this repo tells you when to walk away:

| You want… | Use |
|---|---|
| An **editable, re-hostable** static clone of a design | **this repo** (HTTrack + completers) |
| A **faithful replay** of a complex web app | [Browsertrix Crawler](https://github.com/webrecorder/browsertrix-crawler) → WACZ |
| **One** fully-rendered page as plain HTML | [SingleFile](https://github.com/gildas-lormeau/SingleFile) |
| **One** page as a single portable file | [monolith](https://github.com/Y2Z/monolith) |

## Install as a Claude Code skill (optional)

This repo doubles as a [Claude Code](https://claude.com/claude-code) skill — clone
it into your skills folder and Claude can mirror sites for you:

```bash
./install.sh --skill     # symlinks into ~/.claude/skills/httrack-site-mirror
```

## Tests

```bash
make test        # 25 e2e + unit tests, real downloads, exits non-zero on failure
make lint        # syntax-check every script
```

## Requirements

- **Required:** `httrack`, `python3` (standard library only — nothing to `pip install`).
- **Optional:** `node` + `playwright` for `--capture`; `js-beautify` for nicer copy extraction.

## Please mirror responsibly

This tool is for **analysis, study, and personal/offline copies.** It honors
`robots.txt` by default and keeps requests gentle. Do **not** republish someone
else's branding, logos, licensed fonts, or copyrighted content 1:1 as if it were
your own — learn from the technique and ship original work. You are responsible
for respecting each site's Terms of Service and the law where you live.

## License

[MIT](LICENSE) © baimukhanalan
