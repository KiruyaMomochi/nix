{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.kyaru.services.hardware-poller;

  python = pkgs.python3.withPackages (ps: with ps; [
    requests
    opentelemetry-api
    opentelemetry-sdk
    opentelemetry-exporter-otlp-proto-http
  ]);

  # Whole source tree goes into the store so poller.py can import its
  # sibling source_*.py modules at runtime.
  pollerSrc = pkgs.runCommand "hardware-poller-src" { } ''
    mkdir -p $out
    cp ${./hardware-poller}/*.py $out/
  '';

  # --- Redfish source ---
  redfishCfg = cfg.redfish;
  redfishConfigFile = pkgs.writeText "hardware-poller-redfish-config.json" (builtins.toJSON {
    source_type = "redfish";
    service_name = "hardware-poller-redfish";
    description = "Redfish BMC at ${redfishCfg.bmcUrl}";
    bmc_url = redfishCfg.bmcUrl;
    username = redfishCfg.username;
    interface = redfishCfg.interface;
    interval = redfishCfg.interval;
    chassis_id = redfishCfg.chassisId;
    otlp_endpoint = redfishCfg.otlpEndpoint;
    exportInterval = redfishCfg.exportInterval;
    host_name = config.networking.hostName;
    credentials = [ "bmc_password" ];
  });

  redfishService = {
    description = "Hardware poller: Redfish BMC sensors → OTLP";
    after = [ "network-online.target" "opentelemetry-collector.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${python}/bin/python ${pollerSrc}/poller.py --config ${redfishConfigFile} --source redfish";
      Restart = "on-failure";
      RestartSec = 10;

      LoadCredential = [ "bmc_password:${redfishCfg.credentialFile}" ];
      StateDirectory = "hardware-poller";

      DynamicUser = true;
      AmbientCapabilities = mkIf (redfishCfg.interface != null) [ "CAP_NET_RAW" ];
      CapabilityBoundingSet = mkIf (redfishCfg.interface != null) [ "CAP_NET_RAW" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  # --- SMART source ---
  smartCfg = cfg.smart;
  smartConfigFile = pkgs.writeText "hardware-poller-smart-config.json" (builtins.toJSON {
    source_type = "smart";
    service_name = "hardware-poller-smart";
    description = "SMART disk health monitoring";
    devices = smartCfg.devices;
    interval = smartCfg.interval;
    otlp_endpoint = smartCfg.otlpEndpoint;
    exportInterval = smartCfg.exportInterval;
    host_name = config.networking.hostName;
    credentials = [ ];
  });

  smartService = {
    description = "Hardware poller: SMART disk health → OTLP";
    after = [ "opentelemetry-collector.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${python}/bin/python ${pollerSrc}/poller.py --config ${smartConfigFile} --source smart";
      # smartctl must be on PATH for the smart source
      Environment = [ "PATH=${pkgs.smartmontools}/bin" ];
      Restart = "on-failure";
      RestartSec = 10;

      StateDirectory = "hardware-poller";

      # SMART needs /dev/nvmeX (root:root 600) for controller info
      # AND /dev/nvmeXnY (root:disk 660) for block device reads.
      # DynamicUser + disk group only covers the latter — char device still blocked.
      # Run as root; all other hardening (ProtectSystem/Home, PrivateTmp) still active.
      User = "root";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
in
{
  options.kyaru.services.hardware-poller = {
    redfish = {
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

      exportInterval = mkOption {
        type = types.int;
        default = 60;
        description = ''
          How often (in seconds) to export metrics to OTLP.
          Independent from polling interval — can push more frequently than poll.
          Default: 60s.
        '';
      };
    };

    smart = {
      enable = mkEnableOption "SMART disk health poller (OTLP metrics)";

      devices = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "/dev/nvme0n1" "/dev/nvme1n1" "/dev/sda" ];
        description = ''
          List of block devices to monitor.
          NVMe devices: /dev/nvme0n1, /dev/nvme1n1, etc.
          SATA/SAS devices: /dev/sda, /dev/sdb, etc.
        '';
      };

      interval = mkOption {
        type = types.int;
        default = 300;
        description = "Polling interval in seconds (default 5 minutes).";
      };

      otlpEndpoint = mkOption {
        type = types.str;
        default = "http://127.0.0.1:4318";
        description = ''
          OTLP/HTTP endpoint to push metrics to.
          Default is the local OpenTelemetry Collector.
        '';
      };

      exportInterval = mkOption {
        type = types.int;
        default = 60;
        description = ''
          How often (in seconds) to export metrics to OTLP.
          Independent from polling interval — can push more frequently than poll.
          Default: 60s.
        '';
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.redfish.enable {
      systemd.services.hardware-poller-redfish = redfishService;
    })

    (mkIf cfg.smart.enable {
      systemd.services.hardware-poller-smart = smartService;
    })
  ];
}
