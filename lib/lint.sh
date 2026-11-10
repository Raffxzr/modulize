#!/usr/bin/env bash
# modulize lint — validate shell scripts, JSON syntax, and template completeness.

lint_usage() {
  cat <<'EOF'
Usage:
  modulize lint [directory] [options]

Lint shell scripts for syntax errors, validate JSON files, and detect
unrendered placeholders or CRLF line endings in the module tree.

Options:
  --strict       Treat warnings as errors
  --dir DIR      Target module directory (default: current directory)
  -h, --help     Show this help

Examples:
  modulize lint
  modulize lint ./MyModule --strict
EOF
}

cmd_lint() {
  local dir='.' strict=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strict)
        strict=1
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
        lint_usage
        return 0
        ;;
      -*)
        die "unknown option: $1 (try: modulize lint --help)"
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
  lint_error() { errors=$((errors + 1)); error "$*"; }
  lint_warn() { warnings=$((warnings + 1)); warn "$*"; }
  lint_pass() { ok "$*"; }

  info "Linting module at $dir"

  # 1. Check shell script syntax
  local sh_files=()
  while IFS= read -r -d '' file; do
    sh_files+=("$file")
  done < <(find "$dir" -type f \
    -not -path "$dir/.git/*" \
    -not -path "$dir/build/*" \
    -not -path "$dir/dist/*" \
    \( -name '*.sh' -o -path "$dir/system/bin/*" -o -path "$dir/system/xbin/*" \) \
    -print0 2>/dev/null)

  if [[ ${#sh_files[@]} -gt 0 ]]; then
    local err_out
    for file in "${sh_files[@]}"; do
      local rel
      rel=$(relative_path "$dir" "$file")
      if err_out=$(bash -n "$file" 2>&1); then
        lint_pass "syntax ok: $rel"
      else
        lint_error "syntax error in $rel: $err_out"
      fi

      # Check shebang
      local first_line
      first_line=$(head -n 1 "$file" 2>/dev/null || true)
      if [[ "$first_line" =~ ^#! ]]; then
        :
      else
        lint_warn "missing shebang in $rel"
      fi
    done
  fi

  # 2. Check JSON validity
  local json_files=()
  while IFS= read -r -d '' file; do
    json_files+=("$file")
  done < <(find "$dir" -type f \
    -not -path "$dir/.git/*" \
    -not -path "$dir/build/*" \
    -not -path "$dir/dist/*" \
    -name '*.json' \
    -print0 2>/dev/null)

  for file in "${json_files[@]}"; do
    local rel
    rel=$(relative_path "$dir" "$file")
    if have_cmd jq; then
      if jq -e . "$file" >/dev/null 2>&1; then
        lint_pass "valid json: $rel"
      else
        lint_error "invalid json syntax in $rel"
      fi
    elif have_cmd python3; then
      if python3 -m json.tool "$file" >/dev/null 2>&1; then
        lint_pass "valid json: $rel"
      else
        lint_error "invalid json syntax in $rel"
      fi
    fi
  done

  # 3. Check for unrendered template placeholders
  local unrendered
  unrendered=$(grep -RInE '\{\{[A-Z_]+\}\}' "$dir" \
    --exclude-dir=.git --exclude-dir=build --exclude-dir=dist 2>/dev/null || true)

  if [[ -z "$unrendered" ]]; then
    lint_pass "no unrendered placeholders found"
  else
    lint_error "unrendered template placeholders detected:\n$unrendered"
  fi

  # 4. Check for CRLF line endings
  local crlf_found=()
  for file in "${sh_files[@]}"; do
    if LC_ALL=C grep -q $'\r' "$file" 2>/dev/null; then
      crlf_found+=("$(relative_path "$dir" "$file")")
    fi
  done

  if [[ ${#crlf_found[@]} -eq 0 ]]; then
    lint_pass "line endings: LF (no CRLF found in scripts)"
  else
    lint_error "CRLF line endings detected in: ${crlf_found[*]} (run: modulize doctor --fix)"
  fi

  log ''
  if [[ "$errors" -gt 0 ]]; then
    error "lint found $errors error(s) and $warnings warning(s)"
    return 1
  fi

  if [[ "$strict" -eq 1 && "$warnings" -gt 0 ]]; then
    error "lint found $warnings warning(s) in strict mode"
    return 1
  fi

  if [[ "$warnings" -gt 0 ]]; then
    ok "lint passed with $warnings warning(s)"
  else
    ok "lint passed cleanly"
  fi
}
