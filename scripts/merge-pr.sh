#!/bin/sh

set -eu

repo_root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)

usage() {
  cat <<'EOF'
Usage: sh scripts/merge-pr.sh --pr N --subject "Subject line" --changes-file PATH [options]

Squash-merges a pull request with a contract-compliant commit message.

Generates the squash message via scripts/new-commit-message.sh, validates it
with scripts/check-commit-standards.sh, then squash merges and deletes the
branch. GitHub's auto-generated squash message never satisfies the commit
contract, so never merge through the web UI button.

Options:
  --pr N             Pull request number. Required.
  --subject TEXT     Squash commit subject line. Required.
  --changes-file PATH  File holding the changes:/rationale:/checks: list
                       bodies (the three sections, with bullets). Required.
  --agent TEXT       Agent trailer value. Default: ${AGENT_ID:-copilot}
  --role TEXT        role trailer value. Default: orchestrator
  --project TEXT     project trailer value. Default: repo directory name
  --help             Show this help.

Example:
  sh scripts/merge-pr.sh --pr 2 --subject "docs: add workflow" \
    --changes-file /tmp/sections.txt --agent claude
EOF
}

pr=""
subject=""
changes_file=""
agent="${AGENT_ID:-copilot}"
role="orchestrator"
project="$(basename "$repo_root")"

while [ $# -gt 0 ]; do
  case "$1" in
    --pr) pr="$2"; shift 2 ;;
    --subject) subject="$2"; shift 2 ;;
    --changes-file) changes_file="$2"; shift 2 ;;
    --agent) agent="$2"; shift 2 ;;
    --role) role="$2"; shift 2 ;;
    --project) project="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[ -n "$pr" ] || { echo "missing --pr" >&2; exit 1; }
[ -n "$subject" ] || { echo "missing --subject" >&2; exit 1; }
[ -n "$changes_file" ] || { echo "missing --changes-file" >&2; exit 1; }
[ -f "$changes_file" ] || { echo "changes file not found: $changes_file" >&2; exit 1; }

# Resolve the target repo and pin the reviewed head BEFORE building the
# message, so there is no window where a new push gets silently merged.
target_repo=$(git -C "$repo_root" remote get-url origin | sed 's/^git@[^:]*://; s|^https\?://[^/]*/||; s/\.git$//')
head_sha=$(gh pr view "$pr" --repo "$target_repo" --json headRefOid --jq .headRefOid)

msg_file=$(mktemp -u)
trap 'rm -f "$msg_file"' EXIT

sh "$repo_root/scripts/new-commit-message.sh" \
  --subject "$subject" --agent "$agent" --role "$role" \
  --project "$project" --output "$msg_file" >/dev/null

# Replace the TODO skeleton sections with the supplied bodies.
# Sections are passed via a file descriptor, not awk -v, so backslashes survive.
awk '
  BEGIN { skip = 0 }
  /^changes:$/ {
    print
    while ((getline line < CHANGES_FILE) > 0) print line
    print ""
    skip = 1
    next
  }
  skip && /^project:/ { skip = 0; print; next }
  skip { next }
  { print }
' CHANGES_FILE="$changes_file" "$msg_file" > "$msg_file.new" && mv "$msg_file.new" "$msg_file"

sh "$repo_root/scripts/check-commit-standards.sh" "$msg_file"

merge_subject=$(head -1 "$msg_file")
merge_body=$(tail -n +2 "$msg_file")

# Merge pinned to the head SHA sampled above: any push after that sample
# makes GitHub refuse the merge instead of landing unreviewed commits.
gh pr merge "$pr" --repo "$target_repo" \
  --squash --delete-branch --match-head-commit "$head_sha" \
  --subject "$merge_subject" --body "$merge_body"

echo "Merged PR #$pr with contract-compliant squash message."
