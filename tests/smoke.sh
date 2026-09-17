#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$root/autofetch.sh"
grep -q '^id = "herdr-autofetch"$' "$root/herdr-plugin.toml"
grep -q '^id = "list"$' "$root/herdr-plugin.toml"
grep -q '^id = "fetch-now"$' "$root/herdr-plugin.toml"
grep -q '^id = "tick"$' "$root/herdr-plugin.toml"

printf 'smoke tests passed\n'
