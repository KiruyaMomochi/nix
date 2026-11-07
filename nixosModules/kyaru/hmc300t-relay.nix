{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.kyaru.services.hmc300t-relay;

  python = pkgs.python3.withPackages (ps: with ps; [
    pycryptodome
  ]);

  relaySrc = pkgs.runCommand "hmc300t-relay-src" { } ''
    mkdir -p $out
    cp ${./hmc300t-relay}/*.py $out/
  '';

  devicesFile = pkgs.writeText "hmc300t-devices.json" (builtins.toJSON cfg.devices);

  hmc300tCli = pkgs.writeShellScriptBin "hmc300t" ''
    export HMC300T_DEVICES_FILE="''${HMC300T_DEVICES_FILE:-${devicesFile}}"
    export HMC300T_SOCKET="''${HMC300T_SOCKET:-${cfg.controlSocket}}"
    exec ${python}/bin/python ${relaySrc}/cli.py "$@"
  '';

  allAllowedIps = unique (
    cfg.allowedSources ++ mapAttrsToList (_: d: d.ip) cfg.devices
  );
in
{
  options.kyaru.services.hmc300t-relay = {
    enable = mkEnableOption "Hisense HMC300T transparent cloud relay and local control socket";

    listenHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "IPv4 address to bind the TCP relay listener on.";
    };

    listenPort = mkOption {
      type = types.port;
      default = 8088;
      description = "TCP port the AC Wi-Fi modules connect to (ns.wg.hismarttv.com).";
    };

    upstreamHost = mkOption {
      type = types.str;
      default = "220.243.139.234";
      description = ''
        Pinned upstream Hisense cloud IPv4 address. Kept as a literal IP so the
        relay does not loop back into itself when LAN DNS redirects
        ns.wg.hismarttv.com to this host.
      '';
    };

    upstreamPort = mkOption {
      type = types.port;
      default = 8088;
      description = "Upstream Hisense cloud TCP port.";
    };

    interface = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "eno1";
      description = "LAN interface for the nftables source-restricted firewall rule.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to add an nftables input-allow rule for configured devices and allowedSources.";
    };

    allowedSources = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "192.168.50.1" ];
      description = "Additional source IPv4 addresses (besides devices.*.ip) permitted to reach listenHost:listenPort.";
    };

    user = mkOption {
      type = types.str;
      default = "yozakura";
      description = "User account running the relay service.";
    };

    group = mkOption {
      type = types.str;
      default = "users";
      description = "Group owning the control socket.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/hmc300t-relay";
      description = "Directory for relay.log and per-session raw byte captures.";
    };

    controlSocket = mkOption {
      type = types.str;
      default = "/run/hmc300t-relay/control.sock";
      description = "Unix domain socket path for querying status and injecting frames.";
    };

    devices = mkOption {
      default = { };
      description = "Named HMC300T air conditioner units (e.g. bedroom, living, parents).";
      type = types.attrsOf (
        types.submodule {
          options = {
            ip = mkOption {
              type = types.str;
              description = "LAN IPv4 address of the AC Wi-Fi module.";
            };
            did = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "36-character Hisense WifiId (DID).";
            };
            description = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Human-readable room or unit label.";
            };
          };
        }
      );
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ hmc300tCli ];

    networking.firewall.extraInputRules = mkIf (cfg.openFirewall && allAllowedIps != [ ]) ''
      ${optionalString (cfg.interface != null) "iifname \"${cfg.interface}\" "}ip saddr { ${concatStringsSep ", " allAllowedIps} } ${optionalString (cfg.listenHost != "0.0.0.0") "ip daddr ${cfg.listenHost} "}tcp dport ${toString cfg.listenPort} accept comment "hmc300t-relay"
    '';

    systemd.services.hmc300t-relay = {
      description = "Hisense HMC300T transparent cloud relay and control socket";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "hmc300t-relay";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "hmc300t-relay";
        RuntimeDirectoryMode = "0750";
        UMask = "0077";
        ExecStart = concatStringsSep " " [
          "${python}/bin/python"
          "${relaySrc}/controlled_relay.py"
          "--listen-host"
          cfg.listenHost
          "--listen-port"
          (toString cfg.listenPort)
          "--upstream-host"
          cfg.upstreamHost
          "--upstream-port"
          (toString cfg.upstreamPort)
          "--log-dir"
          cfg.stateDir
          "--control-socket"
          cfg.controlSocket
          "--socket-mode"
          "0660"
          "--unlink-stale-socket"
          "--devices-file"
          "${devicesFile}"
        ];
        Restart = "on-failure";
        RestartSec = 3;
        TimeoutStopSec = 10;

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };
  };
}
