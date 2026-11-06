{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.programs.kyaru.desktop;

  # Native Wayland with fcitx5 through text-input. The fcitx wiki suggests v1
  # on KWin, but with an on-screen keyboard launcher as KWin's input method, Chrome
  # 156 on v1 gets no IME at all (Win+Space does nothing); v3 works.
  # text-input also tells KWin when a text field is focused, which the
  # on-screen keyboard's touch-to-show relies on.
  chromiumWayland = "--ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";
in
{
  options.programs.kyaru.desktop = {
    enable = lib.mkEnableOption "Kiruya's desktop packages";
  };

  config = lib.mkIf cfg.enable {
    home.sessionVariables = {
      # NIXOS_OZONE_WL = 1;
    };
    fonts.fontconfig.enable = true;
    # Drops what has no build for this platform (Edge and Spotify on aarch64).
    home.packages = lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) (with pkgs; [
      font-awesome
      # zotero 10.0.4 fails to build on nixpkgs 2026-10-07 (NixOS/nixpkgs#569006); unused for now
      # zotero
      (microsoft-edge.override {
        commandLineArgs = chromiumWayland;
      })
      keepassxc
      (google-chrome.override {
        # Pinned so cookies stay readable outside Plasma (Hyprland would pick basic).
        commandLineArgs = "--enable-features=WebUIDarkMode --force-dark-mode --disable-features=UserAgentClientHint --password-store=kwallet6 ${chromiumWayland}";
      })
      # goldendict-ng
      ddcui
      drawio
      remmina
      spotify
      vlc
      obsidian
      anki
      kuro

      mattermost-desktop
      # https://github.com/NixOS/nixpkgs/pull/157520 make element-desktop-wayland a shell wrapper
      # which means it does not create desktop items, so we don't use that.
      # And that what does is simply adding the environment variable
      element-desktop

      # for clipboard
      wl-clipboard
      xclip
      xsel
    ]);

    # Remmina rewrites this on every start if it is missing (Hidden=false, i.e. tray applet
    # autostarts). Keeping our own copy stops that; it only writes the file when absent.
    xdg.configFile."autostart/remmina-applet.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Remmina Applet
      Exec=remmina -i
      Hidden=true
    '';

    # Twilight: the flake re-hosts these artifacts, so old locks keep building.
    programs.zen-browser.enable = true;

    programs.vscode =
      {
        # Same as Chrome: Electron only picks KWallet on its own when XDG_CURRENT_DESKTOP says KDE.
        package = (pkgs.vscode.override { commandLineArgs = "--password-store=kwallet6"; }).fhs;
        enable = true;
      };
  };
}
