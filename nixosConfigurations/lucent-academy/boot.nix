{ config, pkgs, ... }:

# Boot signed UKIs instead of Type 1 entries. With Secure Boot on, systemd-boot ignores a
# Type 1 entry's `devicetree` line (src/boot/boot.c) and this machine needs its DT; the
# stub loads the .dtb embedded in a UKI either way. lanzaboote has no DT support yet
# (nix-community/lanzaboote#369).
#
# /efi is the Windows ESP (systemd-boot, loader.conf); /boot is XBOOTLDR: UKIs in EFI/nixos,
# and Type 1 entries that point at them (`uki`), so the menu reads like nixpkgs' builder.
# Everything is signed once `sbctl create-keys` has been run; before that it stays unsigned.
# Never writes EFI variables: the firmware entry was made from Windows with bcdedit.
let
  installHook = pkgs.writeShellApplication {
    name = "lucent-install-bootloader";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
      gnused
      jq
      util-linux
      sbsigntool
      systemdUkify
    ];
    runtimeEnv = {
      # Patched for this firmware, see ./sdboot.nix.
      SDBOOT = "${pkgs.callPackage ./sdboot.nix { }}/systemd-bootaa64.efi";
      DTB_NAME = config.hardware.deviceTree.name;
      # /boot is 3G, the installer entry takes 1.5G, one UKI is ~100M.
      KEEP = "5";
      KEYS = "/var/lib/sbctl/keys/db";
    };
    text = builtins.readFile ./install-bootloader.sh;
  };
in
{
  boot.loader.external = {
    enable = true;
    installHook = "${installHook}/bin/lucent-install-bootloader";
  };
  boot.loader.efi.efiSysMountPoint = "/efi";

  # Each toplevel (specialisations included) records its own DT, so a specialisation
  # with a different hardware.deviceTree.name gets that DT in its UKI.
  system.extraSystemBuilderCmds = ''
    echo -n ${config.hardware.deviceTree.name} > $out/lucent-dtb-name
  '';

  environment.systemPackages = [ pkgs.sbctl ];
}
