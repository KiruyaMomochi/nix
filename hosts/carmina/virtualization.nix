{ config, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    virt-manager
    swtpm
  ];

  networking.firewall.trustedInterfaces = [ "virbr1" ];

  # KVM
  virtualisation.libvirtd = { enable = true; };
  boot.extraModprobeConfig = ''
    options kvm_intel nested=1
    options kvm_intel emulate_invalid_guest_state=0
    options kvm ignore_msrs=1
  '';


  # LXD and LXC
  # virtualisation.lxd.enable = true;
  # virtualisation.lxc.enable = true;
  # virtualisation.lxc.lxcfs.enable = true;

  # VMWare
  virtualisation.vmware.host = {
    enable = true;
  };

  # boot.binfmt.emulatedSystems = [
  #   "riscv64-linux"
  # ];
  # boot.binfmt.registrations.riscv64-linux = 
  # let
  #   getEmulator = system: (lib.systems.elaborate { inherit system; }).emulator pkgs;
  #   getQemuArch = system: (lib.systems.elaborate { inherit system; }).qemuArch;
  #   system = "riscv64-linux"; 
  # in
  # {
  #   # interpreter = getEmulator system;
  #   fixBinary = true;
  #   openBinary = true;
  #   matchCredentials = true;
  #   # preserveArgvZero = false;
  #   # wrapInterpreterInShell = false;
  # };
}
