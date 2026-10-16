# Checkmk for Omarchy

Bar widget for the Omarchy shell that shows the worst state of selected Checkmk
services, lists hosts and problems in a popup and sends a desktop notification
whenever a service changes state. It watches any number of Checkmk servers.

## Setup

1. In Checkmk, create a user for the widget under *Setup › Users*: role *Guest user*
   (read-only, sees all hosts) and authentication option *Automation secret*.
2. Install and enable the widget:

   ```bash
   ln -s "$PWD" ~/.config/omarchy/plugins/jimjonesbr.checkmk
   omarchy-shell shell rescanPlugins
   omarchy plugin enable jimjonesbr.checkmk
   ```

3. Click the (grey) icon in the bar. The panel opens the form for a first server:
   name, site URL, user, secret and optional filters. *Test connection*, then *Save*.

More servers are added under the gear icon in the panel (or `s`): the server list
shows each server with its state, `enter` edits one, `n` adds one, `x` twice
removes one.

The servers are stored in `~/.config/omarchy-checkmk/servers.json` (see
`servers.example.json`), the secrets in the desktop keyring (Secret Service, e.g.
gnome-keyring, label "Checkmk user@url"). Without a keyring a secret goes to
`~/.config/omarchy-checkmk/secrets/<id>`, readable only by you. The widget hands
secrets to `bin/checkmk-config` over stdin, so they never show up in the process
list. The single server `config` file of earlier versions is migrated on first use.

## Usage

| Bar icon     | Meaning                                         |
|--------------|-------------------------------------------------|
| normal color | no unhandled problems                           |
| amber        | worst unhandled problem is WARN (orange: UNKNOWN) |
| red          | at least one unhandled CRIT                     |
| dimmed       | no server reachable, showing last known state   |

Left click opens the panel, middle click polls now, right click opens the Checkmk web UI.

The panel has two tabs:

- **Hosts**: one row per host, coloured by its worst service like in Checkmk
  (green, amber, orange, red), with the number of services per state. Open a
  host to see all of its services.
- **Problems**: every service that is not OK, worst first, across all hosts.

With more than one server the hosts are grouped by server. A server that does not
answer keeps its last known state, dimmed and marked as unreachable, and you get a
notification when it goes away and when it comes back.

Selecting a service shows its full output and its metrics; hovering a value shows
its warn and crit levels. Pressing enter again opens the service in Checkmk.

Below the metrics, the *History* buttons (4h, 25h, 1w, 1m) load the history of
the metrics from Checkmk and draw one graph per metric, with the warn and crit
levels as dashed lines; hovering a graph shows the value at that time. Nothing is
downloaded until a range is picked, a range takes roughly 2 to 12 KB per metric,
and fetched ranges are kept for five minutes. The history needs Checkmk 2.2 or
newer. The site id is taken from the end of the server URL; for setups where it
differs, add `"site": "<id>"` to the server in `servers.json`.

| Key                 | Action                                          |
|---------------------|-------------------------------------------------|
| `j` / `k`           | move the selection                              |
| `enter` / `l`       | open host, show service details, open in Checkmk |
| `h` / `backspace`   | back                                            |
| `1` / `2`           | hosts / problems tab                            |
| `a`                 | problems only / all services                    |
| `g`                 | history of the selected service: 4h, 25h, 1w, 1m, off |
| `o`                 | open the selected host or service in Checkmk    |
| `r`                 | poll now                                        |
| `s`                 | server list                                     |
| `esc`               | close                                           |

From a terminal or a Hyprland keybinding:

```bash
omarchy-shell checkmk show hosts          # or: problems, servers, host:vm-db03, host:staging/stg-web01
omarchy-shell checkmk show "service:staging/stg-web01/Memory@25h"   # a service with its graph
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
| `bin/checkmk-poll`   | queries all servers, writes `~/.cache/omarchy-checkmk/status.json`, notifies |
| `bin/checkmk-config` | lists, tests, saves and removes servers, keeps the secrets  |
| `bin/checkmk-graph`  | fetches the metric history of one service for the graphs    |
| `BarWidget.qml`      | bar icon, runs the poller on a timer, watches the status file |
| `Panel.qml`          | popup with hosts, problems and the server settings          |
| `deploy-checkmk/`    | disposable Checkmk test instances with fake hosts (podman)  |

## Test instance

```bash
deploy-checkmk/checkmk.sh up          # Checkmk on http://localhost:8080/cmk/ (cmkadmin/cmkadmin)
deploy-checkmk/lab-hosts.sh sync      # fake VMs from deploy-checkmk/fixtures/*.txt
deploy-checkmk/lab-hosts.sh state vm-db02 "Replication Check - pg-hr" 2

# A second, independent instance with the hosts in deploy-checkmk/fixtures-staging/
export CMK_LAB=staging CMK_WEB_PORT=8081 CMK_AGENT_PORT=8001
deploy-checkmk/checkmk.sh up          # http://localhost:8081/cmk/
deploy-checkmk/lab-hosts.sh sync
```

Each instance creates the read-only API user `omarchy`; its secret is in
`deploy-checkmk/omarchy.secret` (`omarchy-staging.secret` for the second one).
