# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:
assert (lib.strings.removeSuffix "\n" (builtins.readFile ./secret.nix)) != "";
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # Don't know how to use agenix yet...
      # https://github.com/divnix/digga/discussions/319
      # Instead, https://stackoverflow.com/questions/4348590/how-can-i-make-git-ignore-future-revisions-to-a-file
      ./secret.nix
    ];

  nixpkgs.overlays = [
    (final: prev: {
        libsForQt5 = prev.libsForQt5.overrideScope' (qt5final: qt5prev: {
          kdeconnect-kde = qt5prev.kdeconnect-kde.overrideAttrs (oldAttrs: {
            buildInputs = oldAttrs.buildInputs ++ [qt5final.kirigami-addons];
          });
        });
      }
    )
  ];

  fileSystems = {
    # "/".options = [ ];
    # "/home".options = [ ];
    "/nix".options = [ "noatime" ];
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.linux_6_1
  # .override {
    # argsOverride = rec {
      # src = pkgs.fetchurl {
            # url = "mirror://kernel/linux/kernel/v6.x/linux-${version}.tar.xz";
            # sha256 = "sha256-dIYvqKtA7a6FuzOFwLcf4QMoi85RhSbWMZeACzy97LE=";
      # };
      # version = "6.2";
      # modDirVersion = "6.2.0";
    # }; 
  # }
  );
  boot.kernelModules = [
    "nft_tproxy"
    "nft_socket"
  ];
  boot.supportedFilesystems = [ "ntfs" ];


  hardware.opengl = {
    extraPackages = with pkgs; [ ];
    driSupport = true;
    driSupport32Bit = true;
  };
  hardware.cpu.intel.updateMicrocode = true;

  networking.hostName = "caon"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.
  networking.networkmanager.dns = "systemd-resolved";
  services.resolved.enable = true;
  # networking.hosts = {
  #   "151.101.66.217" = ["cache.nixos.org" "channels.nixos.org"];
  # };

  # Set your time zone.
  time.timeZone = "Asia/Taipei";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://127.0.0.1:3090";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.supportedLocales = [ "all" ];
  i18n.inputMethod = {
    enabled = "fcitx5";

    fcitx5.addons = with pkgs; [
      fcitx5-chewing fcitx5-rime
    ];
  };
  console = {
    font = "Lat2-Terminus16";
    # keyMap = "us";
    useXkbConfig = true; # use xkbOptions in tty.
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # KDE
  services.xserver.desktopManager.plasma5.enable = true;
  services.xserver.displayManager.sddm.enable = true;
  programs.partition-manager.enable = true;
  # Fix GTK themes are not applied in Wayland applications
  programs.dconf.enable = true;

  # RDP
  services.xrdp.enable = true;
  services.xrdp.defaultWindowManager = "startplasma-x11";
  services.xrdp.openFirewall = true;

  # programs.sway.enable = true;
  xdg.portal.wlr.enable = true;

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" "repl-flake" ];

  # Configure keymap in X11
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = {
  #   "eurosign:e";
  #   "caps:escape" # map caps to escape.
  # };

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound with pipewire.
  # Remove sound.enable or turn it off if you had it set previously, it seems to cause conflicts with pipewire
  # sound.enable = false;
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;
  # rtkit is optional but recommended
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  hardware.bluetooth.enable = true;

  programs.adb.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kyaru = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "adbusers" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      firefox
      tdesktop
      nil
    ];
    shell = pkgs.fish;
    description = "百地 希留耶";
  };

  services.tailscale = {
    enable = true;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    helix # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget curl
    librime
    nftables
    virt-manager
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    sarasa-gothic
    roboto
    (nerdfonts.override { fonts = [ "CascadiaCode" ]; })
  ];
  fonts.fontDir.enable = true;
  fonts.enableDefaultPackages = true;
  # fonts.optimizeForVeryHighDPI = true;

  programs.kdeconnect.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.X11Forwarding = true;
  services.openssh.ports = [ 22 ];
  system.autoUpgrade.enable = true;

  networking.nftables.enable = true;
  networking.networkmanager.firewallBackend = "nftables";
  networking.firewall.allowedTCPPorts = [ (config.services.zerotierone.port) 443 3389 8964 3090 ];
  networking.firewall.allowedUDPPorts = [ (config.services.zerotierone.port) 3389 3478 8964 3090 41641 ];
  networking.firewall.trustedInterfaces = [ "virbr0" ];
  networking.firewall.enable = true;
  networking.nat = {
    enable = true;
    internalInterfaces = [ "tailscale0" ];
  };
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };

  programs.fish.enable = true;
  nixpkgs.config.allowUnfree = true;

  programs.firejail.enable = true;
  programs.firejail.wrappedBinaries = {};

  # VMWare
  # virtualisation.vmware.host.enable = true;
  # VMWare Fix
  # boot.kernelParams = [
    # "ibt=off"
  # ];

  # KVM
  virtualisation.libvirtd = {
    enable = true;
  };

  # Nspawn
  systemd.services."container-getty@" = {
    environment = {
      TERM = "xterm-256color";
    };
  };

  nix.settings.trusted-users = [ "kyaru" ];

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # This option is not compactiable with flakes
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It’s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
