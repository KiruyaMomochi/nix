{ config, ... }:
{
  programs.kyaru = {
    desktop.enable = true;
    kde.enable = true;
  };

  # Baloo file indexer: disabled on this machine (no GUI use, wastes CPU)
  # HM doesn't have a services.baloo option, so we manage the rc directly
  xdg.configFile."baloofilerc".text = ''
    [Basic Settings]
    Indexing-Enabled=false

    [General]
    exclude folders=${config.home.homeDirectory}/Projects/
  '';
}
