{ config
, lib
, pkgs
, ...
}:
with lib;
let
  cfg = config.kyaru.desktop;
in
{
  options.kyaru.desktop = {
    enable = mkEnableOption "Kiruya's desktop environment";
    environment = mkOption {
      type = with types; nullOr (enum [ "gnome" "kde" ]);
      default = "kde";
      description = "Environment to use";
    };
  };

  config =
    mkIf cfg.enable (mkMerge [
      {
        boot.supportedFilesystems = [ "ntfs" ];

        # Enable the X11 windowing system.
        services.xserver.enable = true;

        # Fix GTK themes are not applied in Wayland applications
        programs.dconf.enable = true;
        # programs.sway.enable = true;
        # programs.hyprland.enable = true;

        # screenshot
        xdg.portal.wlr.enable = true;

        console = {
          # font = "Lat2-Terminus16";
          # keyMap = "us";
          useXkbConfig = true; # use xkbOptions in tty.
        };
        # Configure keymap in X11
        # services.xserver.layout = "us";
        # services.xserver.xkbOptions = {
        #   "eurosign:e";
        #   "caps:escape" # map caps to escape.
        # };

        # Enable sound with pipewire.
        # Remove sound.enable or turn it off if you had it set previously, it seems to cause conflicts with pipewire
        # sound.enable = false;
        # rtkit is optional but recommended
        security.rtkit.enable = true;
        services.pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
        };

        # Enable CUPS to print documents.
        # services.printing.enable = true;

        # Enable touchpad support (enabled default in most desktopManager).
        services.libinput.enable = true;
        services.openssh.settings.X11Forwarding = true;
        services.xrdp.openFirewall = true;

        programs.firejail.enable = true;
        programs.firejail.wrappedBinaries = { };

        environment.systemPackages = with pkgs; [
          firefox
          librime
          ddcutil
        ] ++ (optional config.virtualisation.libvirtd.enable virt-manager);

        networking.networkmanager.enable = mkDefault true; # Easiest to use and most distros use this by default.
        networking.networkmanager.dns = "systemd-resolved";
        services.resolved.enable = true;

        # VMWare fix
        boot.kernelParams = mkIf config.virtualisation.vmware.host.enable [
          "ibt=off"
        ];

        # Select internationalisation properties.
        i18n.supportedLocales = [ "all" ];
        i18n.inputMethod = {
          type = "fcitx5";
          enable = true;
          fcitx5.waylandFrontend = true;

          fcitx5.addons = with pkgs; [
            fcitx5-chewing
            fcitx5-rime
            fcitx5-mozc
          ];
        };
        fonts.packages = with pkgs; [
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-cjk-serif
          noto-fonts-emoji
          liberation_ttf
          monaspace
          sarasa-gothic
          roboto
          nerd-fonts.monaspace
        ];
        fonts.fontDir.enable = true;
        fonts.enableDefaultPackages = true;

        virtualisation.libvirtd = {
          qemu = {
            swtpm.enable = true;
            ovmf.enable = true;
            ovmf.packages = [ pkgs.kyaru.ovmf.fd ]; # Secure boot
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

        programs.adb.enable = true;

        # DDC
        hardware.i2c.enable = true;
        # boot.extraModulePackages = [ config.boot.kernelPackages.ddcci-driver ];
        # boot.kernelModules = [ "ddcci_backlight" ];

        programs.nix-ld.enable = true;

        programs.localsend.enable = true;
      }
      (mkIf (cfg.environment == "gnome") {
        # GNOME
        services.xserver.displayManager.gdm.enable = true;
        services.xserver.desktopManager.gnome.enable = true;

        # programs.sway.enable = true;
        services.xrdp.defaultWindowManager = mkDefault "gnome-session";
      })
      (mkIf (cfg.environment == "kde") {
        # KDE
        services.desktopManager.plasma6.enable = lib.mkDefault true;
        services.displayManager.sddm.enable =
          true;
        programs.partition-manager.enable = true;

        services.xrdp.defaultWindowManager = mkDefault
          "startplasma-x11";
      })
    ]);
}
