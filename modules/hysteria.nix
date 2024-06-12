{ config, pkgs, lib, utils, ... }:
let
  cfg = config.services.hysteria;
  # It's yaml but we use json for jq
  settingsFormat = pkgs.formats.json { };
in
with lib;
{
  imports = [ ];
  options.services.hysteria = {
    enable = mkEnableOption "Hysteria 2, the powerful, lightning fast and censorship resistant proxy";
    package = mkPackageOption pkgs "hysteria" { };

    logLevel = mkOption {
      type = types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = ''
        Log level.
      '';
    };

    useACMEHost = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Use certificate from the specific ACME host.";
    };

    port = mkOption {
      type = types.nullOr types.port;
      default = 443;
      description = ''
        Which port this service should listen on.
      '';
    };

    settings = mkOption {
      type = types.submodule {
        # Declare that the settings option supports arbitrary format values, yaml here
        freeformType = settingsFormat.type;
        # Declare an option for the port such that the type is checked and this option
        # is shown in the manual.
        options.listen = mkOption {
          type = types.str;
          description = ''
            The server's listen address.
          '';
        };
      };
      default = { };
      # Add upstream documentation to the settings description
      description = ''
        Configuration for Hysteria 2, see
        <link xlink:href="https://v2.hysteria.network/docs/advanced/Full-Server-Config"/>
        for supported values.

        Options containing secret data should be set to an attribute set
        containing the attribute `_secret` - a string pointing to a file
        containing the value the option should be set to.
      '';
    };
  };

  config =
    let sslCertDir = config.security.acme.certs.${cfg.useACMEHost}.directory; in
    mkIf cfg.enable {
      systemd.services.hysteria = {
        description = "Hysteria Server Service";

        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        restartIfChanged = true;

        preStart = ''
          umask 0077
          mkdir -p /etc/hysteria
          ${utils.genJqSecretsReplacementSnippet cfg.settings "/etc/hysteria/config.json"}
        '';

        serviceConfig = {
          Type = "simple";
          Environment = "HYSTERIA_LOG_LEVEL=${cfg.logLevel}";
          ExecStart = "${cfg.package}/bin/hysteria server --config /etc/hysteria/config.json";
          Restart = "on-failure";
          RestartSec = "10s";
          CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" "CAP_NET_RAW" ];
          AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" "CAP_NET_RAW" ];
          NoNewPrivileges = true;
        };
      };
      services.hysteria.settings = mkMerge [
        (mkIf (cfg.useACMEHost != null) {
          tls = {
            cert = "${sslCertDir}/cert.pem";
            key = "${sslCertDir}/key.pem";
          };
        }
        )
        (mkIf (cfg.port != null) {
          listen = mkDefault ":${builtins.toString cfg.port}";
        })
      ];
    };
}
