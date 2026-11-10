#!/usr/bin/env bash
# modulize bump — bump module version across module.prop, update.json, and CHANGELOG.md.

bump_usage() {
  cat <<'EOF'
Usage:
  modulize bump [patch | minor | major | <version>] [directory] [options]

Synchronize version and versionCode across module.prop, update.json,
and insert a new release entry in CHANGELOG.md.

Arguments:
  type             patch (default), minor, major, or explicit version (e.g. v1.2.0)
  directory        Module directory (default: current directory)

Options:
  --code CODE      Override the new integer versionCode (default: previous + 1)
  --notes TEXT     Release note summary for CHANGELOG.md
  --dir DIR        Explicit target directory
  -y, --yes        Accept defaults without prompting
  -h, --help       Show this help

Examples:
  modulize bump                    # v0.1.0 -> v0.1.1, versionCode + 1
  modulize bump minor              # v0.1.0 -> v0.2.0, versionCode + 1
  modulize bump major              # v0.1.0 -> v1.0.0, versionCode + 1
  modulize bump v1.2.0             # Set explicit version
  modulize bump patch ./MyModule --notes "Fix thermal service bug"
EOF
}

cmd_bump() {
  local bump_type='' dir='' custom_code='' notes='' assume_yes=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --code)
        [[ $# -ge 2 ]] || die "--code requires a value"
        custom_code=$2
        shift 2
        ;;
      --code=*)
        custom_code=${1#*=}
        shift
        ;;
      --notes)
        [[ $# -ge 2 ]] || die "--notes requires a value"
        notes=$2
        shift 2
        ;;
      --notes=*)
        notes=${1#*=}
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
      -y | --yes)
        assume_yes=1
        shift
        ;;
      -h | --help)
        bump_usage
        return 0
        ;;
      -*)
        die "unknown option: $1 (try: modulize bump --help)"
        ;;
      patch | minor | major)
        [[ -z "$bump_type" ]] || die "bump type already specified as '$bump_type'"
        bump_type=$1
        shift
        ;;
      v[0-9]* | [0-9]*)
        [[ -z "$bump_type" ]] || die "bump type already specified as '$bump_type'"
        bump_type=$1
        shift
        ;;
      *)
        if [[ -z "$dir" && -d "$1" ]]; then
          dir=$1
        elif [[ -z "$bump_type" ]]; then
          bump_type=$1
        else
          die "unexpected argument: $1"
        fi
        shift
        ;;
    esac
  done

  bump_type=${bump_type:-patch}
  dir=${dir:-.}

  [[ -d "$dir" ]] || die "directory not found: $dir"
  dir=$(cd "$dir" && pwd)
  local prop_file="$dir/module.prop"
  [[ -f "$prop_file" ]] || die "module.prop not found in $dir"

  local id name old_version old_code
  id=$(get_prop id "$prop_file")
  name=$(get_prop name "$prop_file")
  old_version=$(get_prop version "$prop_file")
  old_code=$(get_prop versionCode "$prop_file")

  [[ -n "$id" ]] || die "module id missing in $prop_file"
  [[ -n "$old_version" ]] || die "current version missing in $prop_file"
  [[ -n "$old_code" ]] || old_code="0"

  local new_version
  new_version=$(bump_semver "$old_version" "$bump_type") \
    || die "could not compute new version from '$old_version' with type '$bump_type'"

  validate_version "$new_version" \
    || die "invalid target version calculated: '$new_version'"

  local new_code
  if [[ -n "$custom_code" ]]; then
    validate_version_code "$custom_code" \
      || die "invalid custom versionCode: '$custom_code'"
    new_code=$custom_code
  else
    new_code=$((old_code + 1))
  fi

  notes=${notes:-"Bump version to ${new_version}"}
  local today
  today=$(date +%F)

  info "Bumping $name ($id)"
  printf '    Version:     %s -> %s\n' "$old_version" "$new_version"
  printf '    versionCode: %s -> %s\n' "$old_code" "$new_code"

  if [[ "$assume_yes" -eq 0 ]] && is_tty; then
    confirm "Apply version bump?" y || die "aborted by user"
  fi

  # 1. Update module.prop
  set_prop version "$new_version" "$prop_file"
  set_prop versionCode "$new_code" "$prop_file"
  ok "Updated module.prop"

  # 2. Update update.json if present
  local json_file="$dir/update.json"
  if [[ -f "$json_file" ]]; then
    local old_zip new_zip repo
    old_zip=$(sed -n 's/.*"zipUrl": *"\([^"]*\)".*/\1/p' "$json_file" | head -n 1)

    if [[ -n "$old_zip" ]]; then
      # Replace /old_version/ and /id-old_version.zip
      new_zip=${old_zip//"$old_version"/"$new_version"}
    else
      repo=$(sed -n 's#.*raw\.githubusercontent\.com/\([^/]\+/[^/]\+\)/.*#\1#p' "$prop_file" | head -n 1)
      repo=${repo:-"owner/$id"}
      new_zip="https://github.com/${repo}/releases/download/${new_version}/${id}-${new_version}.zip"
    fi

    sync_update_json "$json_file" "$new_version" "$new_code" "$new_zip"
    ok "Updated update.json (zipUrl -> ${new_version})"
  fi

  # 3. Update CHANGELOG.md if present
  local changelog_file="$dir/CHANGELOG.md"
  if [[ -f "$changelog_file" ]]; then
    if grep -q "^## \[${new_version}\]" "$changelog_file"; then
      warn "CHANGELOG.md already contains a section for ${new_version}"
    else
      local tmp_cl
      tmp_cl=$(mktemp "${TMPDIR:-/tmp}/modulize_cl.XXXXXX")
      local entry
      entry=$(printf '## [%s] - %s\n\n### Changed\n- %s\n\n' "$new_version" "$today" "$notes")

      if grep -q '^## \[' "$changelog_file"; then
        # Insert right before the first release heading
        awk -v entry="$entry" '
          !inserted && /^## \[/ {
            printf "%s", entry
            inserted = 1
          }
          { print }
        ' "$changelog_file" > "$tmp_cl"
        mv "$tmp_cl" "$changelog_file"
      else
        # Append to the end
        printf '\n%s' "$entry" >> "$changelog_file"
        rm -f "$tmp_cl"
      fi
      ok "Updated CHANGELOG.md"
    fi
  fi

  log ''
  ok "Bump complete: ${new_version} (${new_code})"
}
