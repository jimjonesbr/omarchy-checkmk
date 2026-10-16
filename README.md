# Checkmk for Omarchy

Bar widget for the Omarchy shell that shows the worst state of selected Checkmk
services, lists the problems in a popup and sends a desktop notification
whenever a service changes state.

## Setup

1. In Checkmk, create a user for the widget under *Setup › Users*: role *Guest user*
   (read-only, sees all hosts) and authentication option *Automation secret*.
2. Install and enable the widget:

   ```bash
   ln -s "$PWD" ~/.config/omarchy/plugins/jimjonesbr.checkmk
   omarchy-shell shell rescanPlugins
   omarchy plugin enable jimjonesbr.checkmk
   ```

3. Click the (grey) icon in the bar. The panel opens the connection form: site URL,
   user, secret and optional filters. *Test connection*, then *Save*. The gear icon
   in the panel (or `s`) brings the form back later.

The settings are stored in `~/.config/omarchy-checkmk/config`, the secret in the
desktop keyring (Secret Service, e.g. gnome-keyring, label "Checkmk user@url").
Without a keyring it goes to `~/.config/omarchy-checkmk/secret`, readable only by
you. The widget hands the secret to `bin/checkmk-config` over stdin, so it never
shows up in the process list. Editing the config file by hand still works, see
`config.example`.

## Usage

| Bar icon     | Meaning                                         |
|--------------|-------------------------------------------------|
| normal color | no unhandled problems                           |
| amber        | worst unhandled problem is WARN (orange: UNKNOWN) |
| red          | at least one unhandled CRIT                     |
| dimmed       | Checkmk not reachable, showing last known state |

Left click opens the panel, middle click polls now, right click opens the Checkmk web UI.

The panel has two tabs:

- **Hosts**: one row per host, coloured by its worst service like in Checkmk
  (green, amber, orange, red), with the number of services per state. Open a
  host to see all of its services.
- **Problems**: every service that is not OK, worst first, across all hosts.

Selecting a service shows its full output and its metrics (value, warn and crit
levels); pressing enter again opens it in Checkmk.

| Key                 | Action                                          |
|---------------------|-------------------------------------------------|
| `j` / `k`           | move the selection                              |
| `enter` / `l`       | open host, show service details, open in Checkmk |
| `h` / `backspace`   | back to the host list                           |
| `1` / `2`           | hosts / problems tab                            |
| `a`                 | problems only / all services                    |
| `o`                 | open the selected host or service in Checkmk    |
| `r`                 | poll now                                        |
| `esc`               | close                                           |

From a terminal or a Hyprland keybinding:

```bash
omarchy-shell checkmk show hosts          # or: problems, host:vm-db03
omarchy-shell checkmk toggle
omarchy-shell checkmk refresh
```

Acknowledged problems, problems in downtime and services of hosts that are down
count as handled: they are listed dimmed and neither colour the icon nor notify.
A down host is reported as its own entry.

Refresh interval, notifications and the bar icon (any Nerd Font glyph, default
heart-pulse) can be changed in the widget settings (`refreshIntervalSec`,
`notifications`, `icon` in `~/.config/omarchy/shell.json`).

## Files

| Path               | What                                                       |
|--------------------|------------------------------------------------------------|
| `bin/checkmk-poll` | queries the REST API, writes `~/.cache/omarchy-checkmk/status.json`, notifies |
| `BarWidget.qml`    | bar icon, runs the poller on a timer, watches the status file |
| `Panel.qml`        | popup with the list of problems                            |
| `deploy-checkmk/`  | disposable Checkmk test instance with fake hosts (podman)  |

## Test instance

```bash
deploy-checkmk/checkmk.sh up          # Checkmk on http://localhost:8080/cmk/ (cmkadmin/cmkadmin)
deploy-checkmk/lab-hosts.sh sync      # fake VMs from deploy-checkmk/fixtures/*.txt
deploy-checkmk/lab-hosts.sh state vm-db02 "Replication Check - pg-hr" 2
```
