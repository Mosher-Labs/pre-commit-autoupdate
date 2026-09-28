#!/usr/bin/env bash
# Auto-update pre-commit hooks and stage changes for commit
#
# This hook runs `pre-commit autoupdate` and stages any changes to
# .pre-commit-config.yaml so they are included in the current commit.
#
# Hook args:
#   --interval-hours N  Skip the update if one succeeded in the last N hours.
#   Anything else is passed through to `pre-commit autoupdate`
#   (e.g. --freeze, --bleeding-edge, --repo URL, --jobs N).

set -euo pipefail

CONFIG_FILE=".pre-commit-config.yaml"
DEFAULT_JOBS=8

interval_hours=0
jobs_set=false
autoupdate_args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --interval-hours)
            interval_hours="${2:?--interval-hours requires a value}"
            shift 2
            ;;
        --interval-hours=*)
            interval_hours="${1#*=}"
            shift
            ;;
        -j | --jobs | -j* | --jobs=*)
            jobs_set=true
            autoupdate_args+=("$1")
            shift
            ;;
        *)
            autoupdate_args+=("$1")
            shift
            ;;
    esac
done

if [[ ! "$interval_hours" =~ ^[0-9]+$ ]]; then
    echo "--interval-hours must be a whole number, got: $interval_hours" >&2
    exit 1
fi

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "No $CONFIG_FILE found, skipping autoupdate"
    exit 0
fi

# Fetch repos in parallel; each one is a network round trip
if [[ "$jobs_set" == false ]]; then
    autoupdate_args+=(--jobs "$DEFAULT_JOBS")
fi

# Skip if a recent run with the same args succeeded. The stamp stores the
# args so changing them (e.g. adding --freeze) forces a fresh run.
stamp_file="$(git rev-parse --git-path pre-commit-autoupdate.stamp)"
stamp_key="${autoupdate_args[*]}"
if [[ "$interval_hours" -gt 0 && -f "$stamp_file" ]] &&
    [[ "$(cat "$stamp_file")" == "$stamp_key" ]] &&
    [[ -n "$(find "$stamp_file" -mmin "-$((interval_hours * 60))")" ]]; then
    exit 0
fi

# Run pre-commit autoupdate
echo "Checking for pre-commit hook updates..."
pre-commit autoupdate "${autoupdate_args[@]}"
printf '%s' "$stamp_key" >"$stamp_file"

# Stage the config file if it changed
if ! git diff --quiet "$CONFIG_FILE" 2>/dev/null; then
    git add "$CONFIG_FILE"
    echo "Pre-commit hooks updated and staged for commit"
fi

exit 0
