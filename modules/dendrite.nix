{ config, pkgs, lib, ... }:
with lib;
{
  options = {
    kyaru.services.dendrite = {
      createDatabase = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = lib.mdDoc ''
          Whether to enable and configure `services.postgres` to ensure that the database user `dendrite`
          and the database `dendrite` exist.
        '';
      };
      jetstream = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = lib.mdDoc ''
          Whether to enable the standalone NATS server.
        '';
      };
    };
  };

  config =
    let
      cfg = config.services.dendrite;
      kyaruCfg = config.kyaru.services.dendrite;
    in
    mkIf cfg.enable (mkMerge [
      (mkIf kyaruCfg.createDatabase {
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
      })
      (mkIf kyaruCfg.jetstream {
        services.nats = {
          enable = true;
          jetstream = true;
        };
        services.dendrite.settings.global.jetstream = {
          addresses = [ "localhost:${builtins.toString config.services.nats.port}" ];
          topic_prefix = "Dendrite";
        };
      })
    ]);
}
