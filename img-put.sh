#!/bin/bash
# OmaPegui helper: put an image on the clipboard, and optionally send the paste
# gesture, for an image file that passes the same checks the save helper makes.
#   img-put.sh [--copy-only] <mime type> <file>
#
# The clipboard replacement is checked: the paste gesture is sent only if
# wl-copy succeeded, and a failure of either step is the exit status.
set -u
umask 077

copy_only=0
if [[ ${1:-} == --copy-only ]]; then
  copy_only=1
  shift
fi
mime=${1:-}
src=${2:-}

case $mime in image/png | image/jpeg | image/webp | image/gif) ;; *) exit 1 ;; esac
[[ -n $src && -f $src && ! -L $src && -r $src ]] || exit 1

base="$HOME/.local/state/omarchy"
state="$base/omapegui"
stock="$base/clipboard-images"
own="$state/images"
[[ -d $base && ! -L $base ]] || exit 1
real=$(realpath -- "$src") || exit 1
# A folder that does not exist, or is (or sits under) a symlink, allows nothing;
# an empty prefix would match everything.
inside=0
if [[ -d $stock && ! -L $stock ]]; then
  folder_real=$(realpath -- "$stock") || exit 1
  [[ -n $folder_real ]] && case $real in "$folder_real"/*) inside=1 ;; esac
fi
if [[ -d $state && ! -L $state && -d $own && ! -L $own ]]; then
  folder_real=$(realpath -- "$own") || exit 1
  [[ -n $folder_real ]] && case $real in "$folder_real"/*) inside=1 ;; esac
fi
(( inside )) || exit 1
[[ -f $real && ! -L $real ]] || exit 1

wl-copy --type "$mime" <"$real" >/dev/null 2>&1 || exit 1
(( copy_only )) && exit 0

sleep 0.15
wtype -M shift -k Insert -m shift
