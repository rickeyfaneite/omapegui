#!/bin/bash
# OmaPegui helper for "copy to category": get what the user has selected and
# answer on stdout with one header line, then (for text) the text itself.
#
#   grab.sh copy      send Ctrl+C to the focused window; if the clipboard
#                     changed, use it, otherwise use the PRIMARY selection
#   grab.sh primary   use the PRIMARY selection only (for terminals, where
#                     Ctrl+C would interrupt the program)
#
#   OMAPEGUI-GRAB kind=text src=clipboard|primary
#   OMAPEGUI-GRAB kind=image src=clipboard mime=<type> name=<hash>.<ext>
#   OMAPEGUI-GRAB kind=none
#
# An image is written to the plugin's images folder under its final name (the
# plugin removes it again if the user cancels). Nothing is ever put on the
# clipboard here.
set -u
umask 077
mode=${1:-}
case $mode in copy | primary) ;; *) exit 2 ;; esac

limit=8388608   # 8 MiB: the same ceiling as put.sh
runtime=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
tmp=$(mktemp "${runtime%/}/omapegui-grab.XXXXXX") || exit 1
trap 'rm -f -- "$tmp"' EXIT

none() { echo "OMAPEGUI-GRAB kind=none"; exit 0; }

# A fingerprint of what the clipboard holds now: its types and a hash of its first type.
clip_sig() {
  local types first
  types=$(wl-paste -l 2>/dev/null | tr '\n' ' ')
  first=${types%% *}
  printf '%s|' "$types"
  [[ -n $first ]] && { wl-paste -t "$first" 2>/dev/null | head -c 16777216 | sha256sum; }
}

# Text from the given selection (clipboard or primary), if it has text.
emit_text() {
  local src=$1 flag=()
  [[ $src == primary ]] && flag=(-p)
  wl-paste ${flag[@]+"${flag[@]}"} --no-newline --type text >"$tmp" 2>/dev/null || return 1
  local size
  size=$(wc -c <"$tmp") || return 1
  (( size > 0 && size <= limit )) || return 1
  grep -q '[^[:space:]]' "$tmp" || return 1
  echo "OMAPEGUI-GRAB kind=text src=$src"
  cat "$tmp"
  exit 0
}

# An image from the clipboard, when it has one and no text.
emit_image() {
  local types mime ext
  types=$(wl-paste -l 2>/dev/null) || return 1
  grep -qi '^text/plain\|^UTF8_STRING$\|^STRING$' <<<"$types" && return 1
  for mime in image/png image/jpeg image/webp image/gif; do
    grep -qx "$mime" <<<"$types" && break
    mime=
  done
  [[ -n $mime ]] || return 1
  case $mime in image/png) ext=png ;; image/jpeg) ext=jpg ;; image/webp) ext=webp ;; image/gif) ext=gif ;; esac
  wl-paste -t "$mime" >"$tmp" 2>/dev/null || return 1
  local size hash dir="$HOME/.local/state/omarchy/omapegui/images" base="$HOME/.local/state/omarchy"
  size=$(wc -c <"$tmp") || return 1
  (( size > 0 && size <= limit )) || return 1
  [[ -d $base && ! -L $base && -d $dir && ! -L $dir && -O $dir && ! -L "$base/omapegui" ]] || return 1
  hash=$(sha256sum <"$tmp") || return 1
  hash=${hash%% *}
  local dest="$dir/$hash.$ext" staged
  if [[ -e $dest || -L $dest ]]; then [[ -f $dest && ! -L $dest ]] || return 1; fi
  staged=$(mktemp "$dir/.grab.XXXXXX") || return 1
  cp -- "$tmp" "$staged" && mv -fT -- "$staged" "$dest" || { rm -f -- "$staged"; return 1; }
  echo "OMAPEGUI-GRAB kind=image src=clipboard mime=$mime name=$hash.$ext"
  exit 0
}

if [[ $mode == copy ]]; then
  before=$(clip_sig)
  # Explicit mods, no window target: the keys reach the focused surface even while
  # a modifier of the trigger is still held (see Omarchy's own universal copy).
  hyprctl dispatch 'hl.dsp.send_key_state({ mods = "CTRL", key = "C", state = "down" })' >/dev/null 2>&1
  sleep 0.05
  hyprctl dispatch 'hl.dsp.send_key_state({ mods = "CTRL", key = "C", state = "up" })' >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 0.05
    if [[ $(clip_sig) != "$before" ]]; then
      emit_image
      emit_text clipboard
      break
    fi
  done
fi

emit_text primary
none
