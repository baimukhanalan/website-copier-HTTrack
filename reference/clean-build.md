# Strip HTTrack cruft for a deployable copy

HTTrack leaves bookkeeping files that must NOT ship in a clean mirror/deploy:

```
hts-cache/            # crawl state (keep ONLY if you want --update/--continue)
hts-log.txt           # crawl log
backblue.gif fade.gif # HTTrack's own UI gifs injected into index stubs
cookies.txt
*.orig / *.bak        # if you kept pristine backups while editing
index.html            # HTTrack's TOP-LEVEL stub listing mirrors (the real page
                      #   is under <out>/<host>/index.html — don't confuse them)
```

## Make a clean copy (rsync, excludes cruft)
```bash
SRC=/abs/out/dir/SITE
DST=/abs/deploy
rsync -a --delete \
  --exclude 'hts-cache/' --exclude 'hts-log.txt' \
  --exclude 'backblue.gif' --exclude 'fade.gif' --exclude 'cookies.txt' \
  --exclude '*.orig' --exclude '*.bak' \
  "$SRC/" "$DST/"
```

## Keep pristine backups BEFORE editing a mirror you'll rebrand
When you plan to edit the bundle/HTML in place, snapshot first:
```bash
cp assets/main-*.js  assets/main.js.orig
cp index.html        index.html.orig
```
So edits are re-derivable and you can diff against the original.

## Cache-busting on redeploy
If the HTML references assets as `...?v=<timestamp>`, bump it every deploy so
browsers don't serve a stale bundle:
```bash
V=$(date +%s); sed -E -i '' "s#\?v=[0-9]+#?v=$V#g" index.html assets/*.js
```
(`-i ''` is the macOS/BSD `sed` in-place form; GNU sed uses `-i`.)
Set `Cache-Control: no-store` on the HTML at the host for good measure.
