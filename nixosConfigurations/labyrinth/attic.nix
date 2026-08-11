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
      # The user must be spelled out. atticd runs with DynamicUser=yes, whose
      # unit environment has no USER/LOGNAME, so sqlx cannot infer one and
      # falls back to the literal "anonymous" — pg_hba's `local all all trust`
      # then rejects it because no such role exists.
      database.url = "postgresql://atticd@/atticd?host=/run/postgresql";
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
