#!/usr/bin/env bash
# Shared helpers for the modulize CLI.

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RED=$'\033[1;31m'
  GREEN=$'\033[1;32m'
  YELLOW=$'\033[1;33m'
  CYAN=$'\033[1;36m'
  RESET=$'\033[0m'
else
  BOLD='' DIM='' RED='' GREEN='' YELLOW='' CYAN='' RESET=''
fi

log() { printf '%s\n' "$*"; }
info() { printf '%s==>%s %s\n' "${CYAN}" "${RESET}" "$*"; }
ok() { printf '%s✓%s %s\n' "${GREEN}" "${RESET}" "$*"; }
warn() { printf '%s!%s %s\n' "${YELLOW}" "${RESET}" "$*" >&2; }
error() { printf '%sx%s %s\n' "${RED}" "${RESET}" "$*" >&2; }
die() { error "$*"; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

require_cmd() {
  have_cmd "$1" || die "required command not found: $1"
}

trim() {
  local value=$1
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[[:space:]_]\+/-/g' \
          -e 's/[^a-z0-9._-]//g' \
          -e 's/-\{2,\}/-/g' \
          -e 's/^-//' \
          -e 's/-$//'
}

# Sanitize a directory name into a module id while preserving CamelCase.
module_id_from_name() {
  printf '%s' "$1" \
    | sed -e 's/[[:space:]_]\+/-/g' \
          -e 's/[^A-Za-z0-9._-]//g' \
          -e 's/-\{2,\}/-/g' \
          -e 's/^-//' \
          -e 's/-$//'
}

titleize() {
  local input=$1 word out=()
  input=${input//[-_.]/ }
  for word in $input; do
    out+=("${word^}")
  done
  printf '%s' "${out[*]}"
}

is_tty() { [[ -t 0 && -t 1 ]]; }

prompt() {
  local __var=$1 label=$2 default=${3-} answer
  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$label" "$default" >&2
  else
    printf '%s: ' "$label" >&2
  fi
  IFS= read -r answer || answer=''
  [[ -z "$answer" ]] && answer=$default
  printf -v "$__var" '%s' "$answer"
}

confirm() {
  local label=$1 default=${2:-n} answer
  if [[ "$default" == "y" ]]; then
    printf '%s [Y/n]: ' "$label" >&2
  else
    printf '%s [y/N]: ' "$label" >&2
  fi
  IFS= read -r answer || answer=''
  answer=${answer:-$default}
  [[ "$answer" =~ ^[Yy]$ ]]
}

validate_module_id() {
  [[ "$1" =~ ^[A-Za-z][A-Za-z0-9._-]{0,63}$ ]]
}

validate_version() {
  [[ "$1" =~ ^v[0-9][0-9A-Za-z._-]{0,31}$ ]]
}

validate_version_code() {
  [[ "$1" =~ ^[1-9][0-9]{0,9}$ ]]
}

validate_repo() {
  [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
}

validate_branch() {
  [[ "$1" =~ ^[A-Za-z0-9._/-]+$ ]]
}

validate_min_sdk() {
  [[ "$1" =~ ^[1-9][0-9]?$ ]]
}

# Escape a value so it can be used as a sed replacement with the # delimiter.
_sed_value() {
  printf '%s' "$1" | sed -e 's/[\\&#]/\\&/g'
}

# Render one template using the MODULE_* / REPO / BRANCH render variables.
render_template() {
  local src=$1 dst=$2 tmp
  [[ -f "$src" ]] || die "template not found: $src"
  mkdir -p "$(dirname "$dst")"
  tmp=$(mktemp "${TMPDIR:-/tmp}/modulize.XXXXXX")

  sed \
    -e "s#{{MODULE_ID}}#$(_sed_value "${MODULE_ID:-}")#g" \
    -e "s#{{MODULE_NAME}}#$(_sed_value "${MODULE_NAME:-}")#g" \
    -e "s#{{VERSION}}#$(_sed_value "${VERSION:-}")#g" \
    -e "s#{{VERSION_CODE}}#$(_sed_value "${VERSION_CODE:-}")#g" \
    -e "s#{{AUTHOR}}#$(_sed_value "${AUTHOR:-}")#g" \
    -e "s#{{DESCRIPTION}}#$(_sed_value "${DESCRIPTION:-}")#g" \
    -e "s#{{REPO}}#$(_sed_value "${REPO:-}")#g" \
    -e "s#{{BRANCH}}#$(_sed_value "${BRANCH:-}")#g" \
    -e "s#{{MIN_SDK}}#$(_sed_value "${MIN_SDK:-}")#g" \
    -e "s#{{TEMPLATE}}#$(_sed_value "${TEMPLATE_PROFILE:-}")#g" \
    -e "s#{{GENERATED_DATE}}#$(_sed_value "${GENERATED_DATE:-}")#g" \
    -e "s#{{YEAR}}#$(_sed_value "${YEAR:-}")#g" \
    "$src" >"$tmp"

  mv "$tmp" "$dst"
}

# Copy a template with placeholder rendering.
copy_template() {
  local src=$1 dst=$2
  render_template "$src" "$dst"
}

# Copy a file without rendering placeholders.
copy_raw() {
  local src=$1 dst=$2 mode=${3:-0644}
  [[ -f "$src" ]] || die "template not found: $src"
  mkdir -p "$(dirname "$dst")"
  install -m "$mode" "$src" "$dst"
}

relative_path() {
  local from=$1 to=$2
  if have_cmd realpath; then
    realpath --relative-to="$from" "$to"
  else
    printf '%s' "$to"
  fi
}
