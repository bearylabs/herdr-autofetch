# Herdr Git Autofetch

Automatically fetches the Git repositories belonging to open Herdr workspaces.
Linked worktrees and multiple panes from the same repository are deduplicated,
so each repository is fetched only once per run.

The plugin only runs `git fetch`. It does not merge, rebase, switch branches, or
modify working trees.

## Requirements

- Herdr 0.9.1 or newer
- Linux
- Bash 4+
- Git
- `jq`
- util-linux (`flock`)
- GNU coreutils (`timeout`, `sha256sum`)

## Install

```bash
herdr plugin install bearylabs/herdr-autofetch --ref v0.1.0
```

Verify that Herdr loaded the plugin:

```bash
herdr plugin list --plugin herdr-autofetch
herdr plugin action list --plugin herdr-autofetch
```

## Enable periodic fetching

Herdr plugins do not currently have a native timer entrypoint. This plugin uses
Herdr's server-side tab-bar command scheduler instead, so no systemd service or
cron job is required.

Add the following property to the existing `[ui]` section in
`~/.config/herdr/config.toml`:

```toml
tab_bar_right = [
  { type = "command", command = "\"$HERDR_BIN_PATH\" plugin action invoke herdr-autofetch.tick >/dev/null 2>&1", interval_seconds = 180, timeout_seconds = 240 },
]
```

Do not add a second `[ui]` heading if the configuration already contains one.
If `tab_bar_right` already has entries, append the autofetch command:

```toml
tab_bar_right = [
  { type = "zoom" },
  { type = "datetime", format = "%H:%M" },
  { type = "command", command = "\"$HERDR_BIN_PATH\" plugin action invoke herdr-autofetch.tick >/dev/null 2>&1", interval_seconds = 180, timeout_seconds = 240 },
]
```

Validate and reload the configuration:

```bash
herdr config check
herdr server reload-config
```

The command runs immediately and then every three minutes. It produces no tab-bar
text. Scheduled runs skip repositories that were fetched successfully within
the last 150 seconds, preventing redundant fetches from multiple clients or
sessions while leaving enough margin before the next scheduled run.

## Usage

List the repositories Herdr Autofetch currently detects without contacting any
remote:

```bash
herdr plugin action invoke herdr-autofetch.list
```

Fetch all detected repositories immediately, ignoring the recent-fetch guard:

```bash
herdr plugin action invoke herdr-autofetch.fetch-now
```

Inspect recent runs and errors:

```bash
herdr plugin log list --plugin herdr-autofetch --limit 10
```

## Configuration

The default settings are:

```bash
FETCH_TIMEOUT_SECONDS=120
MIN_FETCH_INTERVAL_SECONDS=150
FETCH_ALL_REMOTES=true
PRUNE=true
```

To override them, create `config.sh` in the plugin configuration directory:

```bash
config_dir="$(herdr plugin config-dir herdr-autofetch)"
cat >"$config_dir/config.sh" <<'EOF'
FETCH_TIMEOUT_SECONDS=120
MIN_FETCH_INTERVAL_SECONDS=150
FETCH_ALL_REMOTES=true
PRUNE=true
EOF
```

The file is sourced as shell code and must therefore contain trusted content.
After changing it, no Herdr reload is necessary; the next plugin invocation
uses the new values.

## How repository discovery works

The plugin reads one Herdr API snapshot and considers:

- checkout paths reported for Herdr worktrees
- working directories of open panes
- foreground working directories of open panes

Each path is resolved to its Git top-level directory. Linked worktrees are then
deduplicated using `git rev-parse --git-common-dir`. Repositories without a
configured remote are skipped.

Fetches are non-interactive and have a configurable timeout. Per-repository
locks prevent simultaneous fetches of the same repository.

## Update

Herdr Plugin v1 does not have a separate update command. Install the desired
version again:

```bash
herdr plugin install bearylabs/herdr-autofetch --ref v0.1.1
```

Plugin configuration and state are retained.

## Disable or uninstall

First remove the `herdr-autofetch.tick` command from `tab_bar_right`, then
reload Herdr:

```bash
herdr config check
herdr server reload-config
```

Uninstall the plugin:

```bash
herdr plugin uninstall herdr-autofetch
```
