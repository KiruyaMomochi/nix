{ config, lib, pkgs, ... }:
{
  services.openobserve = {
    enable = true;
    data_retention_days = 14;
  };

  services.dragonflydb = {
    enable = true;
  };

  services.garage = {
    enable = true;
    package = pkgs.garage_2;
    settings = {
      replication_factor = 1;
      consistency_mode = "consistent";
      rpc_bind_addr = "127.0.0.1:3901";
      s3_api = {
        api_bind_addr = "127.0.0.1:3900";
        s3_region = "garage";
      };
      s3_web.bind_addr = "100.82.238.137:3902";
      admin.api_bind_addr = "127.0.0.1:3903";
    };
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    enableTCPIP = true; 
    extensions = ps: with ps; [ pgvector ];
    ensureDatabases = [ "lobechat" ];
    ensureUsers = [
      {
        name = "lobechat";
        ensureDBOwnership = true;
        # \password lobechat
        # CREATE EXTENSION vector
      }
    ];
  };
}

