{
  config,
  pkgs,
  lib,
  ...
}:
{
  # https://github.com/zhaofengli/attic/blob/main/integration-tests/basic/default.nix

  services.atticd = {
    settings = {
      storage.type = "local";
      storage.path = "/mnt/data/nix";
      database.url = "postgresql:///atticd?host=/run/postgresql";
    };
  };

  users.groups.atticd = {};
  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    ensureDatabases = [ "atticd" ];
    ensureUsers = [
      {
        name = "atticd";
        ensureDBOwnership = true;
      }
    ];
  };
}
