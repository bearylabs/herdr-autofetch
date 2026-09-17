#!/usr/bin/env bash
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr-autofetch}"
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins/config/herdr-autofetch}"

# Defaults can be overridden in $HERDR_PLUGIN_CONFIG_DIR/config.sh.
FETCH_TIMEOUT_SECONDS=120
MIN_FETCH_INTERVAL_SECONDS=150
FETCH_ALL_REMOTES=true
PRUNE=true

if [[ -r "$CONFIG_DIR/config.sh" ]]; then
    # This is deliberately a shell config: plugin configuration is trusted code.
    # shellcheck source=/dev/null
    source "$CONFIG_DIR/config.sh"
fi

usage() {
    printf 'Usage: %s [--force|--if-stale|--dry-run]\n' "${0##*/}" >&2
}

mode="${1:---force}"
case "$mode" in
    --force|--if-stale|--dry-run) ;;
    *) usage; exit 2 ;;
esac

if ! [[ "$FETCH_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    printf 'FETCH_TIMEOUT_SECONDS must be a positive integer\n' >&2
    exit 2
fi
if ! [[ "$MIN_FETCH_INTERVAL_SECONDS" =~ ^[0-9]+$ ]]; then
    printf 'MIN_FETCH_INTERVAL_SECONDS must be a non-negative integer\n' >&2
    exit 2
fi

for dependency in jq git flock timeout sha256sum; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        printf 'Missing required command: %s\n' "$dependency" >&2
        exit 1
    fi
done

mkdir -p "$STATE_DIR/repos"

if ! snapshot="$("$HERDR" api snapshot)"; then
    printf 'Could not read the Herdr API snapshot\n' >&2
    exit 1
fi

mapfile -t candidates < <(
    jq -r '
      [
        .result.snapshot.workspaces[]?.worktree.repo_root?,
        .result.snapshot.workspaces[]?.worktree.checkout_path?,
        .result.snapshot.panes[]?.cwd?,
        .result.snapshot.panes[]?.foreground_cwd?
      ]
      | map(select(type == "string" and length > 0))
      | unique[]
    ' <<<"$snapshot"
)

declare -A seen=()
found=0
fetched=0
skipped=0
failed=0
now="$(date +%s)"

for candidate in "${candidates[@]}"; do
    [[ -d "$candidate" ]] || continue

    checkout="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null)" || continue
    common_dir="$(git -C "$checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || continue

    [[ -z "${seen[$common_dir]+present}" ]] || continue
    seen["$common_dir"]=1
    ((found += 1))

    # Repositories without remotes need no fetch and should not count as errors.
    if [[ -z "$(git -C "$checkout" remote 2>/dev/null)" ]]; then
        printf 'skip (no remotes): %s\n' "$checkout"
        ((skipped += 1))
        continue
    fi

    if [[ "$mode" == "--dry-run" ]]; then
        printf 'would fetch: %s\n' "$checkout"
        continue
    fi

    key="$(printf '%s' "$common_dir" | sha256sum | awk '{print $1}')"
    lock_file="$STATE_DIR/repos/$key.lock"
    stamp_file="$STATE_DIR/repos/$key.last-success"

    exec {lock_fd}>"$lock_file"
    if ! flock -n "$lock_fd"; then
        printf 'skip (already fetching): %s\n' "$checkout"
        exec {lock_fd}>&-
        ((skipped += 1))
        continue
    fi

    if [[ "$mode" == "--if-stale" && -e "$stamp_file" ]]; then
        last_fetch="$(stat -c %Y "$stamp_file" 2>/dev/null || printf '0')"
        if (( now - last_fetch < MIN_FETCH_INTERVAL_SECONDS )); then
            printf 'skip (recently fetched): %s\n' "$checkout"
            flock -u "$lock_fd"
            exec {lock_fd}>&-
            ((skipped += 1))
            continue
        fi
    fi

    fetch_args=(fetch)
    [[ "$FETCH_ALL_REMOTES" == true ]] && fetch_args+=(--all)
    [[ "$PRUNE" == true ]] && fetch_args+=(--prune)

    printf 'fetch: %s\n' "$checkout"
    if GIT_TERMINAL_PROMPT=0 timeout --foreground "${FETCH_TIMEOUT_SECONDS}s" \
        git -C "$checkout" "${fetch_args[@]}"; then
        touch "$stamp_file"
        ((fetched += 1))
    else
        printf 'fetch failed: %s\n' "$checkout" >&2
        ((failed += 1))
    fi

    flock -u "$lock_fd"
    exec {lock_fd}>&-
done

printf 'repositories=%d fetched=%d skipped=%d failed=%d\n' \
    "$found" "$fetched" "$skipped" "$failed"

((failed == 0))
