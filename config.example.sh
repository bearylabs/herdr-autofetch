# shellcheck shell=bash disable=SC2034
# Copy this file to the directory printed by:
#   herdr plugin config-dir herdr-autofetch
# and name it config.sh.

# Maximum runtime of one repository fetch.
FETCH_TIMEOUT_SECONDS=120

# Suppress scheduled duplicate fetches for this many seconds per repository.
# Manual `fetch-now` actions ignore this value.
MIN_FETCH_INTERVAL_SECONDS=150

# true: fetch every configured remote; false: fetch the default remote.
FETCH_ALL_REMOTES=true

# Pass --prune to git fetch.
PRUNE=true
