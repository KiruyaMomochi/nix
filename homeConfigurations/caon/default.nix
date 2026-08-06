{ config, ... }:
{
  programs.kyaru = {
    desktop.enable = true;
    kde.enable = true;
  };

  # CDP fallback proxy + headless browser now live in yozakura's profile (uid 1002).
  # Both bind 127.0.0.1, which has no uid boundary, so a single instance serves both users
  # and avoids two Chrome processes fighting over port 9222.
  services.cdp-proxy.enable = false;

  # Baloo file indexer: disabled on this machine (no GUI use, wastes CPU)
  # HM doesn't have a services.baloo option, so we manage the rc directly
  xdg.configFile."baloofilerc".text = ''
    [Basic Settings]
    Indexing-Enabled=false

    [General]
    exclude folders=${config.home.homeDirectory}/Projects/
  '';
}
