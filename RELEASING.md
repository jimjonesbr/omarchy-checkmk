# Releasing a new version

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
