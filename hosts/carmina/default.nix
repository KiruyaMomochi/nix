# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:
{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./virtualization.nix
      ../modules/desktop.nix
    ];

  fileSystems = {
    "/".options = [ "compress=zstd" ];
    "/home".options = [ "compress=zstd" ];
    "/nix".options = [ "compress=zstd" "noatime" ];
    "/swap".options = [ "noatime" ];
  };
  swapDevices = [{ device = "/swap/swapfile"; }];

  # Lanzaboote currently replaces the systemd-boot module.
  # This setting is usually set to true in configuration.nix
  # generated at installation time. So we force it to false
  # for now.
  boot.lanzaboote.enable = true;
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;

  # https://github.com/mkubecek/vmware-host-modules/issues/202
  # boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernelModules = [
    "nft_tproxy"
    "nft_socket"
    "i2c_dev"
  ];

  hardware.bluetooth.enable = true;
  networking = {
    hosts = {
      "10.15.89.181" = [ "rancher.geekpie.tech" ];
      "100.64.0.38" = [ "google.com" "www.google.com" "translate.google.com" ];
      # "151.101.66.217" = ["cache.nixos.org" "channels.nixos.org"];
    };
    nat = {
      enable = true;
      internalInterfaces = [ "tailscale0" "ve+" ];
    };
  };
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };

  # Enable wacom
  services.xserver.wacom.enable = true;

  # Enable RDP
  services.xserver.desktopManager.lxqt.enable = config.services.xrdp.enable;
  services.xserver.windowManager.openbox.enable = config.services.xserver.desktopManager.lxqt.enable;
  services.xrdp.enable = true;
  services.xrdp.defaultWindowManager = "startlxqt";
  services.xrdp.openFirewall = true;

  # Set your time zone.
  time.timeZone = "Asia/Taipei";

  programs.kdeconnect.enable = true;
  services.flatpak.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kyaru = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" "libvirtd" "lxd" "podman" "wireshark" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      tdesktop
    ];
    shell = pkgs.fish;
    description = "百地 希留耶";
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [ ];

  # School is polluting DNS and the changed DNS server's DNSSEC is broken so
  services.resolved.dnssec = "false";

  services.openssh.ports = [ 22 5022 ];
  system.autoUpgrade.enable = true;
  programs.wireshark.enable = true;

  # Singularity
  programs.singularity = {
    enableSuid = true;
    enableFakeroot = true;
    enable = true;
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
