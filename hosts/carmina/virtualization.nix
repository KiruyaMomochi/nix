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

  # Docker
  # virtualisation.docker = {
  #   enable = true;
  #   daemon.settings = {
  #     registry-mirrors = [
  #       "https://hub-mirror.c.163.com"
  #     ];
  #   };
  #   extraOptions  = "--iptables=False";
  #   rootless = {
  #     enable = true;
  #     setSocketVariable = true;/
  #   };
  # };
  # virtualisation.docker.storageDriver = "btrfs";

  # LXD and LXC
  # virtualisation.lxd.enable = true;
  # virtualisation.lxc.enable = true;
  # virtualisation.lxc.lxcfs.enable = true;

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
