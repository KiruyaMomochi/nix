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
    bottles
    remmina
    spotify
  ];

  programs.vscode =
    let
      # generated = import ./vscode-extensions.nix;
      # extensions = pkgs.vscode-utils.extensionsFromVscodeMarketplace generated.extensions;
      # package = pkgs.vscode-with-extensions.override {
      #  vscodeExtensions = extensions;
      # };
      package = pkgs.vscode.fhs;
    in
    {
      inherit package;
      enable = true;
    };
}
