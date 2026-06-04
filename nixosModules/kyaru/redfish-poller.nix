{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.kyaru.services.redfish-poller;

  python = pkgs.python3.withPackages (ps: with ps; [
    requests
    opentelemetry-api
    opentelemetry-sdk
    opentelemetry-exporter-otlp-proto-http
  ]);

  configFile = pkgs.writeText "redfish-poller-config.json" (builtins.toJSON {
    bmc_url = cfg.bmcUrl;
    username = cfg.username;
    interface = cfg.interface;
    interval = cfg.interval;
    chassis_id = cfg.chassisId;
    otlp_endpoint = cfg.otlpEndpoint;
    host_name = config.networking.hostName;
  });
in
{
  options.kyaru.services.redfish-poller = {
    enable = mkEnableOption "Redfish BMC sensor poller (OTLP metrics)";

    bmcUrl = mkOption {
      type = types.str;
      default = "https://169.254.3.254";
      description = "BMC Redfish base URL.";
    };

    username = mkOption {
      type = types.str;
      default = "monitor";
      description = "Redfish username (read-only account recommended).";
    };

    credentialFile = mkOption {
      type = types.path;
      description = ''
        Path to a file containing the BMC password (plain text, single line).
        Typically a sops-nix managed secret path.
        Exposed to the service via systemd LoadCredential.
      '';
    };

    interface = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "usb0";
      description = ''
        Network interface to bind for BMC communication.
        Set to null to use default routing.
      '';
    };

    interval = mkOption {
      type = types.int;
      default = 60;
      description = "Polling interval in seconds.";
    };

    chassisId = mkOption {
      type = types.str;
      default = "1";
      description = "Redfish Chassis ID to poll sensors from.";
    };

    otlpEndpoint = mkOption {
      type = types.str;
      default = "http://127.0.0.1:4318";
      description = ''
        OTLP/HTTP endpoint to push metrics to.
        Default is the local OpenTelemetry Collector.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.redfish-poller = {
      description = "Redfish BMC sensor poller → OTLP metrics";
      after = [ "network.target" "opentelemetry-collector.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${python}/bin/python ${./redfish-poller/poll.py} --config ${configFile}";
        Restart = "on-failure";
        RestartSec = 10;

        # Credential: password file exposed at /run/credentials/redfish-poller.service/bmc_password
        LoadCredential = [ "bmc_password:${cfg.credentialFile}" ];

        # State: persist last seen event ID across restarts
        StateDirectory = "redfish-poller";

        # Security hardening
        DynamicUser = true;
        # CAP_NET_RAW needed for SO_BINDTODEVICE (interface binding)
        AmbientCapabilities = mkIf (cfg.interface != null) [ "CAP_NET_RAW" ];
        CapabilityBoundingSet = mkIf (cfg.interface != null) [ "CAP_NET_RAW" ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };
  };
}
