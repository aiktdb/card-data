#!/usr/bin/env bash

set -euo pipefail

: "${SOURCE_REPO:?valiables SOURCE_REPO}"
if ! [[ "$SOURCE_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "invalid parameter" >&2
  exit 1
fi

UPSTREAM="${SOURCE_URL:-https://github.com/$SOURCE_REPO.git}"
REQUIRED_WORK="${REQUIRED_WORK:-アイカツ！アンコール}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if ! git clone -q --depth 1 "$UPSTREAM" "$work/upstream" >/dev/null 2>&1; then
  echo "failed" >&2
  exit 1
fi
src="$work/upstream"

python3 - "$src" "$REQUIRED_WORK" <<'PY'
import json, os, sys
src, required = sys.argv[1], sys.argv[2]
try:
    index = json.load(open(os.path.join(src, "index.json"), encoding="utf-8"))
    files = index.get("files")
    assert isinstance(files, list) and files, "no files"
    works = [w.get("work") for w in index.get("works", [])]
    assert required in works, f"no {required}"
    for f in files:
        path = f["path"]
        assert path == "coords.json" or (path.startswith("v/") and path.endswith(".json") and ".." not in path), f"exception: {path}"
        body = json.load(open(os.path.join(src, path), encoding="utf-8"))
        if f.get("kind") == "cards":
            assert isinstance(body.get("cards"), list), f"{path}"
except Exception as e:
    sys.exit(f"failure: {e}")
print(f"check OK（{len(files)} ）")
PY

owner="${SOURCE_REPO%%/*}"
name="${SOURCE_REPO##*/}"
for f in "$src/index.json" "$src/coords.json" "$src/LICENSE" "$src"/v/*.json; do
  [ -f "$f" ] || continue
  if grep -qiF -e "$owner" -e "$name" "$f"; then
    echo "safe guard: ${f#"$src"/}" >&2
    exit 1
  fi
done

mkdir -p v
for f in v/*.json; do
  [ -e "$f" ] || continue
  [ -f "$src/$f" ] || rm -f "$f"
done
for f in index.json coords.json LICENSE; do
  if [ -f "$src/$f" ]; then cp "$src/$f" "$f"; else rm -f "$f"; fi
done
cp "$src"/v/*.json v/
touch .nojekyll

git add -A index.json coords.json LICENSE v .nojekyll
if git diff --cached --quiet; then
  echo "no change"
  echo "changed=0" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi
git -c user.name=card-data-sync -c user.email=card-data-sync@users.noreply.github.com -c commit.gpgsign=false \
  commit -q -m "update（$(date -u +%Y-%m-%d)）"
git --no-pager show --stat --format='%s' HEAD | head -20
echo "changed=1" >> "${GITHUB_OUTPUT:-/dev/null}"
