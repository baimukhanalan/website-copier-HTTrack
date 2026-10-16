# Extracting copy, text, and assets from a mirror

## Where the text lives
- **Classic sites**: in the HTML — `get_page_text` / grep the `.html` files.
- **Canvas/WebGL sites**: on-screen text is **baked into the JS bundle** as
  string literals, OR rendered from a **texture atlas** (`.ktx2`/`.basis`/`.png`)
  where the words are pixels, not strings. Check both.

## 1. Strings from the bundle (fastest)
```bash
scripts/extract_copy.sh assets/main-*.js            # filtered prose
strings -n 8 assets/main-*.js | grep -iE 'your|the|free' # raw fallback
```
If a **source map** is referenced (`//# sourceMappingURL=main.js.map`), fetch it
— it reconstructs original variable names and strings far more cleanly than
grepping minified code:
```bash
curl -s https://SITE/assets/main-*.js.map -o main.js.map   # if served
```

## 2. Pretty-print to read structure
```bash
npx js-beautify assets/main-*.js -o /tmp/pretty.js   # splits packed one-liners
```
Then search `/tmp/pretty.js` for the data arrays that drive scenes
(`[{...},{...}]`), company lists, pricing, copy beats.

## 3. Text baked into a texture atlas (hard mode)
If words appear on screen but are NOT in the JS strings, they're in an image
atlas. To read/replace them:
```bash
# inspect a ktx2/basis atlas (install: brew install basis_universal)
basisu -unpack assets/atlases/texts.ktx2        # -> .png you can open
```
Editing then re-encoding an atlas is involved (decode -> edit pixels in PIL ->
`basisu -ktx2 -q 255` with matching ETC1S/level settings -> verify it still
transcodes). Only go here if string/HTML edits can't reach the text.

## 4. Assets inventory
```bash
find . -type f -not -path '*/hts-cache/*' | sed 's/.*\.//' | sort | uniq -c | sort -rn
```
Shows the file-type histogram (how many webp/glb/ktx2/mp4) — a quick read on how
asset-heavy and how "completed" the mirror is.

## 5. AST extraction (precise — skip keys/identifiers, keep user-facing text)
When grep is too noisy, parse the (beautified) bundle and pull only string
literals:
```bash
npx ast-grep --pattern '"$A"' pretty.js          # pattern-match string nodes
# or Babel: @babel/parser -> walk StringLiteral / TemplateLiteral nodes
```
Practical order of attack: **source map → beautify → AST/ast-grep →
`strings`/`grep`** as last resort.

## Caveat
Minified identifiers are not the original names; strings are reliable, logic flow
is not. For a faithful rebuild, prefer a source map or ground-truth runtime
capture (`capture_playwright.js`) over reverse-engineering minified control flow.
