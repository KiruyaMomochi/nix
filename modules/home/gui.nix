{ config, pkgs, ... }:
{
  nixpkgs.overlays = [
    (import ../../overlays/goldendict.nix)
  ];
  home.packages = with pkgs; [
    zotero
    micotosft-edge
    cascadia-code
    slack
    libreoffice-qt
    hunspell
    filelight
    keepassxc
    (google-chrome.override {
      commandLineArgs = "--enable-features=WebUIDarkMode --force-dark-mode";
    })
    goldendict
    ddcui
    drawui
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
