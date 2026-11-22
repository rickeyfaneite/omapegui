#!/bin/bash
# OmaPegui helper: prepare the plugin's private state folder, then print this
# install's random salt (made on first use). Safe to run again at any time; it is
# also how file modes are tightened after each write. Any failed step makes it
# exit non-zero, and the caller treats that as "state folder not safe".
#
# Exit codes: 3 a state path is a symlink, 4 not a directory we own or cannot be
# made, 5 a state file is a symlink or not a regular file, 6 a mode could not be
# set, 7 the salt could not be made or read.
set -u
set -o pipefail
umask 077

[[ -n ${HOME:-} ]] || exit 4
base="$HOME/.local/state/omarchy"
state="$base/omapegui"
images="$state/images"

# Omarchy's own folder; created if the stock plugin has not made it yet.
[[ -L $base ]] && exit 3
if [[ ! -e $base ]]; then
  mkdir -p -m 700 -- "$base" || exit 4
fi
[[ -d $base && ! -L $base && -O $base ]] || exit 4

for d in "$state" "$images"; do
  [[ -L $d ]] && exit 3
  [[ -e $d && ! -d $d ]] && exit 4
  mkdir -p -m 700 -- "$d" || exit 4
  [[ -d $d && ! -L $d && -O $d ]] || exit 4
  chmod -- 700 "$d" || exit 6
done

for f in categories.json times.json salt; do
  p="$state/$f"
  [[ -L $p ]] && exit 5
  [[ -e $p && ! -f $p ]] && exit 5
  if [[ -e $p ]]; then chmod -- 600 "$p" || exit 6; fi
done

# Saved images are the plugin's own regular files.
find "$images" -maxdepth 1 -type f -exec chmod 600 {} + || exit 6

if [[ ! -s $state/salt ]]; then
  tmp=$(mktemp "$state/.salt.XXXXXX") || exit 7
  if ! head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' >"$tmp"; then rm -f -- "$tmp"; exit 7; fi
  [[ $(wc -c <"$tmp") -ge 48 ]] || { rm -f -- "$tmp"; exit 7; }
  mv -f -- "$tmp" "$state/salt" || { rm -f -- "$tmp"; exit 7; }
  chmod -- 600 "$state/salt" || exit 6
fi
cat -- "$state/salt" || exit 7
