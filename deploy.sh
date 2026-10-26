#!/usr/bin/env bash
# deploy.sh — commit, push to GitHub, optionally tag a release and upload 0pn.ai to the web server.
#
#   ./deploy.sh "what changed"                        # bump SW cache, update sitemap date, commit, push
#   ./deploy.sh "what changed" --upload               # ...and FTP the site files to the server
#   ./deploy.sh "what changed" --upload v1.0.1        # ...and tag + push a release (any order of flags)
#   ./deploy.sh "what changed" v1.0.1                 # tag without uploading
#
# For --upload, create .deploy.env next to this script (git-ignored):
#   FTP_HOST=ftp.example.com
#   FTP_USER=username
#   FTP_PASS=password
#   FTP_DIR=/wwwroot          # remote folder that serves https://0pn.ai
set -euo pipefail
cd "$(dirname "$0")"

MSG="${1:-}"; UPLOAD=""; TAG=""
[ -n "$MSG" ] || { echo "usage: ./deploy.sh \"commit message\" [--upload] [vX.Y.Z]"; exit 1; }
for arg in "${@:2}"; do
  case "$arg" in
    --upload) UPLOAD=1 ;;
    v[0-9]*)  TAG="$arg" ;;
    *) echo "unknown argument: $arg"; exit 1 ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repository"; exit 1; }
BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 1. Bump the service-worker cache name so installed apps fetch the new files.
if grep -qE '0pn-v[0-9]+' sw.js; then
  CUR=$(grep -oE '0pn-v[0-9]+' sw.js | head -1 | sed 's|.*-v||')
  NEXT=$((10#$CUR+1))
  sed -i '' -E "s/0pn-v[0-9]+/0pn-v${NEXT}/" sw.js
  echo "service worker cache: 0pn-v${CUR} -> 0pn-v${NEXT}"
fi

# 2. Keep the sitemap's lastmod current.
sed -i '' -E "s#<lastmod>[0-9-]+</lastmod>#<lastmod>$(date +%F)</lastmod>#" sitemap.xml

# 3. Commit (signed-off, per CONTRIBUTING.md) and push to GitHub. Never force-pushes.
git add -A
if git diff --cached --quiet; then
  echo "nothing new to commit"
else
  git commit -s -m "$MSG"
fi
git pull --rebase --quiet origin "$BRANCH" || { echo "pull --rebase failed; resolve and re-run"; exit 1; }
git push origin "$BRANCH"
echo "pushed to GitHub: $BRANCH"

# 4. Optional release tag.
if [ -n "$TAG" ]; then
  if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "tag $TAG already exists; skipping"
  else
    git tag -a "$TAG" -m "$MSG"
    git push origin "$TAG"
    echo "tagged $TAG — create the Release on GitHub: https://github.com/tirmizisamir/0pn.ai/releases/new?tag=$TAG"
  fi
fi

# 5. Optional FTP upload of the files the web server needs.
if [ -n "$UPLOAD" ]; then
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
