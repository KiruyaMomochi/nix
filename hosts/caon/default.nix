# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:
assert (lib.strings.removeSuffix "\n" (builtins.readFile ./secret.nix)) != "";
{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./virtualisation.nix
      ./secret.nix
      ./printing.nix
      ../desktop.nix
    ];

  fileSystems = {
    # "/".options = [ ];
    # "/home".options = [ ];
    "/nix".options = [ "noatime" ];
  };

  # Lanzaboote currently replaces the systemd-boot module.
  # This setting is usually set to true in configuration.nix
  # generated at installation time. So we force it to false
  # for now.
  boot.lanzaboote.enable = true;
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;

  system.autoUpgrade.enable = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Set your time zone.
  time.timeZone = "Asia/Taipei";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kyaru = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "adbusers" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      firefox
      tdesktop
      nil
    ];
    shell = pkgs.fish;
    description = "百地 希留耶";
  };
  nix.settings.trusted-users = [ "kyaru" ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [ ];

  # List services that you want to enable:
  # Enable the OpenSSH daemon.
  # Remote access
  # RDP
  services.xrdp.enable = true;

  # Networking
  hardware.bluetooth.enable = true;
  services.tailscale.enable = true;
  networking = {
    firewall = {
      enable = true;
      allowedTCPPorts = [ (config.services.zerotierone.port) 443 3389 8964 3090 ];
      allowedUDPPorts = [ (config.services.zerotierone.port) 3389 3478 8964 3090 41641 ];
      trustedInterfaces = [ "virbr0" ];
    };
    # hosts = {
    #   "151.101.66.217" = ["cache.nixos.org" "channels.nixos.org"];
    # };
    nat = {
      enable = true;
      internalInterfaces = [ "tailscale0" ];
    };
  };
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };

  services.telegraf.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It’s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
