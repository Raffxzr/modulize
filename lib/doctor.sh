#!/usr/bin/env bash
# modulize doctor — sanity-check a generated module tree.

doctor_usage() {
  cat <<'EOF'
Usage:
  modulize doctor [directory] [--strict]

Validate module.prop, update.json, installer files, and release automation.
With --strict, warnings are treated as errors.
EOF
}

doctor_prop() {
  sed -n "s/^$1=//p" "$2" | tr -d '\r' | head -n 1
}

cmd_doctor() {
  local dir='.' strict=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strict)
        strict=1
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

  [[ -x "$dir/customize.sh" ]] || doctor_warn 'customize.sh is not executable'
  [[ -x "$dir/build.sh" ]] || doctor_warn 'build.sh is not executable'

  if [[ -f "$dir/update.json" ]]; then
    if have_cmd jq && jq -e . "$dir/update.json" >/dev/null 2>&1; then
      local json_version json_code json_zip json_changelog
      json_version=$(jq -r '.version // empty' "$dir/update.json")
      json_code=$(jq -r '.versionCode // empty' "$dir/update.json")
      json_zip=$(jq -r '.zipUrl // empty' "$dir/update.json")
      json_changelog=$(jq -r '.changelog // empty' "$dir/update.json")

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

  local crlf
  crlf=$(find "$dir" -type f \
    -not -path "$dir/.git/*" \
    -not -path "$dir/build/*" \
    -not -path "$dir/dist/*" \
    \( -name '*.sh' -o -path "$dir/system/bin/*" -o -path "$dir/system/xbin/*" \) \
    -print0 2>/dev/null | while IFS= read -r -d '' file; do
      LC_ALL=C grep -q $'\r' "$file" && printf '%s\n' "$file"
    done || true)

  if [[ -z "$crlf" ]]; then
    doctor_pass 'shell scripts use LF line endings'
  else
    doctor_error "CRLF line endings found in: $(printf '%s' "$crlf" | tr '\n' ' ')"
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
    ok 'doctor passed'
  fi
}
