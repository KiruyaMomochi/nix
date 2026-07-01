{ config, lib, pkgs, ... }:

{
  # https://nixos.wiki/wiki/Nvidia
  hardware.graphics.enable = true;

  boot.kernelParams = [
    # https://bbs.archlinux.org/viewtopic.php?id=286976
    "pcie_port_pm=off"
    # Mitigation for repeated Xid 79 "GPU has fallen off the bus" on 41:00
    # RTX PRO 6000 (2026-05-12). Disables PCIe ASPM globally as a
    # belt-and-suspenders measure. Root ports already report ASPM Disabled
    # in nvidia-bug-report, but the endpoint side might still negotiate it.
    "pcie_aspm=off"
  ];

  # Force MSI on the NVIDIA driver and skip preserving VRAM allocations
  # across power state transitions (we keep GPUs awake anyway, so this
  # extra bookkeeping is wasted work).
  boot.extraModprobeConfig = ''
    options nvidia NVreg_EnableMSI=1
    options nvidia NVreg_PreserveVideoMemoryAllocations=0
  '';

  services.xserver.videoDrivers = [ "nvidia" "modesetting" ];
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
    open = true;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.latest;
  };

  virtualisation.containers.containersConf.settings.engine.cdi_spec_dirs = [
    "/etc/cdi"
    "/var/run/cdi"
  ];

  security.pam.loginLimits = [{
    domain = "kyaru";
    item = "memlock";
    value = "infinity";
  }];
}
