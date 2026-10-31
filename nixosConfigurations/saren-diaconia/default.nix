{ inputs, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./fan.nix
    inputs.nixos-hardware.nixosModules.gpd-pocket-4
  ];

  kyaru.enable = true;
  kyaru.desktop.enable = true;
  virtualisation.podman.enable = true;

  fileSystems = {
    "/".options = [ "compress=zstd" ];
    "/home".options = [ "compress=zstd" ];
    "/nix".options = [ "compress=zstd" "noatime" ];
    "/swap".options = [ "noatime" ];
  };
  swapDevices = [{ device = "/swap/swapfile"; size = 16 * 1024; }];

  # Plain systemd-boot for now; switch to lanzaboote once Secure Boot is set up.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  services.fwupd.enable = true;
  hardware.graphics.enable = true;
  hardware.bluetooth.enable = true;

  # Pinned to what the installer assigned, so other modules can refer to it.
  users.users.kyaru.uid = 1000;
  users.users.kyaru.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHt7EEGFGu0Yg/XlowRZugaAWaHtdwOwx52VH6/5Yzn9 kyaru@caon"
  ];

  time.timeZone = "Asia/Taipei";
  environment.systemPackages = with pkgs; [ nushell ];
  programs.kdeconnect.enable = true;

  system.stateVersion = "26.11";
}
