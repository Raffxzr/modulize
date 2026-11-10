#!/usr/bin/env bash
# modulize add — add components to an existing module.

add_usage() {
  cat <<'EOF'
Usage:
  modulize add <component> [directory] [options]

Add modular components to an existing Magisk / KernelSU / APatch module.

Components:
  webui          WebUI dashboard in webroot/index.html
  post-fs-data   Early boot hook executed before /data decryption
  action         Action button script executed in root manager app
  service        Late-start service boot script
  cli            CLI entrypoint executable at system/bin/<module-id>
  uninstall      Cleanup script executed when module is removed
  system.prop    System property overlay file
  workflow       GitHub Actions build and release workflows

Options:
  --force        Overwrite component file if it already exists
  --dir DIR      Target module directory (default: current directory)
  -h, --help     Show this help

Examples:
  modulize add webui
  modulize add action ./MyModule
  modulize add post-fs-data --force
  modulize add workflow
EOF
}

cmd_add() {
  local component='' dir='' force=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)
        force=1
        shift
        ;;
      --dir)
        [[ $# -ge 2 ]] || die "--dir requires a value"
        dir=$2
        shift 2
        ;;
      --dir=*)
        dir=${1#*=}
        shift
        ;;
      -h | --help)
        add_usage
        return 0
        ;;
      -*)
        die "unknown option: $1 (try: modulize add --help)"
        ;;
      *)
        if [[ -z "$component" ]]; then
          component=$1
        elif [[ -z "$dir" ]]; then
          dir=$1
        else
          die "unexpected argument: $1"
        fi
        shift
        ;;
    esac
  done

  [[ -n "$component" ]] || die "missing component (try: modulize add --help)"
  dir=${dir:-.}
  [[ -d "$dir" ]] || die "directory not found: $dir"
  dir=$(cd "$dir" && pwd)

  local prop_file="$dir/module.prop"
  [[ -f "$prop_file" ]] || die "module.prop not found in $dir"

  # Populate template variables from existing module metadata
  MODULE_ID=$(get_prop id "$prop_file")
  MODULE_NAME=$(get_prop name "$prop_file")
  VERSION=$(get_prop version "$prop_file")
  VERSION_CODE=$(get_prop versionCode "$prop_file")
  AUTHOR=$(get_prop author "$prop_file")
  DESCRIPTION=$(get_prop description "$prop_file")

  [[ -n "$MODULE_ID" ]] || die "module id missing in $prop_file"
  [[ -n "$MODULE_NAME" ]] || MODULE_NAME="$MODULE_ID"

  REPO=$(sed -n 's#.*raw\.githubusercontent\.com/\([^/]\+/[^/]\+\)/.*#\1#p' "$prop_file" | head -n 1)
  if [[ -z "$REPO" ]]; then
    REPO=$(git -C "$dir" config --get remote.origin.url 2>/dev/null \
      | sed -E 's#.*github\.com[:/]([^/]+/[^/.]+)(\.git)?#\1#' || true)
  fi
  REPO=${REPO:-"owner/$MODULE_ID"}

  BRANCH=$(sed -n "s#.*raw\.githubusercontent\.com/${REPO}/\([^/]\+\)/.*#\1#p" "$prop_file" | head -n 1)
  BRANCH=${BRANCH:-"main"}

  local custom_sh="$dir/customize.sh"
  if [[ -f "$custom_sh" ]]; then
    MIN_SDK=$(sed -n 's/.*\[ "\$API" -ge \([0-9]\+\) \].*/\1/p' "$custom_sh" | head -n 1)
  fi
  MIN_SDK=${MIN_SDK:-21}

  GENERATED_DATE=$(date +%F)
  YEAR=$(date +%Y)
  TEMPLATE_PROFILE='custom'

  export MODULE_ID MODULE_NAME VERSION VERSION_CODE AUTHOR DESCRIPTION
  export REPO BRANCH MIN_SDK TEMPLATE_PROFILE GENERATED_DATE YEAR

  local tmpl_dir="$ROOT_DIR/templates"

  case "$component" in
    webui)
      local target="$dir/webroot/index.html"
      [[ -e "$target" && "$force" -eq 0 ]] && die "$target already exists (use --force to overwrite)"
      copy_template "$tmpl_dir/full/webroot/index.html.tmpl" "$target"
      ok "Added WebUI: webroot/index.html"
      ;;
    post-fs-data)
      local target="$dir/post-fs-data.sh"
      [[ -e "$target" && "$force" -eq 0 ]] && die "$target already exists (use --force to overwrite)"
      copy_template "$tmpl_dir/full/post-fs-data.sh.tmpl" "$target"
      chmod 0755 "$target"
      ok "Added hook: post-fs-data.sh (0755)"
      ;;
    action)
      local target="$dir/action.sh"
      [[ -e "$target" && "$force" -eq 0 ]] && die "$target already exists (use --force to overwrite)"
      copy_template "$tmpl_dir/standard/action.sh.tmpl" "$target"
      chmod 0755 "$target"
      ok "Added action button: action.sh (0755)"
      ;;
    service)
      local target="$dir/service.sh"
      [[ -e "$target" && "$force" -eq 0 ]] && die "$target already exists (use --force to overwrite)"
      copy_template "$tmpl_dir/standard/service.sh.tmpl" "$target"
      chmod 0755 "$target"
      ok "Added service hook: service.sh (0755)"
      ;;
    cli)
      local target="$dir/system/bin/$MODULE_ID"
      [[ -e "$target" && "$force" -eq 0 ]] && die "$target already exists (use --force to overwrite)"
      copy_template "$tmpl_dir/standard/system/bin/cli.sh.tmpl" "$target"
      chmod 0755 "$target"
      ok "Added CLI entrypoint: system/bin/$MODULE_ID (0755)"
      ;;
    uninstall)
      local target="$dir/uninstall.sh"
      [[ -e "$target" && "$force" -eq 0 ]] && die "$target already exists (use --force to overwrite)"
      copy_template "$tmpl_dir/standard/uninstall.sh.tmpl" "$target"
      chmod 0755 "$target"
      ok "Added uninstall hook: uninstall.sh (0755)"
      ;;
    system.prop)
      local target="$dir/system.prop"
      [[ -e "$target" && "$force" -eq 0 ]] && die "$target already exists (use --force to overwrite)"
      copy_template "$tmpl_dir/standard/system.prop.tmpl" "$target"
      ok "Added system properties: system.prop"
      ;;
    workflow | workflows)
      local rel_target="$dir/.github/workflows/release.yml"
      local bld_target="$dir/.github/workflows/build.yml"
      if [[ (-e "$rel_target" || -e "$bld_target") && "$force" -eq 0 ]]; then
        die "workflows already exist in $dir/.github/workflows (use --force to overwrite)"
      fi
      copy_raw "$tmpl_dir/workflows/release.yml" "$rel_target"
      copy_template "$tmpl_dir/workflows/build.yml.tmpl" "$bld_target"
      ok "Added workflows: .github/workflows/{build,release}.yml"
      ;;
    *)
      die "unknown component: $component (supported: webui, post-fs-data, action, service, cli, uninstall, system.prop, workflow)"
      ;;
  esac
}
