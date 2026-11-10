#!/usr/bin/env bash
# raff-module init — scaffold a Magisk / KernelSU / APatch module.

init_usage() {
  cat <<'EOF'
Usage:
  raff-module init [directory] [options]

Create a ready-to-build module tree in DIRECTORY (default: current directory).

Options:
  --id ID                Module id, for example "MyModule"
  --name NAME            Display name
  --version VERSION      Version tag, for example v0.1.0
  --version-code CODE    Integer versionCode
  --author NAME          Author name
  --description TEXT     Module description
  --repo OWNER/REPO      GitHub repository used by update.json
  --branch BRANCH        Default branch used by raw URLs (default: main)
  --min-sdk API          Minimum Android SDK (default: 21)
  --template PROFILE     minimal | standard | full (default: standard)
  --no-workflow          Skip .github/workflows
  --no-git               Do not run git init
  --force                Write into a non-empty directory
  -y, --yes              Accept defaults, never prompt
  -h, --help             Show this help

Examples:
  raff-module init MyModule
  raff-module init MyModule --id MyModule --repo Raffxzr/MyModule -y
  raff-module init ./demo --template full --min-sdk 26
EOF
}

detect_github_owner() {
  local owner

  if have_cmd gh && gh api user --jq .login >/dev/null 2>&1; then
    gh api user --jq .login
    return 0
  fi

  owner=$(git config --get github.user 2>/dev/null || true)
  if [[ -n "$owner" ]]; then
    printf '%s' "$owner"
    return 0
  fi

  owner=$(slugify "${AUTHOR:-Raffxzr}")
  printf '%s' "${owner:-raffxzr}"
}

cmd_init() {
  local target='' assume_yes=0 force=0 git_init=1 enable_workflows=1
  local profile='standard'

  MODULE_ID=''
  MODULE_NAME=''
  VERSION='v0.1.0'
  VERSION_CODE='1'
  AUTHOR=''
  DESCRIPTION=''
  REPO=''
  BRANCH='main'
  MIN_SDK='21'

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)
        [[ $# -ge 2 ]] || die "--id requires a value"
        MODULE_ID=$2
        shift 2
        ;;
      --id=*)
        MODULE_ID=${1#*=}
        shift
        ;;
      --name)
        [[ $# -ge 2 ]] || die "--name requires a value"
        MODULE_NAME=$2
        shift 2
        ;;
      --name=*)
        MODULE_NAME=${1#*=}
        shift
        ;;
      --version)
        [[ $# -ge 2 ]] || die "--version requires a value"
        VERSION=$2
        shift 2
        ;;
      --version=*)
        VERSION=${1#*=}
        shift
        ;;
      --version-code)
        [[ $# -ge 2 ]] || die "--version-code requires a value"
        VERSION_CODE=$2
        shift 2
        ;;
      --version-code=*)
        VERSION_CODE=${1#*=}
        shift
        ;;
      --author)
        [[ $# -ge 2 ]] || die "--author requires a value"
        AUTHOR=$2
        shift 2
        ;;
      --author=*)
        AUTHOR=${1#*=}
        shift
        ;;
      --description)
        [[ $# -ge 2 ]] || die "--description requires a value"
        DESCRIPTION=$2
        shift 2
        ;;
      --description=*)
        DESCRIPTION=${1#*=}
        shift
        ;;
      --repo)
        [[ $# -ge 2 ]] || die "--repo requires a value"
        REPO=$2
        shift 2
        ;;
      --repo=*)
        REPO=${1#*=}
        shift
        ;;
      --branch)
        [[ $# -ge 2 ]] || die "--branch requires a value"
        BRANCH=$2
        shift 2
        ;;
      --branch=*)
        BRANCH=${1#*=}
        shift
        ;;
      --min-sdk)
        [[ $# -ge 2 ]] || die "--min-sdk requires a value"
        MIN_SDK=$2
        shift 2
        ;;
      --min-sdk=*)
        MIN_SDK=${1#*=}
        shift
        ;;
      --template)
        [[ $# -ge 2 ]] || die "--template requires a value"
        profile=$2
        shift 2
        ;;
      --template=*)
        profile=${1#*=}
        shift
        ;;
      --no-workflow | --no-workflows)
        enable_workflows=0
        shift
        ;;
      --no-git)
        git_init=0
        shift
        ;;
      --force)
        force=1
        shift
        ;;
      -y | --yes)
        assume_yes=1
        shift
        ;;
      -h | --help)
        init_usage
        return 0
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          [[ -z "$target" ]] || die "only one target directory is supported"
          target=$1
          shift
        done
        ;;
      -*)
        die "unknown option: $1 (try: raff-module init --help)"
        ;;
      *)
        [[ -z "$target" ]] || die "only one target directory is supported"
        target=$1
        shift
        ;;
    esac
  done

  target=${target:-.}

  local base
  if [[ "$target" == "." ]]; then
    base=$(basename "$PWD")
  else
    base=$(basename "$target")
  fi
  [[ -n "$base" && "$base" != "." && "$base" != "/" ]] || base='my-module'

  local id_default
  id_default=$(module_id_from_name "$base")
  [[ -n "$id_default" ]] || id_default='my-module'
  if [[ ! "$id_default" =~ ^[A-Za-z] ]]; then
    id_default="module-$id_default"
  fi
  id_default=${id_default:0:64}

  AUTHOR=${AUTHOR:-$(git config user.name 2>/dev/null || true)}
  AUTHOR=${AUTHOR:-Raffxzr}

  local owner
  owner=$(detect_github_owner)

  MODULE_ID=${MODULE_ID:-$id_default}
  MODULE_NAME=${MODULE_NAME:-$(titleize "$MODULE_ID")}
  DESCRIPTION=${DESCRIPTION:-A Magisk / KernelSU / APatch module scaffolded by raff-module.}
  REPO=${REPO:-$owner/$MODULE_ID}

  if [[ "$assume_yes" -eq 0 ]] && is_tty; then
    log ''
    log "${BOLD}Module details${RESET} ${DIM}(enter to keep the default)${RESET}"
    prompt MODULE_ID 'Module id' "$MODULE_ID"
    prompt MODULE_NAME 'Display name' "$MODULE_NAME"
    prompt VERSION 'Version tag' "$VERSION"
    prompt VERSION_CODE 'versionCode' "$VERSION_CODE"
    prompt AUTHOR 'Author' "$AUTHOR"
    prompt DESCRIPTION 'Description' "$DESCRIPTION"
    prompt REPO 'GitHub repo (owner/name)' "$REPO"
    prompt BRANCH 'Default branch' "$BRANCH"
    prompt MIN_SDK 'Minimum SDK' "$MIN_SDK"
    prompt profile 'Template (minimal/standard/full)' "$profile"
    log ''
  elif [[ "$assume_yes" -eq 0 ]] && ! is_tty; then
    warn 'stdin is not a TTY; using defaults for missing values'
  fi

  validate_module_id "$MODULE_ID" \
    || die "invalid module id '$MODULE_ID' (use letters, digits, dot, dash, underscore; start with a letter)"
  [[ -n "$MODULE_NAME" ]] || die 'module name cannot be empty'
  validate_version "$VERSION" || die "invalid version '$VERSION' (expected something like v0.1.0)"
  validate_version_code "$VERSION_CODE" || die "invalid versionCode '$VERSION_CODE' (expected a positive integer)"
  validate_repo "$REPO" || die "invalid repo '$REPO' (expected owner/name)"
  validate_branch "$BRANCH" || die "invalid branch '$BRANCH'"
  validate_min_sdk "$MIN_SDK" || die "invalid minimum SDK '$MIN_SDK'"
  case "$profile" in
    minimal | standard | full) ;;
    *) die "invalid template '$profile' (choose minimal, standard, or full)" ;;
  esac

  mkdir -p "$target"
  local target_abs
  target_abs=$(cd "$target" && pwd)

  if [[ -n "$(ls -A "$target_abs" 2>/dev/null | grep -vx '.git' || true)" ]] && [[ "$force" -eq 0 ]]; then
    die "target directory is not empty: $target_abs (use --force to overwrite generated files)"
  fi

  local template_dir="$ROOT_DIR/templates"
  local generated_date year
  generated_date=$(date +%F)
  year=$(date +%Y)

  TEMPLATE_PROFILE=$profile
  GENERATED_DATE=$generated_date
  YEAR=$year
  export MODULE_ID MODULE_NAME VERSION VERSION_CODE AUTHOR DESCRIPTION
  export REPO BRANCH MIN_SDK TEMPLATE_PROFILE GENERATED_DATE YEAR

  info "Scaffolding $MODULE_NAME ($MODULE_ID) in $target_abs"

  copy_template "$template_dir/base/module.prop.tmpl" "$target_abs/module.prop"
  copy_template "$template_dir/base/customize.sh.tmpl" "$target_abs/customize.sh"
  copy_template "$template_dir/base/update.json.tmpl" "$target_abs/update.json"
  copy_template "$template_dir/base/build.sh.tmpl" "$target_abs/build.sh"
  copy_template "$template_dir/base/README.md.tmpl" "$target_abs/README.md"
  copy_template "$template_dir/base/CHANGELOG.md.tmpl" "$target_abs/CHANGELOG.md"
  copy_raw "$template_dir/base/.gitignore" "$target_abs/.gitignore"
  copy_raw "$template_dir/base/.gitattributes" "$target_abs/.gitattributes"
  copy_raw "$template_dir/base/module.include" "$target_abs/module.include"
  copy_raw "$template_dir/base/META-INF/com/google/android/update-binary" \
    "$target_abs/META-INF/com/google/android/update-binary" 0755
  copy_raw "$template_dir/base/META-INF/com/google/android/updater-script" \
    "$target_abs/META-INF/com/google/android/updater-script"

  chmod 0755 "$target_abs/customize.sh" "$target_abs/build.sh"

  if [[ "$profile" != 'minimal' ]]; then
    copy_template "$template_dir/standard/service.sh.tmpl" "$target_abs/service.sh"
    copy_template "$template_dir/standard/action.sh.tmpl" "$target_abs/action.sh"
    copy_template "$template_dir/standard/uninstall.sh.tmpl" "$target_abs/uninstall.sh"
    copy_template "$template_dir/standard/system.prop.tmpl" "$target_abs/system.prop"
    copy_template "$template_dir/standard/system/bin/cli.sh.tmpl" \
      "$target_abs/system/bin/$MODULE_ID"
    chmod 0755 "$target_abs/service.sh" "$target_abs/action.sh" \
      "$target_abs/uninstall.sh" "$target_abs/system/bin/$MODULE_ID"
  fi

  if [[ "$profile" == 'full' ]]; then
    copy_template "$template_dir/full/post-fs-data.sh.tmpl" "$target_abs/post-fs-data.sh"
    copy_template "$template_dir/full/webroot/index.html.tmpl" "$target_abs/webroot/index.html"
    chmod 0755 "$target_abs/post-fs-data.sh"
  fi

  if [[ "$enable_workflows" -eq 1 ]]; then
    copy_raw "$template_dir/workflows/release.yml" \
      "$target_abs/.github/workflows/release.yml"
    copy_template "$template_dir/workflows/build.yml.tmpl" \
      "$target_abs/.github/workflows/build.yml"
  fi

  if [[ "$git_init" -eq 1 ]] && ! git -C "$target_abs" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$target_abs" init -b main >/dev/null 2>&1; then
      ok 'Initialized git repository on main'
    else
      git -C "$target_abs" init >/dev/null 2>&1 || warn 'could not initialize git repository'
      git -C "$target_abs" symbolic-ref HEAD refs/heads/main 2>/dev/null || true
    fi
  fi

  log ''
  ok "Created $MODULE_NAME"
  printf '    directory  %s\n' "$target_abs"
  printf '    template   %s\n' "$profile"
  printf '    version    %s (%s)\n' "$VERSION" "$VERSION_CODE"
  printf '    repo       %s\n' "$REPO"
  printf '    workflows  %s\n' "$([[ "$enable_workflows" -eq 1 ]] && echo enabled || echo skipped)"
  log ''
  log "${BOLD}Next steps${RESET}"
  printf '  cd %q\n' "$target_abs"
  printf '  ./build.sh\n'
  printf '  git add . && git commit -m "feat: initial %s module"\n' "$MODULE_ID"
  printf '  git tag %s && git push origin %s --tags\n' "$VERSION" "$BRANCH"
}
