# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];


  kyaru.enable = true;
  kyaru.vps.enable = true;

  services.nginx.enable = lib.mkForce false;
  services.tailscale = {
    enable = true;
    derper = {
      openFirewall = true;
      # TODO: Not enabling tailscale derp server
      # as it has a hard dependency on nginx
      # Need to consider manually implement with caddy instead?
      # https://github.com/NixOS/nixpkgs/blob/7905f79129074b6f709df4ac9fa7594e36329aad/nixos/modules/services/networking/tailscale-derper.nix#L70
      verifyClients = true;
    };
  };

  # Define on which hard drive you want to install Grub.
  boot.loader.grub.device = "/dev/vda"; # or "nodev" for efi only

  networking.tempAddresses = "disabled";
  # Set your time zone.
  time.timeZone = "Asia/Taipei";
  # Select internationalisation properties.
  i18n.defaultLocale = "zh_TW.UTF-8";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  kyaru.vps.user.name = "yui";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?
}
