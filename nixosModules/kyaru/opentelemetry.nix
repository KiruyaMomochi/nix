{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.kyaru.services.opentelemetry;
in
{
  options.kyaru.services.opentelemetry = {
    enable = mkEnableOption "Kyaru's OpenTelemetry setup";

    logs = mkOption {
      type = types.bool;
      default = false;
      description = "Enable log collection (journald)";
    };

    metrics = mkOption {
      type = types.bool;
      default = true;
      description = "Enable metrics collection (hostmetrics)";
    };

    endpoint = mkOption {
      type = types.str;
      default = "http://127.0.0.1:4317";
      description = "OTLP gRPC endpoint for monitoring";
    };

    basicAuth = {
      enable = mkEnableOption "Basic Auth using LoadCredential";
      credentialName = mkOption {
        type = types.str;
        default = "authorization";
        description = "Name of the credential in LoadCredential to use for client_auth";
      };
    };

    journaldUnits = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of systemd units to collect logs from. If empty, all units are collected.";
    };

    loadCredential = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "authorization:/path/to/secret" ];
      description = ''
        Credentials to load for the service.
        Passed to systemd LoadCredential.
        
        The 'authorization' credential is expected by the default config if basicAuth is enabled.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.opentelemetry-collector = {
      serviceConfig.LoadCredential = cfg.loadCredential;
      # Allow reading /home for filesystem metrics
      serviceConfig.ProtectHome = "read-only";
    };

    services.opentelemetry-collector = {
      enable = true;
      package = pkgs.opentelemetry-collector-contrib;
      settings = {
        extensions = mkIf cfg.basicAuth.enable {
          "basicauth/monitor".client_auth = "\${file:/run/credentials/opentelemetry-collector.service/${cfg.basicAuth.credentialName}}";
        };
        receivers = {
          hostmetrics = mkIf cfg.metrics {
            collection_interval = "60s";
            scrapers = {
              cpu = { };
              load = { };
              memory = { };
              disk = { };
              filesystem = { };
              network = { };
            };
          };
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/journaldreceiver/README.md
          journald = mkIf cfg.logs {
            units = mkIf (cfg.journaldUnits != [ ]) cfg.journaldUnits;
            # A field that contains non-printable or non-UTF8 is serialized as a number array instead. This is necessary to handle binary data in a safe way without losing data, since JSON cannot embed binary data natively. Each byte of the binary field will be mapped to its numeric value in the range 0…255.
            convert_message_bytes = true;
            # https://www.dash0.com/guides/opentelemetry-journald-receiver
            operators = [
              # 1. Move the whole body (map) to attributes["body"]
              { type = "move"; from = "body"; to = "attributes[\"body\"]"; }
              # 2. Flatten attributes["body"] to top-level attributes
              # This preserves all journald fields as attributes
              { type = "flatten"; field = "attributes[\"body\"]"; }
              # 3. Parse Severity from the preserved PRIORITY in attributes
              {
                type = "severity_parser";
                parse_from = "attributes.PRIORITY";
                mapping = {
                  "fatal" = [ "0" "1" "2" ];
                  "error" = "3";
                  "warn" = "4";
                  "info" = [ "5" "6" ];
                  "debug" = "7";
                };
              }
              # 4. Set the Scope Name from the systemd unit name
              {
                type = "scope_name_parser";
                parse_from = "attributes._SYSTEMD_UNIT";
              }
              # 5. Move the actual log message back to the Body
              { type = "move"; from = "attributes.MESSAGE"; to = "body"; }
            ];
          };
        };
        processors = {
          "batch/monitor" = {
            send_batch_size = 8192;
            timeout = "10s";
          };
          resourcedetection = {
            detectors = [ "system" ];
            system = {
              hostname_sources = [ "os" ];
            };
          };
          # Drop start_time/boot_time to prevent metric series reset on restart
          resource = {
            attributes = [
              { key = "host.boot_time"; action = "delete"; }
              { key = "process.start_time"; action = "delete"; }
            ];
          };
          transform = {
            log_statements = [
              {
                context = "log";
                statements = [
                  # Try to parse body as JSON if it looks like JSON
                  # We merge the parsed json into attributes
                  "merge_maps(attributes, ParseJSON(body), \"insert\") where IsMatch(body, \"^\\\\{.*\\\\}$\")"
                ];
              }
            ];
          };
        };
        exporters = {
          "otlp/monitor" = {
            endpoint = cfg.endpoint;
            auth = mkIf cfg.basicAuth.enable {
              authenticator = "basicauth/monitor";
            };
            headers = {
              organization = "default";
              stream-name = "default";
            };
          };
        };
        service = {
          extensions = optionals cfg.basicAuth.enable [ "basicauth/monitor" ];
          pipelines = {
            metrics = mkIf cfg.metrics {
              receivers = [ "hostmetrics" ];
              processors = [ "batch/monitor" "resourcedetection" "resource" ];
              exporters = [ "otlp/monitor" ];
            };
            logs = mkIf cfg.logs {
              receivers = [ "journald" ];
              processors = [ "batch/monitor" "resourcedetection" "resource" "transform" ];
              exporters = [ "otlp/monitor" ];
            };
          };
        };
      };
    };
  };
}
