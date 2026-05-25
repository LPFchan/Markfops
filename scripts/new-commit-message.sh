#!/bin/sh

set -eu

repo_root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)

usage() {
  cat <<'EOF'
Usage: sh scripts/new-commit-message.sh --subject "Subject line" [options]

Creates a repo-compliant commit message skeleton with a fresh LOG id.

Options:
  --subject TEXT     Commit subject line. Required.
  --agent TEXT       Agent trailer value. Default: ${AGENT_ID:-copilot}
  --role TEXT        role trailer value. Default: worker
  --project TEXT     project trailer value. Default: repo directory name
  --artifacts TEXT   Optional comma-separated artifact ids.
  --output PATH      Write to PATH instead of an auto-generated temp file.
  --help             Show this help.

Example:
  sh scripts/new-commit-message.sh --subject "feat: add helper" --agent gpt54
EOF
}

normalize_agent() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

agent_suffix() {
  normalized=$(normalize_agent "$1")
  [ -n "$normalized" ] || return 1

  length=${#normalized}
  if [ "$length" -le 6 ]; then
    printf '%s\n' "$normalized"
    return 0
  fi

  start=$((length - 5))
  printf '%s\n' "$normalized" | cut -c"$start"-
}

slugify_subject() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//; s/^$/commit/'
}

SUBJECT=""
AGENT="${AGENT_ID:-copilot}"
ROLE="worker"
PROJECT=$(basename "$repo_root" | tr '[:upper:]' '[:lower:]')
ARTIFACTS=""
OUTPUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --subject)
      SUBJECT=$2
      shift 2
      ;;
    --agent)
      AGENT=$2
      shift 2
      ;;
    --role)
      ROLE=$2
      shift 2
      ;;
    --project)
      PROJECT=$2
      shift 2
      ;;
    --artifacts)
      ARTIFACTS=$2
      shift 2
      ;;
    --output)
      OUTPUT=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[ -n "$SUBJECT" ] || {
  echo "--subject is required" >&2
  usage >&2
  exit 2
}

suffix=$(agent_suffix "$AGENT") || {
  echo "--agent must contain at least one alphanumeric character after normalization" >&2
  exit 2
}

timestamp_body=$(TZ=Asia/Seoul date '+%Y-%m-%d %H-%M-%S KST')
timestamp_id=$(TZ=Asia/Seoul date '+%Y%m%d-%H%M%S')
log_id="LOG-${timestamp_id}-${suffix}"

if [ -z "$OUTPUT" ]; then
  subject_slug=$(slugify_subject "$SUBJECT")
  OUTPUT="$repo_root/.tmp_commit_msg_${subject_slug}_${timestamp_id}.txt"
fi

if [ -e "$OUTPUT" ]; then
  echo "Refusing to overwrite existing file: $OUTPUT" >&2
  exit 1
fi

{
  printf '%s\n' "$SUBJECT"
  printf '\n'
  printf 'timestamp: %s\n' "$timestamp_body"
  printf 'changes:\n'
  printf -- '- TODO\n'
  printf 'rationale:\n'
  printf -- '- TODO\n'
  printf 'checks:\n'
  printf -- '- TODO\n'
  printf '\n'
  printf 'project: %s\n' "$PROJECT"
  printf 'agent: %s\n' "$AGENT"
  printf 'role: %s\n' "$ROLE"
  printf 'commit: %s\n' "$log_id"
  if [ -n "$ARTIFACTS" ]; then
    printf 'artifacts: %s\n' "$ARTIFACTS"
  fi
} > "$OUTPUT"

git_registry_dir=$(git -C "$repo_root" rev-parse --git-path repo-template/generated-commit-ids)
case "$git_registry_dir" in
  /*) registry_dir=$git_registry_dir ;;
  *) registry_dir="$repo_root/$git_registry_dir" ;;
esac
mkdir -p "$registry_dir"
{
  printf 'log_id=%s\n' "$log_id"
  printf 'created_at=%s\n' "$timestamp_body"
  printf 'message_file=%s\n' "$OUTPUT"
  printf 'subject=%s\n' "$SUBJECT"
  printf 'agent=%s\n' "$AGENT"
  printf 'role=%s\n' "$ROLE"
  printf 'project=%s\n' "$PROJECT"
} > "$registry_dir/$log_id"

printf 'Created commit message skeleton: %s\n' "$OUTPUT"
printf 'Primary LOG id: %s\n' "$log_id"
printf 'Registered LOG id for the local prepare-commit-msg gate.\n'
printf 'Next steps:\n'
printf '  1. Edit the TODO bullets in %s\n' "$OUTPUT"
printf '  2. Validate it: sh scripts/check-commit-standards.sh %s\n' "$OUTPUT"
printf '  3. Commit with: git commit -F %s\n' "$OUTPUT"
