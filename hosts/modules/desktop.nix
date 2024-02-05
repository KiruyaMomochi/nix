{ config, pkgs, lib, ... }:
let
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.lists) optional;
in
{
  hardware.opengl = {
    driSupport = true;
    driSupport32Bit = true;
  };

  boot.supportedFilesystems = [ "ntfs" ];

  # Select internationalisation properties.
  i18n.supportedLocales = [ "all" ];
  i18n.inputMethod = {
    enabled = "fcitx5";
    fcitx5.waylandFrontend = true;

    fcitx5.addons = with pkgs; [
      fcitx5-chewing
      fcitx5-rime
      fcitx5-mozc
    ];
  };

  console = {
    font = "Lat2-Terminus16";
    # keyMap = "us";
    useXkbConfig = true; # use xkbOptions in tty.
  };

  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  networking.networkmanager.dns = "systemd-resolved";
  services.resolved.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # KDE
  services.xserver.desktopManager.plasma5.enable = true;
  services.xserver.displayManager.sddm.enable = true;
  programs.partition-manager.enable = true;
  # Fix GTK themes are not applied in Wayland applications
  programs.dconf.enable = true;

  # programs.sway.enable = true;
  programs.hyprland.enable = true;

  # screenshot
  xdg.portal.wlr.enable = true;

  # Configure keymap in X11
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = {
  #   "eurosign:e";
  #   "caps:escape" # map caps to escape.
  # };

  # Enable sound with pipewire.
  # Remove sound.enable or turn it off if you had it set previously, it seems to cause conflicts with pipewire
  # sound.enable = false;
  # hardware.pulseaudio.enable = true;
  # rtkit is optional but recommended
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.adb.enable = true;

  programs.firejail.enable = true;
  programs.firejail.wrappedBinaries = { };

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  services.xserver.libinput.enable = true;
  services.openssh.settings.X11Forwarding = true;
  services.xrdp = {
    defaultWindowManager = mkDefault "startplasma-x11";
    openFirewall = true;
  };

  environment.systemPackages = with pkgs; [
    firefox
    librime
    ddcutil
  ] ++ (optional config.virtualisation.libvirtd.enable virt-manager);

  # VMWare fix
  boot.kernelParams = mkIf config.virtualisation.vmware.host.enable [
    "ibt=off"
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    liberation_ttf
    monaspace
    sarasa-gothic
    roboto
    (nerdfonts.override { fonts = [
      "CascadiaCode"
      "Monaspace"
    ]; })
  ];

  virtualisation.libvirtd = {
    qemu = {
      swtpm.enable = true;
      ovmf.enable = true;
      ovmf.packages = [ pkgs.OVMFFull.fd ]; # Secure boot
    };
  };
  virtualisation.vmware.host = {
    extraPackages = with pkgs; [ ntfs3g ];
    extraConfig = ''
      # Allow unsupported device's OpenGL and Vulkan acceleration for guest vGPU
      mks.gl.allowUnsupportedDrivers = "TRUE"
      mks.vk.allowUnsupportedDevices = "TRUE"
    '';
  };

  environment.etc = mkIf config.virtualisation.libvirtd.enable {
    "ovmf/edk2-x86_64-secure-code.fd" = {
      source = config.virtualisation.libvirtd.qemu.package + "/share/qemu/edk2-x86_64-secure-code.fd";
    };
    "ovmf/edk2-i386-vars.fd" = {
      source = config.virtualisation.libvirtd.qemu.package + "/share/qemu/edk2-i386-vars.fd";
    };
  };

  fonts.fontDir.enable = true;
  fonts.enableDefaultPackages = true;
  # fonts.optimizeForVeryHighDPI = true;
}
