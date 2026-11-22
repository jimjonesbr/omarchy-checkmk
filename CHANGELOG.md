# Changelog

Versions follow [semantic versioning](https://semver.org); during the beta they
carry a `-beta.N` suffix.

## Unreleased

### Security

- Editing a server with the password left empty reused its stored secret even
  when the URL or user had changed, and sent it to the new address with *Test
  connection* or *Save*. A stored secret now only goes to its own site and user;
  for another one the password has to be entered.
- After a change of URL, a server that did not answer kept the old site's
  services, and `g` on one of them asked the new site for its history, sending
  it the old host, service and metric names. Those services are now dropped,
  `g` asks for no history of a stale service, and checkmk-graph refuses a
  service whose link is not below the server's current URL.
- A `servers.json` with a syntax error was taken for an empty one, and saving a
  server replaced it, losing every other server. Now nothing runs until it is
  fixed, and the panel says why.
- The developer lab (`deploy-checkmk/`) published its ports on every network
  interface, with the well-known administrator password `cmkadmin`. It now
  listens on this machine only, a new instance gets a random password, and its
  scripts pass passwords to curl through file descriptors.

## 0.5.0-beta.2 (2026-11-22)

### Security

- A value that goes to curl (site URL, filters, proxy) can no longer add curl
  options of its own, and curl only speaks http and https: a `file://` site
  URL, for instance, is refused.
- A user name or secret with a line break is refused, instead of adding an
  HTTP header to every request.
- The single-server configuration of 0.2.0 is read as text when it is
  migrated; it used to be run as a shell script.
- `servers.json` is written under a lock, so that two changes at the same time,
  e.g. a poll and a save, can no longer leave it broken.

### Changed

- The plugin is called *Checkmk status for Omarchy* (in the bar editor
  *Checkmk status*), so that it reads as a companion to Checkmk rather than
  Checkmk itself, and neither as a Checkmk server nor as an agent that
  monitors this machine. The README and the about page say that it is not
  affiliated with Checkmk GmbH.
- When a remembered password goes to a file because no desktop keyring is
  running, the server form now says so.
- Tests of the config helper's checks (`tests/config.test.js`).

### Fixed

- `omarchy-shell checkmk show …` and a click on a notification opened the
  password prompt instead of the view asked for while a server was locked.

### Removed

- The number of problems next to the bar icon, and its `showCount` setting: at
  a size that fits the bar it is hard to read on some screens, and larger
  counts do not fit. The icon's colour, the tooltip and the panel tell the same.

## 0.5.0-beta.1 (2026-11-20)

### Added

- Servers on a private network can be reached through a tunnel: *Proxy* under
  *Advanced* in the server form, e.g. `localhost:1080` for `ssh -D 1080 jumphost`.
- *Disconnect* and *Connect* a server, in its form or with `d` in the server
  list. A disconnected server is not polled and leaves the icon, the lists and
  the notifications; it keeps its settings and a remembered password. Its dot
  in the server list becomes a ring.
- *Mute notifications* for a server that should be watched but not announced.
- The number of unhandled problems next to the bar icon (setting `showCount`).
- The problems list groups the services by host, the host with the worst
  problem first. Clicking a host's name opens it.
- Clicking a notification opens that service or host in the panel.
- Services whose state Checkmk is still re-checking are marked *soft*.
- The bar icon pulses on an unhandled CRIT (setting `pulseOnCrit`).
- An expanded service shows when it was last checked and how often, and the
  list marks services Checkmk considers stale as *overdue*.
- Clicking a state count on top (CRIT, UNKN, WARN, OK) filters the services by
  that state; `f` cycles through them.
- Server actions show on hover in the server list.
- Tests for the panel logic and the notification rules (`node --test tests/`).

### Changed

- Notifications follow hard states only, as Checkmk's own do: a single failed
  check that clears on the next one stays quiet.
- Host and service names, check output, the site URL and the filters no longer
  appear on any command line, where every local user can read them.
  Notifications go over D-Bus (this needs `python-gobject`, part of Omarchy;
  without it, notifications only count the changes), links open through a
  private page, and curl and jq read their input from streams and files.
- Remembered passwords are filed in the desktop keyring under a salted hash of
  URL and user instead of the plain URL and user. Existing entries move over
  once, the first time the widget runs.
- A password kept in memory only is forgotten when its server is disconnected,
  and *Connect* asks for it first.
- A password typed into a form but not saved is forgotten when the form is left.

### Fixed

- Sites with about a thousand services or more polled forever without result
  ("No data yet"): the status was handed to jq on the command line, which has
  a size limit.
- A host that went straight to DOWN was not announced.
- After pulsing once, the bar icon no longer dimmed while no server answered.

## 0.4.0-beta.1 (2026-10-18)

- An about page with version, author, license and homepage (`i`).
- Fixed state colours, so CRIT looks like CRIT in every theme.
- Passwords are no longer saved by default: they are kept in memory for 8
  hours. *Remember password* keeps one in the desktop keyring for 30 days.
  `lock` forgets it right away.
- The secret goes to curl through a file descriptor, not its command line; the
  server form warns about admin accounts, plain http and disabled certificate
  checks.
- History graphs of a service's metrics (4h, 25h, 1w, 1m).
- Removal instructions and a preview for the marketplace.
- First beta.

## 0.3.0 (2026-10-16)

- Several Checkmk servers, managed in the panel and stored in `servers.json`.
  A server that does not answer keeps its last known state, marked stale. The
  configuration of 0.2.0 is migrated on first use.

## 0.2.0 (2026-10-16)

- First version: the worst state of the Checkmk services as a bar icon, hosts
  and problems in a panel with service details and metrics, and a desktop
  notification when a service changes state.
