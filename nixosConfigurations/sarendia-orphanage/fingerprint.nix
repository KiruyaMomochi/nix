{ config, lib, pkgs, ... }:

# FocalTech 2808:0752 fingerprint reader. libfprint has no driver for it; FocalTech's
# own libfprint build does, so ftfp_proxy runs that in a separate daemon and exposes
# it to fprintd as a TOD driver. Enrol with `fprintd-enroll`.
let
  cfg = config.hardware.focaltech-fingerprint;

  vendorLib = pkgs.stdenvNoCC.mkDerivation {
    name = "focaltech-libfprint-vendor";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      (pkgs.python3.withPackages (p: [ p.pyelftools ]))
    ];
    buildInputs = with pkgs; [ glib gusb pixman nss libgudev ];
    installPhase = ''
      install -Dm755 ${cfg.vendorLib} $out/lib/libfprint.so
      python3 ${./fingerprint-unversion-gusb.py} $out/lib/libfprint.so
    '';
  };

  socket = "/run/ftfp_proxy-focaltech.sock";
in
{
  options.hardware.focaltech-fingerprint.vendorLib = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "libfprint-2.so.2.0.0 from FocalTech's libfprint-2-2 1.94.4+tod1 deb.";
  };

  config = lib.mkIf (cfg.vendorLib != null) {
    services.fprintd = {
      enable = true;
      tod.enable = true;
      tod.driver = pkgs.kyaru.ftfp-proxy;
    };
    systemd.services.fprintd.environment.FTFP_PROXY_SOCKET = socket;

    # Logging in still takes the password: kwallet is unlocked with it.
    security.pam.services.login.fprintAuth = false;
    security.pam.services.sddm = lib.mkIf config.services.displayManager.sddm.enable {
      fprintAuth = false;
    };

    # Same as upstream's systemd/ units.
    systemd.sockets.ftfp-proxy = {
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = socket;
        SocketMode = "0600";
        RemoveOnStop = true;
      };
    };
    systemd.services.ftfp-proxy = {
      description = "FocalTech fingerprint vendor driver";
      requires = [ "ftfp-proxy.socket" ];
      after = [ "ftfp-proxy.socket" ];
      serviceConfig = {
        ExecStart = "${pkgs.kyaru.ftfp-proxy}/bin/ftfp_proxy_daemon --socket ${socket} --vendor-lib ${vendorLib}/lib/libfprint.so";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectControlGroups = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_NETLINK" ];
        ReadWritePaths = [ "/run" ];
        Restart = "on-failure";
        RestartSec = 1;
      };
    };
  };
}
