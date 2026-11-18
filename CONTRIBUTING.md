# Contributing

Thanks for helping out! This file is for working on the plugin itself. To just
use it, the [README](README.md) is all you need.

Bugs and ideas are welcome in the
[issues](https://github.com/jimjonesbr/omarchy-checkmk/issues).

## A Checkmk to test against

You don't need a real Checkmk server to work on the widget. `deploy-checkmk/`
starts a throwaway one in a [podman](https://podman.io) container, filled with
fake hosts. Nothing has to be installed besides podman.

```bash
deploy-checkmk/checkmk.sh up       # start it: http://localhost:8080/cmk/ (cmkadmin/cmkadmin)
deploy-checkmk/lab-hosts.sh sync   # add the fake hosts from deploy-checkmk/fixtures/
```

To connect the widget, use the URL above, the user `omarchy` and the secret
printed by `deploy-checkmk/checkmk.sh secret`.

To see how the widget reacts to a problem, change the state of a service
(0 = OK, 1 = WARN, 2 = CRIT, 3 = UNKNOWN):

```bash
deploy-checkmk/lab-hosts.sh state vm-db02 "Replication Check - pg-hr" 2
```

When you are done, `deploy-checkmk/checkmk.sh down` stops it (the data is kept)
and `deploy-checkmk/checkmk.sh purge` removes it completely. The header of each
script lists all its commands.

To test with several servers, a second instance with the hosts from
`fixtures-staging/` runs next to the first one:

```bash
CMK_LAB=staging CMK_WEB_PORT=8081 CMK_AGENT_PORT=8001 deploy-checkmk/checkmk.sh up
CMK_LAB=staging CMK_WEB_PORT=8081 deploy-checkmk/lab-hosts.sh sync
```

## Trying your changes

After changing the code, run `omarchy-restart-shell` to reload the widget.

## Releasing a new version

The version lives only in `manifest.json`; the panel's about page reads it from
there. It follows [semantic versioning](https://semver.org): raise PATCH for
fixes, MINOR for new features, MAJOR for changes that break existing setups
(e.g. `servers.json`). While the plugin is in beta, versions carry a `-beta.N`
suffix (`0.4.0-beta.1`, `0.4.0-beta.2`, …); the first stable release is `1.0.0`.

```bash
jq '.version = "0.4.0-beta.2"' manifest.json > manifest.tmp && mv manifest.tmp manifest.json
omarchy plugin validate .
git commit -am "Release 0.4.0-beta.2"
git tag -a v0.4.0-beta.2 -m "0.4.0-beta.2"
git push && git push --tags
```

Installed plugins pick it up with `omarchy plugin update`. A marketplace listing
stays on its approved commit until the update is submitted through the
[plugin verification form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=verify-plugin.yml)
with the full commit hash (`git rev-parse HEAD`).
