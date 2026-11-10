# Changelog

All notable changes to `modulize` are documented in this file.

## [0.3.0] - 2026-11-10

### Added

- `modulize bump [patch|minor|major|<version>]` to increment semver and
  `versionCode`, synchronize `update.json` (`zipUrl`), and prepend release
  entries to `CHANGELOG.md`.
- `modulize add <component>` to add modular components into existing modules
  (`webui`, `post-fs-data`, `action`, `service`, `cli`, `uninstall`, `system.prop`,
  `workflow`).
- `modulize doctor --fix` for automated remediation: repairs CRLF line endings,
  restores executable permissions on scripts, and fixes metadata drift in
  `update.json`.
- `modulize lint` pre-flight command to validate shell script syntax (`bash -n`),
  JSON syntax, template placeholders, and line endings.
- Expanded automated smoke test suite to 145 passing assertions.

## [0.2.0] - 2026-11-10

### Changed

- Renamed the project, repository, and CLI from `raff-module` to `modulize`.
- Installed binary is now `~/.local/bin/modulize`.
- Runtime payload is now `~/.local/share/modulize`.
- Version environment variable is now `MODULIZE_VERSION`.
- The old `Raffxzr/raff-module` GitHub URL redirects to `Raffxzr/modulize`.

## [0.1.0] - 2026-11-10

### Added

- `raff-module init` with interactive and flag-driven scaffolding.
- `minimal`, `standard`, and `full` module profiles.
- Magisk / KernelSU / APatch templates:
  `module.prop`, `customize.sh`, `update.json`, `build.sh`, installer,
  service/action/uninstall hooks, CLI stub, and WebUI skeleton.
- GitHub Actions templates for build artifacts and tag-driven releases.
- `raff-module build` and `raff-module doctor` commands.
- End-to-end smoke test suite with 80+ assertions.
- `make install` installer for `~/.local` or a custom `PREFIX`.

### Fixed

- Generated build workflow follows the `--branch` value instead of hardcoding
  `main`.
- `doctor` accepts nested branch names such as `feature/demo`.
- `init` preserves CamelCase when deriving a module id from the directory name.
- `init` rejects a target path that exists but is not a directory.
- GitHub owner detection no longer blocks scaffolding when `gh` is slow or
  offline.
- Generated release workflow passes metadata through step environment variables
  and validates that `versionCode` is numeric.
