#!/usr/bin/env bash
set -euo pipefail

repo="James1997s/lockplus15-rootless"
catalog="themes/catalog.json"
count=0

while IFS= read -r relative_path; do
  gh api "repos/${repo}/contents/themes/${relative_path}" --jq '.sha' >/dev/null
  count=$((count + 1))
done < <(grep -oE '"url": "[^"]+\.json"' "$catalog" | sed -E 's/"url": "([^"]+)"/\1/')

printf 'Verified %d public GitHub theme URLs.\n' "$count"
