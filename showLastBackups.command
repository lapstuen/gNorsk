#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ Denne filen må ligge i Git-repoets rotmappe."
  read -n 1 -s -r -p "Trykk en tast for å lukke..."
  exit 1
fi

echo "📦 Repo: $(pwd)"
echo "🔄 Henter backup-tagger fra GitHub (origin)…"
git fetch -q --tags

# List remote backup-* tags, fetch commit time for each, sort by time, show last 25
{
  git ls-remote --tags origin 'backup-*' \
  | awk '{print $2}' \
  | sed 's@refs/tags/@@' \
  | while read -r tag; do
      [ -z "$tag" ] && continue
      sha="$(git ls-remote --tags origin "$tag" | awk '{print $1}' | head -1)"
      if ! git cat-file -e "$sha" 2>/dev/null; then
        git fetch -q origin "$sha" || true
      fi
      ts="$(git show -s --format=%ci "$sha" 2>/dev/null || echo '?')"
      printf "%s\t%s\t%s\n" "$ts" "$tag" "$sha"
    done
} \
| sort \
| tail -n 25 \
| awk -F'\t' '{ printf "🏷️  %-28s  %s\n", $2, $1 }'

echo
echo "✅ Ferdig – viste de siste 25 pushede backup-taggene (fra origin)."
read -n 1 -s -r -p "Trykk en tast for å lukke..."