{ config, pkgs, lib, ... }:
{
  home.packages = [ pkgs.rclone ];
  systemd.user.services."rclone-onedrive" = {
    Unit = {
      Description = "OneDrive mount service";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      Type = "notify";
      ExecStart = "${pkgs.rclone}/bin/rclone mount onedrive: ${config.home.homeDirectory}/OneDrive --vfs-cache-mode full";
      Restart = "on-failure";
      RestartSec = 30;
    };
  };
}
