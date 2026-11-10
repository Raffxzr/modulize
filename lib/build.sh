#!/usr/bin/env bash
# modulize build — run the module build script from anywhere.

build_usage() {
  cat <<'EOF'
Usage:
  modulize build [directory]

Run DIRECTORY/build.sh (default: current directory) and print the resulting
flashable zip. Any extra arguments are forwarded to build.sh.
EOF
}

cmd_build() {
  local dir='.'

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        build_usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "unknown option: $1 (try: modulize build --help)"
        ;;
      *)
        dir=$1
        shift
        break
        ;;
    esac
  done

  [[ -d "$dir" ]] || die "directory not found: $dir"
  [[ -f "$dir/build.sh" ]] || die "build.sh not found in $dir"
  [[ -x "$dir/build.sh" ]] || chmod +x "$dir/build.sh"

  (cd "$dir" && ./build.sh "$@")
}
