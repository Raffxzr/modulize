#!/usr/bin/env bash
# Smoke tests for raff-module. No external test framework required.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT_DIR/raff-module"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/raff-module-tests.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
CURRENT=''

section() {
  CURRENT=$1
  printf '\n%s\n' "$CURRENT"
}

pass() {
  PASS=$((PASS + 1))
  printf '  ok  %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL %s\n' "$1" >&2
}

assert_file() {
  [[ -f "$1" ]] && pass "file exists: ${1#"$TMP_DIR"/}" || fail "missing file: $1"
}

assert_dir() {
  [[ -d "$1" ]] && pass "directory exists: ${1#"$TMP_DIR"/}" || fail "missing directory: $1"
}

assert_no_file() {
  [[ ! -e "$1" ]] && pass "not present: ${1#"$TMP_DIR"/}" || fail "should not exist: $1"
}

assert_exec() {
  [[ -x "$1" ]] && pass "executable: ${1#"$TMP_DIR"/}" || fail "not executable: $1"
}

assert_contains() {
  local file=$1 pattern=$2
  if grep -Fq -- "$pattern" "$file"; then
    pass "$(basename "$file") contains: $pattern"
  else
    fail "$(basename "$file") missing: $pattern"
  fi
}

assert_not_contains() {
  local file=$1 pattern=$2
  if grep -Fq -- "$pattern" "$file"; then
    fail "$(basename "$file") should not contain: $pattern"
  else
    pass "$(basename "$file") does not contain: $pattern"
  fi
}

run_ok() {
  local label=$1
  shift
  if "$@" >"$TMP_DIR/output.log" 2>&1; then
    pass "$label"
  else
    fail "$label"
    sed 's/^/       /' "$TMP_DIR/output.log" >&2
  fi
}

run_fail() {
  local label=$1
  shift
  if "$@" >"$TMP_DIR/output.log" 2>&1; then
    fail "$label (expected failure)"
    sed 's/^/       /' "$TMP_DIR/output.log" >&2
  else
    pass "$label"
  fi
}

check_shell_syntax() {
  local dir=$1 file
  local files=()
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find "$dir" -type f \
    -not -path "$dir/.git/*" \
    -not -path "$dir/build/*" \
    -not -path "$dir/dist/*" \
    \( -name '*.sh' -o -path "$dir/system/bin/*" \) \
    -print0)

  for file in "${files[@]}"; do
    if bash -n "$file" 2>"$TMP_DIR/syntax.log"; then
      pass "syntax ok: ${file#"$dir"/}"
    else
      fail "syntax error: $file"
      sed 's/^/       /' "$TMP_DIR/syntax.log" >&2
    fi
  done
}

# ---------------------------------------------------------------------------
section 'standard profile'
# ---------------------------------------------------------------------------
STANDARD="$TMP_DIR/standard"
run_ok 'init creates a standard module' \
  "$CLI" init "$STANDARD" \
  --id DemoModule --name 'Demo Module' --author Tester \
  --description 'Example & module #1 | test' --repo Raffxzr/DemoModule -y

assert_file "$STANDARD/module.prop"
assert_file "$STANDARD/customize.sh"
assert_file "$STANDARD/update.json"
assert_file "$STANDARD/build.sh"
assert_file "$STANDARD/README.md"
assert_file "$STANDARD/CHANGELOG.md"
assert_file "$STANDARD/module.include"
assert_file "$STANDARD/.gitattributes"
assert_file "$STANDARD/service.sh"
assert_file "$STANDARD/action.sh"
assert_file "$STANDARD/uninstall.sh"
assert_file "$STANDARD/system.prop"
assert_file "$STANDARD/system/bin/DemoModule"
assert_file "$STANDARD/META-INF/com/google/android/update-binary"
assert_file "$STANDARD/.github/workflows/build.yml"
assert_file "$STANDARD/.github/workflows/release.yml"
assert_exec "$STANDARD/customize.sh"
assert_exec "$STANDARD/build.sh"
assert_exec "$STANDARD/system/bin/DemoModule"
assert_exec "$STANDARD/META-INF/com/google/android/update-binary"

assert_contains "$STANDARD/module.prop" 'id=DemoModule'
assert_contains "$STANDARD/module.prop" 'version=v0.1.0'
assert_contains "$STANDARD/module.prop" 'versionCode=1'
assert_contains "$STANDARD/module.prop" 'description=Example & module #1 | test'
assert_contains "$STANDARD/module.prop" 'updateJson=https://raw.githubusercontent.com/Raffxzr/DemoModule/main/update.json'
assert_contains "$STANDARD/update.json" '"version": "v0.1.0"'
assert_contains "$STANDARD/update.json" '"versionCode": 1'
assert_contains "$STANDARD/update.json" 'Raffxzr/DemoModule/releases/download/v0.1.0/DemoModule-v0.1.0.zip'
assert_contains "$STANDARD/CHANGELOG.md" '## [v0.1.0]'
assert_contains "$STANDARD/customize.sh" 'SKIPUNZIP=1'
assert_contains "$STANDARD/customize.sh" '[ "$API" -ge 21 ]'

check_shell_syntax "$STANDARD"

run_ok 'raff-module build produces a zip' "$CLI" build "$STANDARD"
ZIP="$STANDARD/dist/DemoModule-v0.1.0.zip"
assert_file "$ZIP"
if [[ -f "$ZIP" ]]; then
  ENTRIES=$(unzip -Z1 "$ZIP")
  for entry in module.prop customize.sh service.sh action.sh uninstall.sh \
    META-INF/com/google/android/update-binary system/bin/DemoModule; do
    if printf '%s\n' "$ENTRIES" | grep -qx -- "$entry"; then
      pass "zip contains: $entry"
    else
      fail "zip missing: $entry"
    fi
  done
  if printf '%s\n' "$ENTRIES" | grep -q '^update.json$'; then
    fail 'release zip should not contain update.json'
  else
    pass 'release zip excludes update.json'
  fi
fi

run_ok 'doctor accepts the generated module' "$CLI" doctor "$STANDARD"

# ---------------------------------------------------------------------------
section 'minimal profile'
# ---------------------------------------------------------------------------
MINIMAL="$TMP_DIR/minimal"
run_ok 'init creates a minimal module' \
  "$CLI" init "$MINIMAL" --id MiniMod --repo Raffxzr/MiniMod \
  --template minimal --no-workflow --no-git -y

assert_file "$MINIMAL/module.prop"
assert_file "$MINIMAL/customize.sh"
assert_file "$MINIMAL/update.json"
assert_file "$MINIMAL/build.sh"
assert_no_file "$MINIMAL/service.sh"
assert_no_file "$MINIMAL/action.sh"
assert_no_file "$MINIMAL/uninstall.sh"
assert_no_file "$MINIMAL/system.prop"
assert_no_file "$MINIMAL/.github/workflows/release.yml"
assert_contains "$MINIMAL/module.prop" 'id=MiniMod'
check_shell_syntax "$MINIMAL"

# ---------------------------------------------------------------------------
section 'full profile'
# ---------------------------------------------------------------------------
FULL="$TMP_DIR/full"
run_ok 'init creates a full module' \
  "$CLI" init "$FULL" --id FullMod --repo Raffxzr/FullMod \
  --template full --min-sdk 26 -y

assert_file "$FULL/post-fs-data.sh"
assert_file "$FULL/webroot/index.html"
assert_file "$FULL/system/bin/FullMod"
assert_exec "$FULL/post-fs-data.sh"
assert_contains "$FULL/customize.sh" '[ "$API" -ge 26 ]'
assert_contains "$FULL/webroot/index.html" '<title>FullMod</title>'
check_shell_syntax "$FULL"

# ---------------------------------------------------------------------------
section 'custom branch'
# ---------------------------------------------------------------------------
BRANCHED="$TMP_DIR/branched"
run_ok 'init honors a custom default branch' \
  "$CLI" init "$BRANCHED" --id BranchMod --repo Raffxzr/BranchMod \
  --branch feature/demo -y

assert_contains "$BRANCHED/module.prop" 'Raffxzr/BranchMod/feature/demo/update.json'
assert_contains "$BRANCHED/.github/workflows/build.yml" 'branches: [feature/demo]'
assert_contains "$BRANCHED/update.json" 'Raffxzr/BranchMod/feature/demo/CHANGELOG.md'
run_ok 'doctor accepts a nested branch name' "$CLI" doctor "$BRANCHED"

# ---------------------------------------------------------------------------
section 'default id'
# ---------------------------------------------------------------------------
DEFAULT_ID="$TMP_DIR/CamelCaseModule"
run_ok 'init derives a CamelCase id from the directory' \
  "$CLI" init "$DEFAULT_ID" --repo Raffxzr/CamelCaseModule -y
assert_contains "$DEFAULT_ID/module.prop" 'id=CamelCaseModule'
assert_contains "$DEFAULT_ID/module.prop" 'name=CamelCaseModule'

# ---------------------------------------------------------------------------
section 'validation'
# ---------------------------------------------------------------------------
run_fail 'rejects an invalid module id' \
  "$CLI" init "$TMP_DIR/bad-id" --id '9 bad id' --repo owner/repo -y

run_fail 'rejects an invalid version' \
  "$CLI" init "$TMP_DIR/bad-version" --id GoodMod --version '1.0' \
  --repo owner/repo -y

run_fail 'rejects an invalid versionCode' \
  "$CLI" init "$TMP_DIR/bad-code" --id GoodMod --version-code 'abc' \
  --repo owner/repo -y

run_fail 'rejects an invalid repo' \
  "$CLI" init "$TMP_DIR/bad-repo" --id GoodMod --repo 'not-a-repo' -y

run_fail 'refuses to overwrite a non-empty directory' \
  "$CLI" init "$STANDARD" --id DemoModule --repo owner/repo -y

run_ok '--force allows writing into a non-empty directory' \
  "$CLI" init "$STANDARD" --id DemoModule --name 'Demo Module' \
  --repo Raffxzr/DemoModule --force -y

# ---------------------------------------------------------------------------
section 'doctor failure modes'
# ---------------------------------------------------------------------------
BROKEN="$TMP_DIR/broken"
cp -R "$STANDARD" "$BROKEN"
sed -i 's/^version=v0.1.0$/version=v9.9.9/' "$BROKEN/module.prop"
run_fail 'doctor detects update.json/metadata drift' "$CLI" doctor "$BROKEN"

MISSING="$TMP_DIR/missing"
mkdir -p "$MISSING"
run_fail 'doctor fails without module.prop' "$CLI" doctor "$MISSING"

# ---------------------------------------------------------------------------
section 'summary'
# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
