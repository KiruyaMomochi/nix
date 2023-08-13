{ config, pkgs, lib, ... }:
{
  home.packages = [ pkgs.rclone ];
  systemd.user.services."rclone-onedrive" = {
    Unit = {
      Description = "OneDrive mount service";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      Type = "notify";
      ExecStart = "${pkgs.rclone}/bin/rclone mount onedrive: ${config.home.homeDirectory}/OneDrive --vfs-cache-mode full";
    };
  };
}
