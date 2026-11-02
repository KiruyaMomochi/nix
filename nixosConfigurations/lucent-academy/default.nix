{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./vivobook.nix
  ];

  # Fan control via the EC. Read vivobook-s15-fedora docs/ec-fan-control.md first.
  hardware.vivobook-s15.experimentalEC = true;

  kyaru.enable = true;
  kyaru.desktop.enable = true;

  boot.loader.systemd-boot = {
    enable = true;
    xbootldrMountPoint = "/boot";
    # /boot is 3G and the installer entry takes 1.5G of it; one generation is ~100M.
    configurationLimit = 10;
  };
  boot.loader.efi.efiSysMountPoint = "/efi";
  # The firmware reports Alt held on every key after the first, so the stock menu
  # only reacts to number keys. Copy our build over what bootctl installed.
  boot.loader.systemd-boot.extraInstallCommands =
    let
      efi = "${pkgs.callPackage ./sdboot.nix { }}/systemd-bootaa64.efi";
    in
    ''
      ${pkgs.coreutils}/bin/install -m 0700 ${efi} /efi/EFI/systemd/systemd-bootaa64.efi
      ${pkgs.coreutils}/bin/install -m 0700 ${efi} /efi/EFI/BOOT/BOOTAA64.EFI
    '';
  # The firmware entry was made from Windows with bcdedit. EFI runtime services on X1E
  # are unreliable (justririll/x1e-sleep runs with efi=noruntime), so never write efivars.
  boot.loader.efi.canTouchEfiVariables = false;

  # Built-in numpad. The Wayland greeter is KWin, which ignores sddm.conf's
  # Numlock and reads kcminputrc from sddm's home instead (NumLock=0 means on).
  services.displayManager.sddm.autoNumlock = true;
  systemd.tmpfiles.settings."10-sddm-numlock" = {
    "/var/lib/sddm/.config".d = {
      user = "sddm";
      group = "sddm";
      mode = "0755";
    };
    "/var/lib/sddm/.config/kcminputrc"."L+".argument = "${pkgs.writeText "sddm-kcminputrc" ''
      [Keyboard]
      NumLock=0
    ''}";
  };

  hardware.graphics.enable = true;
  hardware.bluetooth.enable = true;

  users.users.kyaru.uid = 1000;
  users.users.kyaru.extraGroups = [ "video" "audio" ];
  users.users.kyaru.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHt7EEGFGu0Yg/XlowRZugaAWaHtdwOwx52VH6/5Yzn9 kyaru@caon"
  ];

  time.timeZone = "Asia/Taipei";
  environment.systemPackages = with pkgs; [ nushell ];
  programs.kdeconnect.enable = true;

  system.stateVersion = "26.05";
}
