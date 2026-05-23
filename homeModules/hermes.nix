{ config
, pkgs
, lib
, ...
}:
let
  cfg = config.services.hermes-gateway;

  effectivePackage = cfg.package.override {
    inherit (cfg) extraDependencyGroups;
  };
in
{
  options.services.hermes-gateway = with lib; {
    enable = mkEnableOption "Hermes Agent Gateway service";

    package = mkOption {
      type = types.package;
      default = pkgs.kyaru.hermes-agent;
      description = "The hermes-agent package to use.";
    };

    extraDependencyGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Additional pyproject.toml optional-dependency groups to include.
        Use this for lazy-installed extras that fail in read-only Nix envs
        (e.g. "anthropic", "exa", "telegram").
      '';
    };

    hermesHome = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.hermes";
      description = "Path to HERMES_HOME directory.";
    };

    workingDirectory = mkOption {
      type = types.str;
      default = config.home.homeDirectory;
      description = "Working directory for the gateway process.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = "${cfg.hermesHome}/.env";
      description = "Path to environment file with secrets (API keys etc).";
    };

    extraPaths = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra directories to prepend to PATH in the service.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Make hermes CLI available in interactive shells, with HERMES_HOME defaulting
    # to cfg.hermesHome so the CLI and gateway service stay in sync without
    # requiring the user to set a session variable.  --set-default is used so an
    # explicit HERMES_HOME= in the environment still takes precedence.
    home.packages = [
      (effectivePackage.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          for wrapper in $out/bin/hermes $out/bin/hermes-agent $out/bin/hermes-acp; do
            wrapProgram "$wrapper" --set-default HERMES_HOME ${lib.escapeShellArg cfg.hermesHome}
          done
        '';
      }))
    ];

    systemd.user.services.hermes-gateway = {
      Unit = {
        Description = "Hermes Agent Gateway - Messaging Platform Integration";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
        StartLimitIntervalSec = 0;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${effectivePackage}/bin/hermes gateway run";
        WorkingDirectory = cfg.workingDirectory;

        Environment = [
          "PATH=${lib.concatStringsSep ":" (cfg.extraPaths ++ ["${pkgs.bash}/bin" "${effectivePackage}/bin" "/run/current-system/sw/bin"])}"
          "HERMES_HOME=${cfg.hermesHome}"
        ];

        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;

        Restart = "always";
        RestartSec = 5;
        RestartMaxDelaySec = 300;
        RestartSteps = 5;
        RestartForceExitStatus = 75;
        KillMode = "mixed";
        KillSignal = "SIGTERM";
        ExecReload = "${pkgs.util-linux}/bin/kill -USR1 $MAINPID";
        TimeoutStopSec = 210;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}
