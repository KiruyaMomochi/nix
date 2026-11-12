# Called by NixOS with the toplevel being installed. Environment from boot.nix:
# SDBOOT, DTB_NAME (fallback for generations without lucent-dtb-name), KEEP, KEYS.
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

mkdir -p "$esp/EFI/systemd" "$esp/EFI/BOOT" "$esp/loader" "$xbl/EFI/nixos" "$xbl/loader/entries"
install_efi "$SDBOOT" "$esp/EFI/systemd/systemd-bootaa64.efi"
install_efi "$SDBOOT" "$esp/EFI/BOOT/BOOTAA64.EFI"

current=$(readlink -f "$1")
default=""
wanted=()
mapfile -t gens < <(find /nix/var/nix/profiles -maxdepth 1 -name 'system-*-link' -printf '%f\n' \
  | sed -E 's/^system-([0-9]+)-link$/\1/' | sort -n | tail -n "$KEEP")

# install_el2 GEN TOPLEVEL UKI: the EL2 entry lives on the ESP because its launcher and
# drivers do (qebspil reads /firmware and slbounce reads /tcblaunch.exe from their own
# volume). The launcher has the UKI path compiled in, so the newest el2 UKI is copied to
# that one name; generations are walked oldest first, so the last call wins.
el2_installed=""
install_el2() {
  local g=$1 top=$2 uki=$3 fw f src
  if [ ! -e "$esp/tcblaunch.exe" ]; then
    echo "skipping EL2 entry: $esp/tcblaunch.exe missing" >&2
    return
  fi
  mkdir -p "$esp/EFI/el2" "$esp/loader/entries"
  install_efi "$top/lucent-el2/launcher.efi" "$esp/EFI/el2/launcher.efi"
  install_efi "$top/lucent-el2/qebspilaa64.efi" "$esp/EFI/el2/qebspilaa64.efi"
  install_efi "$top/lucent-el2/slbounceaa64.efi" "$esp/EFI/el2/slbounceaa64.efi"
  fw=qcom/x1e80100/ASUSTeK/vivobook-s15
  mkdir -p "$esp/firmware/$fw"
  for f in qcadsp8380.mbn adsp_dtbs.elf qccdsp8380.mbn cdsp_dtbs.elf; do
    src="$top/firmware/$fw/$f"
    if [ -e "$src.zst" ]; then zstd -qdcf "$src.zst" > "$esp/firmware/$fw/$f.tmp"
    elif [ -e "$src" ]; then cp -L "$src" "$esp/firmware/$fw/$f.tmp"
    else echo "skipping EL2 entry: $f not in $top/firmware" >&2; return
    fi
    mv "$esp/firmware/$fw/$f.tmp" "$esp/firmware/$fw/$f"
  done
  cp "$uki" "$xbl/EFI/nixos/lucent-el2.efi.tmp"
  mv "$xbl/EFI/nixos/lucent-el2.efi.tmp" "$xbl/EFI/nixos/lucent-el2.efi"
  {
    echo "title NixOS (el2-cxsd, experimental)"
    echo "version Generation $g"
    echo "efi /EFI/el2/launcher.efi"
    echo "sort-key nixos-zz-el2"
  } > "$esp/loader/entries/lucent-el2.conf.tmp"
  mv "$esp/loader/entries/lucent-el2.conf.tmp" "$esp/loader/entries/lucent-el2.conf"
  el2_installed=1
  echo "installed EL2 entry (generation $g)"
}

# install_one GEN TOPLEVEL [SPECIALISATION]
install_one() {
  local g=$1 top=$2 spec=${3:-} uki entry out label built title dtb=$DTB_NAME
  if [ -e "$top/lucent-dtb-name" ]; then dtb=$(cat "$top/lucent-dtb-name"); fi
  if [ -n "$spec" ]; then
    uki="nixos-generation-$g-$spec-$(basename "$top" | cut -c1-8).efi"
    entry="nixos-generation-$g-specialisation-$spec.conf"
    title="NixOS ($spec)"
  else
    uki="nixos-generation-$g-$(basename "$top" | cut -c1-8).efi"
    entry="nixos-generation-$g.conf"
    title="NixOS"
  fi
  wanted+=("$uki" "$entry")
  out="$xbl/EFI/nixos/$uki"

  # Already there, and signed if we sign: keep it.
  if ! { [ -e "$out" ] && { [ ${#sign[@]} -eq 0 ] || sbverify --cert "$KEYS/db.pem" "$out" >/dev/null 2>&1; }; }; then
    ukify build \
      --linux="$top/kernel" \
      --initrd="$top/initrd" \
      --devicetree="$top/dtbs/$dtb" \
      --cmdline="init=$top/init $(cat "$top/kernel-params")" \
      --os-release="@$top/etc/os-release" \
      "${sign[@]}" \
      --output="$out.tmp" >/dev/null 2>&1
    mv "$out.tmp" "$out"
    echo "installed $uki${sign:+ (signed)}"
  fi

  if [ -d "$top/lucent-el2" ]; then install_el2 "$g" "$top" "$out"; fi

  # Same title/version/sort-key as nixpkgs' systemd-boot builder writes, but the
  # entry points at the UKI instead of linux/initrd/devicetree.
  label=$(jq -r '."org.nixos.bootspec.v1".label' "$top/boot.json")
  built=$(date -d "@$(stat -L -c %Z "$profile-$g-link")" +%F)
  {
    echo "title $title"
    echo "version Generation $g $label, built on $built"
    echo "uki /EFI/nixos/$uki"
    echo "sort-key nixos"
  } > "$xbl/loader/entries/$entry.tmp"
  mv "$xbl/loader/entries/$entry.tmp" "$xbl/loader/entries/$entry"
}

for g in "${gens[@]}"; do
  top=$(readlink -f "$profile-$g-link")
  if [ "$top" = "$current" ]; then default="nixos-generation-$g.conf"; fi
  install_one "$g" "$top"
  # Specialisations get their own UKI: with Secure Boot the stub won't take a
  # cmdline from the entry, so a different kernel-params needs a different image.
  for s in "$top"/specialisation/*; do
    [ -e "$s" ] || continue
    install_one "$g" "$(readlink -f "$s")" "$(basename "$s")"
  done
done

for f in "$xbl"/EFI/nixos/nixos-generation-*.efi "$xbl"/loader/entries/nixos-generation-*.conf; do
  [ -e "$f" ] || continue
  found=0
  for w in "${wanted[@]}"; do
    if [ "$(basename "$f")" = "$w" ]; then found=1; fi
  done
  if [ $found = 0 ]; then rm -f "$f"; echo "removed $(basename "$f")"; fi
done

if [ -z "$el2_installed" ]; then
  rm -f "$esp/loader/entries/lucent-el2.conf" "$xbl/EFI/nixos/lucent-el2.efi"
fi

if [ -z "$default" ]; then default="nixos-generation-${gens[-1]}.conf"; fi
printf 'timeout 5\ndefault %s\nconsole-mode keep\n' "$default" > "$esp/loader/loader.conf.tmp"
mv "$esp/loader/loader.conf.tmp" "$esp/loader/loader.conf"
sync
