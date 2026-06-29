{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  kyaru.enable = true;
  kyaru.vps.enable = true;
  boot.loader.grub.device = "/dev/sda";
  time.timeZone = "America/New_York";

  system.stateVersion = "24.05";
}
