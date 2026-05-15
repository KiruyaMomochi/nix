{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.kyaru.services.opentelemetry;

  # Common header maps. GreptimeDB needs different headers per signal:
  #   * traces: `x-greptime-pipeline-name: greptime_trace_v1` is REQUIRED.
  #             Optionally `x-greptime-trace-table-name` to override the table name.
  #   * logs:   Optionally `x-greptime-log-table-name`.
  #   * metrics: No special header needed.
  # OTel Collector exporters take a fixed `headers` map per instance, so we
  # spin up one `otlphttp/*` exporter per signal even though they all point at
  # the same endpoint. This is by GreptimeDB's official recommendation —
  # questionable design choice on their side, but the workaround is cheap.
  tracesHeaders = {
    x-greptime-pipeline-name = "greptime_trace_v1";
  } // optionalAttrs (cfg.traces.tableName != null) {
    x-greptime-trace-table-name = cfg.traces.tableName;
  };

  logsHeaders = optionalAttrs (cfg.logs.tableName != null) {
    x-greptime-log-table-name = cfg.logs.tableName;
  };

  metricsHeaders = { };

  mkExporter = headers: {
    endpoint = cfg.endpoint;
    inherit headers;
    auth = mkIf cfg.basicAuth.enable {
      authenticator = "basicauth/monitor";
    };
  };
in
{
  options.kyaru.services.opentelemetry = {
    enable = mkEnableOption "Kyaru's OpenTelemetry setup (GreptimeDB-flavored)";

    logs.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable log collection (journald).";
    };

    logs.tableName = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "host_logs";
      description = ''
        Optional GreptimeDB table name for logs. Sent via
        `x-greptime-log-table-name` header. Defaults to `opentelemetry_logs`.
      '';
    };

    metrics.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable metrics collection (hostmetrics).";
    };

    traces.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable a traces pipeline. The OTLP receiver is exposed locally so that
        applications on this host can push traces via OTLP/gRPC or OTLP/HTTP.
      '';
    };

    traces.tableName = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "host_traces";
      description = ''
        Optional GreptimeDB table name for traces. Sent via
        `x-greptime-trace-table-name` header. Defaults to `opentelemetry_traces`.
      '';
    };

    endpoint = mkOption {
      type = types.str;
      default = "http://127.0.0.1:4000/v1/otlp";
      description = ''
        GreptimeDB OTLP/HTTP base URL. The `otlphttp` exporter will append
        `/v1/traces`, `/v1/logs`, `/v1/metrics` as needed.

        NOTE: GreptimeDB only supports OTLP over HTTP, not gRPC.
      '';
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
          hostmetrics = mkIf cfg.metrics.enable {
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
          journald = mkIf cfg.logs.enable {
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
          # OTLP receiver for application-pushed traces (and other signals if needed).
          otlp = mkIf cfg.traces.enable {
            protocols = {
              grpc.endpoint = "127.0.0.1:4317";
              http.endpoint = "127.0.0.1:4318";
            };
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
          # One exporter per signal — GreptimeDB requires different headers
          # depending on the signal type (pipeline name for traces, optional
          # table name for logs). All point at the same /v1/otlp endpoint.
          "otlphttp/traces" = mkIf cfg.traces.enable (mkExporter tracesHeaders);
          "otlphttp/logs" = mkIf cfg.logs.enable (mkExporter logsHeaders);
          "otlphttp/metrics" = mkIf cfg.metrics.enable (mkExporter metricsHeaders);
        };
        service = {
          extensions = optionals cfg.basicAuth.enable [ "basicauth/monitor" ];
          pipelines = {
            metrics = mkIf cfg.metrics.enable {
              # When traces.enable is on, the otlp receiver is also wired in
              # so remote clients can push metrics over OTLP (gRPC/HTTP), not
              # just hostmetrics from this host.
              receivers = [ "hostmetrics" ] ++ optionals cfg.traces.enable [ "otlp" ];
              processors = [ "batch/monitor" "resourcedetection" "resource" ];
              exporters = [ "otlphttp/metrics" ];
            };
            logs = mkIf cfg.logs.enable {
              receivers = [ "journald" ] ++ optionals cfg.traces.enable [ "otlp" ];
              processors = [ "batch/monitor" "resourcedetection" "resource" "transform" ];
              exporters = [ "otlphttp/logs" ];
            };
            traces = mkIf cfg.traces.enable {
              receivers = [ "otlp" ];
              processors = [ "batch/monitor" "resourcedetection" "resource" ];
              exporters = [ "otlphttp/traces" ];
            };
          };
        };
      };
    };
  };
}
