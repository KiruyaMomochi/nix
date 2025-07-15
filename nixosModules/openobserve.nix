{
  options,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.openobserve;
in
{
  options.services.openobserve = {
    enable = mkEnableOption "the OpenObserve server";
    package = mkOption {
      type = types.package;
      default = pkgs.openobserve;
      description = "The OpenObserve package to use.";
    };
    environmentFile = mkOption {
      type = types.path;
      default = config.systemd.package.openobserve.environmentFile;
      description = "Path to the environment file for OpenObserve.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.openobserve = {
      description = "The OpenObserve server";
      after = [ "syslog.target" "network-online.target" "remote-fs.target" "nss-lookup.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        LimitNOFILE = 65535;
        EnvironmentFile = cfg.environmentFile;
        ExecStart = "${cfg.package}/bin/openobserve";
        ExecStop = "${pkgs.coreutils}/bin/kill -s QUIT $MAINPID";
        Restart = "on-failure";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
