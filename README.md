# vscode-search-provider

A GNOME Shell search provider that shows recently opened VS Code folders and
workspaces in the overview and in Search Light, and opens them in VS Code.

It is a standalone D-Bus service (`org.gnome.Shell.SearchProvider2`), not a
GNOME Shell extension. D-Bus starts it on the first search; it exits after two
idle minutes. Nothing runs in the background otherwise.

- Bus name: `io.github.jannik_el.VSCodeSearchProvider`
- Object path: `/io/github/jannik_el/VSCodeSearchProvider`
- Tested on Ubuntu, GNOME Shell 50, Wayland, snap VS Code.

## How it finds projects

This VS Code build keeps no `history.recentlyOpenedPathsList`, so recents come
from `~/.config/Code/User/workspaceStorage/*/workspace.json` (also
`Code - Insiders` and `VSCodium`), ranked by the mtime of each workspace's
`state.vscdb`. Folders that no longer exist are skipped; `vscode-remote://`
entries are kept. Every search term must match the folder name or path
(case-insensitive). Results open through the VS Code `.desktop` file.

## Install

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

## Testing

Run the service from the source tree (stop an installed instance first) and
query it:

```sh
make run
gdbus call --session --dest io.github.jannik_el.VSCodeSearchProvider \
  --object-path /io/github/jannik_el/VSCodeSearchProvider \
  --method org.gnome.Shell.SearchProvider2.GetInitialResultSet "['seal']"
```
