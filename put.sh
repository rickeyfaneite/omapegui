#!/bin/bash
# OmaPegui helper: put text from stdin on the clipboard, and optionally send it
# to the focused window. The text never travels as an argument, so it can be any
# size and can never be read as an option, and it is never typed key by key (a
# newline typed that way would be a Return).
#
#   put.sh copy    copy only
#   put.sh paste   copy, then Shift+Insert
#   put.sh plain   copy as text/plain, then Shift+Insert
set -u
umask 077
mode=${1:-}
case $mode in copy | paste | plain) ;; *) exit 2 ;; esac

limit=8388608   # 8 MiB: nothing the plugin hands over is larger
dir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
tmp=$(mktemp "${dir%/}/omapegui-put.XXXXXX") || exit 1
trap 'rm -f -- "$tmp"' EXIT
head -c $((limit + 1)) >"$tmp" || exit 1
size=$(wc -c <"$tmp") || exit 1
(( size > 0 && size <= limit )) || exit 1

# wl-copy forks to serve the selection; silence its streams so nothing waits on them.
if [[ $mode == plain ]]; then
  wl-copy --type text/plain <"$tmp" >/dev/null 2>&1 || exit 1
else
  wl-copy <"$tmp" >/dev/null 2>&1 || exit 1
fi
[[ $mode == copy ]] && exit 0

sleep 0.15
wtype -M shift -k Insert -m shift
