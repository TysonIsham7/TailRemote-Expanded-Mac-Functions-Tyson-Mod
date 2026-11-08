#!/bin/sh
# Refuse a commit that contains this Mac's local signing values, a filled-in
# Apple team ID, or signing material. The personal strings are read from
# gitignored files, so the public tree does not list them.
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

mode=staged
if [ "${1:-}" = "--all" ]; then
  mode=all
fi

patterns=$(mktemp)
names=$(mktemp)
trap 'rm -f "$patterns" "$names"' EXIT

add_pattern() {
  value=$1
  case $value in
    ""|\#*|YOURTEAMID|com.example.tailremote) return ;;
  esac
  if [ "${#value}" -lt 6 ]; then
    return
  fi
  printf '%s\n' "$value" >> "$patterns"
}

read_assignments() {
  file=$1
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      ""|//*|\#*) continue ;;
    esac
    case $line in
      *=*)
        value=${line#*=}
        value=${value%%//*}
        value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//')
        add_pattern "$value"
        ;;
    esac
  done < "$file"
}

read_denylist() {
  file=$1
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      ""|\#*) continue ;;
    esac
    value=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    add_pattern "$value"
  done < "$file"
}

read_assignments Config/Local.xcconfig
read_denylist Config/denylist.local
if [ -s "$patterns" ]; then
  sort -u "$patterns" -o "$patterns"
fi

if [ "$mode" = "all" ]; then
  git ls-files > "$names"
else
  git diff --cached --name-only --diff-filter=ACMR > "$names"
fi

fail=0

while IFS= read -r path; do
  [ -n "$path" ] || continue
  base=$(basename "$path")
  case $base in
    Local.xcconfig|denylist.local)
      printf 'blocked file: %s\n' "$path" >&2
      fail=1
      ;;
  esac
  case $path in
    *.p12|*.mobileprovision|*.cer|*.p8|*.pem|*.key)
      printf 'blocked file: %s\n' "$path" >&2
      fail=1
      ;;
  esac
done < "$names"

while IFS= read -r path; do
  [ -n "$path" ] && [ -f "$path" ] || continue
  case $path in
    *.pbxproj|*.yml|*.yaml|*.xcconfig|*.plist|*.md|*.sh|*.swift) ;;
    *) continue ;;
  esac
  if grep -nE 'DEVELOPMENT_TEAM[[:space:]]*[:=][[:space:]]*[A-Z0-9]{10}([^A-Z0-9]|$)' "$path" >&2; then
    printf 'filled-in DEVELOPMENT_TEAM in %s\n' "$path" >&2
    fail=1
  fi
done < "$names"

while IFS= read -r pattern; do
  [ -n "$pattern" ] || continue
  while IFS= read -r path; do
    [ -n "$path" ] && [ -f "$path" ] || continue
    if grep -F -n -I -e "$pattern" "$path" >&2; then
      printf 'local-only value in %s\n' "$path" >&2
      fail=1
    fi
  done < "$names"
done < "$patterns"

if [ "$fail" -ne 0 ]; then
  printf '\nCommit blocked. Personal signing stays in Config/Local.xcconfig and Config/denylist.local.\n' >&2
  exit 1
fi
