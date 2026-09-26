#!/bin/bash
#
# sync-from-template.sh — self-sync for an adopted repo.
#
# Run from anywhere inside an adopted repo. Fetches the latest repo-template
# scaffold from GitHub, applies every entry in scaffold/manifest.txt
# verbatim, splices the managed section of AGENTS.md (everything up to the
# template-managed:end marker; content after it is preserved), and bumps the
# Template version line when content changed.
#
# Exits 0 and prints SYNC-CHANGED=1 when files were modified, otherwise
# prints SYNC-CHANGED=0. The caller (weekly GitHub Actions workflow, or an
# operator) owns the commit.

set -eu

REPO_ROOT=$(git rev-parse --show-toplevel)
TEMPLATE_URL=${TEMPLATE_URL:-https://github.com/LPFchan/repo-template.git}

TMP=$(mktemp -d /tmp/template-self-sync.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

git clone -q --depth 1 "$TEMPLATE_URL" "$TMP/template"
SCAFFOLD="$TMP/template/scaffold"
MANIFEST="$SCAFFOLD/manifest.txt"
VERSION=$(sed -n 's/^\*\*Template version: \(.*\)\*\*/\1/p' "$SCAFFOLD/records/REPO.md" | head -1)
[ -n "$VERSION" ] || { echo "could not read Template version" >&2; exit 1; }

changed=0

splice_agents() {
  python3 - "$SCAFFOLD/AGENTS.md" "$REPO_ROOT/AGENTS.md" "$TMP/agents-merged.md" <<'PY'
import sys

scaffold_path, repo_path, out_path = sys.argv[1:4]
END = "<!-- template-managed:end -->"
LEGACY_TAIL = "## Repo-Specific Rules"

scaffold = open(scaffold_path).read()
repo = open(repo_path).read()

if END not in scaffold:
    sys.exit("scaffold AGENTS.md is missing the template-managed:end marker")

managed = scaffold[: scaffold.index(END) + len(END)]

if END in repo:
    tail = repo[repo.index(END) + len(END) :]
elif LEGACY_TAIL in repo:
    tail = "\n\n" + repo[repo.index(LEGACY_TAIL) :]
elif "## Code Review Rules" in repo:
    idx = repo.index("## Code Review Rules")
    end = repo.index("\n## ", idx + 1) if "\n## " in repo[idx + 1 :] else len(repo)
    tail = repo[end:]
else:
    sys.exit(1)

open(out_path, "w").write(managed + tail)
PY
}

while IFS= read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  entry=$(echo "$line" | sed 's/^ *//; s/ *$//')

  if [ "$entry" = "AGENTS.md managed-section" ]; then
    [ -f "$REPO_ROOT/AGENTS.md" ] || continue
    if splice_agents; then
      if ! cmp -s "$TMP/agents-merged.md" "$REPO_ROOT/AGENTS.md"; then
        cp "$TMP/agents-merged.md" "$REPO_ROOT/AGENTS.md"
        changed=1
      fi
    else
      echo "AGENTS.md has no template boundary; skipping managed-section sync" >&2
    fi
    continue
  fi

  src=${entry%% -> *}
  dst=${entry##* -> }
  src_path="$SCAFFOLD/$src"
  dst_path="$REPO_ROOT/$dst"

  case "$src" in
    */)
      mkdir -p "$dst_path"
      if ! diff -qr "$src_path" "$dst_path" >/dev/null 2>&1; then
        rsync -a --delete "$src_path" "$dst_path"
        changed=1
      fi
      ;;
    *)
      if ! cmp -s "$src_path" "$dst_path" 2>/dev/null; then
        mkdir -p "$(dirname "$dst_path")"
        cp "$src_path" "$dst_path"
        chmod +x "$dst_path" 2>/dev/null || true
        changed=1
      fi
      ;;
  esac
done < "$MANIFEST"

if [ $changed = 1 ] && [ -f "$REPO_ROOT/records/REPO.md" ]; then
  if ! grep -q "Template version: $VERSION" "$REPO_ROOT/records/REPO.md"; then
    sed -i "s/\*\*Template version: [0-9.]*\*\*/**Template version: $VERSION**/" "$REPO_ROOT/records/REPO.md"
  fi
fi

echo "SYNC-VERSION=$VERSION"
echo "SYNC-CHANGED=$changed"
