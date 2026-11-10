# raff-module

[![CI](https://github.com/Raffxzr/raff-module/actions/workflows/ci.yml/badge.svg)](https://github.com/Raffxzr/raff-module/actions/workflows/ci.yml)

Scaffold production-ready **Magisk / KernelSU / APatch** modules in seconds.

```bash
raff-module init MyModule
```

`raff-module` takes the parts that are identical in every module — installer,
OTA manifest, build script, release automation — and generates them with your
metadata already filled in. The output is a flashable module, not a toy
skeleton: it is extracted from real modules such as
[RaffOptimizer](https://github.com/Raffxzr/RaffOptimizer).

## What you get

```text
MyModule/
├── module.prop                      # identity + in-app OTA endpoint
├── customize.sh                     # SKIPUNZIP installer, API check, permissions
├── update.json                      # OTA manifest (version, zipUrl, changelog)
├── build.sh                         # reproducible flashable zip builder
├── service.sh                       # late_start service hook
├── action.sh                        # root-manager action button
├── uninstall.sh                     # persistent-data cleanup
├── system.prop                      # system property overlay
├── system/bin/MyModule              # CLI stub
├── META-INF/com/google/android/     # Magisk installer
├── .github/workflows/build.yml      # CI: syntax check + zip artifact
├── .github/workflows/release.yml    # tag -> release -> update.json refresh
├── README.md
├── CHANGELOG.md
└── module.include                   # extra zip payload paths
```

## Install the CLI

```bash
git clone https://github.com/Raffxzr/raff-module.git
cd raff-module
make install            # -> ~/.local/bin/raff-module
```

Install system-wide instead:

```bash
sudo make install PREFIX=/usr/local
```

You can also run it directly without installing:

```bash
./raff-module init MyModule
```

Requirements: `bash`, `sed`, `zip`, and `git`. `jq` is used by `doctor` and by
the generated release workflow (preinstalled on GitHub runners).

## Usage

```bash
raff-module init [directory] [options]
raff-module build [directory]
raff-module doctor [directory] [--strict]
raff-module version
```

### Interactive

```bash
raff-module init MyModule
```

You will be asked for the module id, display name, version, author, repo,
branch, minimum SDK, and template profile. Press enter to keep a default.

### Non-interactive

```bash
raff-module init MyModule \
  --id MyModule \
  --name "My Module" \
  --version v1.0.0 \
  --version-code 100 \
  --author Raffxzr \
  --description "What this module does" \
  --repo Raffxzr/MyModule \
  --template full \
  -y
```

### Init options

| Option | Description | Default |
| :--- | :--- | :--- |
| `--id ID` | Module id (letters, digits, `.`, `-`, `_`) | target directory name |
| `--name NAME` | Display name | title-cased id |
| `--version VERSION` | Version tag, must match the release tag | `v0.1.0` |
| `--version-code CODE` | Positive integer `versionCode` | `1` |
| `--author NAME` | Author shown in the installer | `git config user.name` |
| `--description TEXT` | One-line description | generic scaffold text |
| `--repo OWNER/REPO` | GitHub repo used by `update.json` | detected GitHub account |
| `--branch BRANCH` | Branch used by raw URLs and CI | `main` |
| `--min-sdk API` | Minimum Android SDK enforced by the installer | `21` |
| `--template PROFILE` | `minimal`, `standard`, or `full` | `standard` |
| `--no-workflow` | Skip `.github/workflows` | workflows enabled |
| `--no-git` | Skip `git init` | git enabled |
| `--force` | Write into a non-empty directory | refuse |
| `-y`, `--yes` | Accept defaults, never prompt | prompt on a TTY |

### Profiles

| Profile | Adds |
| :--- | :--- |
| `minimal` | `module.prop`, `customize.sh`, `update.json`, `build.sh`, installer, docs, workflows |
| `standard` | minimal + `service.sh`, `action.sh`, `uninstall.sh`, `system.prop`, CLI stub |
| `full` | standard + `post-fs-data.sh` and a ready-to-edit WebUI at `webroot/index.html` |

## Build the generated module

```bash
cd MyModule
./build.sh
# or, from anywhere:
raff-module build MyModule
```

Output: `dist/MyModule-v0.1.0.zip`, with a SHA-256 checksum printed. The build
script refuses CRLF shell scripts, normalises permissions, validates required
installer files, and packages only module payload (never `update.json`, docs,
or dev files).

## Validate a module

```bash
raff-module doctor MyModule
```

`doctor` checks:

- `module.prop` identity and version fields
- `updateJson` is a raw GitHub URL
- `update.json` is valid JSON and matches `version` / `versionCode`
- the OTA zip URL matches `<id>-<version>.zip`
- `CHANGELOG.md` contains the current version
- installer files, build script, and workflows are present
- shell scripts use LF line endings

Use `--strict` in CI if warnings should fail the build.

## Release flow

The generated `release.yml` runs when a tag matching `v*` is pushed:

1. Bump `version` and `versionCode` in `module.prop`.
2. Add a `## [vX.Y.Z]` section to `CHANGELOG.md`.
3. Commit and push to the default branch.
4. Push the tag:

   ```bash
   git tag vX.Y.Z
   git push origin main --tags
   ```

The workflow validates that the tag equals `module.prop`'s `version`, builds the
zip, creates or updates the GitHub release, extracts release notes from
`CHANGELOG.md`, and commits the refreshed `update.json` back to the default
branch.

> The workflow needs permission to push `update.json`. `permissions: contents:
> write` is already set; if your repository or organization restricts the
> `GITHUB_TOKEN`, allow write access for Actions. If the default branch is
> protected, permit the GitHub Actions bot to push or update `update.json`
> manually.

Root managers read `update.json` through `updateJson` in `module.prop`, so
users get the update prompt without reinstalling anything.

## Why these defaults

The templates follow the same conventions as `RaffOptimizer`:

- `SKIPUNZIP=1` and explicit extraction in `customize.sh`
- one `build.sh` as the only packaging path
- `update.json` generated by CI, never committed by hand after releases
- tag/version validation before publishing
- no release zips in git

## Development

```bash
make test     # 80+ smoke assertions, no test framework needed
make lint     # bash -n on the CLI, libs, and tests
```

The test suite scaffolds all three profiles, builds a zip, validates it with
`doctor`, and exercises failure modes.

## License

MIT © [Raffxzr](https://github.com/Raffxzr)
