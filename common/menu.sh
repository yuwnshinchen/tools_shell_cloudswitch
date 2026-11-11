#!/bin/bash
# menu.sh - fzf menu library (bash 3.2 compatible, no path exposed)

# Global arrays (bash 3.2 safe)
MENU_ITEMS=()
MENU_PATHS=()

# collect_menu <dir1> <dir2> ...
collect_menu() {
  MENU_ITEMS=()
  MENU_PATHS=()

  for dir in "$@"; do
    [[ ! -d "$dir" ]] && continue

    for f in "$dir"/*.sh; do
      [[ ! -f "$f" ]] && continue

      cmd=$(basename "$f" .sh)
      desc=$(grep -m1 '^# DESC:' "$f" | cut -d':' -f2- | xargs)
      [[ -z "$desc" ]] && desc="(no description)"

      MENU_ITEMS+=("$cmd|$desc")
      MENU_PATHS+=("$f")
    done
  done
}

# select_menu
# output: selected index (0-based), empty if cancelled
select_menu() {
  local selected index

  selected=$(printf "%s\n" "${MENU_ITEMS[@]}" | \
    nl -w1 -s':' | \
    fzf --height=15 --border \
        --prompt="Select > " \
        --info=inline \
        --delimiter='|' \
        --with-nth=1,2)

  [[ -z "$selected" ]] && return 1

  index=$(echo "$selected" | cut -d':' -f1)
  echo $((index - 1))
}
