# Checkmk for Omarchy

A bar widget for the Omarchy shell that keeps an eye on one or more Checkmk servers.

- The bar icon takes the colour of the worst unhandled problem: amber for WARN,
  orange for UNKNOWN, red for CRIT.
- A popup lists hosts and problems, with service details, metrics and history graphs.
- A desktop notification is sent whenever a service changes state.

Requires Checkmk 2.2 or newer, plus `curl` and `jq`, and `keyutils` or
`secret-tool` to keep the secret.

## Install

```bash
omarchy plugin add https://github.com/jimjonesbr/omarchy-checkmk.git --enable
```

In Checkmk, create a user for the widget under *Setup › Users*, with the role
*Guest user* (read-only) and an *Automation secret*. Then click the grey icon in
the bar, fill in URL, user and secret, *Test connection* and *Save*.

More servers can be added under the gear icon in the panel.

## Remove

Forget the stored secrets first, then remove the plugin and its settings:

```bash
~/.config/omarchy/plugins/jimjonesbr.checkmk/bin/checkmk-config lock
omarchy plugin remove jimjonesbr.checkmk
rm -rf ~/.config/omarchy-checkmk ~/.cache/omarchy-checkmk
```

## Usage

Left click opens the panel, middle click polls now, right click opens Checkmk.

| Key               | Action                                           |
|-------------------|--------------------------------------------------|
| `j` / `k`         | move                                             |
| `enter` / `l`     | open host, show service details, open in Checkmk |
| `h` / `backspace` | back                                             |
| `1` / `2`         | hosts / problems                                 |
| `g`               | service history: 4h, 25h, 1w, 1m, off            |
| `a`               | problems only / all services                     |
| `o`               | open in Checkmk                                  |
| `s`               | servers                                          |
| `r`               | poll now                                         |

Acknowledged problems and problems in downtime are shown dimmed and neither
colour the icon nor notify.

From a terminal or a Hyprland keybinding:

```bash
omarchy-shell checkmk show hosts    # or problems, servers, host:NAME
omarchy-shell checkmk refresh
```

## Settings

The widget settings in `~/.config/omarchy/shell.json` are `refreshIntervalSec`
(default 60), `notifications` and `icon` (any Nerd Font glyph).

The servers are kept in `~/.config/omarchy-checkmk/servers.json` (see
`servers.example.json`). If the Checkmk site id is not the last part of the URL,
add `"site": "<id>"` to that server.

By default the password is never saved: the widget asks for it after each login
and keeps it in kernel memory only, for 8 hours (`sessionHours`). With *Remember
password* it goes to the desktop keyring for 30 days (`rememberDays`). Anything
running in your session can read it there, and with autologin the keyring is a
plain file, so only remember the password of a read-only account. Either way,
`lock` in the server list forgets it right away.

## Development

`deploy-checkmk/` starts a disposable Checkmk in podman with fake hosts:

```bash
deploy-checkmk/checkmk.sh up       # http://localhost:8080/cmk/ (cmkadmin/cmkadmin)
deploy-checkmk/lab-hosts.sh sync   # hosts from deploy-checkmk/fixtures/
deploy-checkmk/lab-hosts.sh state vm-db02 "Replication Check - pg-hr" 2
```

The read-only API user is `omarchy`, with its secret in `deploy-checkmk/omarchy.secret`.
`CMK_LAB=staging CMK_WEB_PORT=8081` runs a second instance from `fixtures-staging/`.

After changing the code, run `omarchy-restart-shell`.
