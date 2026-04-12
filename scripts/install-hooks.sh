#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
git -C "$repo_root" config core.hooksPath .githooks
chmod +x "$repo_root/.githooks/commit-msg" "$repo_root/scripts/check-commit-standards.sh"

echo "Configured git hooks for $repo_root"
echo "Active hooks path: .githooks"
