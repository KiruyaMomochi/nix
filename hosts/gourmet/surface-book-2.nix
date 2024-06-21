# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ inputs, config, lib, pkgs, ... }:

{
  imports =
    [
      inputs.nixos-hardware.nixosModules.microsoft-surface-common
    ];

  microsoft-surface.surface-control.enable = true;

  # https://wiki.archlinux.org/title/Microsoft_Surface_Book_2
  networking.networkmanager.wifi = {
    powersave = false;
    scanRandMacAddress = false;
  };

  # https://nixos.wiki/wiki/Nvidia
  hardware.opengl = {
    enable = true;
  };

  services.xserver.videoDrivers = [ "nvidia" "intel" ];
  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = false;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of 
    # supported GPUs is at: 
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus 
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.vulkan_beta;

    # Set PRIME pci ids
    prime = {
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:2:0:0";
      # Try reverse sync
      reverseSync.enable = true;
      # Enable if using an external GPU
      # To prevent system instability from hot-unplugging an eGPU while being
      # used to display the X11 desktop, the NVIDIA X driver does not configure
      # X screens on external GPUs by default.
      allowExternalGpu = false;
    };
  };

  specialisation = {
    no-nvidia.configuration = {
      system.nixos.tags = [ "no-nvidia" ];
      services.xserver.videoDrivers = lib.mkForce [ ];
      hardware.nvidia.modesetting.enable = lib.mkForce false;
    };
  };
}
