{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.programs.kyaru.desktop;
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
      zotero
      microsoft-edge
      filelight
      keepassxc
      (google-chrome.override {
        commandLineArgs = "--enable-features=WebUIDarkMode --force-dark-mode --disable-features=UserAgentClientHint";
      })
      kyaru.goldendict-ng
      ddcui
      drawio
      remmina
      spotify
      vlc
      obsidian
      anki

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

    programs.vscode =
      let
        package = pkgs.vscode.fhs;
      in
      {
        inherit package;
        enable = true;
      };
  };
}
