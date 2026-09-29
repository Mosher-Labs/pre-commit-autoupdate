#!/usr/bin/env bash
# Runs hooks/autoupdate.sh against local hook repos, with release dates served
# from fixture files through PCA_GITHUB_API. Needs git and pre-commit.
#
# Usage: tests/run.sh    (BASH_BIN=/bin/bash to test another bash)
#
# check takes its condition as a string and evals it, so $status and $(...)
# in single quotes are intended.
# shellcheck disable=SC2016,SC2034

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/hooks/autoupdate.sh"
BASH_BIN="${BASH_BIN:-bash}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export PCA_GITHUB_API="file://$WORK/api"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset GITHUB_TOKEN GH_TOKEN

passed=0
status=0
failed=0

# Creates a hook repo at $WORK/remotes/acme/<name> with tags v1.0.0 and v2.0.0.
make_hook_repo() {
    local dir="$WORK/remotes/acme/$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    printf -- '- id: noop\n  name: noop\n  entry: "true"\n  language: system\n' >"$dir/.pre-commit-hooks.yaml"
    git -C "$dir" add . && git -C "$dir" commit -qm one && git -C "$dir" tag v1.0.0
    git -C "$dir" commit -qm two --allow-empty && git -C "$dir" tag -a v2.0.0 -m v2.0.0
}

# Writes a release fixture for acme/<name> <tag> published <days> ago.
release() {
    local dir="$WORK/api/repos/acme/$1/releases/tags" since
    since=$(($(date -u +%s) - $3 * 86400))
    mkdir -p "$dir"
    printf '{\n  "tag_name": "%s",\n  "published_at": "%s"\n}\n' "$2" \
        "$(date -u -d "@$since" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$since" +%Y-%m-%dT%H:%M:%SZ)" >"$dir/$2"
}

# Creates a fresh consumer repo pinning both hook repos at v1.0.0 and cds into it.
new_consumer() {
    rm -rf "$WORK/api" "$WORK/consumer"
    mkdir -p "$WORK/consumer" && cd "$WORK/consumer"
    git init -q
    cat >.pre-commit-config.yaml <<EOF
repos:
  - repo: $WORK/remotes/acme/tool
    rev: v1.0.0
    hooks:
      - id: noop
  - repo: $WORK/remotes/acme/other
    rev: v1.0.0
    hooks:
      - id: noop
EOF
    git add . && git commit -qm init
}

# Replaces the consumer's config with stdin and commits it.
set_config() {
    cat >.pre-commit-config.yaml
    git add . && git commit -qm config
}

# Prints the rev line for acme/<name>.
rev_of() {
    tr -d '\r' <.pre-commit-config.yaml | grep -A1 "acme/$1\$" | sed -n 's/^ *rev: *//p'
}

# Runs the hook, saving its output and exit code in $status.
run_hook() {
    status=0
    "$BASH_BIN" "$HOOK" "$@" >"$WORK/out" 2>&1 || status=$?
}

check() {
    if eval "$2"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        echo "FAIL: $1 ($2)"
        sed 's/^/    /' "$WORK/out" 2>/dev/null || true
    fi
}

make_hook_repo tool
make_hook_repo other
make_hook_repo hashy
git -C "$WORK/remotes/acme/hashy" commit -qm three --allow-empty
git -C "$WORK/remotes/acme/hashy" tag 'v2.0.0#evil'
make_hook_repo moved
"$BASH_BIN" --version | head -n 1

new_consumer
run_hook
check "default run bumps and stages" '[[ "$(rev_of tool)" == v2.0.0 ]] && ! git diff --cached --quiet'

new_consumer
run_hook --freeze
check "--freeze writes a SHA with a frozen comment" '[[ "$(rev_of tool)" =~ ^[0-9a-f]{40}\ \ \#\ frozen:\ v2.0.0$ ]]'

new_consumer
release tool v2.0.0 1
release other v2.0.0 1
run_hook --min-age-days 7
check "--min-age-days holds a young release" '[[ "$(rev_of tool)" == v1.0.0 ]] && git diff --quiet && git diff --cached --quiet'

new_consumer
release tool v2.0.0 30
release other v2.0.0 30
run_hook --min-age-days 7
check "--min-age-days takes an old release" '[[ "$(rev_of tool)" == v2.0.0 && "$(rev_of other)" == v2.0.0 ]]'

new_consumer
run_hook --min-age-days 7
check "--min-age-days holds a tag with no release" '[[ "$(rev_of tool)" == v1.0.0 && "$(rev_of other)" == v1.0.0 ]]'

new_consumer
release tool v2.0.0 30
release other v2.0.0 1
run_hook --min-age-days 7
check "--min-age-days decides per repo" '[[ "$(rev_of tool)" == v2.0.0 && "$(rev_of other)" == v1.0.0 ]]'

new_consumer
release tool v2.0.0 30
release other v2.0.0 1
run_hook --freeze --min-age-days 7
check "--min-age-days reads the tag from a frozen comment" '[[ "$(rev_of tool)" =~ frozen:\ v2.0.0$ && "$(rev_of other)" == v1.0.0 ]]'

new_consumer
run_hook --fail-on-update
check "--fail-on-update fails and leaves the bump unstaged" '[[ $status -ne 0 && "$(rev_of tool)" == v2.0.0 ]] && ! git diff --quiet && git diff --cached --quiet'

new_consumer
run_hook
git commit -qm bump
run_hook --fail-on-update
check "--fail-on-update passes when nothing changes" '[[ $status -eq 0 ]]'

new_consumer
release tool v2.0.0 1
release other v2.0.0 1
run_hook --fail-on-update --min-age-days 7
check "--fail-on-update passes when every bump is held" '[[ $status -eq 0 ]] && git diff --quiet'

new_consumer
run_hook --min-age-days abc
check "rejects a non-numeric --min-age-days" '[[ $status -eq 1 ]]'

new_consumer
run_hook --min-age-days 3 --bleeding
check "rejects --min-age-days with --bleeding-edge, even abbreviated" '[[ $status -eq 1 ]] && grep -q "combined with --bleeding-edge" "$WORK/out"'

new_consumer
set_config <<CONFIG
repos:
  - repo: $WORK/remotes/acme/tool
    rev: v1.0.0
    hooks:
      - id: noop
  - hooks:
      - id: noop
    rev: v1.0.0
    repo: $WORK/remotes/acme/other
CONFIG
release tool v2.0.0 30
release other v2.0.0 1
run_hook --min-age-days 7
check "--min-age-days finds repo: after rev: in the same entry" '[[ "$(grep -B1 acme/other .pre-commit-config.yaml | sed -n "s/^ *rev: *//p")" == v1.0.0 && "$(rev_of tool)" == v2.0.0 ]]'

for args in "--min-age-days 7" "--freeze --min-age-days 7"; do
    new_consumer
    set_config <<CONFIG
repos:
  - repo: $WORK/remotes/acme/hashy
    rev: v1.0.0
    hooks:
      - id: noop
CONFIG
    release hashy v2.0.0 30
    # shellcheck disable=SC2086
    run_hook $args
    check "$args holds a tag with # in it" '[[ "$(rev_of hashy)" == v1.0.0 ]] && grep -q "no release date for v2.0.0#evil" "$WORK/out"'
done

new_consumer
first_sha="$(git -C "$WORK/remotes/acme/moved" rev-parse v2.0.0)"
set_config <<CONFIG
repos:
  - repo: $WORK/remotes/acme/moved
    rev: $first_sha  # frozen: v2.0.0
    hooks:
      - id: noop
CONFIG
git -C "$WORK/remotes/acme/moved" commit -qm moved --allow-empty
git -C "$WORK/remotes/acme/moved" tag -f -a v2.0.0 -m moved >/dev/null
release moved v2.0.0 30
run_hook --freeze --min-age-days 7
check "--min-age-days holds a frozen tag that moved" '[[ "$(rev_of moved)" == "$first_sha  # frozen: v2.0.0" ]] && grep -q "now points to a different commit" "$WORK/out"'

new_consumer
set_config <<CONFIG
repos:
  - repo: $WORK/remotes/acme/tool
    rev: v2.0.0
    hooks:
      - id: noop
CONFIG
release tool v2.0.0 1
run_hook --freeze --min-age-days 7
check "--freeze converts the current tag to its SHA without an age check" '[[ "$(rev_of tool)" =~ ^[0-9a-f]{40}\ \ \#\ frozen:\ v2.0.0$ ]]'

new_consumer
printf 'repos:\n  - repo: %s\n    rev: v1.0.0\n    hooks:\n      - id: noop' "$WORK/remotes/acme/tool" | set_config
release tool v2.0.0 1
run_hook --min-age-days 7 --fail-on-update
check "a held bump leaves a config with no trailing newline unchanged" '[[ $status -eq 0 ]] && git diff --quiet'

new_consumer
printf 'repos:\r\n  - repo: %s\r\n    rev: "v1.0.0"\r\n    hooks:\r\n      - id: noop\r\n' "$WORK/remotes/acme/tool" | set_config
release tool v2.0.0 30
run_hook --min-age-days 7
check "takes an old release for a quoted rev in a CRLF file" '[[ "$(rev_of tool)" == *v2.0.0* && "$(grep -c "$(printf "\r")\$" .pre-commit-config.yaml)" -eq 5 ]]'

new_consumer
release tool v2.0.0 30
run_hook --min-age-days 7
check "holds a repo with no release and takes one with an old release" '[[ "$(rev_of tool)" == v2.0.0 && "$(rev_of other)" == v1.0.0 ]]'

new_consumer
run_hook --interval-hours 24 --min-age-days 7
release tool v2.0.0 30
release other v2.0.0 30
run_hook --interval-hours 24 --min-age-days 7
check "--interval-hours retries after a missing release date" '[[ "$(rev_of tool)" == v2.0.0 ]]'

new_consumer
run_hook --interval-hours 24
git reset -q && git checkout -q -- .pre-commit-config.yaml
run_hook --interval-hours 24
check "--interval-hours skips a second run" '[[ "$(rev_of tool)" == v1.0.0 ]]'

echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
