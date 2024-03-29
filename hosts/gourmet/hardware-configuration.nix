# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/746c8122-94e3-4910-bdd8-35f6f8b2410f";
      fsType = "btrfs";
      options = [ "subvol=@root" ];
    };

  boot.initrd.luks.devices."system".device = "/dev/disk/by-uuid/7c8a8438-eed2-4a0f-9e3e-1d413bbb85d8";

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/746c8122-94e3-4910-bdd8-35f6f8b2410f";
      fsType = "btrfs";
      options = [ "subvol=@home" ];
    };

  fileSystems."/nix" =
    { device = "/dev/disk/by-uuid/746c8122-94e3-4910-bdd8-35f6f8b2410f";
      fsType = "btrfs";
      options = [ "subvol=@nix" ];
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/DC34-1C2C";
      fsType = "vfat";
    };

  swapDevices =
    [ { device = "/dev/disk/by-partlabel/cryptswap"; }
    ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp0s20f0u1u2u3.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp0s20f0u4u2.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp1s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
