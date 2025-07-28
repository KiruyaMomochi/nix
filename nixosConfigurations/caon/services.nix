{ config, lib, pkgs, ... }:
{
  services.openobserve = {
    enable = true;
  };
  services.opentelemetry-collector = {
    enable = true;
    package = pkgs.opentelemetry-collector-contrib;
    settings = {
      receivers = {
        journald = {
          directory = "/var/log/journal";
        };
      };
      exporters = {
        "otlp/openobserve" = {
          endpoint = "localhost:5081";
          headers = {
            organization = "default";
            "stream-name" = "journal-logs";
          };
          tls = {
            insecure = true;
          };
        };
      };
      processors = {
        batch = {
          send_batch_size = 1024;
          timeout = "10s";
        };
      };
      service = {
        pipelines = {
          logs = {
            receivers = [ "journald" ];
            processors = [ "batch" ];
            exporters = [ "otlp/openobserve" ];
          };
        };
      };
    };
  };
}
