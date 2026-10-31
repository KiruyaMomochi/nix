{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.programs.kyaru.desktop;

  # Native Wayland with fcitx5 through text-input. KWin works better with
  # text-input-v1 than v3 (https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland),
  # and this also lets KWin know when a text field is focused, which the
  # on-screen keyboard's touch-to-show relies on.
  chromiumWayland = "--ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=1";
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
    home.packages = with pkgs; [
      font-awesome
      # zotero 10.0.4 fails to build on nixpkgs 2026-10-07 (NixOS/nixpkgs#569006); unused for now
      # zotero
      (microsoft-edge.override {
        commandLineArgs = chromiumWayland;
      })
      keepassxc
      (google-chrome.override {
        commandLineArgs = "--enable-features=WebUIDarkMode --force-dark-mode --disable-features=UserAgentClientHint ${chromiumWayland}";
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
    ];

    # Twilight: the flake re-hosts these artifacts, so old locks keep building.
    programs.zen-browser.enable = true;

    programs.vscode =
      {
        package = pkgs.vscode.fhs;
        enable = true;
      };
  };
}
