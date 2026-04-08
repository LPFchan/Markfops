#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
git -C "$repo_root" config core.hooksPath .githooks
chmod +x \
  "$repo_root/.githooks/commit-msg" \
  "$repo_root/scripts/check-commit-standards.sh" \
  "$repo_root/scripts/check-commit-range.sh" \
  "$repo_root/scripts/install-hooks.sh"

echo "Configured git hooks for $repo_root"
echo "Active hooks path: .githooks"

if [ -f "$repo_root/.gitmessage.markfops" ]; then
  echo "Optional helper available: .gitmessage.markfops"
  echo "Set it manually if desired:"
  echo "  git config commit.template .gitmessage.markfops"
fi
