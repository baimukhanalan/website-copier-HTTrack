#!/usr/bin/env node
/*
 * capture_playwright.js — ground-truth capture for interaction-gated SPA/WebGL sites.
 *
 * Drives the REAL page in headless Chromium and writes every same-origin network
 * response to disk at its URL path. Because it hooks the network layer BELOW
 * JavaScript, it captures assets no matter how their URLs are templated
 * (`${company}.webp`, `${name}.glb`, ...). Output is a plain, path-preserving
 * file tree you serve directly with serve.py.
 *
 * SETUP
 *   npm i -D playwright && npx playwright install chromium
 *
 * RUN
 *   node capture_playwright.js https://SITE ./mirror/SITE
 *
 * TUNE WITHOUT EDITING (env vars):
 *   CAP_SCROLLS=12     how many scroll/tap stages to step through   (default 8)
 *   CAP_WAIT=2500      ms to wait on each stage for lazy loads       (default 2000)
 *   CAP_GESTURE=circle draw-a-circle unlock gesture: circle|none     (default circle)
 *   CAP_W=1440 CAP_H=900   viewport                                  (default 1440x900)
 *   CAP_HOSTS=a.com,b.com  extra hosts to also save (besides origin)
 *   CAP_HEADFUL=1      show the browser window (debug)
 *
 * The default drive() is a generic "unlock + scroll through stages" recipe that
 * fits most scroll-driven sites. For an unusual gate, edit drive() directly.
 */
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const BASE = process.argv[2];
const OUT = process.argv[3] || "./mirror";
if (!BASE) { console.error("usage: node capture_playwright.js <url> [outDir]"); process.exit(1); }

const E = process.env;
const SCROLLS = parseInt(E.CAP_SCROLLS || "8", 10);
const WAIT = parseInt(E.CAP_WAIT || "2000", 10);
const GESTURE = E.CAP_GESTURE || "circle";
const VW = parseInt(E.CAP_W || "1440", 10);
const VH = parseInt(E.CAP_H || "900", 10);
const origin = new URL(BASE).hostname;
const hosts = new Set([origin, ...((E.CAP_HOSTS || "").split(",").map(s => s.trim()).filter(Boolean))]);

async function drive(page) {
  const W = page.viewportSize().width, H = page.viewportSize().height;
  const cx = W / 2, cy = H / 2;
  if (GESTURE === "circle") {
    // draw a circle ("zero"/unlock) gesture some gated intros require
    await page.mouse.move(cx, cy - H * 0.15);
    await page.mouse.down();
    for (let i = 1; i <= 90; i++) {
      const a = (i / 90) * Math.PI * 2;
      await page.mouse.move(cx + W * 0.18 * Math.sin(a), cy - H * 0.15 * Math.cos(a));
    }
    await page.mouse.up();
    await page.waitForTimeout(WAIT);
  }
  // tap-and-hold, then progress through stages (scroll + hold triggers lazy loads)
  for (let s = 0; s < SCROLLS; s++) {
    await page.mouse.move(cx, cy);
    await page.mouse.down(); await page.waitForTimeout(Math.min(WAIT, 2500)); await page.mouse.up();
    await page.mouse.wheel(0, 1200);
    await page.waitForTimeout(WAIT * 0.75);
  }
  await page.waitForTimeout(WAIT * 1.5);
}

(async () => {
  const browser = await chromium.launch({ headless: !E.CAP_HEADFUL });
  const page = await browser.newPage({ viewport: { width: VW, height: VH } });
  let saved = 0, seen = 0;
  page.on("response", async (res) => {
    try {
      const u = new URL(res.url());
      if (!hosts.has(u.hostname)) return;
      if (!res.ok()) return;
      seen++;
      let rel = decodeURIComponent(u.pathname).replace(/^\//, "") || "index.html";
      if (rel.endsWith("/")) rel += "index.html";
      // lay cross-origin hosts under <host>/..., keep origin at the root
      const base = u.hostname === origin ? OUT : path.join(OUT, u.hostname);
      const dest = path.join(base, rel);
      const body = await res.body();
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.writeFileSync(dest, body);
      saved++;
    } catch { /* streaming/opaque responses — ignore */ }
  });
  console.error(`Loading ${BASE}  (scrolls=${SCROLLS} wait=${WAIT} gesture=${GESTURE})`);
  try { await page.goto(BASE, { waitUntil: "networkidle", timeout: 60000 }); }
  catch (e) { console.error("goto warning:", e.message); }
  await drive(page);
  await browser.close();
  console.error(`Saw ${seen} responses, saved ${saved} files to ${OUT}`);
})();
