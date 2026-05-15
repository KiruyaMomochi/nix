{ config, pkgs, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    optional
    optionalString
    ;
  cfg = config.kyaru.services.greptimedb;

  tomlFormat = pkgs.formats.toml { };

  baseSettings = {
    http = { addr = cfg.http.addr; };
    grpc = { bind_addr = cfg.grpc.addr; };
    mysql = { addr = cfg.mysql.addr; };
    postgres = { addr = cfg.postgres.addr; };
    storage = {
      type = "File";
      data_home = cfg.dataDir;
    };
  };

  settings = lib.recursiveUpdate baseSettings cfg.extraSettings;
  configFile = tomlFormat.generate "greptimedb.toml" settings;

  # Credential name inside systemd LoadCredential for user provider file
  userProviderCredName = "user-provider";
  userProviderCredPath = "/run/credentials/greptimedb.service/${userProviderCredName}";
in
{
  options.kyaru.services.greptimedb = {
    enable = mkEnableOption "GreptimeDB standalone (unified metrics/logs/traces database)";

    package = mkOption {
      type = types.package;
      default = pkgs.kyaru.greptimedb or pkgs.kyaru.greptimedb-bin or pkgs.greptimedb-bin;
      defaultText = lib.literalExpression "pkgs.kyaru.greptimedb";
      description = "GreptimeDB package to use.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/greptimedb";
      description = "Working data directory (data_home).";
    };

    http.addr = mkOption {
      type = types.str;
      default = "127.0.0.1:4000";
      description = "HTTP API listen address (OTLP/HTTP ingest, dashboard, REST).";
    };

    grpc.addr = mkOption {
      type = types.str;
      default = "127.0.0.1:4001";
      description = "gRPC server bind address.";
    };

    mysql.addr = mkOption {
      type = types.str;
      default = "127.0.0.1:4002";
      description = "MySQL wire-protocol listen address.";
    };

    postgres.addr = mkOption {
      type = types.str;
      default = "127.0.0.1:4003";
      description = "Postgres wire-protocol listen address.";
    };

    auth.userProviderFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/greptimedb/users";
      description = ''
        Path to a static user provider file (one `user=password` per line).
        Loaded via systemd `LoadCredential` so the path is not leaked to the Nix store.
        When null, no authentication is configured.
      '';
    };

    extraSettings = mkOption {
      type = tomlFormat.type;
      default = { };
      example = lib.literalExpression ''
        {
          logging.level = "info";
        }
      '';
      description = "Extra TOML settings merged on top of the base config.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the HTTP/gRPC/MySQL/Postgres ports in the firewall.";
    };
  };

  config = mkIf cfg.enable {
    users.users.greptimedb = {
      isSystemUser = true;
      group = "greptimedb";
      home = cfg.dataDir;
      description = "GreptimeDB service user";
    };
    users.groups.greptimedb = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 greptimedb greptimedb - -"
    ];

    systemd.services.greptimedb = {
      description = "GreptimeDB standalone";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = "greptimedb";
        Group = "greptimedb";
        ExecStart =
          let
            authFlag = optionalString (cfg.auth.userProviderFile != null)
              " --user-provider=static_user_provider:file:${userProviderCredPath}";
          in
          "${cfg.package}/bin/greptime standalone start -c ${configFile}${authFlag}";
        Restart = "on-failure";
        RestartSec = "5s";

        # Data dir
        StateDirectory = "greptimedb";
        WorkingDirectory = cfg.dataDir;

        # Secret injection (avoids leaking secret paths into the nix store)
        LoadCredential = optional (cfg.auth.userProviderFile != null)
          "${userProviderCredName}:${toString cfg.auth.userProviderFile}";

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        ReadWritePaths = [ cfg.dataDir ];
        LimitNOFILE = 65536;
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts =
        let
          portOf = a: lib.toInt (lib.last (lib.splitString ":" a));
        in
        [
          (portOf cfg.http.addr)
          (portOf cfg.grpc.addr)
          (portOf cfg.mysql.addr)
          (portOf cfg.postgres.addr)
        ];
    };
  };
}
