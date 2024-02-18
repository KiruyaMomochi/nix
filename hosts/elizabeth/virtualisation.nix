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

  # KVM
  virtualisation.libvirtd.enable = true;
  environment.systemPackages = with pkgs; [
    virt-manager
  ];
}
