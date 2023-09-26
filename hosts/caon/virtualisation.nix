{ config, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    virt-manager
    swtpm
  ];

  networking.firewall.trustedInterfaces = [ "virbr+" ];

  # KVM
  virtualisation.libvirtd = { enable = true; };
  boot.extraModprobeConfig = ''
    options kvm_intel nested=1
    options kvm_intel emulate_invalid_guest_state=0
    options kvm ignore_msrs=1
  '';

  # Podman
  virtualisation.podman = {
    enable = true;
    extraPackages = [ pkgs.btrfs-progs ];
    # Required for containers under podman-compose to be able to talk to each other.
    defaultNetwork.settings = {
      dns_enabled = true;
    };
  };
  # https://github.com/NixOS/nixpkgs/issues/226365
  networking.firewall.interfaces.podman0.allowedUDPPorts = [ 53 5353 ];

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

  # VMWare
  virtualisation.vmware.host = {
    enable = true;
  };
}
