# Checkmk for Omarchy

A bar widget for the Omarchy shell that keeps an eye on one or more Checkmk servers.

- The bar icon takes the colour of the worst unhandled problem: amber for WARN,
  orange for UNKNOWN, red for CRIT. An unhandled CRIT also makes it pulse.
- A popup lists hosts and problems, with service details, metrics and history graphs.
- A desktop notification tells when services change state, e.g. "2 services
  changed state, now 1 CRIT, 1 OK". Clicking it opens the panel with the details.
  Notifications name no hosts or services: their text is passed on command lines,
  which every local user can read.

Requires Checkmk 2.2 or newer, plus `curl` and `jq`, and `keyutils` or
`secret-tool` to keep the secret.

> **Beta.** This is still under development and not yet ready for production use.
> Expect rough edges, and please report them in the [issues](https://github.com/jimjonesbr/omarchy-checkmk/issues).

## Install

```bash
omarchy plugin add https://github.com/jimjonesbr/omarchy-checkmk.git --enable
```

In Checkmk, create a user for the widget under *Setup › Users*, with the role
*Guest user* (read-only) and an *Automation secret*. Then click the grey icon in
the bar, fill in URL, user and secret, *Test connection* and *Save*.

More servers can be added under the gear icon in the panel.

## Update

```bash
omarchy plugin update
```

Versions follow [semantic versioning](https://semver.org): only a new major
version may need changes to your setup (e.g. `servers.json`). During the beta, versions carry a `-beta.N` suffix.

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
| `f`               | only CRIT, UNKNOWN, WARN or OK services, or all  |
| `o`               | open in Checkmk                                  |
| `s`               | servers                                          |
| `i`               | about: version, author, license                  |
| `r`               | poll now                                         |

Clicking one of the counts on top (CRIT, UNKN, WARN, OK) shows only the
services in that state, clicking it again shows all. Inside a host the counts
are those of the host.

Acknowledged problems and problems in downtime are shown dimmed and neither
colour the icon nor notify.

An expanded service shows when it was last checked and how often. Services that
Checkmk considers stale (no fresh result for 1.5 check intervals) are marked
*overdue*. For asynchronous local checks (e.g. in `local/300/`) the commercial
editions report when the agent produced the cached data. The community edition
only knows the last agent contact, so there the time can be newer than the data.

From a terminal or a Hyprland keybinding:

```bash
omarchy-shell checkmk show hosts    # or problems, servers, about, host:NAME
omarchy-shell checkmk refresh
```

## Settings

The widget settings in `~/.config/omarchy/shell.json` are `refreshIntervalSec`
(default 60), `notifications`, `pulseOnCrit` and `icon` (any Nerd Font glyph).

The servers are kept in `~/.config/omarchy-checkmk/servers.json` (see
`servers.example.json`). If the Checkmk site id is not the last part of the URL,
add `"site": "<id>"` to that server.

A server on a private network can be reached through a tunnel. Open it, e.g.
with `ssh -D 1080 jumphost`, and under *Advanced* in the server form set
*Proxy* to `localhost:1080`. A bare `host:port` is a SOCKS5 proxy that also looks
up host names through the tunnel (`socks5h://`); use `http://host:port` for an
HTTP proxy. *Browser* sets the command that opens this server's links in
Checkmk, e.g. `chromium --proxy-server=socks5://localhost:1080`. Without it,
links go to the default browser. The widget does not open the tunnel itself; while it is down,
the server shows a connection error.

By default the password is never saved: the widget asks for it after each login
and keeps it in kernel memory only, for 8 hours (`sessionHours`). With *Remember
password* it goes to the desktop keyring for 30 days (`rememberDays`). Anything
running in your session can read it there, and with autologin the keyring is a
plain file, so only remember the password of a read-only account. Either way,
`lock` in the server list forgets it right away.

## Development

Want to work on the plugin? [CONTRIBUTING.md](CONTRIBUTING.md) explains how to
run a test Checkmk on your machine and how releases are made.
