# vscode-search-provider

[![CI](https://github.com/jannik-el/vscode-search-provider/actions/workflows/ci.yml/badge.svg)](https://github.com/jannik-el/vscode-search-provider/actions/workflows/ci.yml)

A GNOME Shell search provider that shows recently opened VS Code folders and
workspaces in the overview and in Search Light, and opens them in VS Code.

It is a standalone D-Bus service (`org.gnome.Shell.SearchProvider2`), not a
GNOME Shell extension. D-Bus starts it on the first search; it exits after two
idle minutes. Nothing runs in the background otherwise.

- Bus name: `io.github.jannik_el.VSCodeSearchProvider`
- Object path: `/io/github/jannik_el/VSCodeSearchProvider`

## Compatibility

| GNOME Shell | Status |
| --- | --- |
| 50 | Tested (Ubuntu, Wayland, snap VS Code, GLib 2.88, gjs 1.88) |
| 46–49 | Expected to work, not tested |
| 45 and older | Not supported |

The lower bound comes from the `gi://GioUnix` import, which needs GLib 2.80
(GNOME 46, Ubuntu 24.04). The `org.gnome.Shell.SearchProvider2` interface
itself hasn't changed in years. The `.deb` encodes this as
`Depends: gjs (>= 1.80), gir1.2-glib-2.0 (>= 2.80), gnome-shell (>= 46)`.

## How it finds projects

This VS Code build keeps no `history.recentlyOpenedPathsList`, so recents come
from `~/.config/Code/User/workspaceStorage/*/workspace.json` (also
`Code - Insiders` and `VSCodium`), ranked by the mtime of each workspace's
`state.vscdb`. Folders that no longer exist are skipped; `vscode-remote://`
entries are kept. Every search term must match the folder name or path
(case-insensitive). Results open through the VS Code `.desktop` file.

## Install

### From the apt repository (recommended)

A signed apt repository on GitHub Pages carries every release, so
`apt upgrade` keeps the provider up to date:

```sh
sudo curl -fsSLo /usr/share/keyrings/vscode-search-provider.gpg \
  https://jannik-el.github.io/vscode-search-provider/vscode-search-provider.gpg
printf '%s\n' 'Types: deb' \
  'URIs: https://jannik-el.github.io/vscode-search-provider/' \
  'Suites: ./' \
  'Signed-By: /usr/share/keyrings/vscode-search-provider.gpg' |
  sudo tee /etc/apt/sources.list.d/vscode-search-provider.sources
sudo apt update
sudo apt install vscode-search-provider
```

apt checks the repository's signature and every package's SHA256 on each
update. To check the key itself, compare the fingerprint from
`gpg --show-keys /usr/share/keyrings/vscode-search-provider.gpg` with
`gpg --show-keys vscode-search-provider.asc` in this repo:
`A384 C9D2 3628 1BEF 997C  DE52 E4EF D9E4 77DA 917E`. Then **log out and back
in once**.

### From a release

Each [GitHub Release](https://github.com/jannik-el/vscode-search-provider/releases)
has the `.deb`, a `SHA256SUMS` file and a signed build provenance
attestation. Download, verify, install:

```sh
VERSION=1.0.0
BASE=https://github.com/jannik-el/vscode-search-provider/releases/download/v$VERSION
curl -fLO "$BASE/vscode-search-provider_${VERSION}_all.deb" -fLO "$BASE/SHA256SUMS"
sha256sum -c SHA256SUMS
gh attestation verify "vscode-search-provider_${VERSION}_all.deb" --repo jannik-el/vscode-search-provider
sudo apt install "./vscode-search-provider_${VERSION}_all.deb"
```

`sha256sum -c` checks the file arrived intact. The optional `gh attestation
verify` also proves it was built by this repo's release workflow from the
tagged commit. Then **log out and back in once**.

### From source

```sh
make install
```

This builds `build/vscode-search-provider_<version>_all.deb`, installs it with
`sudo apt install`, and then removes the files of the old pre-package install
(`local.vscode.SearchProvider`), if present. Then **log out and back in once**.

To only build the package: `make deb`.

### Why it needs sudo

GNOME Shell 50 reads search-provider `.ini` files only from the system data
dirs (`/usr/share`, `/usr/local/share`), never from `~/.local/share`
(`remoteSearch.js` calls `collectFromDatadirs('search-providers', false)`). So
at least the `.ini` has to be installed as root, and a `.deb` is the cleanest
way to do that. The package installs:

| File | Purpose |
| --- | --- |
| `/usr/share/vscode-search-provider/searchProvider.js` | the gjs service |
| `/usr/share/dbus-1/services/io.github.jannik_el.VSCodeSearchProvider.service` | D-Bus activation |
| `/usr/share/gnome-shell/search-providers/io.github.jannik_el.VSCodeSearchProvider.search-provider.ini` | registers the provider with GNOME Shell |

### When a re-login is needed

GNOME Shell reads the provider list at login. Log out and in after the first
install, and after any change to the `.ini` (bus name, object path, desktop
id). Updating only `searchProvider.js` (a new package version) needs no
re-login: the next search starts the new code once the old process has exited
(up to two minutes, or `pkill -f vscode-search-provider/searchProvider.js`).

## Uninstall

```sh
make uninstall
```

Then log out and back in to drop the (now empty) provider from the shell.

## Non-snap VS Code

The `.ini` names the app whose icon and name GNOME shows. The default is the
snap's `code_code.desktop`. For the Microsoft `.deb`/apt build:

```sh
make clean install DESKTOP_ID=code.desktop
```

## Search order

GNOME lists providers in `org.gnome.desktop.search-providers sort-order`. To
put VS Code first:

```sh
gsettings get org.gnome.desktop.search-providers sort-order
```

and add `'code_code.desktop'` at the front with `gsettings set`.

## Versioning

The project follows [Semantic Versioning](https://semver.org). The version
lives in [`VERSION`](VERSION) and goes into the package name and metadata.
Changes are listed in [`CHANGELOG.md`](CHANGELOG.md).

- **Major:** anything that needs a re-login or breaks existing setups, such as
  a new bus name or object path, or dropping a GNOME version.
- **Minor:** new features, such as new result sources or settings.
- **Patch:** fixes that leave the D-Bus interface and installed paths alone.

To release: bump `VERSION`, add a `CHANGELOG.md` entry, commit, then

```sh
make release
git push origin main v$(cat VERSION)
```

`make release` refuses to tag without a changelog entry or with uncommitted
changes. Pushing the tag runs the release workflow, which checks the tag
matches `VERSION`, builds and tests the package, and publishes the GitHub
Release with the `.deb`, `SHA256SUMS`, the changelog entry as notes and an
attestation. It then downloads the packages of all releases, checks each
against its `SHA256SUMS`, rebuilds the apt repository with
[`tools/apt-repo.sh`](tools/apt-repo.sh), signs it, and deploys it to GitHub
Pages. Running the Release workflow by hand only re-publishes the apt repo.

The apt repo needs a one-time setup by the maintainer:
[`tools/setup-apt-signing.sh`](tools/setup-apt-signing.sh) creates the signing
key, stores it as the `APT_SIGNING_KEY` secret, writes the public key to
`vscode-search-provider.asc` (commit it), and switches Pages to deploy from
Actions.

## Testing

```sh
make check
```

builds the package and runs [`tests/smoke.sh`](tests/smoke.sh) against both
the source and the packaged script. The test starts a private session bus
with no service directories, so it never touches the real bus or an
installed copy. It feeds a fake `workspaceStorage` and checks search, ranking,
multi-term matching, skipping of missing folders, and result metas.

[CI](.github/workflows/ci.yml) runs `make check` on every push and pull request
in Ubuntu 24.04 (GNOME 46, the oldest supported) and 26.04 (GNOME 50)
containers, and checks the package's dependencies resolve there.

To poke at it by hand, run the service from the source tree (stop an
installed instance first) and query it:

```sh
make run
gdbus call --session --dest io.github.jannik_el.VSCodeSearchProvider \
  --object-path /io/github/jannik_el/VSCodeSearchProvider \
  --method org.gnome.Shell.SearchProvider2.GetInitialResultSet "['seal']"
```
