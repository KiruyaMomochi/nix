{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.vlmcsd;
in
{
  options.services.vlmcsd = {
    enable = lib.mkEnableOption "the KMS Emulator in C";

    package = lib.mkPackageOption pkgs "vlmcsd" { };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/etc/vlmcsd/config.json";
      description = ''
        The absolute path to the configuration file.
      '';
    };

    dataFile = mkOption {
      type = types.path;
      default = "${cfg.package}/share/vlmcsd/vlmcsd.kmd";
      example = "/etc/vlmcsd/config.json";
      description = ''
        The absolute path to the configuration file.
      '';
    };

    listenPort = mkOption {
      type = types.port;
      default = 1688;
      description = ''
        Port number of vlmcsd.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to open the firewall for the specified vlmcsd port.
      '';
    };
  };

  # https://github.com/Wind4/vlmcsd-debian/blob/master/vlmcsd.service
  config = mkMerge [
    (mkIf cfg.enable {
      systemd.services.vlmcsd = {
        description = "The KMS Emulator in C";

        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        serviceConfig = {
          Type = "simple";
          DynamicUser = true;
          Restart = "on-failure";
          RestartSec = "5s";
          ExecStart = "${cfg.package}/bin/vlmcsd -P ${builtins.toString cfg.listenPort} ${lib.optionalString (cfg.configFile != null) "-i ${cfg.configFile}"} -j ${cfg.dataFile} -l syslog -D";
        };
      };
    })

    (mkIf (cfg.enable && cfg.openFirewall) {
      networking.firewall.allowedTCPPorts = [ cfg.listenPort ];
    })
  ];
}

