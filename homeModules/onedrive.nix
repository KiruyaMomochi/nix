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
    allowOther = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Pass --allow-other so other users (and root) can traverse the mount.
        Requires programs.fuse.userAllowOther = true on the host.
      '';
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
        ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        Type = "notify";
        ExecStartPre = [
          "-/run/wrappers/bin/fusermount -uz ${cfg.mountPath}"
          "${pkgs.coreutils}/bin/mkdir -p ${cfg.mountPath}"
        ];
        # OneDrive supports ChangeNotify, so polling keeps the dir cache fresh
        # and it can live ~forever instead of re-listing every 5 minutes.
        ExecStart = "${cfg.package}/bin/rclone mount onedrive: ${cfg.mountPath} --vfs-cache-mode full --dir-cache-time 1000h --poll-interval 1m --rc --rc-no-auth"
          + lib.optionalString cfg.allowOther " --allow-other";
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
