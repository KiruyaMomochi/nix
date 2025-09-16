{ config, pkgs, lib, ... }:
let
  vfioIds = [
    # intel graphics
    "8086:a780"
    # audio device is in the same IOMMU group as PCH SMBus controller, hence commented out
    # "8086:7ad0"
  ];
  macvtaps = [
    "macvtap0"
    "macvtap1"
    "macvtap2"
  ];
in
{
  environment.systemPackages = with pkgs; [
    virt-manager
    # Also need to use <binary path='/run/current-system/sw/bin/virtiofsd' xattr='on'>
    # https://github.com/NixOS/nixpkgs/issues/113172
    virtiofsd
    swtpm
  ];

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

  # https://github.com/NixOS/nixpkgs/issues/226365
  networking.firewall.interfaces."podman*".allowedUDPPorts = [ 53 5353 ];
  networking.firewall.interfaces."docker*".allowedUDPPorts = [ 53 5353 ];

  containers = { };

  # Podman
  virtualisation.podman = {
    enable = true;
    extraPackages = [ ];
    defaultNetwork.settings = {
      dns_enabled = true;
    };
  };

  # KVM
  virtualisation.libvirtd = {
    enable = true;
    extraConfig = ''
      uri_default = "qemu:///systtem"
      unix_sock_group = "libvirtd"
      unix_sock_rw_perms = "0770"
    '';
  };

  # single thread download under bad network environment
  virtualisation.containers.containersConf.settings = {
    engine.image_parallel_copies = 1;
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
  boot.kernelParams = [
    # https://forums.unraid.net/topic/76529-notes-about-supermicro-x11sca-f/page/2/
    "i915.disable_display=1"
    # required for gvt-g, not sure for gvt-d
    "i915.enable_gvt=1"
    # https://gist.github.com/mikroskeem/fdbbbd35d7273aa77ba9ebc11e7b8e5d
    "kvm.ignore_msrs=1"
    "intel_iommu=on"
    # prevent Linux from touching devices which cannot be passed through
    "iommu=pt"
    # https://astrid.tech/2022/09/22/0/nixos-gpu-vfio/
    ("vfio-pci.ids=" + lib.concatStringsSep "," vfioIds)
  ];

  # boot.blacklistedKernelModules = [ "i915" ];
  # boot.initrd.availableKernelModules = [
  #   "i915"
  #   "vfio-pci"
  # ];

  # Why 40?
  # See https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/tasks/network-interfaces-systemd.nix
  systemd.network.networks = {
    "40-eno1" = {
      macvtap = macvtaps;
    };
    "40-virbr1" = {
      matchConfig = {
        Name = "virbr1";
      };
      networkConfig = {
        Address = "192.168.87.1/24";
        Gateway = "192.168.87.1";
        DNS = "192.168.87.11";
        Domains = "corp.kyaru.bond";
        # IPMasquerade = "ipv4";
      };
      dhcpV4Config = {
        UseRoutes = false;
        RouteMetric = 32767;
      };
    };
  };

  systemd.network.netdevs = {
    "40-virbr1" = {
      netdevConfig = {
        Name = "virbr1";
        Kind = "bridge";
      };
    };
  } // (builtins.listToAttrs (builtins.map
    (name: {
      name = "40-${name}";
      value = {
        netdevConfig = {
          Name = name;
          Kind = "macvtap";
        };
        extraConfig = ''
          [MACVTAP]
          Mode=bridge
        '';
      };
    })
    macvtaps));

  # VMWare
  # virtualisation.vmware.host = {
  #   enable = true;
  # };
  boot.kernelModules = [
    "kvm_intel"
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
    "vfio_virqfd"
  ];

  services.cockpit = {
    enable = true;
    openFirewall = true;
    port = 9090;
  };
}
