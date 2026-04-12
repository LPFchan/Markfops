#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <base> <head>" >&2
  exit 2
fi

base=$1
head=$2
# Local extension: keep zero-SHA handling and duplicate LOG-id scanning for pushed ranges.
zero=0000000000000000000000000000000000000000

repo_root=$(cd "$(dirname "$0")/.." && pwd)
checker="$repo_root/scripts/check-commit-standards.sh"

if [ "$head" = "$zero" ]; then
  echo "No commits to check for deleted ref"
  exit 0
fi

if [ "$base" = "$zero" ]; then
  commits=$(git -C "$repo_root" rev-list "$head")
  range_label="$head"
else
  commits=$(git -C "$repo_root" rev-list "$base..$head")
  range_label="$base..$head"
fi

if [ -z "$commits" ]; then
  echo "No commits to check in range $range_label"
  exit 0
fi

for commit in $commits; do
  tmp=$(mktemp)
  git -C "$repo_root" log -1 --format=%B "$commit" > "$tmp"
  if ! "$checker" "$tmp"; then
    echo >&2
    echo "Offending commit: $commit" >&2
    rm -f "$tmp"
    exit 1
  fi
  rm -f "$tmp"
done

echo "Commit standards passed for range $range_label"
