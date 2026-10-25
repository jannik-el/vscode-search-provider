# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-10-25

### Added

- `org.gnome.Shell.SearchProvider2` D-Bus service listing recent VS Code
  folders and workspaces (from `workspaceStorage`, ranked by last use).
- `.deb` packaging with `make deb`, `make install` and `make uninstall`.
- Bus name `io.github.jannik_el.VSCodeSearchProvider`; `make install` removes
  the files of the earlier unpackaged `local.vscode.SearchProvider` setup.
- D-Bus smoke test (`make check`), CI on Ubuntu 24.04 and 26.04, and a release
  workflow publishing the `.deb` with `SHA256SUMS` and a build attestation.

[1.0.0]: https://github.com/jannik-el/vscode-search-provider/releases/tag/v1.0.0
