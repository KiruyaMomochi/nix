{ config, pkgs, ... }:
{
  nixpkgs.overlays = [
    (import ../../overlays/goldendict.nix)
  ];
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
    goldendict
    ddcui
    drawio
    gitkraken
    mattermost-desktop
    remmina
    spotify
    vlc
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
