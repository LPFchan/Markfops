#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <commit-message-file>" >&2
  exit 2
fi

msg_file=$1

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
  echo "Expected trailers:" >&2
  echo "  project: markfops" >&2
  echo "  agent: <agent-id>" >&2
  echo "  role: orchestrator|worker|subagent|operator" >&2
  echo "  artifacts: <artifact-id>[, <artifact-id>...]" >&2
  echo >&2
  echo "Bootstrap or migration exceptions must be explicit in the commit message." >&2
  exit 1
}

subject=$(sed -n '1p' "$msg_file")
[ -n "$subject" ] || fail "subject line is empty"

if is_exception_commit; then
  exit 0
fi

has_trailer "project" || fail "missing trailer: project"
has_trailer "agent" || fail "missing trailer: agent"
has_trailer "role" || fail "missing trailer: role"
has_trailer "artifacts" || fail "missing trailer: artifacts"

project=$(trailer_value "project")
[ "$project" = "markfops" ] || fail "project trailer must be markfops"

role=$(trailer_value "role")
case "$role" in
  orchestrator|worker|subagent|operator) ;;
  *) fail "invalid role trailer: $role" ;;
esac

artifacts=$(trailer_value "artifacts")
[ -n "$artifacts" ] || fail "artifacts trailer is empty"

echo "$artifacts" | grep -Eq '^[A-Z]{3}-[0-9]{8}-[0-9]{3}(, [A-Z]{3}-[0-9]{8}-[0-9]{3})*$' ||
  fail "artifacts trailer must be a comma-separated list like ART-YYYYMMDD-NNN"
