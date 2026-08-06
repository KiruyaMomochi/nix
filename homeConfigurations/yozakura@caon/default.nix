{ lib, ... }:
{
  home.username = "yozakura";
  programs.kyaru.desktop.enable = lib.mkForce false;
  programs.kyaru.kde.enable = lib.mkForce false;
  services.vscode-server.enable = lib.mkForce false;
  services.cdp-proxy.enable = true;
}