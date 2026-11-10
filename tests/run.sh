#!/usr/bin/env bash
# Smoke tests for modulize. No external test framework required.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT_DIR/modulize"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/modulize-tests.XXXXXX")
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

assert_no_placeholders() {
  local dir=$1 matches
  matches=$(grep -RInE '\{\{[A-Z_]+\}\}' "$dir" \
    --exclude-dir=.git --exclude-dir=build --exclude-dir=dist 2>/dev/null || true)
  if [[ -z "$matches" ]]; then
    pass 'no unrendered placeholders'
  else
    fail 'unrendered template placeholders found'
    printf '%s\n' "$matches" | sed 's/^/       /' >&2
  fi
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

assert_no_placeholders "$STANDARD"
check_shell_syntax "$STANDARD"

run_ok 'modulize build produces a zip' "$CLI" build "$STANDARD"
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
assert_no_placeholders "$MINIMAL"
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
assert_no_placeholders "$FULL"
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

touch "$TMP_DIR/not-a-directory"
run_fail 'rejects a target that is a file' \
  "$CLI" init "$TMP_DIR/not-a-directory" --id GoodMod --repo owner/repo -y

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
section 'bump subcommand'
# ---------------------------------------------------------------------------
BUMP_DIR="$TMP_DIR/bump-target"
run_ok 'init module for bump testing' \
  "$CLI" init "$BUMP_DIR" --id BumpMod --repo Raffxzr/BumpMod -y

assert_contains "$BUMP_DIR/module.prop" 'version=v0.1.0'
assert_contains "$BUMP_DIR/module.prop" 'versionCode=1'

# Test patch bump
run_ok 'bump patch increments patch and versionCode' \
  "$CLI" bump patch "$BUMP_DIR" -y
assert_contains "$BUMP_DIR/module.prop" 'version=v0.1.1'
assert_contains "$BUMP_DIR/module.prop" 'versionCode=2'
assert_contains "$BUMP_DIR/update.json" '"version": "v0.1.1"'
assert_contains "$BUMP_DIR/update.json" '"versionCode": 2'
assert_contains "$BUMP_DIR/CHANGELOG.md" '## [v0.1.1]'

# Test minor bump
run_ok 'bump minor increments minor and resets patch' \
  "$CLI" bump minor "$BUMP_DIR" -y
assert_contains "$BUMP_DIR/module.prop" 'version=v0.2.0'
assert_contains "$BUMP_DIR/module.prop" 'versionCode=3'
assert_contains "$BUMP_DIR/update.json" '"version": "v0.2.0"'

# Test major bump with custom notes
run_ok 'bump major increments major and sets notes' \
  "$CLI" bump major "$BUMP_DIR" --notes 'Major redesign' -y
assert_contains "$BUMP_DIR/module.prop" 'version=v1.0.0'
assert_contains "$BUMP_DIR/module.prop" 'versionCode=4'
assert_contains "$BUMP_DIR/CHANGELOG.md" 'Major redesign'

# Test explicit version and custom code
run_ok 'bump explicit version and custom code' \
  "$CLI" bump v2.5.0 "$BUMP_DIR" --code 99 -y
assert_contains "$BUMP_DIR/module.prop" 'version=v2.5.0'
assert_contains "$BUMP_DIR/module.prop" 'versionCode=99'
assert_contains "$BUMP_DIR/update.json" '"version": "v2.5.0"'
assert_contains "$BUMP_DIR/update.json" '"versionCode": 99'

# ---------------------------------------------------------------------------
section 'add subcommand'
# ---------------------------------------------------------------------------
ADD_DIR="$TMP_DIR/add-target"
run_ok 'init minimal module for add testing' \
  "$CLI" init "$ADD_DIR" --id AddMod --repo Raffxzr/AddMod --template minimal -y

assert_no_file "$ADD_DIR/webroot/index.html"
assert_no_file "$ADD_DIR/post-fs-data.sh"
assert_no_file "$ADD_DIR/action.sh"
assert_no_file "$ADD_DIR/system/bin/AddMod"

run_ok 'add webui' "$CLI" add webui "$ADD_DIR"
assert_file "$ADD_DIR/webroot/index.html"
assert_contains "$ADD_DIR/webroot/index.html" '<title>AddMod</title>'

run_ok 'add post-fs-data' "$CLI" add post-fs-data "$ADD_DIR"
assert_file "$ADD_DIR/post-fs-data.sh"
assert_exec "$ADD_DIR/post-fs-data.sh"

run_ok 'add action' "$CLI" add action "$ADD_DIR"
assert_file "$ADD_DIR/action.sh"
assert_exec "$ADD_DIR/action.sh"

run_ok 'add cli' "$CLI" add cli "$ADD_DIR"
assert_file "$ADD_DIR/system/bin/AddMod"
assert_exec "$ADD_DIR/system/bin/AddMod"

run_fail 'add refuses to overwrite existing component without --force' \
  "$CLI" add webui "$ADD_DIR"

run_ok 'add with --force overwrites existing component' \
  "$CLI" add webui "$ADD_DIR" --force

# ---------------------------------------------------------------------------
section 'doctor --fix auto-repair'
# ---------------------------------------------------------------------------
FIX_DIR="$TMP_DIR/fix-target"
run_ok 'init module for doctor fix testing' \
  "$CLI" init "$FIX_DIR" --id FixMod --repo Raffxzr/FixMod -y

printf 'SKIPUNZIP=1\r\nASH_STANDALONE=1\r\n' >> "$FIX_DIR/customize.sh"
chmod -x "$FIX_DIR/customize.sh"
chmod -x "$FIX_DIR/build.sh"

run_fail 'doctor detects CRLF and non-executable files' \
  "$CLI" doctor "$FIX_DIR" --strict

run_ok 'doctor --fix repairs CRLF and permissions' \
  "$CLI" doctor "$FIX_DIR" --fix

assert_exec "$FIX_DIR/customize.sh"
assert_exec "$FIX_DIR/build.sh"
run_ok 'doctor passes cleanly after fix' \
  "$CLI" doctor "$FIX_DIR" --strict

# ---------------------------------------------------------------------------
section 'lint subcommand'
# ---------------------------------------------------------------------------
run_ok 'lint accepts clean module' "$CLI" lint "$STANDARD" --strict

LINT_BROKEN="$TMP_DIR/lint-broken"
cp -R "$STANDARD" "$LINT_BROKEN"
printf 'if then fi syntax error\n' >> "$LINT_BROKEN/customize.sh"
run_fail 'lint detects shell syntax errors' "$CLI" lint "$LINT_BROKEN"

# ---------------------------------------------------------------------------
section 'summary'
# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
