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
    fonts.fontconfig.enable = true;
    home.packages = with pkgs; [
      font-awesome
      zotero
      microsoft-edge
      cascadia-code
      slack
      libreoffice-qt
      hunspell
      hunspellDicts.en-us-large
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

      # for clipboard
      wl-clipboard
      wl-clipboard-x11
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
