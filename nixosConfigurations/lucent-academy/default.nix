{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./vivobook.nix
  ];

  kyaru.enable = true;
  kyaru.desktop.enable = true;

  boot.loader.systemd-boot = {
    enable = true;
    xbootldrMountPoint = "/boot";
    # /boot is 3G and the installer entry takes 1.5G of it; one generation is ~100M.
    configurationLimit = 10;
  };
  boot.loader.efi.efiSysMountPoint = "/efi";
  # The firmware entry was made from Windows with bcdedit. EFI runtime services on X1E
  # are unreliable (justririll/x1e-sleep runs with efi=noruntime), so never write efivars.
  boot.loader.efi.canTouchEfiVariables = false;

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
