{ config, pkgs, lib, ... }:
{
  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve+" ];
  };

  # https://github.com/NixOS/nixpkgs/issues/226365
  networking.firewall.interfaces."podman*".allowedUDPPorts = [ 53 5353 ];
  networking.firewall.interfaces."docker*".allowedUDPPorts = [ 53 5353 ];
  networking.firewall.trustedInterfaces = [ "virbr+" ];

  containers =
    let
      stateVersion = config.system.stateVersion;
    in
    { };

  # Podman
  virtualisation.podman = {
    enable = true;
    extraPackages = [ pkgs.btrfs-progs ];
    defaultNetwork.settings = {
      dns_enabled = true;
    };
  };

  # # https://github.com/NixOS/nixpkgs/issues/231191
  # environment.etc."resolv.conf".mode = "direct-symlink";

  virtualisation.docker = {
    # enable = true;
    storageDriver = "btrfs";
    rootless = {
      enable = true;
    };
  };
  users.users.kyaru.extraGroups = [ "docker" ];

  virtualisation.containers = {
    enable = true;
    storage.settings = {
      storage = {
        driver = "btrfs";
        graphroot = "/var/lib/containers/storage";
        runroot = "/run/containers/storage";
      };
    };
  };

  # KVM
  virtualisation.libvirtd.enable = true;
  environment.systemPackages = with pkgs; [
    virt-manager
  ];
}
