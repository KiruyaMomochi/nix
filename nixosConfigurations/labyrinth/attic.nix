{ config, pkgs, lib, ... }:
{
  # https://github.com/zhaofengli/attic/blob/main/integration-tests/basic/default.nix
  
  services.atticd = {
    enable = true;
    settings = {
      storage.type = "local";
      storage.path = "/mnt/data/nix";
      database.url = "postgresql:///atticd?host=/run/postgresql";
    };
  };

  # Ensure storage directory exists with correct permissions
  systemd.tmpfiles.rules = [
    "d /mnt/data/nix 0750 atticd atticd -"
  ];

  services.postgresql = {
    enable = true;
    ensureDatabases = [ "atticd" ];
    ensureUsers = [
      {
        name = "atticd";
        ensureDBOwnership = true;
      }
    ];
  };
}
