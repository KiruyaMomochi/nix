{ config, lib, pkgs, ... }:
{
  services.dragonflydb = {
    enable = true;
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    enableTCPIP = true;
    extensions = ps: with ps; [ pgvector pg_search pgroonga ];
    ensureDatabases = [ "priconne" ];
    ensureUsers = [
      { name = "kyaru"; }
    ];
  };
}

