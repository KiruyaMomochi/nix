{ config, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    virt-manager
    # Also need to use <binary path='/run/current-system/sw/bin/virtiofsd' xattr='on'>
    # https://github.com/NixOS/nixpkgs/issues/113172
    virtiofsd
    swtpm
  ];

  networking.firewall.trustedInterfaces = [ "virbr+" "vnet+" ];
  networking.firewall.allowedUDPPorts = [
    # DNS
    53
    5353
    # DHCP
    67
    68
  ];
  networking.firewall.allowedTCPPortRanges = [
    # spice
    { from = 5900; to = 5999; }
  ];
  networking.firewall.allowedTCPPorts = [
    # libvirt
    16509
  ];

  # KVM
  virtualisation.libvirtd = {
    enable = true;
    extraConfig = ''
      uri_default = "qemu:///systtem"
      unix_sock_group = "libvirtd"
      unix_sock_rw_perms = "0770"
    '';
  };
  boot.extraModprobeConfig = ''
    options kvm_intel nested=1
    options kvm_intel emulate_invalid_guest_state=0
    options kvm ignore_msrs=1
  '';
  networking.firewall.checkReversePath = "loose";
  # USB passthrough
  virtualisation.spiceUSBRedirection.enable = true;

  # https://gist.github.com/techhazard/1be07805081a4d7a51c527e452b87b26
  # CHANGE: intel_iommu enables iommu for intel CPUs with VT-d
  # use amd_iommu if you have an AMD CPU with AMD-Vi
  boot.kernelParams = [ "intel_iommu=on" ];

  services.cockpit = {
    enable = true;
    openFirewall = true;
  };

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
  # networking.firewall.interfaces.podman0.allowedUDPPorts = [ 53 5353 ];

  virtualisation.containers = {
    enable = true;
    storage.settings = {
      storage = {
        driver = "overlay";
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
