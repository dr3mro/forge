#!/bin/sh
# Git reports successful local ref changes on stdin.
[ "$1" = committed ] || exit 0
root=$(git rev-parse --show-toplevel) || exit 1
file="$root/version.cpp.in"
[ -f "$file" ] && [ ! -L "$file" ] || exit 0
while read -r old new ref; do
  case "$ref" in refs/tags/*) ;; *) continue ;; esac
  # Only newly created numeric release tags affect project versioning.
  case "$old" in *[!0]*) continue ;; esac
  case "$new" in *[!0]*) ;; *) continue ;; esac
  tag=${ref#refs/tags/}
  printf '%s\n' "$tag" | grep -Eq '^v?[0-9]+(\.[0-9]+){0,3}$' || continue
  tmp=$(mktemp "$root/.forge-version.XXXXXX") || exit 1
  if ! printf 'inline constexpr char forge_version[] = "%s";\n' "$tag" > "$tmp" ||
    ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    exit 1
  fi
done
