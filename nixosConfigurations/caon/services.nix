{ config, lib, pkgs, ... }:
{
  services.openobserve = {
    enable = true;
    data_retention_days = 14;
  };
}
