# Called by NixOS with the toplevel being installed. Environment from boot.nix:
# SDBOOT, DTB_NAME, KEEP, KEYS.
esp=/efi
xbl=/boot
profile=/nix/var/nix/profiles/system

for m in "$esp" "$xbl"; do
  if ! mountpoint -q "$m"; then echo "$m is not mounted" >&2; exit 1; fi
done

sign=()
if [ -e "$KEYS/db.key" ]; then
  sign=(--signtool=sbsign --secureboot-private-key="$KEYS/db.key" --secureboot-certificate="$KEYS/db.pem")
fi

install_efi() {
  if [ ${#sign[@]} -gt 0 ]; then
    sbsign --key "$KEYS/db.key" --cert "$KEYS/db.pem" --output "$2.tmp" "$1" 2>/dev/null
  else
    cp "$1" "$2.tmp"
  fi
  mv "$2.tmp" "$2"
}

mkdir -p "$esp/EFI/systemd" "$esp/EFI/BOOT" "$esp/loader" "$xbl/EFI/Linux"
install_efi "$SDBOOT" "$esp/EFI/systemd/systemd-bootaa64.efi"
install_efi "$SDBOOT" "$esp/EFI/BOOT/BOOTAA64.EFI"

current=$(readlink -f "$1")
default=""
wanted=()
mapfile -t gens < <(find /nix/var/nix/profiles -maxdepth 1 -name 'system-*-link' -printf '%f\n' \
  | sed -E 's/^system-([0-9]+)-link$/\1/' | sort -n | tail -n "$KEEP")

for g in "${gens[@]}"; do
  top=$(readlink -f "$profile-$g-link")
  name="nixos-generation-$g-$(basename "$top" | cut -c1-8).efi"
  wanted+=("$name")
  if [ "$top" = "$current" ]; then default=$name; fi
  out="$xbl/EFI/Linux/$name"

  # Already there, and signed if we sign: nothing to do.
  if [ -e "$out" ]; then
    if [ ${#sign[@]} -eq 0 ] || sbverify --cert "$KEYS/db.pem" "$out" >/dev/null 2>&1; then
      continue
    fi
  fi

  osr=$(mktemp)
  {
    grep -vE '^(PRETTY_NAME|IMAGE_VERSION)=' "$top/etc/os-release"
    echo "PRETTY_NAME=\"NixOS generation $g\""
    echo "IMAGE_VERSION=$g"
  } > "$osr"
  ukify build \
    --linux="$top/kernel" \
    --initrd="$top/initrd" \
    --devicetree="$top/dtbs/$DTB_NAME" \
    --cmdline="init=$top/init $(cat "$top/kernel-params")" \
    --os-release="@$osr" \
    "${sign[@]}" \
    --output="$out.tmp" >/dev/null
  rm -f "$osr"
  mv "$out.tmp" "$out"
  echo "installed $name${sign:+ (signed)}"
done

for f in "$xbl"/EFI/Linux/nixos-generation-*.efi; do
  [ -e "$f" ] || continue
  found=0
  for w in "${wanted[@]}"; do
    if [ "$(basename "$f")" = "$w" ]; then found=1; fi
  done
  if [ $found = 0 ]; then rm -f "$f"; echo "removed $(basename "$f")"; fi
done

if [ -z "$default" ]; then default=${wanted[-1]}; fi
printf 'timeout 5\ndefault %s\nconsole-mode keep\n' "$default" > "$esp/loader/loader.conf.tmp"
mv "$esp/loader/loader.conf.tmp" "$esp/loader/loader.conf"
sync
