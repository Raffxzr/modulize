#!/usr/bin/env bash
# modulize doctor — sanity-check a generated module tree.

doctor_usage() {
  cat <<'EOF'
Usage:
  modulize doctor [directory] [options]

Validate module.prop, update.json, installer files, line endings, and workflows.

Options:
  --fix          Automatically fix common issues (CRLF line endings, permissions, metadata drift)
  --strict       Treat warnings as errors
  --dir DIR      Target module directory (default: current directory)
  -h, --help     Show this help

Examples:
  modulize doctor
  modulize doctor --fix
  modulize doctor ./MyModule --strict
EOF
}

doctor_prop() {
  get_prop "$1" "$2"
}

cmd_doctor() {
  local dir='.' strict=0 fix=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strict)
        strict=1
        shift
        ;;
      --fix)
        fix=1
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
        doctor_usage
        return 0
        ;;
      -*)
        die "unknown option: $1 (try: modulize doctor --help)"
        ;;
      *)
        dir=$1
        shift
        ;;
    esac
  done

  [[ -d "$dir" ]] || die "directory not found: $dir"
  dir=$(cd "$dir" && pwd)
  [[ -f "$dir/module.prop" ]] || die "module.prop not found in $dir"

  local errors=0 warnings=0
  doctor_error() { errors=$((errors + 1)); error "$*"; }
  doctor_warn() { warnings=$((warnings + 1)); warn "$*"; }
  doctor_pass() { ok "$*"; }
  doctor_fix() { ok "${CYAN}[fixed]${RESET} $*"; }

  info "Checking $dir"

  local id name version version_code author description update_json_url
  id=$(doctor_prop id "$dir/module.prop")
  name=$(doctor_prop name "$dir/module.prop")
  version=$(doctor_prop version "$dir/module.prop")
  version_code=$(doctor_prop versionCode "$dir/module.prop")
  author=$(doctor_prop author "$dir/module.prop")
  description=$(doctor_prop description "$dir/module.prop")
  update_json_url=$(doctor_prop updateJson "$dir/module.prop")

  if validate_module_id "$id"; then
    doctor_pass "module id: $id"
  else
    doctor_error "invalid module id: '${id:-<missing>}'"
  fi

  [[ -n "$name" ]] && doctor_pass "module name: $name" || doctor_error 'module name is missing'
  [[ -n "$author" ]] || doctor_warn 'author is missing'
  [[ -n "$description" ]] || doctor_warn 'description is missing'

  if validate_version "$version"; then
    doctor_pass "version: $version"
  else
    doctor_error "invalid version: '${version:-<missing>}'"
  fi

  if validate_version_code "$version_code"; then
    doctor_pass "versionCode: $version_code"
  else
    doctor_error "invalid versionCode: '${version_code:-<missing>}'"
  fi

  if [[ -n "$update_json_url" ]]; then
    if [[ "$update_json_url" =~ ^https://raw\.githubusercontent\.com/[^/]+/[^/]+/.+/update\.json$ ]]; then
      doctor_pass "updateJson: $update_json_url"
    else
      doctor_error "updateJson is not a raw.githubusercontent.com update.json URL: $update_json_url"
    fi
  else
    doctor_warn 'module.prop has no updateJson entry; in-app OTA updates will not work'
  fi

  [[ -f "$dir/customize.sh" ]] && doctor_pass 'customize.sh present' \
    || doctor_error 'customize.sh is missing'
  [[ -f "$dir/META-INF/com/google/android/update-binary" ]] \
    && doctor_pass 'META-INF installer present' \
    || doctor_error 'META-INF/com/google/android/update-binary is missing'
  [[ -f "$dir/build.sh" ]] && doctor_pass 'build.sh present' \
    || doctor_error 'build.sh is missing'

  # Line endings check and fix (run before permissions check)
  local crlf_files=()
  while IFS= read -r -d '' file; do
    if LC_ALL=C grep -q $'\r' "$file" 2>/dev/null; then
      crlf_files+=("$file")
    fi
  done < <(find "$dir" -type f \
    -not -path "$dir/.git/*" \
    -not -path "$dir/build/*" \
    -not -path "$dir/dist/*" \
    \( -name '*.sh' -o -path "$dir/system/bin/*" -o -path "$dir/system/xbin/*" \) \
    -print0 2>/dev/null)

  if [[ ${#crlf_files[@]} -gt 0 ]]; then
    if [[ "$fix" -eq 1 ]]; then
      for f in "${crlf_files[@]}"; do
        local tmp_fix
        tmp_fix=$(mktemp "${TMPDIR:-/tmp}/modulize_crlf.XXXXXX")
        tr -d '\r' < "$f" > "$tmp_fix"
        chmod --reference="$f" "$tmp_fix" 2>/dev/null || true
        cat "$tmp_fix" > "$f"
        rm -f "$tmp_fix"
        doctor_fix "converted $(relative_path "$dir" "$f") from CRLF to LF"
      done
      doctor_pass 'all shell scripts now use LF line endings'
    else
      doctor_error "CRLF line endings found in: $(for f in "${crlf_files[@]}"; do relative_path "$dir" "$f"; done | tr '\n' ' ') (run: modulize doctor --fix)"
    fi
  else
    doctor_pass 'shell scripts use LF line endings'
  fi

  # Executable checks with --fix auto-repair
  for exec_file in "$dir/customize.sh" "$dir/build.sh" "$dir/service.sh" "$dir/action.sh" "$dir/post-fs-data.sh" "$dir/uninstall.sh"; do
    if [[ -f "$exec_file" ]]; then
      local base_name
      base_name=$(basename "$exec_file")
      if [[ "$fix" -eq 1 && ! -x "$exec_file" ]]; then
        chmod 0755 "$exec_file"
        doctor_fix "$base_name made executable"
      fi

      if [[ -x "$exec_file" ]]; then
        doctor_pass "$base_name is executable"
      else
        doctor_warn "$base_name is not executable (run: modulize doctor --fix)"
      fi
    fi
  done

  # Check executable permissions in system/bin
  if [[ -d "$dir/system/bin" ]]; then
    for bin_file in "$dir/system/bin"/*; do
      if [[ -f "$bin_file" ]]; then
        local bin_name
        bin_name="system/bin/$(basename "$bin_file")"
        if [[ "$fix" -eq 1 && ! -x "$bin_file" ]]; then
          chmod 0755 "$bin_file"
          doctor_fix "$bin_name made executable"
        fi

        if [[ -x "$bin_file" ]]; then
          doctor_pass "$bin_name is executable"
        else
          doctor_warn "$bin_name is not executable"
        fi
      fi
    done
  fi

  if [[ -f "$dir/update.json" ]]; then
    if have_cmd jq && jq -e . "$dir/update.json" >/dev/null 2>&1; then
      local json_version json_code json_zip json_changelog
      json_version=$(jq -r '.version // empty' "$dir/update.json")
      json_code=$(jq -r '.versionCode // empty' "$dir/update.json")
      json_zip=$(jq -r '.zipUrl // empty' "$dir/update.json")
      json_changelog=$(jq -r '.changelog // empty' "$dir/update.json")

      local json_drift=0
      if [[ "$json_version" != "$version" || "$json_code" != "$version_code" || "$json_zip" != *"/${id}-${version}.zip" ]]; then
        json_drift=1
      fi

      if [[ "$json_drift" -eq 1 && "$fix" -eq 1 ]]; then
        local target_zip
        if [[ -n "$json_zip" && "$json_zip" =~ /releases/download/ ]]; then
          target_zip=$(echo "$json_zip" | sed -E "s#/download/[^/]+/[^/]+#download/${version}/${id}-${version}.zip#")
        else
          local repo
          repo=$(sed -n 's#.*raw\.githubusercontent\.com/\([^/]\+/[^/]\+\)/.*#\1#p' "$dir/module.prop" | head -n 1)
          target_zip="https://github.com/${repo:-owner/repo}/releases/download/${version}/${id}-${version}.zip"
        fi
        sync_update_json "$dir/update.json" "$version" "$version_code" "$target_zip"
        doctor_fix "update.json synchronized with module.prop"
        json_version=$version
        json_code=$version_code
        json_zip=$target_zip
      fi

      [[ "$json_version" == "$version" ]] \
        && doctor_pass 'update.json version matches module.prop' \
        || doctor_error "update.json version '$json_version' does not match module.prop '$version'"

      [[ "$json_code" == "$version_code" ]] \
        && doctor_pass 'update.json versionCode matches module.prop' \
        || doctor_error "update.json versionCode '$json_code' does not match module.prop '$version_code'"

      [[ "$json_zip" == *"/${id}-${version}.zip" ]] \
        && doctor_pass 'update.json zipUrl matches the module zip name' \
        || doctor_error "update.json zipUrl does not end with /${id}-${version}.zip"

      [[ -n "$json_changelog" ]] && doctor_pass 'update.json changelog set' \
        || doctor_warn 'update.json changelog is empty'
    else
      doctor_error 'update.json is missing or is not valid JSON (install jq for full validation)'
    fi
  else
    doctor_error 'update.json is missing; root managers cannot check for OTA updates'
  fi

  if [[ -f "$dir/CHANGELOG.md" ]]; then
    if grep -q "^## \[${version}\]" "$dir/CHANGELOG.md"; then
      doctor_pass "CHANGELOG.md has a section for $version"
    else
      doctor_warn "CHANGELOG.md has no '## [${version}]' section; release notes will be empty"
    fi
  else
    doctor_warn 'CHANGELOG.md is missing'
  fi

  if [[ -f "$dir/.github/workflows/release.yml" ]]; then
    doctor_pass 'release workflow present'
  else
    doctor_warn 'release workflow is missing (.github/workflows/release.yml)'
  fi

  if [[ -f "$dir/.github/workflows/build.yml" ]]; then
    doctor_pass 'build workflow present'
  else
    doctor_warn 'build workflow is missing (.github/workflows/build.yml)'
  fi

  log ''
  if [[ "$errors" -gt 0 ]]; then
    error "doctor found $errors error(s) and $warnings warning(s)"
    return 1
  fi

  if [[ "$strict" -eq 1 && "$warnings" -gt 0 ]]; then
    error "doctor found $warnings warning(s) in strict mode"
    return 1
  fi

  if [[ "$warnings" -gt 0 ]]; then
    ok "doctor passed with $warnings warning(s)"
  else
    ok 'doctor passed cleanly'
  fi
}
