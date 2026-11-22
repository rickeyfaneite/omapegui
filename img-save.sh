#!/bin/bash
# OmaPegui helper: copy an image into the plugin's own images folder.
#   img-save.sh <source file> <file name>
#
# The source must be a regular file, not a symlink, whose real path is inside
# Omarchy's clipboard-images folder or the plugin's own images folder. Neither
# folder, nor the state folders above them, may be a symlink. The destination is
# always the plugin's images folder. The copy goes to a temporary name and is
# renamed over the destination only once complete, and only if the destination
# is absent or already a regular file.
set -u
umask 077

base="$HOME/.local/state/omarchy"
state="$base/omapegui"
stock="$base/clipboard-images"
dir="$state/images"
src=${1:-}
name=${2:-}

[[ $name =~ ^[0-9a-f]{32,64}\.(png|jpg|webp|gif)$ ]] || exit 1
[[ -d $base && ! -L $base && -d $stock && ! -L $stock ]] || exit 1
[[ -d $dir && ! -L $dir && -O $dir && -d $state && ! -L $state ]] || exit 1
[[ -n $src && -f $src && ! -L $src && -r $src ]] || exit 1

real=$(realpath -- "$src") || exit 1
stock_real=$(realpath -- "$stock") || exit 1
dir_real=$(realpath -- "$dir") || exit 1
case $real in
  "$stock_real"/* | "$dir_real"/*) ;;
  *) exit 1 ;;
esac
[[ -f $real && ! -L $real ]] || exit 1

dest="$dir/$name"
if [[ -e $dest || -L $dest ]]; then
  [[ -f $dest && ! -L $dest ]] || exit 1
fi

tmp=$(mktemp "$dir/.save.XXXXXX") || exit 1
trap 'rm -f -- "$tmp"' EXIT
cp -- "$real" "$tmp" || exit 1
mv -fT -- "$tmp" "$dest" || exit 1
trap - EXIT
