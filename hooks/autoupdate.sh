#!/usr/bin/env bash
# Auto-update pre-commit hooks and stage changes for commit
#
# This hook runs `pre-commit autoupdate` and stages any changes to
# .pre-commit-config.yaml so they are included in the current commit.

set -euo pipefail

CONFIG_FILE=".pre-commit-config.yaml"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "No $CONFIG_FILE found, skipping autoupdate"
    exit 0
fi

# Run pre-commit autoupdate
echo "Checking for pre-commit hook updates..."
pre-commit autoupdate

# Stage the config file if it changed
if ! git diff --quiet "$CONFIG_FILE" 2>/dev/null; then
    git add "$CONFIG_FILE"
    echo "Pre-commit hooks updated and staged for commit"
fi

exit 0
