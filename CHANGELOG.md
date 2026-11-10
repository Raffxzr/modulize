# Changelog

All notable changes to `raff-module` are documented in this file.

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
