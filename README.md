# Checkmk for Omarchy

A bar widget for the Omarchy shell that keeps an eye on one or more Checkmk servers.

- The bar icon takes the colour of the worst unhandled problem: amber for WARN,
  orange for UNKNOWN, red for CRIT, with the number of unhandled problems next
  to it. An unhandled CRIT also makes it pulse.
- A popup lists hosts and problems, with service details, metrics and history graphs.
- A desktop notification tells when a service changes state, with the host and
  the check output; clicking it opens that service in the panel. Like Checkmk's
  own notifications, it waits until Checkmk has confirmed the state (a hard
  state), so a single failed check that clears on the next one stays quiet. More
  than five changes at once come as one summary.

Requires Checkmk 2.2 or newer, plus `curl`, `jq` and `python-gobject` (all part
of Omarchy), and `keyutils` or `secret-tool` to keep the secret. Without
`python-gobject`, notifications only count the changes.

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
version may need changes to your setup (e.g. `servers.json`). During the beta,
versions carry a `-beta.N` suffix. [CHANGELOG.md](CHANGELOG.md) lists what
changed.

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
| `n`               | in the server list: add a server                 |
| `x`               | in the server list: remove, press twice          |
| `d`               | in the server list: disconnect or connect        |
| `u`               | in the server list: lock or unlock               |
| `i`               | about: version, author, license                  |
| `r`               | poll now                                         |

The problems list groups the services by host, the host with the worst problem
first. Clicking a host's name opens it.

Clicking one of the counts on top (CRIT, UNKN, WARN, OK) shows only the
services in that state, clicking it again shows all. Inside a host the counts
are those of the host.

Acknowledged problems and problems in downtime are shown dimmed and neither
colour the icon nor notify.

A server can be disconnected for a while, with *Disconnect* in its form or `d`
in the server list: it is no longer polled and leaves the icon, the lists and
the notifications. It keeps its settings and a remembered password; a password
kept in memory only is forgotten. *Connect* brings the server back and asks for
a forgotten password first. While no server is connected, the icon is grey.
*Mute notifications* in the form keeps a server polled and shown, but silences
its notifications.

A service whose state Checkmk is still re-checking is marked *soft*.

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
(default 60), `notifications`, `pulseOnCrit`, `showCount` and `icon` (any Nerd
Font glyph).

The servers are kept in `~/.config/omarchy-checkmk/servers.json` (see
`servers.example.json`). If the Checkmk site id is not the last part of the URL,
add `"site": "<id>"` to that server.

A server on a private network can be reached through a tunnel. Open it, e.g.
with `ssh -D 1080 jumphost`, and under *Advanced* in the server form set
*Proxy* to `localhost:1080`. A bare `host:port` is a SOCKS5 proxy that also looks
up host names through the tunnel (`socks5h://`); use `http://host:port` for an
HTTP proxy. The widget does not open the tunnel itself; while it is down, the
server shows a connection error. Links to Checkmk open in the default browser,
which needs its own way through the tunnel, e.g. a proxy or PAC setting.

By default the password is never saved: the widget asks for it after each login
and keeps it in kernel memory only, for 8 hours (`sessionHours`). With *Remember
password* it goes to the desktop keyring for 30 days (`rememberDays`). Anything
running in your session can read it there, and with autologin the keyring is a
plain file, so only remember the password of a read-only account. Either way,
`lock` in the server list forgets it right away.

## Development

Want to work on the plugin? [CONTRIBUTING.md](CONTRIBUTING.md) explains how to
run a test Checkmk on your machine and how releases are made.
