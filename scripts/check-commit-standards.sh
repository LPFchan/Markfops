#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <commit-message-file>" >&2
  exit 2
fi

msg_file=$1
repo_root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)

if [ ! -f "$msg_file" ]; then
  echo "commit standards check failed: commit message file not found: $msg_file" >&2
  exit 2
fi

has_trailer() {
  key=$1
  grep -Eq "^$key: .+" "$msg_file"
}

trailer_value() {
  key=$1
  sed -n "s/^$key: //p" "$msg_file" | tail -n 1
}

is_exception_commit() {
  grep -Eqi '^(bootstrap|migration)(\b| exception\b)' "$msg_file" ||
    grep -Eqi '^exception: (bootstrap|migration)$' "$msg_file"
}

fail() {
  echo "commit standards check failed: $1" >&2
  echo >&2
  echo "Expected required trailers:" >&2
  echo "  project: <project-id>" >&2
  echo "  agent: <agent-id>" >&2
  echo "  role: orchestrator|worker|subagent|operator" >&2
  echo "  commit: LOG-YYYYMMDD-HHMMSS-<agent-suffix>[, LOG-...]" >&2
  echo >&2
  echo "Optional trailer:" >&2
  echo "  artifacts: <artifact-id>[, <artifact-id>...]" >&2
  echo >&2
  echo "Required body keys:" >&2
  echo "  timestamp:" >&2
  echo "  changes:" >&2
  echo "  rationale:" >&2
  echo "  checks:" >&2
  echo "  notes: (optional)" >&2
  echo >&2
  echo "Bootstrap or migration exceptions must be explicit in the commit message." >&2
  exit 1
}

normalize_agent() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

agent_suffix() {
  normalized=$(normalize_agent "$1")
  [ -n "$normalized" ] || return 1
  printf '%s\n' "$normalized" | awk '
    {
      len = length($0)
      if (len <= 6) {
        print $0
      } else {
        print substr($0, len - 5)
      }
    }
  '
}

default_branch_ref() {
  if ref=$(git -C "$repo_root" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s\n' "$ref"
    return 0
  fi

  if git -C "$repo_root" show-ref --verify --quiet refs/remotes/origin/main; then
    printf '%s\n' "origin/main"
    return 0
  fi

  if git -C "$repo_root" show-ref --verify --quiet refs/remotes/origin/master; then
    printf '%s\n' "origin/master"
    return 0
  fi

  if ref=$(git -C "$repo_root" symbolic-ref -q --short HEAD 2>/dev/null); then
    printf '%s\n' "$ref"
    return 0
  fi

  return 1
}

extract_commit_ids_from_value() {
  printf '%s\n' "$1" | tr ',' '\n' | sed 's/^ *//; s/ *$//'
}

extract_body_to_file() {
  target=$1
  awk '
    NR == 1 {
      next
    }
    /^(project|agent|role|commit|artifacts): / {
      exit
    }
    {
      print
    }
  ' "$msg_file" > "$target"
}

validate_body() {
  body_file=$(mktemp)
  extract_body_to_file "$body_file"

  if ! awk '
    function die(msg) {
      print "commit standards check failed: " msg > "/dev/stderr"
      exit 1
    }

    /^[[:space:]]*$/ {
      next
    }

    state == 0 {
      if ($0 ~ /^timestamp: [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}-[0-9]{2}-[0-9]{2} KST$/) {
        state = 1
        next
      }
      die("expected `timestamp: YYYY-MM-DD HH-mm-ss KST` before other body content")
    }

    state == 1 {
      if ($0 == "changes:") {
        state = 2
        changes_items = 0
        next
      }
      die("expected `changes:` after `timestamp:`")
    }

    state == 2 {
      if ($0 ~ /^- .+/) {
        changes_items = 1
        next
      }
      if (changes_items && $0 == "rationale:") {
        state = 3
        rationale_items = 0
        next
      }
      die("expected one or more `- ...` lines under `changes:`")
    }

    state == 3 {
      if ($0 ~ /^- .+/) {
        rationale_items = 1
        next
      }
      if (rationale_items && $0 == "checks:") {
        state = 4
        checks_items = 0
        next
      }
      die("expected one or more `- ...` lines under `rationale:`")
    }

    state == 4 {
      if ($0 ~ /^- .+/) {
        checks_items = 1
        next
      }
      if (checks_items && $0 == "notes:") {
        state = 5
        notes_items = 0
        next
      }
      die("expected one or more `- ...` lines under `checks:`")
    }

    state == 5 {
      if ($0 ~ /^- .+/) {
        notes_items = 1
        next
      }
      die("expected one or more `- ...` lines under optional `notes:`")
    }

    END {
      if (state == 0) {
        die("missing structured body")
      }
      if (state == 1) {
        die("missing `changes:` section")
      }
      if (state == 2 && !changes_items) {
        die("`changes:` must contain at least one list item")
      }
      if (state == 3 && !rationale_items) {
        die("`rationale:` must contain at least one list item")
      }
      if (state == 4 && !checks_items) {
        die("`checks:` must contain at least one list item")
      }
      if (state == 5 && !notes_items) {
        die("`notes:` must contain at least one list item when present")
      }
    }
  ' "$body_file"; then
    rm -f "$body_file"
    exit 1
  fi

  rm -f "$body_file"
}

check_primary_id_uniqueness() {
  primary_id=$1
  refs=""
  head_sha=$(git -C "$repo_root" rev-parse -q --verify HEAD 2>/dev/null || true)

  current_ref=$(git -C "$repo_root" symbolic-ref -q --short HEAD 2>/dev/null || true)
  default_ref=$(default_branch_ref || true)

  if [ -n "$current_ref" ]; then
    refs=$current_ref
  fi

  if [ -n "$default_ref" ] && [ "$default_ref" != "$current_ref" ]; then
    refs="$refs $default_ref"
  fi

  [ -n "$refs" ] || return 0

  for sha in $(git -C "$repo_root" rev-list $refs 2>/dev/null); do
    existing_value=$(git -C "$repo_root" log -1 --format=%B "$sha" | sed -n 's/^commit: //p' | tail -n 1)
    [ -n "$existing_value" ] || continue

    for existing_id in $(extract_commit_ids_from_value "$existing_value"); do
      if [ "$existing_id" = "$primary_id" ]; then
        if [ -n "$head_sha" ] && [ "$sha" = "$head_sha" ]; then
          continue
        fi
        fail "primary \`commit:\` id already exists in history: $primary_id (generate a fresh skeleton with sh scripts/new-commit-message.sh --subject \"...\")"
      fi
    done
  done

  return 0
}

subject=$(sed -n '1p' "$msg_file")
[ -n "$subject" ] || fail "subject line is empty"

if is_exception_commit; then
  exit 0
fi

has_trailer "project" || fail "missing trailer: project"
has_trailer "agent" || fail "missing trailer: agent"
has_trailer "role" || fail "missing trailer: role"
has_trailer "commit" || fail "missing trailer: commit"

project=$(trailer_value "project")
agent=$(trailer_value "agent")
role=$(trailer_value "role")
commit_value=$(trailer_value "commit")
artifacts_value=$(trailer_value "artifacts" || true)

[ -n "$project" ] || fail "project trailer is empty"
[ -n "$agent" ] || fail "agent trailer is empty"

case "$role" in
  orchestrator|worker|subagent|operator) ;;
  *) fail "invalid role trailer: $role" ;;
esac

validate_body

normalized_agent=$(normalize_agent "$agent")
[ -n "$normalized_agent" ] || fail "agent trailer must include at least one alphanumeric character after normalization"
expected_primary_suffix=$(agent_suffix "$agent")

[ -n "$commit_value" ] || fail "commit trailer is empty"

seen_commit_ids=""
primary_commit_id=""
commit_index=0

for commit_id in $(extract_commit_ids_from_value "$commit_value"); do
  [ -n "$commit_id" ] || fail "commit trailer contains an empty LOG id"

  printf '%s\n' "$commit_id" | grep -Eq '^LOG-[0-9]{8}-[0-9]{6}-[a-z0-9]{1,6}$' ||
    fail "commit trailer must be a comma-separated list like LOG-YYYYMMDD-HHMMSS-agentid"

  case " $seen_commit_ids " in
    *" $commit_id "*) fail "duplicate LOG id inside commit trailer: $commit_id" ;;
  esac
  seen_commit_ids="$seen_commit_ids $commit_id"

  if [ "$commit_index" -eq 0 ]; then
    primary_commit_id=$commit_id
    primary_suffix=${primary_commit_id##*-}
    [ "$primary_suffix" = "$expected_primary_suffix" ] ||
      fail "primary LOG id suffix must match the normalized agent suffix: expected $expected_primary_suffix"
  fi

  commit_index=$((commit_index + 1))
done

[ -n "$primary_commit_id" ] || fail "commit trailer must contain at least one LOG id"

if [ -n "$artifacts_value" ]; then
  seen_artifacts=""

  for artifact_id in $(extract_commit_ids_from_value "$artifacts_value"); do
    [ -n "$artifact_id" ] || fail "artifacts trailer contains an empty artifact id"

    case "$artifact_id" in
      LOG-*) fail "artifacts trailer must not include LOG ids: $artifact_id" ;;
    esac

    printf '%s\n' "$artifact_id" | grep -Eq '^[A-Z]{3}-[0-9]{8}-[0-9]{3}$' ||
      fail "artifacts trailer must contain only file-backed ids like DEC-YYYYMMDD-NNN"

    case " $seen_artifacts " in
      *" $artifact_id "*) fail "duplicate artifact id inside artifacts trailer: $artifact_id" ;;
    esac
    seen_artifacts="$seen_artifacts $artifact_id"
  done
fi

check_primary_id_uniqueness "$primary_commit_id"
