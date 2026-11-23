#!/bin/bash
# Tests for the helper scripts, run in a throwaway HOME with stub wl-copy, wtype and
# Omarchy paste script. No Wayland needed.   Usage: bash tests/helpers.sh [plugin dir]
set -u
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
T=$(mktemp -d); export HOME="$T/home"; mkdir -p "$HOME/.local/state/omarchy/clipboard-images" "$T/bin" "$T/omarchy/bin" "$T/run"
export XDG_RUNTIME_DIR="$T/run" OMARCHY_PATH="$T/omarchy"
# stubs
cat > "$T/bin/wl-copy" <<'S'
#!/bin/bash
echo "wl-copy args: $*" >> "$STUBLOG"; cat > "$STUBDIR/clip.out"
S
cat > "$T/bin/wtype" <<'S'
#!/bin/bash
echo "wtype args: $*" >> "$STUBLOG"
S
cat > "$T/omarchy/bin/omarchy-clipboard-paste-file" <<'S'
#!/bin/bash
echo "paste-file args: $*" >> "$STUBLOG"
S
# BSD mv (macOS) has no -T; give those machines a stand-in so the tests can run.
if ! touch "$T/mvprobe" 2>/dev/null || ! mv -fT -- "$T/mvprobe" "$T/mvprobe2" 2>/dev/null; then
  cat > "$T/bin/mv" <<'S'
#!/bin/bash
args=(); for a in "$@"; do [[ $a == -fT ]] && a=-f; args+=("$a"); done
exec /bin/mv "${args[@]}"
S
fi
chmod +x "$T/bin/"* "$T/omarchy/bin/"*
export STUBLOG="$T/stub.log" STUBDIR="$T" PATH="$T/bin:$PATH"
ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; FAILED=1; }
FAILED=0
chk(){ # label expected_rc cmd...
  local label=$1 exp=$2; shift 2; "$@" >/dev/null 2>&1; local rc=$?
  [[ $rc == $exp ]] && ok "$label (rc $rc)" || bad "$label (rc $rc, expected $exp)"
}
P="$SRC"
echo "---- put.sh"
printf 'line1\nline2 --copy-only -kReturn' | "$P/put.sh" copy; [[ $? == 0 && $(cat $T/clip.out) == $'line1\nline2 --copy-only -kReturn' ]] && ok "copy keeps text, options inert" || bad copy
grep -q "wl-copy args: $" $STUBLOG && ok "copy: wl-copy called without a type" || bad "copy args"
: > $STUBLOG; printf 'hello' | "$P/put.sh" plain; grep -q "wl-copy args: --type text/plain" $STUBLOG && grep -q "wtype args: -M shift -k Insert -m shift" $STUBLOG && ok "plain: wl-copy --type text/plain then Shift+Insert, no typing" || { bad plain; cat $STUBLOG; }
: > $STUBLOG; printf 'hello' | "$P/put.sh" paste; grep -q "wtype args: -M shift -k Insert -m shift" $STUBLOG && ok "paste: Shift+Insert" || bad paste
grep -c "wtype args: -$" $STUBLOG | grep -q '^0$' && ok "no wtype - (typing) call anywhere" || bad "typing call seen"
chk "mode type is gone" 2 bash -c "printf x | $P/put.sh type"
chk "bogus mode" 2 bash -c "printf x | $P/put.sh nope"
chk "empty input" 1 bash -c "$P/put.sh copy </dev/null"
head -c 9000000 /dev/zero | tr '\0' 'a' > $T/big; chk "over 8 MiB refused" 1 bash -c "$P/put.sh copy <$T/big"
head -c 8388608 /dev/zero | tr '\0' 'a' > $T/ok8; chk "exactly 8 MiB accepted" 0 bash -c "$P/put.sh copy <$T/ok8"
left=$(ls $T/run | wc -l | tr -d ' '); [[ $left == 0 ]] && ok "no temp file left in runtime dir after all put.sh runs" || { bad "temp files left: $left"; ls $T/run; }
echo "---- setup.sh"
salt=$("$P/setup.sh"); rc=$?; S="$HOME/.local/state/omarchy/omapegui"
[[ $rc == 0 && ${#salt} == 48 ]] && ok "setup: rc 0, 48-char salt" || bad "setup rc=$rc salt=[$salt]"
mode(){ perl -e 'printf "%o", (stat($ARGV[0]))[2] & 07777' "$1"; }
[[ $(mode $S) == 700 && $(mode $S/images) == 700 && $(mode $S/salt) == 600 ]] && ok "modes: state 700, images 700, salt 600" || bad "modes $(mode $S) $(mode $S/images) $(mode $S/salt)"
salt2=$("$P/setup.sh"); [[ $salt == $salt2 ]] && ok "salt is stable across runs" || bad salt
echo '{}' > $S/categories.json; chmod 644 $S/categories.json; echo '{}' > $S/times.json; chmod 664 $S/times.json; touch $S/images/x.png; chmod 644 $S/images/x.png
"$P/setup.sh" >/dev/null; [[ $(mode $S/categories.json) == 600 && $(mode $S/times.json) == 600 && $(mode $S/images/x.png) == 600 ]] && ok "existing files re-set to 600" || bad "file modes"
chmod 755 $S; "$P/setup.sh" >/dev/null; [[ $(mode $S) == 700 ]] && ok "state folder re-set to 700" || bad "dir re-set"
rm $S/images/x.png
mv $S $S.real; ln -s $S.real $S; chk "state folder is a symlink -> refused" 3 "$P/setup.sh"; rm $S; mv $S.real $S
mv $S/images $S/images.real; ln -s $S/images.real $S/images; chk "images folder is a symlink -> refused" 3 "$P/setup.sh"; rm $S/images; mv $S/images.real $S/images
mv $S/times.json $S/t.real; ln -s $S/t.real $S/times.json; chk "times.json symlink -> refused" 5 "$P/setup.sh"; rm $S/times.json; mv $S/t.real $S/times.json
echo "---- img-save.sh"
H=$(printf 'a%.0s' $(seq 1 64)); STOCK="$HOME/.local/state/omarchy/clipboard-images"
printf 'PNGDATA' > "$STOCK/$H.png"
chk "save from stock folder" 0 "$P/img-save.sh" "$STOCK/$H.png" "$H.png"
[[ $(cat $S/images/$H.png) == PNGDATA && $(mode $S/images/$H.png) == 600 ]] && ok "saved copy has the content, mode 600" || bad "saved copy"
[[ -z $(ls -A $S/images | grep '^\.save') ]] && ok "no temp left" || bad "temp left"
chk "bad name (path)" 1 "$P/img-save.sh" "$STOCK/$H.png" "../$H.png"
chk "bad name (extension)" 1 "$P/img-save.sh" "$STOCK/$H.png" "$H.txt"
chk "bad name (dotfile)" 1 "$P/img-save.sh" "$STOCK/$H.png" ".$H.png"
echo secret > "$T/outside.png"; chk "source outside stock folder" 1 "$P/img-save.sh" "$T/outside.png" "$H.png"
ln -s "$T/outside.png" "$STOCK/$(printf 'b%.0s' $(seq 1 64)).png"; chk "source is a symlink" 1 "$P/img-save.sh" "$STOCK/$(printf 'b%.0s' $(seq 1 64)).png" "$(printf 'b%.0s' $(seq 1 64)).png"
mkdir "$STOCK/sub"; ln -s "$T" "$STOCK/sub/up"; printf x > "$T/viaup.png"; chk "source reached through a symlinked dir" 1 "$P/img-save.sh" "$STOCK/sub/up/viaup.png" "$H.png"
chk "source is a directory" 1 "$P/img-save.sh" "$STOCK/sub" "$H.png"
chk "source missing" 1 "$P/img-save.sh" "$STOCK/nope.png" "$H.png"
chk "source from own images folder (category to category)" 0 "$P/img-save.sh" "$S/images/$H.png" "$H.png"
mv $S/images $S/images.real; ln -s $S/images.real $S/images; chk "destination folder is a symlink" 1 "$P/img-save.sh" "$STOCK/$H.png" "$H.png"; rm $S/images; mv $S/images.real $S/images
echo "---- img-rm.sh"
printf x > $S/images/$(printf 'c%.0s' $(seq 1 64)).png; printf keep > "$T/home/keepme"
chk "remove a valid name" 0 "$P/img-rm.sh" "$(printf 'c%.0s' $(seq 1 64)).png"
[[ ! -e $S/images/$(printf 'c%.0s' $(seq 1 64)).png ]] && ok "file gone" || bad "file still there"
chk "path traversal name" 1 "$P/img-rm.sh" "../../../keepme"
chk "absolute path" 1 "$P/img-rm.sh" "$T/home/keepme"
chk "dotfile name" 1 "$P/img-rm.sh" ".bashrc"
[[ -e "$T/home/keepme" ]] && ok "outside file untouched" || bad "outside file deleted"
mv $S/images $S/images.real; ln -s "$T/home" $S/images; printf z > "$T/home/$H.png"; chk "images folder is a symlink to elsewhere" 1 "$P/img-rm.sh" "$H.png"; [[ -e "$T/home/$H.png" ]] && ok "target of the symlink untouched" || bad "deleted through symlink"; rm $S/images; mv $S/images.real $S/images
echo "---- img-put.sh"
printf 'PNGDATA' > "$STOCK/$H.png"
: > $STUBLOG; rm -f $T/clip.out
chk "paste image from stock folder" 0 "$P/img-put.sh" image/png "$STOCK/$H.png"
grep -q "wl-copy args: --type image/png" $STUBLOG && [[ $(cat $T/clip.out) == PNGDATA ]] && ok "wl-copy got the type and the image bytes" || { bad "wl-copy call"; cat $STUBLOG; }
grep -q "wtype args: -M shift -k Insert -m shift" $STUBLOG && ok "paste gesture sent after the copy" || bad "no paste gesture"
grep -q "paste-file" $STUBLOG && bad "Omarchy's paste-file script was used" || ok "Omarchy's paste-file script is not used"
: > $STUBLOG; chk "copy-only succeeds" 0 "$P/img-put.sh" --copy-only image/png "$STOCK/$H.png"
grep -q "wtype" $STUBLOG && bad "copy-only sent a paste gesture" || ok "copy-only sends no gesture"
# failures propagate and no gesture follows a failed copy
cp "$T/bin/wl-copy" "$T/wl-copy.ok"; printf '#!/bin/bash\nexit 1\n' > "$T/bin/wl-copy"
: > $STUBLOG; chk "failed wl-copy -> failure" 1 "$P/img-put.sh" image/png "$STOCK/$H.png"
grep -q "wtype" $STUBLOG && bad "gesture sent after a failed copy" || ok "no gesture after a failed copy"
chk "failed wl-copy (copy-only) -> failure" 1 "$P/img-put.sh" --copy-only image/png "$STOCK/$H.png"
cp "$T/wl-copy.ok" "$T/bin/wl-copy"
cp "$T/bin/wtype" "$T/wtype.ok"; printf '#!/bin/bash\nexit 3\n' > "$T/bin/wtype"
chk "failed wtype -> failure" 3 "$P/img-put.sh" image/png "$STOCK/$H.png"
cp "$T/wtype.ok" "$T/bin/wtype"
chk "mime text/plain refused" 1 "$P/img-put.sh" text/plain "$STOCK/$H.png"
chk "mime image/svg+xml refused" 1 "$P/img-put.sh" image/svg+xml "$STOCK/$H.png"
chk "file outside both folders refused" 1 "$P/img-put.sh" image/png "$T/outside.png"
chk "symlink refused" 1 "$P/img-put.sh" image/png "$STOCK/$(printf 'b%.0s' $(seq 1 64)).png"
chk "own images folder allowed" 0 "$P/img-put.sh" image/png "$S/images/$H.png"
mv "$STOCK" "$STOCK.gone"; mv $S/images $S/images.gone; chk "no folders at all -> nothing allowed" 1 "$P/img-put.sh" image/png "$T/outside.png"; mv "$STOCK.gone" "$STOCK"; mv $S/images.gone $S/images
mv "$STOCK" "$STOCK.real"; mkdir -p "$T/elsewhere"; printf 'x' > "$T/elsewhere/$H.png"; ln -s "$T/elsewhere" "$STOCK"
chk "stock folder is a symlink -> put refused" 1 "$P/img-put.sh" image/png "$STOCK/$H.png"
chk "stock folder is a symlink -> save refused" 1 "$P/img-save.sh" "$STOCK/$H.png" "$H.png"
rm "$STOCK"; mv "$STOCK.real" "$STOCK"
mv $S $S.real; mkdir -p "$T/elsewhere2"; ln -s "$S.real" "$S"
chk "state folder (parent of images) is a symlink -> put refused" 1 "$P/img-put.sh" image/png "$S/images/$H.png"
rm "$S"; mv $S.real $S
echo "---- more setup.sh and img-save.sh"
rm -rf "$HOME/.local/state/omarchy"; salt=$("$P/setup.sh"); rc=$?
[[ $rc == 0 && ${#salt} == 48 && -d $HOME/.local/state/omarchy/omapegui/images ]] && ok "setup creates a missing Omarchy base folder" || bad "setup without base (rc $rc)"
mkdir -p "$HOME/.local/state/omarchy/clipboard-images"; printf 'PNGDATA' > "$STOCK/$H.png"
mv "$HOME/.local/state/omarchy" "$HOME/.local/state/omarchy.real"; ln -s "$HOME/.local/state/omarchy.real" "$HOME/.local/state/omarchy"
chk "base folder is a symlink -> setup refused" 3 "$P/setup.sh"
rm "$HOME/.local/state/omarchy"; mv "$HOME/.local/state/omarchy.real" "$HOME/.local/state/omarchy"
# a failing step makes setup fail: a state file that is a directory
mkdir $S/categories.json; chk "categories.json is a directory -> setup fails" 5 "$P/setup.sh"; rmdir $S/categories.json
# image destination that is a symlink to a directory is refused; mv -T never moves into it
mkdir -p "$T/dest-target"; ln -s "$T/dest-target" "$S/images/$H.png"
chk "destination is a symlink to a directory -> refused" 1 "$P/img-save.sh" "$STOCK/$H.png" "$H.png"
[[ -z $(ls -A "$T/dest-target") ]] && ok "nothing was moved into the symlink's target" || bad "file landed in the target"
rm "$S/images/$H.png"
mkdir "$S/images/$H.png"; chk "destination is a directory -> refused" 1 "$P/img-save.sh" "$STOCK/$H.png" "$H.png"; rmdir "$S/images/$H.png"
printf 'OLD' > "$S/images/$H.png"; chk "destination is an existing regular file -> replaced" 0 "$P/img-save.sh" "$STOCK/$H.png" "$H.png"
[[ $(cat "$S/images/$H.png") == PNGDATA ]] && ok "replaced with the new copy" || bad "not replaced"
echo "---- grab.sh (stub wl-paste and hyprctl)"
"$P/setup.sh" >/dev/null
W="$T/wl"; mkdir -p "$W"
cat > "$T/bin/wl-paste" <<'S'
#!/bin/bash
# State in $W: types (one per line), clip.<type-with-slashes-as-_>, primary.
W="$STUBDIR/wl"; primary=0; type=
while [[ $# -gt 0 ]]; do case $1 in -p) primary=1 ;; -l) list=1 ;; -t | --type) type=$2; shift ;; esac; shift; done
if [[ ${list:-0} == 1 ]]; then [[ $primary == 1 ]] && { [[ -s $W/primary ]] && echo text/plain; exit 0; }; [[ -s $W/types ]] && cat "$W/types" || exit 1; exit 0; fi
if [[ $primary == 1 ]]; then [[ -s $W/primary ]] && cat "$W/primary" || exit 1; exit 0; fi
case $type in text | text/plain) cat "$W/clip.text" 2>/dev/null || exit 1 ;; *) cat "$W/clip.${type//\//_}" 2>/dev/null || exit 1 ;; esac
S
cat > "$T/bin/hyprctl" <<'S'
#!/bin/bash
echo "hyprctl args: $*" >> "$STUBLOG"
W="$STUBDIR/wl"
# The "up" half of Ctrl+C is when the stub application puts its selection on the clipboard.
if [[ $* == *'state = "up"'* && -f $W/after ]]; then cp "$W/after.types" "$W/types"; [[ -f $W/after ]] && cp "$W/after" "$W/clip.text"; fi
S
chmod +x "$T/bin/wl-paste" "$T/bin/hyprctl"
reset_wl() { rm -f "$W"/*; : > $STUBLOG; }
reset_wl; printf 'text/plain\n' > "$W/types"; printf 'old clip' > "$W/clip.text"; printf 'highlighted' > "$W/primary"
out=$("$P/grab.sh" primary); [[ $out == $'OMAPEGUI-GRAB kind=text src=primary\nhighlighted' ]] && ok "primary: header then the highlighted text" || { bad "primary"; echo "$out"; }
grep -q "hyprctl" $STUBLOG && bad "primary must not send Ctrl+C" || ok "primary: no Ctrl+C sent"
reset_wl; printf 'text/plain\n' > "$W/types"; printf 'old clip' > "$W/clip.text"; printf 'new selection' > "$W/after"; printf 'text/plain\n' > "$W/after.types"
out=$("$P/grab.sh" copy); [[ $out == $'OMAPEGUI-GRAB kind=text src=clipboard\nnew selection' ]] && ok "copy: Ctrl+C changed the clipboard, so the clipboard is used" || { bad "copy changed"; echo "$out"; }
grep -q 'mods = "CTRL", key = "C", state = "down"' $STUBLOG && grep -q 'state = "up"' $STUBLOG && ok "copy: Ctrl+C sent as down then up" || bad "ctrl-c keys"
reset_wl; printf 'text/plain\n' > "$W/types"; printf 'same' > "$W/clip.text"; printf 'from primary' > "$W/primary"
out=$("$P/grab.sh" copy); [[ $out == $'OMAPEGUI-GRAB kind=text src=primary\nfrom primary' ]] && ok "copy: clipboard unchanged, so PRIMARY is used" || { bad "copy fallback"; echo "$out"; }
reset_wl; printf 'text/plain\n' > "$W/types"; printf 'same' > "$W/clip.text"
out=$("$P/grab.sh" copy); [[ $out == "OMAPEGUI-GRAB kind=none" ]] && ok "copy: nothing changed and no PRIMARY -> none" || { bad "copy none"; echo "$out"; }
reset_wl; printf '   \n' > "$W/primary"; out=$("$P/grab.sh" primary); [[ $out == "OMAPEGUI-GRAB kind=none" ]] && ok "whitespace-only selection -> none" || { bad "blank"; echo "$out"; }
reset_wl; printf 'image/png\n' > "$W/types"; printf 'PNGBYTES' > "$W/clip.image_png"
printf 'image/png\n' > "$W/after.types"; printf 'x' > "$W/after"; rm -f "$W/types"   # clipboard empty before, an image after
printf 'PNGBYTES' > "$W/after.img"
cat > "$T/bin/hyprctl" <<'S'
#!/bin/bash
echo "hyprctl args: $*" >> "$STUBLOG"
W="$STUBDIR/wl"
[[ $* == *'state = "up"'* ]] && { printf 'image/png\n' > "$W/types"; printf 'PNGBYTES' > "$W/clip.image_png"; }
exit 0
S
out=$("$P/grab.sh" copy); name=$(printf PNGBYTES | sha256sum | cut -d' ' -f1).png
[[ $out == "OMAPEGUI-GRAB kind=image src=clipboard mime=image/png name=$name" && $(cat "$S/images/$name") == PNGBYTES ]] && ok "an image on the clipboard is saved under its hash" || { bad "image grab"; echo "$out"; }
[[ $(stat -c %a "$S/images/$name" 2>/dev/null || stat -f %Lp "$S/images/$name") == 600 ]] && ok "image file is private (0600)" || bad "image mode"
chk "bad mode refused" 2 "$P/grab.sh" nonsense
echo; [[ $FAILED == 0 ]] && echo "ALL PASSED" || echo "SOME FAILED"
rm -rf "$T"
