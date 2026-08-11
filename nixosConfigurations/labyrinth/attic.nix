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
      # URL-encode the socket path (%2F = /). The `@/` syntax fails sqlx parse.
      database.url = "postgresql://atticd@%2Frun%2Fpostgresql/atticd";
    };
  };

  # atticd module sets DynamicUser=yes by default, which allocates a transient
  # high UID that PostgreSQL peer auth cannot resolve. We define a static user
  # below, so turn off DynamicUser to use it.
  systemd.services.atticd.serviceConfig.DynamicUser = lib.mkForce false;

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
