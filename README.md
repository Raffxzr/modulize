# raff-module

Scaffold Magisk / KernelSU / APatch modules in seconds.

```bash
raff-module init my-module
```

`raff-module` generates the boring parts that every module needs:

- `module.prop`
- `customize.sh`
- `update.json` (OTA manifest)
- `build.sh` (reproducible module zip)
- `META-INF` installer
- GitHub Actions workflows for build + release
- optional `service.sh`, `action.sh`, `uninstall.sh`, WebUI, and a CLI stub

The templates are extracted from production modules such as
[RaffOptimizer](https://github.com/Raffxzr/RaffOptimizer), so the result is
ready to flash, not just a toy skeleton.

## Status

Work in progress. Usage, flags, and release flow will land in the next commits.
