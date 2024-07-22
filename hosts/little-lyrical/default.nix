{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../modules/vps.nix
  ];

  boot.loader.grub.device = "/dev/vda"; # or "nodev" for efi only
  time.timeZone = "Europe/Amsterdam";

  # InfluxDB
  # https://github.com/NixOS/nixpkgs/issues/253877
  services.influxdb2 = {
    enable = true;
  };

  # Grafana
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
      };
    };
  };

  # services.loki = {
  #   enable = true;
  # };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
