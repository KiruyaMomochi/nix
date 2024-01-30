{ config, pkgs, lib, ... }:
{
  services.postgresql = {
    enable = true;
    ensureDatabases = [
      "dendrite"
    ];
    ensureUsers = [
      {
        name = "dendrite";
        ensureDBOwnership = true;
      }
    ];
  };

  services.dendrite = {
    settings = {
      global = {
        database = {
          connection_string = "postgresql://dendrite@/dendrite";
        };
      };
      sync_api = {
        search = {
          enabled = true;
          language = "cjk";
        };
      };
    };
  };

  systemd.services.dendrite.serviceConfig.User = "dendrite";
}
