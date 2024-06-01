{ config
, pkgs
, lib
, ...
}:
let
  cfg = config.services.onedrive-rclone;
in
{
  options.services.onedrive-rclone = with lib; {
    enable = mkEnableOption "Enable OneDrive Rclone mount service";
    package = mkPackageOption pkgs "rclone" { };
    mountPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/OneDrive";
      description = "Path to mount";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    systemd.user.services."rclone-onedrive" = {
      Unit = {
        Description = "OneDrive mount service";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
        ConditionPathExists = [
          "${config.xdg.configHome}/rclone/rclone.conf"
          "${config.home.homeDirectory}/OneDrive"
        ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        Type = "notify";
        ExecStart = "${cfg.package}/bin/rclone mount onedrive: ${cfg.mountPath} --vfs-cache-mode full";
        ExecStop = "fusermount -u ${cfg.mountPath}"; # Dismounts
        Restart = "on-failure";
        RestartSec = "10s";
        StartLimitInterval = 600;
        StartLimitBurst = 3;
        Environment = [ "PATH=/run/wrappers/bin/:$PATH" ]; # Required environments
      };
    };
  };
}
