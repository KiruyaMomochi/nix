# 裝機前的佔位版本，用 label 掛載。裝好後用 nixos-generate-config 生成的蓋掉。
# 分區：Windows 縮完後新建
#   1G  vfat  label=NIXBOOT  （Windows 那個 100M ESP 塞不下幾代內核，另開一個）
#   剩下 btrfs label=nixos，subvol: root nix home swap
{ config, lib, modulesPath, ... }:
let
  btrfs = subvol: {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=${subvol}" ];
  };
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "thunderbolt" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];

  fileSystems."/" = btrfs "root";
  fileSystems."/nix" = btrfs "nix";
  fileSystems."/home" = btrfs "home";
  fileSystems."/swap" = btrfs "swap";
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXBOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
