# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ inputs, config, lib, pkgs, ... }:

{
  imports =
    [
      inputs.nixos-hardware.nixosModules.microsoft-surface-common
    ];

  # https://wiki.archlinux.org/title/Microsoft_Surface_Book_2
  networking.networkmanager.wifi = {
    powersave = false;
    scanRandMacAddress = false;
  };
}
