#!/bin/bash
# OmaPegui helper: delete saved images by bare file name, only inside the
# plugin's own images folder, and only names of the form the plugin generates.
#   img-rm.sh <file name>...
set -u
base="$HOME/.local/state/omarchy"
state="$base/omapegui"
dir="$state/images"

[[ -d $base && ! -L $base && -d $state && ! -L $state ]] || exit 1
[[ -d $dir && ! -L $dir && -O $dir ]] || exit 1
status=0
for name in "$@"; do
  if [[ $name =~ ^[0-9a-f]{32,64}\.(png|jpg|webp|gif)$ ]]; then
    rm -f -- "$dir/$name" || status=1
  else
    status=1
  fi
done
exit $status
