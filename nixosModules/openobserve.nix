{ options
, config
, lib
, pkgs
, ...
}:
with lib;
let
  cfg = config.services.openobserve;
  stateDir = "openobserve";
in
{
  options.services.openobserve = {
    enable = mkEnableOption "the OpenObserve server";
    package = mkOption {
      type = types.package;
      default = pkgs.openobserve;
      description = "The OpenObserve package to use.";
    };
    # stateDir = lib.mkOption {
    #   type = lib.types.path;
    #   default = "/var/lib/openobserve";
    #   description = "OpenObserve data directory.";
    # };
    # # systemd.tmpfiles.rules = [ "d '${cfg.stateDir}' - ${cfg.user} ${cfg.group} - -" ];
    port = lib.mkOption {
      type = types.port;
      default = 5080;
      description = "openobserve server listen HTTP port.";
    };
    host = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "openobserve server listen HTTP ip address.";
    };
    ipv6 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "enable ipv6 support for HTTP";
    };
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        ZO_ROOT_USER_EMAIL = "root@example.com";
        ZO_ROOT_USER_PASSWORD = "Complexpass#123";
        ZO_DATA_DIR = "/data/openobserve";
      };
      description = ''
        Environment variables to set for the service. Secrets should be
        specified using {option}`environmentFiles`.
        Refer to <https://openobserve.ai/docs/environment-variables/>
        for available options.
      '';
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = "/run/secrets/openobserve.env";
      description = ''
        Files to load environment variables from. Loaded variables override
        values set in {option}`environment`.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.openobserve = {
      description = "The OpenObserve server";
      after = [ "syslog.target" "network-online.target" "remote-fs.target" "nss-lookup.target" ];
      wants = [ "network-online.target" ];
      environment = mkMerge [
        {
          ZO_HTTP_PORT = builtins.toString cfg.port;
          ZO_HTTP_IPV6_ENABLED = if cfg.ipv6 then "true" else "false";
          ZO_DATA_DIR = "/var/lib/${stateDir}";
        }
        (lib.mkIf (cfg.host != null) {
          ZO_HTTP_ADDR = cfg.host;
        })
        cfg.environment
      ];
      serviceConfig = {
        Type = "simple";
        LimitNOFILE = 65535;
        ExecStart = "${cfg.package}/bin/openobserve";
        ExecStop = "${pkgs.coreutils}/bin/kill -s QUIT $MAINPID";
        Restart = "on-failure";
        EnvironmentFile = cfg.environmentFiles;

        DynamicUser = true;
        NoNewPrivileges = true;

        ProtectProc = "invisible";
        ProtectSystem = "strict";
        ProtectHome = "tmpfs";

        PrivateTmp = true;
        PrivateDevices = true;
        PrivateIPC = true;

        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;

        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;

        StateDirectory = stateDir;
        WorkingDirectory = "%S/${stateDir}";

        # ReadWritePaths = [
        #   cfg.stateDir
        # ];
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
