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
    home.packages = with pkgs; [
      zotero
      microsoft-edge
      cascadia-code
      slack
      libreoffice-qt
      hunspell
      filelight
      keepassxc
      (google-chrome.override {
        commandLineArgs = "--enable-features=WebUIDarkMode --force-dark-mode --disable-features=UserAgentClientHint";
      })
      kyaru.goldendict-ng
      ddcui
      drawio
      gitkraken
      mattermost-desktop
      remmina
      spotify
      vlc
      krita
      obsidian
      anki
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
