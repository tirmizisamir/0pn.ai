#!/usr/bin/env bash
# deploy.sh — commit, push, and (optionally) upload 0pn.ai to the web server.
#
#   ./deploy.sh "what changed"            # bump cache version, commit, push
#   ./deploy.sh "what changed" --upload   # ...and FTP the site files to the server
#
# For --upload, put credentials in a file named .deploy.env next to this script (it is git-ignored):
#   FTP_HOST=ftp.example.com
#   FTP_USER=username
#   FTP_PASS=password
#   FTP_DIR=/wwwroot          # remote folder that serves https://0pn.ai (often /wwwroot or /httpdocs)
set -euo pipefail
cd "$(dirname "$0")"

MSG="${1:-}"; UPLOAD="${2:-}"
[ -n "$MSG" ] || { echo "usage: ./deploy.sh \"commit message\" [--upload]"; exit 1; }

# 1. Bump the service-worker cache name so installed apps fetch the new files.
if grep -qE '0pn-v[0-9]+' sw.js; then
  CUR=$(grep -oE '0pn-v[0-9]+' sw.js | head -1 | tr -dc '0-9')
  NEXT=$((CUR+1))
  sed -i '' -E "s/0pn-v[0-9]+/0pn-v${NEXT}/" sw.js
  echo "service worker cache: 0pn-v${CUR} -> 0pn-v${NEXT}"
fi

# 2. Keep the sitemap's lastmod current.
TODAY=$(date +%F)
sed -i '' -E "s#<lastmod>[0-9-]+</lastmod>#<lastmod>${TODAY}</lastmod>#" sitemap.xml

# 3. Commit (signed-off, per CONTRIBUTING.md) and push.
git add -A
if git diff --cached --quiet; then
  echo "nothing to commit"
else
  git commit -s -m "$MSG"
fi
git push origin "$(git rev-parse --abbrev-ref HEAD)"

# 4. Optional FTP upload of the files the web server needs.
if [ "$UPLOAD" = "--upload" ]; then
  [ -f .deploy.env ] || { echo "missing .deploy.env (see header of this script)"; exit 1; }
  # shellcheck disable=SC1091
  source .deploy.env
  FILES=(index.html sw.js manifest.json web.config og-image.png screenshot-mobile.png robots.txt sitemap.xml llms.txt
         icons/icon.svg icons/favicon-32.png icons/icon-192.png icons/icon-512.png icons/icon-maskable-512.png icons/apple-touch-icon.png)
  for f in "${FILES[@]}"; do
    echo "uploading $f"
    curl -sS --ssl-reqd --ftp-create-dirs -u "${FTP_USER}:${FTP_PASS}" -T "$f" "ftp://${FTP_HOST}${FTP_DIR}/$f"
  done
  echo "upload complete: https://0pn.ai/"
fi
echo "done."
