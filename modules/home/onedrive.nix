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
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    systemd.user.services."rclone-onedrive" = {
      Unit = {
        Description = "OneDrive mount service";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
        ConditionPathExists = "${config.xdg.configHome}/rclone/rclone.conf";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        Type = "notify";
        ExecStart = "${cfg.package}/bin/rclone mount onedrive: ${config.home.homeDirectory}/OneDrive --vfs-cache-mode full";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };
  };
}
