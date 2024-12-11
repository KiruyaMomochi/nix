# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:
let
  inherit (lib.modules) mkForce;
in
{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./virtualisation.nix
    ];

  kyaru.enable = true;
  kyaru.desktop.enable = true;
  virtualisation.docker.enable = true;
  virtualisation.podman.enable = true;
  # virtualisation.docker.rootless.enable = true;

  # Filesystem
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

  boot.kernelModules = [
    "nft_tproxy"
    "nft_socket"
    "amdgpu"
  ];

  # Use latest kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  services.fwupd.enable = true;

  # For AMD
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      amdvlk
    ];
  };
  hardware.cpu.amd.updateMicrocode = true;
  services.xserver.videoDrivers = [ "amdgpu" ];

  # Set your time zone.
  time.timeZone = "Asia/Taipei";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kyaru = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "adbusers" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      firefox
      telegram-desktop
    ];
    shell = pkgs.nushell;
    description = "百地 希留耶";
  };
  nix.settings.trusted-users = [ "kyaru" ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [ nushell ];

  # Programs
  programs.kdeconnect.enable = true;

  # List services that you want to enable:
  system.autoUpgrade.enable = true;

  # Networking
  hardware.bluetooth.enable = true;
  networking = {
    nat = {
      enable = true;
      internalInterfaces = [ "tailscale0" ];
    };
    networkmanager.dispatcherScripts = [
      {
        type = "pre-up";
        source = pkgs.writeText "enableGroHook" ''
          if [[ "$DEVICE_IFACE" == wlp* ]] || [[ "$DEVICE_IFACE" == enp* ]]; then
            ${pkgs.ethtool}/bin/ethtool -K "$DEVICE_IFACE" rx-udp-gro-forwarding on rx-gro-list off
            >&2 echo "Enable GRO for $DEVICE_IFACE finished with exit code $?"
          fi
        '';
      }
    ];
  };
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };

  # Wireshark
  programs.wireshark.enable = true;

  # fail to compile
  # services.guix.enable = true;

  services.cloudflared = {
    # enable = true;
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It’s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
