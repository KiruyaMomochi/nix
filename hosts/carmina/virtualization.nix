{ config, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    virt-manager
    swtpm
  ];

  networking.firewall.trustedInterfaces = [ "virbr1" ];

  # KVM
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      swtpm.enable = true;
      ovmf.enable = true;
      ovmf.packages = [ pkgs.OVMFFull.fd ]; # Secure boot
    };
  };
  boot.extraModprobeConfig = ''
    options kvm_intel nested=1
    options kvm_intel emulate_invalid_guest_state=0
    options kvm ignore_msrs=1
  '';

  environment.etc = {
    "ovmf/edk2-x86_64-secure-code.fd" = {
      source = config.virtualisation.libvirtd.qemu.package + "/share/qemu/edk2-x86_64-secure-code.fd";
    };

    "ovmf/edk2-i386-vars.fd" = {
      source = config.virtualisation.libvirtd.qemu.package + "/share/qemu/edk2-i386-vars.fd";
    };
  };

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
    dockerCompat = true;
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
    extraPackages = with pkgs; [ ntfs3g ];
    extraConfig = ''
      # Allow unsupported device's OpenGL and Vulkan acceleration for guest vGPU
      mks.gl.allowUnsupportedDrivers = "TRUE"
      mks.vk.allowUnsupportedDevices = "TRUE"
    '';
  };
  # VMWare Fix
  boot.kernelParams = [
    "ibt=off"
  ];
  nixpkgs.overlays = lib.singleton (self: super: {
    # https://nixos.wiki/wiki/Linux_kernel#Overriding_kernel_packages
    linuxPackages_latest = super.linuxPackages_latest.extend (kself: ksuper: {
      # vmware = ksuper.vmware.overrideAttrs(oldAttrs: let version = "17.0.2"; in {
      #   version = "${version}-${kself.kernel.version}";
      #   src = self.fetchFromGitHub {
      #     owner = "mkubecek";
      #     repo = "vmware-host-modules";
      #     rev = "w${version}";
      #     sha256 = "sha256-ziTGF+ZpcMIZ97UdOFuD4UxrlyOrZxMJ/ysSZu41A7o=";
      #   };
      # });
      vmware = ksuper.vmware.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or []) ++ [(self.fetchpatch {
          name = "fix-gso-undefined.patch";
          sha256 = "sha256-VhbRDJHyfyMrRCflRbf05GPi1/b2OdpjIPgTeOvMZrM=";
          url = "https://github.com/mkubecek/vmware-host-modules/commit/b75cd616cca0a4c9ff22124c4c91d218e64e6205.patch";
        })];
      });
    });
  });

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
