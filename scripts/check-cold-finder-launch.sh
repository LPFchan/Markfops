#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 /path/to/Markfops.app" >&2
    exit 2
fi

app=$1
if [ ! -d "$app" ]; then
    echo "Markfops app not found: $app" >&2
    exit 2
fi

probe_root=$(mktemp -d /tmp/markfops-cold-launch.XXXXXX)
fixture="$probe_root/Finder Launch Probe.md"
recovery_directory="$probe_root/Recovery"
automation_error="$probe_root/automation-error.log"
before_pids=$(pgrep -x Markfops 2>/dev/null || true)
app_pid=

cleanup() {
    if [ -n "$app_pid" ]; then
        kill -TERM "$app_pid" 2>/dev/null || true
    fi
    rm -r "$probe_root"
}
trap cleanup EXIT HUP INT TERM

printf '# Finder Launch Probe\n' > "$fixture"
open -n -a "$app" --env "MARKFOPS_RECOVERY_DIRECTORY=$recovery_directory" "$fixture"

attempt=0
while [ "$attempt" -lt 120 ]; do
    attempt=$((attempt + 1))
    sleep 0.25
    for candidate in $(pgrep -x Markfops 2>/dev/null || true); do
        case " $before_pids " in
            *" $candidate "*) ;;
            *) app_pid=$candidate ;;
        esac
    done
    [ -n "$app_pid" ] && break
done

if [ -z "$app_pid" ]; then
    echo "Markfops did not launch" >&2
    exit 1
fi

attempt=0
while [ "$attempt" -lt 120 ]; do
    attempt=$((attempt + 1))
    if ! result=$(osascript -e "tell application \"System Events\" to tell first process whose unix id is $app_pid to return {count of windows, name of every window}" 2>"$automation_error"); then
        automation_message=$(cat "$automation_error")
        case "$automation_message" in
            *"not allowed assistive access"*|*"Not authorized to send Apple events"*|*"(-1743)"*|*"(-25211)"*)
                printf '%s\n' "$automation_message" >&2
                echo "Unable to inspect Markfops windows through System Events" >&2
                exit 1
                ;;
        esac
        sleep 0.25
        continue
    fi
    case "$result" in
        1,*"Finder Launch Probe")
            echo "Cold Finder launch opened the requested document window"
            exit 0
            ;;
    esac
    sleep 0.25
done

if [ -s "$automation_error" ]; then
    cat "$automation_error" >&2
fi
echo "Cold Finder launch did not present the requested document window" >&2
exit 1
