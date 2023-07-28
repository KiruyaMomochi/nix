{ config, pkgs, ... }:
{
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
    goldendict-ng
    ddcui
    drawio
    gitkraken
    mattermost-desktop
    remmina
    spotify
    vlc
    krita
  ];

  programs.vscode =
    let
      package = pkgs.vscode.fhs;
    in
    {
      inherit package;
      enable = true;
    };
}
