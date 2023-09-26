{ config, pkgs, lib, ... }:
{
  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve+" ];
  };

  # https://github.com/NixOS/nixpkgs/issues/226365
  networking.firewall.interfaces.podman0.allowedUDPPorts = [ 53 5353 ];

  containers =
    let
      stateVersion = config.system.stateVersion;
    in
    { };

  # Podman
  virtualisation.podman = {
    enable = true;
    extraPackages = [ pkgs.btrfs-progs ];
    dockerSocket.enable = true;
    # Create a `docker` alias for podman, to use it as a drop-in replacement
    dockerCompat = false;
    # Required for containers under podman-compose to be able to talk to each other.
    defaultNetwork.settings = {
      dns_enabled = true;
    };
  };

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
}