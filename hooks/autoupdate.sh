#!/usr/bin/env bash
# Auto-update pre-commit hooks and stage changes for commit
#
# This hook runs `pre-commit autoupdate` and stages any changes to
# .pre-commit-config.yaml so they are included in the current commit.
#
# Hook args:
#   --interval-hours N  Skip the update if it ran in the last N hours.
#   --min-age-days N    Keep a hook's current rev until the GitHub release for
#                       its new tag is at least N days old. Anything unknown
#                       (no release, API error, moved tag) keeps the current rev.
#   --fail-on-update    Fail the commit when a rev is bumped, and leave the bump
#                       unstaged for review.
#   Anything else is passed through to `pre-commit autoupdate`
#   (e.g. --freeze, --repo URL, --jobs N).
#
# Env:
#   PCA_GITHUB_API      API base for hook repos not on github.com, such as
#                       GitHub Enterprise (https://github.example.com/api/v3).
#   GITHUB_TOKEN or GH_TOKEN  Sent to an https API when set.

set -euo pipefail

CONFIG_FILE=".pre-commit-config.yaml"
DEFAULT_JOBS=8

interval_hours=0
min_age_days=0
fail_on_update=false
bleeding_edge=false
jobs_set=false
unknown_hold=false
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
        --min-age-days)
            min_age_days="${2:?--min-age-days requires a value}"
            shift 2
            ;;
        --min-age-days=*)
            min_age_days="${1#*=}"
            shift
            ;;
        --fail-on-update)
            fail_on_update=true
            shift
            ;;
        -j | --jobs | -j* | --jobs=*)
            jobs_set=true
            autoupdate_args+=("$1")
            shift
            ;;
        *)
            # pre-commit accepts abbreviations such as --bleeding.
            [[ "$1" == --b* ]] && bleeding_edge=true
            autoupdate_args+=("$1")
            shift
            ;;
    esac
done

for value in "$interval_hours" "$min_age_days"; do
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo "--interval-hours and --min-age-days take a whole number, got: $value" >&2
        exit 1
    fi
done

# --bleeding-edge revs are untagged commits, so they have no release date.
if [[ "$min_age_days" -gt 0 && "$bleeding_edge" == true ]]; then
    echo "--min-age-days can't be combined with --bleeding-edge" >&2
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

# Prints a YAML scalar's value from the text after its `key:`, without quotes
# or a trailing comment.
yaml_value() {
    local text="$1"
    text="${text#"${text%%[![:space:]]*}"}"
    case "$text" in
        \"*) text="${text#\"}" && echo "${text%%\"*}" ;;
        \'*) text="${text#\'}" && echo "${text%%\'*}" ;;
        *) echo "${text%%[[:space:]]*}" ;;
    esac
}

# Prints the tag in a rev line's `# frozen: <tag>` comment, if any.
frozen_tag() {
    if [[ "$1" =~ [[:space:]]\#[[:space:]]*frozen:[[:space:]]*([^[:space:]]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Prints the tag a rev line pins: the frozen comment's tag, else the rev value.
line_tag() {
    local tag
    tag="$(frozen_tag "$1")"
    [[ -n "$tag" ]] || tag="$(yaml_value "${1#*rev:}")"
    echo "$tag"
}

is_rev_line() {
    [[ "$1" =~ ^[[:space:]]*(-[[:space:]]+)?rev: ]]
}

# Prints the repo: value of the list item holding new_lines[$1], or nothing if
# the item doesn't have exactly one. Keys may come in any order.
item_repo() {
    local rev_line="${new_lines[$1]}" prefix key_col start dash_col end i line lead count=0 url=""
    prefix="${rev_line%%rev:*}"
    key_col=${#prefix}
    start=$1
    if [[ "$prefix" != *-* ]]; then
        while ((start > 0)); do
            start=$((start - 1))
            line="${new_lines[start]}"
            [[ "$line" =~ ^[[:space:]]*(\#.*)?$ ]] && continue
            lead="${line%%[![:space:]]*}"
            ((${#lead} < key_col)) && break
        done
    fi
    lead="${new_lines[start]%%[![:space:]]*}"
    dash_col=${#lead}
    end=$((start + 1))
    while ((end < ${#new_lines[@]})); do
        line="${new_lines[end]}"
        lead="${line%%[![:space:]]*}"
        if [[ ! "$line" =~ ^[[:space:]]*(\#.*)?$ ]] && ((${#lead} <= dash_col)); then
            break
        fi
        end=$((end + 1))
    done
    for ((i = start; i < end; i++)); do
        line="${new_lines[i]}"
        if [[ "$line" =~ ^[[:space:]]*(-[[:space:]]+)?repo: ]]; then
            prefix="${line%%repo:*}"
            if ((${#prefix} == key_col)); then
                count=$((count + 1))
                url="$(yaml_value "${line#*repo:}")"
            fi
        fi
    done
    ((count == 1)) && echo "$url"
    return 0
}

# Prints "<api base> <owner/repo>": api.github.com for github.com repos, else
# PCA_GITHUB_API when set.
repo_api() {
    local url="${1%/}"
    url="${url%.git}"
    local name="${url##*/}" rest="${url%/*}"
    local owner="${rest##*[/:]}"
    [[ -n "$name" && -n "$owner" && "$rest" != "$url" ]] || return 1
    if [[ "$url" =~ ^(https://|http://|ssh://git@|git@)github\.com[:/] ]]; then
        echo "https://api.github.com $owner/$name"
    elif [[ -n "${PCA_GITHUB_API:-}" ]]; then
        echo "$PCA_GITHUB_API $owner/$name"
    else
        return 1
    fi
}

# Percent-encodes everything except unreserved URL characters.
url_encode() {
    local LC_ALL=C s="$1" out="" c i
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in
            [A-Za-z0-9._~-]) out+="$c" ;;
            *) out+="$(printf '%%%02X' "'$c")" ;;
        esac
    done
    echo "$out"
}

# Prints the published_at time of the release for a tag. Prints nothing when
# there's no release, the request fails, the response is for another tag, or
# the time isn't ISO 8601.
release_published_at() {
    local api="$1" slug="$2" tag="$3" token="" json tag_name published
    local auth=()
    [[ "$api" == https://* ]] && token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    [[ -n "$token" ]] && auth=(-H "Authorization: Bearer $token")
    json="$(curl -fsSLg --max-time 10 --proto '=https,file' \
        -H "Accept: application/vnd.github+json" ${auth[@]+"${auth[@]}"} \
        "$api/repos/$slug/releases/tags/$(url_encode "$tag")" 2>/dev/null || true)"
    tag_name="$(printf '%s\n' "$json" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
    published="$(printf '%s\n' "$json" | sed -n 's/.*"published_at": *"\([^"]*\)".*/\1/p' | head -n 1)"
    [[ "$tag_name" == "$tag" ]] || return 0
    [[ "$published" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 0
    echo "$published"
}

# Prints the UTC time N days ago as an ISO 8601 string (GNU or BSD date).
days_ago_iso() {
    local since=$(($(date -u +%s) - $1 * 86400))
    date -u -d "@$since" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
        date -u -r "$since" +%Y-%m-%dT%H:%M:%SZ
}

# Restores the old rev line for each repo whose new tag is too young or
# unknown. pre-commit autoupdate rewrites rev lines in place, so line N of the
# old file matches line N of the new one. Sets unknown_hold when a release
# date couldn't be found, so the next run retries.
hold_young_bumps() {
    local old_file="$1" cutoff line old_line url tag old_tag api_slug published reason i
    local old_lines=() new_lines=() kept=0 newline_at_end=true
    cutoff="$(days_ago_iso "$min_age_days")"
    [[ -z "$(tail -c 1 "$CONFIG_FILE")" ]] || newline_at_end=false

    while IFS= read -r line || [[ -n "$line" ]]; do old_lines+=("$line"); done <"$old_file"
    while IFS= read -r line || [[ -n "$line" ]]; do new_lines+=("$line"); done <"$CONFIG_FILE"
    if [[ ${#old_lines[@]} -ne ${#new_lines[@]} ]]; then
        echo "Config layout changed during autoupdate; keeping every current rev" >&2
        cp "$old_file" "$CONFIG_FILE"
        return
    fi

    for ((i = 0; i < ${#new_lines[@]}; i++)); do
        line="${new_lines[i]}"
        old_line="${old_lines[i]}"
        [[ "$line" == "$old_line" ]] && continue
        # Only rev lines are judged; other rewrites (migrate-config) are undone.
        if ! is_rev_line "$line" || ! is_rev_line "$old_line"; then
            new_lines[i]="$old_line"
            continue
        fi

        url="$(item_repo "$i")"
        tag="$(line_tag "$line")"
        old_tag="$(line_tag "$old_line")"
        reason=""
        if [[ -z "$url" || -z "$tag" ]]; then
            reason="can't tell which repo or tag changed"
        elif [[ "$tag" == "$old_tag" && -n "$(frozen_tag "$old_line")" ]]; then
            reason="tag $tag now points to a different commit"
        elif [[ "$tag" == "$old_tag" ]]; then
            # --freeze converting a tag to its SHA; the version is unchanged.
            reason=""
        else
            published=""
            if api_slug="$(repo_api "$url")"; then
                # shellcheck disable=SC2086 # "<api> <slug>" splits into two args.
                published="$(release_published_at $api_slug "$tag")"
            fi
            if [[ -z "$published" ]]; then
                reason="no release date for $tag"
                unknown_hold=true
            elif [[ "$published" > "$cutoff" ]]; then
                reason="$tag released $published, under $min_age_days days ago"
            fi
        fi

        if [[ -n "$reason" ]]; then
            echo "Holding ${url:-a repo} at its current rev: $reason"
            new_lines[i]="$old_line"
        else
            kept=$((kept + 1))
        fi
    done

    if [[ "$kept" -eq 0 ]]; then
        cp "$old_file" "$CONFIG_FILE"
        return
    fi
    for ((i = 0; i < ${#new_lines[@]}; i++)); do
        if ((i < ${#new_lines[@]} - 1)) || [[ "$newline_at_end" == true ]]; then
            printf '%s\n' "${new_lines[i]}"
        else
            printf '%s' "${new_lines[i]}"
        fi
    done >"$CONFIG_FILE"
}

# Skip if a recent run with the same args finished. The stamp stores the
# args so changing them (e.g. adding --freeze) forces a fresh run.
stamp_file="$(git rev-parse --git-path pre-commit-autoupdate.stamp)"
stamp_key="${autoupdate_args[*]} --min-age-days $min_age_days"
if [[ "$interval_hours" -gt 0 && -f "$stamp_file" ]] &&
    [[ "$(cat "$stamp_file")" == "$stamp_key" ]] &&
    [[ -n "$(find "$stamp_file" -mmin "-$((interval_hours * 60))")" ]]; then
    exit 0
fi

backup_file=""
if [[ "$min_age_days" -gt 0 ]]; then
    backup_file="$(mktemp)"
    trap 'rm -f "$backup_file"' EXIT
    cp "$CONFIG_FILE" "$backup_file"
fi

# Run pre-commit autoupdate
echo "Checking for pre-commit hook updates..."
pre-commit autoupdate "${autoupdate_args[@]}"
if [[ -n "$backup_file" ]] && ! cmp -s "$backup_file" "$CONFIG_FILE"; then
    hold_young_bumps "$backup_file"
fi
# A missing release date may be a rate limit, so retry on the next commit.
if [[ "$unknown_hold" == false ]]; then
    printf '%s' "$stamp_key" >"$stamp_file"
fi

# Stage the config file if it changed, or fail so it's reviewed on its own
if ! git diff --quiet "$CONFIG_FILE" 2>/dev/null; then
    if [[ "$fail_on_update" == true ]]; then
        echo "Pre-commit hooks updated in $CONFIG_FILE. Review the change and commit it on its own." >&2
        exit 1
    fi
    git add "$CONFIG_FILE"
    echo "Pre-commit hooks updated and staged for commit"
fi

exit 0
