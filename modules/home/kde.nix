{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    ark
    kcolorchooser
    krita
    kate
    qalculate-qt # latte-dock
    krdc
    libsForQt5.dolphin
  ];
}
